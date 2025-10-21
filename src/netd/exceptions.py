"""Network management exceptions."""


class NetworkError(Exception):
    """Base class for network-related errors."""
    pass


class ConnectionError(NetworkError):
    """Raised when connection operations fail."""
    pass


class AccessPointError(NetworkError):
    """Raised when access point operations fail."""
    pass


class ScanError(NetworkError):
    """Raised when network scanning fails."""
    pass


class ConfigurationError(NetworkError):
    """Raised when network configuration is invalid."""
    pass


class NetworkManagerError(NetworkError):
    """Raised when NetworkManager operations fail."""

    def __init__(self, message: str, nm_error: Exception = None):
        super().__init__(message)
        self.nm_error = nm_error


class TimeoutError(NetworkError):
    """Raised when network operations timeout."""
    pass


class InterfaceError(NetworkError):
    """Raised when network interface operations fail."""
    pass