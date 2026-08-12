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
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required and is not found"; exit 1; }

if [ -f ".env" ]; then source .env; fi

# Guard against dangerous or misconfigured paths before doing anything else.
if [ "$TMP_DIR" = "$DESTINATION" ]; then
  echo "Error: TMP_DIR must be different from DESTINATION."
  exit 1
fi

case "$DESTINATION" in
  /)
    echo "Error: DESTINATION must not be the filesystem root."
    exit 1
    ;;
  "$HOME")
    echo "Error: DESTINATION must not be the home directory."
    exit 1
    ;;
esac

if [ ! -d "$TMP_DIR" ]; then
  mkdir -p "$TMP_DIR" || { echo "Error: Cannot create TMP_DIR $TMP_DIR."; exit 1; }
elif [ ! -w "$TMP_DIR" ]; then
  echo "Error: TMP_DIR $TMP_DIR is not writable."
  exit 1
fi

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
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
if ! RELEASE_JSON=$(curl -fsSL "$API_URL"); then
    echo "Error: Failed to fetch release information from GitHub API."
    exit 1
fi

VERSION_LATEST=$(printf '%s' "$RELEASE_JSON" | sed -nE 's/.*"tag_name": "v([^"]+)".*/\1/p')

if [ -z "$VERSION_LATEST" ]; then
    echo "Error: Failed to determine the latest Element Web version."
    exit 1
fi

# SHA-256 digest of the release asset, taken from the same API response.
DIGEST=$(printf '%s' "$RELEASE_JSON" | awk -v v="$VERSION_LATEST" '
    index($0, "\"name\": \"element-v" v ".tar.gz\"") { capture = 1 }
    capture && /"digest": "sha256:/ {
        sub(/^.*"digest": "sha256:/, "")
        sub(/".*$/, "")
        print
        exit
    }
')

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

echo "Verifying SHA-256 checksum..."

if [ -n "$DIGEST" ]; then
    if ! printf '%s  %s\n' "$DIGEST" "$ARCHIVE_FILE" | sha256sum -c --quiet; then
        echo "Error: SHA-256 checksum of the downloaded archive does not match."
        rm -f "$ARCHIVE_FILE"
        rm -rf "$EXTRACT_DIR"
        exit 1
    fi
else
    echo "Warning: No SHA-256 digest found for the release asset, skipping verification."
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

# Sanity check: make sure the archive actually contains Element Web files
# before touching the current installation. The `version` file is required
# because the script relies on it to track the installed version.
if [ ! -f "$EXTRACT_DIR/index.html" ] || [ ! -f "$EXTRACT_DIR/version" ]; then
    echo "Error: The downloaded archive does not look like an Element Web release."
    echo "Element Web may have changed its release structure and the script needs to be updated."
    echo "The current installation was left untouched."
    rm -f "$ARCHIVE_FILE"
    rm -rf "$EXTRACT_DIR"
    exit 1
fi

echo "Replacing installed Element Web files..."

find "$DESTINATION" -mindepth 1 -maxdepth 1 ! -name 'config.json' -exec rm -rf {} +

# Remove the release's own config.json (if any) so that the preserved
# user configuration in DESTINATION is not overwritten by `cp -a`.
rm -f "$EXTRACT_DIR/config.json"

cp -a "$EXTRACT_DIR"/. "$DESTINATION"/

rm -f "$ARCHIVE_FILE"
rm -rf "$EXTRACT_DIR"

if [ -n "$VERSION_INSTALLED" ]; then
    echo "Element Web successfully updated from $VERSION_INSTALLED to $VERSION_LATEST."
else
    echo "Element Web $VERSION_LATEST successfully installed."
fi
