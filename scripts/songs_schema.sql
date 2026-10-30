-- =====================================================================
-- Song Playlist (vinyl store) backend — run once in Supabase → SQL Editor. Safe to re-run.
-- Same project as movie-recommendations; every object is prefixed song_ so nothing clashes.
--   song_catalog        public read-only song features (seeded below)
--   song_user_titles    songs a signed-in user added to their own library (RLS own rows)
--   song_status         per-user Liked / Want to listen / Played (RLS own rows)
--   song_playlists      named playlists + song_playlist_items (RLS own rows)
--   song_prefs          optional taste profile (languages / genres / artists)
--   song_recommend()    'For you' recommender (security invoker, uses auth.uid())
--   song_similar()      'More like this' for one song
-- =====================================================================

-- ---------- catalog ----------
create table if not exists public.song_catalog (
  id          text primary key check (char_length(id) between 1 and 64),
  title       text not null,
  artist      text not null,
  language    text,
  genre       text,
  album       text,
  year        int,
  decade      int generated always as ((year / 10) * 10) stored,
  popularity  int not null default 0,              -- number of source posts that saved it
  updated_at  timestamptz not null default now()
);
create index if not exists song_catalog_artist_idx on public.song_catalog (lower(artist));
create index if not exists song_catalog_genre_idx  on public.song_catalog (genre);
create index if not exists song_catalog_lang_idx   on public.song_catalog (language);
alter table public.song_catalog enable row level security;
drop policy if exists "song catalog public read" on public.song_catalog;
create policy "song catalog public read" on public.song_catalog for select to anon, authenticated using (true);
revoke all on public.song_catalog from anon, authenticated;
grant select on public.song_catalog to anon, authenticated;

-- ---------- songs added by users (plain RLS insert from the browser, no Edge Function) ----------
create table if not exists public.song_user_titles (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title       text not null check (char_length(btrim(title)) between 1 and 200),
  artist      text not null check (char_length(btrim(artist)) between 1 and 200),
  language    text check (language is null or char_length(language) <= 40),
  genre       text check (genre is null or char_length(genre) <= 60),
  link        text check (link is null or (char_length(link) <= 500 and link ~* '^https://')),
  created_at  timestamptz not null default now()
);
create index if not exists song_user_titles_user_idx on public.song_user_titles (user_id, created_at desc);
alter table public.song_user_titles enable row level security;
drop policy if exists "song titles select own" on public.song_user_titles;
drop policy if exists "song titles insert own" on public.song_user_titles;
drop policy if exists "song titles update own" on public.song_user_titles;
drop policy if exists "song titles delete own" on public.song_user_titles;
create policy "song titles select own" on public.song_user_titles for select to authenticated using (user_id = auth.uid());
create policy "song titles insert own" on public.song_user_titles for insert to authenticated with check (user_id = auth.uid());
create policy "song titles update own" on public.song_user_titles for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "song titles delete own" on public.song_user_titles for delete to authenticated using (user_id = auth.uid());
revoke all on public.song_user_titles from anon, authenticated;
grant select, insert, update, delete on public.song_user_titles to authenticated;

-- ---------- per-user status ----------
create table if not exists public.song_status (
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  song_id     text not null check (char_length(song_id) between 1 and 64),   -- catalog id or 'u_<uuid>' for added songs
  liked       boolean not null default false,
  want        boolean not null default false,
  played      boolean not null default false,
  updated_at  timestamptz not null default now(),
  primary key (user_id, song_id)
);
alter table public.song_status enable row level security;
drop policy if exists "song status select own" on public.song_status;
drop policy if exists "song status insert own" on public.song_status;
drop policy if exists "song status update own" on public.song_status;
drop policy if exists "song status delete own" on public.song_status;
create policy "song status select own" on public.song_status for select to authenticated using (user_id = auth.uid());
create policy "song status insert own" on public.song_status for insert to authenticated with check (user_id = auth.uid());
create policy "song status update own" on public.song_status for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "song status delete own" on public.song_status for delete to authenticated using (user_id = auth.uid());
revoke all on public.song_status from anon, authenticated;
grant select, insert, update, delete on public.song_status to authenticated;

