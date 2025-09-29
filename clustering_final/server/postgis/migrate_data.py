#!/usr/bin/env python3
"""
Stage 4 Data Migration Script
Migrates all existing LiDAR visualization data from JSON/GeoJSON files to PostGIS database.
Handles all data types: centroids, polygons, and lines.
"""

import psycopg2
import psycopg2.extras
from psycopg2.extras import execute_values
import json
import os
import glob
import logging
import sys
from pathlib import Path
import time

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Database configuration
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'lidar_clustering',
    'user': 'lidar_user',
    'password': 'lidar_pass'
}

# Base directory for data
BASE_DIR = "/home/prodair/Desktop/MORIUS5090/clustering/clustering_final/outlast/chunks"

def create_connection():
    """Create database connection with error handling"""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        conn.autocommit = False  # Use transactions for data migration
        logger.info("Successfully connected to PostgreSQL database")
        return conn
    except psycopg2.Error as e:
        logger.error(f"Error connecting to PostgreSQL database: {e}")
        sys.exit(1)

def clear_existing_data(cursor):
    """Clear existing data from all tables"""
    tables = ['masts', 'trees', 'buildings', 'other_vegetation', 'wires', 'processing_metadata']

    for table in tables:
        cursor.execute(f"TRUNCATE TABLE {table} RESTART IDENTITY CASCADE;")
        logger.info(f"Cleared existing data from {table} table")

def migrate_masts_data(cursor):
    """Migrate masts centroid data from JSON files"""
    masts_data = []
    metadata_data = []

    # Find all mast JSON files
    mast_files = glob.glob(f"{BASE_DIR}/*/compressed/filtred_by_classes/*/centroids/*_centroids_clean.json")
    mast_files.extend(glob.glob(f"{BASE_DIR}/*/compressed/filtred_by_classes/*/centroids/*_centroids.json"))

    logger.info(f"Found {len(mast_files)} mast files to process")

    for file_path in mast_files:
        try:
            with open(file_path, 'r') as f:
                data = json.load(f)

            # Extract chunk info from path
            path_parts = Path(file_path).parts
            chunk = None
            for part in path_parts:
                if part.startswith('chunk_'):
                    chunk = part
                    break

            if not chunk:
                logger.warning(f"Could not extract chunk info from {file_path}")
                continue

            # Check if this is a mast file
            if '3_Masts' not in file_path:
                continue

            # Process centroids
            centroids = data.get('centroids', [])
            for i, centroid in enumerate(centroids):
                masts_data.append((
                    centroid.get('mast_id', i + 1),
                    chunk,
                    f"POINT({centroid['x']} {centroid['y']})",
                    centroid.get('height_m'),
                    centroid.get('point_count'),
                    centroid.get('quality_score'),
                    centroid.get('extraction_method', 'unknown')
                ))

            # Process metadata if available
            if 'metadata' in data:
                meta = data['metadata']
                metadata_data.append((
                    chunk,
                    '3_Masts',
                    meta.get('extraction_method', 'unknown'),
                    meta.get('input_points'),
                    meta.get('clean_points'),
                    len(centroids),
                    None  # No total_area for centroids
                ))

            logger.info(f"Processed mast file: {file_path} - {len(centroids)} centroids")

        except Exception as e:
            logger.error(f"Error processing mast file {file_path}: {e}")
            continue

    # Insert masts data
    if masts_data:
        insert_sql = """
        INSERT INTO masts (mast_id, chunk, geom, height_m, point_count, quality_score, extraction_method)
        VALUES %s
        """
        execute_values(cursor, insert_sql, masts_data, template=None, page_size=100)
        logger.info(f"Inserted {len(masts_data)} mast records")

    return metadata_data

