-- مملكة الجيمر: عدادات اللعب ومساهمات الزوار
-- نفّذ هذا الملف مرة واحدة في Supabase SQL Editor.
begin;

create table if not exists public.game_plays (
 id uuid primary key default gen_random_uuid(),
 game_id uuid not null references public.games(id) on delete cascade,
 visitor_id uuid,
 played_at timestamptz not null default now()
);
create index if not exists game_plays_game_played_idx on public.game_plays(game_id, played_at desc);

alter table public.game_plays enable row level security;
drop policy if exists "Anyone can record game plays" on public.game_plays;
create policy "Anyone can record game plays" on public.game_plays
 for insert to anon, authenticated with check (
  exists(select 1 from public.games g where g.id=game_id and g.status='published')
 );
-- Keep raw play events private. Visitors receive aggregate counts only through the RPC below.
drop policy if exists "Anyone can read aggregate play events" on public.game_plays;
drop policy if exists "Admins read game plays" on public.game_plays;
create policy "Admins read game plays" on public.game_plays
 for select to authenticated using (public.is_mkg_admin());

revoke select on public.game_plays from anon, authenticated;
grant insert on public.game_plays to anon, authenticated;

-- Safe aggregate endpoint: exposes counts per published game, never visitor IDs or event rows.
create or replace function public.get_game_play_stats()
returns table (
 game_id uuid,
 total_plays bigint,
 plays_last_7_days bigint
)
language sql
stable
security definer
set search_path = public
as $
 select
  p.game_id,
  count(*)::bigint as total_plays,
  count(*) filter (where p.played_at >= now() - interval '7 days')::bigint as plays_last_7_days
 from public.game_plays p
 inner join public.games g on g.id = p.game_id
 where g.status = 'published'
 group by p.game_id;
$;

revoke all on function public.get_game_play_stats() from public;
grant execute on function public.get_game_play_stats() to anon, authenticated;

create table if not exists public.visitor_contributions (
 id uuid primary key default gen_random_uuid(),
 type text not null default 'suggestion' check(type in ('suggestion')),
 title text not null check(char_length(title) between 1 and 120),
 details text not null check(char_length(details) between 1 and 2000),
 submitter_name text not null default 'زائر' check(char_length(submitter_name)<=60),
 status text not null default 'pending' check(status in ('pending','reviewed','accepted','rejected')),
 created_at timestamptz not null default now()
);
create index if not exists visitor_contributions_created_idx on public.visitor_contributions(created_at desc);
alter table public.visitor_contributions enable row level security;

drop policy if exists "Visitors submit suggestions" on public.visitor_contributions;
create policy "Visitors submit suggestions" on public.visitor_contributions
 for insert to anon, authenticated with check (status='pending' and type='suggestion');
drop policy if exists "Admins read suggestions" on public.visitor_contributions;
create policy "Admins read suggestions" on public.visitor_contributions
 for select to authenticated using (public.is_mkg_admin());
drop policy if exists "Admins update suggestions" on public.visitor_contributions;
create policy "Admins update suggestions" on public.visitor_contributions
 for update to authenticated using (public.is_mkg_admin()) with check (public.is_mkg_admin());

grant select, insert on public.game_plays to anon, authenticated;
grant select, insert, update on public.visitor_contributions to anon, authenticated;
grant usage on schema public to anon, authenticated;

commit;
