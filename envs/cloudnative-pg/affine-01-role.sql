-- Run as a superuser against the shared cluster's `postgres` database.
-- To request a rotation, change the ExternalSecret and wait for it to become Ready:
--   kubectl -n affine annotate externalsecret affine-postgres force-sync="$(date +%s)" --overwrite
-- Read the generated password, then supply it to psql:
--   AFFINE_PASSWORD="$(kubectl -n affine get secret affine-postgres -o jsonpath='{.data.password}' | base64 --decode)"
--   psql --set=affine_password="$AFFINE_PASSWORD" --file=affine-01-role.sql
-- Rerun this file after deliberately rotating the ExternalSecret, then restart Affine.
\set ON_ERROR_STOP on

\if :{?affine_password}
\else
  \echo 'affine_password must be supplied with --set=affine_password=...'
  \quit
\endif

SELECT format('CREATE ROLE affine LOGIN PASSWORD %L', :'affine_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'affine')
\gexec

ALTER ROLE affine WITH
  LOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION
  PASSWORD :'affine_password';
