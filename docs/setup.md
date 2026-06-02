# PostgreSQL database setup for students

A locally-hosted PostgreSQL database in Docker, exposed to the internet via Tailscale and NGINX stream proxy.

## Table of contents

- [Architecture overview](#architecture-overview)
- [Components](#components)
- [Directory structure](#directory-structure)
- [Setup instructions](#setup-instructions)
  - [Prerequisites](#prerequisites)
  - [Step 1: Configure environment](#step-1-configure-environment)
  - [Step 2: Set up Tailscale](#step-2-set-up-tailscale)
  - [Step 3: Start PostgreSQL](#step-3-start-postgresql)
  - [Step 4: Configure NGINX on VPS](#step-4-configure-nginx-on-vps)
  - [Step 5: Create student accounts](#step-5-create-student-accounts)
  - [Step 6: Create shared database (optional)](#step-6-create-shared-database-optional)
  - [Step 7: Set up backups](#step-7-set-up-backups)
  - [Step 8: Test connection](#step-8-test-student-connection)
- [Student connection guide](#student-connection-guide)
  - [Connection details](#connection-details)
  - [Connection string format](#connection-string-format)
  - [Using psql](#using-psql)
  - [Using Python (psycopg2)](#using-python-psycopg2)
  - [Using Node.js (pg)](#using-nodejs-pg)
- [Maintenance](#maintenance)
  - [View logs](#view-logs)
  - [Restart database](#restart-database)
  - [Manual backup](#manual-backup)
  - [Restore from backup](#restore-from-backup)
  - [Reset student password](#reset-student-password)
  - [Add new student](#add-new-student)
- [Monitoring](#monitoring)
  - [Services](#services)
  - [Starting the monitoring stack](#starting-the-monitoring-stack)
  - [Accessing Grafana](#accessing-grafana)
  - [Pre-configured dashboard](#pre-configured-dashboard)
  - [Query statistics with pg_stat_statements](#query-statistics-with-pg_stat_statements)
- [Load testing](#load-testing)
  - [Set-up](#set-up)
  - [Using the load test script](#using-the-load-test-script)
  - [Test types](#test-types)
  - [Interpreting results](#interpreting-results)
  - [Monitoring during load tests](#monitoring-during-load-tests)
  - [Custom load test scripts](#custom-load-test-scripts)
- [Security notes](#security-notes)
- [Security hardening (optional)](#security-hardening-optional)
  - [Fail2ban for PostgreSQL connections](#fail2ban-for-postgresql-connections)
  - [NGINX rate limiting](#nginx-rate-limiting)
- [Troubleshooting](#troubleshooting)
  - [Quick diagnostic commands](#quick-diagnostic-commands)

## Architecture overview

```text
┌─────────────────────┐         Tailscale Tunnel        ┌─────────────────────┐
│   LOCAL MACHINE     │◄───────────────────────────────►│         VPS         │
│                     │      (encrypted, persistent)    │                     │
│  ┌───────────────┐  │                                 │  ┌───────────────┐  │
│  │ Docker        │  │                                 │  │ NGINX Stream  │  │
│  │ PostgreSQL    │  │                                 │  │ (TCP Proxy)   │  │
│  │ :5432 (SSL)   │  │                                 │  │ :54321        │  │
│  └───────────────┘  │                                 │  └───────────────┘  │
│                     │                                 │                     │
│ Tailscale: <local>  │                                 │  Tailscale: <vps>   │
└─────────────────────┘                                 └─────────────────────┘
                                                                  ▲
                                                                  │
                                                                  │ TLS encrypted
                                                                  │
                                                          Students connect
                                                          your-domain:54321
```

## Components

| Component | Location | Purpose |
| --------- | -------- | ------- |
| PostgreSQL 16 | Local (Docker) | Database server |
| Tailscale | Local ↔ VPS | Encrypted tunnel |
| NGINX Stream | VPS | TCP/SSL proxy |
| Backup Scripts | Local | Automated backups to HDD RAID |

## Directory structure

```text
postgresSQL-server/
├── docker-compose.yml            # PostgreSQL + monitoring stack
├── .env                          # Admin credentials (git-ignored)
├── .gitignore
├── config/
│   ├── postgresql.conf           # PostgreSQL server configuration
│   ├── pg_hba.conf               # Client authentication rules
│   ├── prometheus.yml            # Prometheus scrape configuration
│   ├── ssl/                      # SSL certificates (git-ignored)
│   └── grafana/
│       ├── provisioning/
│       │   ├── datasources/      # Auto-configured Prometheus datasource
│       │   └── dashboards/       # Dashboard provisioning config
│       └── dashboards/           # Pre-built dashboard JSON files
├── init/
│   └── 00-init.sql               # Runs on first container start
├── scripts/
│   ├── create_students.sh        # Create student accounts from credentials/students.txt
│   ├── backup.sh                 # Daily backup script
│   ├── setup-backup-cron.sh      # Install backup cron job
│   ├── loadtest.sh               # Load testing with pgbench
│   └── custom_loadtest.sql       # Custom load test SQL script
├── vps/
│   └── nginx-stream.conf         # NGINX stream config for the VPS
├── docs/
│   ├── index.md                  # Documentation site home
│   ├── setup.md                  # This file
│   ├── architecture.md           # Architecture diagrams
│   └── blog-post.md              # Blog post about the project
├── credentials/                  # Generated student credentials (git-ignored)
│   ├── students.txt              # Student usernames, one per line
│   └── student_credentials.csv
└── data/                         # PostgreSQL data directory (git-ignored)
    └── postgres/
```

## Setup instructions

### Prerequisites

- Docker and Docker Compose installed locally
- Tailscale installed on both local machine and VPS, both joined to the same tailnet
- NGINX with stream module on VPS
- SSH access to VPS

### Step 1: Configure environment

Create a `.env` file in the project root:

```bash
# Generate both required passwords
echo "POSTGRES_ADMIN_PASSWORD=$(openssl rand -base64 32)" > .env
echo "GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)" >> .env
```

### Step 2: Set up Tailscale

Both the local machine and VPS must be joined to the same Tailscale network (tailnet). The VPS acts as the headnode.

1. Install Tailscale on each machine if not already installed:

   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   ```

2. Authenticate each machine to your tailnet:

   ```bash
   sudo tailscale up
   ```

3. Verify both machines are visible to each other:

   ```bash
   tailscale status
   ```

   Both machines should show as active, e.g.:

   ```
   100.64.0.x  <vps>           <account>  linux  active
   100.64.0.y  <local-machine> <account>  linux  active
   ```

4. Open the PostgreSQL proxy port on the VPS firewall:

   ```bash
   sudo ufw allow 54321/tcp
   ```

5. Test connectivity from the local machine to the VPS:

   ```bash
   ping <vps-tailscale-ip>
   ```

> **Note:** Tailscale uses the `100.64.0.0/10` CGNAT range. All traffic between tailnet peers is encrypted end-to-end. No manual key exchange or inter-peer firewall rules are needed.

### Step 3: Start PostgreSQL

1. Start the container:

   ```bash
   docker compose up -d
   ```

2. Verify it's running:

   ```bash
   docker compose ps
   docker logs student-postgres
   ```

3. Test local connection:

   ```bash
   docker exec -it student-postgres psql -U admin -d postgres
   ```

### Step 4: Configure NGINX on VPS

1. Check if stream module is available:

   ```bash
   nginx -V 2>&1 | grep stream
   ```

2. If not available, install nginx-full:

   ```bash
   sudo apt install nginx-full
   ```

3. Edit `/etc/nginx/nginx.conf` and add the stream block from `vps/nginx-stream.conf`
   - Add OUTSIDE the `http {}` block
   - Update SSL certificate paths to match your setup

4. Test configuration:

   ```bash
   sudo nginx -t
   ```

5. Reload NGINX:

   ```bash
   sudo systemctl reload nginx
   ```

### Step 5: Create student accounts

1. Create a `credentials/students.txt` file with one username per line:

   ```text
   jsmith
   mgarcia
   kwilson
   # Lines starting with # are ignored
   ```

   Usernames should be lowercase with no spaces (letters, numbers, underscores only).

2. Make scripts executable:

   ```bash
   chmod +x scripts/*.sh
   ```

3. Run the student creation script:

   ```bash
   ./scripts/create_students.sh
   ```

4. Credentials will be saved to `credentials/student_credentials.csv`

### Step 6: Create shared database (optional)

If students need a collaborative database they can all access:

1. Connect as admin and create the database:

   ```bash
   source .env
   PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" psql -h localhost -U admin -d postgres
   ```

2. Run the following SQL (replace `your_database_name` with your desired name):

   ```sql
   -- Create the shared database
   CREATE DATABASE your_database_name;

   -- Connect to it
   \c your_database_name

   -- Create a shared role for students
   CREATE ROLE students;

   -- Grant schema permissions
   GRANT ALL ON SCHEMA public TO students;

   -- Default privileges: students can use each other's tables
   ALTER DEFAULT PRIVILEGES FOR ROLE students IN SCHEMA public
       GRANT ALL ON TABLES TO students;
   ALTER DEFAULT PRIVILEGES FOR ROLE students IN SCHEMA public
       GRANT ALL ON SEQUENCES TO students;

   -- Add existing students to the role (repeat for each student)
   GRANT students TO jsmith, mgarcia, kwilson, alee;

   -- Allow students to connect
   GRANT CONNECT ON DATABASE your_database_name TO students;
   ```

3. Students can now connect:

   ```bash
   psql "host=your-domain.com port=54321 dbname=your_database_name user=jsmith sslmode=require"
   ```

**Note:** New students created via `create_students.sh` are automatically added to the `students` role.

### Step 7: Set up backups

1. Edit `scripts/backup.sh` and update `BACKUP_DIR` to your HDD RAID path

2. Test backup:

   ```bash
   ./scripts/backup.sh
   ```

3. Install cron job:

   ```bash
   ./scripts/setup-backup-cron.sh
   ```

### Step 8: Test student connection

From any external machine:

```bash
psql "host=your-domain.com port=54321 dbname=student01_db user=student01 sslmode=require"
```

## Student connection guide

### Connection details

| Setting | Value |
| ------- | ----- |
| Host | `your-domain.com` |
| Port | `54321` |
| Database | `studentXX_db` (your assigned database) |
| Username | `studentXX` (your assigned username) |
| Password | (provided separately) |

### Connection string format

```bash
postgresql://studentXX:PASSWORD@your-domain.com:54321/studentXX_db?sslmode=require
```

### Using psql

```bash
psql "host=your-domain.com port=54321 dbname=student01_db user=student01 sslmode=require"
```

### Using Python (psycopg2)

```python
import psycopg2

conn = psycopg2.connect(
    host="your-domain.com",
    port=54321,
    database="student01_db",
    user="student01",
    password="YOUR_PASSWORD",
    sslmode="require"
)
```

### Using Node.js (pg)

```javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: 'your-domain.com',
  port: 54321,
  database: 'student01_db',
  user: 'student01',
  password: 'YOUR_PASSWORD',
  ssl: { rejectUnauthorized: false }
});
```

## Maintenance

### View logs

```bash
docker logs -f student-postgres
```

### Restart database

```bash
docker compose restart
```

### Manual backup

```bash
./scripts/backup.sh
```

### Restore from backup

```bash
gunzip -c /path/to/backup.sql.gz | docker exec -i student-postgres psql -U admin
```

### Reset student password

```bash
docker exec -it student-postgres psql -U admin -c "ALTER USER student01 WITH PASSWORD 'new_password';"
```

### Add new student

The preferred method is adding the username to `credentials/students.txt` and re-running `./scripts/create_students.sh` — it is idempotent and handles role membership automatically.

To add a single student manually:

```bash
docker exec -it student-postgres psql -U admin <<EOF
CREATE USER newuser WITH PASSWORD 'secure_password' CONNECTION LIMIT 3 NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE newuser_db OWNER newuser;
REVOKE ALL ON DATABASE newuser_db FROM PUBLIC;
GRANT CONNECT ON DATABASE newuser_db TO newuser;
GRANT students TO newuser;
EOF
```

## Monitoring

The stack includes a full monitoring solution with Prometheus, Grafana, and pg_stat_statements.

### Services

| Service | URL | Purpose |
| ------- | --- | ------- |
| Grafana | <http://localhost:3000> | Dashboards and visualization |
| Prometheus | <http://localhost:9090> | Metrics collection and storage |
| postgres_exporter | <http://localhost:9187> | PostgreSQL metrics exporter |

### Starting the monitoring stack

```bash
docker compose up -d
```

All monitoring services start automatically with PostgreSQL.

### Accessing Grafana

1. Open <http://localhost:3000>
2. Login with:
   - Username: `admin`
   - Password: Value of `GRAFANA_ADMIN_PASSWORD` from `.env` (default: `admin`)
3. The PostgreSQL Overview dashboard is pre-configured

### Pre-configured dashboard

The PostgreSQL Overview dashboard shows:

- Active and idle connections
- Cache hit ratio
- Database size
- Connections over time
- Row operations rate (inserts, updates, deletes, fetches)
- Transaction rate (commits vs rollbacks)
- Locks by mode

### pgvector — vector similarity search

The `vector` extension (pgvector 0.8.x) is pre-installed via the `pgvector/pgvector:pg16` image and enabled automatically in the `postgres` database on first start.

**Enable in any database:**

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

**Basic usage:**

```sql
-- Create a table with a vector column (e.g. 1536-dim OpenAI embeddings)
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(1536)
);

-- Insert a vector
INSERT INTO documents (content, embedding) VALUES ('hello world', '[0.1, 0.2, ...]');

-- Nearest-neighbour search (cosine distance)
SELECT id, content
FROM documents
ORDER BY embedding <=> '[0.1, 0.2, ...]'
LIMIT 5;

-- Create an index for fast ANN search
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);
```

**Distance operators:**

| Operator | Metric |
| -------- | ------ |
| `<->` | L2 (Euclidean) distance |
| `<#>` | Negative inner product |
| `<=>` | Cosine distance |
| `<+>` | L1 (taxicab) distance |

See the [pgvector documentation](https://github.com/pgvector/pgvector) for full index options (`ivfflat`, `hnsw`) and query tuning.

### Query statistics with pg_stat_statements

Query-level statistics are available via the `pg_stat_statements` extension:

```sql
-- Top 10 slowest queries by total time
SELECT 
    substring(query, 1, 50) as query_preview,
    calls,
    round(total_exec_time::numeric, 2) as total_ms,
    round(mean_exec_time::numeric, 2) as avg_ms,
    rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

-- Most frequently called queries
SELECT 
    substring(query, 1, 50) as query_preview,
    calls,
    round(mean_exec_time::numeric, 2) as avg_ms
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 10;

-- Reset statistics
SELECT pg_stat_statements_reset();
```

## Load testing

Load testing is done with `pgbench`, PostgreSQL's built-in benchmarking tool.

### Set-up

Install pgbench locally:

```bash
sudo apt install postgresql-contrib
```

Or run tests inside the container:

```bash
docker exec -it student-postgres pgbench ...
```

### Using the load test script

```bash
# Initialize test tables (required before first test)
PGPASSWORD=your_password ./scripts/loadtest.sh init

# Single user hammering the server (60 seconds)
PGPASSWORD=your_password ./scripts/loadtest.sh single

# Multiple users (20 clients, 4 threads, 60 seconds)
PGPASSWORD=your_password ./scripts/loadtest.sh multi

# Stress test (50 clients, 8 threads, 120 seconds)
PGPASSWORD=your_password ./scripts/loadtest.sh stress

# Read-only test (SELECT queries only)
PGPASSWORD=your_password ./scripts/loadtest.sh readonly

# Custom duration/parameters
PGPASSWORD=your_password ./scripts/loadtest.sh multi 30 4 90

# Clean up test tables when done
PGPASSWORD=your_password ./scripts/loadtest.sh cleanup
```

### Test types

| Test | Clients | Description |
| ---- | ------- | ----------- |
| `single` | 1 | One user making continuous requests |
| `multi` | 20 | Simulate typical class usage |
| `stress` | 50 | Push server to limits |
| `readonly` | 30 | SELECT-only workload |
| `custom` | varies | Run your own SQL script |

### Interpreting results

pgbench outputs:

- **TPS (transactions per second)**: Higher is better
- **Latency**: Average time per transaction (lower is better)
- **stddev**: Consistency of response times

Example output:

```text
pgbench (PostgreSQL 16.1)
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
number of clients: 20
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 45231
number of failed transactions: 0 (0.000%)
latency average = 26.521 ms
latency stddev = 18.432 ms
initial connection time = 89.234 ms
tps = 754.012345 (without initial connection time)
```

### Monitoring during load tests

1. Open Grafana (<http://localhost:3000>) before starting a test
2. Watch the PostgreSQL Overview dashboard in real-time
3. You'll see connections spike, transaction rates increase, and can identify bottlenecks

### Custom load test scripts

Create custom scenarios in `scripts/custom_loadtest.sql`:

```sql
-- Example: Simulate student workload
\set student_id random(1, 30)
\set assignment_id random(1, 100)

SELECT * FROM assignments WHERE id = :assignment_id;
UPDATE submissions SET updated_at = NOW() WHERE student_id = :student_id;
```

Run with:

```bash
PGPASSWORD=secret ./scripts/loadtest.sh custom scripts/custom_loadtest.sql 15 60
```

## Security notes

- Each student is limited to 3 concurrent connections
- Query timeout is set to 30 seconds
- Students can only access their own database
- Tailscale encrypts all traffic between the local machine and the VPS using WireGuard under the hood
- SSL/TLS is enforced at the PostgreSQL level — all connections must use `sslmode=require`; this means traffic is double-encrypted end-to-end from client to database

## Security hardening (optional)

These additional measures protect against brute-force attacks and connection flooding.

### Fail2ban for PostgreSQL connections

Fail2ban automatically bans IPs that have too many failed connection attempts.

**1. Create the filter** (on VPS):

```bash
sudo tee /etc/fail2ban/filter.d/nginx-stream.conf << 'EOF'
[Definition]
failregex = ^<HOST> \[.*\] TCP 502
            ^<HOST> \[.*\] TCP 500
ignoreregex =
EOF
```

**2. Add the jail** (on VPS):

```bash
sudo tee -a /etc/fail2ban/jail.local << 'EOF'

[nginx-stream]
enabled = true
port = 54321
filter = nginx-stream
logpath = /var/log/nginx/stream_access.log
maxretry = 10
bantime = 3600
findtime = 600
EOF
```

**3. Restart fail2ban:**

```bash
sudo systemctl restart fail2ban
```

**4. Verify the jail is active:**

```bash
sudo fail2ban-client status
```

You should see `nginx-stream` in the jail list.

**Useful fail2ban commands:**

```bash
# Check status of PostgreSQL jail
sudo fail2ban-client status nginx-stream

# Unban an IP
sudo fail2ban-client set nginx-stream unbanip 1.2.3.4

# View banned IPs
sudo fail2ban-client get nginx-stream banip
```

### NGINX rate limiting

Rate limiting prevents any single IP from opening too many connections.

The NGINX stream config (`vps/nginx-stream.conf`) includes:

```nginx
stream {
    # Track connections per IP (10MB zone = ~160,000 IPs)
    limit_conn_zone $binary_remote_addr zone=postgres_conn:10m;

    server {
        listen 54321;
        proxy_pass postgresql_backend;
        
        # Timeout settings
        proxy_timeout 600s;           # Allow long-running queries (10 min)
        proxy_connect_timeout 30s;    # Connection establishment timeout
        
        # Buffer settings for better throughput
        proxy_buffer_size 16k;
        
        # Limit to 5 concurrent connections per IP
        limit_conn postgres_conn 5;
    }
}
```

This limits each IP address to 5 concurrent connections. Since each student is limited to 3 database connections, this provides headroom while preventing any single user from monopolizing server resources. The extended timeouts (600s) allow for long-running student queries.

To apply rate limiting, update the stream block in `/etc/nginx/nginx.conf` on the VPS and reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

## Troubleshooting

### Quick diagnostic commands

Run these commands to quickly identify where a connection issue is occurring:

**From your client machine:**

```bash
# Test if port is reachable
nc -zv your-domain.com 54321

# Test PostgreSQL connection
psql "host=your-domain.com port=54321 dbname=jsmith_db user=jsmith"
```

**On the VPS:**

```bash
# Check if NGINX is listening on the port
sudo ss -tlnp | grep 54321

# Check Tailscale status and peer connectivity
tailscale status

# Test connection to PostgreSQL through Tailscale
nc -zv <local-tailscale-ip> 5432

# Test PostgreSQL directly through Tailscale
PGPASSWORD=password psql -h <local-tailscale-ip> -p 5432 -U username -d database_name

# Check NGINX stream logs
sudo tail -20 /var/log/nginx/stream_error.log

# Verify stream block is loaded in NGINX config
sudo nginx -T 2>&1 | grep -A5 'stream {'

# Check firewall status
sudo ufw status
```

**On the local machine (PostgreSQL host):**

```bash
# Check if PostgreSQL container is running
docker compose ps

# Check PostgreSQL logs
docker logs student-postgres 2>&1 | tail -30

# Test local PostgreSQL connection
docker exec -it student-postgres psql -U admin -d postgres
```

### Cannot connect to database

#### Symptom: Connection timed out

1. Check if port is open on VPS: `ssh your-vps "sudo ss -tlnp | grep 54321"`
2. Check VPS firewall: `ssh your-vps "sudo ufw status | grep 54321"`
3. Check hosting provider firewall (web panel) - many providers have separate firewalls
4. Test port reachability: `nc -zv your-domain.com 54321`

#### Symptom: Connection refused

1. Check NGINX is running: `ssh your-vps "sudo systemctl status nginx"`
2. Verify stream block is in nginx.conf: `ssh your-vps "sudo nginx -T | grep -A3 'stream {'"`
3. Check NGINX config syntax: `ssh your-vps "sudo nginx -t"`

#### Symptom: Server closed connection unexpectedly

1. Check NGINX stream error log: `ssh <your-vps> "sudo tail -20 /var/log/nginx/stream_error.log"`
2. Test Tailscale connectivity from VPS: `ssh <your-vps> "nc -zv <local-tailscale-ip> 5432"`
3. Check PostgreSQL logs: `docker logs student-postgres 2>&1 | tail -30`
4. Verify pg_hba.conf allows connections from Tailscale network (`100.64.0.0/10`)

### Tailscale connectivity issues

1. Check that both machines are active on the tailnet:

   ```bash
   # On either machine
   tailscale status
   ```

   Both the local machine and VPS should show as active with their respective Tailscale IPs.

2. Test direct connectivity:

   ```bash
   # From the local machine
   ping <vps-tailscale-ip>

   # From the VPS
   ssh <your-vps> "ping -c 3 <local-tailscale-ip>"
   ```

3. Re-authenticate if a machine shows offline:

   ```bash
   sudo tailscale up
   ```

### NGINX stream not working

1. Verify stream module is available:

   ```bash
   nginx -V 2>&1 | grep stream
   ```

   If not present, install nginx-full:

   ```bash
   sudo apt install nginx-full
   ```

2. Check config syntax: `sudo nginx -t`

3. Ensure stream block is OUTSIDE http block in `/etc/nginx/nginx.conf`

4. Check if port is listening: `sudo ss -tlnp | grep 54321`

5. View stream access log: `sudo tail -f /var/log/nginx/stream_access.log`

### PostgreSQL authentication errors

1. Check pg_hba.conf has correct entries for the Tailscale network (`100.64.0.0/10`)
2. Verify username and password are correct
3. Check if user exists:

   ```bash
   docker exec -it student-postgres psql -U admin -c "\\du"
   ```

4. Check if database exists:

   ```bash
   docker exec -it student-postgres psql -U admin -c "\\l"
   ```

---

## SSL certificate setup

SSL is already enabled in this stack — `pg_hba.conf` uses `hostssl` for all remote connections and the certificates are mounted into the PostgreSQL container. This section documents how the certificates are generated so they can be regenerated if needed.

### Generate certificates

```bash
mkdir -p ./config/ssl
cd ./config/ssl

# Generate a self-signed certificate (valid for 10 years)
openssl req -new -x509 -days 3650 -nodes \
  -out server.crt \
  -keyout server.key \
  -subj "/CN=postgres"

# Set permissions — PostgreSQL requires the key owned by UID 70 (postgres in alpine)
chmod 600 server.key
chmod 644 server.crt
sudo chown 70:70 server.key
```

The certificates live in `config/ssl/` which is excluded from git. After regenerating, restart the container:

```bash
docker compose restart postgres
```

### Stricter client verification

By default students connect with `sslmode=require`, which encrypts but doesn't verify the server certificate. To enforce certificate verification:

```bash
# Copy server.crt to the client machine, then:
psql "host=your-domain.com port=54321 dbname=jsmith_db user=jsmith sslmode=verify-ca sslrootcert=/path/to/server.crt"
```

**Python:**

```python
conn = psycopg2.connect(
    host="your-domain.com",
    port=54321,
    database="student01_db",
    user="student01",
    password="YOUR_PASSWORD",
    sslmode="require"
)
```

**Node.js:**

```javascript
const pool = new Pool({
  host: 'your-domain.com',
  port: 54321,
  database: 'student01_db',
  user: 'student01',
  password: 'YOUR_PASSWORD',
  ssl: { rejectUnauthorized: false }  // set to true and provide ca if using verify-ca
});
```
