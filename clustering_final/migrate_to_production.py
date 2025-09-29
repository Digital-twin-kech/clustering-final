#!/usr/bin/env python3
"""
Production Data Migration Script for LiDAR Clustering Data
Migrates organized data from server/data to production PostGIS database
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

# Data paths
DATA_DIR = Path('/home/prodair/Desktop/clustering/datasetclasified/new_data/new_data/data')

class ProductionMigrator:
    def __init__(self):
        self.conn = None
        self.cursor = None

    def connect(self):
        """Connect to production PostGIS database"""
        try:
            self.conn = psycopg2.connect(**DB_CONFIG)
            self.cursor = self.conn.cursor()
            logger.info(f"Connected to production database at {DB_CONFIG['host']}")

            # Test PostGIS extension
            self.cursor.execute("SELECT PostGIS_Version();")
            postgis_version = self.cursor.fetchone()[0]
            logger.info(f"PostGIS version: {postgis_version}")

        except Exception as e:
            logger.error(f"Failed to connect to database: {e}")
            raise

    def create_schema(self):
        """Create database schema with proper tables and spatial indexes"""
        logger.info("Creating database schema...")

        # Create tables (without dropping existing data)
        create_tables_sql = """
        -- Drop existing views if they exist but keep tables
        DROP VIEW IF EXISTS chunk_statistics CASCADE;
        DROP VIEW IF EXISTS chunk_spatial_bounds CASCADE;

        -- Create Masts table (Point features) if not exists
        CREATE TABLE IF NOT EXISTS masts (
            id SERIAL PRIMARY KEY,
            chunk_id INTEGER,
            cluster_id INTEGER,
            num_points INTEGER,
            class_name VARCHAR(50),
            geometry GEOMETRY(POINT, 29180),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        -- Create Trees table (Point features) if not exists
        CREATE TABLE IF NOT EXISTS trees (
            id SERIAL PRIMARY KEY,
            chunk_id INTEGER,
            cluster_id INTEGER,
            num_points INTEGER,
            class_name VARCHAR(50),
            geometry GEOMETRY(POINT, 29180),
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
            geometry GEOMETRY(POLYGON, 29180),
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
            geometry GEOMETRY(POLYGON, 29180),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        -- Create Wires table (LineString features) if not exists
        CREATE TABLE IF NOT EXISTS wires (
            id SERIAL PRIMARY KEY,
            chunk_id INTEGER,
            cluster_id INTEGER,
            length DOUBLE PRECISION,
            class_name VARCHAR(50),
            geometry GEOMETRY(LINESTRING, 29180),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        """

        self.cursor.execute(create_tables_sql)

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
        """

        self.cursor.execute(indexes_sql)
        self.conn.commit()
        logger.info("Database schema created successfully")

    def import_centroid_data(self, table_name, data_dir):
        """Import centroid data (masts, trees) from JSON files"""
        logger.info(f"Importing {table_name} centroid data...")

        if table_name == 'masts':
            pattern = '*Masts*'
        elif table_name == 'trees':
            pattern = '*Trees*'
        else:
            pattern = f'*{table_name}*'

        centroid_files = list((DATA_DIR / 'centroids').glob(pattern))

        if not centroid_files:
            logger.warning(f"No {table_name} files found")
            return 0

        total_imported = 0

        for file_path in centroid_files:
            logger.info(f"Processing {file_path.name}")

            try:
                with open(file_path, 'r') as f:
                    data = json.load(f)

                # Extract chunk ID from filename
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
                        f"POINT({centroid.get('centroid_x')} {centroid.get('centroid_y')})"
                    ))

                if insert_data:
                    insert_sql = f"""
                    INSERT INTO {table_name} (chunk_id, cluster_id, num_points, class_name, geometry)
                    VALUES %s
                    """

                    execute_values(
                        self.cursor, insert_sql, insert_data,
                        template=None, page_size=1000
                    )

                    imported_count = len(insert_data)
                    total_imported += imported_count
                    logger.info(f"Imported {imported_count} {table_name} from {file_path.name}")

            except Exception as e:
                logger.error(f"Error processing {file_path}: {e}")
                continue

        self.conn.commit()
        logger.info(f"Total {table_name} imported: {total_imported}")
        return total_imported

    def import_polygon_data(self, table_name, subdir):
        """Import polygon data (buildings, vegetation) from GeoJSON files"""
        logger.info(f"Importing {table_name} polygon data...")

        polygon_files = list((DATA_DIR / 'polygons' / subdir).glob('*.geojson'))

        if not polygon_files:
            logger.warning(f"No {table_name} files found in polygons/{subdir}")
            return

        total_imported = 0

        for file_path in polygon_files:
            logger.info(f"Processing {file_path.name}")

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
                            properties.get('cluster_id', properties.get('id', 0)),
                            properties.get('area', 0.0),
                            properties.get('perimeter', 0.0),
                            properties.get('class_name', table_name.replace('_', ' ').title()),
                            polygon_wkt
                        ))

                if insert_data:
                    insert_sql = f"""
                    INSERT INTO {table_name} (chunk_id, cluster_id, area, perimeter, class_name, geometry)
                    VALUES %s
                    """

                    execute_values(
                        self.cursor, insert_sql, insert_data,
                        template=None, page_size=1000
                    )

                    imported_count = len(insert_data)
                    total_imported += imported_count
                    logger.info(f"Imported {imported_count} {table_name} from {file_path.name}")

            except Exception as e:
                logger.error(f"Error processing {file_path}: {e}")
                continue

        self.conn.commit()
        logger.info(f"Total {table_name} imported: {total_imported}")
        return total_imported

    def import_line_data(self, table_name, subdir):
        """Import line data (wires) from GeoJSON files"""
        logger.info(f"Importing {table_name} line data...")

        line_files = list((DATA_DIR / 'lines' / subdir).glob('*.geojson'))

        if not line_files:
            logger.warning(f"No {table_name} files found in lines/{subdir}")
            return

        total_imported = 0

        for file_path in line_files:
            logger.info(f"Processing {file_path.name}")

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
                            properties.get('cluster_id', properties.get('id', 0)),
                            properties.get('length', 0.0),
                            properties.get('class_name', table_name.title()),
                            linestring_wkt
                        ))

                if insert_data:
                    insert_sql = f"""
                    INSERT INTO {table_name} (chunk_id, cluster_id, length, class_name, geometry)
                    VALUES %s
                    """

                    execute_values(
                        self.cursor, insert_sql, insert_data,
                        template=None, page_size=1000
                    )

                    imported_count = len(insert_data)
                    total_imported += imported_count
                    logger.info(f"Imported {imported_count} {table_name} from {file_path.name}")

            except Exception as e:
                logger.error(f"Error processing {file_path}: {e}")
                continue

        self.conn.commit()
        logger.info(f"Total {table_name} imported: {total_imported}")
        return total_imported

    def _extract_chunk_id(self, filename):
        """Extract chunk ID from filename"""
        parts = filename.split('_')
        for i, part in enumerate(parts):
            if part.startswith('chunk'):
                try:
                    return int(parts[i+1])
                except (IndexError, ValueError):
                    pass

        # Fallback: try to find any number in filename
        import re
        numbers = re.findall(r'\d+', filename)
        return int(numbers[0]) if numbers else 1

    def verify_import(self):
        """Verify imported data and provide statistics"""
        logger.info("Verifying data import...")

        tables = ['masts', 'trees', 'buildings', 'other_vegetation', 'wires']
        total_records = 0

        for table in tables:
            self.cursor.execute(f"SELECT COUNT(*) FROM {table}")
            count = self.cursor.fetchone()[0]
            total_records += count
            logger.info(f"{table}: {count} records")

        logger.info(f"Total records imported: {total_records}")

        # Get coordinate system info
        self.cursor.execute("""
        SELECT srtext FROM spatial_ref_sys WHERE srid = 29180
        """)
        srs_info = self.cursor.fetchone()
        if srs_info:
            logger.info("Coordinate system: UTM Zone 29N (EPSG:29180) ✓")

        return total_records

    def migrate_all_data(self):
        """Main migration function"""
        try:
            # Connect to database
            self.connect()

            # Create schema
            self.create_schema()

            # Import all data types
            stats = {}
            stats['masts'] = self.import_centroid_data('masts', 'centroids')
            stats['trees'] = self.import_centroid_data('trees', 'centroids')
            stats['buildings'] = self.import_polygon_data('buildings', 'buildings')
            stats['other_vegetation'] = self.import_polygon_data('other_vegetation', 'vegetation')
            stats['wires'] = self.import_line_data('wires', 'wires')

            # Verify import
            total_imported = self.verify_import()

            logger.info("="*60)
            logger.info("MIGRATION COMPLETED SUCCESSFULLY")
            logger.info("="*60)
            logger.info(f"Production database: {DB_CONFIG['host']}:{DB_CONFIG['port']}")
            logger.info(f"Database: {DB_CONFIG['database']}")
            logger.info(f"Total records imported: {total_imported}")
            logger.info("Data is ready for production use!")

            return stats

        except Exception as e:
            logger.error(f"Migration failed: {e}")
            raise
        finally:
            if self.conn:
                self.conn.close()

def main():
    """Main execution function"""
    if not DATA_DIR.exists():
        logger.error(f"Data directory not found: {DATA_DIR}")
        sys.exit(1)

    logger.info("Starting production data migration...")
    logger.info(f"Source data: {DATA_DIR}")
    logger.info(f"Target database: {DB_CONFIG['host']}:{DB_CONFIG['port']}")

    migrator = ProductionMigrator()
    try:
        stats = migrator.migrate_all_data()
        logger.info("Migration completed successfully!")
        return stats
    except Exception as e:
        logger.error(f"Migration failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()