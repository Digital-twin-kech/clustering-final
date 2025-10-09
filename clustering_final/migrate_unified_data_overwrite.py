#!/usr/bin/env python3
"""
Production Data Migration Script - COMPLETE UNIFIED DATASET
Migrates all unified data (chunks 1-17) to production PostGIS database
⚠️  OVERWRITES existing data - replaces old data with new unified dataset
"""

import os
import json
import psycopg2
from psycopg2.extras import execute_values
import logging
from pathlib import Path
import sys
import glob

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Production database configuration
DB_CONFIG = {
    'host': '13.221.230.78',
    'port': 5432,
    'database': 'lidar_clustering',
    'user': 'lidar_user',
    'password': os.getenv('DB_PASSWORD', 'lidar_pass')
}

# Data paths - unified Berkan dataset (all 17 chunks)
DATA_DIR = Path('/home/prodair/Downloads/data-last-berkan/data-last-berkan/data')

class UnifiedDataMigrator:
    def __init__(self):
        self.conn = None
        self.cursor = None
        self.stats = {
            'masts': 0,
            'trees': 0,
            'buildings': 0,
            'other_vegetation': 0,
            'wires': 0,
            'traffic_lights': 0,
            'traffic_signs': 0
        }

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
            logger.error(f"❌ Database connection failed: {e}")
            raise

    def create_tables(self):
        """Create or recreate tables with proper schema"""
        logger.info("\n🔧 Creating database tables...")

        # Drop existing tables
        tables = ['masts', 'trees', 'buildings', 'other_vegetation', 'wires', 'traffic_lights', 'traffic_signs']
        for table in tables:
            self.cursor.execute(f"DROP TABLE IF EXISTS {table} CASCADE;")
            logger.info(f"   🗑️  Dropped old table: {table}")

        # Create tables with proper schema
        table_schemas = {
            'masts': """
                CREATE TABLE masts (
                    id SERIAL PRIMARY KEY,
                    chunk_id INTEGER,
                    cluster_id INTEGER,
                    num_points INTEGER,
                    class_name VARCHAR(50),
                    geometry GEOMETRY(POINT, 32629),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                CREATE INDEX idx_masts_geom ON masts USING GIST(geometry);
            """,
            'trees': """
                CREATE TABLE trees (
                    id SERIAL PRIMARY KEY,
                    chunk_id INTEGER,
                    cluster_id INTEGER,
                    num_points INTEGER,
                    class_name VARCHAR(50),
                    geometry GEOMETRY(POINT, 32629),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                CREATE INDEX idx_trees_geom ON trees USING GIST(geometry);
            """,
            'traffic_lights': """
                CREATE TABLE traffic_lights (
                    id SERIAL PRIMARY KEY,
                    chunk_id INTEGER,
                    cluster_id INTEGER,
                    num_points INTEGER,
                    class_name VARCHAR(50),
                    geometry GEOMETRY(POINT, 32629),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                CREATE INDEX idx_traffic_lights_geom ON traffic_lights USING GIST(geometry);
            """,
            'traffic_signs': """
                CREATE TABLE traffic_signs (
                    id SERIAL PRIMARY KEY,
                    chunk_id INTEGER,
                    cluster_id INTEGER,
                    num_points INTEGER,
                    class_name VARCHAR(50),
                    geometry GEOMETRY(POINT, 32629),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                CREATE INDEX idx_traffic_signs_geom ON traffic_signs USING GIST(geometry);
            """,
            'buildings': """
                CREATE TABLE buildings (
                    id SERIAL PRIMARY KEY,
                    chunk_id INTEGER,
                    polygon_id INTEGER,
                    area_m2 FLOAT,
                    perimeter_m FLOAT,
                    point_count INTEGER,
                    class_name VARCHAR(50),
                    geometry GEOMETRY(POLYGON, 32629),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                CREATE INDEX idx_buildings_geom ON buildings USING GIST(geometry);
            """,
            'other_vegetation': """
                CREATE TABLE other_vegetation (
                    id SERIAL PRIMARY KEY,
                    chunk_id INTEGER,
                    polygon_id INTEGER,
                    area_m2 FLOAT,
                    perimeter_m FLOAT,
                    point_count INTEGER,
                    class_name VARCHAR(50),
                    geometry GEOMETRY(POLYGON, 32629),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                CREATE INDEX idx_vegetation_geom ON other_vegetation USING GIST(geometry);
            """,
            'wires': """
                CREATE TABLE wires (
                    id SERIAL PRIMARY KEY,
                    chunk_id INTEGER,
                    line_id INTEGER,
                    length_m FLOAT,
                    class_name VARCHAR(50),
                    geometry GEOMETRY(LINESTRING, 32629),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                CREATE INDEX idx_wires_geom ON wires USING GIST(geometry);
            """
        }

        for table_name, schema in table_schemas.items():
            self.cursor.execute(schema)
            logger.info(f"   ✅ Created table: {table_name}")

        self.conn.commit()
        logger.info("✅ All tables created successfully\n")

    def migrate_centroids(self):
        """Migrate centroid data (Trees, Masts, Traffic Lights, Traffic Signs)"""
        logger.info("📍 Migrating centroids...")

        centroid_types = {
            '7_Trees': 'trees',
            '12_Masts': 'masts',
            '9_TrafficLights': 'traffic_lights',
            '10_TrafficSigns': 'traffic_signs'
        }

        centroids_dir = DATA_DIR / 'centroids'

        for class_pattern, table_name in centroid_types.items():
            json_files = glob.glob(str(centroids_dir / f"*{class_pattern}*.json"))

            if not json_files:
                logger.warning(f"   ⚠️  No files found for {class_pattern}")
                continue

            records = []
            for json_file in json_files:
                try:
                    with open(json_file, 'r') as f:
                        data = json.load(f)

                    chunk_id = self._extract_chunk_id(os.path.basename(json_file))

                    for centroid in data.get('centroids', []):
                        x = centroid.get('centroid_x')
                        y = centroid.get('centroid_y')
                        if x and y:
                            records.append((
                                chunk_id,
                                centroid.get('cluster_id', 0),
                                centroid.get('point_count', 0),
                                class_pattern,
                                x, y
                            ))

                except Exception as e:
                    logger.error(f"   ❌ Error processing {json_file}: {e}")

            if records:
                insert_query = f"""
                    INSERT INTO {table_name} (chunk_id, cluster_id, num_points, class_name, geometry)
                    VALUES %s
                """
                template = "(%(chunk_id)s, %(cluster_id)s, %(num_points)s, %(class_name)s, ST_SetSRID(ST_MakePoint(%(x)s, %(y)s), 32629))"

                records_dict = [
                    {'chunk_id': r[0], 'cluster_id': r[1], 'num_points': r[2], 'class_name': r[3], 'x': r[4], 'y': r[5]}
                    for r in records
                ]

                execute_values(self.cursor, insert_query, records_dict, template=template)
                self.stats[table_name] = len(records)
                logger.info(f"   ✅ {class_pattern}: {len(records)} records")

        self.conn.commit()

    def migrate_polygons(self):
        """Migrate polygon data (Buildings, Vegetation)"""
        logger.info("\n🏢 Migrating polygons...")

        polygon_types = {
            'buildings': 'buildings',
            'vegetation': 'other_vegetation'
        }

        polygons_dir = DATA_DIR / 'polygons'

        for subdir, table_name in polygon_types.items():
            geojson_files = glob.glob(str(polygons_dir / subdir / "*.geojson"))

            if not geojson_files:
                logger.warning(f"   ⚠️  No files found for {subdir}")
                continue

            records = []
            for geojson_file in geojson_files:
                try:
                    with open(geojson_file, 'r') as f:
                        data = json.load(f)

                    chunk_id = self._extract_chunk_id(os.path.basename(geojson_file))

                    for feature in data.get('features', []):
                        geom = feature.get('geometry', {})
                        props = feature.get('properties', {})

                        if geom.get('type') == 'Polygon':
                            coords = geom.get('coordinates', [[]])[0]
                            wkt = self._coords_to_wkt_polygon(coords)

                            records.append((
                                chunk_id,
                                props.get('polygon_id', 0),
                                props.get('area_m2', 0),
                                props.get('perimeter_m', 0),
                                props.get('point_count', 0),
                                props.get('class', subdir),
                                wkt
                            ))

                except Exception as e:
                    logger.error(f"   ❌ Error processing {geojson_file}: {e}")

            if records:
                insert_query = f"""
                    INSERT INTO {table_name} (chunk_id, polygon_id, area_m2, perimeter_m, point_count, class_name, geometry)
                    VALUES %s
                """
                template = "(%(chunk_id)s, %(polygon_id)s, %(area_m2)s, %(perimeter_m)s, %(point_count)s, %(class_name)s, ST_GeomFromText(%(wkt)s, 32629))"

                records_dict = [
                    {'chunk_id': r[0], 'polygon_id': r[1], 'area_m2': r[2], 'perimeter_m': r[3], 'point_count': r[4], 'class_name': r[5], 'wkt': r[6]}
                    for r in records
                ]

                execute_values(self.cursor, insert_query, records_dict, template=template)
                self.stats[table_name] = len(records)
                logger.info(f"   ✅ {subdir}: {len(records)} records")

        self.conn.commit()

    def migrate_lines(self):
        """Migrate line data (Wires)"""
        logger.info("\n🔌 Migrating lines...")

        lines_dir = DATA_DIR / 'lines' / 'wires'
        geojson_files = glob.glob(str(lines_dir / "*.geojson"))

        if not geojson_files:
            logger.warning("   ⚠️  No wire files found")
            return

        records = []
        for geojson_file in geojson_files:
            try:
                with open(geojson_file, 'r') as f:
                    data = json.load(f)

                chunk_id = self._extract_chunk_id(os.path.basename(geojson_file))

                for feature in data.get('features', []):
                    geom = feature.get('geometry', {})
                    props = feature.get('properties', {})

                    if geom.get('type') == 'LineString':
                        coords = geom.get('coordinates', [])
                        wkt = self._coords_to_wkt_linestring(coords)

                        records.append((
                            chunk_id,
                            props.get('line_id', 0),
                            props.get('length_m', 0),
                            props.get('class', '11_Wires'),
                            wkt
                        ))

            except Exception as e:
                logger.error(f"   ❌ Error processing {geojson_file}: {e}")

        if records:
            insert_query = """
                INSERT INTO wires (chunk_id, line_id, length_m, class_name, geometry)
                VALUES %s
            """
            template = "(%(chunk_id)s, %(line_id)s, %(length_m)s, %(class_name)s, ST_GeomFromText(%(wkt)s, 32629))"

            records_dict = [
                {'chunk_id': r[0], 'line_id': r[1], 'length_m': r[2], 'class_name': r[3], 'wkt': r[4]}
                for r in records
            ]

            execute_values(self.cursor, insert_query, records_dict, template=template)
            self.stats['wires'] = len(records)
            logger.info(f"   ✅ wires: {len(records)} records")

        self.conn.commit()

    def _extract_chunk_id(self, filename):
        """Extract chunk ID from filename"""
        parts = filename.split('_')
        for i, part in enumerate(parts):
            if part == 'chunk' and i + 1 < len(parts):
                try:
                    chunk_num = parts[i + 1].split('.')[0]
                    chunk_num = ''.join(c for c in chunk_num if c.isdigit())
                    return int(chunk_num)
                except (ValueError, IndexError):
                    pass
        return 0

    def _coords_to_wkt_polygon(self, coords):
        """Convert coordinates to WKT POLYGON format"""
        coord_str = ', '.join([f"{x} {y}" for x, y in coords])
        return f"POLYGON(({coord_str}))"

    def _coords_to_wkt_linestring(self, coords):
        """Convert coordinates to WKT LINESTRING format"""
        coord_str = ', '.join([f"{x} {y}" for x, y in coords])
        return f"LINESTRING({coord_str})"

    def print_summary(self):
        """Print migration summary"""
        logger.info("\n" + "="*70)
        logger.info("📊 MIGRATION SUMMARY")
        logger.info("="*70)
        logger.info(f"✅ Masts: {self.stats['masts']:,}")
        logger.info(f"✅ Trees: {self.stats['trees']:,}")
        logger.info(f"✅ Traffic Lights: {self.stats['traffic_lights']:,}")
        logger.info(f"✅ Traffic Signs: {self.stats['traffic_signs']:,}")
        logger.info(f"✅ Buildings: {self.stats['buildings']:,}")
        logger.info(f"✅ Vegetation: {self.stats['other_vegetation']:,}")
        logger.info(f"✅ Wires: {self.stats['wires']:,}")
        logger.info("-"*70)
        total = sum(self.stats.values())
        logger.info(f"📈 TOTAL FEATURES: {total:,}")
        logger.info("="*70)

    def close(self):
        """Close database connection"""
        if self.cursor:
            self.cursor.close()
        if self.conn:
            self.conn.close()
        logger.info("✅ Database connection closed")

