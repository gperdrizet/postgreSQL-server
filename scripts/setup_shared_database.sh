#!/bin/bash

# Configuration
ADMIN_USER="admin"
DB_HOST="localhost"
DB_PORT="5432"
SHARED_DB_NAME="${1:-shared_project}"

# Load admin password from .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

if [ -z "$POSTGRES_ADMIN_PASSWORD" ]; then
    echo "Error: POSTGRES_ADMIN_PASSWORD not set. Create .env file first."
    exit 1
fi

echo "=========================================="
echo "Setting up shared database: $SHARED_DB_NAME"
echo "=========================================="
echo ""

# Create the shared database and configure permissions
PGPASSWORD=$POSTGRES_ADMIN_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $ADMIN_USER -d postgres <<EOF
-- Create the shared database if it doesn't exist
SELECT 'CREATE DATABASE $SHARED_DB_NAME'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$SHARED_DB_NAME')\gexec

-- Create students role if it doesn't exist
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'students') THEN
        CREATE ROLE students;
        RAISE NOTICE 'Created students role';
    ELSE
        RAISE NOTICE 'Students role already exists';
    END IF;
END
\$\$;

-- Grant connect privilege
GRANT CONNECT ON DATABASE $SHARED_DB_NAME TO students;

EOF

if [ $? -ne 0 ]; then
    echo "✗ Failed to create database or role"
    exit 1
fi

echo "✓ Database and role created"

# Configure permissions on the shared database
PGPASSWORD=$POSTGRES_ADMIN_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $ADMIN_USER -d $SHARED_DB_NAME <<EOF

-- Grant schema permissions
GRANT ALL ON SCHEMA public TO students;

-- Default privileges: students can use each other's tables
ALTER DEFAULT PRIVILEGES FOR ROLE students IN SCHEMA public
    GRANT ALL ON TABLES TO students;
ALTER DEFAULT PRIVILEGES FOR ROLE students IN SCHEMA public
    GRANT ALL ON SEQUENCES TO students;
ALTER DEFAULT PRIVILEGES FOR ROLE students IN SCHEMA public
    GRANT ALL ON FUNCTIONS TO students;

-- Grant usage and create on schema
GRANT USAGE, CREATE ON SCHEMA public TO students;

EOF

if [ $? -ne 0 ]; then
    echo "✗ Failed to configure permissions"
    exit 1
fi

echo "✓ Permissions configured"

# Get all student users (users whose databases end with _db)
echo ""
echo "Adding existing student users to the students role..."

STUDENT_USERS=$(PGPASSWORD=$POSTGRES_ADMIN_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $ADMIN_USER -d postgres -t -c "
    SELECT r.rolname 
    FROM pg_roles r
    WHERE EXISTS (
        SELECT 1 FROM pg_database d 
        WHERE d.datname = r.rolname || '_db' 
        AND d.datdba = r.oid
    )
    AND r.rolname != 'admin'
    ORDER BY r.rolname;
" | sed 's/^[ \t]*//;s/[ \t]*$//' | grep -v '^$')

if [ -z "$STUDENT_USERS" ]; then
    echo "No student users found yet. Run create_students.sh to create student accounts."
else
    # Count students
    NUM_STUDENTS=$(echo "$STUDENT_USERS" | wc -l)
    echo "Found $NUM_STUDENTS student user(s):"
    
    for USERNAME in $STUDENT_USERS; do
        PGPASSWORD=$POSTGRES_ADMIN_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $ADMIN_USER -d postgres -c "GRANT students TO $USERNAME;" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "  ✓ $USERNAME"
        else
            echo "  ✗ $USERNAME (may already be a member)"
        fi
    done
fi

echo ""
echo "=========================================="
echo "✓ Shared database setup complete!"
echo "=========================================="
echo ""
echo "Database name: $SHARED_DB_NAME"
echo "All current and future students can access this database."
echo ""
echo "Students can connect using:"
echo "  psql \"host=your-domain.com port=54321 dbname=$SHARED_DB_NAME user=USERNAME sslmode=require\""
echo ""
