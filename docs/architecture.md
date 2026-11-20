# Architecture

Detailed architecture diagrams for the self-hosted PostgreSQL setup.

## Network topology

The local machine and VPS are both nodes on a Tailscale tailnet. The VPS acts as the public entry point: NGINX receives incoming TCP connections on port 54321 and proxies them over Tailscale to PostgreSQL running on the local machine. There is no direct exposure of the database host to the internet.

```mermaid
flowchart TB
    subgraph Internet
        Students[Students/Clients]
    end
    
    subgraph VPS["VPS (gatekeeper)"]
        PublicIP[Public IP :54321]
        NGINX[NGINX Stream Proxy]
        TS_VPS[Tailscale node]
        PROM[Prometheus<br/>job pyrite-postgres-exporter]
        GRAF[Grafana<br/>postgres-main-overview]
    end
    
    subgraph Home["Local Machine (pyrite)"]
        TS_Local[Tailscale node]
        subgraph Docker[Docker Compose Stack]
            PG[(PostgreSQL 16<br/>:5432 — SSL)]
            Exporter[postgres_exporter<br/>:9187]
        end
    end
    
    Students -->|"TLS+SSL :54321"| PublicIP
    PublicIP --> NGINX
    NGINX -->|"TCP Proxy → <local-tailscale-ip>:5432"| TS_VPS
    TS_VPS <-->|"Tailscale (encrypted)"| TS_Local
    TS_Local --> PG
    
    PG --> Exporter
    Exporter -->|"scrape :9187 over Tailscale"| PROM
    PROM --> GRAF
```

## Docker services

Only PostgreSQL, `postgres-exporter`, and pgAdmin run in Docker on this host. Prometheus and Grafana run on the VPS (`gatekeeper`).

```mermaid
flowchart LR
    subgraph compose["Docker Compose - local machine"]
        subgraph data[Data Layer]
            PG[(postgres<br/>PostgreSQL 16)]
        end
        
        subgraph monitoring[Monitoring Layer]
            EXP[postgres-exporter<br/>:9187]
        end
    end
    
    subgraph vps["VPS - gatekeeper"]
        PROM[Prometheus]
        GRAF[Grafana]
    end

    PG -->|"metrics"| EXP
    EXP -->|"scrape :9187 over Tailscale"| PROM
    PROM -->|"datasource"| GRAF
    
    EXT_DB[External Clients] -->|":5432 SSL"| PG
    EXT_GRAF[Browser] --> GRAF
```

## Data flow

```mermaid
sequenceDiagram
    participant S as Student
    participant N as NGINX (VPS)
    participant T as Tailscale
    participant P as PostgreSQL (local machine)
    
    S->>N: Connect to domain:54321 (SSL handshake)
    N->>T: Forward via Tailscale to <local-tailscale-ip>:5432
    T->>P: Deliver to PostgreSQL
    P->>P: Authenticate (pg_hba.conf + scram-sha-256)
    P->>T: Return result
    T->>N: Forward response
    N->>S: Deliver to client
```

## Security layers

```mermaid
flowchart TB
    subgraph layer1[Layer 1: Network]
        TS[Tailscale Encryption<br/>VPS ↔ local machine]
    end
    
    subgraph layer2[Layer 2: Transport]
        SSL[SSL/TLS Certificates<br/>client → PostgreSQL end-to-end]
    end
    
    subgraph layer3[Layer 3: Authentication]
        AUTH[PostgreSQL Auth<br/>scram-sha-256 via pg_hba.conf]
    end
    
    subgraph layer4[Layer 4: Authorization]
        PERMS[Per-user Databases<br/>Role-based Access]
    end
    
    layer1 --> layer2 --> layer3 --> layer4
```

## Database structure

```mermaid
erDiagram
    ADMIN ||--o{ USER_DB : owns
    ADMIN ||--o{ SHARED_DB : owns
    STUDENT }|--|| USER_DB : "has personal"
    STUDENT }o--o{ SHARED_DB : "collaborates in"
    
    ADMIN {
        string username "admin"
        string role "superuser"
    }
    
    STUDENT {
        string username "e.g. jsmith"
        string password "auto-generated"
        int connection_limit "3"
    }
    
    USER_DB {
        string name "username_db"
        string owner "student"
    }
    
    SHARED_DB {
        string name "e.g. distributed_gan"
        string owner "admin"
        string access "students role"
    }
```

## Backup flow

```mermaid
flowchart LR
    PG[(PostgreSQL)] -->|pg_dump| BACKUP[Backup Script]
    BACKUP -->|gzip| LOCAL[Local Storage]
    LOCAL -->|rsync| NAS[NAS/RAID]
    
    CRON[Cron Job<br/>Daily 2 AM] -->|triggers| BACKUP
```

## Monitoring stack

```mermaid
flowchart TB
    subgraph Local["Local Machine (pyrite)"]
        subgraph PostgreSQL
            PG[(Database)]
            PSS[pg_stat_statements]
            PSA[pg_stat_activity]
        end

        subgraph Exporter["postgres_exporter :9187"]
            COLLECT[Collect Metrics]
        end
    end
    
    subgraph VPS["VPS (gatekeeper)"]
        subgraph Prometheus
            SCRAPE[Scrape Targets<br/>pyrite-postgres-exporter]
            STORE[Time Series DB]
            ALERT[Alerting Rules]
        end

        subgraph Grafana
            DASH[Dashboards<br/>postgres-main-overview]
            VIS[Visualizations]
        end
    end
    
    PG --> PSS
    PG --> PSA
    PSS --> COLLECT
    PSA --> COLLECT
    COLLECT -->|"Tailscale"| SCRAPE
    SCRAPE --> STORE
    STORE --> DASH
    STORE --> ALERT
    DASH --> VIS
```

The local host only exports metrics. Prometheus (job `pyrite-postgres-exporter`) scrapes `$TAILSCALE_IP:9187` over Tailscale, and the `postgres-main-overview` dashboard lives in the central Grafana on the VPS. No Prometheus server or Grafana instance runs locally.

## Viewing these diagrams

These Mermaid diagrams render automatically on:
- GitHub (README, markdown files)
- GitLab
- Notion
- VS Code (with Mermaid extension)

Or paste into [mermaid.live](https://mermaid.live) to view/edit.
