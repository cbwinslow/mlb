# Security Policy

## Reporting

Please do not open public issues for sensitive vulnerabilities. Report security issues privately through GitHub Security Advisories or direct trusted maintainer contact.

## Repository Rules

- Never commit secrets, API keys, passwords, tokens, or private certificates.
- Never print raw `DATABASE_URL` or other secret-bearing connection strings to logs or CLI output.
- Use distinct credentials for local, test, and production-like environments.
- Prefer secret-manager or environment injection over checked-in configuration.
- Hash stored API keys or signing secrets where appropriate.

## Platform Posture

This repository is building a PostgreSQL-first MLB analytics platform with future support for workers, APIs, MCP tools, and workspace-aware security boundaries. Security-sensitive work includes:

- source controls and legal holds
- audit and observability
- service-account boundaries
- row-level security for workspace-owned objects
- restricted raw-schema access

## Development Expectations

- Redact sensitive values from screenshots, logs, and PR descriptions.
- Update docs when security posture or access rules change.
- Prefer non-superuser app accounts.
- Keep worker credentials separate from manual admin credentials.
