-- مملكة الجيمر: جلسات الزوار وإعلانات المنصة
-- نفّذ مرة واحدة في Supabase SQL Editor بعد مراجعة النسخة الاحتياطية.
begin;

create table if not exists public.platform_ads (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 1 and 120),
  description text not null default '' check (char_length(description) <= 500),
  image_path text,
  target_url text,
  is_active boolean not null default true,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_ads_dates_check check (ends_at is null or starts_at is null or ends_at > starts_at)
);
create index if not exists platform_ads_active_dates_idx
  on public.platform_ads(is_active, starts_at, ends_at);

alter table public.platform_ads enable row level security;
drop policy if exists "Public reads active platform ads" on public.platform_ads;
create policy "Public reads active platform ads" on public.platform_ads
 for select to anon, authenticated
 using (is_active = true and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()));
drop policy if exists "Admins manage platform ads" on public.platform_ads;
create policy "Admins manage platform ads" on public.platform_ads
 for all to authenticated
 using (public.is_mkg_admin())
 with check (public.is_mkg_admin());
grant select on public.platform_ads to anon, authenticated;
grant insert, update, delete on public.platform_ads to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('platform-ads','platform-ads',true,5242880,array['image/png','image/jpeg','image/webp','image/gif'])
on conflict (id) do update set public=true, file_size_limit=5242880,
 allowed_mime_types=array['image/png','image/jpeg','image/webp','image/gif'];

drop policy if exists "Public reads platform ad images" on storage.objects;
create policy "Public reads platform ad images" on storage.objects
 for select to anon, authenticated using (bucket_id='platform-ads');
drop policy if exists "Admins upload platform ad images" on storage.objects;
create policy "Admins upload platform ad images" on storage.objects
 for insert to authenticated with check (bucket_id='platform-ads' and public.is_mkg_admin());
drop policy if exists "Admins update platform ad images" on storage.objects;
create policy "Admins update platform ad images" on storage.objects
 for update to authenticated using (bucket_id='platform-ads' and public.is_mkg_admin())
 with check (bucket_id='platform-ads' and public.is_mkg_admin());
drop policy if exists "Admins delete platform ad images" on storage.objects;
create policy "Admins delete platform ad images" on storage.objects
 for delete to authenticated using (bucket_id='platform-ads' and public.is_mkg_admin());

create or replace function public.start_visitor_session(p_visitor_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare new_id uuid;
begin
  insert into public.visitor_sessions(visitor_id,started_at,last_active_at,total_seconds,play_seconds)
  values (p_visitor_id,now(),now(),0,0)
  returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.heartbeat_visitor_session(p_session_id uuid,p_visitor_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
 update public.visitor_sessions
 set last_active_at=now(),
     total_seconds=greatest(total_seconds, floor(extract(epoch from (now()-started_at)))::integer)
 where id=p_session_id and visitor_id=p_visitor_id and ended_at is null;
$$;

create or replace function public.finish_visitor_session(p_session_id uuid,p_visitor_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
 update public.visitor_sessions
 set last_active_at=now(),
     ended_at=coalesce(ended_at,now()),
     total_seconds=greatest(total_seconds, floor(extract(epoch from (now()-started_at)))::integer)
 where id=p_session_id and visitor_id=p_visitor_id;
$$;

revoke all on function public.start_visitor_session(uuid) from public;
revoke all on function public.heartbeat_visitor_session(uuid,uuid) from public;
revoke all on function public.finish_visitor_session(uuid,uuid) from public;
grant execute on function public.start_visitor_session(uuid) to anon,authenticated;
grant execute on function public.heartbeat_visitor_session(uuid,uuid) to anon,authenticated;
grant execute on function public.finish_visitor_session(uuid,uuid) to anon,authenticated;

commit;
