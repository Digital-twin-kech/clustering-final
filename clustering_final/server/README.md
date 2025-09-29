# LiDAR Clustering Server Deployment

This folder contains the complete server deployment structure for LiDAR clustering visualization and database systems.

## 📁 Directory Structure

```
server/
├── data/                    # Organized LiDAR visualization data
│   ├── centroids/          # Point features: Masts & Trees (JSON)
│   ├── polygons/           # Polygon features (GeoJSON)
│   │   ├── buildings/
│   │   └── vegetation/
│   ├── lines/             # Line features (GeoJSON)
│   │   └── wires/
│   ├── manifest.json      # Data inventory and statistics
│   └── README.md          # Data documentation
├── visualization/          # File-based visualization server
│   └── server.py          # Optimized FastAPI server using organized data
├── postgis/               # PostGIS database deployment
│   ├── docker-compose.yml # Container orchestration
│   ├── Dockerfile         # API service container
│   ├── create_schema.py   # Database schema creation
│   ├── migrate_data.py    # Data migration pipeline
│   ├── lidar_postgis_server.py # PostGIS-based API server
│   └── init/              # Database initialization scripts
└── README.md              # This file
```

## 🚀 Deployment Options

### Option 1: File-Based Visualization Server
Quick deployment with organized data structure.

```bash
cd server/visualization
pip install fastapi uvicorn pyproj
python server.py
```
- **Access**: http://localhost:8001
- **Data**: Uses organized file structure from `../data/`
- **Performance**: Fast loading, optimized file organization

### Option 2: PostGIS Database Server
Enterprise deployment with PostgreSQL/PostGIS database.

```bash
cd server/postgis

# Start PostGIS database
docker-compose up -d postgis

# Create database schema
python create_schema.py

# Migrate data from files to database
python migrate_data.py

# Start complete system
docker-compose up -d
```
- **Access**: http://localhost:8002
- **Database**: PostgreSQL with PostGIS extensions
- **Features**: Spatial indexing, advanced queries, scalability

## 📊 Data Statistics

**Total Features**: 30 files organized across categories
- **Centroids**: 12 mast files (clean + enhanced processing)
- **Polygons**: 12 files (6 buildings + 6 vegetation)
- **Lines**: 6 wire files
- **Coordinate System**: UTM Zone 29N (Morocco region)

## 🛠️ Server Requirements

### File-Based Server
- Python 3.8+
- FastAPI, Uvicorn, PyProj
- ~100MB storage for data files
- 256MB RAM minimum

### PostGIS Server
- Docker & Docker Compose
- 2GB RAM minimum (database + API)
- ~500MB storage for database
- PostgreSQL 15 + PostGIS 3.3

## 🔧 Configuration

### Environment Variables
- `DATA_DIR`: Path to organized data folder (default: `./data`)
- `DB_HOST`: Database host (PostGIS deployment)
- `DB_PORT`: Database port (default: 5432)
- `DB_NAME`: Database name (default: lidar_clustering)

### Ports
- **8001**: File-based visualization server
- **8002**: PostGIS-based server
- **5432**: PostgreSQL database (internal)

## 📈 Performance Comparison

| Feature | File-Based | PostGIS |
|---------|------------|---------|
| Startup Time | <5 seconds | ~30 seconds |
| Data Loading | <2 seconds | <1 second |
| Memory Usage | ~256MB | ~512MB |
| Scalability | Good | Excellent |
| Query Features | Basic | Advanced |
| Spatial Indexes | No | Yes |

## 🚨 Troubleshooting

### File-Based Server Issues
```bash
# Check data directory
ls -la server/data/

# Verify Python dependencies
pip list | grep fastapi

# Test API endpoints
curl http://localhost:8001/api/health
```

### PostGIS Server Issues
```bash
# Check containers
docker-compose ps

# View logs
docker-compose logs

# Test database connection
docker exec -it lidar_postgis psql -U lidar_user -d lidar_clustering -c "SELECT version();"
```

## 📝 API Endpoints

Both servers provide:
- `GET /` - Interactive map visualization
- `GET /api/data` - All LiDAR data
- `GET /api/health` - Health check

PostGIS server additionally provides:
- `GET /api/stats` - Database statistics
- Advanced spatial queries

## 🔄 Migration Path

1. **Development**: Start with file-based server for quick testing
2. **Production**: Migrate to PostGIS for scalability and performance
3. **Data Migration**: Use `migrate_data.py` to move from files to database

## 🌍 Geographic Coverage

- **Region**: Western Morocco
- **Coordinate System**: UTM Zone 29N (EPSG:29180)
- **Data Chunks**: 6 geographic chunks with complete coverage
- **Classes**: Masts, Trees, Buildings, Other Vegetation, Wires

---

**Ready for deployment!** Choose the option that best fits your infrastructure and requirements.