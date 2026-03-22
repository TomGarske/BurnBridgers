#!/bin/bash
# =============================================================
# burnbridgers — Local AI (Offline Mode)
# Usage: ./dev/start-local-ai.sh
# =============================================================
MODEL="qwen2.5-coder:32b-instruct-q4_K_M"

echo "🏠 Starting local AI (offline mode) with $MODEL..."

# ---------------------------------------------------------------------------
# Fix: Claude Code recently added an attribution header that invalidates the
# KV cache, making inference ~90% slower with local models.
# Setting CLAUDE_CODE_ATTRIBUTION_HEADER=0 in ~/.claude/settings.json
# disables the header and restores full cache performance.
# ---------------------------------------------------------------------------
SETTINGS_FILE="$HOME/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
  if ! grep -q '"CLAUDE_CODE_ATTRIBUTION_HEADER"' "$SETTINGS_FILE"; then
    echo "⚙️  Patching ~/.claude/settings.json to disable attribution header (KV cache fix)..."
    # Insert the env key into an existing "env" block, or add one if absent
    python3 - <<'PYEOF'
import json, sys

path = __import__('os').path.expanduser("~/.claude/settings.json")
with open(path) as f:
    cfg = json.load(f)

env = cfg.setdefault("env", {})
env["CLAUDE_CODE_ATTRIBUTION_HEADER"] = "0"

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)

print("  ✅ settings.json updated")
PYEOF
  else
    echo "✅ Attribution header already disabled in settings.json"
  fi
else
  echo "⚙️  ~/.claude/settings.json not found — creating it with KV cache fix..."
  mkdir -p "$HOME/.claude"
  cat > "$SETTINGS_FILE" <<'JSON'
{
  "env": {
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0"
  }
}
JSON
  echo "  ✅ settings.json created"
fi

# ---------------------------------------------------------------------------
# Start Ollama if not already running
# ---------------------------------------------------------------------------
if ! curl -s http://localhost:11434 > /dev/null 2>&1; then
  echo "⚡ Starting Ollama..."
  ollama serve &
  sleep 2
fi

# ---------------------------------------------------------------------------
# Pull model if not already downloaded
# ---------------------------------------------------------------------------
if ! ollama list | grep -q "$MODEL"; then
  echo "📦 Pulling $MODEL (first time only)..."
  ollama pull "$MODEL"
fi

echo "✅ Ready — launching Claude Code"

# Launch Claude Code pointed at local Ollama (env vars scoped to this exec)
ANTHROPIC_BASE_URL=http://localhost:11434 \
ANTHROPIC_API_KEY=ollama \
ANTHROPIC_MODEL=$MODEL \
exec claude
