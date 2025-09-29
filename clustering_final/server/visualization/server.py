#!/usr/bin/env python3
"""
Optimized LiDAR Clustering Visualization Server
FastAPI server that uses organized data structure for improved performance
Designed for server deployment with centralized data folder
"""

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
import json
import glob
import os
from typing import List, Dict, Any
import pyproj
from pathlib import Path
import uvicorn
import time

app = FastAPI(
    title="LiDAR Clustering Server Visualization",
    description="Optimized visualization server with organized data structure",
    version="2.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Coordinate conversion setup for Morocco region
UTM_29N = pyproj.CRS("EPSG:32629")  # UTM Zone 29N
WGS84 = pyproj.CRS("EPSG:4326")    # WGS84 lat/lon
transformer = pyproj.Transformer.from_crs(UTM_29N, WGS84, always_xy=True)

# Data directory configuration
DATA_DIR = "./data_new"

def convert_utm_to_wgs84(utm_x: float, utm_y: float) -> tuple:
    """Convert UTM Zone 29N coordinates to WGS84 lat/lon"""
    try:
        lon, lat = transformer.transform(utm_x, utm_y)
        return lat, lon
    except Exception as e:
        print(f"Conversion error for UTM ({utm_x}, {utm_y}): {e}")
        return None, None

def load_centroids_data():
    """Load all centroid data from organized data structure"""
    centroids_data = {}
    centroids_dir = f"{DATA_DIR}/centroids"

    if not os.path.exists(centroids_dir):
        return {}

    json_files = glob.glob(f"{centroids_dir}/*.json")

    for json_file in json_files:
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)

            # Extract chunk and class from filename
            filename = os.path.basename(json_file)
            parts = filename.replace('.json', '').split('_')

            if len(parts) >= 2:
                chunk = parts[0] + '_' + parts[1]  # e.g., chunk_1
                class_name = '_'.join(parts[2:]).replace('_centroids', '')

                key = f"{chunk}_{class_name}"

                # Convert UTM centroids to WGS84
                converted_centroids = []
                for centroid in data.get('centroids', []):
                    utm_x = centroid.get('centroid_x')
                    utm_y = centroid.get('centroid_y')

                    if utm_x and utm_y:
                        lat, lon = convert_utm_to_wgs84(utm_x, utm_y)
                        if lat and lon:
                            centroid_data = {
                                'object_id': centroid.get('object_id'),
                                'lat': lat,
                                'lon': lon,
                                'utm_x': utm_x,
                                'utm_y': utm_y,
                                'utm_z': centroid.get('centroid_z'),
                                'point_count': centroid.get('point_count', 0),
                                'class': class_name,
                                'chunk': chunk,
                                'type': 'centroid'
                            }

                            # Add enhanced mast metadata if available
                            if 'relative_height_m' in centroid:
                                centroid_data.update({
                                    'relative_height_m': centroid.get('relative_height_m'),
                                    'point_density': centroid.get('point_density'),
                                    'quality_score': centroid.get('quality_score'),
                                    'validation_status': centroid.get('validation_status'),
                                    'is_clean': True
                                })
                            else:
                                centroid_data['is_clean'] = False

                            converted_centroids.append(centroid_data)

                if converted_centroids:
                    centroids_data[key] = converted_centroids

        except Exception as e:
            print(f"Error loading {json_file}: {e}")
            continue

    return centroids_data

