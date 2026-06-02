# PostgreSQL Administration Makefile
# Usage: make <command>
#
# Load environment variables from .env
include .env
export

# Configuration
DB_HOST ?= localhost
DB_PORT ?= 5432
DB_USER ?= admin
PSQL = PGPASSWORD="$(POSTGRES_ADMIN_PASSWORD)" psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) --pset=pager=off

.PHONY: help list-databases list-tables list-users list-connections \
	drop-database drop-table create-backup restore-backup \
	db-size table-sizes vacuum check-health shell grant-students-access \
	setup-backup-cron enable-startup-on-boot disable-startup-on-boot

# Default target
help:
	@echo "PostgreSQL Administration Commands"
	@echo "=================================="
	@echo ""
	@echo "Database Info:"
	@echo "  make list-databases        List all databases"
	@echo "  make list-tables DB=name   List tables in a database"
	@echo "  make list-users            List all users/roles"
	@echo "  make list-connections      Show active connections"
	@echo "  make db-size               Show database sizes"
	@echo "  make table-sizes DB=name   Show table sizes in a database"
	@echo ""
	@echo "Database Management:"
	@echo "  make drop-database DB=name Drop a database (DANGEROUS!)"
	@echo "  make drop-table DB=name TABLE=name  Drop a table (DANGEROUS!)"
	@echo "  make create-database DB=name        Create empty database"
	@echo "  make grant-students-access DB=name  Grant all students access to a database"
	@echo ""
	@echo "Maintenance:"
	@echo "  make vacuum                Run VACUUM ANALYZE on all databases"
	@echo "  make vacuum-full DB=name   Run VACUUM FULL on a database (locks tables)"
	@echo "  make check-health          Check PostgreSQL health"
	@echo "  make show-config           Show key PostgreSQL settings"
	@echo ""
	@echo "Backup/Restore:"
	@echo "  make create-backup DB=name Create backup of a database"
	@echo "  make backup-all            Backup all databases"
	@echo "  make restore-backup DB=name FILE=path  Restore from backup"
	@echo ""
	@echo "Interactive:"
	@echo "  make shell                 Open psql shell"
	@echo "  make shell DB=name         Open psql shell to specific database"
	@echo ""
	@echo "Load Testing:"
	@echo "  make loadtest-init         Initialize pgbench tables"
	@echo "  make loadtest-single       Run single user load test"
	@echo "  make loadtest-multi        Run multi-user load test"
	@echo ""
	@echo "Automation:"
	@echo "  make setup-backup-cron     Install daily backup cron job"
	@echo "  make enable-startup-on-boot  Start DB/monitoring stack automatically on boot"
	@echo "  make disable-startup-on-boot Remove automatic startup on boot"

# ============================================
# Database Info
# ============================================

list-databases:
	@echo "=== Databases ==="
	@$(PSQL) -d postgres -c "\l"

list-tables:
ifndef DB
	@echo "Error: DB required. Usage: make list-tables DB=database_name"
	@exit 1
endif
	@echo "=== Tables in $(DB) ==="
	@$(PSQL) -d $(DB) -c "\dt+"

list-users:
	@echo "=== Users and Roles ==="
	@$(PSQL) -d postgres -c "\du+"

list-connections:
	@echo "=== Active Connections ==="
	@$(PSQL) -d postgres -c "SELECT pid, usename, datname, client_addr, state, query_start, LEFT(query, 50) as query FROM pg_stat_activity WHERE state != 'idle' ORDER BY query_start;"

db-size:
	@echo "=== Database Sizes ==="
	@$(PSQL) -d postgres -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) as size FROM pg_database ORDER BY pg_database_size(datname) DESC;"

table-sizes:
ifndef DB
	@echo "Error: DB required. Usage: make table-sizes DB=database_name"
	@exit 1
endif
	@echo "=== Table Sizes in $(DB) ==="
	@$(PSQL) -d $(DB) -c "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) as size FROM pg_tables WHERE schemaname = 'public' ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC;"

