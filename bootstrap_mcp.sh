#!/usr/bin/env bash
set -euo pipefail

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required." >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required." >&2
  exit 1
fi

if ! command -v python >/dev/null 2>&1; then
  echo "Python is required." >&2
  exit 1
fi

if ! command -v uvx >/dev/null 2>&1; then
  echo "uvx not found; install uv first: https://docs.astral.sh/uv/" >&2
fi

npm install -g @mermaid-js/mermaid-cli

echo
echo "Bootstrap complete. Set these environment variables before using MCP:"
echo "  export GITHUB_PERSONAL_ACCESS_TOKEN=..."
echo "  export MCP_POSTGRES_URL=postgresql://user:pass@host:5432/dbname"
