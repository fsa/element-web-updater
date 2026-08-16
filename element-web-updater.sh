#!/bin/bash

# Element Web Updater
#
# Repository: https://github.com/fsa/element-web-updater
# License:    MIT (https://github.com/fsa/element-web-updater/blob/main/LICENSE)
#
# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
# The values below are the defaults. Edit them directly to change the
# behaviour, or override them with the corresponding environment variables:
#
#   DESTINATION=/var/www/element bash element-web-updater.sh
#
# DESTINATION is mandatory and has no default; when left empty the script
# refuses to run.
#
#   DESTINATION   Installation directory (required).
#   TMP_DIR       Directory used for downloading and temporarily
#                 extracting files (default: /tmp).
#   REPO          GitHub repository with the Element Web releases
#                 (default: element-hq/element-web).

DESTINATION="${DESTINATION:-}"
TMP_DIR="${TMP_DIR:-/tmp}"
REPO="${REPO:-element-hq/element-web}"

set -euo pipefail

err() {
    echo "Error: $*" >&2
    exit 1
}

cleanup() {
    [ -n "${WORK_DIR:-}" ] && rm -rf "$WORK_DIR"
}
trap cleanup EXIT

command -v curl >/dev/null 2>&1 || err "cURL is required and is not found"
command -v sha256sum >/dev/null 2>&1 || err "sha256sum is required and is not found"

# DESTINATION is mandatory and has no default.
if [ -z "$DESTINATION" ]; then
    err "DESTINATION is not set. Set the DESTINATION environment variable."
fi

# Relative paths are not allowed.
case "$DESTINATION" in
    /*) ;;
    *) err "DESTINATION must be an absolute path." ;;
esac

case "$TMP_DIR" in
    /*) ;;
    *) err "TMP_DIR must be an absolute path." ;;
esac

# Guard against dangerous or misconfigured paths before doing anything else.
if [ "$TMP_DIR" = "$DESTINATION" ]; then
    err "TMP_DIR must be different from DESTINATION."
fi

# Do not allow TMP_DIR and DESTINATION to be nested inside each other:
# the unique working directory is created inside TMP_DIR, so a TMP_DIR
# inside DESTINATION (or a DESTINATION inside TMP_DIR) could let a cleanup
# delete the installation or vice versa.
case "$TMP_DIR" in
    "$DESTINATION"/*)
        err "TMP_DIR must not be located inside DESTINATION."
        ;;
esac

case "$DESTINATION" in
    "$TMP_DIR"/*)
        err "DESTINATION must not be located inside TMP_DIR."
        ;;
esac

case "$DESTINATION" in
    /)
        err "DESTINATION must not be the filesystem root."
        ;;
    "$HOME")
        err "DESTINATION must not be the home directory."
        ;;
esac

if [ ! -d "$TMP_DIR" ]; then
    mkdir -p "$TMP_DIR" || err "Cannot create TMP_DIR $TMP_DIR."
elif [ ! -w "$TMP_DIR" ]; then
    err "TMP_DIR $TMP_DIR is not writable."
fi

if [ ! -d "$DESTINATION" ]; then
    err "Destination $DESTINATION does not exist"
fi

if [ ! -w "$DESTINATION" ]; then
    err "Destination $DESTINATION is not writable by the current user."
fi

if [ -f "$DESTINATION/version" ]; then
    # The release archive ships its own `version` file (e.g. `v1.12.25`),
    # which is copied into DESTINATION by `cp -a`. Normalize it so that the
    # comparison with VERSION_LATEST (no `v` prefix) works.
    VERSION_INSTALLED="$(< "$DESTINATION/version")"
    VERSION_INSTALLED="${VERSION_INSTALLED#v}"
    VERSION_INSTALLED="${VERSION_INSTALLED//[[:space:]]/}"
else
    VERSION_INSTALLED=""
fi

API_URL="https://api.github.com/repos/${REPO}/releases/latest"
if ! RELEASE_JSON=$(curl -fsSL "$API_URL"); then
    err "Failed to fetch release information from GitHub API."
fi

# Extract the latest release version from the API response using bash
# parameter expansion instead of an external tool.
VERSION_LATEST="${RELEASE_JSON#*\"tag_name\": \"v}"
VERSION_LATEST="${VERSION_LATEST%%\"*}"

if [ -z "$VERSION_LATEST" ]; then
    err "Failed to determine the latest Element Web version."
fi

# SHA-256 digest of the release asset, taken from the same API response.
DIGEST=""
asset_part="${RELEASE_JSON#*\"name\": \"element-v${VERSION_LATEST}.tar.gz\"}"
if [ "$asset_part" != "$RELEASE_JSON" ]; then
    digest_part="${asset_part#*\"digest\": \"sha256:}"
    if [ "$digest_part" != "$asset_part" ]; then
        DIGEST="${digest_part%%\"*}"
    fi
fi

if [ "$VERSION_INSTALLED" = "$VERSION_LATEST" ]; then
    echo "Element Web version $VERSION_LATEST is already installed. No update is required."
    exit 0
fi

if [ -z "$VERSION_INSTALLED" ]; then
    shopt -s nullglob dotglob
    entries=("$DESTINATION"/*)
    shopt -u nullglob dotglob
    for entry in "${entries[@]}"; do
        if [ "${entry##*/}" != "config.json" ]; then
            err "Element Web version was not detected, but the installation directory is not empty.

