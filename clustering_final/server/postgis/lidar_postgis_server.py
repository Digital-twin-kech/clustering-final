#!/usr/bin/env python3
"""
Stage 4 PostGIS-based LiDAR Visualization Server
FastAPI server that connects to PostGIS database for LiDAR clustering visualization
"""

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
import psycopg2
import psycopg2.extras
from typing import List, Dict, Any, Optional
import json
import logging
import os
import uvicorn

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="LiDAR PostGIS Visualization Server",
    description="Stage 4 - PostGIS-based LiDAR clustering visualization",
    version="4.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Database configuration from environment variables
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': int(os.getenv('DB_PORT', 5432)),
    'database': os.getenv('DB_NAME', 'lidar_clustering'),
    'user': os.getenv('DB_USER', 'lidar_user'),
    'password': os.getenv('DB_PASSWORD', 'lidar_pass')
}

def get_db_connection():
    """Create database connection"""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        return conn
    except psycopg2.Error as e:
        logger.error(f"Database connection error: {e}")
        raise HTTPException(status_code=500, detail="Database connection failed")

@app.get("/")
async def root():
    """Main map visualization page"""
    return HTMLResponse(content="""
<!DOCTYPE html>
<html>
<head>
    <title>LiDAR PostGIS Visualization</title>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
    <style>
        body { margin: 0; padding: 0; font-family: Arial, sans-serif; background: #f0f0f0; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; text-align: center; }
        .header h1 { margin: 0; font-size: 2.5em; font-weight: 300; }
        .header p { margin: 10px 0 0 0; opacity: 0.9; font-size: 1.1em; }
        .controls { background: white; padding: 15px; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 15px; }
        .control-group { display: flex; align-items: center; gap: 10px; }
        .control-group label { font-weight: bold; color: #333; }
        select, button { padding: 8px 12px; border: 1px solid #ddd; border-radius: 4px; font-size: 14px; }
        button { background: #667eea; color: white; border: none; cursor: pointer; }
        button:hover { background: #5a67d8; }
        .stats { background: rgba(255,255,255,0.9); padding: 10px; border-radius: 5px; font-size: 14px; color: #333; }
        #map { height: 80vh; width: 100%; border: 2px solid #ddd; }
        .leaflet-popup-content { font-family: Arial, sans-serif; }
        .popup-title { font-weight: bold; font-size: 16px; color: #333; margin-bottom: 8px; }
        .popup-info { font-size: 14px; line-height: 1.4; }
        .coordinate-info { background: #f8f9fa; padding: 8px; border-radius: 4px; margin-top: 8px; font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🗄️ LiDAR PostGIS Visualization</h1>
        <p>Stage 4 - PostgreSQL/PostGIS Database-based LiDAR clustering visualization</p>
    </div>

    <div class="controls">
        <div class="control-group">
            <label for="classFilter">Filter by Class:</label>
            <select id="classFilter">
                <option value="all">All Classes</option>
            </select>
        </div>
        <div class="control-group">
            <label for="chunkFilter">Filter by Chunk:</label>
            <select id="chunkFilter">
                <option value="all">All Chunks</option>
            </select>
        </div>
        <div class="control-group">
            <button onclick="loadData()">🔄 Refresh Data</button>
            <button onclick="fitMapToData()">🎯 Fit to Data</button>
        </div>
        <div class="stats" id="stats">Loading data from PostGIS...</div>
    </div>

    <div id="map"></div>

    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
    <script>
        let map;
        let allData = {masts: [], trees: [], buildings: [], vegetation: [], wires: []};
        let markers = []; let polygons = []; let lines = [];
        let markerGroup; let polygonGroup; let lineGroup;

        const classColors = {
            'masts': '#DC143C', 'trees': '#228B22', 'buildings': '#8B4513',
            'other_vegetation': '#90EE90', 'wires': '#8B4513'
        };

        function initMap() {
            map = L.map('map').setView([34.0209, -6.8416], 13);
            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                attribution: '© OpenStreetMap | PostGIS LiDAR Visualization'
            }).addTo(map);

            markerGroup = L.layerGroup().addTo(map);
            polygonGroup = L.layerGroup().addTo(map);
            lineGroup = L.layerGroup().addTo(map);

            loadData();
        }

        async function loadData() {
            try {
                document.getElementById('stats').textContent = 'Loading from PostGIS database...';

                const response = await fetch('/api/data');
                const result = await response.json();

                allData = result.data || {};

                displayMasts(allData.masts || []);
                displayPolygons([...(allData.trees || []), ...(allData.buildings || []), ...(allData.vegetation || [])]);
                displayLines(allData.wires || []);

                updateStats(allData);
                updateFilters(result.filters || {});

                setTimeout(() => fitMapToData(), 1000);
            } catch (error) {
                console.error('Error loading data:', error);
                document.getElementById('stats').textContent = 'Error loading PostGIS data';
            }
        }

        function displayMasts(masts) {
            markerGroup.clearLayers();
            masts.forEach(mast => {
                const [lat, lon] = [mast.lat, mast.lon];
                const marker = L.circleMarker([lat, lon], {
                    radius: 8, fillColor: classColors.masts, color: '#ffffff',
                    weight: 2, opacity: 1, fillOpacity: 0.8
                });

                const popupContent = `
                    <div class="popup-title">Mast #${mast.mast_id}</div>
                    <div class="popup-info">
                        <strong>Height:</strong> ${mast.height_m?.toFixed(1)}m<br>
                        <strong>Points:</strong> ${mast.point_count?.toLocaleString()}<br>
                        <strong>Quality:</strong> ${mast.quality_score?.toFixed(2)}<br>
                        <strong>Chunk:</strong> ${mast.chunk}
                    </div>
                `;

                marker.bindPopup(popupContent);
                marker.addTo(markerGroup);
                markers.push(marker);
            });
        }

        function displayPolygons(polygonData) {
            polygonGroup.clearLayers();
            polygonData.forEach(poly => {
                const color = classColors[poly.class_type] || '#8B4513';
                const coords = poly.coordinates;

                const polygon = L.polygon(coords, {
                    fillColor: color, fillOpacity: 0.6, color: '#333333', weight: 2
                });

                const popupContent = `
                    <div class="popup-title">${poly.class_type} #${poly.id}</div>
                    <div class="popup-info">
                        <strong>Area:</strong> ${poly.area_m2?.toLocaleString()} m²<br>
                        <strong>Points:</strong> ${poly.point_count?.toLocaleString()}<br>
                        <strong>Chunk:</strong> ${poly.chunk}
                    </div>
                `;

                polygon.bindPopup(popupContent);
                polygon.addTo(polygonGroup);
                polygons.push(polygon);
            });
        }

        function displayLines(lines) {
            lineGroup.clearLayers();
            lines.forEach(line => {
                const coords = line.coordinates;
                const polyline = L.polyline(coords, {
                    color: classColors.wires, weight: 4, opacity: 0.8
                });

                const popupContent = `
                    <div class="popup-title">Wire #${line.line_id}</div>
                    <div class="popup-info">
                        <strong>Length:</strong> ${line.length_m?.toFixed(1)} m<br>
                        <strong>Points:</strong> ${line.point_count?.toLocaleString()}<br>
                        <strong>Chunk:</strong> ${line.chunk}
                    </div>
                `;

                polyline.bindPopup(popupContent);
                polyline.addTo(lineGroup);
                lines.push(polyline);
            });
        }

        function updateStats(data) {
            const mastCount = (data.masts || []).length;
            const treeCount = (data.trees || []).length;
            const buildingCount = (data.buildings || []).length;
            const vegetationCount = (data.vegetation || []).length;
            const wireCount = (data.wires || []).length;

            document.getElementById('stats').innerHTML = `
                <strong>${mastCount}</strong> masts |
                <strong>${treeCount}</strong> trees |
                <strong>${buildingCount}</strong> buildings |
                <strong>${vegetationCount}</strong> vegetation |
                <strong>${wireCount}</strong> wires
            `;
        }

        function updateFilters(filters) {
            // Implementation for filter dropdowns
        }

        function fitMapToData() {
            const allFeatures = [...markers, ...polygons, ...lines];
            if (allFeatures.length > 0) {
                const group = new L.featureGroup(allFeatures);
                map.fitBounds(group.getBounds().pad(0.1));
            }
        }

        document.addEventListener('DOMContentLoaded', initMap);
    </script>
</body>
</html>
    """)

