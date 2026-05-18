# MCP Setup

This project uses a production `mcp.config.json` that wires together repo, database, reasoning, and diagram tooling.

## Included servers

- filesystem
- git
- github
- postgres
- memory
- sequential-thinking
- fetch
- time
- mermaid

## Required environment variables

- `GITHUB_PERSONAL_ACCESS_TOKEN`
- `MCP_POSTGRES_URL`

## Notes

- `filesystem` is scoped to the current repository.
- `git` is scoped to the current repository.
- `postgres` uses `MCP_POSTGRES_URL` so credentials are not hardcoded in the config.
- `github` uses `GITHUB_PERSONAL_ACCESS_TOKEN`.
- `mermaid` uses Mermaid CLI (`mmdc`) for diagram generation.

## Bootstrap

Run:

```bash
bash bootstrap_mcp.sh
```