Installation aborted to avoid overwriting existing files."
        fi
    done

    echo "Element Web is not installed. Installing version $VERSION_LATEST..."
else
    echo "Element Web $VERSION_INSTALLED found, updating to $VERSION_LATEST..."
fi

ARCHIVE_URL="https://github.com/$REPO/releases/download/v${VERSION_LATEST}/element-v${VERSION_LATEST}.tar.gz"

echo "Downloading Element Web $VERSION_LATEST..."

WORK_DIR=$(mktemp -d "$TMP_DIR/element-web-updater.XXXXXX") ||
    err "Cannot create temporary directory in $TMP_DIR."

ARCHIVE_FILE="$WORK_DIR/element.tar.gz"
EXTRACT_DIR="$WORK_DIR/extracted"

mkdir -p "$EXTRACT_DIR"

if [ -t 1 ]; then
    CURL_OPTS=(-fL --progress-bar)
else
    CURL_OPTS=(-fsSL)
fi

if ! curl "${CURL_OPTS[@]}" -o "$ARCHIVE_FILE" "$ARCHIVE_URL"; then
    err "Failed to download Element Web $VERSION_LATEST."
fi

echo "Verifying SHA-256 checksum..."

if [ -n "$DIGEST" ]; then
    if ! printf '%s  %s\n' "$DIGEST" "$ARCHIVE_FILE" | sha256sum -c --quiet; then
        err "SHA-256 checksum of the downloaded archive does not match."
    fi
else
    echo "Warning: No SHA-256 digest found for the release asset, skipping verification."
fi

echo "Extracting Element Web $VERSION_LATEST..."

if ! tar -xzf "$ARCHIVE_FILE" \
    --strip-components=1 \
    -C "$EXTRACT_DIR"; then
    err "Failed to extract Element Web $VERSION_LATEST."
fi

# Sanity check: make sure the archive actually contains Element Web files
# before touching the current installation. The `version` file is required
# because the script relies on it to track the installed version.
if [ ! -f "$EXTRACT_DIR/index.html" ] || [ ! -f "$EXTRACT_DIR/version" ]; then
    err "The downloaded archive does not look like an Element Web release.

Element Web may have changed its release structure and the script needs to be updated.

The current installation was left untouched."
fi

# Verify that the version inside the archive matches the version the script
# asked for. This runs before anything in DESTINATION is touched.
ARCHIVE_VERSION="$(< "$EXTRACT_DIR/version")"
ARCHIVE_VERSION="${ARCHIVE_VERSION#v}"
ARCHIVE_VERSION="${ARCHIVE_VERSION//[[:space:]]/}"

if [ "$ARCHIVE_VERSION" != "$VERSION_LATEST" ]; then
    err "The version in the downloaded archive ($ARCHIVE_VERSION) does not match the expected version ($VERSION_LATEST)."
fi

echo "Replacing installed Element Web files..."

shopt -s nullglob dotglob
for entry in "$DESTINATION"/*; do
    if [ "${entry##*/}" != "config.json" ]; then
        rm -rf "$entry"
    fi
done
shopt -u nullglob dotglob

# Remove the release's own config.json (if any) so that the preserved
# user configuration in DESTINATION is not overwritten by `cp -a`.
rm -f "$EXTRACT_DIR/config.json"

if ! cp -a "$EXTRACT_DIR"/. "$DESTINATION"/; then
    err "Failed to copy Element Web files to $DESTINATION."
fi

if [ -n "$VERSION_INSTALLED" ]; then
    echo "Element Web successfully updated from $VERSION_INSTALLED to $VERSION_LATEST."
else
    echo "Element Web $VERSION_LATEST successfully installed."
fi