@app.get("/api/data")
async def get_all_data():
    """Get all LiDAR data from PostGIS database"""
    conn = get_db_connection()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cursor:
            # Get masts with coordinate conversion
            cursor.execute("""
                SELECT
                    mast_id, chunk,
                    ST_Y(ST_Transform(geom, 4326)) as lat,
                    ST_X(ST_Transform(geom, 4326)) as lon,
                    height_m, point_count, quality_score, extraction_method
                FROM masts
                ORDER BY chunk, mast_id
            """)
            masts = cursor.fetchall()

            # Get trees with coordinate conversion
            cursor.execute("""
                SELECT
                    tree_id as id, chunk, 'trees' as class_type,
                    ST_AsGeoJSON(ST_Transform(geom, 4326))::json->'coordinates' as coordinates,
                    area_m2, perimeter_m, point_count, aspect_ratio
                FROM trees
                ORDER BY chunk, tree_id
            """)
            trees = cursor.fetchall()

            # Get buildings
            cursor.execute("""
                SELECT
                    building_id as id, chunk, 'buildings' as class_type,
                    ST_AsGeoJSON(ST_Transform(geom, 4326))::json->'coordinates' as coordinates,
                    area_m2, perimeter_m, point_count, aspect_ratio
                FROM buildings
                ORDER BY chunk, building_id
            """)
            buildings = cursor.fetchall()

            # Get other vegetation
            cursor.execute("""
                SELECT
                    polygon_id as id, chunk, 'other_vegetation' as class_type,
                    ST_AsGeoJSON(ST_Transform(geom, 4326))::json->'coordinates' as coordinates,
                    area_m2, perimeter_m, point_count, aspect_ratio
                FROM other_vegetation
                ORDER BY chunk, polygon_id
            """)
            vegetation = cursor.fetchall()

            # Get wires
            cursor.execute("""
                SELECT
                    line_id, chunk,
                    ST_AsGeoJSON(ST_Transform(geom, 4326))::json->'coordinates' as coordinates,
                    length_m, point_count
                FROM wires
                ORDER BY chunk, line_id
            """)
            wires = cursor.fetchall()

            # Convert coordinates format for polygons
            for item in trees + buildings + vegetation:
                if item['coordinates']:
                    # Convert GeoJSON coordinates [[[lon,lat]]] to Leaflet format [[[lat,lon]]]
                    coords = item['coordinates'][0]  # Get outer ring
                    item['coordinates'] = [[coord[1], coord[0]] for coord in coords]

            # Convert coordinates format for lines
            for wire in wires:
                if wire['coordinates']:
                    # Convert GeoJSON coordinates [[lon,lat]] to Leaflet format [[lat,lon]]
                    wire['coordinates'] = [[coord[1], coord[0]] for coord in wire['coordinates']]

            return {
                "data": {
                    "masts": [dict(row) for row in masts],
                    "trees": [dict(row) for row in trees],
                    "buildings": [dict(row) for row in buildings],
                    "vegetation": [dict(row) for row in vegetation],
                    "wires": [dict(row) for row in wires]
                },
                "filters": {
                    "chunks": list(set([row['chunk'] for row in masts + trees + buildings + vegetation + wires])),
                    "classes": ["masts", "trees", "buildings", "other_vegetation", "wires"]
                }
            }

    except Exception as e:
        logger.error(f"Database query error: {e}")
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        conn.close()