def load_polygon_data():
    """Load all polygon data from organized structure"""
    polygons_data = {}

    # Load from each polygon category
    categories = ['trees', 'buildings', 'vegetation']

    for category in categories:
        polygon_dir = f"{DATA_DIR}/polygons/{category}"

        if not os.path.exists(polygon_dir):
            continue

        geojson_files = glob.glob(f"{polygon_dir}/*.geojson")

        for geojson_file in geojson_files:
            try:
                with open(geojson_file, 'r') as f:
                    geojson_data = json.load(f)

                # Extract chunk from filename
                filename = os.path.basename(geojson_file)
                chunk = filename.split('_')[0] + '_' + filename.split('_')[1]  # chunk_1

                key = f"{chunk}_{category}"

                # Process polygon features
                converted_polygons = []
                for feature in geojson_data.get('features', []):
                    if feature.get('geometry', {}).get('type') == 'Polygon':
                        coordinates = feature['geometry']['coordinates'][0]  # Get exterior ring
                        converted_coords = []

                        for coord in coordinates:
                            x, y = coord[0], coord[1]

                            # Detect coordinate system and convert if needed
                            if -180 <= x <= 180 and -90 <= y <= 90:
                                # Already WGS84
                                if abs(x) > abs(y) and x > 30:
                                    lat, lon = x, y
                                else:
                                    lon, lat = x, y
                            else:
                                # UTM, convert to WGS84
                                lat, lon = convert_utm_to_wgs84(x, y)

                            if lat and lon:
                                converted_coords.append([lat, lon])

                        if len(converted_coords) >= 3:  # Valid polygon
                            converted_polygons.append({
                                'polygon_id': feature.get('properties', {}).get('polygon_id'),
                                'coordinates': [converted_coords],
                                'area_m2': feature.get('properties', {}).get('area_m2', 0),
                                'perimeter_m': feature.get('properties', {}).get('perimeter_m', 0),
                                'point_count': feature.get('properties', {}).get('point_count', 0),
                                'class': category,
                                'chunk': chunk,
                                'type': 'polygon'
                            })

                if converted_polygons:
                    polygons_data[key] = converted_polygons

            except Exception as e:
                print(f"Error loading {geojson_file}: {e}")
                continue

    return polygons_data

def load_lines_data():
    """Load all line data from organized structure"""
    lines_data = {}

    lines_dir = f"{DATA_DIR}/lines/wires"

    if not os.path.exists(lines_dir):
        return {}

    geojson_files = glob.glob(f"{lines_dir}/*.geojson")

    for geojson_file in geojson_files:
        try:
            with open(geojson_file, 'r') as f:
                geojson_data = json.load(f)

            # Extract chunk from filename
            filename = os.path.basename(geojson_file)
            chunk = filename.split('_')[0] + '_' + filename.split('_')[1]  # chunk_1

            key = f"{chunk}_wires"

            # Process line features
            converted_lines = []
            for feature in geojson_data.get('features', []):
                if feature.get('geometry', {}).get('type') == 'LineString':
                    coordinates = feature['geometry']['coordinates']
                    converted_coords = []

                    for coord in coordinates:
                        x, y = coord[0], coord[1]

                        # Detect coordinate system and convert if needed
                        if -180 <= x <= 180 and -90 <= y <= 90:
                            # Already WGS84
                            if abs(x) > abs(y) and x > 30:
                                lat, lon = x, y
                            else:
                                lon, lat = x, y
                        else:
                            # UTM, convert to WGS84
                            lat, lon = convert_utm_to_wgs84(x, y)

                        if lat and lon:
                            converted_coords.append([lat, lon])

                    if len(converted_coords) >= 2:  # Valid line
                        converted_lines.append({
                            'line_id': feature.get('properties', {}).get('line_id'),
                            'coordinates': converted_coords,
                            'length_m': feature.get('properties', {}).get('length_m', 0),
                            'width_m': feature.get('properties', {}).get('width_m', 0),
                            'point_count': feature.get('properties', {}).get('point_count', 0),
                            'class': 'wires',
                            'chunk': chunk,
                            'type': 'line'
                        })

            if converted_lines:
                lines_data[key] = converted_lines

        except Exception as e:
            print(f"Error loading {geojson_file}: {e}")
            continue

    return lines_data

