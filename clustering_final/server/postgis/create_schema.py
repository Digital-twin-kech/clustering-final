#!/usr/bin/env python3
"""
Stage 4 PostGIS Schema Creation Script
Creates the complete database schema for LiDAR clustering visualization data.
Designed for PostgreSQL with PostGIS extension.
"""

import psycopg2
import psycopg2.extras
from psycopg2 import sql
import logging
import sys

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

def create_connection():
    """Create database connection with error handling"""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        conn.autocommit = True
        logger.info("Successfully connected to PostgreSQL database")
        return conn
    except psycopg2.Error as e:
        logger.error(f"Error connecting to PostgreSQL database: {e}")
        sys.exit(1)

def create_extensions(cursor):
    """Enable required PostgreSQL extensions"""
    extensions = ['postgis', 'postgis_topology']

    for ext in extensions:
        try:
            cursor.execute(f"CREATE EXTENSION IF NOT EXISTS {ext};")
            logger.info(f"Extension '{ext}' enabled")
        except psycopg2.Error as e:
            logger.error(f"Error creating extension {ext}: {e}")
            raise

def create_masts_table(cursor):
    """Create masts table for centroid points"""
    create_table_sql = """
    CREATE TABLE IF NOT EXISTS masts (
        id SERIAL PRIMARY KEY,
        mast_id INTEGER NOT NULL,
        chunk VARCHAR(50) NOT NULL,
        geom GEOMETRY(POINT, 29180) NOT NULL,
        height_m REAL,
        point_count INTEGER,
        quality_score REAL,
        extraction_method VARCHAR(100),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    );
    """

    cursor.execute(create_table_sql)

    # Create spatial index
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_masts_geom ON masts USING GIST (geom);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_masts_chunk ON masts (chunk);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_masts_mast_id ON masts (mast_id);")

    logger.info("Masts table created successfully")

def create_trees_table(cursor):
    """Create trees table for polygon features"""
    create_table_sql = """
    CREATE TABLE IF NOT EXISTS trees (
        id SERIAL PRIMARY KEY,
        tree_id INTEGER NOT NULL,
        chunk VARCHAR(50) NOT NULL,
        geom GEOMETRY(POLYGON, 29180) NOT NULL,
        area_m2 REAL,
        perimeter_m REAL,
        point_count INTEGER,
        aspect_ratio REAL,
        extraction_method VARCHAR(100),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    );
    """

    cursor.execute(create_table_sql)

    # Create spatial index
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_trees_geom ON trees USING GIST (geom);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_trees_chunk ON trees (chunk);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_trees_tree_id ON trees (tree_id);")

    logger.info("Trees table created successfully")

def create_buildings_table(cursor):
    """Create buildings table for polygon features"""
    create_table_sql = """
    CREATE TABLE IF NOT EXISTS buildings (
        id SERIAL PRIMARY KEY,
        building_id INTEGER NOT NULL,
        chunk VARCHAR(50) NOT NULL,
        geom GEOMETRY(POLYGON, 29180) NOT NULL,
        area_m2 REAL,
        perimeter_m REAL,
        point_count INTEGER,
        aspect_ratio REAL,
        extraction_method VARCHAR(100),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    );
    """

    cursor.execute(create_table_sql)

    # Create spatial index
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_buildings_geom ON buildings USING GIST (geom);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_buildings_chunk ON buildings (chunk);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_buildings_building_id ON buildings (building_id);")

    logger.info("Buildings table created successfully")

def create_other_vegetation_table(cursor):
    """Create other_vegetation table for polygon features"""
    create_table_sql = """
    CREATE TABLE IF NOT EXISTS other_vegetation (
        id SERIAL PRIMARY KEY,
        polygon_id INTEGER NOT NULL,
        chunk VARCHAR(50) NOT NULL,
        geom GEOMETRY(POLYGON, 29180) NOT NULL,
        area_m2 REAL,
        perimeter_m REAL,
        point_count INTEGER,
        aspect_ratio REAL,
        extraction_method VARCHAR(100),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    );
    """

    cursor.execute(create_table_sql)

    # Create spatial index
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_other_vegetation_geom ON other_vegetation USING GIST (geom);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_other_vegetation_chunk ON other_vegetation (chunk);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_other_vegetation_polygon_id ON other_vegetation (polygon_id);")

    logger.info("Other vegetation table created successfully")