def migrate_polygon_data(cursor, class_name, table_name, class_folder):
    """Generic function to migrate polygon data (trees, buildings, vegetation)"""
    polygon_data = []
    metadata_data = []

    # Find all polygon GeoJSON files for this class
    pattern = f"{BASE_DIR}/*/compressed/filtred_by_classes/{class_folder}/polygons/*_polygons.geojson"
    polygon_files = glob.glob(pattern)

    logger.info(f"Found {len(polygon_files)} {class_name} files to process")

    for file_path in polygon_files:
        try:
            with open(file_path, 'r') as f:
                data = json.load(f)

            # Extract chunk info
            path_parts = Path(file_path).parts
            chunk = None
            for part in path_parts:
                if part.startswith('chunk_'):
                    chunk = part
                    break

            if not chunk:
                logger.warning(f"Could not extract chunk info from {file_path}")
                continue

            # Process features
            features = data.get('features', [])
            for feature in features:
                props = feature.get('properties', {})
                geom = feature.get('geometry')

                if geom and geom.get('type') == 'Polygon':
                    # Convert coordinates to WKT format
                    coords = geom['coordinates']
                    if coords:
                        # Build WKT polygon string
                        rings = []
                        for ring in coords:
                            ring_coords = ', '.join([f"{coord[0]} {coord[1]}" for coord in ring])
                            rings.append(f"({ring_coords})")
                        wkt = f"POLYGON({', '.join(rings)})"

                        # Determine ID field name based on class
                        id_field = {
                            'trees': 'tree_id',
                            'buildings': 'building_id',
                            'other_vegetation': 'polygon_id'
                        }.get(table_name, 'polygon_id')

                        polygon_data.append((
                            props.get(id_field, props.get('polygon_id', len(polygon_data) + 1)),
                            chunk,
                            wkt,
                            props.get('area_m2'),
                            props.get('perimeter_m'),
                            props.get('point_count'),
                            props.get('aspect_ratio'),
                            props.get('extraction_method', 'unknown')
                        ))

            # Process collection-level metadata if available
            coll_props = data.get('properties', {})
            if 'results' in coll_props:
                results = coll_props['results']
                metadata_data.append((
                    chunk,
                    class_name,
                    coll_props.get('extraction_method', 'unknown'),
                    results.get('input_points'),
                    results.get('clean_points'),
                    len(features),
                    results.get('total_area_m2')
                ))

            logger.info(f"Processed {class_name} file: {file_path} - {len(features)} polygons")

        except Exception as e:
            logger.error(f"Error processing {class_name} file {file_path}: {e}")
            continue

    # Insert polygon data
    if polygon_data:
        # Dynamic column mapping based on table
        if table_name == 'trees':
            insert_sql = """
            INSERT INTO trees (tree_id, chunk, geom, area_m2, perimeter_m, point_count, aspect_ratio, extraction_method)
            VALUES %s
            """
        elif table_name == 'buildings':
            insert_sql = """
            INSERT INTO buildings (building_id, chunk, geom, area_m2, perimeter_m, point_count, aspect_ratio, extraction_method)
            VALUES %s
            """
        else:  # other_vegetation
            insert_sql = """
            INSERT INTO other_vegetation (polygon_id, chunk, geom, area_m2, perimeter_m, point_count, aspect_ratio, extraction_method)
            VALUES %s
            """

        execute_values(cursor, insert_sql, polygon_data, template=None, page_size=100)
        logger.info(f"Inserted {len(polygon_data)} {class_name} records")

    return metadata_data

def migrate_wires_data(cursor):
    """Migrate wire line data from GeoJSON files"""
    wires_data = []
    metadata_data = []

    # Find all wire GeoJSON files
    wire_files = glob.glob(f"{BASE_DIR}/*/compressed/filtred_by_classes/*/lines/*_lines.geojson")

    logger.info(f"Found {len(wire_files)} wire files to process")

    for file_path in wire_files:
        try:
            # Skip road/sidewalk files based on previous filtering logic
            if any(x in file_path for x in ['12_Roads', '13_Sidewalks']):
                continue

            with open(file_path, 'r') as f:
                data = json.load(f)

            # Extract chunk info
            path_parts = Path(file_path).parts
            chunk = None
            for part in path_parts:
                if part.startswith('chunk_'):
                    chunk = part
                    break

            if not chunk:
                logger.warning(f"Could not extract chunk info from {file_path}")
                continue

            # Check if this is a wire file
            if '11_Wires' not in file_path:
                continue

            # Process features
            features = data.get('features', [])
            for feature in features:
                props = feature.get('properties', {})
                geom = feature.get('geometry')

                if geom and geom.get('type') == 'LineString':
                    # Convert coordinates to WKT format
                    coords = geom['coordinates']
                    if coords:
                        coord_pairs = ', '.join([f"{coord[0]} {coord[1]}" for coord in coords])
                        wkt = f"LINESTRING({coord_pairs})"

                        wires_data.append((
                            props.get('line_id', len(wires_data) + 1),
                            chunk,
                            wkt,
                            props.get('length_m'),
                            props.get('point_count'),
                            props.get('extraction_method', 'unknown')
                        ))

            # Process metadata if available
            coll_props = data.get('properties', {})
            if 'results' in coll_props:
                results = coll_props['results']
                metadata_data.append((
                    chunk,
                    '11_Wires',
                    coll_props.get('extraction_method', 'unknown'),
                    results.get('input_points'),
                    results.get('clean_points'),
                    len(features),
                    None  # No total_area for lines
                ))

            logger.info(f"Processed wire file: {file_path} - {len(features)} lines")

        except Exception as e:
            logger.error(f"Error processing wire file {file_path}: {e}")
            continue

    # Insert wires data
    if wires_data:
        insert_sql = """
        INSERT INTO wires (line_id, chunk, geom, length_m, point_count, extraction_method)
        VALUES %s
        """
        execute_values(cursor, insert_sql, wires_data, template=None, page_size=100)
        logger.info(f"Inserted {len(wires_data)} wire records")

    return metadata_data

