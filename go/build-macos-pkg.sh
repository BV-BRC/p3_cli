#!/bin/bash
# Build macOS .pkg installer for BV-BRC CLI tools

set -e

GO=/home/olson/P3/go-1.25.6/go/bin/go
VERSION="${VERSION:-1.0.0}"
OUTPUT_DIR="dist"
PKG_ID="org.bvbrc.cli"
INSTALL_LOCATION="/usr/local"

cd "$(dirname "$0")"

# Get list of all commands
COMMANDS=$(ls -d cmd/p3-*/ | xargs -n1 basename)
CMD_COUNT=$(echo $COMMANDS | wc -w)

echo "Building BV-BRC CLI tools v${VERSION} macOS installer"
echo "Commands to build: $CMD_COUNT"

# Function to build pkg for a specific architecture
build_pkg() {
    local ARCH=$1
    local ARCH_NAME=$2

    echo ""
    echo "========================================"
    echo "Building for $ARCH_NAME ($ARCH)..."
    echo "========================================"

    local BUILD_DIR="$OUTPUT_DIR/pkg-build-$ARCH"
    local PAYLOAD_DIR="$BUILD_DIR/payload"
    local SCRIPTS_DIR="$BUILD_DIR/scripts"
    local RESOURCES_DIR="$BUILD_DIR/resources"

    # Clean and create directories
    rm -rf "$BUILD_DIR"
    mkdir -p "$PAYLOAD_DIR/bin"
    mkdir -p "$SCRIPTS_DIR"
    mkdir -p "$RESOURCES_DIR"

    # Build binaries
    echo "Compiling binaries..."
    for cmd in $COMMANDS; do
        echo "  $cmd"
        GOOS=darwin GOARCH=$ARCH CGO_ENABLED=0 $GO build -buildvcs=false -ldflags="-s -w" -o "$PAYLOAD_DIR/bin/$cmd" "./cmd/$cmd"
    done

    # Create postinstall script
    cat > "$SCRIPTS_DIR/postinstall" << 'POSTINSTALL'
#!/bin/bash
# Post-installation script for BV-BRC CLI tools

# Ensure /usr/local/bin is in PATH for common shells
SHELLS=("/etc/profile" "/etc/zprofile")
PATH_LINE='export PATH="/usr/local/bin:$PATH"'

for shell_rc in "${SHELLS[@]}"; do
    if [ -f "$shell_rc" ]; then
        if ! grep -q "/usr/local/bin" "$shell_rc" 2>/dev/null; then
            echo "" >> "$shell_rc"
            echo "# Added by BV-BRC CLI installer" >> "$shell_rc"
            echo "$PATH_LINE" >> "$shell_rc"
        fi
    fi
done

echo "BV-BRC CLI tools installed successfully!"
echo "You may need to restart your terminal or run: source ~/.zshrc"
exit 0
POSTINSTALL
    chmod +x "$SCRIPTS_DIR/postinstall"

    # Create welcome text
    cat > "$RESOURCES_DIR/welcome.txt" << EOF
Welcome to the BV-BRC CLI Tools Installer

This package will install $CMD_COUNT command-line tools for interacting with BV-BRC (Bacterial and Viral Bioinformatics Resource Center).

Tools included:
- p3-login, p3-logout, p3-whoami: Authentication
- p3-ls, p3-cat, p3-cp, p3-mkdir, p3-rm: Workspace file operations
- p3-all-genomes, p3-all-features: Data queries
- p3-get-genome-data, p3-get-feature-data: Data retrieval
- p3-submit-*: Job submission commands
- p3-job-status: Job monitoring
- And more data processing utilities

The tools will be installed to /usr/local/bin.

For more information, visit: https://www.bv-brc.org
EOF

    # Create license text
    cat > "$RESOURCES_DIR/license.txt" << 'EOF'
BV-BRC CLI Tools

Copyright (c) 2024 BV-BRC Team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

    # Create readme
    cat > "$RESOURCES_DIR/readme.txt" << EOF
BV-BRC CLI Tools v${VERSION}

GETTING STARTED
===============

1. Open Terminal

2. Log in to BV-BRC:
   p3-login your-username

3. List your workspace:
   p3-ls /your-username@patricbrc.org/home

4. Query genomes:
   p3-all-genomes --eq genome_name,Escherichia

5. Get help on any command:
   p3-login --help
   p3-all-genomes --help

DOCUMENTATION
=============

Full documentation is available at:
https://www.bv-brc.org/docs/cli_tutorial/

SUPPORT
=======

For issues and questions:
- Email: help@bv-brc.org
- Website: https://www.bv-brc.org
EOF

    # Create conclusion text
    cat > "$RESOURCES_DIR/conclusion.txt" << EOF
Installation Complete!

The BV-BRC CLI tools have been installed to /usr/local/bin.

To get started:
1. Open a new Terminal window
2. Run: p3-login your-username
3. Run: p3-ls to list your workspace

For help with any command, use the --help flag:
  p3-login --help
  p3-all-genomes --help

Documentation: https://www.bv-brc.org/docs/cli_tutorial/
EOF

    # Create Distribution.xml for productbuild
    cat > "$BUILD_DIR/Distribution.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>BV-BRC CLI Tools</title>
    <organization>org.bvbrc</organization>
    <domains enable_localSystem="true" enable_anywhere="false"/>
    <options customize="never" require-scripts="true" rootVolumeOnly="true"/>

    <welcome file="welcome.txt"/>
    <license file="license.txt"/>
    <readme file="readme.txt"/>
    <conclusion file="conclusion.txt"/>

    <choices-outline>
        <line choice="default">
            <line choice="org.bvbrc.cli.pkg"/>
        </line>
    </choices-outline>

    <choice id="default"/>
    <choice id="org.bvbrc.cli.pkg" visible="false">
        <pkg-ref id="org.bvbrc.cli.pkg"/>
    </choice>

    <pkg-ref id="org.bvbrc.cli.pkg" version="${VERSION}" onConclusion="none">bvbrc-cli.pkg</pkg-ref>
</installer-gui-script>
EOF

    echo ""
    echo "Package structure created in $BUILD_DIR"
    echo ""
    echo "To build the .pkg installer on macOS, copy this directory and run:"
    echo ""
    echo "  # Build component package"
    echo "  pkgbuild --root $PAYLOAD_DIR \\"
    echo "           --scripts $SCRIPTS_DIR \\"
    echo "           --identifier $PKG_ID \\"
    echo "           --version $VERSION \\"
    echo "           --install-location $INSTALL_LOCATION \\"
    echo "           $BUILD_DIR/bvbrc-cli.pkg"
    echo ""
    echo "  # Build product archive (with GUI)"
    echo "  productbuild --distribution $BUILD_DIR/Distribution.xml \\"
    echo "               --resources $RESOURCES_DIR \\"
    echo "               --package-path $BUILD_DIR \\"
    echo "               $OUTPUT_DIR/bvbrc-cli-${VERSION}-$ARCH_NAME.pkg"
}

