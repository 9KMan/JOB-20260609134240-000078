-- 001_extensions_and_enums.sql
-- Foundation: required PostgreSQL extensions and enumerated types.

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- Enumerated types used across the schema.
-- These are kept conservative and additive; new values are appended with `alter type ... add value`.

do $$ begin
  create type user_role as enum (
    'owner',         -- organisation owner, full control including billing
    'admin',         -- organisation admin, manage members and configuration
    'manager',       -- production / operations manager
    'operator',      -- shop floor operator
    'qa',            -- quality assurance
    'auditor',       -- read-only auditor
    'viewer'         -- read-only viewer
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type lot_status as enum (
    'received',
    'quarantined',
    'released',
    'rejected',
    'depleted'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type batch_status as enum (
    'planned',
    'in_progress',
    'completed',
    'cancelled',
    'on_hold'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type recall_status as enum (
    'initiated',
    'investigating',
    'confirmed',
    'resolved',
    'closed'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type recall_severity as enum (
    'low',
    'medium',
    'high',
    'critical'
  );
exception when duplicate_object then null; end $$;