@app.get("/")
async def root():
    """Main map visualization page with organized data loading"""
    return HTMLResponse(content="""
<!DOCTYPE html>
<html>
<head>
    <title>LiDAR Server Visualization</title>
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
        <h1>🏗️ LiDAR Server Visualization</h1>
        <p>Optimized server deployment with organized data structure - Morocco Region</p>
    </div>

    <div class="controls">
        <div class="control-group">
            <label for="classFilter">Filter by Class:</label>
            <select id="classFilter"><option value="all">All Classes</option></select>
        </div>
        <div class="control-group">
            <label for="chunkFilter">Filter by Chunk:</label>
            <select id="chunkFilter"><option value="all">All Chunks</option></select>
        </div>
        <div class="control-group">
            <button onclick="loadData()">🔄 Refresh Data</button>
            <button onclick="fitMapToData()">🎯 Fit to Data</button>
        </div>
        <div class="stats" id="stats">Loading organized data...</div>
    </div>

    <div id="map"></div>

    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
    <script>
        let map;
        let allData = {centroids: [], polygons: [], lines: []};
        let markers = []; let polygons = []; let lines = [];
        let markerGroup; let polygonGroup; let lineGroup;

        const classColors = {
            '2_12_Masts': '#DC143C', '5_12_Masts': '#DC143C', '12_Masts': '#DC143C', '3_Masts': '#DC143C',
            '2_7_Trees': '#228B22', '5_7_Trees': '#228B22', '7_Trees': '#228B22', 'trees': '#228B22',
            'buildings': '#8B4513', '6_Buildings': '#8B4513',
            'vegetation': '#90EE90', '8_OtherVegetation': '#90EE90',
            'wires': '#FF6600', '11_Wires': '#FF6600'
        };

        function initMap() {
            map = L.map('map').setView([34.0209, -6.8416], 13);
            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                attribution: '© OpenStreetMap | Optimized Server Visualization'
            }).addTo(map);

            markerGroup = L.layerGroup().addTo(map);
            polygonGroup = L.layerGroup().addTo(map);
            lineGroup = L.layerGroup().addTo(map);

            loadData();
        }

        async function loadData() {
            try {
                document.getElementById('stats').textContent = 'Loading from organized data structure...';

                const response = await fetch('/api/data');
                const result = await response.json();

                allData = {centroids: [], polygons: [], lines: []};
                const classes = new Set();
                const chunks = new Set();

                // Process all data types
                Object.entries(result.centroids || {}).forEach(([key, centroids]) => {
                    centroids.forEach(centroid => {
                        allData.centroids.push(centroid);
                        classes.add(centroid.class);
                        chunks.add(centroid.chunk);
                    });
                });

                Object.entries(result.polygons || {}).forEach(([key, polygonList]) => {
                    polygonList.forEach(polygon => {
                        allData.polygons.push(polygon);
                        classes.add(polygon.class);
                        chunks.add(polygon.chunk);
                    });
                });

                Object.entries(result.lines || {}).forEach(([key, lineList]) => {
                    lineList.forEach(line => {
                        allData.lines.push(line);
                        classes.add(line.class);
                        chunks.add(line.chunk);
                    });
                });

                displayMarkers(allData.centroids);
                displayPolygons(allData.polygons);
                displayLines(allData.lines);

                updateStats(allData);
                updateFilters(Array.from(classes), Array.from(chunks));

                setTimeout(() => fitMapToData(), 1000);
            } catch (error) {
                console.error('Error loading data:', error);
                document.getElementById('stats').textContent = 'Error loading organized data';
            }
        }

        function displayMarkers(data) {
            markerGroup.clearLayers();
            markers = [];

            data.forEach(centroid => {
                const color = classColors[centroid.class] || '#DC143C';
                const marker = L.circleMarker([centroid.lat, centroid.lon], {
                    radius: 8, fillColor: color, color: '#ffffff',
                    weight: 2, opacity: 1, fillOpacity: 0.8
                });

                let popupContent = `
                    <div class="popup-title">${centroid.class} #${centroid.object_id}</div>
                    <div class="popup-info">
                        <strong>Points:</strong> ${centroid.point_count.toLocaleString()}<br>
                        <strong>Chunk:</strong> ${centroid.chunk}<br>
                        <strong>Height:</strong> ${centroid.utm_z?.toFixed(2)}m
                `;

                if (centroid.is_clean && centroid.quality_score !== undefined) {
                    popupContent += `<br><strong>🧹 Enhanced Data:</strong><br>
                        <strong>Quality:</strong> ${centroid.quality_score.toFixed(2)}/1.0<br>
                        <strong>Status:</strong> <span style="color: green;">${centroid.validation_status}</span>`;
                }

                popupContent += `</div>`;
                marker.bindPopup(popupContent);
                marker.addTo(markerGroup);
                markers.push(marker);
            });
        }

        function displayPolygons(polygonData) {
            polygonGroup.clearLayers();
            polygons = [];

            polygonData.forEach(polygonItem => {
                const color = classColors[polygonItem.class] || '#8B4513';
                const coords = polygonItem.coordinates[0];

                const polygon = L.polygon(coords, {
                    fillColor: color, fillOpacity: 0.6, color: '#333333', weight: 2
                });

                const popupContent = `
                    <div class="popup-title">${polygonItem.class} #${polygonItem.polygon_id}</div>
                    <div class="popup-info">
                        <strong>Area:</strong> ${polygonItem.area_m2.toLocaleString()} m²<br>
                        <strong>Points:</strong> ${polygonItem.point_count.toLocaleString()}<br>
                        <strong>Chunk:</strong> ${polygonItem.chunk}
                    </div>
                `;

                polygon.bindPopup(popupContent);
                polygon.addTo(polygonGroup);
                polygons.push(polygon);
            });
        }

        function displayLines(lineData) {
            lineGroup.clearLayers();
            lines = [];

            lineData.forEach(lineItem => {
                const color = classColors[lineItem.class] || '#8B4513';
                const coords = lineItem.coordinates;

                const line = L.polyline(coords, {
                    color: color, weight: 4, opacity: 0.8
                });

                const popupContent = `
                    <div class="popup-title">${lineItem.class} #${lineItem.line_id}</div>
                    <div class="popup-info">
                        <strong>Length:</strong> ${lineItem.length_m.toFixed(1)} m<br>
                        <strong>Points:</strong> ${lineItem.point_count.toLocaleString()}<br>
                        <strong>Chunk:</strong> ${lineItem.chunk}
                    </div>
                `;

                line.bindPopup(popupContent);
                line.addTo(lineGroup);
                lines.push(line);
            });
        }

        function updateStats(data) {
            const centroidCount = data.centroids.length;
            const polygonCount = data.polygons.length;
            const lineCount = data.lines.length;

            document.getElementById('stats').innerHTML = `
                <strong>${centroidCount}</strong> centroids |
                <strong>${polygonCount}</strong> polygons |
                <strong>${lineCount}</strong> lines |
                <strong>Organized Data Structure</strong>
            `;
        }

        function updateFilters(classes, chunks) {
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
    """API endpoint to get all organized LiDAR data"""
    try:
        start_time = time.time()

        # Load data from organized structure
        centroids = load_centroids_data()
        polygons = load_polygon_data()
        lines = load_lines_data()

        load_time = time.time() - start_time

        # Calculate statistics
        total_centroids = sum(len(centroids) for centroids in centroids.values())
        total_polygons = sum(len(polygons) for polygons in polygons.values())
        total_lines = sum(len(lines) for lines in lines.values())

        return {
            "centroids": centroids,
            "polygons": polygons,
            "lines": lines,
            "metadata": {
                "load_time_seconds": round(load_time, 2),
                "total_centroids": total_centroids,
                "total_polygons": total_polygons,
                "total_lines": total_lines,
                "total_features": total_centroids + total_polygons + total_lines,
                "data_structure": "organized"
            }
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error loading data: {str(e)}")

@app.get("/api/manifest")
async def get_data_manifest():
    """Get data manifest with file inventory"""
    try:
        manifest_path = f"{DATA_DIR}/manifest.json"
        if os.path.exists(manifest_path):
            with open(manifest_path, 'r') as f:
                return json.load(f)
        else:
            return {"error": "Manifest not found"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error loading manifest: {str(e)}")

@app.get("/api/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "data_directory": os.path.exists(DATA_DIR),
        "server_type": "organized_data_structure"
    }

if __name__ == "__main__":
    print("🏗️ Starting LiDAR Server Visualization...")
    print("📁 Data Structure: Organized server deployment")
    print("📍 Coordinate System: UTM Zone 29N → WGS84")
    print("🌍 Region: Western Morocco")
    print("🔗 Access: http://localhost:8001")

    uvicorn.run(
        "server:app",
        host="0.0.0.0",
        port=8001,
        reload=True,
        log_level="info"
    )