-- ---------- playlists ----------
create table if not exists public.song_playlists (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 60),
  created_at  timestamptz not null default now(),
  unique (user_id, name)
);
create table if not exists public.song_playlist_items (
  playlist_id uuid not null references public.song_playlists(id) on delete cascade,
  song_id     text not null check (char_length(song_id) between 1 and 64),
  added_at    timestamptz not null default now(),
  primary key (playlist_id, song_id)
);
alter table public.song_playlists enable row level security;
alter table public.song_playlist_items enable row level security;
drop policy if exists "song pl select own" on public.song_playlists;
drop policy if exists "song pl insert own" on public.song_playlists;
drop policy if exists "song pl update own" on public.song_playlists;
drop policy if exists "song pl delete own" on public.song_playlists;
create policy "song pl select own" on public.song_playlists for select to authenticated using (user_id = auth.uid());
create policy "song pl insert own" on public.song_playlists for insert to authenticated with check (user_id = auth.uid());
create policy "song pl update own" on public.song_playlists for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "song pl delete own" on public.song_playlists for delete to authenticated using (user_id = auth.uid());
drop policy if exists "song pli select own" on public.song_playlist_items;
drop policy if exists "song pli insert own" on public.song_playlist_items;
drop policy if exists "song pli delete own" on public.song_playlist_items;
create policy "song pli select own" on public.song_playlist_items for select to authenticated
  using (exists (select 1 from public.song_playlists p where p.id = playlist_id and p.user_id = auth.uid()));
create policy "song pli insert own" on public.song_playlist_items for insert to authenticated
  with check (exists (select 1 from public.song_playlists p where p.id = playlist_id and p.user_id = auth.uid()));
create policy "song pli delete own" on public.song_playlist_items for delete to authenticated
  using (exists (select 1 from public.song_playlists p where p.id = playlist_id and p.user_id = auth.uid()));
revoke all on public.song_playlists, public.song_playlist_items from anon, authenticated;
grant select, insert, update, delete on public.song_playlists to authenticated;
grant select, insert, delete on public.song_playlist_items to authenticated;

-- ---------- taste profile ----------
create table if not exists public.song_prefs (
  user_id     uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  languages   text[] not null default '{}' check (coalesce(array_length(languages,1),0) <= 20),
  genres      text[] not null default '{}' check (coalesce(array_length(genres,1),0) <= 40),
  artists     text[] not null default '{}' check (coalesce(array_length(artists,1),0) <= 40),
  updated_at  timestamptz not null default now()
);
alter table public.song_prefs enable row level security;
drop policy if exists "song prefs select own" on public.song_prefs;
drop policy if exists "song prefs insert own" on public.song_prefs;
drop policy if exists "song prefs update own" on public.song_prefs;
create policy "song prefs select own" on public.song_prefs for select to authenticated using (user_id = auth.uid());
create policy "song prefs insert own" on public.song_prefs for insert to authenticated with check (user_id = auth.uid());
create policy "song prefs update own" on public.song_prefs for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.song_prefs from anon, authenticated;
grant select, insert, update on public.song_prefs to authenticated;

-- ---------- recommender ----------
-- Signals: liked = +2, want to listen = +0.8, played = +0.5; taste profile picks = +1 each.
-- Features: artist (x2), genre (x1), language (x0.6), decade (x0.3), + small popularity prior.
-- New users with no signals get the most-saved songs (filtered by their taste profile if any).
-- Excludes songs the user already liked or played. Includes the user's own added songs.
drop function if exists public.song_recommend(int);
create or replace function public.song_recommend(p_limit int default 40)
returns table (id text, score numeric, because_id text, because_title text, reasons text[])
language sql stable security invoker set search_path = public as $$
with me as (select auth.uid() as uid),
songs as (
  select c.id, c.title, c.artist, c.language, c.genre, c.decade, c.popularity from public.song_catalog c
  union all
  select 'u_' || u.id::text, u.title, u.artist, nullif(u.language,''), nullif(u.genre,''), null::int, 0
  from public.song_user_titles u, me where u.user_id = me.uid
),
mine as (
  select s.song_id, s.liked, s.played,
         (case when s.liked then 2.0 else 0 end + case when s.want then 0.8 else 0 end
          + case when s.played then 0.5 else 0 end)::numeric as wgt
  from public.song_status s, me where s.user_id = me.uid
),
rated as (select x.*, m.wgt, m.liked from mine m join songs x on x.id = m.song_id where m.wgt > 0),
pr as (select p.* from public.song_prefs p, me where p.user_id = me.uid),
fa as (select lower(artist) k, sum(wgt) w from rated group by 1
       union all select lower(a), 1.0 from pr, unnest(pr.artists) a),
