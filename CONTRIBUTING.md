# Contributing to MLB Analytics Platform

## Development Setup

```bash
# Clone
git clone https://github.com/cbwinslow/mlb.git
cd mlb

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# Install in editable mode with all deps
pip install -e .

# Copy env template
cp .env.example .env
# Edit .env with your local DATABASE_URL

# Verify CLI works
baseball --help
baseball db-init
```

## Branching Strategy

- `main` — stable, always deployable
- `feature/<name>` — new features
- `fix/<name>` — bug fixes
- `docs/<name>` — documentation only
- `chore/<name>` — housekeeping (deps, CI, etc.)

## Pull Request Checklist

- [ ] All AI review comments addressed before requesting human review
- [ ] Tests added/updated for new code
- [ ] `pyproject.toml` updated if new dependencies added
- [ ] `ROADMAP.md` updated if milestone items completed
- [ ] No hardcoded credentials or secrets
- [ ] Database URL is never printed unmasked

## Commit Message Format

```
type(scope): short description

Longer explanation if needed.

Fixes #issue-number
```

Types: `feat`, `fix`, `docs`, `chore`, `test`, `refactor`, `ci`

## Running Tests

```bash
pytest tests/
```

## Code Style

- Python: `ruff` for linting, `black` for formatting
- SQL: lowercase keywords, snake_case identifiers
- All settings via `baseball.settings.AppSettings` — never `os.environ` directly
