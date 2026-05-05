# Tech Stack

Phoenix LiveView app backed by PostgreSQL.

## Database

Phoenix connects to Postgres via `Ecto.Repo` (no Ecto schemas). All queries use `DbHelpers.run_sql/2,3` with named parameters (`$(param_name)`), which are converted to positional Postgrex params at runtime. Query results are optionally validated against a Zoi schema.

## Configuration

All runtime config is loaded from `.env` (via Dotenvy) merged with system env vars. Key variables:

- `DATABASE_URL` — Ecto-format Postgres URL (`ecto://user:pass@host/db`)
- `SECRET_KEY_BASE` — Phoenix cookie signing key
- `PORT` — HTTP port (default 4000)

Copy `example.env` to `.env` and fill in values before starting the app.

## Dev Environment

`docker compose up` starts two containers:

1. **db** — Postgres 17; `schema.sql` is mounted and run on first start
2. **app** — Elixir/Phoenix; source is bind-mounted so live reload works

## Production

Set `PHX_SERVER=true` and provide env vars (`DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`). The app binds to `0.0.0.0:4000` behind a reverse proxy terminating TLS.
