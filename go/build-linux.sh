#!/bin/bash
# Build script for BV-BRC CLI tools - Linux installer

set -e

GO=/home/olson/P3/go-1.25.6/go/bin/go
VERSION="${VERSION:-1.0.0}"
OUTPUT_DIR="dist"

cd "$(dirname "$0")"

# Get list of all commands
COMMANDS=$(ls -d cmd/p3-*/ | xargs -n1 basename)
CMD_COUNT=$(echo $COMMANDS | wc -w)

echo "Building BV-BRC CLI tools v${VERSION} for Linux"
echo "Commands to build: $CMD_COUNT"

# Build for Linux amd64
build_linux() {
    local ARCH=$1
    local ARCH_NAME=$2

    echo ""
    echo "Building for Linux $ARCH_NAME ($ARCH)..."

    local BIN_DIR="$OUTPUT_DIR/linux-$ARCH/bin"
    mkdir -p "$BIN_DIR"

    for cmd in $COMMANDS; do
        echo "  $cmd"
        GOOS=linux GOARCH=$ARCH CGO_ENABLED=0 $GO build -buildvcs=false -ldflags="-s -w" -o "$BIN_DIR/$cmd" "./cmd/$cmd"
    done
}

# Clean and build
rm -rf "$OUTPUT_DIR/linux-"*
rm -rf "$OUTPUT_DIR/bvbrc-cli-"*"-linux-"*

build_linux "amd64" "x86_64"
build_linux "arm64" "aarch64"

# Create tarballs
echo ""
echo "Creating distribution archives..."

cd "$OUTPUT_DIR"

tar -czf "bvbrc-cli-${VERSION}-linux-amd64.tar.gz" -C linux-amd64 bin
echo "  Created bvbrc-cli-${VERSION}-linux-amd64.tar.gz"

tar -czf "bvbrc-cli-${VERSION}-linux-arm64.tar.gz" -C linux-arm64 bin
echo "  Created bvbrc-cli-${VERSION}-linux-arm64.tar.gz"

cd ..

# Create .deb package structure for amd64
echo ""
echo "Creating Debian package structure..."

DEB_DIR="$OUTPUT_DIR/deb-build-amd64"
rm -rf "$DEB_DIR"
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/usr/local/bin"

# Copy binaries
cp "$OUTPUT_DIR/linux-amd64/bin/"* "$DEB_DIR/usr/local/bin/"

# Create control file
cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: bvbrc-cli
Version: ${VERSION}
Section: science
Priority: optional
Architecture: amd64
Maintainer: BV-BRC Team <help@bv-brc.org>
Description: BV-BRC Command Line Interface Tools
 Command-line tools for interacting with BV-BRC (Bacterial and Viral
 Bioinformatics Resource Center). Includes tools for authentication,
 workspace management, data queries, and job submission.
Homepage: https://www.bv-brc.org
EOF

# Create postinst script
cat > "$DEB_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/bash
echo "BV-BRC CLI tools installed successfully!"
echo "Run 'p3-login' to authenticate with BV-BRC."
EOF
chmod 755 "$DEB_DIR/DEBIAN/postinst"

# Build .deb if dpkg-deb is available
if command -v dpkg-deb &> /dev/null; then
    dpkg-deb --build "$DEB_DIR" "$OUTPUT_DIR/bvbrc-cli_${VERSION}_amd64.deb"
    echo "  Created bvbrc-cli_${VERSION}_amd64.deb"
else
    echo "  dpkg-deb not available - .deb package not created"
    echo "  To build on Debian/Ubuntu: dpkg-deb --build $DEB_DIR $OUTPUT_DIR/bvbrc-cli_${VERSION}_amd64.deb"
fi

# Create .deb package structure for arm64
DEB_DIR="$OUTPUT_DIR/deb-build-arm64"
rm -rf "$DEB_DIR"
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/usr/local/bin"

cp "$OUTPUT_DIR/linux-arm64/bin/"* "$DEB_DIR/usr/local/bin/"

cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: bvbrc-cli
Version: ${VERSION}
Section: science
Priority: optional
Architecture: arm64
Maintainer: BV-BRC Team <help@bv-brc.org>
Description: BV-BRC Command Line Interface Tools
 Command-line tools for interacting with BV-BRC (Bacterial and Viral
 Bioinformatics Resource Center). Includes tools for authentication,
 workspace management, data queries, and job submission.
Homepage: https://www.bv-brc.org
EOF

cat > "$DEB_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/bash
echo "BV-BRC CLI tools installed successfully!"
echo "Run 'p3-login' to authenticate with BV-BRC."
EOF
chmod 755 "$DEB_DIR/DEBIAN/postinst"

if command -v dpkg-deb &> /dev/null; then
    dpkg-deb --build "$DEB_DIR" "$OUTPUT_DIR/bvbrc-cli_${VERSION}_arm64.deb"
    echo "  Created bvbrc-cli_${VERSION}_arm64.deb"
fi

# Create RPM spec file
echo ""
echo "Creating RPM spec file..."

mkdir -p "$OUTPUT_DIR/rpm-build"
cat > "$OUTPUT_DIR/rpm-build/bvbrc-cli.spec" << EOF
Name:           bvbrc-cli
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        BV-BRC Command Line Interface Tools

License:        MIT
URL:            https://www.bv-brc.org

%description
Command-line tools for interacting with BV-BRC (Bacterial and Viral
Bioinformatics Resource Center). Includes tools for authentication,
workspace management, data queries, and job submission.

%install
mkdir -p %{buildroot}/usr/local/bin
cp -r %{_sourcedir}/bin/* %{buildroot}/usr/local/bin/

%files
/usr/local/bin/p3-*

%post
echo "BV-BRC CLI tools installed successfully!"
echo "Run 'p3-login' to authenticate with BV-BRC."
EOF

echo "  Created rpm-build/bvbrc-cli.spec"

# Create install script
cat > "$OUTPUT_DIR/install-linux.sh" << 'EOF'
#!/bin/bash
# Install script for BV-BRC CLI tools

set -e

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        TARBALL="bvbrc-cli-*-linux-amd64.tar.gz"
        ;;
    aarch64|arm64)
        TARBALL="bvbrc-cli-*-linux-arm64.tar.gz"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Find tarball
TARBALL_PATH=$(ls $TARBALL 2>/dev/null | head -1)
if [ -z "$TARBALL_PATH" ]; then
    echo "Could not find tarball for architecture: $ARCH"
    exit 1
fi

echo "Installing BV-BRC CLI tools from $TARBALL_PATH"
echo "Install directory: $INSTALL_DIR"

# Extract and install
TMP_DIR=$(mktemp -d)
tar -xzf "$TARBALL_PATH" -C "$TMP_DIR"

if [ -w "$INSTALL_DIR" ]; then
    cp "$TMP_DIR/bin/"* "$INSTALL_DIR/"
else
    echo "Need sudo to install to $INSTALL_DIR"
    sudo cp "$TMP_DIR/bin/"* "$INSTALL_DIR/"
fi

rm -rf "$TMP_DIR"

echo ""
echo "Installation complete!"
echo "Run 'p3-login' to authenticate with BV-BRC."
EOF
chmod +x "$OUTPUT_DIR/install-linux.sh"

echo ""
echo "========================================"
echo "Linux build complete!"
echo "========================================"
echo ""
echo "Distribution files:"
ls -lh "$OUTPUT_DIR"/*linux* "$OUTPUT_DIR"/*.deb 2>/dev/null || true
echo ""
echo "Installation options:"
echo ""
echo "  1. Using tarball:"
echo "     tar -xzf bvbrc-cli-${VERSION}-linux-amd64.tar.gz"
echo "     sudo cp bin/p3-* /usr/local/bin/"
echo ""
echo "  2. Using .deb (Debian/Ubuntu):"
echo "     sudo dpkg -i bvbrc-cli_${VERSION}_amd64.deb"
echo ""
echo "  3. Using install script:"
echo "     ./install-linux.sh"
