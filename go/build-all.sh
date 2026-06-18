#!/bin/bash
# Build BV-BRC CLI tools for all platforms

set -e

cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
export VERSION

echo "========================================"
echo "Building BV-BRC CLI Tools v${VERSION}"
echo "========================================"
echo ""

# Build for all platforms
./build-macos.sh
echo ""
./build-linux.sh
echo ""
./build-windows.sh

echo ""
echo "========================================"
echo "All builds complete!"
echo "========================================"
echo ""
echo "Distribution packages in dist/:"
echo ""
ls -lh dist/*.tar.gz dist/*.deb 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
echo ""
echo "Total commands: 42"
echo "Platforms: macOS (Intel, Apple Silicon), Linux (x86_64, ARM64), Windows (x64, ARM64)"
