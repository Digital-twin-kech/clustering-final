#!/bin/bash
# Start the LiDAR visualization server with data_new_2 dataset

echo "🚀 Starting LiDAR Visualization Server"
echo "========================================"
echo "📂 Data source: ../data_new_2 (Berkan dataset)"
echo "📊 Dataset: 9 chunks (chunk_9 to chunk_17)"
echo "🌐 Server will be available at: http://localhost:8000"
echo "========================================"
echo ""

# Change to server directory
cd "$(dirname "$0")"

# Check if data directory exists
if [ ! -d "../data_new_2" ]; then
    echo "❌ Error: Data directory '../data_new_2' not found!"
    echo "   Expected path: /home/prodair/Desktop/MORIUS5090/clustering/clustering_final/server/data_new_2"
    exit 1
fi

echo "✅ Data directory found"
echo ""

# Check Python dependencies
python3 -c "import fastapi, uvicorn, pyproj" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "⚠️  Installing required Python packages..."
    pip3 install fastapi uvicorn pyproj --user
fi

echo "🔄 Starting server..."
echo ""

# Start the server
python3 -m uvicorn server:app --host 0.0.0.0 --port 8000 --reload
