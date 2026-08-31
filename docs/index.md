# PostgreSQL Server

A self-hosted PostgreSQL setup for educators, indie developers, and small teams. Secure, monitored, and production-ready without enterprise costs.

## What this is

PostgreSQL 16 running in Docker on a local machine, exposed to the internet through a Tailscale tunnel and NGINX stream proxy on a lightweight VPS. Students connect with standard clients (`psql`, `psycopg2`, `pg`, etc.) to a public endpoint, the database runs on your hardware.

## Features

| Feature | Description |
| ------- | ----------- |
| **Secure by default** | Tailscale tunnel, SSL/TLS, per-user isolation |
| **Full monitoring** | Grafana dashboards, Prometheus metrics |
| **Multi-tenant** | Individual databases per student + optional shared DB |
| **Vector search** | pgvector for embeddings and similarity search |
| **Load tested** | Proven for 30+ concurrent users |
| **Admin tools** | Makefile commands, backup scripts |

## Performance

Tested on a modest home server:

| Metric | Single user | 20 concurrent users |
| ------ | ----------- | ------------------- |
| TPS | 258 | 1,661 |
| Latency | 3.9ms | 12ms |
| Failures | 0% | 0% |

## Documentation

- [Setup guide](setup.md): step-by-step instructions, student connection examples, monitoring, load testing, and troubleshooting
- [Architecture](architecture.md): detailed diagrams for the network topology, data flow, security layers, and monitoring stack
- [Blog](blog-post.md): write-up on why and how this was built
