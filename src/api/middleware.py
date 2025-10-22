"""Middleware components for API gateway."""

import time
import logging
from typing import Dict, Optional
from collections import defaultdict, deque

from fastapi import Request, Response, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from starlette.middleware.base import BaseHTTPMiddleware


class AuthMiddleware(BaseHTTPMiddleware):
    """Authentication middleware for API access."""

    def __init__(self, app, auth_token: str):
        """Initialize auth middleware."""
        super().__init__(app)
        self.auth_token = auth_token
        self.security = HTTPBearer()
        self.logger = logging.getLogger(__name__)

        # Paths that don't require authentication
        self.public_paths = {
            "/health",
            "/docs",
            "/redoc",
            "/openapi.json",
            "/ws",  # WebSocket authentication handled separately
        }

    async def dispatch(self, request: Request, call_next):
        """Process authentication for requests."""
        try:
            # Skip authentication for public paths
            if request.url.path in self.public_paths:
                return await call_next(request)

            # Skip authentication for WebSocket paths
            if request.url.path.startswith("/ws"):
                return await call_next(request)

            # Skip authentication for static files
            if request.url.path.startswith("/assets/"):
                return await call_next(request)

            # Check for authorization header
            auth_header = request.headers.get("Authorization")
            if not auth_header:
                return Response(
                    content='{"error": "Authorization header required"}',
                    status_code=401,
                    media_type="application/json"
                )

            # Validate token format
            if not auth_header.startswith("Bearer "):
                return Response(
                    content='{"error": "Invalid authorization format"}',
                    status_code=401,
                    media_type="application/json"
                )

            # Extract and validate token
            token = auth_header[7:]  # Remove "Bearer " prefix
            if not self._validate_token(token):
                return Response(
                    content='{"error": "Invalid or expired token"}',
                    status_code=401,
                    media_type="application/json"
                )

            # Token is valid, proceed with request
            return await call_next(request)

        except Exception as e:
            self.logger.error(f"Authentication error: {e}")
            return Response(
                content='{"error": "Authentication failed"}',
                status_code=500,
                media_type="application/json"
            )

    def _validate_token(self, token: str) -> bool:
        """Validate authentication token."""
        try:
            # Simple token validation - in production, use JWT or similar
            return token == self.auth_token

        except Exception as e:
            self.logger.error(f"Token validation error: {e}")
            return False


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Rate limiting middleware to prevent abuse."""

    def __init__(self, app, requests_per_minute: int = 60):
        """Initialize rate limit middleware."""
        super().__init__(app)
        self.requests_per_minute = requests_per_minute
        self.window_size = 60  # 1 minute window
        self.logger = logging.getLogger(__name__)

        # Store request timestamps per client IP
        self.client_requests: Dict[str, deque] = defaultdict(deque)

        # Paths exempt from rate limiting
        self.exempt_paths = {
            "/health",
            "/ws",
        }

    async def dispatch(self, request: Request, call_next):
        """Process rate limiting for requests."""
        try:
            # Skip rate limiting for exempt paths
            if request.url.path in self.exempt_paths:
                return await call_next(request)

            # Get client IP
            client_ip = self._get_client_ip(request)

            # Check rate limit
            if not self._check_rate_limit(client_ip):
                return Response(
                    content='{"error": "Rate limit exceeded"}',
                    status_code=429,
                    media_type="application/json",
                    headers={
                        "Retry-After": "60",
                        "X-RateLimit-Limit": str(self.requests_per_minute),
                        "X-RateLimit-Remaining": "0",
                        "X-RateLimit-Reset": str(int(time.time()) + 60)
                    }
                )

            # Record this request
            self._record_request(client_ip)

            # Process request
            response = await call_next(request)

            # Add rate limit headers to response
            remaining = self._get_remaining_requests(client_ip)
            response.headers["X-RateLimit-Limit"] = str(self.requests_per_minute)
            response.headers["X-RateLimit-Remaining"] = str(remaining)
            response.headers["X-RateLimit-Reset"] = str(int(time.time()) + 60)

            return response

        except Exception as e:
            self.logger.error(f"Rate limiting error: {e}")
            return await call_next(request)

    def _get_client_ip(self, request: Request) -> str:
        """Get client IP address from request."""
        # Check for forwarded headers (proxy/load balancer)
        forwarded_for = request.headers.get("X-Forwarded-For")
        if forwarded_for:
            return forwarded_for.split(",")[0].strip()

        real_ip = request.headers.get("X-Real-IP")
        if real_ip:
            return real_ip

        # Fallback to direct connection IP
        if hasattr(request, "client") and request.client:
            return request.client.host

        return "unknown"

    def _check_rate_limit(self, client_ip: str) -> bool:
        """Check if client has exceeded rate limit."""
        try:
            current_time = time.time()
            client_requests = self.client_requests[client_ip]

            # Remove old requests outside the window
            while client_requests and client_requests[0] <= current_time - self.window_size:
                client_requests.popleft()

            # Check if within limit
            return len(client_requests) < self.requests_per_minute

        except Exception as e:
            self.logger.error(f"Rate limit check error: {e}")
            return True  # Allow request on error

    def _record_request(self, client_ip: str) -> None:
        """Record a request timestamp for the client."""
        try:
            current_time = time.time()
            self.client_requests[client_ip].append(current_time)

        except Exception as e:
            self.logger.error(f"Request recording error: {e}")

    def _get_remaining_requests(self, client_ip: str) -> int:
        """Get remaining requests for client in current window."""
        try:
            current_requests = len(self.client_requests[client_ip])
            return max(0, self.requests_per_minute - current_requests)

        except Exception as e:
            self.logger.error(f"Remaining requests calculation error: {e}")
            return self.requests_per_minute

    def cleanup_old_entries(self) -> None:
        """Clean up old request entries to prevent memory leaks."""
        try:
            current_time = time.time()
            cleanup_threshold = current_time - (self.window_size * 2)

            # Clean up old entries
            clients_to_remove = []
            for client_ip, requests in self.client_requests.items():
                # Remove old requests
                while requests and requests[0] <= cleanup_threshold:
                    requests.popleft()

                # Mark empty clients for removal
                if not requests:
                    clients_to_remove.append(client_ip)

            # Remove empty clients
            for client_ip in clients_to_remove:
                del self.client_requests[client_ip]

            if clients_to_remove:
                self.logger.debug(f"Cleaned up {len(clients_to_remove)} inactive rate limit entries")

        except Exception as e:
            self.logger.error(f"Rate limit cleanup error: {e}")

    def get_stats(self) -> Dict[str, int]:
        """Get rate limiting statistics."""
        try:
            return {
                "active_clients": len(self.client_requests),
                "total_tracked_requests": sum(len(requests) for requests in self.client_requests.values()),
                "requests_per_minute_limit": self.requests_per_minute
            }

        except Exception as e:
            self.logger.error(f"Rate limit stats error: {e}")
            return {}


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Middleware to add security headers to responses."""

    def __init__(self, app):
        """Initialize security headers middleware."""
        super().__init__(app)
        self.logger = logging.getLogger(__name__)

    async def dispatch(self, request: Request, call_next):
        """Add security headers to responses."""
        try:
            response = await call_next(request)

            # Add security headers
            security_headers = {
                "X-Content-Type-Options": "nosniff",
                "X-Frame-Options": "DENY",
                "X-XSS-Protection": "1; mode=block",
                "Referrer-Policy": "strict-origin-when-cross-origin",
                "Content-Security-Policy": "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';",
            }

            for header, value in security_headers.items():
                response.headers[header] = value

            return response

        except Exception as e:
            self.logger.error(f"Security headers error: {e}")
            return await call_next(request)


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """Middleware to log API requests."""

    def __init__(self, app, log_level: str = "INFO"):
        """Initialize request logging middleware."""
        super().__init__(app)
        self.logger = logging.getLogger(__name__)
        self.log_level = getattr(logging, log_level.upper(), logging.INFO)

    async def dispatch(self, request: Request, call_next):
        """Log API requests and responses."""
        try:
            start_time = time.time()

            # Log request
            if self.logger.isEnabledFor(self.log_level):
                self.logger.log(
                    self.log_level,
                    f"Request: {request.method} {request.url.path} from {request.client.host if request.client else 'unknown'}"
                )

            # Process request
            response = await call_next(request)

            # Log response
            duration = time.time() - start_time
            if self.logger.isEnabledFor(self.log_level):
                self.logger.log(
                    self.log_level,
                    f"Response: {response.status_code} {request.method} {request.url.path} ({duration:.3f}s)"
                )

            return response

        except Exception as e:
            self.logger.error(f"Request logging error: {e}")
            return await call_next(request)