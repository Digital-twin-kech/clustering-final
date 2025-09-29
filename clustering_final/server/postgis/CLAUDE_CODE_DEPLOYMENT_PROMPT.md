# LiDAR PostGIS Stage 4 Deployment - Claude Code Server Setup

## 🎯 DEPLOYMENT OBJECTIVE
Deploy a complete **Stage 4 PostGIS-based LiDAR clustering visualization system** using Docker containers. This system migrates from file-based storage to a robust PostgreSQL/PostGIS database with spatial indexing and optimized queries.

## 📋 SYSTEM ARCHITECTURE
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   FastAPI       │    │    PostGIS       │    │   Web Client    │
│   Server        │────│   Database       │    │   (Browser)     │
│   (Port 8000)   │    │   (Port 5432)    │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 🗄️ DATABASE SCHEMA SPECIFICATION

### **Coordinate System**: UTM Zone 29N (EPSG:29180) for Morocco region
### **Tables Structure**:

1. **`masts`** (Point geometries)
   - `id` (SERIAL PRIMARY KEY)
   - `mast_id` (INTEGER) - Original mast identifier
   - `chunk` (VARCHAR(50)) - Data chunk identifier
   - `geom` (GEOMETRY(POINT, 29180)) - Spatial point in UTM 29N
   - `height_m` (REAL) - Mast height in meters
   - `point_count` (INTEGER) - Number of LiDAR points
   - `quality_score` (REAL) - Quality assessment score
   - `extraction_method` (VARCHAR(100)) - Processing method used

2. **`trees`** (Polygon geometries)
   - `id` (SERIAL PRIMARY KEY)
   - `tree_id` (INTEGER) - Tree polygon identifier
   - `chunk` (VARCHAR(50)) - Data chunk identifier
   - `geom` (GEOMETRY(POLYGON, 29180)) - Spatial polygon in UTM 29N
   - `area_m2` (REAL) - Area in square meters
   - `perimeter_m` (REAL) - Perimeter in meters
   - `point_count` (INTEGER) - Number of LiDAR points
   - `aspect_ratio` (REAL) - Shape aspect ratio

3. **`buildings`** (Polygon geometries)
   - Same structure as `trees` but with `building_id`

4. **`other_vegetation`** (Polygon geometries)
   - Same structure as `trees` but with `polygon_id`

5. **`wires`** (LineString geometries)
   - `id` (SERIAL PRIMARY KEY)
   - `line_id` (INTEGER) - Wire line identifier
   - `chunk` (VARCHAR(50)) - Data chunk identifier
   - `geom` (GEOMETRY(LINESTRING, 29180)) - Spatial line in UTM 29N
   - `length_m` (REAL) - Length in meters
   - `point_count` (INTEGER) - Number of LiDAR points

6. **`processing_metadata`** (Processing tracking)
   - Tracks processing information for each class/chunk combination

### **Spatial Indexes**: All geometry columns have GIST indexes for fast spatial queries

## 🚀 DEPLOYMENT INSTRUCTIONS

### **Step 1: Setup Docker Environment**
```bash
# Navigate to the stage4_postgis directory
cd /path/to/clustering/clustering_final/stage4_postgis

# Verify all required files exist:
ls -la
# Should show: docker-compose.yml, Dockerfile, requirements.txt,
# lidar_postgis_server.py, create_schema.py, migrate_data.py,
# init/01_create_extensions.sql
```

### **Step 2: Start PostGIS Database**
```bash
# Start only the PostGIS container first
docker-compose up -d postgis

# Wait for database to be ready (check health status)
docker-compose ps
# Wait until postgis shows "healthy" status

# Check database logs
docker-compose logs postgis
```

### **Step 3: Create Database Schema**
```bash
# Install Python dependencies for schema creation
pip install psycopg2-binary

# Create the complete database schema
python3 create_schema.py

# Verify schema creation
docker exec -it lidar_postgis psql -U lidar_user -d lidar_clustering -c "\dt"
# Should list all 6 tables: masts, trees, buildings, other_vegetation, wires, processing_metadata
```

### **Step 4: Migrate Existing Data**
```bash
# Run the comprehensive data migration
python3 migrate_data.py

# This will:
# - Clear existing data from all tables
# - Migrate masts from JSON centroid files
# - Migrate trees, buildings, vegetation from GeoJSON polygon files
# - Migrate wires from GeoJSON line files
# - Insert processing metadata
# - Provide detailed migration statistics
```

