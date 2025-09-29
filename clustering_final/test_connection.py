#!/usr/bin/env python3
"""
Test Production Database Connection
Quick script to test connection to PostGIS database
"""

import psycopg2
import getpass
import sys

def test_connection():
    """Test connection to production database"""

    # Database configuration
    host = '13.221.230.78'
    port = 5432
    database = 'lidar_clustering'
    user = 'lidar_user'

    # Get password securely
    password = getpass.getpass(f"Enter password for {user}@{host}: ")

    try:
        # Attempt connection
        conn = psycopg2.connect(
            host=host,
            port=port,
            database=database,
            user=user,
            password=password
        )

        cursor = conn.cursor()

        # Test basic queries
        print("✅ Connected successfully!")

        # Check PostgreSQL version
        cursor.execute("SELECT version();")
        pg_version = cursor.fetchone()[0]
        print(f"✅ PostgreSQL: {pg_version.split(',')[0]}")

        # Check PostGIS version
        cursor.execute("SELECT PostGIS_Version();")
        postgis_version = cursor.fetchone()[0]
        print(f"✅ PostGIS: {postgis_version}")

        # Check if tables exist
        cursor.execute("""
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public'
        ORDER BY table_name;
        """)

        tables = cursor.fetchall()
        if tables:
            print(f"✅ Existing tables: {', '.join([t[0] for t in tables])}")
        else:
            print("ℹ️  No existing tables found (fresh database)")

        # Check permissions
        cursor.execute("""
        SELECT has_database_privilege(current_user, current_database(), 'CREATE') as can_create,
               has_database_privilege(current_user, current_database(), 'CONNECT') as can_connect;
        """)

        perms = cursor.fetchone()
        print(f"✅ Permissions - CREATE: {perms[0]}, CONNECT: {perms[1]}")

        conn.close()
        print("\n🚀 Database is ready for migration!")
        return True

    except psycopg2.OperationalError as e:
        print(f"❌ Connection failed: {e}")
        return False
    except Exception as e:
        print(f"❌ Error: {e}")
        return False

if __name__ == "__main__":
    print("Testing production database connection...")
    print("Host: 13.221.230.78:5432")
    print("Database: lidar_clustering")
    print("User: lidar_user")
    print("-" * 50)

    success = test_connection()
    sys.exit(0 if success else 1)