-- Create required PostgreSQL extensions for LiDAR clustering database
-- This script runs automatically when the PostGIS container starts

-- Enable PostGIS extension for spatial data support
CREATE EXTENSION IF NOT EXISTS postgis;

-- Enable PostGIS topology extension (optional but useful for advanced spatial operations)
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Create a log entry to confirm extensions are loaded
DO $$
BEGIN
    RAISE NOTICE 'PostGIS extensions successfully created for LiDAR clustering database';
END $$;