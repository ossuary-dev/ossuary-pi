"""Network database for persistent network memory."""

import asyncio
import aiosqlite
import logging
import json
from pathlib import Path
from typing import List, Dict, Any, Optional
from datetime import datetime
from dataclasses import dataclass, asdict


@dataclass
class NetworkRecord:
    """Network record in database."""
    ssid: str
    bssid: str
    security_type: str
    password_hash: Optional[str]
    auto_connect: bool
    priority: int
    first_connected: datetime
    last_connected: datetime
    connect_count: int
    failed_attempts: int
    notes: Optional[str]

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        data = asdict(self)
        data['first_connected'] = self.first_connected.isoformat()
        data['last_connected'] = self.last_connected.isoformat()
        return data

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'NetworkRecord':
        """Create from dictionary."""
        data['first_connected'] = datetime.fromisoformat(data['first_connected'])
        data['last_connected'] = datetime.fromisoformat(data['last_connected'])
        return cls(**data)


class NetworkDatabase:
    """Database for persistent network storage."""

    def __init__(self, db_path: str = "/var/lib/ossuary/networks.db"):
        """Initialize network database."""
        self.db_path = Path(db_path)
        self.db_dir = self.db_path.parent
        self.logger = logging.getLogger(__name__)

        # Connection pool
        self.connection: Optional[aiosqlite.Connection] = None

        # Ensure directory exists
        self._ensure_directory()

    def _ensure_directory(self) -> None:
        """Ensure database directory exists."""
        try:
            self.db_dir.mkdir(parents=True, exist_ok=True)
        except Exception as e:
            self.logger.error(f"Failed to create database directory: {e}")

    async def initialize(self) -> None:
        """Initialize database and create tables."""
        try:
            self.logger.info("Initializing network database")

            self.connection = await aiosqlite.connect(str(self.db_path))
            self.connection.row_factory = aiosqlite.Row

            await self._create_tables()
            await self._migrate_schema()

            self.logger.info("Network database initialized")

        except Exception as e:
            self.logger.error(f"Failed to initialize database: {e}")
            raise

    async def _create_tables(self) -> None:
        """Create database tables."""
        try:
            # Networks table
            await self.connection.execute("""
                CREATE TABLE IF NOT EXISTS networks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    ssid TEXT NOT NULL,
                    bssid TEXT,
                    security_type TEXT,
                    password_hash TEXT,
                    auto_connect BOOLEAN DEFAULT TRUE,
                    priority INTEGER DEFAULT 0,
                    first_connected TIMESTAMP,
                    last_connected TIMESTAMP,
                    connect_count INTEGER DEFAULT 0,
                    failed_attempts INTEGER DEFAULT 0,
                    notes TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(ssid, bssid)
                )
            """)

            # Connection history table
            await self.connection.execute("""
                CREATE TABLE IF NOT EXISTS connection_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    network_id INTEGER,
                    connected_at TIMESTAMP,
                    disconnected_at TIMESTAMP,
                    duration INTEGER,
                    signal_strength INTEGER,
                    connection_type TEXT,
                    success BOOLEAN,
                    error_message TEXT,
                    FOREIGN KEY (network_id) REFERENCES networks (id)
                )
            """)

            # Network statistics table
            await self.connection.execute("""
                CREATE TABLE IF NOT EXISTS network_stats (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    network_id INTEGER,
                    date DATE,
                    total_connections INTEGER DEFAULT 0,
                    total_duration INTEGER DEFAULT 0,
                    avg_signal_strength INTEGER,
                    failed_connections INTEGER DEFAULT 0,
                    data_transferred INTEGER DEFAULT 0,
                    FOREIGN KEY (network_id) REFERENCES networks (id),
                    UNIQUE(network_id, date)
                )
            """)

            # Create indexes
            await self.connection.execute("""
                CREATE INDEX IF NOT EXISTS idx_networks_ssid ON networks (ssid)
            """)
            await self.connection.execute("""
                CREATE INDEX IF NOT EXISTS idx_networks_priority ON networks (priority DESC)
            """)
            await self.connection.execute("""
                CREATE INDEX IF NOT EXISTS idx_connection_history_network ON connection_history (network_id)
            """)

            await self.connection.commit()

        except Exception as e:
            self.logger.error(f"Failed to create tables: {e}")
            raise

    async def _migrate_schema(self) -> None:
        """Migrate database schema if needed."""
        try:
            # Check current schema version
            try:
                cursor = await self.connection.execute("""
                    SELECT value FROM metadata WHERE key = 'schema_version'
                """)
                row = await cursor.fetchone()
                current_version = int(row[0]) if row else 0
            except Exception:
                # Create metadata table
                await self.connection.execute("""
                    CREATE TABLE IF NOT EXISTS metadata (
                        key TEXT PRIMARY KEY,
                        value TEXT
                    )
                """)
                current_version = 0

            # Apply migrations
            target_version = 1  # Current schema version

            if current_version < target_version:
                await self._apply_migrations(current_version, target_version)

        except Exception as e:
            self.logger.error(f"Failed to migrate schema: {e}")

    async def _apply_migrations(self, current_version: int, target_version: int) -> None:
        """Apply database migrations."""
        try:
            for version in range(current_version + 1, target_version + 1):
                self.logger.info(f"Applying migration to version {version}")

                if version == 1:
                    # Add any schema changes for version 1
                    pass

                # Update schema version
                await self.connection.execute("""
                    INSERT OR REPLACE INTO metadata (key, value) VALUES ('schema_version', ?)
                """, (str(version),))

            await self.connection.commit()

        except Exception as e:
            self.logger.error(f"Failed to apply migrations: {e}")
            raise

    async def add_network(self, ssid: str, bssid: str = None, security_type: str = "unknown",
                         password: str = None, auto_connect: bool = True, priority: int = 0) -> int:
        """Add a new network to the database."""
        try:
            now = datetime.now()

            # Hash password if provided
            password_hash = self._hash_password(password) if password else None

            cursor = await self.connection.execute("""
                INSERT OR REPLACE INTO networks
                (ssid, bssid, security_type, password_hash, auto_connect, priority,
                 first_connected, last_connected, connect_count, failed_attempts)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0)
            """, (ssid, bssid, security_type, password_hash, auto_connect, priority, now, now))

            await self.connection.commit()

            network_id = cursor.lastrowid
            self.logger.info(f"Added network: {ssid} (ID: {network_id})")
            return network_id

        except Exception as e:
            self.logger.error(f"Failed to add network {ssid}: {e}")
            raise

    async def get_network(self, ssid: str, bssid: str = None) -> Optional[NetworkRecord]:
        """Get network by SSID and optionally BSSID."""
        try:
            if bssid:
                cursor = await self.connection.execute("""
                    SELECT * FROM networks WHERE ssid = ? AND bssid = ?
                """, (ssid, bssid))
            else:
                cursor = await self.connection.execute("""
                    SELECT * FROM networks WHERE ssid = ? ORDER BY priority DESC LIMIT 1
                """, (ssid,))

            row = await cursor.fetchone()
            if row:
                return self._row_to_network_record(row)

            return None

        except Exception as e:
            self.logger.error(f"Failed to get network {ssid}: {e}")
            return None

    async def get_all_networks(self, auto_connect_only: bool = False) -> List[NetworkRecord]:
        """Get all networks, optionally filtered by auto_connect."""
        try:
            if auto_connect_only:
                cursor = await self.connection.execute("""
                    SELECT * FROM networks WHERE auto_connect = TRUE
                    ORDER BY priority DESC, last_connected DESC
                """)
            else:
                cursor = await self.connection.execute("""
                    SELECT * FROM networks ORDER BY priority DESC, last_connected DESC
                """)

            rows = await cursor.fetchall()
            return [self._row_to_network_record(row) for row in rows]

        except Exception as e:
            self.logger.error(f"Failed to get all networks: {e}")
            return []

    async def update_network(self, ssid: str, **updates) -> bool:
        """Update network record."""
        try:
            if not updates:
                return True

            # Build update query
            set_clauses = []
            values = []

            for key, value in updates.items():
                if key in ['ssid', 'bssid', 'security_type', 'password_hash',
                          'auto_connect', 'priority', 'notes']:
                    set_clauses.append(f"{key} = ?")
                    values.append(value)

            if not set_clauses:
                return True

            # Add updated_at
            set_clauses.append("updated_at = CURRENT_TIMESTAMP")
            values.append(ssid)

            query = f"""
                UPDATE networks SET {', '.join(set_clauses)}
                WHERE ssid = ?
            """

            cursor = await self.connection.execute(query, values)
            await self.connection.commit()

            return cursor.rowcount > 0

        except Exception as e:
            self.logger.error(f"Failed to update network {ssid}: {e}")
            return False

    async def remove_network(self, ssid: str, bssid: str = None) -> bool:
        """Remove network from database."""
        try:
            if bssid:
                cursor = await self.connection.execute("""
                    DELETE FROM networks WHERE ssid = ? AND bssid = ?
                """, (ssid, bssid))
            else:
                cursor = await self.connection.execute("""
                    DELETE FROM networks WHERE ssid = ?
                """, (ssid,))

            await self.connection.commit()

            removed = cursor.rowcount > 0
            if removed:
                self.logger.info(f"Removed network: {ssid}")

            return removed

        except Exception as e:
            self.logger.error(f"Failed to remove network {ssid}: {e}")
            return False

    async def record_connection(self, ssid: str, bssid: str = None, success: bool = True,
                               signal_strength: int = None, error_message: str = None) -> None:
        """Record a connection attempt."""
        try:
            # Get network ID
            network = await self.get_network(ssid, bssid)
            if not network:
                # Add network if it doesn't exist
                network_id = await self.add_network(ssid, bssid)
            else:
                network_id = (await self.connection.execute("""
                    SELECT id FROM networks WHERE ssid = ? AND (bssid = ? OR bssid IS NULL)
                    ORDER BY priority DESC LIMIT 1
                """, (ssid, bssid))).fetchone()[0]

            now = datetime.now()

            # Record connection history
            await self.connection.execute("""
                INSERT INTO connection_history
                (network_id, connected_at, success, signal_strength, error_message)
                VALUES (?, ?, ?, ?, ?)
            """, (network_id, now, success, signal_strength, error_message))

            # Update network statistics
            if success:
                await self.connection.execute("""
                    UPDATE networks SET
                        connect_count = connect_count + 1,
                        last_connected = ?,
                        failed_attempts = 0
                    WHERE id = ?
                """, (now, network_id))
            else:
                await self.connection.execute("""
                    UPDATE networks SET failed_attempts = failed_attempts + 1 WHERE id = ?
                """, (network_id,))

            await self.connection.commit()

        except Exception as e:
            self.logger.error(f"Failed to record connection for {ssid}: {e}")

    async def get_connection_history(self, ssid: str = None, limit: int = 100) -> List[Dict[str, Any]]:
        """Get connection history."""
        try:
            if ssid:
                cursor = await self.connection.execute("""
                    SELECT ch.*, n.ssid FROM connection_history ch
                    JOIN networks n ON ch.network_id = n.id
                    WHERE n.ssid = ?
                    ORDER BY ch.connected_at DESC LIMIT ?
                """, (ssid, limit))
            else:
                cursor = await self.connection.execute("""
                    SELECT ch.*, n.ssid FROM connection_history ch
                    JOIN networks n ON ch.network_id = n.id
                    ORDER BY ch.connected_at DESC LIMIT ?
                """, (limit,))

            rows = await cursor.fetchall()
            return [dict(row) for row in rows]

        except Exception as e:
            self.logger.error(f"Failed to get connection history: {e}")
            return []

    async def get_network_statistics(self, days: int = 30) -> Dict[str, Any]:
        """Get network usage statistics."""
        try:
            # Total networks
            cursor = await self.connection.execute("SELECT COUNT(*) FROM networks")
            total_networks = (await cursor.fetchone())[0]

            # Recent connections
            cursor = await self.connection.execute("""
                SELECT COUNT(*) FROM connection_history
                WHERE connected_at > datetime('now', '-{} days')
            """.format(days))
            recent_connections = (await cursor.fetchone())[0]

            # Success rate
            cursor = await self.connection.execute("""
                SELECT
                    COUNT(*) as total,
                    SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) as successful
                FROM connection_history
                WHERE connected_at > datetime('now', '-{} days')
            """.format(days))
            row = await cursor.fetchone()
            success_rate = (row[1] / row[0] * 100) if row[0] > 0 else 0

            # Most used networks
            cursor = await self.connection.execute("""
                SELECT n.ssid, COUNT(*) as connections
                FROM connection_history ch
                JOIN networks n ON ch.network_id = n.id
                WHERE ch.connected_at > datetime('now', '-{} days')
                GROUP BY n.ssid
                ORDER BY connections DESC
                LIMIT 5
            """.format(days))
            most_used = [dict(row) for row in await cursor.fetchall()]

            return {
                "total_networks": total_networks,
                "recent_connections": recent_connections,
                "success_rate": success_rate,
                "most_used_networks": most_used,
                "period_days": days
            }

        except Exception as e:
            self.logger.error(f"Failed to get network statistics: {e}")
            return {}

    def _hash_password(self, password: str) -> str:
        """Hash password for storage."""
        import hashlib
        return hashlib.sha256(password.encode()).hexdigest()

    def _row_to_network_record(self, row) -> NetworkRecord:
        """Convert database row to NetworkRecord."""
        return NetworkRecord(
            ssid=row['ssid'],
            bssid=row['bssid'],
            security_type=row['security_type'],
            password_hash=row['password_hash'],
            auto_connect=bool(row['auto_connect']),
            priority=row['priority'],
            first_connected=datetime.fromisoformat(row['first_connected']),
            last_connected=datetime.fromisoformat(row['last_connected']),
            connect_count=row['connect_count'],
            failed_attempts=row['failed_attempts'],
            notes=row['notes']
        )

    async def export_networks(self, export_path: str) -> bool:
        """Export networks to JSON file."""
        try:
            networks = await self.get_all_networks()
            export_data = {
                "exported_at": datetime.now().isoformat(),
                "networks": [network.to_dict() for network in networks]
            }

            with open(export_path, 'w') as f:
                json.dump(export_data, f, indent=2)

            self.logger.info(f"Networks exported to {export_path}")
            return True

        except Exception as e:
            self.logger.error(f"Failed to export networks: {e}")
            return False

    async def import_networks(self, import_path: str) -> bool:
        """Import networks from JSON file."""
        try:
            with open(import_path, 'r') as f:
                import_data = json.load(f)

            networks = import_data.get('networks', [])
            imported_count = 0

            for network_data in networks:
                try:
                    network = NetworkRecord.from_dict(network_data)
                    await self.add_network(
                        network.ssid,
                        network.bssid,
                        network.security_type,
                        None,  # Don't import passwords
                        network.auto_connect,
                        network.priority
                    )
                    imported_count += 1
                except Exception as e:
                    self.logger.warning(f"Failed to import network {network_data.get('ssid')}: {e}")

            self.logger.info(f"Imported {imported_count} networks from {import_path}")
            return True

        except Exception as e:
            self.logger.error(f"Failed to import networks: {e}")
            return False

    async def cleanup_old_history(self, days: int = 90) -> int:
        """Clean up old connection history."""
        try:
            cursor = await self.connection.execute("""
                DELETE FROM connection_history
                WHERE connected_at < datetime('now', '-{} days')
            """.format(days))

            await self.connection.commit()

            removed_count = cursor.rowcount
            if removed_count > 0:
                self.logger.info(f"Cleaned up {removed_count} old connection records")

            return removed_count

        except Exception as e:
            self.logger.error(f"Failed to cleanup old history: {e}")
            return 0

    async def close(self) -> None:
        """Close database connection."""
        try:
            if self.connection:
                await self.connection.close()
                self.connection = None
                self.logger.info("Network database closed")

        except Exception as e:
            self.logger.error(f"Failed to close database: {e}")