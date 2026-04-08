#!/usr/bin/env bash
set -euo pipefail

# Ironwake CI — Install GDExtensions (GodotSteam) on Linux runners.
# Bash equivalent of setup-extensions.ps1.

PROJECT_ROOT="${1:?Usage: $0 <project-root>}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

# ── Versions (keep in sync with setup-steamos.sh) ─────────────────────
GODOTSTEAM_TAG="v4.17.1-gde"
GODOTSTEAM_ARCHIVE="godotsteam-4.17-gdextension-plugin-4.4.tar.xz"
GODOTSTEAM_URL="https://codeberg.org/godotsteam/godotsteam/releases/download/$GODOTSTEAM_TAG/$GODOTSTEAM_ARCHIVE"

# ── GodotSteam ─────────────────────────────────────────────────────────
GODOTSTEAM_DEST="$PROJECT_ROOT/addons/godotsteam"

if [[ -d "$GODOTSTEAM_DEST" ]]; then
    echo "GodotSteam already present — skipping download."
else
    echo "Downloading GodotSteam $GODOTSTEAM_TAG..."
    TMPFILE="$(mktemp /tmp/godotsteam-XXXXXX.tar.xz)"
    trap 'rm -f "$TMPFILE"' EXIT

    curl -fSL --progress-bar -o "$TMPFILE" "$GODOTSTEAM_URL"

    echo "Extracting GodotSteam..."
    tar -xJf "$TMPFILE" -C "$PROJECT_ROOT"

    if [[ ! -d "$GODOTSTEAM_DEST" ]]; then
        echo "ERROR: GodotSteam extraction succeeded but '$GODOTSTEAM_DEST' was not created."
        exit 1
    fi
    echo "GodotSteam installed to $GODOTSTEAM_DEST"
fi

echo "GDExtension setup complete."