def insert_metadata(cursor, all_metadata):
    """Insert all processing metadata"""
    if all_metadata:
        insert_sql = """
        INSERT INTO processing_metadata (chunk, class_name, extraction_method, input_points, clean_points, total_features, total_area_m2)
        VALUES %s
        ON CONFLICT (chunk, class_name, extraction_method) DO UPDATE SET
            input_points = EXCLUDED.input_points,
            clean_points = EXCLUDED.clean_points,
            total_features = EXCLUDED.total_features,
            total_area_m2 = EXCLUDED.total_area_m2,
            processing_date = CURRENT_TIMESTAMP
        """
        execute_values(cursor, insert_sql, all_metadata, template=None, page_size=100)
        logger.info(f"Inserted {len(all_metadata)} metadata records")

def main():
    """Main function to migrate all visualization data"""
    logger.info("Starting data migration to PostGIS database")
    start_time = time.time()

    conn = create_connection()

    try:
        with conn.cursor() as cursor:
            # Clear existing data
            clear_existing_data(cursor)
            conn.commit()

            # Collect all metadata
            all_metadata = []

            # Migrate masts
            logger.info("Migrating masts data...")
            masts_metadata = migrate_masts_data(cursor)
            all_metadata.extend(masts_metadata)
            conn.commit()

            # Migrate trees
            logger.info("Migrating trees data...")
            trees_metadata = migrate_polygon_data(cursor, '7_Trees', 'trees', '7_Trees')
            all_metadata.extend(trees_metadata)
            conn.commit()

            # Migrate buildings
            logger.info("Migrating buildings data...")
            buildings_metadata = migrate_polygon_data(cursor, '6_Buildings', 'buildings', '6_Buildings')
            all_metadata.extend(buildings_metadata)
            conn.commit()

            # Migrate other vegetation
            logger.info("Migrating other vegetation data...")
            vegetation_metadata = migrate_polygon_data(cursor, '8_OtherVegetation', 'other_vegetation', '8_OtherVegetation')
            all_metadata.extend(vegetation_metadata)
            conn.commit()

            # Migrate wires
            logger.info("Migrating wires data...")
            wires_metadata = migrate_wires_data(cursor)
            all_metadata.extend(wires_metadata)
            conn.commit()

            # Insert metadata
            logger.info("Inserting processing metadata...")
            insert_metadata(cursor, all_metadata)
            conn.commit()

            # Print summary statistics
            cursor.execute("SELECT COUNT(*) FROM masts")
            masts_count = cursor.fetchone()[0]

            cursor.execute("SELECT COUNT(*) FROM trees")
            trees_count = cursor.fetchone()[0]

            cursor.execute("SELECT COUNT(*) FROM buildings")
            buildings_count = cursor.fetchone()[0]

            cursor.execute("SELECT COUNT(*) FROM other_vegetation")
            vegetation_count = cursor.fetchone()[0]

            cursor.execute("SELECT COUNT(*) FROM wires")
            wires_count = cursor.fetchone()[0]

            cursor.execute("SELECT COUNT(*) FROM processing_metadata")
            metadata_count = cursor.fetchone()[0]

            end_time = time.time()
            duration = end_time - start_time

            logger.info("=" * 60)
            logger.info("MIGRATION SUMMARY")
            logger.info("=" * 60)
            logger.info(f"Masts: {masts_count:,} records")
            logger.info(f"Trees: {trees_count:,} records")
            logger.info(f"Buildings: {buildings_count:,} records")
            logger.info(f"Other Vegetation: {vegetation_count:,} records")
            logger.info(f"Wires: {wires_count:,} records")
            logger.info(f"Metadata: {metadata_count:,} records")
            logger.info(f"Total Duration: {duration:.2f} seconds")
            logger.info("=" * 60)
            logger.info("Data migration completed successfully!")

    except Exception as e:
        logger.error(f"Error during data migration: {e}")
        conn.rollback()
        sys.exit(1)

    finally:
        conn.close()

if __name__ == "__main__":
    main()