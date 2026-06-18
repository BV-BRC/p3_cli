#!/bin/bash
# Build script for BV-BRC CLI tools - Windows installer

set -e

GO=/home/olson/P3/go-1.25.6/go/bin/go
VERSION="${VERSION:-1.0.0}"
OUTPUT_DIR="dist"

cd "$(dirname "$0")"

# Get list of all commands
COMMANDS=$(ls -d cmd/p3-*/ | xargs -n1 basename)
CMD_COUNT=$(echo $COMMANDS | wc -w)

echo "Building BV-BRC CLI tools v${VERSION} for Windows"
echo "Commands to build: $CMD_COUNT"

# Build for Windows
build_windows() {
    local ARCH=$1
    local ARCH_NAME=$2

    echo ""
    echo "Building for Windows $ARCH_NAME ($ARCH)..."

    local BIN_DIR="$OUTPUT_DIR/windows-$ARCH"
    mkdir -p "$BIN_DIR"

    for cmd in $COMMANDS; do
        echo "  $cmd.exe"
        GOOS=windows GOARCH=$ARCH CGO_ENABLED=0 $GO build -buildvcs=false -ldflags="-s -w" -o "$BIN_DIR/$cmd.exe" "./cmd/$cmd"
    done
}

# Clean and build
rm -rf "$OUTPUT_DIR/windows-"*
rm -rf "$OUTPUT_DIR/bvbrc-cli-"*"-windows-"*

build_windows "amd64" "x64"
build_windows "arm64" "ARM64"

# Create zip archives
echo ""
echo "Creating distribution archives..."

cd "$OUTPUT_DIR"

# Create zip if zip command is available
if command -v zip &> /dev/null; then
    zip -rq "bvbrc-cli-${VERSION}-windows-amd64.zip" windows-amd64
    echo "  Created bvbrc-cli-${VERSION}-windows-amd64.zip"

    zip -rq "bvbrc-cli-${VERSION}-windows-arm64.zip" windows-arm64
    echo "  Created bvbrc-cli-${VERSION}-windows-arm64.zip"
else
    # Fallback to tar.gz
    tar -czf "bvbrc-cli-${VERSION}-windows-amd64.tar.gz" windows-amd64
    echo "  Created bvbrc-cli-${VERSION}-windows-amd64.tar.gz (zip not available)"

    tar -czf "bvbrc-cli-${VERSION}-windows-arm64.tar.gz" windows-arm64
    echo "  Created bvbrc-cli-${VERSION}-windows-arm64.tar.gz (zip not available)"
fi

cd ..

# Create batch file installer
cat > "$OUTPUT_DIR/windows-amd64/install.bat" << 'EOF'
@echo off
REM BV-BRC CLI Tools Installer for Windows
REM Run this as Administrator

echo BV-BRC CLI Tools Installer
echo ==========================
echo.

REM Check for admin rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo This script requires Administrator privileges.
    echo Please right-click and select "Run as administrator"
    pause
    exit /b 1
)

REM Create installation directory
set INSTALL_DIR=C:\Program Files\BVBRC
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

REM Copy executables
echo Installing to %INSTALL_DIR%...
copy /Y *.exe "%INSTALL_DIR%\" >nul

REM Add to PATH
echo Adding to system PATH...
setx /M PATH "%PATH%;%INSTALL_DIR%" >nul 2>&1

echo.
echo Installation complete!
echo.
echo Please restart your command prompt or PowerShell to use the tools.
echo.
echo To get started:
echo   1. Open a new Command Prompt or PowerShell
echo   2. Run: p3-login your-username
echo   3. Run: p3-ls to list your workspace
echo.
pause
EOF

cp "$OUTPUT_DIR/windows-amd64/install.bat" "$OUTPUT_DIR/windows-arm64/install.bat"

# Create PowerShell installer
cat > "$OUTPUT_DIR/windows-amd64/install.ps1" << 'EOF'
# BV-BRC CLI Tools Installer for Windows (PowerShell)
# Run as Administrator: powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Stop"

Write-Host "BV-BRC CLI Tools Installer" -ForegroundColor Cyan
Write-Host "==========================" -ForegroundColor Cyan
Write-Host ""

# Check for admin rights
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script requires Administrator privileges." -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Red
    exit 1
}

# Installation directory
$InstallDir = "C:\Program Files\BVBRC"

# Create directory if it doesn't exist
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# Copy executables
Write-Host "Installing to $InstallDir..."
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Copy-Item "$ScriptDir\*.exe" -Destination $InstallDir -Force

# Add to PATH
$currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($currentPath -notlike "*$InstallDir*") {
    Write-Host "Adding to system PATH..."
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$InstallDir", "Machine")
}

Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Please restart your PowerShell or Command Prompt to use the tools."
Write-Host ""
Write-Host "To get started:" -ForegroundColor Yellow
Write-Host "  1. Open a new PowerShell or Command Prompt"
Write-Host "  2. Run: p3-login your-username"
Write-Host "  3. Run: p3-ls to list your workspace"
Write-Host ""
EOF

cp "$OUTPUT_DIR/windows-amd64/install.ps1" "$OUTPUT_DIR/windows-arm64/install.ps1"

# Create README for Windows
cat > "$OUTPUT_DIR/windows-amd64/README.txt" << EOF
BV-BRC CLI Tools v${VERSION} for Windows
========================================

INSTALLATION
------------

Option 1: Using the installer (recommended)
  1. Right-click on install.bat and select "Run as administrator"
  2. Follow the prompts
  3. Restart your command prompt

Option 2: Using PowerShell
  1. Open PowerShell as Administrator
  2. Run: powershell -ExecutionPolicy Bypass -File install.ps1
  3. Restart your PowerShell