def create_wires_table(cursor):
    """Create wires table for line features"""
    create_table_sql = """
    CREATE TABLE IF NOT EXISTS wires (
        id SERIAL PRIMARY KEY,
        line_id INTEGER NOT NULL,
        chunk VARCHAR(50) NOT NULL,
        geom GEOMETRY(LINESTRING, 29180) NOT NULL,
        length_m REAL,
        point_count INTEGER,
        extraction_method VARCHAR(100),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    );
    """

    cursor.execute(create_table_sql)

    # Create spatial index
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wires_geom ON wires USING GIST (geom);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wires_chunk ON wires (chunk);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wires_line_id ON wires (line_id);")

    logger.info("Wires table created successfully")

def create_processing_metadata_table(cursor):
    """Create metadata table to track processing information"""
    create_table_sql = """
    CREATE TABLE IF NOT EXISTS processing_metadata (
        id SERIAL PRIMARY KEY,
        chunk VARCHAR(50) NOT NULL,
        class_name VARCHAR(50) NOT NULL,
        extraction_method VARCHAR(100),
        input_points INTEGER,
        clean_points INTEGER,
        total_features INTEGER,
        total_area_m2 REAL,
        processing_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(chunk, class_name, extraction_method)
    );
    """

    cursor.execute(create_table_sql)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_metadata_chunk ON processing_metadata (chunk);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_metadata_class ON processing_metadata (class_name);")

    logger.info("Processing metadata table created successfully")

def create_summary_views(cursor):
    """Create useful summary views for data analysis"""

    # View for chunk statistics
    chunk_stats_view = """
    CREATE OR REPLACE VIEW chunk_statistics AS
    SELECT
        chunk,
        COUNT(CASE WHEN 'masts' = 'masts' THEN 1 END) as mast_count,
        COUNT(CASE WHEN 'trees' = 'trees' THEN 1 END) as tree_count,
        COUNT(CASE WHEN 'buildings' = 'buildings' THEN 1 END) as building_count,
        COUNT(CASE WHEN 'other_vegetation' = 'other_vegetation' THEN 1 END) as vegetation_count,
        COUNT(CASE WHEN 'wires' = 'wires' THEN 1 END) as wire_count
    FROM (
        SELECT chunk FROM masts
        UNION ALL SELECT chunk FROM trees
        UNION ALL SELECT chunk FROM buildings
        UNION ALL SELECT chunk FROM other_vegetation
        UNION ALL SELECT chunk FROM wires
    ) all_chunks
    GROUP BY chunk
    ORDER BY chunk;
    """

    cursor.execute(chunk_stats_view)

    # View for spatial bounds by chunk
    spatial_bounds_view = """
    CREATE OR REPLACE VIEW chunk_spatial_bounds AS
    SELECT
        chunk,
        ST_XMin(geom_union) as min_x,
        ST_YMin(geom_union) as min_y,
        ST_XMax(geom_union) as max_x,
        ST_YMax(geom_union) as max_y,
        ST_Area(geom_union) as total_area_m2
    FROM (
        SELECT
            chunk,
            ST_Union(geom) as geom_union
        FROM (
            SELECT chunk, geom FROM masts
            UNION ALL SELECT chunk, geom FROM trees
            UNION ALL SELECT chunk, geom FROM buildings
            UNION ALL SELECT chunk, geom FROM other_vegetation
            UNION ALL SELECT chunk, geom FROM wires
        ) all_geoms
        GROUP BY chunk
    ) chunk_unions
    ORDER BY chunk;
    """

    cursor.execute(spatial_bounds_view)

    logger.info("Summary views created successfully")

def main():
    """Main function to create the complete database schema"""
    logger.info("Starting PostGIS schema creation for LiDAR clustering data")

    conn = create_connection()

    try:
        with conn.cursor() as cursor:
            # Create extensions
            create_extensions(cursor)

            # Create all tables
            create_masts_table(cursor)
            create_trees_table(cursor)
            create_buildings_table(cursor)
            create_other_vegetation_table(cursor)
            create_wires_table(cursor)
            create_processing_metadata_table(cursor)

            # Create views
            create_summary_views(cursor)

            logger.info("Schema creation completed successfully!")
            logger.info("Database is ready for data migration")

    except Exception as e:
        logger.error(f"Error during schema creation: {e}")
        sys.exit(1)

    finally:
        conn.close()

if __name__ == "__main__":
    main()