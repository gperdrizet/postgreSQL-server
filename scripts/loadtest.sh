#!/bin/bash
#
# PostgreSQL Load Testing Script using pgbench
# Usage: ./loadtest.sh [single|multi|stress|custom]
#

set -e

# Configuration
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-postgres}"
DB_USER="${DB_USER:-admin}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check if pgbench is available
check_pgbench() {
    if ! command -v pgbench &> /dev/null; then
        print_error "pgbench not found. Install postgresql-contrib or run tests inside the container."
        echo ""
        echo "To run inside the container:"
        echo "  docker exec -it student-postgres pgbench ..."
        echo ""
        echo "Or install locally:"
        echo "  sudo apt install postgresql-contrib"
        exit 1
    fi
}

# Initialize pgbench tables
init_pgbench() {
    local scale=${1:-10}
    print_header "Initializing pgbench (scale factor: $scale)"
    echo "This creates test tables: pgbench_accounts, pgbench_branches, pgbench_tellers, pgbench_history"
    echo ""
    
    PGPASSWORD="$PGPASSWORD" pgbench -i -s "$scale" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME"
    
    print_success "Initialization complete!"
    echo ""
}

# Single user hammering the server
test_single_user() {
    local duration=${1:-60}
    print_header "Single User Load Test (Duration: ${duration}s)"
    echo "Simulating one user performing continuous transactions..."
    echo ""
    
    PGPASSWORD="$PGPASSWORD" pgbench \
        -c 1 \
        -j 1 \
        -T "$duration" \
        -P 5 \
        --progress-timestamp \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        "$DB_NAME"
    
    echo ""
    print_success "Single user test complete!"
}

# Multiple concurrent users
test_multi_user() {
    local clients=${1:-20}
    local threads=${2:-4}
    local duration=${3:-60}
    
    print_header "Multi-User Load Test"
    echo "Clients: $clients | Threads: $threads | Duration: ${duration}s"
    echo ""
    
    PGPASSWORD="$PGPASSWORD" pgbench \
        -c "$clients" \
        -j "$threads" \
        -T "$duration" \
        -P 5 \
        --progress-timestamp \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        "$DB_NAME"
    
    echo ""
    print_success "Multi-user test complete!"
}

# Stress test - push the server to its limits
test_stress() {
    local clients=${1:-50}
    local threads=${2:-8}
    local duration=${3:-120}
    
    print_header "STRESS TEST"
    print_warning "This will push the server hard!"
    echo "Clients: $clients | Threads: $threads | Duration: ${duration}s"
    echo ""
    
    PGPASSWORD="$PGPASSWORD" pgbench \
        -c "$clients" \
        -j "$threads" \
        -T "$duration" \
        -P 5 \
        --progress-timestamp \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        "$DB_NAME"
    
    echo ""
    print_success "Stress test complete!"
}

# Read-only test (SELECT focused)
test_readonly() {
    local clients=${1:-30}
    local duration=${2:-60}
    
    print_header "Read-Only Load Test"
    echo "Clients: $clients | Duration: ${duration}s"
    echo ""
    
    PGPASSWORD="$PGPASSWORD" pgbench \
        -c "$clients" \
        -j 4 \
        -T "$duration" \
        -P 5 \
        -S \
        --progress-timestamp \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        "$DB_NAME"
    
    echo ""
    print_success "Read-only test complete!"
}

# Custom SQL script test
test_custom() {
    local script_file=${1:-"scripts/custom_loadtest.sql"}
    local clients=${2:-10}
    local duration=${3:-60}
    
    if [ ! -f "$script_file" ]; then
        print_error "Custom script not found: $script_file"
        echo ""
        echo "Create a custom SQL script with pgbench variables, e.g.:"
        echo ""
        echo "  -- scripts/custom_loadtest.sql"
        echo "  \\set aid random(1, 100000 * :scale)"
        echo "  SELECT abalance FROM pgbench_accounts WHERE aid = :aid;"
        echo ""
        exit 1
    fi
    
    print_header "Custom Script Load Test"
    echo "Script: $script_file | Clients: $clients | Duration: ${duration}s"
    echo ""
    
    PGPASSWORD="$PGPASSWORD" pgbench \
        -c "$clients" \
        -j 4 \
        -T "$duration" \
        -P 5 \
        -f "$script_file" \
        --progress-timestamp \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        "$DB_NAME"
    
    echo ""
    print_success "Custom test complete!"
}

# Cleanup pgbench tables
cleanup() {
    print_header "Cleaning up pgbench tables"
    
    PGPASSWORD="$PGPASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME" <<EOF
DROP TABLE IF EXISTS pgbench_accounts CASCADE;
DROP TABLE IF EXISTS pgbench_branches CASCADE;
DROP TABLE IF EXISTS pgbench_tellers CASCADE;
DROP TABLE IF EXISTS pgbench_history CASCADE;
EOF
    
    print_success "Cleanup complete!"
}

# Show usage
usage() {
    echo "PostgreSQL Load Testing Script"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  init [scale]              Initialize pgbench tables (default scale: 10)"
    echo "  single [duration]         Single user hammering server (default: 60s)"
    echo "  multi [clients] [threads] [duration]"
    echo "                            Multiple concurrent users (defaults: 20, 4, 60s)"
    echo "  stress [clients] [threads] [duration]"
    echo "                            Stress test (defaults: 50, 8, 120s)"
    echo "  readonly [clients] [duration]"
    echo "                            Read-only SELECT test (defaults: 30, 60s)"
    echo "  custom [script] [clients] [duration]"
    echo "                            Run custom SQL script"
    echo "  cleanup                   Remove pgbench tables"
    echo ""
    echo "Environment variables:"
    echo "  PGPASSWORD    Database password (required)"
    echo "  DB_HOST       Database host (default: localhost)"
    echo "  DB_PORT       Database port (default: 5432)"
    echo "  DB_NAME       Database name (default: postgres)"
    echo "  DB_USER       Database user (default: admin)"
    echo ""
    echo "Examples:"
    echo "  PGPASSWORD=secret $0 init"
    echo "  PGPASSWORD=secret $0 single 30"
    echo "  PGPASSWORD=secret $0 multi 50 8 120"
    echo "  PGPASSWORD=secret $0 stress"
    echo ""
}

# Main
check_pgbench

if [ -z "$PGPASSWORD" ]; then
    print_error "PGPASSWORD environment variable is required"
    echo ""
    usage
    exit 1
fi

case "${1:-}" in
    init)
        init_pgbench "${2:-10}"
        ;;
    single)
        test_single_user "${2:-60}"
        ;;
    multi)
        test_multi_user "${2:-20}" "${3:-4}" "${4:-60}"
        ;;
    stress)
        test_stress "${2:-50}" "${3:-8}" "${4:-120}"
        ;;
    readonly)
        test_readonly "${2:-30}" "${3:-60}"
        ;;
    custom)
        test_custom "${2:-scripts/custom_loadtest.sql}" "${3:-10}" "${4:-60}"
        ;;
    cleanup)
        cleanup
        ;;
    *)
        usage
        exit 1
        ;;
esac