# Clean output directory
rm -rf "$OUTPUT_DIR/pkg-build-"*

# Build for both architectures
build_pkg "amd64" "intel"
build_pkg "arm64" "apple-silicon"

# Create a helper script for building on macOS
cat > "$OUTPUT_DIR/build-pkg-on-macos.sh" << 'BUILDSCRIPT'
#!/bin/bash
# Run this script ON MACOS to create the .pkg installers

set -e

VERSION="${VERSION:-1.0.0}"

for ARCH in intel apple-silicon; do
    BUILD_DIR="pkg-build-${ARCH/intel/amd64}"
    BUILD_DIR="${BUILD_DIR/apple-silicon/arm64}"

    if [ ! -d "$BUILD_DIR" ]; then
        echo "Build directory $BUILD_DIR not found"
        continue
    fi

    echo "Building $ARCH package..."

    # Build component package
    pkgbuild --root "$BUILD_DIR/payload" \
             --scripts "$BUILD_DIR/scripts" \
             --identifier "org.bvbrc.cli" \
             --version "$VERSION" \
             --install-location "/usr/local" \
             "$BUILD_DIR/bvbrc-cli.pkg"

    # Build product archive
    productbuild --distribution "$BUILD_DIR/Distribution.xml" \
                 --resources "$BUILD_DIR/resources" \
                 --package-path "$BUILD_DIR" \
                 "bvbrc-cli-${VERSION}-${ARCH}.pkg"

    echo "Created bvbrc-cli-${VERSION}-${ARCH}.pkg"
done

echo ""
echo "Done! Package files created:"
ls -lh *.pkg 2>/dev/null || echo "No .pkg files created"
BUILDSCRIPT
chmod +x "$OUTPUT_DIR/build-pkg-on-macos.sh"

echo ""
echo "========================================"
echo "Build preparation complete!"
echo "========================================"
echo ""
echo "Package build directories created:"
echo "  - $OUTPUT_DIR/pkg-build-amd64/   (Intel Macs)"
echo "  - $OUTPUT_DIR/pkg-build-arm64/   (Apple Silicon Macs)"
echo ""
echo "To create .pkg installers, copy the dist/ folder to a Mac and run:"
echo "  cd dist && ./build-pkg-on-macos.sh"
echo ""
echo "Or use the tarballs for manual installation:"
ls -lh "$OUTPUT_DIR"/*.tar.gz 2>/dev/null || true
