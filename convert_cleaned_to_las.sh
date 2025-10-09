#!/bin/bash

# Convert Cleaned LAZ Instances to LAS Format
set -euo pipefail

SOURCE_DIR="/home/prodair/Desktop/MORIUS5090/clustering/out/cleaned_data"
TARGET_DIR="/home/prodair/Desktop/MORIUS5090/clustering/out/cleaned_data_las"

# Setup target directory
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

log "Starting conversion of cleaned LAZ instances to LAS format"
log "Source: $SOURCE_DIR"
log "Target: $TARGET_DIR"

total_converted=0
total_failed=0

# Process all chunks
for chunk_dir in "$SOURCE_DIR"/chunks/*/; do
    [[ -d "$chunk_dir" ]] || continue

    chunk_name=$(basename "$chunk_dir")
    log "Processing chunk: $chunk_name"

    # Create chunk directory in target
    target_chunk_dir="$TARGET_DIR/chunks/$chunk_name"
    mkdir -p "$target_chunk_dir"

    # Process all classes in chunk
    for class_dir in "$chunk_dir"/*/; do
        [[ -d "$class_dir" ]] || continue

        class_name=$(basename "$class_dir")
        log "  Converting class: $class_name"

        # Create class directory in target
        target_class_dir="$target_chunk_dir/$class_name"
        mkdir -p "$target_class_dir"

        # Convert all LAZ files to LAS
        class_converted=0
        class_failed=0

        for laz_file in "$class_dir"/*.laz; do
            [[ -f "$laz_file" ]] || continue

            # Generate corresponding LAS filename
            laz_basename=$(basename "$laz_file" .laz)
            las_file="$target_class_dir/${laz_basename}.las"

            # Convert using PDAL
            if pdal translate "$laz_file" "$las_file" --writers.las.compression=false 2>/dev/null; then
                ((class_converted++))
                ((total_converted++))
            else
                log "    ERROR: Failed to convert $(basename "$laz_file")"
                ((class_failed++))
                ((total_failed++))
            fi
        done

        # Copy cleaning summary if exists
        if [[ -f "$class_dir/cleaning_summary.json" ]]; then
            cp "$class_dir/cleaning_summary.json" "$target_class_dir/"
        fi

        log "    -> Converted: $class_converted, Failed: $class_failed"
    done
done

# Copy main cleaning report
if [[ -f "$SOURCE_DIR/cleaning_report.json" ]]; then
    cp "$SOURCE_DIR/cleaning_report.json" "$TARGET_DIR/"
fi

# Create conversion report
cat > "$TARGET_DIR/conversion_report.json" << EOF
{
  "conversion_summary": {
    "source_directory": "$SOURCE_DIR",
    "target_directory": "$TARGET_DIR",
    "total_converted": $total_converted,
    "total_failed": $total_failed,
    "conversion_rate": "$(echo "scale=1; $total_converted*100/($total_converted+$total_failed)" | bc -l)%",
    "format": "LAZ to LAS conversion"
  },
  "processing_metadata": {
    "generated_at": "$(date -Iseconds)",
    "generator": "convert_cleaned_to_las.sh",
    "pdal_command": "pdal translate input.laz output.las --writers.las.compression=false"
  }
}
EOF

log "Conversion completed!"
log "Total converted: $total_converted"
log "Total failed: $total_failed"
log "Success rate: $(echo "scale=1; $total_converted*100/($total_converted+$total_failed)" | bc -l)%"
log "Output directory: $TARGET_DIR"

# Show final structure
log ""
log "Final directory structure:"
find "$TARGET_DIR" -name "*.las" | head -10
echo "..."
log "Total LAS files created: $(find "$TARGET_DIR" -name "*.las" | wc -l)"