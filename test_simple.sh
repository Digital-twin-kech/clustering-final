#!/bin/bash
set -x
JOB_DIR="$1"
echo "Testing: $JOB_DIR"
echo "Files:"
ls "$JOB_DIR/chunks/"*.laz
echo "Loop test:"
for f in "$JOB_DIR/chunks/"*.laz; do
    echo "File: $f"
    break
done
echo "Done"
