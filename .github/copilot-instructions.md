
# Copilot Workspace Instructions

## Project: Self-hosted PostgreSQL Education Platform

**Stack:** PostgreSQL 16 (Docker), per-student DBs, postgres-exporter, Tailscale VPN, NGINX stream proxy. Prometheus and Grafana are centralized on the VPS (`gatekeeper`); no local Prometheus/Grafana service exists.

---

## Agent Workflow

### Build & Test
- Start stack: `docker compose up -d`
- Health check: `make check-health`
- Create students: `./scripts/create_students.sh` (requires `credentials/students.txt`)
- Load test: `./scripts/loadtest.sh init` and `multi 20 4 60` (the script loads `.env` itself)

### Admin Commands (see `make help`)
- `make shell DB=mydb` — Open psql shell
- `make list-users` / `make list-databases` — Inventory
- `make grant-students-access DB=name` — Grant `students` role access
- `make backup-all` — Full backup to `$BACKUP_DIR` (override per run with `BACKUP_DIR=...`)

### Student Management
- Usernames: lowercase, alphanumeric/underscore (auto-sanitized)
- DBs: `{username}_db`, owned by user
- All students in `students` role (shared DB access)
- Connection limit: 3 per student

### SQL Init
- Scripts in `init/` run alphabetically on first container start
- Use `scripts/grant_distributed_gan_access.sql` as template for shared DB access

### Environment & Secrets
- Copy `.env.template` to `.env` and fill in every value; all settings are required and validated by Compose, the Makefile and `scripts/lib/load-env.sh`
- Host-specific settings: `TAILSCALE_IP`, `DB_HOST`, `PGDATA_DIR`, `BACKUP_DIR`, `PGADMIN_DEFAULT_EMAIL` (plus `DB_PORT` / `DB_USER`)
- Secrets in `.env`: `POSTGRES_ADMIN_PASSWORD`, `PGADMIN_DEFAULT_PASSWORD`
- **Never commit `.env`** or files in `credentials/`
- Admin scripts load `.env` themselves; for ad-hoc commands, `source .env` first

### Security & Auth
- SSL certs: `config/ssl/server.crt` and `server.key` required
- Auth rules: `config/pg_hba.conf`
- Students: `NOSUPERUSER NOCREATEDB NOCREATEROLE`

### pgAdmin
- Web UI at `http://$TAILSCALE_IP:8088`; login `PGADMIN_DEFAULT_EMAIL` / `PGADMIN_DEFAULT_PASSWORD`
- `Local PostgreSQL` server is declarative in `config/pgadmin/servers.json`; pgAdmin 9.x reloads it on every start via `PGADMIN_REPLACE_SERVERS_ON_STARTUP`

### Monitoring
- Centralized on the VPS (`gatekeeper`): Prometheus job `pyrite-postgres-exporter`, Grafana dashboard `postgres-main-overview`
- Only `postgres-exporter` runs locally, at `$TAILSCALE_IP:9187` (Tailscale only)
- No local Prometheus (`:9090`) or Grafana (`:3000`) service

### Troubleshooting & Pitfalls
- Must have Tailscale configured on pyrite (local) and gatekeeper (VPS) with both active on the tailnet; NGINX stream proxy must be running on VPS
- For metrics, gatekeeper must be able to reach `$TAILSCALE_IP:9187` over Tailscale
- Scripts require `.env` and correct permissions
- See `docs/setup.md` for full diagnostics, connection, and security troubleshooting

---

## Example Prompts
- "Create a new student and grant access to the shared database."
- "Run a load test with 50 clients for 2 minutes."
- "Show all active database connections."
- "Backup all databases and verify backup file."
- "Diagnose why a student cannot connect from remote."

---

## Related Customizations
- `/create-instruction agent-student-management` — Automate student DB/user creation, enforce naming/role rules
- `/create-instruction agent-backup-restore` — Automate backup/restore flows, validate backup integrity
- `/create-instruction agent-monitoring` — Query Grafana/Prometheus for health, alert on anomalies

See `README.md` and `docs/setup.md` for architecture, usage, and troubleshooting details.
