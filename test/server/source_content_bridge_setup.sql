-- Disposable database fixture only; production already has the real tables.
create table if not exists public.reading_history (
  user_key text not null,
  source_id text not null,
  show_id text not null,
  title text not null default '',
  cover text,
  chapter_id text,
  chapter_number double precision,
  chapter_url text,
  pos integer not null default 0,
  total integer not null default 0,
  updated_ms bigint not null default 0,
  type text,
  primary key (user_key, source_id, show_id));
create table if not exists public.profile_reading_history (
  user_key text not null,
  profile_id text not null,
  source_id text not null,
  show_id text not null,
  title text not null default '',
  cover text,
  chapter_id text,
  chapter_number double precision,
  chapter_url text,
  pos integer not null default 0,
  total integer not null default 0,
  updated_ms bigint not null default 0,
  type text,
  primary key (user_key, profile_id, source_id, show_id));
create table if not exists public.viewer_profiles (
  user_key text not null,
  profile_id text not null,
  name text not null,
  avatar integer not null default 0,
  is_kids boolean not null default false,
  created_at timestamptz not null default now(),
  photo_url text,
  primary key (user_key, profile_id));
create table if not exists public.backups (
  user_key text primary key,
  payload text not null,
  updated_at timestamptz not null default now());
