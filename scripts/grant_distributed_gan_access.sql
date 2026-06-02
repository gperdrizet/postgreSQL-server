-- Grant students access to distributed_gan database

-- Grant connect privilege
GRANT CONNECT ON DATABASE distributed_gan TO students;

-- Grant schema permissions
GRANT ALL ON SCHEMA public TO students;

-- Grant permissions on all existing tables
GRANT ALL ON ALL TABLES IN SCHEMA public TO students;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO students;

-- Set default privileges for future objects created by admin
ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA public
    GRANT ALL ON TABLES TO students;
ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA public
    GRANT ALL ON SEQUENCES TO students;
ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA public
    GRANT ALL ON FUNCTIONS TO students;
