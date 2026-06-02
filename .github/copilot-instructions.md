
# Copilot Workspace Instructions

## Project: Self-hosted PostgreSQL Education Platform

**Stack:** PostgreSQL 16 (Docker), per-student DBs, Prometheus+Grafana, Tailscale VPN, NGINX stream proxy.

---

## Agent Workflow

### Build & Test
- Start stack: `docker compose up -d`
- Health check: `make check-health`
- Create students: `./scripts/create_students.sh` (requires `credentials/students.txt`)
- Load test: `source .env && PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" ./scripts/loadtest.sh init` and `multi 20 4 60`

### Admin Commands (see `make help`)
- `make shell DB=mydb` — Open psql shell
- `make list-users` / `make list-databases` — Inventory
- `make grant-students-access DB=name` — Grant `students` role access
- `make backup-all` — Full backup to `backups/`

### Student Management
- Usernames: lowercase, alphanumeric/underscore (auto-sanitized)
- DBs: `{username}_db`, owned by user
- All students in `students` role (shared DB access)
- Connection limit: 3 per student

### SQL Init
- Scripts in `init/` run alphabetically on first container start
- Use `scripts/grant_distributed_gan_access.sql` as template for shared DB access

### Environment & Secrets
- Secrets in `.env`: `POSTGRES_ADMIN_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`
- **Never commit `.env`** or files in `credentials/students/`
- Always `source .env` before running scripts needing credentials

### Security & Auth
- SSL certs: `config/ssl/server.crt` and `server.key` required
- Auth rules: `config/pg_hba.conf`
- Students: `NOSUPERUSER NOCREATEDB NOCREATEROLE`

### Monitoring
- Grafana: http://localhost:3000 (admin: `GRAFANA_ADMIN_PASSWORD`)
- Prometheus, postgres-exporter auto-started

### Troubleshooting & Pitfalls
- Must have Tailscale configured on pyrite (local) and gatekeeper (VPS) with both active on the tailnet; NGINX stream proxy must be running on VPS
- Scripts require `.env` and correct permissions
- See `SETUP.md` for full diagnostics, connection, and security troubleshooting

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

See `README.md` and `SETUP.md` for architecture, usage, and troubleshooting details.