@app.get("/api/health")
async def health_check():
    """Health check endpoint"""
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT 1")
            return {"status": "healthy", "database": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "database": "error", "error": str(e)}
    finally:
        conn.close()

@app.get("/api/stats")
async def get_statistics():
    """Get database statistics"""
    conn = get_db_connection()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cursor:
            cursor.execute("""
                SELECT
                    (SELECT COUNT(*) FROM masts) as mast_count,
                    (SELECT COUNT(*) FROM trees) as tree_count,
                    (SELECT COUNT(*) FROM buildings) as building_count,
                    (SELECT COUNT(*) FROM other_vegetation) as vegetation_count,
                    (SELECT COUNT(*) FROM wires) as wire_count,
                    (SELECT SUM(area_m2) FROM trees) as trees_area,
                    (SELECT SUM(area_m2) FROM buildings) as buildings_area,
                    (SELECT SUM(area_m2) FROM other_vegetation) as vegetation_area,
                    (SELECT SUM(length_m) FROM wires) as wires_length
            """)
            stats = cursor.fetchone()
            return dict(stats)
    except Exception as e:
        logger.error(f"Statistics query error: {e}")
        raise HTTPException(status_code=500, detail=f"Statistics error: {str(e)}")
    finally:
        conn.close()

if __name__ == "__main__":
    print("🗄️ Starting PostGIS LiDAR Visualization Server...")
    print("📍 Database: PostGIS with UTM Zone 29N (EPSG:29180)")
    print("🔗 Access: http://localhost:8000")

    uvicorn.run(
        "lidar_postgis_server:app",
        host="0.0.0.0",
        port=8000,
        reload=True
    )