#!/usr/bin/env bash
set -euo pipefail

# Ironwake CI — Export Linux build (Steam Deck / SteamOS)
# Bash equivalent of export-windows.ps1 for ubuntu-latest runners.

PROJECT_ROOT="${1:?Usage: $0 <project-root> [export-preset-name] [output-dir]}"
EXPORT_PRESET_NAME="${2:-Linux}"
OUTPUT_DIR="${3:-build/linux}"

PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
OUTPUT_DIR_RESOLVED="$PROJECT_ROOT/$OUTPUT_DIR"
PRESET_TEMPLATE="$PROJECT_ROOT/tools/ci/export_presets.ci.cfg"
PRESET_DEST="$PROJECT_ROOT/export_presets.cfg"

if [[ ! -f "$PRESET_TEMPLATE" ]]; then
    echo "ERROR: Missing preset template at '$PRESET_TEMPLATE'."
    exit 1
fi

cp "$PRESET_TEMPLATE" "$PRESET_DEST"
mkdir -p "$OUTPUT_DIR_RESOLVED"

GAME_BINARY="$OUTPUT_DIR_RESOLVED/Ironwake.x86_64"

# Resolve Godot CLI installed by chickensoft-games/setup-godot.
# The action sets GODOT or GODOT4 env vars and/or adds godot to PATH.
resolve_godot_command() {
    # Check env vars set by setup-godot action.
    if [[ -n "${GODOT4:-}" ]] && command -v "$GODOT4" &>/dev/null; then
        echo "$GODOT4"
        return
    fi
    if [[ -n "${GODOT:-}" ]] && command -v "$GODOT" &>/dev/null; then
        echo "$GODOT"
        return
    fi
    # Check PATH.
    if command -v godot4 &>/dev/null; then
        echo "godot4"
        return
    fi
    if command -v godot &>/dev/null; then
        echo "godot"
        return
    fi
    # Search home directory (setup-godot default install location).
    local godot_install_dir="$HOME/godot"
    if [[ -d "$godot_install_dir" ]]; then
        local found
        found=$(find "$godot_install_dir" -type f -name "Godot_v*" -executable 2>/dev/null | head -1)
        if [[ -n "$found" ]]; then
            echo "$found"
            return
        fi
    fi
    echo "ERROR: Godot CLI not found." >&2
    exit 1
}

GODOT_CMD="$(resolve_godot_command)"

echo "Exporting with preset '$EXPORT_PRESET_NAME' to '$GAME_BINARY'..."
echo "Using Godot CLI: $GODOT_CMD"

"$GODOT_CMD" --headless --verbose --path "$PROJECT_ROOT" --export-release "$EXPORT_PRESET_NAME" "$GAME_BINARY"

if [[ ! -f "$GAME_BINARY" ]]; then
    echo "ERROR: Export failed — expected binary '$GAME_BINARY' was not created."
    echo "Output directory contents:"
    ls -la "$OUTPUT_DIR_RESOLVED" 2>/dev/null || echo "  <empty or missing>"
    exit 1
fi

echo "Export complete."
