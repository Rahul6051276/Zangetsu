-- Disposable database fixture only; production already has the real tables.
create table if not exists public.mylist (
  user_key text, source_id text, item_id text, title text,
  primary key (user_key, source_id, item_id));
create table if not exists public.profile_mylist (
  user_key text, profile_id text, source_id text, item_id text,
  primary key (user_key, profile_id, source_id, item_id));
create table if not exists public.list_categories (
  user_key text, id uuid, name text, primary key (id));
create table if not exists public.profile_list_categories (
  user_key text, profile_id text, id uuid, name text,
  primary key (user_key, profile_id, id));
create table if not exists public.mylist_categories (
  user_key text, source_id text, item_id text, category_id uuid,
  primary key (user_key, source_id, item_id, category_id));
create table if not exists public.profile_mylist_categories (
  user_key text, profile_id text, source_id text, item_id text,
  category_id uuid,
  primary key (user_key, profile_id, source_id, item_id, category_id));