# ============================================
# Database Management
# ============================================

create-database:
ifndef DB
	@echo "Error: DB required. Usage: make create-database DB=database_name"
	@exit 1
endif
	@$(PSQL) -d postgres -c "CREATE DATABASE $(DB);"
	@echo "✓ Database $(DB) created"

grant-students-access:
ifndef DB
	@echo "Error: DB required. Usage: make grant-students-access DB=database_name"
	@exit 1
endif
	@echo "=== Granting students access to $(DB) ==="
	@$(PSQL) -d postgres -c "GRANT CONNECT ON DATABASE $(DB) TO students;"
	@$(PSQL) -d $(DB) -c "GRANT ALL ON SCHEMA public TO students;"
	@$(PSQL) -d $(DB) -c "GRANT ALL ON ALL TABLES IN SCHEMA public TO students;"
	@$(PSQL) -d $(DB) -c "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO students;"
	@$(PSQL) -d $(DB) -c "ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA public GRANT ALL ON TABLES TO students;"
	@$(PSQL) -d $(DB) -c "ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA public GRANT ALL ON SEQUENCES TO students;"
	@$(PSQL) -d $(DB) -c "ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO students;"
	@echo "✓ Students role granted access to $(DB)"
	@echo "Creating database $(DB)..."
	@$(PSQL) -d postgres -c "CREATE DATABASE $(DB);"
	@echo "✓ Database $(DB) created"

drop-database:
ifndef DB
	@echo "Error: DB required. Usage: make drop-database DB=database_name"
	@exit 1
endif
	@echo "WARNING: This will permanently delete database '$(DB)' and all its data!"
	@read -p "Type the database name to confirm: " confirm && \
	if [ "$$confirm" = "$(DB)" ]; then \
		$(PSQL) -d postgres -c "DROP DATABASE IF EXISTS $(DB);"; \
		echo "✓ Database $(DB) dropped"; \
	else \
		echo "Aborted. Name did not match."; \
	fi

drop-table:
ifndef DB
	@echo "Error: DB required. Usage: make drop-table DB=database_name TABLE=table_name"
	@exit 1
endif
ifndef TABLE
	@echo "Error: TABLE required. Usage: make drop-table DB=database_name TABLE=table_name"
	@exit 1
endif
	@echo "WARNING: This will permanently delete table '$(TABLE)' from database '$(DB)'!"
	@read -p "Type 'yes' to confirm: " confirm && \
	if [ "$$confirm" = "yes" ]; then \
		$(PSQL) -d $(DB) -c "DROP TABLE IF EXISTS $(TABLE) CASCADE;"; \
		echo "✓ Table $(TABLE) dropped from $(DB)"; \
	else \
		echo "Aborted."; \
	fi

# ============================================
# Maintenance
# ============================================

vacuum:
	@echo "=== Running VACUUM ANALYZE on all databases ==="
	@$(PSQL) -d postgres -c "SELECT datname FROM pg_database WHERE datistemplate = false;" -t | \
	while read db; do \
		if [ -n "$$db" ]; then \
			echo "Vacuuming $$db..."; \
			$(PSQL) -d "$$db" -c "VACUUM ANALYZE;" 2>/dev/null || true; \
		fi \
	done
	@echo "✓ Vacuum complete"

vacuum-full:
ifndef DB
	@echo "Error: DB required. Usage: make vacuum-full DB=database_name"
	@exit 1
endif
	@echo "WARNING: VACUUM FULL locks tables and may take a long time!"
	@read -p "Continue? (yes/no): " confirm && \
	if [ "$$confirm" = "yes" ]; then \
		$(PSQL) -d $(DB) -c "VACUUM FULL ANALYZE;"; \
		echo "✓ VACUUM FULL complete on $(DB)"; \
	else \
		echo "Aborted."; \
	fi

