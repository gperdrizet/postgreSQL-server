# How I built a secure PostgreSQL server for my students for under $10/month

*A complete guide to self-hosting a production-grade database with monitoring, without cloud database costs.*

---

## The problem

I teach a database course and needed to give 30 students access to PostgreSQL. My options:

| Option | Monthly Cost | Issues |
|--------|--------------|--------|
| AWS RDS | $15-50+ | Expensive for a class |
| Heroku Postgres | $9-50+ | Limited free tier |
| PlanetScale/Supabase | Free tier limits | Not enough for a full class |
| Shared hosting | Varies | Usually no raw SQL access |

What I really wanted:
- Each student gets their own isolated database
- A shared database for collaborative projects
- Real PostgreSQL (not a managed wrapper)
- Monitoring to see what's happening
- Costs under $10/month

## The solution

**Self-host PostgreSQL on existing hardware, expose it securely through a cheap VPS.**

Final cost:
- **VPS**: $5/month (just for the public IP and proxy)
- **Database server**: My existing home server (or any always-on computer)
- **Total**: $5/month for unlimited students

## Architecture overview

```
Students → VPS ($5) → WireGuard Tunnel → Home Server → PostgreSQL
                ↑
         NGINX TCP Proxy
         (no database here,
          just forwarding)
```

The VPS doesn't run the database—it's just a secure entry point. The actual PostgreSQL runs on my local machine with:
- More storage
- Better CPU
- Zero egress costs
- Full control

WireGuard creates an encrypted tunnel between them.

## What I built

### Core stack
- **PostgreSQL 16** in Docker
- **WireGuard** VPN tunnel
- **NGINX Stream** module for TCP proxying

### Monitoring
- **Prometheus** for metrics collection
- **Grafana** for dashboards
- **postgres_exporter** for PostgreSQL metrics

### Automation
- Student account creation script
- Daily backup scripts
- Load testing with pgbench

## Key features

### 1. Per-student isolation

Each student gets:
```sql
CREATE USER jsmith WITH PASSWORD 'auto_generated';
CREATE DATABASE jsmith_db OWNER jsmith;
-- They can only see their own database
```

### 2. Shared collaboration database

For group projects:
```sql
CREATE DATABASE project_db;
CREATE ROLE students;
GRANT ALL ON DATABASE project_db TO students;
GRANT students TO jsmith, mgarcia, kwilson;
-- Now they can all collaborate
```

### 3. Full monitoring

Grafana shows me:
- Active connections (who's working?)
- Query performance (anyone running slow queries?)
- Transaction rates (load during assignments)
- Cache hit ratios (is the server healthy?)

### 4. Production-grade security

Multiple layers:
1. **WireGuard**: All traffic encrypted, database never directly exposed
2. **SSL/TLS**: Even inside the tunnel, connections are encrypted
3. **Authentication**: Strong auto-generated passwords
4. **Isolation**: Students can't see each other's databases

## Performance results

I load-tested with pgbench to make sure it could handle a full class:

| Scenario | TPS | Latency |
|----------|-----|---------|
| Single user | 258 | 3.9ms |
| 20 concurrent users | 1,661 | 12ms |
| 30 concurrent users | Stable | <20ms |

More than enough for 30 students running queries.

## The setup (simplified)

### 1. VPS setup (10 minutes)

```bash
# Install WireGuard and NGINX
apt install wireguard nginx

# Configure WireGuard
# Configure NGINX stream to proxy port 54321 → WireGuard peer
```

### 2. Local machine (15 minutes)

```bash
# Clone the repo
git clone https://github.com/yourusername/postgresSQL-server.git
cd postgresSQL-server

# Set passwords
echo "POSTGRES_ADMIN_PASSWORD=$(openssl rand -base64 32)" > .env

# Start everything
docker compose up -d
```

### 3. Create students (2 minutes)

```bash
echo -e "jsmith\nmgarcia\nkwilson" > students.txt
./scripts/create_students.sh
# Credentials saved to credentials/student_credentials.csv
```

### 4. Students connect

```bash
psql "host=yourdomain.com port=54321 dbname=jsmith_db user=jsmith sslmode=require"
```

## Lessons learned

### What worked well

1. **WireGuard is amazing** - Simple, fast, "it just works"
2. **Docker Compose** - One command to start everything
3. **Grafana provisioning** - Dashboards auto-configured on startup
4. **pgbench** - Essential for validating the setup

### Gotchas

1. **Passwords with special characters** - URL encoding issues. Use `quote_plus()` in Python or connection objects instead of URL strings.

2. **Statement timeouts** - Set a reasonable default (30s) to prevent runaway queries, but remember to disable for bulk operations.

3. **NGINX Stream module** - Different from regular HTTP proxy. Needs `stream {}` block, not `http {}`.

## Who should use this?

- **Teachers** giving students real database access
- **Indie developers** who want a cheap production database
- **Small teams** needing shared database access
- **Homelab enthusiasts** who want to learn PostgreSQL administration

## The full project

I've open-sourced everything:

**GitHub**: [github.com/yourusername/postgresSQL-server](https://github.com/yourusername/postgresSQL-server)

Includes:
- Complete Docker Compose setup
- WireGuard configuration templates
- NGINX stream configuration
- Student creation scripts
- Backup automation
- Load testing scripts
- Grafana dashboards
- Comprehensive documentation

## Conclusion

For $5/month, I have:
- 30+ isolated student databases
- Shared collaboration databases
- Full monitoring and alerting
- Automated backups
- Production-grade security

The cloud database providers are great for many use cases, but sometimes you just need a PostgreSQL server that you control—without the enterprise price tag.

---

*Questions? Open an issue on the repo or find me on [Twitter/LinkedIn/etc].*

---

**Tags**: #postgresql #selfhosted #docker #education #devops #homelab
