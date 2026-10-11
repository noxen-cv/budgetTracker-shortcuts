#!/bin/bash
# build.sh — Compile all Cherri source files to .shortcut binaries
# Usage: ./build.sh [filename]
#   ./build.sh                  — build all .cherri files in src/
#   ./build.sh track-expenses   — build only src/track-expenses.cherri

set -euo pipefail

SRC_DIR="src"
BUILD_DIR="build"

mkdir -p "$BUILD_DIR"

# Check if cherri is installed
if ! command -v cherri &> /dev/null; then
    echo "Error: cherri compiler not found."
    echo "Install with: brew tap electrikmilk/cherri && brew install cherri"
    exit 1
fi

build_file() {
    local src_file="$1"
    local basename
    basename=$(basename "$src_file" .cherri)
    
    echo "Building: $src_file"
    cherri "$src_file" -o="${BUILD_DIR}/${basename}.shortcut"
    
    echo "  → ${BUILD_DIR}/${basename}.shortcut"
}

if [ $# -eq 1 ]; then
    # Build a specific file
    target="${SRC_DIR}/${1}.cherri"
    if [ ! -f "$target" ]; then
        # Try with .cherri extension already included
        target="${SRC_DIR}/${1}"
    fi
    if [ ! -f "$target" ]; then
        echo "Error: Source file not found: $target"
        exit 1
    fi
    build_file "$target"
else
    # Build all .cherri files
    count=0
    for src_file in "${SRC_DIR}"/*.cherri; do
        [ -f "$src_file" ] || continue
        build_file "$src_file"
        ((count++))
    done
    echo ""
    echo "Done. Built ${count} shortcut(s) → ${BUILD_DIR}/"
fi
