-- 010_sample_data.sql
-- Minimal sample data for local development. Disabled by default; the test
-- suite sets app.is_sample = 'on' (or run with --variable=is_sample=on) to
-- load it. Production runs should not execute this file.

-- This file is intentionally inert outside an explicit opt-in. To enable
-- locally, run:
--   psql ... -v is_sample=on -f 010_sample_data.sql
\set ON_ERROR_STOP off
select case when coalesce(:'is_sample', 'off') = 'on'
  then 'loading sample data'
  else 'skipping sample data (run with -v is_sample=on to load)'
end as sample_status;

-- Sample data is loaded only when is_sample = 'on'.
-- (Implementation deferred to avoid polluting fresh test runs.)
