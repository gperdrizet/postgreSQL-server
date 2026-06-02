# Architecture

Detailed architecture diagrams for the self-hosted PostgreSQL setup.

## Network topology

```mermaid
flowchart TB
    subgraph Internet
        Students[Students/Clients]
    end
    
    subgraph VPS["VPS ($5/month)"]
        PublicIP[Public IP :54321]
        NGINX[NGINX Stream Proxy]
        WG_Server[WireGuard Server<br/>10.0.0.1]
    end
    
    subgraph Home["Local Machine / Home Server"]
        WG_Client[WireGuard Client<br/>10.0.0.2]
        subgraph Docker[Docker Compose Stack]
            PG[(PostgreSQL 16<br/>:5432)]
            Prometheus[Prometheus<br/>:9090]
            Grafana[Grafana<br/>:3000]
            Exporter[postgres_exporter<br/>:9187]
        end
    end
    
    Students -->|"TLS :54321"| PublicIP
    PublicIP --> NGINX
    NGINX -->|"TCP Proxy"| WG_Server
    WG_Server <-->|"WireGuard Tunnel<br/>Encrypted"| WG_Client
    WG_Client --> PG
    
    PG --> Exporter
    Exporter --> Prometheus
    Prometheus --> Grafana
```

## Docker services

```mermaid
flowchart LR
    subgraph compose[Docker Compose]
        subgraph data[Data Layer]
            PG[(postgres<br/>PostgreSQL 16)]
        end
        
        subgraph monitoring[Monitoring Layer]
            EXP[postgres-exporter]
            PROM[prometheus]
            GRAF[grafana]
        end
    end
    
    PG -->|"metrics"| EXP
    EXP -->|"scrape :9187"| PROM
    PROM -->|"datasource"| GRAF
    
    EXT_DB[External Clients] -->|":5432"| PG
    EXT_GRAF[Browser] -->|":3000"| GRAF
```

## Data flow

```mermaid
sequenceDiagram
    participant S as Student
    participant N as NGINX (VPS)
    participant W as WireGuard Tunnel
    participant P as PostgreSQL
    
    S->>N: Connect to domain:54321
    N->>W: Forward via WireGuard
    W->>P: Deliver to PostgreSQL :5432
    P->>P: Authenticate user
    P->>W: Return result
    W->>N: Forward response
    N->>S: Deliver to client
```

## Security layers

```mermaid
flowchart TB
    subgraph layer1[Layer 1: Network]
        WG[WireGuard Encryption]
    end
    
    subgraph layer2[Layer 2: Transport]
        SSL[SSL/TLS Certificates]
    end
    
    subgraph layer3[Layer 3: Authentication]
        AUTH[PostgreSQL Auth<br/>pg_hba.conf]
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
    subgraph PostgreSQL
        PG[(Database)]
        PSS[pg_stat_statements]
        PSA[pg_stat_activity]
    end
    
    subgraph Exporter[postgres_exporter]
        COLLECT[Collect Metrics]
    end
    
    subgraph Prometheus
        SCRAPE[Scrape Targets]
        STORE[Time Series DB]
        ALERT[Alerting Rules]
    end
    
    subgraph Grafana
        DASH[Dashboards]
        VIS[Visualizations]
    end
    
    PG --> PSS
    PG --> PSA
    PSS --> COLLECT
    PSA --> COLLECT
    COLLECT --> SCRAPE
    SCRAPE --> STORE
    STORE --> DASH
    STORE --> ALERT
    DASH --> VIS
```

## Viewing these diagrams

These Mermaid diagrams render automatically on:
- GitHub (README, markdown files)
- GitLab
- Notion
- VS Code (with Mermaid extension)

Or paste into [mermaid.live](https://mermaid.live) to view/edit.
