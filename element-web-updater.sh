#!/bin/bash

# Installation directory.
# Can be overridden in the .env file.
DESTINATION="$HOME/public_html"

# Directory used for downloading and temporarily extracting files.
# Must be different from the installation directory.
# Can be overridden in the .env file.
TMP_DIR="/tmp"

# GitHub repository containing the Element Web releases.
# Can be overridden in the .env file.
REPO="element-hq/element-web"

command -v curl >/dev/null 2>&1 || { echo "cURL is required and is not found"; exit 1; }

if [ -f ".env" ]; then source .env; fi

if [ ! -d "$DESTINATION" ]; then
  echo "Destination $DESTINATION does not exist"
  exit 1
fi

if [ -f "$DESTINATION/version" ]; then
    # The release archive ships its own `version` file (e.g. `v1.12.25`),
    # which is copied into DESTINATION by `cp -a`. Normalize it so that the
    # comparison with VERSION_LATEST (no `v` prefix) works.
    VERSION_INSTALLED=$(cat "$DESTINATION/version" | sed -e 's/^v//' -e 's/[[:space:]]//g')
else
    VERSION_INSTALLED=""
fi
VERSION_LATEST=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" |
    grep -oP '"tarball_url": ".*/tarball/v\K([^/]*)(?=")')

if [ -z "$VERSION_LATEST" ]; then
    echo "Error: Failed to determine the latest Element Web version."
    exit 1
fi

if [ "$VERSION_INSTALLED" == "$VERSION_LATEST" ]; then
  echo "Element Web version $VERSION_LATEST is already installed. No update is required.";  
  exit 0
fi

if [ -z "$VERSION_INSTALLED" ]; then
  if [ -n "$(find "$DESTINATION" -mindepth 1 -maxdepth 1 ! -name 'config.json' -print -quit)" ]; then
    echo "Error: Element Web version was not detected, but the installation directory is not empty."
    echo "Installation aborted to avoid overwriting existing files."
    exit 1
  fi

  echo "Element Web is not installed. Installing version $VERSION_LATEST..."
else
  echo "Element Web $VERSION_INSTALLED found, updating to $VERSION_LATEST..."
fi

ARCHIVE_URL="https://github.com/$REPO/releases/download/v${VERSION_LATEST}/element-v${VERSION_LATEST}.tar.gz"

echo "Downloading Element Web $VERSION_LATEST..."

ARCHIVE_FILE="$TMP_DIR/element-v${VERSION_LATEST}.tar.gz"
EXTRACT_DIR="$TMP_DIR/element-v${VERSION_LATEST}"

rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"

if [ -t 1 ]; then
    CURL_OPTIONS="-fL --progress-bar"
else
    CURL_OPTIONS="-fsSL"
fi

if ! curl $CURL_OPTIONS -o "$ARCHIVE_FILE" "$ARCHIVE_URL"; then
    echo "Error: Failed to download Element Web $VERSION_LATEST."
    rm -f "$ARCHIVE_FILE"
    rm -rf "$EXTRACT_DIR"
    exit 1
fi

echo "Extracting Element Web $VERSION_LATEST..."

if ! tar -xzf "$ARCHIVE_FILE" \
    --strip-components=1 \
    -C "$EXTRACT_DIR"; then
    echo "Error: Failed to extract Element Web $VERSION_LATEST."
    rm -f "$ARCHIVE_FILE"
    rm -rf "$EXTRACT_DIR"
    exit 1
fi

echo "Replacing installed Element Web files..."

find "$DESTINATION" -mindepth 1 ! -name 'config.json' -exec rm -rf {} +

cp -a "$EXTRACT_DIR"/. "$DESTINATION"/

rm -f "$ARCHIVE_FILE"
rm -rf "$EXTRACT_DIR"

if [ -n "$VERSION_INSTALLED" ]; then
    echo "Element Web successfully updated from $VERSION_INSTALLED to $VERSION_LATEST."
else
    echo "Element Web $VERSION_LATEST successfully installed."
fi
