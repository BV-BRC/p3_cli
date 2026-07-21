#!/bin/bash
# Build script for BV-BRC CLI tools - macOS installer

set -e

GO=/home/olson/P3/go-1.25.6/go/bin/go
VERSION="${VERSION:-1.0.0}"
OUTPUT_DIR="dist"
PKG_ID="org.bvbrc.cli"

cd "$(dirname "$0")"

# Get list of all commands
COMMANDS=$(ls -d cmd/p3-*/ | xargs -n1 basename)

echo "Building BV-BRC CLI tools v${VERSION}"
echo "Commands to build: $(echo $COMMANDS | wc -w)"

# Clean and create output directories
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/darwin-amd64/bin"
mkdir -p "$OUTPUT_DIR/darwin-arm64/bin"
mkdir -p "$OUTPUT_DIR/darwin-universal/bin"

# Build for macOS Intel (amd64)
echo ""
echo "Building for macOS Intel (amd64)..."
for cmd in $COMMANDS; do
    echo "  $cmd"
    GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 $GO build -buildvcs=false -ldflags="-s -w" -o "$OUTPUT_DIR/darwin-amd64/bin/$cmd" "./cmd/$cmd"
done

# Build for macOS Apple Silicon (arm64)
echo ""
echo "Building for macOS Apple Silicon (arm64)..."
for cmd in $COMMANDS; do
    echo "  $cmd"
    GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 $GO build -buildvcs=false -ldflags="-s -w" -o "$OUTPUT_DIR/darwin-arm64/bin/$cmd" "./cmd/$cmd"
done

# Create universal binaries using lipo (if available)
if command -v lipo &> /dev/null; then
    echo ""
    echo "Creating universal binaries..."
    for cmd in $COMMANDS; do
        echo "  $cmd"
        lipo -create \
            "$OUTPUT_DIR/darwin-amd64/bin/$cmd" \
            "$OUTPUT_DIR/darwin-arm64/bin/$cmd" \
            -output "$OUTPUT_DIR/darwin-universal/bin/$cmd"
    done
    INSTALL_SRC="$OUTPUT_DIR/darwin-universal"
else
    echo ""
    echo "lipo not available - skipping universal binary creation"
    echo "Will create separate installers for each architecture"
fi

# Create tarball distributions
echo ""
echo "Creating distribution archives..."

cd "$OUTPUT_DIR"

# Intel tarball
tar -czf "bvbrc-cli-${VERSION}-darwin-amd64.tar.gz" -C darwin-amd64 bin
echo "  Created bvbrc-cli-${VERSION}-darwin-amd64.tar.gz"

# ARM64 tarball
tar -czf "bvbrc-cli-${VERSION}-darwin-arm64.tar.gz" -C darwin-arm64 bin
echo "  Created bvbrc-cli-${VERSION}-darwin-arm64.tar.gz"

# Universal tarball (if created)
if [ -d "darwin-universal/bin" ] && [ "$(ls -A darwin-universal/bin)" ]; then
    tar -czf "bvbrc-cli-${VERSION}-darwin-universal.tar.gz" -C darwin-universal bin
    echo "  Created bvbrc-cli-${VERSION}-darwin-universal.tar.gz"
fi

cd ..

echo ""
echo "Build complete!"
echo ""
echo "Distribution files in $OUTPUT_DIR/:"
ls -lh "$OUTPUT_DIR"/*.tar.gz
echo ""
echo "Installation instructions:"
echo "  tar -xzf bvbrc-cli-${VERSION}-darwin-<arch>.tar.gz"
echo "  sudo cp bin/p3-* /usr/local/bin/"
echo ""
echo "Or add the bin directory to your PATH:"
echo "  export PATH=\$PATH:\$(pwd)/bin"
