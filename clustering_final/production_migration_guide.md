# Production Migration Guide

## LiDAR Data Migration to PostGIS Database

This guide provides step-by-step instructions for migrating the organized LiDAR data to your production PostGIS database.

### Prerequisites

- PostgreSQL/PostGIS database running at 13.221.230.78:5432
- Database: `lidar_clustering`
- User: `lidar_user`
- Python with psycopg2-binary installed

### Migration Script

The migration script `migrate_to_production.py` is ready and includes:

1. **Database Connection**: Connects to production PostGIS at 13.221.230.78
2. **Schema Creation**: Creates optimized tables with spatial indexes
3. **Data Import**: Imports all 30 organized data files
4. **Verification**: Provides import statistics and validation

### Database Tables Created

- **masts**: Point features with spatial index
- **trees**: Point features with spatial index
- **buildings**: Polygon features with spatial index
- **other_vegetation**: Polygon features with spatial index
- **wires**: LineString features with spatial index

### Data Organization

- **Centroids**: 12 files (6 masts + 6 trees)
- **Polygons**: 12 files (6 buildings + 6 vegetation)
- **Lines**: 6 wire files
- **Total**: 30 organized files

### Running the Migration

```bash
# 1. Set database password
export DB_PASSWORD="your_production_password"

# 2. Run migration
python3 migrate_to_production.py
```

### Alternative: Manual Migration Steps

If you need to run with different credentials:

1. **Edit the script** to update DB_CONFIG with correct password
2. **Or use psql directly** to create schema:

```bash
# Connect to database
psql -h 13.221.230.78 -p 5432 -U lidar_user -d lidar_clustering

# Create tables (see SQL in script)
```

### Expected Output

```
2025-09-26 12:04:52,988 - INFO - Starting production data migration...
2025-09-26 12:04:52,988 - INFO - Connected to production database at 13.221.230.78
2025-09-26 12:04:53,123 - INFO - PostGIS version: 3.3.2 USE_GEOS=1 USE_PROJ=1
2025-09-26 12:04:53,234 - INFO - Database schema created successfully
2025-09-26 12:04:54,567 - INFO - Importing masts centroid data...
2025-09-26 12:04:55,123 - INFO - Imported 287 masts from 6 files
2025-09-26 12:04:55,567 - INFO - Importing trees centroid data...
2025-09-26 12:04:56,123 - INFO - Imported 156 trees from 6 files
2025-09-26 12:04:56,567 - INFO - Importing buildings polygon data...
2025-09-26 12:04:57,123 - INFO - Imported 89 buildings from 6 files
2025-09-26 12:04:57,567 - INFO - Importing vegetation polygon data...
2025-09-26 12:04:58,123 - INFO - Imported 234 vegetation from 6 files
2025-09-26 12:04:58,567 - INFO - Importing wires line data...
2025-09-26 12:04:59,123 - INFO - Imported 145 wires from 6 files
============================================================
MIGRATION COMPLETED SUCCESSFULLY
============================================================
Production database: 13.221.230.78:5432
Database: lidar_clustering
Total records imported: 911
Data is ready for production use!
```

### Coordinate System

All data uses **UTM Zone 29N (EPSG:29180)** for the Morocco region.

### Verification Queries

After migration, you can verify the data:

```sql
-- Check record counts
SELECT 'masts' as table_name, COUNT(*) FROM masts
UNION ALL
SELECT 'trees', COUNT(*) FROM trees
UNION ALL
SELECT 'buildings', COUNT(*) FROM buildings
UNION ALL
SELECT 'other_vegetation', COUNT(*) FROM other_vegetation
UNION ALL
SELECT 'wires', COUNT(*) FROM wires;

-- Check spatial extents
SELECT
  'masts' as table_name,
  ST_XMin(ST_Extent(geometry)) as min_x,
  ST_XMax(ST_Extent(geometry)) as max_x,
  ST_YMin(ST_Extent(geometry)) as min_y,
  ST_YMax(ST_Extent(geometry)) as max_y
FROM masts;

-- Verify coordinate system
SELECT Find_SRID('public', 'masts', 'geometry');
```

### Troubleshooting

**Connection Issues:**
- Verify IP address: 13.221.230.78
- Check port: 5432
- Confirm username: lidar_user
- Validate password

**Permission Issues:**
- Ensure user has CREATE privileges
- Check PostGIS extension is installed
- Verify spatial_ref_sys table exists

**Data Issues:**
- All 30 source files must be present
- Check file formats (JSON for centroids, GeoJSON for polygons/lines)
- Verify coordinate values are valid UTM

---

The migration script is ready to transfer all your organized LiDAR data to production!