### **Step 5: Start Complete System**
```bash
# Start both database and API server
docker-compose up -d

# Check that both services are running
docker-compose ps
# Should show both 'lidar_postgis' and 'lidar_api' as healthy

# Check API server logs
docker-compose logs lidar_api
```

### **Step 6: Verify Deployment**
```bash
# Test database connection
curl http://localhost:8002/api/health

# Get system statistics
curl http://localhost:8002/api/stats

# Access the web visualization
open http://localhost:8002
```

## 🌐 API ENDPOINTS

- **`GET /`** - Interactive map visualization interface
- **`GET /api/data`** - All LiDAR data with coordinate conversion
- **`GET /api/health`** - System health check
- **`GET /api/stats`** - Database statistics

## 📊 DATA MIGRATION DETAILS

The migration script handles:

1. **Coordinate System Conversion**:
   - Stores data in UTM Zone 29N (EPSG:29180) for accuracy
   - Converts to WGS84 (EPSG:4326) for web display

2. **Data Sources**:
   - Masts: `/outlast/chunks/*/compressed/filtred_by_classes/*/centroids/*_centroids_clean.json`
   - Trees: `/outlast/chunks/*/compressed/filtred_by_classes/7_Trees/polygons/*_polygons.geojson`
   - Buildings: `/outlast/chunks/*/compressed/filtred_by_classes/6_Buildings/polygons/*_polygons.geojson`
   - Vegetation: `/outlast/chunks/*/compressed/filtred_by_classes/8_OtherVegetation/polygons/*_polygons.geojson`
   - Wires: `/outlast/chunks/*/compressed/filtred_by_classes/11_Wires/lines/*_lines.geojson`

3. **Data Validation**:
   - Ensures valid geometry types (Point, Polygon, LineString)
   - Validates coordinate ranges and formats
   - Handles chunk name extraction from file paths

## 🔧 CONFIGURATION

### **Environment Variables**:
- `DB_HOST=localhost` (or postgis container name)
- `DB_PORT=5432`
- `DB_NAME=lidar_clustering`
- `DB_USER=lidar_user`
- `DB_PASSWORD=lidar_pass`

### **Ports**:
- **8002**: FastAPI server (external access)
- **5432**: PostgreSQL database (internal)

## 🚨 TROUBLESHOOTING

### **Database Connection Issues**:
```bash
# Check if PostGIS container is running
docker-compose ps

# Check database logs
docker-compose logs postgis

# Test direct database connection
docker exec -it lidar_postgis psql -U lidar_user -d lidar_clustering -c "SELECT version();"
```

### **Migration Issues**:
```bash
# Check if source data files exist
find /path/to/outlast/chunks -name "*_centroids_clean.json" | head -5
find /path/to/outlast/chunks -name "*_polygons.geojson" | head -5

# Run migration with verbose logging
python3 migrate_data.py 2>&1 | tee migration.log
```

### **API Server Issues**:
```bash
# Check API container logs
docker-compose logs lidar_api

# Test API health directly
docker exec -it lidar_api curl http://localhost:8000/api/health
```

## 📈 EXPECTED RESULTS

After successful deployment:

1. **Database**: ~50,000+ spatial features across all classes
2. **Response Time**: <2 seconds for full dataset queries
3. **Map Loading**: <5 seconds for complete visualization
4. **Memory Usage**: ~512MB for database, ~256MB for API

## 🎛️ PERFORMANCE OPTIMIZATION

The system includes:

- **Spatial Indexes**: GIST indexes on all geometry columns
- **Connection Pooling**: PostgreSQL connection management
- **Coordinate Caching**: Efficient UTM ↔ WGS84 conversion
- **Chunked Queries**: Pagination support for large datasets

## 📝 MONITORING

Check system status:
```bash
# Container health
docker-compose ps

# Resource usage
docker stats

# API metrics
curl http://localhost:8002/api/stats | jq
```

---

**🎯 SUCCESS CRITERIA**:
- All containers running and healthy
- Database contains migrated LiDAR data with proper spatial indexing
- Web interface displays interactive map with all data classes
- API responds to health checks and data queries within acceptable time limits