def main():
    print("\n" + "="*70)
    print("⚠️  PRODUCTION DATA MIGRATION - OVERWRITE MODE")
    print("="*70)
    print(f"📂 Source: {DATA_DIR}")
    print(f"🌐 Target: {DB_CONFIG['host']}:{DB_CONFIG['port']}")
    print(f"🗄️  Database: {DB_CONFIG['database']}")
    print("⚠️  THIS WILL DELETE ALL EXISTING DATA AND REPLACE IT")
    print("="*70)

    response = input("\n⚠️  Are you sure you want to OVERWRITE the production database? (yes/no): ")
    if response.lower() != 'yes':
        print("❌ Migration cancelled")
        return

    migrator = UnifiedDataMigrator()

    try:
        # Connect to database
        migrator.connect()

        # Create/recreate tables
        migrator.create_tables()

        # Migrate all data
        migrator.migrate_centroids()
        migrator.migrate_polygons()
        migrator.migrate_lines()

        # Print summary
        migrator.print_summary()

        print("\n✅ MIGRATION COMPLETED SUCCESSFULLY!")
        print(f"🌐 Production database updated at {DB_CONFIG['host']}")

    except Exception as e:
        logger.error(f"\n❌ MIGRATION FAILED: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    finally:
        migrator.close()

if __name__ == "__main__":
    main()
