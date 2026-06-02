-- This runs automatically when the container first starts

-- Create extension for UUID support (useful for students)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create extension for better password hashing
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create extension for query statistics (monitoring)
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Create extension for vector similarity search (pgvector)
CREATE EXTENSION IF NOT EXISTS "vector";

-- Create students role for shared database access
-- This role will be granted to all student users
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'students') THEN
        CREATE ROLE students;
        RAISE NOTICE 'Created students role for shared database access';
    END IF;
END $$;

-- Log that initialization completed
DO $$
BEGIN
    RAISE NOTICE 'Database initialized successfully at %', NOW();
END $$;
