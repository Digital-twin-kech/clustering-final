#!/usr/bin/env python3
"""
Production Data Migration Script for Berkan LiDAR Dataset
Migrates data_new_2 (Berkan dataset) to production PostGIS database
APPENDS data without removing existing records
"""

import os
import json
import psycopg2
from psycopg2.extras import execute_values
import logging
from pathlib import Path
import sys

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Production database configuration
DB_CONFIG = {
    'host': '13.221.230.78',
    'port': 5432,
    'database': 'lidar_clustering',
    'user': 'lidar_user',
    'password': os.getenv('DB_PASSWORD', 'lidar_pass')  # Use environment variable or default
}

# Data paths - pointing to Berkan dataset
DATA_DIR = Path('/home/prodair/Desktop/MORIUS5090/clustering/clustering_final/server/data_new_2')

class BerkanDataMigrator:
    def __init__(self):
        self.conn = None
        self.cursor = None
        self.dataset_name = "berkan"

    def connect(self):
        """Connect to production PostGIS database"""
        try:
            self.conn = psycopg2.connect(**DB_CONFIG)
            self.cursor = self.conn.cursor()
            logger.info(f"✅ Connected to production database at {DB_CONFIG['host']}")

            # Test PostGIS extension
            self.cursor.execute("SELECT PostGIS_Version();")
            postgis_version = self.cursor.fetchone()[0]
            logger.info(f"📊 PostGIS version: {postgis_version}")

        except Exception as e:
            logger.error(f"❌ Failed to connect to database: {e}")
            raise

    def create_schema(self):
        """Create database schema with proper tables and spatial indexes (if not exists)"""
        logger.info("🔧 Checking/creating database schema...")

        # Create tables (without dropping existing data)
        create_tables_sql = """
        -- Create Masts table (Point features) if not exists
        CREATE TABLE IF NOT EXISTS masts (
            id SERIAL PRIMARY KEY,
            chunk_id INTEGER,
            cluster_id INTEGER,
            num_points INTEGER,
            class_name VARCHAR(50),
            dataset_source VARCHAR(50),
            geometry GEOMETRY(POINT, 32629),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        -- Create Trees table (Point features) if not exists
        CREATE TABLE IF NOT EXISTS trees (
            id SERIAL PRIMARY KEY,
            chunk_id INTEGER,
            cluster_id INTEGER,
            num_points INTEGER,
            class_name VARCHAR(50),
            dataset_source VARCHAR(50),
            geometry GEOMETRY(POINT, 32629),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        -- Create Buildings table (Polygon features) if not exists
        CREATE TABLE IF NOT EXISTS buildings (
            id SERIAL PRIMARY KEY,
            chunk_id INTEGER,
            cluster_id INTEGER,
            area DOUBLE PRECISION,
            perimeter DOUBLE PRECISION,
            class_name VARCHAR(50),
            dataset_source VARCHAR(50),
            geometry GEOMETRY(POLYGON, 32629),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        -- Create Other Vegetation table (Polygon features) if not exists
        CREATE TABLE IF NOT EXISTS other_vegetation (
            id SERIAL PRIMARY KEY,
            chunk_id INTEGER,
            cluster_id INTEGER,
            area DOUBLE PRECISION,
            perimeter DOUBLE PRECISION,
            class_name VARCHAR(50),
            dataset_source VARCHAR(50),
            geometry GEOMETRY(POLYGON, 32629),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        -- Create Wires table (LineString features) if not exists
        CREATE TABLE IF NOT EXISTS wires (
            id SERIAL PRIMARY KEY,
            chunk_id INTEGER,
            cluster_id INTEGER,
            length DOUBLE PRECISION,
            class_name VARCHAR(50),
            dataset_source VARCHAR(50),
            geometry GEOMETRY(LINESTRING, 32629),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        """

        self.cursor.execute(create_tables_sql)

        # Add dataset_source column if it doesn't exist (for existing tables)
        add_column_sql = """
        DO $$
        BEGIN
            ALTER TABLE masts ADD COLUMN IF NOT EXISTS dataset_source VARCHAR(50);
            ALTER TABLE trees ADD COLUMN IF NOT EXISTS dataset_source VARCHAR(50);
            ALTER TABLE buildings ADD COLUMN IF NOT EXISTS dataset_source VARCHAR(50);
            ALTER TABLE other_vegetation ADD COLUMN IF NOT EXISTS dataset_source VARCHAR(50);
            ALTER TABLE wires ADD COLUMN IF NOT EXISTS dataset_source VARCHAR(50);
        END $$;
        """
        self.cursor.execute(add_column_sql)

        # Create spatial indexes if not exists
        indexes_sql = """
        CREATE INDEX IF NOT EXISTS idx_masts_geom ON masts USING GIST (geometry);
        CREATE INDEX IF NOT EXISTS idx_trees_geom ON trees USING GIST (geometry);
        CREATE INDEX IF NOT EXISTS idx_buildings_geom ON buildings USING GIST (geometry);
        CREATE INDEX IF NOT EXISTS idx_vegetation_geom ON other_vegetation USING GIST (geometry);
        CREATE INDEX IF NOT EXISTS idx_wires_geom ON wires USING GIST (geometry);

        CREATE INDEX IF NOT EXISTS idx_masts_chunk ON masts (chunk_id);
        CREATE INDEX IF NOT EXISTS idx_trees_chunk ON trees (chunk_id);
        CREATE INDEX IF NOT EXISTS idx_buildings_chunk ON buildings (chunk_id);
        CREATE INDEX IF NOT EXISTS idx_vegetation_chunk ON other_vegetation (chunk_id);
        CREATE INDEX IF NOT EXISTS idx_wires_chunk ON wires (chunk_id);

        CREATE INDEX IF NOT EXISTS idx_masts_dataset ON masts (dataset_source);
        CREATE INDEX IF NOT EXISTS idx_trees_dataset ON trees (dataset_source);
        CREATE INDEX IF NOT EXISTS idx_buildings_dataset ON buildings (dataset_source);
        CREATE INDEX IF NOT EXISTS idx_vegetation_dataset ON other_vegetation (dataset_source);
        CREATE INDEX IF NOT EXISTS idx_wires_dataset ON wires (dataset_source);
        """

        self.cursor.execute(indexes_sql)
        self.conn.commit()
        logger.info("✅ Database schema verified/created successfully")

    def get_existing_counts(self):
        """Get existing record counts before migration"""
        logger.info("📊 Checking existing data counts...")

        counts = {}
        tables = ['masts', 'trees', 'buildings', 'other_vegetation', 'wires']

        for table in tables:
            self.cursor.execute(f"SELECT COUNT(*) FROM {table}")
            counts[table] = self.cursor.fetchone()[0]
            logger.info(f"   {table}: {counts[table]:,} existing records")

        return counts

    def import_centroid_data(self, table_name):
        """Import centroid data (masts, trees) from JSON files"""
        logger.info(f"📥 Importing {table_name} centroid data from Berkan dataset...")

        if table_name == 'masts':
            pattern = '*Masts*'
        elif table_name == 'trees':
            pattern = '*Trees*'
        else:
            pattern = f'*{table_name}*'

        centroid_files = list((DATA_DIR / 'centroids').glob(pattern))

        if not centroid_files:
            logger.warning(f"⚠️  No {table_name} files found")
            return 0

        total_imported = 0

        for file_path in centroid_files:
            logger.info(f"   Processing {file_path.name}")

            try:
                with open(file_path, 'r') as f:
                    data = json.load(f)

                # Extract chunk ID from filename (handle berkan_chunk_9 format)
                chunk_id = self._extract_chunk_id(file_path.name)

                # Prepare data for bulk insert
                insert_data = []

                # Handle the actual data structure
                centroids_data = data.get('centroids', [])

                for centroid in centroids_data:
                    insert_data.append((
                        chunk_id,
                        centroid.get('cluster_id', centroid.get('object_id', 0)),
                        centroid.get('point_count', centroid.get('num_points', 0)),
                        data.get('class', table_name.title()),
                        self.dataset_name,  # Mark as berkan dataset
                        f"POINT({centroid.get('centroid_x')} {centroid.get('centroid_y')})"
                    ))

                if insert_data:
                    insert_sql = f"""
                    INSERT INTO {table_name} (chunk_id, cluster_id, num_points, class_name, dataset_source, geometry)
                    VALUES %s
                    """

                    execute_values(
                        self.cursor, insert_sql, insert_data,
                        template=None, page_size=1000
                    )

                    imported_count = len(insert_data)
                    total_imported += imported_count
                    logger.info(f"   ✅ Imported {imported_count} {table_name} from {file_path.name}")

            except Exception as e:
                logger.error(f"   ❌ Error processing {file_path}: {e}")
                continue

        self.conn.commit()
        logger.info(f"✅ Total {table_name} imported: {total_imported:,}")
        return total_imported

    def import_polygon_data(self, table_name, subdir):
        """Import polygon data (buildings, vegetation) from GeoJSON files"""
        logger.info(f"📥 Importing {table_name} polygon data from Berkan dataset...")

        polygon_files = list((DATA_DIR / 'polygons' / subdir).glob('*.geojson'))

        if not polygon_files:
            logger.warning(f"⚠️  No {table_name} files found in polygons/{subdir}")
            return 0

        total_imported = 0

        for file_path in polygon_files:
            logger.info(f"   Processing {file_path.name}")

            try:
                with open(file_path, 'r') as f:
                    data = json.load(f)

                chunk_id = self._extract_chunk_id(file_path.name)
                insert_data = []

                for feature in data.get('features', []):
                    if feature['geometry']['type'] == 'Polygon':
                        coords = feature['geometry']['coordinates'][0]  # Exterior ring

                        # Create WKT polygon
                        wkt_coords = ', '.join([f"{coord[0]} {coord[1]}" for coord in coords])
                        polygon_wkt = f"POLYGON(({wkt_coords}))"

                        properties = feature.get('properties', {})

                        insert_data.append((
                            chunk_id,
                            properties.get('cluster_id', properties.get('polygon_id', 0)),
                            properties.get('area_m2', properties.get('area', 0.0)),
                            properties.get('perimeter_m', properties.get('perimeter', 0.0)),
                            properties.get('class', table_name.replace('_', ' ').title()),
                            self.dataset_name,  # Mark as berkan dataset
                            polygon_wkt
                        ))

                if insert_data:
                    insert_sql = f"""
                    INSERT INTO {table_name} (chunk_id, cluster_id, area, perimeter, class_name, dataset_source, geometry)
                    VALUES %s
                    """

                    execute_values(
                        self.cursor, insert_sql, insert_data,
                        template=None, page_size=1000
                    )

                    imported_count = len(insert_data)
                    total_imported += imported_count
                    logger.info(f"   ✅ Imported {imported_count} {table_name} from {file_path.name}")

            except Exception as e:
                logger.error(f"   ❌ Error processing {file_path}: {e}")
                continue

        self.conn.commit()
        logger.info(f"✅ Total {table_name} imported: {total_imported:,}")
        return total_imported

    def import_line_data(self, table_name, subdir):
        """Import line data (wires) from GeoJSON files"""
        logger.info(f"📥 Importing {table_name} line data from Berkan dataset...")

        line_files = list((DATA_DIR / 'lines' / subdir).glob('*.geojson'))

        if not line_files:
            logger.warning(f"⚠️  No {table_name} files found in lines/{subdir}")
            return 0

        total_imported = 0

        for file_path in line_files:
            logger.info(f"   Processing {file_path.name}")

            try:
                with open(file_path, 'r') as f:
                    data = json.load(f)

                chunk_id = self._extract_chunk_id(file_path.name)
                insert_data = []

                for feature in data.get('features', []):
                    if feature['geometry']['type'] == 'LineString':
                        coords = feature['geometry']['coordinates']

                        # Create WKT linestring
                        wkt_coords = ', '.join([f"{coord[0]} {coord[1]}" for coord in coords])
                        linestring_wkt = f"LINESTRING({wkt_coords})"

                        properties = feature.get('properties', {})

                        insert_data.append((
                            chunk_id,
                            properties.get('cluster_id', properties.get('line_id', 0)),
                            properties.get('length_m', properties.get('length', 0.0)),
                            properties.get('class', table_name.title()),
                            self.dataset_name,  # Mark as berkan dataset
                            linestring_wkt
                        ))

                if insert_data:
                    insert_sql = f"""
                    INSERT INTO {table_name} (chunk_id, cluster_id, length, class_name, dataset_source, geometry)
                    VALUES %s
                    """

                    execute_values(
                        self.cursor, insert_sql, insert_data,
                        template=None, page_size=1000
                    )

                    imported_count = len(insert_data)
                    total_imported += imported_count
                    logger.info(f"   ✅ Imported {imported_count} {table_name} from {file_path.name}")

            except Exception as e:
                logger.error(f"   ❌ Error processing {file_path}: {e}")
                continue

        self.conn.commit()
        logger.info(f"✅ Total {table_name} imported: {total_imported:,}")
        return total_imported

    def _extract_chunk_id(self, filename):
        """Extract chunk ID from filename (handles berkan_chunk_9 format)"""
        parts = filename.split('_')

        # Handle formats like: berkan_chunk_9_...
        for i, part in enumerate(parts):
            if part == 'chunk' and i + 1 < len(parts):
                try:
                    # Extract number after 'chunk'
                    chunk_num = parts[i + 1].split('.')[0]  # Remove extension if present
                    # Remove non-digit characters
                    chunk_num = ''.join(c for c in chunk_num if c.isdigit())
                    return int(chunk_num)
                except (ValueError, IndexError):
                    pass

        # Fallback: try to find any number in filename
        import re
        numbers = re.findall(r'\d+', filename)
        return int(numbers[0]) if numbers else 1

    def verify_import(self, before_counts):
        """Verify imported data and provide statistics"""
        logger.info("📊 Verifying data import...")

        tables = ['masts', 'trees', 'buildings', 'other_vegetation', 'wires']
        total_new_records = 0

        print("\n" + "="*70)
        print("IMPORT SUMMARY")
        print("="*70)

        for table in tables:
            self.cursor.execute(f"SELECT COUNT(*) FROM {table}")
            new_count = self.cursor.fetchone()[0]
            old_count = before_counts.get(table, 0)
            imported = new_count - old_count
            total_new_records += imported

            print(f"{table:20} | Before: {old_count:6,} | After: {new_count:6,} | +{imported:6,} new")

        print("="*70)
        print(f"TOTAL NEW RECORDS: {total_new_records:,}")
        print("="*70)

        # Get coordinate system info
        self.cursor.execute("""
        SELECT srtext FROM spatial_ref_sys WHERE srid = 32629
        """)
        srs_info = self.cursor.fetchone()
        if srs_info:
            logger.info("✅ Coordinate system: UTM Zone 29N (EPSG:32629)")

        return total_new_records

    def migrate_all_data(self):
        """Main migration function - APPENDS data without removing existing"""
        try:
            # Connect to database
            self.connect()

            # Get counts before migration
            before_counts = self.get_existing_counts()

            # Create schema (if not exists)
            self.create_schema()

            print("\n" + "="*70)
            print("STARTING BERKAN DATASET MIGRATION")
            print("="*70)
            print(f"Dataset: {self.dataset_name}")
            print(f"Source: {DATA_DIR}")
            print(f"Mode: APPEND (existing data will NOT be removed)")
            print("="*70 + "\n")

            # Import all data types
            stats = {}
            stats['masts'] = self.import_centroid_data('masts')
            stats['trees'] = self.import_centroid_data('trees')
            stats['buildings'] = self.import_polygon_data('buildings', 'buildings')
            stats['other_vegetation'] = self.import_polygon_data('other_vegetation', 'vegetation')
            stats['wires'] = self.import_line_data('wires', 'wires')

            # Verify import
            total_imported = self.verify_import(before_counts)

            print("\n" + "="*70)
            print("✅ MIGRATION COMPLETED SUCCESSFULLY")
            print("="*70)
            print(f"Production database: {DB_CONFIG['host']}:{DB_CONFIG['port']}")
            print(f"Database: {DB_CONFIG['database']}")
            print(f"Dataset appended: {self.dataset_name}")
            print(f"Total NEW records added: {total_imported:,}")
            print("="*70)

            return stats

        except Exception as e:
            logger.error(f"❌ Migration failed: {e}")
            if self.conn:
                self.conn.rollback()
            raise
        finally:
            if self.conn:
                self.conn.close()

def main():
    """Main execution function"""
    if not DATA_DIR.exists():
        logger.error(f"❌ Data directory not found: {DATA_DIR}")
        sys.exit(1)

    print("\n" + "="*70)
    print("BERKAN DATASET MIGRATION TO PRODUCTION POSTGIS")
    print("="*70)
    print(f"Source data: {DATA_DIR}")
    print(f"Target database: {DB_CONFIG['host']}:{DB_CONFIG['port']}")
    print(f"Database: {DB_CONFIG['database']}")
    print("\n⚠️  IMPORTANT: This will APPEND data to existing tables")
    print("             Existing data will NOT be removed")
    print("="*70 + "\n")

    # Ask for confirmation
    response = input("Continue with migration? (yes/no): ")
    if response.lower() != 'yes':
        print("Migration cancelled.")
        sys.exit(0)

    migrator = BerkanDataMigrator()
    try:
        stats = migrator.migrate_all_data()
        logger.info("🎉 Migration completed successfully!")
        return stats
    except Exception as e:
        logger.error(f"❌ Migration failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
