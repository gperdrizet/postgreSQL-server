# postgresSQL-server

A complete, production-ready PostgreSQL setup for educators, indie developers, and small teams who want a secure, monitored database server without enterprise costs.

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![Grafana](https://img.shields.io/badge/Grafana-Monitoring-F46800?logo=grafana&logoColor=white)](https://grafana.com/)
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
| **Full monitoring** | Grafana dashboards, Prometheus metrics |
| **Multi-tenant** | Individual + shared databases for collaboration |
| **Vector search** | pgvector for embeddings and similarity search |
| **Load tested** | Proven for 30+ concurrent users |
| **Complete docs** | Setup guides, troubleshooting, maintenance |
| **Admin tools** | Makefile commands, backup scripts |

## Architecture

```text
┌─────────────────────┐         Tailscale Tunnel        ┌─────────────────────┐
│   LOCAL MACHINE     │◄───────────────────────────────►│        VPS          │
│                     │      (encrypted, persistent)    │                     │
│  ┌───────────────┐  │                                 │  ┌───────────────┐  │
│  │ Docker        │  │                                 │  │ NGINX Stream  │  │
│  │ ├─ PostgreSQL │  │                                 │  │ (TCP Proxy)   │  │
│  │ ├─ Prometheus │  │                                 │  │ :54321        │  │
│  │ └─ Grafana    │  │                                 │  └───────────────┘  │
│  └───────────────┘  │                                 │                     │
│                     │                                 │ Public IP: x.x.x.x  │
│ Tailscale: <local>  │                                 │  Tailscale: <vps>   │
└─────────────────────┘                                 └─────────────────────┘
                                                                  ▲
                                                        Students/clients
                                                        connect here
```

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

# Generate secure passwords
echo "POSTGRES_ADMIN_PASSWORD=$(openssl rand -base64 32)" > .env
echo "GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)" >> .env
```

### 2. Generate SSL certificates

```bash
# Make directory for certs
mkdir -p config/ssl && cd config/ssl

# Generate server certs
openssl req -new -x509 -days 3650 -nodes \
  -out server.crt -keyout server.key -subj "/CN=postgres"

# Set owner only read/write
chmod 600 server.key && sudo chown 70:70 server.key
cd ../..
```

### 3. Start the stack

```bash
docker compose up -d
```

### 4. Configure NGINX on the VPS

Copy `vps/nginx-stream.conf` into `/etc/nginx/nginx.conf` on the VPS (outside the `http {}` block) and reload:

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

Access Grafana at `http://localhost:3000` (login: `admin` / value of `GRAFANA_ADMIN_PASSWORD`).

**Pre-configured dashboard shows:**

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
# Initialize test data
source .env && PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" ./scripts/loadtest.sh init

# Test with 20 concurrent users
source .env && PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" ./scripts/loadtest.sh multi 20 4 60
```

## Project structure

```text
postgresSQL-server/
├── docker-compose.yml        # PostgreSQL + monitoring stack
├── Makefile                  # Admin commands
├── mkdocs.yml                # Documentation site config
├── config/
│   ├── postgresql.conf       # Database configuration
│   ├── pg_hba.conf           # Authentication rules
│   ├── prometheus.yml        # Metrics collection
│   ├── ssl/                  # SSL certificates (git-ignored)
│   └── grafana/              # Dashboard provisioning
├── scripts/
│   ├── create_students.sh    # User/database creation
│   ├── loadtest.sh           # Performance testing
│   └── backup.sh             # Automated backups
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
- [Grafana](https://grafana.com/) - Monitoring dashboards
- [Prometheus](https://prometheus.io/) - Metrics collection
- [Docker](https://www.docker.com/) - Containerization
