#!/bin/bash

# Configuration
ADMIN_USER="admin"
DB_HOST="localhost"
DB_PORT="5432"
PASSWORD_LENGTH=16
STUDENTS_FILE="./credentials/students.txt"

# Load admin password from .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

if [ -z "$POSTGRES_ADMIN_PASSWORD" ]; then
    echo "Error: POSTGRES_ADMIN_PASSWORD not set. Create .env file first."
    exit 1
fi

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
echo "username,password,database" > "$CREDENTIALS_FILE"

echo "Creating $NUM_STUDENTS student databases and users..."
echo ""

while IFS= read -r USERNAME || [ -n "$USERNAME" ]; do
    # Skip empty lines and comments
    [[ -z "$USERNAME" || "$USERNAME" =~ ^# ]] && continue
    
    # Sanitize username: lowercase, remove spaces, keep only alphanumeric and underscore
    USERNAME=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_')
    
    PASSWORD=$(generate_password)
    DATABASE="${USERNAME}_db"
    
    echo "Creating user and database for $USERNAME..."
    
    # Create user and database
    PGPASSWORD=$POSTGRES_ADMIN_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $ADMIN_USER -d postgres <<EOF
-- Create user
CREATE USER $USERNAME WITH PASSWORD '$PASSWORD' 
    CONNECTION LIMIT 3
    NOSUPERUSER NOCREATEDB NOCREATEROLE;

-- Create database owned by the user
CREATE DATABASE $DATABASE OWNER $USERNAME;

-- Revoke public access
REVOKE ALL ON DATABASE $DATABASE FROM PUBLIC;

-- Grant connect to owner only
GRANT CONNECT ON DATABASE $DATABASE TO $USERNAME;

-- Add to students role for shared_project access
GRANT students TO $USERNAME;
EOF

    if [ $? -eq 0 ]; then
        # Add to credentials file
        echo "$USERNAME,$PASSWORD,$DATABASE" >> "$CREDENTIALS_FILE"
        echo "✓ Created $USERNAME with database $DATABASE"
    else
        echo "✗ Failed to create $USERNAME"
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
