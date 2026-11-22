-- Mamlakat Al Gamer: Supabase database and storage policies
-- Visitor uploads are inserted as pending; only an authenticated admin can publish or reject them.
-- Run this in Supabase Dashboard > SQL Editor.
-- IMPORTANT: after creating the administrator account in Supabase Auth,
-- insert that user's UUID into public.user_roles as role='admin'.

create extension if not exists pgcrypto;

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin'))
);

create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  category text not null default 'ألعاب',
  instructions text not null default '',
  html_file_path text not null,
  thumbnail_path text not null,
  submitter_name text not null default 'المدير',
  status text not null default 'pending' check (status in ('pending','published','rejected')),
  created_at timestamptz not null default now()
);

alter table public.games add column if not exists description text not null default '';
alter table public.games add column if not exists category text not null default 'ألعاب';
alter table public.games add column if not exists instructions text not null default '';
alter table public.games add column if not exists html_file_path text;
alter table public.games add column if not exists thumbnail_path text;
alter table public.games add column if not exists submitter_name text not null default 'المدير';
alter table public.games add column if not exists status text not null default 'pending';
alter table public.games add column if not exists created_at timestamptz not null default now();

create or replace function public.is_mkg_admin()
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role = 'admin'
  );
$$;

alter table public.user_roles enable row level security;
alter table public.games enable row level security;

-- Remove legacy policies from the previous schema. They call is_admin(),
-- while the current application consistently uses is_mkg_admin().
drop policy if exists "Admins manage games" on public.games;
drop policy if exists "Admins manage project storage" on storage.objects;
drop policy if exists "Visitors read published games" on public.games;
drop policy if exists "Visitors read game thumbnails 76h136_0" on storage.objects;

-- Explicit table privileges; RLS below still decides which rows each role can access.
grant select, insert on public.games to anon;
grant select, insert, update, delete on public.games to authenticated;
grant select on public.user_roles to authenticated;
grant execute on function public.is_mkg_admin() to anon, authenticated;

drop policy if exists "mkg roles read own" on public.user_roles;
create policy "mkg roles read own" on public.user_roles
for select to authenticated using (user_id = auth.uid());

drop policy if exists "mkg games public read published" on public.games;
create policy "mkg games public read published" on public.games
for select to anon, authenticated
using (status = 'published' or public.is_mkg_admin());

drop policy if exists "mkg visitors submit pending games" on public.games;
create policy "mkg visitors submit pending games" on public.games
for insert to anon, authenticated
with check (
  status = 'pending'
  and length(trim(title)) between 1 and 120
  and html_file_path is not null
  and thumbnail_path is not null
);

drop policy if exists "mkg games admin insert" on public.games;
create policy "mkg games admin insert" on public.games
for insert to authenticated with check (public.is_mkg_admin());

drop policy if exists "mkg games admin update" on public.games;
create policy "mkg games admin update" on public.games
for update to authenticated
using (public.is_mkg_admin()) with check (public.is_mkg_admin());

drop policy if exists "mkg games admin delete" on public.games;
create policy "mkg games admin delete" on public.games
for delete to authenticated using (public.is_mkg_admin());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('game-thumbnails', 'game-thumbnails', true, 5242880,
   array['image/png','image/jpeg','image/webp','image/gif']),
  ('game-files', 'game-files', false, 52428800,
   array['text/html','application/octet-stream'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "mkg public read thumbnails" on storage.objects;
create policy "mkg public read thumbnails" on storage.objects
for select to anon, authenticated
using (bucket_id = 'game-thumbnails');

drop policy if exists "mkg visitors upload game files" on storage.objects;
create policy "mkg visitors upload game files" on storage.objects
for insert to anon, authenticated
with check (
  bucket_id = 'game-files'
  and (storage.foldername(name))[1] is not null
);

drop policy if exists "mkg visitors upload thumbnails" on storage.objects;
create policy "mkg visitors upload thumbnails" on storage.objects
for insert to anon, authenticated
with check (
  bucket_id = 'game-thumbnails'
  and (storage.foldername(name))[1] is not null
);

drop policy if exists "mkg admin upload thumbnails" on storage.objects;
create policy "mkg admin upload thumbnails" on storage.objects
for insert to authenticated
with check (bucket_id = 'game-thumbnails' and public.is_mkg_admin());

drop policy if exists "mkg admin update thumbnails" on storage.objects;
create policy "mkg admin update thumbnails" on storage.objects
for update to authenticated
using (bucket_id = 'game-thumbnails' and public.is_mkg_admin())
with check (bucket_id = 'game-thumbnails' and public.is_mkg_admin());

drop policy if exists "mkg admin delete thumbnails" on storage.objects;
create policy "mkg admin delete thumbnails" on storage.objects
for delete to authenticated
using (bucket_id = 'game-thumbnails' and public.is_mkg_admin());

drop policy if exists "mkg published game files signed read" on storage.objects;
create policy "mkg published game files signed read" on storage.objects
for select to anon, authenticated
using (
  bucket_id = 'game-files'
  and (
    public.is_mkg_admin()
    or exists (
      select 1 from public.games g
      where g.status = 'published' and g.html_file_path = storage.objects.name
    )
  )
);

drop policy if exists "mkg admin upload game files" on storage.objects;
create policy "mkg admin upload game files" on storage.objects
for insert to authenticated
with check (bucket_id = 'game-files' and public.is_mkg_admin());

drop policy if exists "mkg admin update game files" on storage.objects;
create policy "mkg admin update game files" on storage.objects
for update to authenticated
using (bucket_id = 'game-files' and public.is_mkg_admin())
with check (bucket_id = 'game-files' and public.is_mkg_admin());

drop policy if exists "mkg admin delete game files" on storage.objects;
create policy "mkg admin delete game files" on storage.objects
for delete to authenticated
using (bucket_id = 'game-files' and public.is_mkg_admin());

-- Assign administrator access after you know the Auth user's UUID:
-- insert into public.user_roles (user_id, role)
-- values ('PASTE-AUTH-USER-UUID-HERE', 'admin')
-- on conflict (user_id) do update set role = excluded.role;
