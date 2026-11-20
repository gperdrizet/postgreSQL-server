# postgresSQL-server

A complete, production-ready PostgreSQL setup for educators, indie developers, and small teams who want a secure, monitored database server without enterprise costs.

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![Monitoring](https://img.shields.io/badge/Monitoring-Prometheus%20%2B%20Grafana-E6522C?logo=prometheus&logoColor=white)](https://prometheus.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Why this project?

This project lets you run a **secure, monitored, production-grade database** on a low cost VPS + your existing hardware.

**Perfect for:**

- **Educators** teaching SQL to students (isolated databases per student)
- **Indie developers** needing a real database for side projects
- **Small teams** wanting shared database access without cloud costs
- **Homelab enthusiasts** self-hosting their infrastructure

## Features

| Feature | Description |
| ------- | ----------- |
| **Secure by default** | Tailscale tunnel, SSL/TLS, per-user isolation |
| **Centralized monitoring** | Local postgres-exporter scraped by VPS Prometheus; dashboards in central Grafana |
| **Multi-tenant** | Individual + shared databases for collaboration |
| **Vector search** | pgvector for embeddings and similarity search |
| **Load tested** | Proven for 30+ concurrent users |
| **Complete docs** | Setup guides, troubleshooting, maintenance |
| **Admin tools** | Makefile commands, backup scripts |

## Architecture

```text
   LOCAL MACHINE (pyrite)                    VPS (gatekeeper)
  ┌────────────────────────┐                ┌────────────────────────┐
  │ Docker                 │                │ NGINX stream proxy     │
  │  ├─ PostgreSQL :5432   │◄── Tailscale ──│ :54321 → local :5432   │
  │  └─ postgres-exporter  │──── metrics ──►│ Prometheus (scraper)   │
  │     :9187              │    :9187       │ Grafana (dashboards)   │
  └────────────────────────┘                └────────────────────────┘
```

Students connect to the VPS on `:54321`; NGINX forwards the connection over Tailscale to local PostgreSQL. The VPS hosts the monitoring stack; this machine only exposes metrics. There is no local Prometheus or Grafana service.

## Quick start

### Prerequisites

- Docker and Docker Compose
- A VPS with public IP
- Tailscale installed on both machines and joined to the same tailnet

### 1. Clone and configure

```bash
# Clone this repo
git clone https://github.com/yourusername/postgresSQL-server.git
cd postgresSQL-server

# Create your local configuration
cp .env.template .env

# Generate two passwords and paste them into .env
openssl rand -base64 32   # POSTGRES_ADMIN_PASSWORD
openssl rand -base64 32   # PGADMIN_DEFAULT_PASSWORD

# Then fill in TAILSCALE_IP, DB_HOST, PGDATA_DIR, BACKUP_DIR and
# PGADMIN_DEFAULT_EMAIL — see the configuration reference below.
```

#### Configuration reference

Every host-specific value lives in `.env` (start from `.env.template`). None are optional: Compose and the admin scripts stop with a clear error if a value is missing.

| Variable | Purpose | Example |
| -------- | ------- | ------- |
| `POSTGRES_ADMIN_PASSWORD` | PostgreSQL `admin` password | (generated) |
| `PGADMIN_DEFAULT_PASSWORD` | pgAdmin login password | (generated) |
| `PGADMIN_DEFAULT_EMAIL` | pgAdmin login email | `admin@example.lan` |
| `TAILSCALE_IP` | Tailscale IP of the Docker host; where 5432, 9187 and 8088 are published | `100.64.0.2` |
| `DB_HOST` | Host the Makefile and scripts connect to | `100.64.0.2` |
| `DB_PORT` | PostgreSQL port | `5432` |
| `DB_USER` | PostgreSQL admin user | `admin` |
| `PGDATA_DIR` | Absolute path to the PostgreSQL data directory | `/mnt/fast_scratch/postgreSQL-server/data/postgres` |
| `BACKUP_DIR` | Absolute path for database backups | `/mnt/arkk/postgreSQL-server/backups` |

The same `TAILSCALE_IP` must be set as the upstream in `vps/nginx-stream.conf` on the VPS, and `PGDATA_DIR` must exist before starting the stack.

### 2. Generate SSL certificates

```bash
# Make directory for certs
mkdir -p config/ssl && cd config/ssl

# Generate server certs
openssl req -new -x509 -days 3650 -nodes \
  -out server.crt -keyout server.key -subj "/CN=postgres"

# Set owner only read/write
chmod 600 server.key && sudo chown 999:999 server.key
cd ../..
```

### 3. Start the stack

```bash
docker compose up -d
```

### 4. Configure NGINX on the VPS

Copy `vps/nginx-stream.conf` into `/etc/nginx/nginx.conf` on the VPS (outside the `http {}` block), replace `<db-host-tailscale-ip>` in the upstream with the value of `TAILSCALE_IP`, then reload:

```bash
ssh <your-vps> "sudo nginx -t && sudo systemctl reload nginx"
```

### 5. Create student/user accounts

```bash
# Add usernames to credentials/students.txt
echo -e "alice\nbob\ncharlie" > credentials/students.txt

# Create accounts
./scripts/create_students.sh
```

### 6. Connect

```bash
# Students connect via public endpoint
psql "host=your-domain.com port=54321 dbname=alice_db user=alice sslmode=require"
```

See [Setup guide](docs/setup.md) for complete instructions including Tailscale and NGINX configuration.

## Monitoring

Monitoring is centralized on the VPS (`gatekeeper`); this host only exposes metrics.

| Component | Location | Details |
| --------- | -------- | ------- |
| `postgres-exporter` | Local Docker | `$TAILSCALE_IP:9187` (Tailscale only) |
| Prometheus | VPS (`gatekeeper`) | Scrapes job `pyrite-postgres-exporter` |
| Grafana | VPS (`gatekeeper`) | Dashboard `postgres-main-overview` |

There is no local Prometheus (`:9090`) or Grafana (`:3000`) service.

**The central dashboard shows:**

- Active/idle connections
- Transaction rates
- Cache hit ratio
- Database sizes
- Query performance (via pg_stat_statements)

## Admin commands

```bash
make help              # Show all commands
make list-databases    # List all databases
make list-users        # List all users
make check-health      # PostgreSQL health check
make db-size           # Show database sizes
make shell DB=mydb     # Open psql shell
make backup-all        # Backup all databases
```

pgAdmin is available at `http://$TAILSCALE_IP:8088` (Tailscale only). Log in with `PGADMIN_DEFAULT_EMAIL` and `PGADMIN_DEFAULT_PASSWORD`; the local PostgreSQL server is registered automatically from `config/pgadmin/servers.json`. pgAdmin cannot import passwords, so enter `POSTGRES_ADMIN_PASSWORD` the first time you connect (and save it if you wish).

## Data and backups

- PostgreSQL data lives outside the checkout at `$PGDATA_DIR` (fast local disk), so moving the repository does not move the databases.
- Backups are written to `$BACKUP_DIR` (a separate disk or array) by both `make backup-all` and `scripts/backup.sh`. Override per run with `BACKUP_DIR=/some/path make ...`.
- The pgAdmin state is a Docker named volume; it lives wherever Docker's data root points (`docker info --format '{{.DockerRootDir}}'`).

See the [setup guide](docs/setup.md#moving-the-data-directory) for the one-time data migration procedure.

## Start on boot

The Compose services already use `restart: unless-stopped`, and you can also install a systemd unit to guarantee the project stack is brought up on host boot.

```bash
# Install and enable boot startup
make enable-startup-on-boot

# Verify service status
systemctl is-enabled postgresql-server-stack.service
systemctl is-active postgresql-server-stack.service

# Remove boot startup
make disable-startup-on-boot
```

## Load testing

Verify your setup can handle your expected load:

```bash
# The script loads .env itself (PGPASSWORD defaults to POSTGRES_ADMIN_PASSWORD)

# Initialize test data
./scripts/loadtest.sh init

# Test with 20 concurrent users
./scripts/loadtest.sh multi 20 4 60
```

## Project structure

```text
postgresSQL-server/
├── docker-compose.yml        # PostgreSQL + postgres-exporter + pgAdmin
├── .env.template             # Copy to .env and fill in every value
├── Makefile                  # Admin commands
├── mkdocs.yml                # Documentation site config
├── config/
│   ├── postgresql.conf       # Database configuration
│   ├── pg_hba.conf           # Authentication rules
│   ├── pgadmin/servers.json  # Pre-registered pgAdmin server
│   └── ssl/                  # SSL certificates (git-ignored)
├── scripts/
│   ├── create_students.sh    # User/database creation
│   ├── loadtest.sh           # Performance testing
│   ├── backup.sh             # Automated backups
│   └── lib/load-env.sh       # Shared .env loader/validator
├── vps/
│   └── nginx-stream.conf     # NGINX stream config for the VPS
└── docs/
    ├── index.md              # Documentation site home
    ├── setup.md              # Complete setup guide
    ├── architecture.md       # Architecture diagrams
    └── blog-post.md          # Blog post about the project
```

## Documentation

| Document | Description |
| -------- | ----------- |
| [docs/setup.md](docs/setup.md) | Complete setup instructions |
| [docs/architecture.md](docs/architecture.md) | Architecture diagrams |
| [docs/blog-post.md](docs/blog-post.md) | Project write-up |

## Performance

Tested configuration (modest home server):

| Metric | Single user | 20 concurrent users |
| ------ | ----------- | ------------------- |
| TPS | 258 | 1,661 |
| Latency | 3.9ms | 12ms |
| Failures | 0% | 0% |

## Security

- **Network**: Tailscale encrypted tunnel (no direct database exposure)
- **Transport**: SSL/TLS for all connections
- **Authentication**: Strong passwords, per-user databases
- **Isolation**: Students can only access their own database + shared projects
- **Monitoring**: Connection logging, query tracking

## Contributing

Contributions welcome! Please read the existing documentation and open an issue before submitting PRs.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

Built with:

- [PostgreSQL](https://www.postgresql.org/) - The database
- [pgvector](https://github.com/pgvector/pgvector) - Vector similarity search extension
- [Tailscale](https://tailscale.com/) - VPN mesh network
- [Grafana](https://grafana.com/) - Centralized dashboards (VPS)
- [Prometheus](https://prometheus.io/) - Centralized metrics collection (VPS)
- [Docker](https://www.docker.com/) - Containerization