check-health:
	@echo "=== PostgreSQL Health Check ==="
	@echo ""
	@echo "--- Server Status ---"
	@$(PSQL) -d postgres -c "SELECT version();" -t
	@echo ""
	@echo "--- Uptime ---"
	@$(PSQL) -d postgres -c "SELECT now() - pg_postmaster_start_time() as uptime;" -t
	@echo ""
	@echo "--- Connection Stats ---"
	@$(PSQL) -d postgres -c "SELECT count(*) as total, count(*) FILTER (WHERE state = 'active') as active, count(*) FILTER (WHERE state = 'idle') as idle FROM pg_stat_activity;"
	@echo ""
	@echo "--- Database Stats ---"
	@$(PSQL) -d postgres -c "SELECT datname, numbackends as connections, xact_commit as commits, xact_rollback as rollbacks, blks_hit, blks_read, ROUND(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) as cache_hit_ratio FROM pg_stat_database WHERE datname NOT LIKE 'template%' ORDER BY datname;"

show-config:
	@echo "=== Key PostgreSQL Settings ==="
	@$(PSQL) -d postgres -c "SELECT name, setting, unit, short_desc FROM pg_settings WHERE name IN ('max_connections', 'shared_buffers', 'work_mem', 'effective_cache_size', 'maintenance_work_mem', 'synchronous_commit', 'max_parallel_workers', 'statement_timeout');"

# ============================================
# Backup/Restore
# ============================================

create-backup:
ifndef DB
	@echo "Error: DB required. Usage: make create-backup DB=database_name"
	@exit 1
endif
	@mkdir -p backups
	@BACKUP_FILE="backups/$(DB)_$$(date +%Y%m%d_%H%M%S).sql.gz"; \
	echo "Creating backup: $$BACKUP_FILE"; \
	PGPASSWORD="$(POSTGRES_ADMIN_PASSWORD)" pg_dump -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) $(DB) | gzip > "$$BACKUP_FILE"; \
	echo "✓ Backup created: $$BACKUP_FILE"

backup-all:
	@mkdir -p backups
	@echo "=== Backing up all databases ==="
	@BACKUP_FILE="backups/all_databases_$$(date +%Y%m%d_%H%M%S).sql.gz"; \
	PGPASSWORD="$(POSTGRES_ADMIN_PASSWORD)" pg_dumpall -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) | gzip > "$$BACKUP_FILE"; \
	echo "✓ Full backup created: $$BACKUP_FILE"

restore-backup:
ifndef DB
	@echo "Error: DB required. Usage: make restore-backup DB=database_name FILE=backup_file"
	@exit 1
endif
ifndef FILE
	@echo "Error: FILE required. Usage: make restore-backup DB=database_name FILE=backup_file"
	@exit 1
endif
	@echo "WARNING: This will overwrite database '$(DB)' with the backup!"
	@read -p "Type 'yes' to confirm: " confirm && \
	if [ "$$confirm" = "yes" ]; then \
		echo "Restoring $(FILE) to $(DB)..."; \
		gunzip -c "$(FILE)" | $(PSQL) -d $(DB); \
		echo "✓ Restore complete"; \
	else \
		echo "Aborted."; \
	fi

# ============================================
# Interactive
# ============================================

shell:
ifdef DB
	@$(PSQL) -d $(DB)
else
	@$(PSQL) -d postgres
endif

# ============================================
# Load Testing
# ============================================

loadtest-init:
	@./scripts/loadtest.sh init 10

loadtest-single:
	@./scripts/loadtest.sh single 30

loadtest-multi:
	@./scripts/loadtest.sh multi 20 4 30

# ============================================
# Automation
# ============================================

setup-backup-cron:
	@./scripts/setup-backup-cron.sh

enable-startup-on-boot:
	@./scripts/setup-startup-service.sh

disable-startup-on-boot:
	@./scripts/setup-startup-service.sh --uninstall