fg as (select genre k, sum(wgt)/sqrt(count(*)) w from rated where genre is not null and genre <> 'Unknown' group by 1
       union all select g, 1.0 from pr, unnest(pr.genres) g),
fl as (select language k, sum(wgt)/sqrt(count(*)) w from rated where language is not null group by 1
       union all select l, 1.0 from pr, unnest(pr.languages) l),
fd as (select decade k, sum(wgt)/sqrt(count(*)) w from rated where decade is not null group by 1),
a as (select k, sum(w) w from fa group by k), g as (select k, sum(w) w from fg group by k),
l as (select k, sum(w) w from fl group by k), d as (select k, sum(w) w from fd group by k),
has as (select (select count(*) from a) + (select count(*) from g) + (select count(*) from l) > 0 as any_sig),
scored as (
  select x.*,
    least(coalesce((select a.w from a where a.k = lower(x.artist)), 0), 6) * 2.0
    + coalesce((select g.w from g where g.k = x.genre), 0) * 1.0
    + coalesce((select l.w from l where l.k = x.language), 0) * 0.6
    + coalesce((select d.w from d where d.k = x.decade), 0) * 0.3
    + ln(1 + x.popularity) * 0.25 as s
  from songs x
  where not exists (select 1 from mine m where m.song_id = x.id and (m.liked or m.played))
),
diverse as (
  select s.*, s.s - 0.15 * (row_number() over (partition by lower(s.artist) order by s.s desc, s.id) - 1) as fs from scored s
),
top as (select * from diverse, has order by fs desc, popularity desc, id limit greatest(least(p_limit, 200), 1))
select t.id, round(t.fs::numeric, 3), b.id, b.title,
  case when not t.any_sig then array['Most saved']::text[] else array_remove(array[
    (select 'More ' || t.artist from a where a.k = lower(t.artist) and a.w > 0),
    (select 'Genre: ' || t.genre from g where g.k = t.genre and g.w > 0),
    (select 'Language: ' || t.language from l where l.k = t.language and l.w > 0 and t.language <> 'English'),
    (select t.decade || 's' from d where d.k = t.decade and d.w > 0.9)
  ], null) end
from top t
left join lateral (
  select r.id, r.title from rated r where r.liked
  order by (case when lower(r.artist) = lower(t.artist) then 3 else 0 end + case when r.genre = t.genre then 1 else 0 end
          + case when r.language = t.language then 1 else 0 end) desc, r.wgt desc limit 1
) b on true
order by t.fs desc, t.popularity desc, t.id;
$$;
revoke all on function public.song_recommend(int) from public, anon;
grant execute on function public.song_recommend(int) to authenticated;

-- 'More like this' for a catalog song (public, catalog only)
drop function if exists public.song_similar(text, int);
create or replace function public.song_similar(p_id text, p_limit int default 12)
returns table (id text, score numeric)
language sql stable security invoker set search_path = public as $$
  select c.id, round((case when lower(c.artist) = lower(s.artist) then 3 else 0 end
       + case when c.genre = s.genre and s.genre <> 'Unknown' then 2 else 0 end
       + case when c.language = s.language then 1 else 0 end
       + case when c.decade = s.decade then 0.5 else 0 end + ln(1 + c.popularity) * 0.2)::numeric, 3) sc
  from public.song_catalog c, public.song_catalog s
  where s.id = p_id and c.id <> s.id
  order by sc desc, c.popularity desc, c.id limit greatest(least(p_limit, 50), 1);
$$;
revoke all on function public.song_similar(text, int) from public;
grant execute on function public.song_similar(text, int) to anon, authenticated;