Option 3: Manual installation
  1. Copy all .exe files to a directory (e.g., C:\Program Files\BVBRC)
  2. Add that directory to your PATH environment variable
  3. Restart your command prompt

GETTING STARTED
---------------

1. Open Command Prompt or PowerShell
2. Login to BV-BRC:
   p3-login your-username

3. List your workspace:
   p3-ls /your-username@patricbrc.org/home

4. Get help on any command:
   p3-login --help
   p3-all-genomes --help

DOCUMENTATION
-------------

Full documentation: https://www.bv-brc.org/docs/cli_tutorial/

SUPPORT
-------

For issues and questions:
- Email: help@bv-brc.org
- Website: https://www.bv-brc.org
EOF

cp "$OUTPUT_DIR/windows-amd64/README.txt" "$OUTPUT_DIR/windows-arm64/README.txt"

# Update zip files with installers
cd "$OUTPUT_DIR"
if command -v zip &> /dev/null; then
    # Re-create zips with installers included
    rm -f "bvbrc-cli-${VERSION}-windows-amd64.zip" "bvbrc-cli-${VERSION}-windows-arm64.zip"

    zip -rq "bvbrc-cli-${VERSION}-windows-amd64.zip" windows-amd64
    echo "  Updated bvbrc-cli-${VERSION}-windows-amd64.zip"

    zip -rq "bvbrc-cli-${VERSION}-windows-arm64.zip" windows-arm64
    echo "  Updated bvbrc-cli-${VERSION}-windows-arm64.zip"
fi
cd ..

# Create NSIS installer script (for building on Windows with NSIS)
mkdir -p "$OUTPUT_DIR/nsis"
cat > "$OUTPUT_DIR/nsis/bvbrc-cli.nsi" << 'EOF'
; BV-BRC CLI Tools NSIS Installer Script
; Compile with: makensis bvbrc-cli.nsi

!define APPNAME "BV-BRC CLI Tools"
!define COMPANYNAME "BV-BRC"
!define DESCRIPTION "Command-line tools for BV-BRC"
!define VERSIONMAJOR 1
!define VERSIONMINOR 0
!define VERSIONBUILD 0
!define INSTALLSIZE 150000

RequestExecutionLevel admin

InstallDir "$PROGRAMFILES\BVBRC"

Name "${APPNAME}"
Icon "${NSISDIR}\Contrib\Graphics\Icons\modern-install.ico"
OutFile "bvbrc-cli-setup.exe"

!include "MUI2.nsh"

!define MUI_ABORTWARNING
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\modern-install.ico"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "license.txt"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Section "Install"
    SetOutPath $INSTDIR

    ; Copy all executables
    File "*.exe"

    ; Create uninstaller
    WriteUninstaller "$INSTDIR\uninstall.exe"

    ; Add to PATH
    EnVar::AddValue "PATH" "$INSTDIR"

    ; Create Start Menu shortcuts
    CreateDirectory "$SMPROGRAMS\${APPNAME}"
    CreateShortCut "$SMPROGRAMS\${APPNAME}\Uninstall.lnk" "$INSTDIR\uninstall.exe"

    ; Add uninstall information to Add/Remove Programs
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "DisplayName" "${APPNAME}"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "Publisher" "${COMPANYNAME}"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "DisplayVersion" "${VERSIONMAJOR}.${VERSIONMINOR}.${VERSIONBUILD}"
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "EstimatedSize" ${INSTALLSIZE}
SectionEnd

Section "Uninstall"
    ; Remove from PATH
    EnVar::DeleteValue "PATH" "$INSTDIR"

    ; Remove files
    Delete "$INSTDIR\*.exe"
    Delete "$INSTDIR\uninstall.exe"

    ; Remove directories
    RMDir "$INSTDIR"
    RMDir "$SMPROGRAMS\${APPNAME}"

    ; Remove uninstall information
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"
SectionEnd
EOF

# Create license file for NSIS
cat > "$OUTPUT_DIR/nsis/license.txt" << 'EOF'
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

# Copy executables to Inno Setup directory
echo ""
echo "Preparing Inno Setup installer..."
mkdir -p "$OUTPUT_DIR/innosetup"
cp "$OUTPUT_DIR/windows-amd64/"*.exe "$OUTPUT_DIR/innosetup/" 2>/dev/null || true
echo "  Copied executables to innosetup/"

echo ""
echo "========================================"
echo "Windows build complete!"
echo "========================================"
echo ""
echo "Distribution files:"
ls -lh "$OUTPUT_DIR"/*windows* 2>/dev/null || true
echo ""
echo "Installation options for end users:"
echo ""
echo "  1. Extract zip and run install.bat as Administrator"
echo ""
echo "  2. Extract zip and run in PowerShell as Administrator:"
echo "     powershell -ExecutionPolicy Bypass -File install.ps1"
echo ""
echo "  3. Manual: Copy .exe files to a directory and add to PATH"
echo ""
echo "To create a graphical installer:"
echo ""
echo "  Using Inno Setup (recommended):"
echo "    1. Install Inno Setup from https://jrsoftware.org/isinfo.php"
echo "    2. Copy dist/innosetup to Windows"
echo "    3. Run: iscc bvbrc-cli.iss"
echo "    Output: bvbrc-cli-${VERSION}-windows-x64-setup.exe"
echo ""
echo "  Using NSIS:"
echo "    1. Install NSIS from https://nsis.sourceforge.io/"
echo "    2. Copy windows-amd64/*.exe to nsis/"
echo "    3. Run: makensis nsis/bvbrc-cli.nsi"
