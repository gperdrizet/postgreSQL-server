#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/load-env.sh
. "$SCRIPT_DIR/lib/load-env.sh"

# Configuration
PASSWORD_LENGTH=16
STUDENTS_FILE="${1:-./credentials/students.txt}"
FAILED_STUDENTS=0
umask 077

# Check if students file exists
if [ ! -f "$STUDENTS_FILE" ]; then
    echo "Error: $STUDENTS_FILE not found."
    echo "Create a file with one student name per line."
    echo "Names should be lowercase, no spaces (e.g., jsmith, mgarcia)."
    exit 1
fi

# Output file for credentials
CREDENTIALS_DIR="./credentials"
CREDENTIALS_FILE="$CREDENTIALS_DIR/student_credentials.csv"
mkdir -p "$CREDENTIALS_DIR"

# Generate random password
generate_password() {
    openssl rand -base64 $PASSWORD_LENGTH | tr -dc 'a-zA-Z0-9' | head -c $PASSWORD_LENGTH
}

# Count students
NUM_STUDENTS=$(grep -c -v '^$' "$STUDENTS_FILE")

# Create CSV header
if [[ ! -s "$CREDENTIALS_FILE" ]]; then
    echo "username,password,database" > "$CREDENTIALS_FILE"
fi
chmod 600 "$CREDENTIALS_FILE"

echo "Creating $NUM_STUDENTS student databases and users..."
echo ""

while IFS= read -r USERNAME || [ -n "$USERNAME" ]; do
    # Skip empty lines and comments
    [[ -z "$USERNAME" || "$USERNAME" =~ ^# ]] && continue
    
    # Sanitize username: lowercase, remove spaces, keep only alphanumeric and underscore
    USERNAME=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -cd 'a-z0-9_')
    if [[ -z "$USERNAME" || ${#USERNAME} -gt 60 ]]; then
        echo "Error: student name must normalize to 1-60 characters."
        FAILED_STUDENTS=$((FAILED_STUDENTS + 1))
        continue
    fi
    
    PASSWORD=$(generate_password)
    DATABASE="${USERNAME}_db"
    
    echo "Creating user and database for $USERNAME..."
    
    # Create user and database
    PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" psql -X -w -v ON_ERROR_STOP=1 -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres <<EOF
-- Create user
CREATE USER "$USERNAME" WITH PASSWORD '$PASSWORD' 
    CONNECTION LIMIT 3
    NOSUPERUSER NOCREATEDB NOCREATEROLE;

-- Create database owned by the user
CREATE DATABASE "$DATABASE" OWNER "$USERNAME";

-- Revoke public access
REVOKE ALL ON DATABASE "$DATABASE" FROM PUBLIC;

-- Grant connect to owner only
GRANT CONNECT ON DATABASE "$DATABASE" TO "$USERNAME";

-- Add to students role for shared_project access
GRANT students TO "$USERNAME";

\connect "$DATABASE"
CREATE EXTENSION IF NOT EXISTS vector;
EOF

    if [ $? -eq 0 ]; then
        # Add to credentials file
        echo "$USERNAME,$PASSWORD,$DATABASE" >> "$CREDENTIALS_FILE"
        echo "✓ Created $USERNAME with database $DATABASE"
    else
        echo "✗ Failed to create $USERNAME"
        FAILED_STUDENTS=$((FAILED_STUDENTS + 1))
    fi
done < "$STUDENTS_FILE"

echo ""
echo "=========================================="
echo "Done! Credentials saved to: $CREDENTIALS_FILE"
echo "=========================================="
echo ""
echo "IMPORTANT: Distribute credentials securely!"
echo "Consider deleting this file after distribution."
chmod 600 "$CREDENTIALS_FILE"
if [[ "$FAILED_STUDENTS" -gt 0 ]]; then
    echo "Error: $FAILED_STUDENTS student account(s) failed."
    exit 1
fi
