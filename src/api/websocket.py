"""WebSocket manager for real-time communication."""

import asyncio
import json
import logging
from typing import List, Dict, Any, Set
from datetime import datetime

from fastapi import WebSocket, WebSocketDisconnect


class WebSocketManager:
    """Manages WebSocket connections and real-time communication."""

    def __init__(self):
        """Initialize WebSocket manager."""
        self.active_connections: List[WebSocket] = []
        self.connection_info: Dict[WebSocket, Dict[str, Any]] = {}
        self.subscribers: Dict[str, Set[WebSocket]] = {}
        self.logger = logging.getLogger(__name__)

    async def connect(self, websocket: WebSocket) -> None:
        """Accept a WebSocket connection."""
        try:
            await websocket.accept()
            self.active_connections.append(websocket)

            # Store connection info
            self.connection_info[websocket] = {
                "connected_at": datetime.now(),
                "subscriptions": set(),
                "client_info": None
            }

            self.logger.info(f"WebSocket connected. Total connections: {len(self.active_connections)}")

            # Send welcome message
            await self.send_personal_message(websocket, {
                "type": "welcome",
                "message": "Connected to Ossuary API",
                "timestamp": datetime.now()
            })

        except Exception as e:
            self.logger.error(f"Failed to connect WebSocket: {e}")

    def disconnect(self, websocket: WebSocket) -> None:
        """Remove WebSocket connection."""
        try:
            if websocket in self.active_connections:
                self.active_connections.remove(websocket)

            # Clean up subscriptions
            if websocket in self.connection_info:
                subscriptions = self.connection_info[websocket].get("subscriptions", set())
                for topic in subscriptions:
                    if topic in self.subscribers and websocket in self.subscribers[topic]:
                        self.subscribers[topic].remove(websocket)

                del self.connection_info[websocket]

            self.logger.info(f"WebSocket disconnected. Total connections: {len(self.active_connections)}")

        except Exception as e:
            self.logger.error(f"Failed to disconnect WebSocket: {e}")

    async def send_personal_message(self, websocket: WebSocket, message: Dict[str, Any]) -> None:
        """Send message to specific WebSocket connection."""
        try:
            # Ensure timestamp is serializable
            if "timestamp" in message and isinstance(message["timestamp"], datetime):
                message["timestamp"] = message["timestamp"].isoformat()

            await websocket.send_text(json.dumps(message))

        except WebSocketDisconnect:
            self.disconnect(websocket)
        except Exception as e:
            self.logger.error(f"Failed to send personal message: {e}")

    async def broadcast(self, message: Dict[str, Any]) -> None:
        """Broadcast message to all connected clients."""
        try:
            # Ensure timestamp is serializable
            if "timestamp" in message and isinstance(message["timestamp"], datetime):
                message["timestamp"] = message["timestamp"].isoformat()

            message_text = json.dumps(message)

            # Send to all active connections
            disconnected = []
            for websocket in self.active_connections:
                try:
                    await websocket.send_text(message_text)
                except WebSocketDisconnect:
                    disconnected.append(websocket)
                except Exception as e:
                    self.logger.error(f"Failed to send broadcast message: {e}")
                    disconnected.append(websocket)

            # Clean up disconnected clients
            for websocket in disconnected:
                self.disconnect(websocket)

        except Exception as e:
            self.logger.error(f"Failed to broadcast message: {e}")

    async def broadcast_to_topic(self, topic: str, message: Dict[str, Any]) -> None:
        """Broadcast message to subscribers of a specific topic."""
        try:
            if topic not in self.subscribers:
                return

            # Ensure timestamp is serializable
            if "timestamp" in message and isinstance(message["timestamp"], datetime):
                message["timestamp"] = message["timestamp"].isoformat()

            message_text = json.dumps(message)

            # Send to topic subscribers
            disconnected = []
            for websocket in self.subscribers[topic]:
                try:
                    await websocket.send_text(message_text)
                except WebSocketDisconnect:
                    disconnected.append(websocket)
                except Exception as e:
                    self.logger.error(f"Failed to send topic message: {e}")
                    disconnected.append(websocket)

            # Clean up disconnected clients
            for websocket in disconnected:
                self.disconnect(websocket)

        except Exception as e:
            self.logger.error(f"Failed to broadcast to topic {topic}: {e}")

    async def handle_message(self, websocket: WebSocket, message: str) -> None:
        """Handle incoming WebSocket message."""
        try:
            data = json.loads(message)
            message_type = data.get("type")

            if message_type == "subscribe":
                await self._handle_subscribe(websocket, data)
            elif message_type == "unsubscribe":
                await self._handle_unsubscribe(websocket, data)
            elif message_type == "ping":
                await self._handle_ping(websocket, data)
            elif message_type == "client_info":
                await self._handle_client_info(websocket, data)
            else:
                await self.send_personal_message(websocket, {
                    "type": "error",
                    "message": f"Unknown message type: {message_type}",
                    "timestamp": datetime.now()
                })

        except json.JSONDecodeError:
            await self.send_personal_message(websocket, {
                "type": "error",
                "message": "Invalid JSON message",
                "timestamp": datetime.now()
            })
        except Exception as e:
            self.logger.error(f"Failed to handle message: {e}")
            await self.send_personal_message(websocket, {
                "type": "error",
                "message": "Failed to process message",
                "timestamp": datetime.now()
            })

    async def _handle_subscribe(self, websocket: WebSocket, data: Dict[str, Any]) -> None:
        """Handle topic subscription."""
        try:
            topic = data.get("topic")
            if not topic:
                await self.send_personal_message(websocket, {
                    "type": "error",
                    "message": "Topic required for subscription",
                    "timestamp": datetime.now()
                })
                return

            # Add to subscribers
            if topic not in self.subscribers:
                self.subscribers[topic] = set()

            self.subscribers[topic].add(websocket)

            # Update connection info
            if websocket in self.connection_info:
                self.connection_info[websocket]["subscriptions"].add(topic)

            await self.send_personal_message(websocket, {
                "type": "subscribed",
                "topic": topic,
                "message": f"Subscribed to {topic}",
                "timestamp": datetime.now()
            })

            self.logger.debug(f"WebSocket subscribed to topic: {topic}")

        except Exception as e:
            self.logger.error(f"Failed to handle subscribe: {e}")

    async def _handle_unsubscribe(self, websocket: WebSocket, data: Dict[str, Any]) -> None:
        """Handle topic unsubscription."""
        try:
            topic = data.get("topic")
            if not topic:
                await self.send_personal_message(websocket, {
                    "type": "error",
                    "message": "Topic required for unsubscription",
                    "timestamp": datetime.now()
                })
                return

            # Remove from subscribers
            if topic in self.subscribers and websocket in self.subscribers[topic]:
                self.subscribers[topic].remove(websocket)

                # Clean up empty topic
                if not self.subscribers[topic]:
                    del self.subscribers[topic]

            # Update connection info
            if websocket in self.connection_info:
                self.connection_info[websocket]["subscriptions"].discard(topic)

            await self.send_personal_message(websocket, {
                "type": "unsubscribed",
                "topic": topic,
                "message": f"Unsubscribed from {topic}",
                "timestamp": datetime.now()
            })

            self.logger.debug(f"WebSocket unsubscribed from topic: {topic}")

        except Exception as e:
            self.logger.error(f"Failed to handle unsubscribe: {e}")

    async def _handle_ping(self, websocket: WebSocket, data: Dict[str, Any]) -> None:
        """Handle ping message."""
        try:
            await self.send_personal_message(websocket, {
                "type": "pong",
                "timestamp": datetime.now()
            })

        except Exception as e:
            self.logger.error(f"Failed to handle ping: {e}")

    async def _handle_client_info(self, websocket: WebSocket, data: Dict[str, Any]) -> None:
        """Handle client information update."""
        try:
            client_info = data.get("info", {})

            if websocket in self.connection_info:
                self.connection_info[websocket]["client_info"] = client_info

            await self.send_personal_message(websocket, {
                "type": "client_info_updated",
                "message": "Client information updated",
                "timestamp": datetime.now()
            })

            self.logger.debug(f"Updated client info for WebSocket: {client_info}")

        except Exception as e:
            self.logger.error(f"Failed to handle client info: {e}")

    def get_connection_stats(self) -> Dict[str, Any]:
        """Get WebSocket connection statistics."""
        try:
            total_connections = len(self.active_connections)
            topics = list(self.subscribers.keys())
            topic_stats = {
                topic: len(subscribers) for topic, subscribers in self.subscribers.items()
            }

            # Connection details
            connections = []
            for websocket, info in self.connection_info.items():
                connections.append({
                    "connected_at": info["connected_at"].isoformat(),
                    "subscriptions": list(info["subscriptions"]),
                    "client_info": info.get("client_info")
                })

            return {
                "total_connections": total_connections,
                "active_topics": topics,
                "topic_subscribers": topic_stats,
                "connections": connections,
                "timestamp": datetime.now().isoformat()
            }

        except Exception as e:
            self.logger.error(f"Failed to get connection stats: {e}")
            return {"error": str(e)}

    async def send_system_notification(self, level: str, message: str, details: Dict[str, Any] = None) -> None:
        """Send system notification to all connected clients."""
        try:
            notification = {
                "type": "system_notification",
                "level": level,  # info, warning, error, success
                "message": message,
                "details": details or {},
                "timestamp": datetime.now()
            }

            await self.broadcast(notification)

        except Exception as e:
            self.logger.error(f"Failed to send system notification: {e}")

    async def send_service_status_update(self, service: str, status: str, details: Dict[str, Any] = None) -> None:
        """Send service status update."""
        try:
            update = {
                "type": "service_status_update",
                "service": service,
                "status": status,
                "details": details or {},
                "timestamp": datetime.now()
            }

            await self.broadcast_to_topic("service_status", update)

        except Exception as e:
            self.logger.error(f"Failed to send service status update: {e}")

    async def cleanup_inactive_connections(self) -> None:
        """Clean up inactive WebSocket connections."""
        try:
            inactive = []
            current_time = datetime.now()

            for websocket, info in self.connection_info.items():
                # Check if connection is older than 1 hour without activity
                if (current_time - info["connected_at"]).seconds > 3600:
                    try:
                        # Try to send a ping to check if connection is alive
                        await websocket.send_text(json.dumps({
                            "type": "ping",
                            "timestamp": current_time.isoformat()
                        }))
                    except Exception:
                        inactive.append(websocket)

            # Clean up inactive connections
            for websocket in inactive:
                self.disconnect(websocket)

            if inactive:
                self.logger.info(f"Cleaned up {len(inactive)} inactive WebSocket connections")

        except Exception as e:
            self.logger.error(f"Failed to cleanup inactive connections: {e}")

    async def shutdown(self) -> None:
        """Shutdown WebSocket manager."""
        try:
            self.logger.info("Shutting down WebSocket manager")

            # Send shutdown notification
            await self.broadcast({
                "type": "server_shutdown",
                "message": "Server is shutting down",
                "timestamp": datetime.now()
            })

            # Close all connections
            for websocket in self.active_connections[:]:
                try:
                    await websocket.close()
                except Exception:
                    pass

            self.active_connections.clear()
            self.connection_info.clear()
            self.subscribers.clear()

        except Exception as e:
            self.logger.error(f"Failed to shutdown WebSocket manager: {e}")