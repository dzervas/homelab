-- Run as a superuser against the shared cluster after affine-01-role.sql.
-- The shared PostgreSQL image must provide pgvector's `vector` extension.
\set ON_ERROR_STOP on

SELECT 'CREATE DATABASE affine OWNER affine'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'affine')
\gexec

ALTER DATABASE affine OWNER TO affine;
REVOKE ALL ON DATABASE affine FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE affine TO affine;

\connect affine

CREATE EXTENSION IF NOT EXISTS vector;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO affine;
