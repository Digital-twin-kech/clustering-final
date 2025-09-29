#!/usr/bin/env python3

"""
FastAPI Map Visualization Server for LiDAR Clustering Results
===========================================================
Visualizes clustering centroids on an interactive map with proper coordinate conversion
UTM Zone 29N → WGS84 (lat/lon) for web mapping
"""

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
import json
import glob
import os
from typing import List, Dict, Any
import pyproj
from pathlib import Path
import uvicorn

app = FastAPI(
    title="LiDAR Clustering Map Visualizer",
    description="Interactive map visualization of LiDAR clustering results",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for development
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Coordinate conversion setup
# Source: UTM Zone 29N (Morocco region)
# Target: WGS84 (lat/lon for web maps)
UTM_29N = pyproj.CRS("EPSG:32629")  # UTM Zone 29N
WGS84 = pyproj.CRS("EPSG:4326")    # WGS84 lat/lon

# Create transformer for UTM → WGS84 conversion
transformer = pyproj.Transformer.from_crs(UTM_29N, WGS84, always_xy=True)

def convert_utm_to_wgs84(utm_x: float, utm_y: float) -> tuple:
    """Convert UTM Zone 29N coordinates to WGS84 lat/lon"""
    try:
        lon, lat = transformer.transform(utm_x, utm_y)
        return lat, lon
    except Exception as e:
        print(f"Conversion error for UTM ({utm_x}, {utm_y}): {e}")
        return None, None

def load_clustering_results(base_path: str = "/home/prodair/Desktop/MORIUS5090/clustering/clustering_final/outlast/chunks") -> Dict[str, Dict]:
    """Load all clustering results from JSON files (both centroids and polygons)"""
    results = {"centroids": {}, "polygons": {}}

    try:
        # Find all centroid JSON files (including clean masts)
        json_pattern = f"{base_path}/**/centroids/*_centroids.json"
        centroid_files = glob.glob(json_pattern, recursive=True)

        # Find clean mast files (priority over regular mast files)
        clean_mast_pattern = f"{base_path}/**/centroids/*_Masts_centroids_clean.json"
        clean_mast_files = glob.glob(clean_mast_pattern, recursive=True)

        # Replace regular mast files with clean versions if available
        for clean_file in clean_mast_files:
            regular_file = clean_file.replace('_clean.json', '.json')
            if regular_file in centroid_files:
                centroid_files.remove(regular_file)
            centroid_files.append(clean_file)

        # Find all polygon GeoJSON files
        polygon_pattern = f"{base_path}/**/polygons/*_polygons.geojson"
        polygon_files = glob.glob(polygon_pattern, recursive=True)

        # Find all line GeoJSON files (for wires only, exclude roads and sidewalks)
        line_pattern = f"{base_path}/**/lines/*_lines.geojson"
        all_line_files = glob.glob(line_pattern, recursive=True)

        # Filter out road and sidewalk line files
        line_files = []
        for line_file in all_line_files:
            if not any(excluded in line_file for excluded in ['2_Roads_lines', '3_Sidewalks_lines']):
                line_files.append(line_file)

        print(f"Found {len(centroid_files)} clustering result files, {len(polygon_files)} polygon files, and {len(line_files)} line files")

        # Process centroid files
        for json_file in centroid_files:
            try:
                with open(json_file, 'r') as f:
                    data = json.load(f)

                class_name = data.get('class', 'Unknown')
                chunk_name = data.get('chunk', 'Unknown')
                key = f"{chunk_name}_{class_name}"

                # Convert UTM centroids to WGS84
                converted_centroids = []
                for centroid in data.get('centroids', []):
                    utm_x = centroid.get('centroid_x')
                    utm_y = centroid.get('centroid_y')

                    if utm_x and utm_y:
                        lat, lon = convert_utm_to_wgs84(utm_x, utm_y)
                        if lat and lon:
                            # Base centroid data
                            centroid_data = {
                                'object_id': centroid.get('object_id'),
                                'lat': lat,
                                'lon': lon,
                                'utm_x': utm_x,
                                'utm_y': utm_y,
                                'utm_z': centroid.get('centroid_z'),
                                'point_count': centroid.get('point_count', 0),
                                'class': class_name,
                                'chunk': chunk_name,
                                'class_id': data.get('class_id', 0),
                                'type': 'centroid'
                            }

                            # Add clean mast metadata if available
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
                    results["centroids"][key] = converted_centroids
                    print(f"Loaded {len(converted_centroids)} centroids for {key}")

            except Exception as e:
                print(f"Error loading {json_file}: {e}")
                continue

        # Process polygon files
        for geojson_file in polygon_files:
            try:
                with open(geojson_file, 'r') as f:
                    geojson_data = json.load(f)

                class_name = geojson_data.get('properties', {}).get('class', 'Unknown')
                chunk_name = geojson_data.get('properties', {}).get('chunk', 'Unknown')
                key = f"{chunk_name}_{class_name}"

                # Handle polygon coordinates (detect if already WGS84 or UTM)
                converted_polygons = []
                for feature in geojson_data.get('features', []):
                    if feature.get('geometry', {}).get('type') == 'Polygon':
                        coordinates = feature['geometry']['coordinates'][0]  # Get exterior ring
                        converted_coords = []

                        for coord in coordinates:
                            x, y = coord[0], coord[1]

                            # Detect coordinate system: if x is between -180 and 180, assume WGS84
                            if -180 <= x <= 180 and -90 <= y <= 90:
                                # Already WGS84 - but our data might be [longitude, latitude]
                                # Check if first coordinate is longitude (x) or latitude
                                if abs(x) > abs(y) and x > 30:
                                    # First coordinate is larger and > 30, likely longitude
                                    # Data is [longitude, latitude], swap to [latitude, longitude]
                                    lat, lon = x, y
                                else:
                                    # Data is already [latitude, longitude]
                                    lon, lat = x, y
                            else:
                                # Assume UTM, convert to WGS84
                                lat, lon = convert_utm_to_wgs84(x, y)

                            if lat and lon:
                                converted_coords.append([lat, lon])  # Leaflet uses [lat, lon]

                        if len(converted_coords) >= 3:  # Valid polygon
                            converted_polygons.append({
                                'polygon_id': feature.get('properties', {}).get('polygon_id'),
                                'coordinates': [converted_coords],  # GeoJSON polygon format
                                'area_m2': feature.get('properties', {}).get('area_m2', 0),
                                'perimeter_m': feature.get('properties', {}).get('perimeter_m', 0),
                                'point_count': feature.get('properties', {}).get('point_count', 0),
                                'class': class_name,
                                'chunk': chunk_name,
                                'type': 'polygon'
                            })

                if converted_polygons:
                    results["polygons"][key] = converted_polygons
                    print(f"Loaded {len(converted_polygons)} polygons for {key}")

            except Exception as e:
                print(f"Error loading {geojson_file}: {e}")
                continue

        # Process line files (for wires)
        for geojson_file in line_files:
            try:
                with open(geojson_file, 'r') as f:
                    geojson_data = json.load(f)

                class_name = geojson_data.get('properties', {}).get('class', 'Unknown')
                chunk_name = geojson_data.get('properties', {}).get('chunk', 'Unknown')
                key = f"{chunk_name}_{class_name}"

                # Handle line coordinates (detect if already WGS84 or UTM)
                converted_lines = []
                for feature in geojson_data.get('features', []):
                    if feature.get('geometry', {}).get('type') == 'LineString':
                        coordinates = feature['geometry']['coordinates']  # Get line coordinates
                        converted_coords = []

                        for coord in coordinates:
                            x, y = coord[0], coord[1]

                            # Detect coordinate system: if x is between -180 and 180, assume WGS84
                            if -180 <= x <= 180 and -90 <= y <= 90:
                                # Already WGS84 - but our data might be [longitude, latitude]
                                if abs(x) > abs(y) and x > 30:
                                    # First coordinate is larger and > 30, likely longitude
                                    lat, lon = x, y
                                else:
                                    # Data is already [latitude, longitude]
                                    lon, lat = x, y
                            else:
                                # Assume UTM, convert to WGS84
                                lat, lon = convert_utm_to_wgs84(x, y)

                            if lat and lon:
                                converted_coords.append([lat, lon])  # Leaflet uses [lat, lon]

                        if len(converted_coords) >= 2:  # Valid line (at least 2 points)
                            converted_lines.append({
                                'line_id': feature.get('properties', {}).get('line_id'),
                                'coordinates': converted_coords,  # LineString coordinates
                                'length_m': feature.get('properties', {}).get('length_m', 0),
                                'width_m': feature.get('properties', {}).get('width_m', 0),
                                'point_count': feature.get('properties', {}).get('point_count', 0),
                                'aspect_ratio': feature.get('properties', {}).get('aspect_ratio', 0),
                                'min_height_m': feature.get('properties', {}).get('min_height_m', 0),
                                'max_height_m': feature.get('properties', {}).get('max_height_m', 0),
                                'avg_height_m': feature.get('properties', {}).get('avg_height_m', 0),
                                'class': class_name,
                                'chunk': chunk_name,
                                'type': 'line'
                            })

                if converted_lines:
                    if "lines" not in results:
                        results["lines"] = {}
                    results["lines"][key] = converted_lines
                    print(f"Loaded {len(converted_lines)} lines for {key}")

            except Exception as e:
                print(f"Error loading {geojson_file}: {e}")
                continue

    except Exception as e:
        print(f"Error scanning for JSON files: {e}")

    return results

@app.get("/")
async def root():
    """Main map visualization page"""
    return HTMLResponse(content="""
<!DOCTYPE html>
<html>
<head>
    <title>LiDAR Clustering Map Visualization</title>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <!-- Leaflet CSS -->
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />

    <style>
        body {
            margin: 0;
            padding: 0;
            font-family: Arial, sans-serif;
            background-color: #f0f0f0;
        }

        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            text-align: center;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }

        .header h1 {
            margin: 0;
            font-size: 2.5em;
            font-weight: 300;
        }

        .header p {
            margin: 10px 0 0 0;
            opacity: 0.9;
            font-size: 1.1em;
        }

        .controls {
            background: white;
            padding: 15px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 15px;
        }

        .control-group {
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .control-group label {
            font-weight: bold;
            color: #333;
        }

        select, button {
            padding: 8px 12px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 14px;
        }

        button {
            background: #667eea;
            color: white;
            border: none;
            cursor: pointer;
            transition: background 0.3s;
        }

        button:hover {
            background: #5a67d8;
        }

        .stats {
            background: rgba(255,255,255,0.9);
            padding: 10px;
            border-radius: 5px;
            font-size: 14px;
            color: #333;
        }

        #map {
            height: 80vh;
            width: 100%;
            border: 2px solid #ddd;
        }

        .leaflet-popup-content {
            font-family: Arial, sans-serif;
        }

        .popup-title {
            font-weight: bold;
            font-size: 16px;
            color: #333;
            margin-bottom: 8px;
        }

        .popup-info {
            font-size: 14px;
            line-height: 1.4;
        }

        .coordinate-info {
            background: #f8f9fa;
            padding: 8px;
            border-radius: 4px;
            margin-top: 8px;
            font-size: 12px;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>🗺️ LiDAR Clustering Map Visualizer</h1>
        <p>Interactive visualization of LiDAR object detection results - UTM Zone 29N (Morocco)</p>
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

        <div class="stats" id="stats">
            Loading clustering data...
        </div>
    </div>

    <div id="map"></div>

    <!-- Leaflet JavaScript -->
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>

    <script>
        // Global variables
        let map;
        let allData = {centroids: [], polygons: [], lines: []};
        let markers = [];
        let polygons = [];
        let lines = [];
        let markerGroup;
        let polygonGroup;
        let lineGroup;

        // Class colors for different object types
        const classColors = {
            // '2': '#2F2F2F',     // Roads - Removed from visualization
            // '3': '#808080',     // Sidewalks - Removed from visualization
            '6': '#8B4513',     // Buildings - Saddle Brown
            '7': '#228B22',     // Trees - Green
            '8': '#90EE90',     // OtherVegetation - Light Green
            '10': '#FF4500',    // TrafficSigns - Orange Red
            '11': '#8B4513',    // Wires - Saddle Brown
            '12': '#DC143C',    // Masts - Crimson RED (main focus)
            '13': '#FFD700',    // Pedestrians - Gold
            '15': '#4169E1',    // 2Wheel - Royal Blue
            '16': '#32CD32',    // Mobile4w - Lime Green
            '17': '#800080',    // Stationary4w - Purple
            '40': '#006400',    // TreeTrunks - Dark Green
            '41': '#228B22'     // TreesCombined - Green
        };

        // Initialize map
        function initMap() {
            // Morocco region center (approximate)
            map = L.map('map').setView([34.0209, -6.8416], 13);

            // Add OpenStreetMap tiles
            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                attribution: '© OpenStreetMap contributors | LiDAR Clustering Visualization',
                maxZoom: 19
            }).addTo(map);

            // Create marker, polygon, and line groups
            markerGroup = L.layerGroup().addTo(map);
            polygonGroup = L.layerGroup().addTo(map);
            lineGroup = L.layerGroup().addTo(map);

            // Load initial data
            loadData();
        }

        // Load clustering data from API
        async function loadData() {
            try {
                document.getElementById('stats').textContent = 'Loading clustering data...';

                const response = await fetch('http://localhost:8001/api/clustering-data');
                const result = await response.json();

                allData = {centroids: [], polygons: [], lines: []};
                const classes = new Set();
                const chunks = new Set();

                // Process centroid data
                if (result.data && result.data.centroids) {
                    Object.entries(result.data.centroids).forEach(([key, centroids]) => {
                        centroids.forEach(centroid => {
                            allData.centroids.push(centroid);
                            classes.add(centroid.class);
                            chunks.add(centroid.chunk);
                        });
                    });
                }

                // Process polygon data
                if (result.data && result.data.polygons) {
                    Object.entries(result.data.polygons).forEach(([key, polygonList]) => {
                        polygonList.forEach(polygon => {
                            allData.polygons.push(polygon);
                            classes.add(polygon.class);
                            chunks.add(polygon.chunk);
                        });
                    });
                }

                // Process line data (for wires)
                if (result.data && result.data.lines) {
                    Object.entries(result.data.lines).forEach(([key, lineList]) => {
                        lineList.forEach(line => {
                            allData.lines.push(line);
                            classes.add(line.class);
                            chunks.add(line.chunk);
                        });
                    });
                }

                console.log('Loaded data:', allData);

                // Update filter dropdowns
                updateFilters(Array.from(classes), Array.from(chunks));

                // Display data on map
                displayMarkers(allData.centroids);
                displayPolygons(allData.polygons);
                displayLines(allData.lines);

                // Update stats
                updateStats(allData);

                // Fit map to data bounds if we have data
                if (allData.centroids.length > 0 || allData.polygons.length > 0 || allData.lines.length > 0) {
                    console.log('Auto-focusing map to data...');
                    console.log(`Found ${allData.centroids.length} centroids, ${allData.polygons.length} polygons, and ${allData.lines.length} lines`);

                    // Delay to ensure all features are rendered
                    setTimeout(() => {
                        fitMapToData();
                        console.log('Map fitted to data bounds');
                    }, 1000);
                }

            } catch (error) {
                console.error('Error loading data:', error);
                document.getElementById('stats').textContent = 'Error loading data. Check server connection.';
            }
        }

        // Update filter dropdowns
        function updateFilters(classes, chunks) {
            const classFilter = document.getElementById('classFilter');
            const chunkFilter = document.getElementById('chunkFilter');

            // Clear existing options (except "All")
            classFilter.innerHTML = '<option value="all">All Classes</option>';
            chunkFilter.innerHTML = '<option value="all">All Chunks</option>';

            // Add class options
            classes.sort().forEach(className => {
                const option = document.createElement('option');
                option.value = className;
                option.textContent = className;
                classFilter.appendChild(option);
            });

            // Add chunk options
            chunks.sort().forEach(chunkName => {
                const option = document.createElement('option');
                option.value = chunkName;
                option.textContent = chunkName;
                chunkFilter.appendChild(option);
            });

            // Add event listeners
            classFilter.onchange = applyFilters;
            chunkFilter.onchange = applyFilters;
        }

        // Apply filters and update display
        function applyFilters() {
            const classFilter = document.getElementById('classFilter').value;
            const chunkFilter = document.getElementById('chunkFilter').value;

            let filteredData = allData;

            if (classFilter !== 'all') {
                filteredData = filteredData.filter(item => item.class === classFilter);
            }

            if (chunkFilter !== 'all') {
                filteredData = filteredData.filter(item => item.chunk === chunkFilter);
            }

            displayMarkers(filteredData);
            updateStats(filteredData);
        }

        // Display markers on map
        function displayMarkers(data) {
            // Clear existing markers
            markerGroup.clearLayers();
            markers = [];

            data.forEach(centroid => {
                const classId = centroid.class_id.toString();
                const color = classColors[classId] || '#DC143C'; // Default to red

                // Create circle marker
                const marker = L.circleMarker([centroid.lat, centroid.lon], {
                    radius: 8,
                    fillColor: color,
                    color: '#ffffff',
                    weight: 2,
                    opacity: 1,
                    fillOpacity: 0.8
                });

                // Create popup content with clean mast metadata
                let popupContent = `
                    <div class="popup-title">${centroid.class} #${centroid.object_id}</div>
                    <div class="popup-info">
                        <strong>Points:</strong> ${centroid.point_count.toLocaleString()}<br>
                        <strong>Chunk:</strong> ${centroid.chunk}<br>
                        <strong>Height:</strong> ${centroid.utm_z?.toFixed(2)}m
                `;

                // Add clean mast metadata if available
                if (centroid.is_clean && centroid.quality_score !== undefined) {
                    popupContent += `<br><strong>🧹 Clean Mast Data:</strong><br>
                        <strong>Quality Score:</strong> ${centroid.quality_score.toFixed(2)}/1.0<br>
                        <strong>Relative Height:</strong> ${centroid.relative_height_m?.toFixed(1)}m<br>
                        <strong>Point Density:</strong> ${centroid.point_density?.toFixed(1)} pts/m<br>
                        <strong>Status:</strong> <span style="color: green;">${centroid.validation_status}</span>`;
                } else if (centroid.class === '12_Masts') {
                    popupContent += `<br><span style="color: orange;">⚠️ Original mast data (not cleaned)</span>`;
                }

                popupContent += `
                    </div>
                    <div class="coordinate-info">
                        <strong>WGS84:</strong> ${centroid.lat.toFixed(6)}, ${centroid.lon.toFixed(6)}<br>
                        <strong>UTM 29N:</strong> ${centroid.utm_x.toFixed(1)}, ${centroid.utm_y.toFixed(1)}
                    </div>
                `;

                marker.bindPopup(popupContent);
                marker.addTo(markerGroup);
                markers.push(marker);
            });
        }

        // Display polygons on map
        function displayPolygons(polygonData) {
            console.log('displayPolygons called with:', polygonData);

            // Clear existing polygons
            polygonGroup.clearLayers();
            polygons = [];

            if (!polygonData || polygonData.length === 0) {
                console.log('No polygon data to display');
                return;
            }

            polygonData.forEach((polygonItem, index) => {
                console.log(`Processing polygon ${index}:`, polygonItem);

                const classId = polygonItem.class.split('_')[0]; // Extract class ID (e.g., '6' from '6_Buildings')
                const color = classColors[classId] || '#8B4513'; // Default to brown

                console.log(`Using color ${color} for class ${polygonItem.class}`);

                try {
                    // Create Leaflet polygon - coordinates should be [lat, lon] pairs
                    const coords = polygonItem.coordinates[0]; // Get the outer ring
                    console.log('Polygon coordinates:', coords.slice(0, 3)); // Show first 3 points

                    const polygon = L.polygon(coords, {
                        fillColor: color,
                        fillOpacity: 0.6,
                        color: '#333333',
                        weight: 2,
                        opacity: 1.0
                    });

                    // Create popup content
                    const popupContent = `
                        <div class="popup-title">${polygonItem.class} #${polygonItem.polygon_id}</div>
                        <div class="popup-info">
                            <strong>Area:</strong> ${polygonItem.area_m2.toLocaleString()} m²<br>
                            <strong>Perimeter:</strong> ${polygonItem.perimeter_m.toFixed(1)} m<br>
                            <strong>Points:</strong> ${polygonItem.point_count.toLocaleString()}<br>
                            <strong>Chunk:</strong> ${polygonItem.chunk}
                        </div>
                    `;

                    polygon.bindPopup(popupContent);
                    polygon.addTo(polygonGroup);
                    polygons.push(polygon);

                    console.log(`Successfully added polygon ${index} to map`);
                } catch (error) {
                    console.error(`Error creating polygon ${index}:`, error);
                }
            });

            console.log(`Total polygons added: ${polygons.length}`);
        }

        // Display lines on map (for wires)
        function displayLines(lineData) {
            console.log('displayLines called with:', lineData);

            // Clear existing lines
            lineGroup.clearLayers();
            lines = [];

            if (!lineData || lineData.length === 0) {
                console.log('No line data to display');
                return;
            }

            lineData.forEach((lineItem, index) => {
                console.log(`Processing line ${index}:`, lineItem);

                const classId = lineItem.class.split('_')[0]; // Extract class ID (e.g., '11' from '11_Wires')
                const color = classColors[classId] || '#8B4513'; // Default to saddle brown for wires

                console.log(`Using color ${color} for class ${lineItem.class}`);

                try {
                    // Create Leaflet polyline - coordinates should be [lat, lon] pairs
                    const coords = lineItem.coordinates; // Line coordinates
                    console.log('Line coordinates:', coords.slice(0, 3)); // Show first 3 points

                    const line = L.polyline(coords, {
                        color: color,
                        weight: 4,
                        opacity: 0.8
                    });

                    // Create popup content
                    const popupContent = `
                        <div class="popup-title">${lineItem.class} #${lineItem.line_id}</div>
                        <div class="popup-info">
                            <strong>Length:</strong> ${lineItem.length_m.toFixed(1)} m<br>
                            <strong>Width:</strong> ${lineItem.width_m.toFixed(1)} m<br>
                            <strong>Points:</strong> ${lineItem.point_count.toLocaleString()}<br>
                            <strong>Height:</strong> ${lineItem.min_height_m.toFixed(1)} - ${lineItem.max_height_m.toFixed(1)} m<br>
                            <strong>Aspect Ratio:</strong> ${lineItem.aspect_ratio.toFixed(1)}:1<br>
                            <strong>Chunk:</strong> ${lineItem.chunk}
                        </div>
                    `;

                    line.bindPopup(popupContent);
                    line.addTo(lineGroup);
                    lines.push(line);

                    console.log(`Successfully added line ${index} to map`);
                } catch (error) {
                    console.error(`Error creating line ${index}:`, error);
                }
            });

            console.log(`Total lines added: ${lines.length}`);
        }

        // Update statistics display
        function updateStats(data) {
            const centroidCount = data.centroids.length;
            const polygonCount = data.polygons.length;
            const lineCount = data.lines.length;

            const totalPoints = data.centroids.reduce((sum, item) => sum + item.point_count, 0);
            const totalArea = data.polygons.reduce((sum, item) => sum + item.area_m2, 0);
            const totalLength = data.lines.reduce((sum, item) => sum + item.length_m, 0);

            const allItems = [...data.centroids, ...data.polygons, ...data.lines];
            const classes = new Set(allItems.map(item => item.class)).size;

            document.getElementById('stats').innerHTML = `
                <strong>${centroidCount}</strong> points |
                <strong>${polygonCount}</strong> polygons |
                <strong>${lineCount}</strong> lines |
                <strong>${totalPoints.toLocaleString()}</strong> total points |
                <strong>${totalArea.toLocaleString()}</strong> m² area |
                <strong>${totalLength.toFixed(1)}</strong> m length |
                <strong>${classes}</strong> classes
            `;
        }

        // Fit map view to show all data points
        function fitMapToData() {
            const allFeatures = [...markers, ...polygons];
            console.log(`Fitting map to ${allFeatures.length} features (${markers.length} markers + ${polygons.length} polygons)`);

            if (allFeatures.length === 0) {
                console.log('No features to fit map to');
                return;
            }

            const group = new L.featureGroup(allFeatures);
            const bounds = group.getBounds();
            console.log('Calculated bounds:', bounds);

            map.fitBounds(bounds.pad(0.1));
            console.log('Map view updated to fit bounds');
        }

        // Initialize map when page loads
        document.addEventListener('DOMContentLoaded', initMap);
    </script>
</body>
</html>
    """)

@app.get("/api/clustering-data")
async def get_clustering_data():
    """API endpoint to get all clustering results (centroids and polygons)"""
    try:
        results = load_clustering_results()

        if not results or (not results.get("centroids") and not results.get("polygons")):
            return {"message": "No clustering data found", "data": {"centroids": {}, "polygons": {}}}

        # Add summary statistics
        total_centroids = sum(len(centroids) for centroids in results.get("centroids", {}).values())
        total_polygons = sum(len(polygons) for polygons in results.get("polygons", {}).values())

        total_centroid_points = sum(
            sum(centroid.get('point_count', 0) for centroid in centroids)
            for centroids in results.get("centroids", {}).values()
        )

        total_polygon_area = sum(
            sum(polygon.get('area_m2', 0) for polygon in polygons)
            for polygons in results.get("polygons", {}).values()
        )

        return {
            "summary": {
                "total_centroid_files": len(results.get("centroids", {})),
                "total_polygon_files": len(results.get("polygons", {})),
                "total_centroids": total_centroids,
                "total_polygons": total_polygons,
                "total_centroid_points": total_centroid_points,
                "total_polygon_area_m2": total_polygon_area
            },
            "data": results
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error loading clustering data: {str(e)}")

@app.get("/test")
async def test_map():
    """Simple test map page"""
    try:
        with open("/home/prodair/Desktop/MORIUS5090/clustering/clustering_final/test_map.html", "r") as f:
            content = f.read()
        return HTMLResponse(content=content)
    except FileNotFoundError:
        return HTMLResponse(content="<h1>Test file not found</h1>")

@app.get("/api/classes")
async def get_available_classes():
    """Get list of available classes"""
    try:
        results = load_clustering_results()
        classes = set()

        for centroids in results.values():
            for centroid in centroids:
                classes.add(centroid.get('class', 'Unknown'))

        return {"classes": sorted(list(classes))}

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error getting classes: {str(e)}")

if __name__ == "__main__":
    print("🗺️  Starting LiDAR Clustering Map Visualizer...")
    print("📍 Coordinate System: UTM Zone 29N → WGS84")
    print("🌍 Region: Western Morocco")
    print("🔗 Access: http://localhost:8001")

    uvicorn.run(
        "map_server:app",
        host="0.0.0.0",
        port=8001,
        reload=True,
        log_level="info"
    )