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

-- ---------- seed: the 363 catalog songs (re-runnable) ----------
insert into public.song_catalog (id,title,artist,language,genre,album,year,popularity) values
('3MjUtNVVq3C8Fn0MP3zhXa','...Baby One More Time','Britney Spears','English','Pop','...Baby One More Time (Deluxe Version)',1998,2),
('6b8Be6ljOzmkOmFslEb23P','24K Magic','Bruno Mars','English','Pop','24K Magic',2016,1),
('0BxE4FqsDD1Ot4YuBXwAPp','505','Arctic Monkeys','English','Alternative / Indie','Favourite Worst Nightmare',2007,1),
('5kqIPrATaCc2LqxVWzQGbk','7 Years','Lukas Graham','English','Pop','Lukas Graham',2015,1),
('23phSRwoMy48rwFpmuAP8q','A Cruel Angel''s Thesis','Yoko Takahashi','English','Soundtrack','Neon Genesis Evangelion (Original Series Soundtrack)',1995,1),
('59wlTaYOL5tDUgXnbBQ3my','A Moment Apart','ODESZA','English','Electronic / Dance','A Moment Apart',2017,1),
('78TzliRJJhCgsZ0ARUm8vI','A Sad Song About a Girl I No Longer Know','Bedside Kites','English','Alternative / Indie','Bedside Kites - Single',2018,1),
('0FDzzruyVECATHXKHFs9eJ','A Sky Full of Stars','Coldplay','English','Alternative / Indie','Ghost Stories',2014,1),
('2CAFTRtPz6S6dRG0RrXZ6L','Aashiyana','Shreya Ghoshal','Hindi','Unknown','',null,1),
('x88d843a94dd1','Aayi','Kaifi Khalil','Urdu','Unknown','',null,1),
('2374M0fQpWi3dLnB54qaLX','Africa','Toto','English','Rock','Toto IV',1982,1),
('2p8IUWQDrpjuFltbdgLOag','After Hours','The Weeknd','English','R&B / Soul','After Hours',2020,1),
('5c1QJAiC3773EwiZLwHf5x','Again','Lenny Kravitz','English','Rock','Greatest Hits',2000,1),
('0C5vCd4id8DxoDM9HSUpBh','Aise Na Pagal Karo','Kalra Saab & Bharath','Hindi/Urdu','Unknown','',null,1),
('6kEpjptnAwt11Atr4cEMe1','All Good Things','Nelly Furtado','English','Pop','Live Session (iTunes Exclusive) - EP',2006,1),
('3U4isOIWM3VvDubwSI3y7a','All of Me','John Legend','English','R&B / Soul','Love in the Future (Expanded Edition)',2013,2),
('3cfOd4CMv2snFaKAnMdnvK','All Star','Smash Mouth','English','Alternative / Indie','Astro Lounge',1999,2),
('4bJygwUKrRgq1stlNXcgMg','All The Things She Said','t.A.T.u.','English','Pop','200 KM/H In the Wrong Lane',2002,1),
('0JiVRyTJcJnmlwCZ854K4p','Alone','Alan Walker','English','Electronic / Dance','Alone - Single',2016,1),
('0bMbDctzMmTyK2j74j3nF3','Alone, Pt. II','Alan Walker','English','Electronic / Dance','Alone, Pt. II - Single',2019,2),
('0gdWSthwNMJ4TPVya8b0bh','Already Gone','RICEWINE','English','Pop','Already Gone - Single',2021,1),
('4wuu0v0TsGf22iYAgIcKlb','Altered State of Mind','Milmine','English','Alternative / Indie','Altered State of Mind - Single',2017,1),
('2rbDhOo9Fh61Bbu23T2qCk','Always Remember Us This Way','Lady Gaga','English','Soundtrack','A Star Is Born Soundtrack',2018,1),
('7qH9Z4dJEN0l9bidizW7fq','Anchor','Novo Amor','English','Alternative / Indie','Bathing Beach - EP',2017,1),
('1oAwsWBovWRIp7qLMGPIet','Apocalypse','Cigarettes After Sex','English','Alternative / Indie','Cigarettes After Sex',2017,1),
('5vNRhkKd0yEAg8suGBpjeY','APT.','ROSÉ & Bruno Mars','English','Pop','APT. - Single',2024,2),
('x5ad558973ccd','Art of Life','Lusha','English','Folk','Art of life - Single',2024,1),
('3UpS7kBnkVQYG13pDDFTC4','As Long as You Love Me','Backstreet Boys','English','Pop','Backstreet Boys',1997,3),
('7jjglGoCooAXRZnkbybiw3','Autumn Leaves','SIENNA SPIRO','English','Pop','Visitor (Deluxe)',2026,1),
('0SzvmWfOhoxZVGrmvb56YL','Baby I''m Yours','Arctic Monkeys','English','Alternative / Indie','Leave Before the Lights Come On - EP',2006,1),
('7IX2e7pEShera9T1QIMvi7','Baby I''m-a Want You','Bread','English','Rock','Baby I''m a Want You',1971,1),
('6vcdzohhBSbNdsZBh5IRpQ','Back for Good','Take That','English','Pop','Never Forget: The Ultimate Collection',1995,1),
('08mG3Y1vljYA6bvDt4Wqkj','Back In Black','AC/DC','English','Hard Rock','Back In Black',1980,1),
('0FTmksd2dxiE5e3rWyJXs6','back to friends','sombr','English','Indie Rock','back to friends - Single',2024,1),
('1WvsZ19Rl2NKYMb2daFksK','Bass Go Boom','triangel','English','Unknown','',null,1),
('7FCfMXYTIiQ9b4hDYs4Iol','Be the One','Dua Lipa','English','Pop','Dua Lipa (Deluxe)',2015,1),
('2LXtyj95dK56ENS1QLt4IB','Beach Baby','Bon Iver','English','Alternative / Indie','Blood Bank - EP',2009,1),
('3BovdzfaX4jb5KFQwoPfAw','Beat It','Michael Jackson','English','Pop','Thriller',1982,1),
('0gzqZ9d1jIKo9psEIthwXe','Beautiful Day','U2','English','Rock','All That You Can''t Leave Behind',2000,1),
('7uYQELhe7g6QLIzZDOlhbW','Beige','Yoke Lore','English','Alternative / Indie','Goodpain - EP',2017,1),
('0pqnGHJpmpxLKifKRmU6WP','Believer','Imagine Dragons','English','Alternative / Indie','Evolve',2017,2),
('6Ulcs1ZFV3yMQmQrSfixiM','Bennie And The Jets','Elton John','English','Rock','Goodbye Yellow Brick Road (2014 Remaster)',1973,1),
('1Q7EgiMOuwDcB0PJC6AzON','Best Part (feat. H.E.R.)','Daniel Caesar and H.E.R.','English','R&B / Soul','Freudian',2017,1),
('0mIN35QnVz5nl0DfpHBhmy','Bikhra','Abdul Hannan','Urdu','Pop','Bikhra - Single',2022,1),
('6dOtVTDdiauQNBQEDOtlAB','BIRDS OF A FEATHER','Billie Eilish','English','Alternative / Indie','HIT ME HARD AND SOFT',2024,1),
('1WYEDcS7WGjv0rG7rmMX3o','Bitter Sweet Symphony','The Verve','English','Pop','Urban Hymns (Deluxe / Remastered 2016)',1997,2),
('5Xak5fmy089t0FYmh3VJiY','Black','Pearl Jam','English','Rock','Ten',1991,1),
('1Rezzt36ybaT2ZbDZpv83D','Black Milk','Massive Attack','English','Electronic / Dance','Mezzanine',1998,1),
('7kJlTKjNZVT26iwiDUVhRm','Blow Your Mind','Dua Lipa','English','Pop','Blow Your Mind (Mwah) - Single',2016,1),
('1dtLFRRmiGg2nBaV4Rg9Ux','Blue','Far Caspian','English','Indie Rock','Between Days - EP',2018,1),
('1Ng9fMWIR9BvnWPCOVHzfB','Blue Bird','Ikimono-gakari','English','J-Pop','Chou Ikimonobakari Tennen Kinen Members Best Selection',2016,1),
('0dPF6g1FbTnIAf6dHWtSK9','Blush','Miller Blue','English','R&B / Soul','Blush - Single',2021,1),
('2JiDi0qAXsPwhPqA2qaKGt','Bohemian Rhapsody','Queen','English','Rock','A Night At The Opera (Deluxe Edition)',1975,1),
('6YrHQ3Uv9YXK2gJNVTlT8P','Brass in Pocket','Pretenders','English','Rock','Pretenders (Expanded Edition) [2006 Remaster]',1979,1),
('285hMzLhJwHVLe9QT9qilk','Breakeven','The Script','English','Pop','The Script',2008,1),
('0COqiPhxzoWICwFCS4eZcp','Bring Me to Life','Evanescence','English','Hard Rock','Fallen',2003,1),
('2GgxS8bUT5G25QJTsfSv0R','Burn','Ellie Goulding','English','Pop','Halcyon Days',2013,1),
('7mvuJXlOpZ7PUZezHXVsyX','Butterfly Tattoo','Danish Sood','English','Pop','Butterfly Tattoo - Single',2026,1),
('4r8lRYnoOGdEi6YyI5OC1o','Bye Bye Bye','NSYNC','English','Pop','No Strings Attached',2000,2),
('5eM6Rrk8rwLpUhrh7Kk5R1','California','Joni Mitchell','English','Pop','Blue',1971,3),
('3mWpUEBYnv9SIFWfixSJFx','Can''t Get Enough Of Your Love, Babe','Barry White','English','R&B / Soul','Can''t Get Enough',1974,1),
('44AyOl4qVkzS48vBsbNXaC','Can''t Help Falling in Love','Elvis Presley','English','Pop','Blue Hawaii (Original Soundtrack)',1961,1),
('3bidbhpOYeV4knp8AIu8Xn','Can''t Hold Us','Macklemore','English','Hip-Hop / Rap','The Heist (Deluxe Edition)',2011,1),
('2AogRMqARWyUP7VQ3gmSoY','Can’t Fight the Moonlight','LeAnn Rimes','English','Soundtrack','Coyote Ugly (Soundtrack from the Motion Picture)',2000,1),
('4R2kfaDFhslZEMJqAFNpdd','cardigan','Taylor Swift','English','Alternative / Indie','folklore',2020,1),
('0AIpGG5dxEgnAymhdJRSZ0','Champagne Coast','Blood Orange','English','Alternative / Indie','Coastal Grooves (Bonus Track Version)',2011,2),
('5Y0uBJtDX6lJNUm6YybDnX','CHAN MAHIYA - ACOUSTIC','Abdullah Maharvi, Annural Khalid','Urdu','Singer/Songwriter','CHAN MAHIYA (ACOUSTIC) - Single',2025,1),
('27SdWb2rFzO6GWiYDBTD9j','Cheap Thrills','Sia','English','Pop','This Is Acting',2015,1),
('4Q66chx9WzqWcLItXoZ5r4','Cherry Wine - Live','Hozier','English','Alternative / Indie','Hozier',2014,1),
('60wwxj6Dd9NJlirf84wr2c','Clarity (feat. Foxes)','Zedd','English','Electronic / Dance','Clarity (Deluxe Edition)',2012,1),
('2GjMaJ7DacMIkgoe8oMXGg','Close To Me','Ellie Goulding','English','Pop','Brightest Blue',2018,1),
('7BKLCZ1jbUBVqRi2FVlTVw','Closer','The Chainsmokers','English','Electronic / Dance','Collage - EP',2016,2),
('4sDbdBjuYQVdNNB4PiHUPo','Coastline','Good Neighbors','English','Unknown','',null,1),
('5xEM5hIgJ1jjgcEBfpkt2F','Complicated','Avril Lavigne','English','Pop','Let Go',2002,2),
('2tpWsVSb9UEmDRxAl1zhX1','Counting Stars','OneRepublic','English','Pop','Native (Deluxe)',2013,1),
('0nsIevK1SeDfZzDOi6Si75','Crush','Ethel Cain','English','Unknown','',null,1),
('7hoywpB0PVXwQKll5TaQiT','Crutch','Love Spells','English','Alternative / Indie','Crutch - Single',2026,1),
('5rYTMjVkGioNF4MpSQISlg','Desoleil (Brilliant Corners)','Loyle Carner','English','Unknown','',null,1),
('1PYV3TA7E1elt9AFcQmOIZ','Dhun','Navjot Ahuja','Hindi/Urdu','Rock','Dhun - Single',2022,1),
('7oDd86yk8itslrA9HRP2ki','Die for You (Remix)','The Weeknd & Ariana Grande','English','R&B / Soul','Die For You (Remix) - Single',2023,1),
('2plbrEY59IikOBgBGLjaoe','Die With A Smile','Lady Gaga & Bruno Mars','English','Pop','Die With A Smile - Single',2024,1),
('2jSJm3Gv6GLxduWLenmjKS','Digital Bath','Deftones','English','Hard Rock','White Pony',2000,1),
('7rXK1ksEA28ZnOQSwMXGuY','Dil Se','Yawar Abdal','Hindi','Unknown','',null,1),
('0RFxx8rwddnW4j9COvLmGK','Dilaan De Rajya','Maninder Buttar','Punjabi','Unknown','',null,1),
('1VUhLrBErkwHoS0vGEfpzm','Dive In','Finn Askew','English','Pop','Dive In - Single',2025,1),
('6pgTnSZA6ululNCsrhBsZm','Do I Look Like Jesus Christ?!','Dame Atlas','English','Unknown','',null,1),
('2yi7HZrBOC4bMUSTcs4VK6','Do You Want to Build a Snowman','Agatha Lee Monn, Katie Lopez, and Kristen Bell','English','Musicals','Frozen (Original Motion Picture Soundtrack)',2013,1),
('3PfIrDoz19wz7qK7tYeu62','Don''t Start Now','Dua Lipa','English','Pop','Don''t Start Now - Single',2019,3),
('27xkOIER6uDLKALIelHylZ','Don’t Say You Love Me','Jin','English','K-Pop','Echo',2025,1),
('47isJpIIO8m7BJEhiFhnaf','double take','Dhruv','English','Pop','double take - Single',2019,1),
('0OhafDbJz8ZytEGmhWYWoA','Drops of Jupiter','Train','English','Pop','Alive at Last (Live)',2004,1),
('6Pnf0VIWVFTZqRNytCpfDr','Ear Candy','Malvika.online','English','Pop','Ear Candy - Single',2026,1),
('7INi4pMPG4IE0Smx5y4KVf','Easy Lover','Philip Bailey & Phil Collins','English','R&B / Soul','Chinese Wall (Bonus Track)',1984,1),
('4Zy6m1QjUivLl8Zt7E8uxr','Edge of the Earth','The Beaches','English','Alternative / Indie','Blame My Ex',2023,1),
('5zpubzwKoDQupHOCI6kgMf','Enter Sandman','Metallica','English','Metal','Metallica (Deluxe Box Set)',1991,1),
('6me7F0aaZjwDo6RJ5MrfBD','Evergreen','Richy Mitch & The Coal Miners','English','Singer/Songwriter','Evergreen (feat. Caamp) - Single',2024,1),
('1di1BEgJYzPvXUuinsYJGP','Everybody (Backstreet''s Back)','Backstreet Boys','English','Pop','Backstreet Boys',1997,2),
('2iUmqdfGZcHIhS3b9E9EWq','Everybody Talks','Neon Trees','English','Alternative / Indie','versions of you (EP)',2021,1),
('32iNr3J93tqFkxaMYwdRYi','Everywhere, Everything','Noah Kahan with Gracie Abrams','English','Alternative / Indie','Everywhere, Everything - Single',2023,1),
('7gHs73wELdeycvS48JfIos','Faded','Alan Walker','English','Electronic / Dance','Faded - EP',2015,2),
('7LbUv7w2z7rEbNqp1uIL9U','Fallingforyou','The 1975','English','Alternative / Indie','The 1975 (Deluxe)',2013,1),
('1gihuPhrLraKYrJMAEONyc','Feel So Close','Calvin Harris','English','Electronic / Dance','Feel So Close',2011,1),
('6Rqn2GFlmvmV4w9Ala0I1e','Feeling Good','Nina Simone','English','Jazz','I Put a Spell On You',1965,1),
('2LqWD3f9nm0aEfsoy1NwoO','FIKAR','Kaifi Khalil','Urdu','Unknown','',null,1),
('2ve6fUxdNg56eubZpNzfdk','Firaaq','Akshita Mengi','English','Pop','Firaaq - Single',2026,1),
('7LVHVU3tWfcxj5aiPFEW4Q','Fix You','Coldplay','English','Alternative / Indie','X&Y',2005,1),
('7ab0HieXGKChMstA42bn69','Foolmuse','Peter Cat Recording Co.','English','Alternative / Indie','Beta',2024,1),
('3sYDVtqO35oRSOIMx7dOqR','Freak','Lana Del Rey','English','Alternative / Indie','Honeymoon',2015,1),
('5tVA6TkbaAH9QMITTQRrNv','Free Fallin''','Tom Petty','English','Rock','Greatest Hits',1989,1),
('50G9IOZlYuvtcdalWgl7se','Fuego','Bassjackers','English','Electronic / Dance','Fuego - Single',2025,1),
('25OmkVXG16xogP8xdZoVT2','Ganga Kinare','Bunny & Sagar','Hindi','Unknown','',null,1),
('3AjSSQpr1vU1S7FpmO24NP','Gawara','Abdul Hannan and Shahmeer Raza Khan','Urdu','Pop','Gawara - Single',2022,1),
('11mwFrKvLXCbcVGNxffGyP','Genie in a Bottle','Christina Aguilera','English','Pop','Christina Aguilera (Expanded Edition)',1999,2),
('3Z0qLOS0cqWKPHXkbTXmNF','Gilded Lily','Cults','English','Alternative / Indie','Offering',2023,1),
('1h4XVjt26ZCDKmeEoHxT07','Gimme Little Sign','Brenton Wood','English','Soundtrack','Brenton Wood''s 18 Best',1966,1),
('0wbDgMuAoy7O7pL3a69uZx','Give It To Me','Nelly Furtado','English','Hip-Hop / Rap','Shock Value',2007,1),
('3Ty7OTBNSigGEpeW2PqcsC','Glory Box','Portishead','English','Electronic / Dance','Dummy',1994,1),
('0qMip0B2D4ePEjBJvAtYre','Gurenge','LiSA','English','J-Pop','LEO-NiNE',2019,1),
('6jWLyg8AuMQ9LtIB2UlfOF','Hanging by a Moment','Lifehouse','English','Rock','No Name Face',2000,1),
('1JO1xLtVc8mWhIoE3YaCL0','Happy Together','The Turtles','English','Pop','Happy Together',1967,1),
('1rfofaqEpACxVEHIZBJe6W','Havana','Camila Cabello','English','Pop','Camila',2017,1),
('4IvZLDtwBHmBmwgDIUbuwa','Here Comes Your Man','Pixies','English','Alternative / Indie','Doolittle',1989,1),
('3NLrRZoMF0Lx6zTlYqeIo4','Here Without You','3 Doors Down','English','Rock','The Greatest Hits',2002,1),
('3zU9rdflI65tK4dkkNSp77','Heroes (we could be)','Alesso','English','Electronic / Dance','Heroes (We Could Be) [The Remixes] [feat. Tove Lo]',2014,1),
('4RCWB3V8V0dignt99LZ8vH','Hey There Delilah','Plain White T''s','English','Pop','Every Second Counts',2005,1),
('1dKUibfoGwiApjEYJhB9R2','High Hopes 3000','ROLE MODEL','English','Pop','Chuck Timely & The Hourglass',2026,1),
('3d0WouFnFmr0K3kjeza3fF','Hips Don’t Lie','Shakira, Ed Sheeran & Beéle','English','Pop Latino','Oral Fixation, Vol. 2 (Expanded Edition)',2005,1),
('55l73rMvxdjkFSDjEKhyWG','Hollow','emma who?','English','Indie Pop','heaven won''t be knocking at your door',2026,1),
('7DcJ6fEBb7BaKuYKTwiDxK','Homage','Mild High Club','English','Alternative / Indie','Skiptracing',2016,1),
('6cOGSlZKf1nJMiNs13qZnq','HONEYMOON','Jo Hill','English','Unknown','',null,1),
('6D8y7Bck8h11byRY88Pt2z','Houdini','Dua Lipa','English','Pop','Houdini - Single',2023,1),
('0oRgjkJQJAtx0oBxnUPFxv','Humdum','Rahat Fateh Ali Khan','Urdu','Indian','Nasha - Single',2020,1),
('3RiPr603aXAoi4GHyXx0uy','Hymn for the Weekend','Coldplay','English','Alternative / Indie','A Head Full of Dreams',2015,1),
('37l31PrCNsg8baUjarNAi9','I Can''t Handle Change','Roar','English','Pop','I Can''t Handle Change - EP',2010,1),
('7vRriwrloYVaoAe3a9wJHe','i hate u, i love u','gnash','English','Pop','us',2016,1),
('6RNDeRnWsRMjPdNVgupZCs','I Just Called To Say I Love You','Stevie Wonder','English','Soundtrack','The Woman in Red (Original Motion Picture Soundtrack)',1984,1),
('0f8GDk3hYFkHkpecyUByZ7','I Need Your Love','Ellie Goulding','English','Pop','Halcyon Nights',2012,1),
('58pTPJPBjw1xL9OcLcQczU','I Remember Everything (feat. Kacey Musgraves)','Zach Bryan and Kacey Musgraves','English','Country','Zach Bryan',2023,1),
('1Roq03sTKb6TPKBY89YJ4v','I Think I Like When It Rains','Willis','English','Alternative / Indie','Locals 2 - EP',2017,1),
('4qUO70Asimha8yuo5GI9NP','I Took a Pill In Ibiza','Mike Posner','English','Singer/Songwriter','At Night, Alone.',2015,1),
('5XeFesFbtLpXzIVDNQP22n','I Wanna Be Yours','Arctic Monkeys','English','Alternative / Indie','AM',2013,1),
('47BBI51FKFwOMlIiX6m8ya','I Want It That Way','Backstreet Boys','English','Pop','Millennium',1999,3),
('5LxvwujISqiB8vpRYv887S','I Want You Back','The Jackson 5','English','R&B / Soul','Diana Ross Presents the Jackson 5',1969,1),
('6ENaRQvWws0NEO6RLnGzoF','I Want You to Want Me','Letters to Cleo','English','Pop','10 Things I Hate About You (Original Motion Picture Soundtrack)',1999,1),
('6mSnSuOhgHHohqeBw76jRV','i was all over her','salvia palth','English','Unknown','',null,1),
('1CSLeVCXmetBh8IkTPMFdL','I''m a Believer','The Monkees','English','Pop','More of the Monkees (Deluxe Edition)',1966,1),
('2aGw77pZqli064JiPuXYRi','I''m Like A Bird','Nelly Furtado','English','Pop','Whoa, Nelly!',2000,2),
('3PzsbWSQdLCKDLxn7YZfkM','I''m On Fire','Bruce Springsteen','English','Rock','Born In the U.S.A.',1984,1),
('1jlG3KJ3gdYmhfuySFfpO1','I''m with You','Avril Lavigne','English','Pop','Let Go',2002,1),
('76cy1WJvNGJTj78UqeA5zr','IDGAF','Dua Lipa','English','Pop','Dua Lipa (Deluxe)',2018,3),
('1zVsw1SqQKgtzE4aqmE8nE','Idol','YOASOBI','English','J-Pop','Idol - Single',2023,1),
('2kJwzbxV2ppxnQoYw4GLBZ','If the World Was Ending','Bruno Mars','English','Pop','If The World Was Ending (Remixes) [feat. Julia Michaels] - EP',2019,1),
('3KfbEIOC7YIv90FIfNSZpo','In My Life - Remastered','The Beatles','English','Rock','Rubber Soul (Remastered 2009)',1965,2),
('60a0Rd6pjrkxjPbaKzXjfq','In the End','Linkin Park','English','Alternative / Indie','Hybrid Theory (Deluxe Edition)',2000,1),
('62zFEHfAYl5kdHYOivj4BC','International Love','Pitbull','English','Pop','Planet Pit (Deluxe Version)',2011,1),
('6Qyc6fS4DsZjB2mRW9DsQs','Iris','Goo Goo Dolls','English','Pop','Dizzy Up the Girl',1998,2),
('1xgEKRvKO0erYx1JD7YTEO','Is This Love','Whitesnake','English','Rock','Whitesnake (30th Anniversary Super Deluxe Edition)',1987,1),
('0cd2z6Lkm6Syj01l9bdEzq','Ishaare','Curtain Blue','Hindi/Urdu','Unknown','',null,1),
('3eR23VReFzcdmS7TYCrhCe','It Ain''t Me','Kygo & Selena Gomez','English','Pop','It Ain''t Me - Single',2017,1),
('1T4zpIClNclqDC6fVZKjRZ','It Hurts to Be Alone','Bob Marley & The Wailers','English','Roots Reggae','Trenchtown Days: Birth of a Legend',1977,1),
('44A0o4jA8F2ZF03Zacwlwx','Je te laisserai des mots','Patrick Watson','English','Alternative / Indie','Je Te Laisserai Des Mots - Single',2010,1),
('4G92yYrUs0cvY7G41YRI0z','Jealous','Labrinth','English','Pop','Jealous - Single',2014,1),
('0OWrB5fNAY53HKowEtGu7c','Joy (Wouldn''t That Be Good)','Joy Anonymous','English','Electronic / Dance','Joy (Wouldn''t That Be Good) [feat. Elise My Niece & Gud Jon] - Single',2019,1),
('2HbCo1YJTZyF8hD3eyFKPN','Just Keep Watching','Tate McRae','English','Pop','F1 The Album',2025,1),
('7BqBn9nzAq8spo5e7cZ0dJ','Just the Way You Are','Bruno Mars','English','Pop','Doo-Wops & Hooligans (Deluxe)',2010,1),
('3Uwok7aLLQyXhfqNlekSim','Kaise Ho Tum','Divyam Sodhi','Hindi','Indian Pop','Ehsaas - EP',2025,1),
('3gixnmepHSsyAuho34rprN','Khat','Navjot Ahuja','Hindi/Urdu','Indian Pop','Khat - Single',2025,1),
('754kgU5rWscRTfvlsuEwFp','Kiss Me','Sixpence None the Richer','English','Pop/Rock','Sixpence None the Richer',1997,1),
('6ZOBP3NvffbU4SZcrnt1k6','Kryptonite','3 Doors Down','English','Rock','The Better Life',2000,1),
('6F9yAYUaNbUhdlQyt5uZ3b','La Incondicional','Luis Miguel','Spanish','Latin','Busca una Mujer',1988,1),
('6xOEgzkMSZJKz6qtCJsQL5','La Plena','W Sound 05, Beéle, Ovy On The Drums','Spanish','Latin','La Plena (W Sound 05) - Single',2025,1),
('6YkGw5op7PeyP2gmMMMrfJ','La Villa','Ryan Castro','Spanish','Unknown','',null,1),
('0phzfJn8NeT1LkbqfV2peI','Lejos de Ti','The Marias','English','Alternative / Indie','Submarine',2024,1),
('7Cd17G3oNQ34OWUwS8ZxfR','LEMON','Kenshi Yonezu','English','J-Pop','Lemon - Single',2018,1),
('2pUpNOgJBIBCcjyQZQ00qU','Let Her Go','Passenger','English','Singer/Songwriter','All the Little Lights',2012,1),
('2X485T9Z5Ly0xyaghN73ed','Let It Happen','Tame Impala','English','Alternative / Indie','Currents',2015,1),
('6Xe9wT5xeZETPwtaP2ynUz','Levels','Avicii','English','Electronic / Dance','Levels - EP',2011,1),
('39LLxExYz6ewLAcYrzQQyP','Levitating','Dua Lipa','English','Pop','Future Nostalgia',2020,5),
('11ozIUBoXAgRTVWelDn4pL','Lights','Ellie Goulding','English','Pop','Lights (Deluxe)',2010,1),
('3HHehSGzW9dhs2V7Sod4jX','Linger','The Cranberries','English','Pop','Stars: The Best of the Cranberries 1992-2002',1993,1),
('0tMSssfxAL2oV8Vri0mFHE','Listen Before I Go','Billie Eilish','English','Alternative / Indie','WHEN WE ALL FALL ASLEEP, WHERE DO WE GO?',2019,1),
('6zNrg1vlH3rarWRzaHGuZr','Little Queenie','SadGirl','English','Rock','Vol. Three: The Hand That Did the Deed - EP',2016,1),
('7x5xYW5W42OGPAdHUyyguy','Locked Away','R. City feat. Adam Levine','English','Pop','What Dreams Are Made Of',2015,1),
('5Z01UMMf7V1o0MzF86s6WJ','Lose Yourself','Eminem','English','Soundtrack','8 Mile (Music from and Inspired By the Motion Picture)',2002,1),
('4rPkN1FMzQyFNP9cLUGIIB','Love Again','Dua Lipa','English','Pop','Future Nostalgia',2020,1),
('5Ts1DYOuouQLgzTaisxWYh','Love Grows','Edison Lighthouse','English','Pop','Big Hits of the ''60s & ''70s Volume 1',1984,1),
('7HE1FnMtSsRotzIAQPXpr5','Love Me Harder','The Weeknd & Ariana Grande','English','Pop','My Everything',2014,1),
('0Cy7wt6IlRfBPHXXjmZbcP','Love Me Like You Do','Ellie Goulding','English','Soundtrack','Fifty Shades Freed (Original Motion Picture Soundtrack)',2015,1),
('7iBBcw61QVJxI3NDzlpX2E','Love Me Tender','Elvis Presley','English','Rock','The Essential Elvis Presley',1956,1),
('3IVaPHncIZWWNjfg29HVLq','Love T.K.O.','Teddy Pendergrass','English','R&B / Soul','TP (Expanded Edition)',1980,1),
('15JINEqzVMv3SvJTAXAKED','Love the Way You Lie','Eminem & Rihanna','English','Hip-Hop / Rap','Recovery',2010,1),
('58RDwkonFMOkoytBtIQetc','Love You to Death','Type O Negative','English','Metal','October Rust',1996,1),
('50kpGaPAhYJ3sGmk6vplg0','Love Yourself','Justin Bieber','English','Pop','Purpose (Deluxe)',2015,1),
('3dq3nRBGMcXmfY4iC6Jess','Lovestone','Micah Edwards, David Blazer','English','R&B / Soul','Lovestone - Single',2021,1),
('4Y6cDd4EPHcEbiUKdyvNwM','Macarena','Los del Río','English','Pop Latino','Fiesta Macarena',1995,1),
('4wH4dJgrsxONID6KS2tDQM','Maneater','Nelly Furtado','English','Pop','Loose',2006,1),
('6x3QIoNigqF82XJAFxTsya','Manos Al Aire','Nelly Furtado','English','Pop Latino','Manos al Aire (World Mixes) - EP',2009,1),
('3IDc87lrpEHWFBASmgTgFV','Mercy Mercy Me (The Ecology)','Marvin Gaye','English','R&B / Soul','What''s Going On',1971,1),
('6GyFP1nfCDB8lbD2bG0Hq9','Midnight City','M83','English','Electronic / Dance','Hurry Up, We''re Dreaming',2011,1),
('0aSf9IRbXwZsQryKrsFcFy','Morning After Dark','Nelly Furtado','English','Pop','Shock Value II',2009,1),
('6TT7B4MigCJCc0tqKYEpZC','Moves','Suki Waterhouse','English','Alternative / Indie','I Can''t Let Go',2021,1),
('6f4itfvWzS59Qu7JWorhxn','Movies','Weyes Blood','English','Alternative / Indie','Titanic Rising',2019,1),
('003vvx7Niy0yvhvHt4a68B','Mr. Brightside','The Killers','English','Rock','Direct Hits',2003,2),
('5DiXcVovI0FcY2s0icWWUu','Mr. Jones','Counting Crows','English','Rock','August and Everything After',1993,1),
('38tfi9dtBQQ5Wyt7EL0G3z','My Kind of Woman','Mac DeMarco','English','Alternative / Indie','2',2012,1),
('5GbVzc6Ex5LYlLJqzRQhuy','Mystery of Love','Sufjan Stevens','English','Soundtrack','Call Me by Your Name (Original Motion Picture Soundtrack)',2004,1),
('6m5sG6iWIfnO5o9RG20xhu','Naazni','Annural Khalid, Abdullah Siddiqui','Urdu','Pop','Naazni - Single',2025,1),
('4rd5oaaf3JkDGiiVjfvqjk','Naina','Aayu','Hindi/Urdu','Indian Pop','Naina - Single',2025,1),
('7dEfa89dZfo6CQPdsgGCF6','Nandemonaiya','RADWIMPS','Japanese','Rock','Your Name.',2016,1),
('7FTDYXZEsuuD8WWeIPV001','Nectarine','Oddisee','English','Unknown','',null,1),
('02shCNmb6IvgB5jLqKjtkK','Nevada (feat. Cozi)','Vicetone','English','Electronic / Dance','Nevada (feat. Cozi Zuehlsdorff) - Single',2016,1),
('2ekn2ttSfGqwhhate0LSR0','New Rules','Dua Lipa','English','Pop','Dua Lipa (Deluxe)',2017,1),
('3UDpwoxz9SUvVE0e1mnsxx','NIGHTS LIKE THIS','The Kid LAROI','English','Pop','THE FIRST TIME',2023,1),
('1Vb4HQnN2kZ5Y2KgYF5TDV','No Lie','Dua Lipa','English','Reggae','Mad Love: The Prequel',2016,2),
('3RIgHHpnFKj5Rni1shokDj','Norman Fucking Rockwell!!','Lana Del Rey','English','Alternative / Indie','Norman Fucking Rockwell!',2019,1),
('3o9kpgkIcffx0iSwxhuNI2','Numb Little Bug','Em Beihold','English','Pop','Numb Little Bug - Single',2022,2),
('6tnW4s6zXXqOefLrnf1lYk','Numpty','Paolo Nutini','English','Pop','Caustic Love',2014,1),
('0AjcdGri5vhJsmZnduCEqd','October Passed Me By','girl in red','English','Alternative / Indie','October Passed Me By - Single',2022,1),
('1BLOVHYYlH4JUHQGcpt75R','Ode To The Mets','The Strokes','English','Pop','Skinwalkers IV - Single',2014,1),
('4n7jnSxVLd8QioibtTDBDq','On My Way','Alan Walker','English','Electronic / Dance','On My Way (Da Tweekaz Remix) - Single',2019,1),
('3C0nOe05EIt1390bVABLyN','On The Floor','Jennifer Lopez featuring Pitbull','English','Pop','LOVE? (Bonus Version)',2011,1),
('6qqrTXSdwiJaq8SO0X2lSe','Ordinary','Alex Warren','English','Pop','Ordinary - Single',2024,1),
('0vItJLwvxJzu5PPw6o62A6','Our House - Demo','Graham Nash & Joni Mitchell','English','Rock','Déjà Vu (50th Anniversary Deluxe Edition)',1970,1),
('7MmG8p0F9N3C4AXdK6o6Eb','Outside','Ellie Goulding','English','Electronic / Dance','Motion',2014,2),
('3m083t4HzUoU5jv5EQzIr8','Pahado Ki Sard Hawa','Rawmats & Krishna Singh','Hindi','Indian Pop','Pahado Ki Sard Hawa - Single',2026,1),
('0tgVpDi06FyKpA1z0VMD4v','Perfect','Ed Sheeran','English','Pop','÷ (Deluxe)',2017,2),
('77D0gduGbVpmLLeqZpXEP1','Phir Se Milenge','Aeymanntara & Amar Kashyap','Hindi','Indie Pop','Phir Se Milenge - Single',2026,1),
('7mVREWqbljHlbmTXSKl1zs','Pina Colada','Rupert Holmes','English','Urbano latino','Piña Colada - Single',2022,1),
('5iacz50wp5ncLjr8w9ZZ5T','Piya','Khwaab, Divyam Sodhi, Bhumi, and Circle Tone','Hindi/Urdu','Pop','SUKOON - EP',2026,1),
('5YPMEOJ58kfl56VHxTgwx3','Play Hard (feat. Akon)','David Guetta','English','Pop','Nothing But the Beat 2.0',2012,1),
('6QgcyluNYt0xLANGOg3jpM','Please, Please, Please Let Me Get What I Want','Deftones','English','Hard Rock','B-Sides & Rarities (Bonus Track Version)',2005,1),
('5UiaszjisznaX77YaCgUhX','Plus Je T''embrasse','Blossom Dearie','English','Jazz','The Diva Series',1958,1),
('7g1251d41qVR8kq6yz9XXa','pouring outside','dyl dion','English','Pop','Pouring Outside - Single',2021,1),
('3Q6T5Xwf39j9HTQwUZERMT','Powerful','Ellie Goulding','English','Electronic / Dance','Peace Is The Mission (Extended)',2015,1),
('2gam98EZKrF9XuOkU13ApN','Promiscuous','Nelly Furtado','English','Pop','Loose (Expanded Edition)',2006,1),
('6OXPLt5yKSqf7fSFKvSxMw','Pyari Amaanat','Arpit Bala, O.D., Angad Virk','Hindi/Urdu','Pop','Keychain Laalu',2025,1),
('4QhWbupniDd44EDtnh2bFJ','Pyramids','Frank Ocean','English','Classical Crossover','VSQ Performs Frank Ocean',2025,1),
('x5bd4902f036d','Qarib','Kaifi Khalil','Urdu','Unknown','',null,1),
('6FjbAnaPRPwiP3sciEYctO','Raabta','Abdul Hannan & Rovalio','Hindi','Pop','Raabta - Single',2023,2),
('6f7zyAEUCZuvX4Zty62Z5o','Radha','Shreya Ghoshal','Hindi','Bollywood','Student of the Year (Original Motion Picture Soundtrack)',2012,1),
('70mA7DPs4PDYXpNkWzta0p','Rahbara','Abhishek Srivastava, Shayra','Hindi/Urdu','Unknown','',null,1),
('2AnT5iXM8ET5kiqBuE8Mpi','Rakhlo Tum Chupaake','Arpit Bala, Adil','Hindi','Pop','Keychain Laalu',2025,1),
('26SBh3qrxSkpVqLRQkcSbU','Rave Therapy','Maddix, Bassjackers','English','Techno','Rave Therapy - Single',2026,1),
('2rOUaQ1TGj7wZdHdn9UgTL','ReawakeR (feat. Felix of Stray Kids)','LiSA, Felix','English','Unknown','',null,1),
('2YSrlOiR9kyiqUURfYwDXI','Ride It','Jay Sean','English','Contemporary R&B','My Own Way (Deluxe)',2008,1),
('4LFwNJWoj74Yd71fIr1W8x','Right Here Waiting','Richard Marx','English','Adult Contemporary','Greatest Hits',1989,1),
('4X6aeSW2bhlbm7YyEstj6Y','Rivers and Roads','The Head And The Heart','English','Alternative / Indie','The Head And The Heart',2010,1),
('6UwYHPRnrv4Glcp74tiP9B','Rivet Gun','Mother Soki','English','Alternative / Indie','Fantasy - EP',2025,1),
('58dBJivB6lbAY5irCuAxJX','Rock You Like a Hurricane','Scorpions','English','Hard Rock','Love at First Sting',1984,1),
('4OSBTYWVwsQhGLF9NHvIbR','Rolling in the Deep','Adele','English','Pop','21',2010,1),
('0BGkzaDbOlO8l0PosWFyyt','Romeo.','SohM','English','Unknown','',null,1),
('x360cb217420f','Rosalyn','Bon Iver','English','Unknown','',null,1),
('3FWPoYBDserKdzcattMFGa','Roses (feat. ROZES)','The Chainsmokers','English','Electronic / Dance','Bouquet - EP',2015,1),
('6RtPijgfPKROxEzTHNRiDp','Rude','MAGIC!','English','Pop','Don''t Kill the Magic',2013,1),
('4iHO9d5IT1Jc0EgMVBROG0','Saawariya','Iqbal Nova, Hiten, and Bandana Datta','Hindi/Urdu','Indian Pop','Saawariya - Single',2025,1),
('6osKPJp6kQwZcgUqBteJFN','Safari','Serena','English','Electronic / Dance','Safari - Single',2000,1),
('2dDHtDrDaxTB7QR6EoCSne','Saibo','Shreya Ghoshal','Hindi','Soundtrack','Saibo - Single',2011,1),
('18LQimMc3xmXMDIqmER6gF','Sakura','Eshan Kesari','Hindi/Urdu','Rock','Sakura - Single',2025,1),
('6gKjueO32MnERRo04gpJ8v','Same Effect','BENEE','English','Alternative / Indie','Hey u x',2020,1),
('0rk2X5TAhraBC5aCIXK2Rq','Samjhawan','Shreya Ghoshal','Hindi','Bollywood','Humpty Sharma Ki Dulhania (Original Motion Picture Soundtrack)',2014,1),
('52noeR9sobs1a0E0Z6VuUO','Save a Prayer','Duran Duran','English','New Wave','Rio (Remastered)',1982,1),
('1oFAF1hdPOickyHgbuRjyX','Save Your Tears (Remix)','The Weeknd & Ariana Grande','English','R&B / Soul','Save Your Tears (Remix) - Single',2021,1),
('2aI21FnmY7TJVKeMaoQZ0t','Say It Right','Nelly Furtado','English','Pop','Loose',2006,1),
('42ydLwx4i5V49RXHOozJZq','Scars To Your Beautiful','Alessia Cara','English','Pop','Know-It-All',2015,1),
('2t0wwvR15fc3K1ey8OiOaN','Selfless','The Strokes','English','Alternative / Indie','The New Abnormal',2020,1),
('4nsiKM4S8cRU3oWNiTOeWz','Settle','BAYNK, Sinéad Harnett','English','Electronic / Dance','Settle - Single',2018,1),
('3dPQuX8Gs42Y7b454ybpMR','Seven Nation Army','The White Stripes','English','Rock','Elephant',2003,1),
('6INLpBxo9F5QMer04VXEnd','Sexy Boy','Air','English','Electronic / Dance','Moon Safari',1998,1),
('35o9a4iAfLl5jRmqMX9c1D','Shape of My Heart','Backstreet Boys','English','Pop','Black & Blue',2000,2),
('7qiZfU4dY1lWllzX7mPBI3','Shape Of You','Ed Sheeran','English','Pop','÷ (Deluxe)',2017,2),
('0o9zmvc5f3EFApU52PPIyW','SHINUNOGA E-WA','Fujii Kaze','English','J-Pop','HELP EVER HURT NEVER',2020,1),
('75IQVo8hqI1iwVZyvkN2VT','Show Me How','Men I Trust','English','Pop','Show Me How - Single',2018,1),
('3BsaRV5QIulYz2lV9WWa8T','Show Me the Meaning of Being Lonely','Backstreet Boys','English','Pop','Millennium',1999,2),
('3nKEiJUeaWn8q2O9I1xwlB','Shukran Allah','Shreya Ghoshal','Hindi','Bollywood','Kurbaan (Original Motion Picture Soundtrack)',2009,1),
('1di1C0QI6Y92yZPYn6XYAZ','Silhouette','KANA-BOON','English','Rock','TIME',2014,1),
('2Fjz5ZC5BvFdCqcnTZ3ilH','Sing Me to Sleep','Alan Walker','English','Electronic / Dance','Sing Me to Sleep - Single',2016,1),
('2v4ZqzBYvsnb7WFuUISj8h','Skin','Prathamesh, Kod.E','English','Unknown','',null,1),
('4RL77hMWUq35NYnPLXBpih','Skinny Love','Birdy','English','Alternative / Indie','Fire Within',2011,1),
('3B3eOgLJSqPEA0RfboIQVM','Skinny Love','Bon Iver','English','Alternative / Indie','For Emma, Forever Ago',2007,1),
('5hx7w26Zi3zafMgvMTUqF6','SNAP','Rosa Linn','English','Indie Pop','SNAP - Single',2022,1),
('799ZxMkKLLWdxpXdpogkDi','SOBER','daste.','English','Indie Pop','SOBER - Single',2019,1),
('1qDrWA6lyx8cLECdZE7TV7','Somebody That I Used to Know','Gotye feat. Kimbra','English','Alternative / Indie','Making Mirrors',2011,1),
('1SKPmfSYaPsETbRHaiA18G','Somewhere Only We Know','Keane','English','Pop','Somewhere Only We Know - EP',2004,1),
('1Qj8q4Y7868u5q23jPDUS7','SONDER','late monday','English','Pop','SONDER - Single',2026,1),
('06CUyVD4i6YQ8X9dXC7mI6','Soundtrack for Your Backseat','sundiver ca','English','Alternative / Indie','Superstar Baby',2019,1),
('1ujxjsoNvh4XgS2fUNwkZ2','Space Song','Beach House','English','Alternative / Indie','Depression Cherry',2015,1),
('0pQskrTITgmCMyr85tb9qq','Starman - 2012 Remaster','David Bowie','English','Pop','The Rise and Fall of Ziggy Stardust and the Spiders from Mars (2012 Remaster)',1972,1),
('3DgV3M5T98FfrYtRfkm5RQ','Stay For One More Night','Goodvibes Sound','English','Alternative / Indie','Stay For One More Night - Single',2021,1),
('4w1e3b3GGYIz75SlMcFchT','still the same i see','sondaeblu','English','R&B / Soul','u said. this time will be different.',2026,1),
('7AGXTYi7SuenK2U5j3L8aW','still wanna hold u','SAMSON','English','Hip-Hop / Rap','Understand. - EP',2024,1),
('4nVBt6MZDDP6tRVdQTgxJg','Story of My Life','One Direction','English','Pop','Midnight Memories',2013,2),
('3CRDbSIZ4r5MsZ0YwxuEkn','Stressed Out','Twenty One Pilots','English','Alternative / Indie','Blurryface',2015,1),
('75z2YLg5Lkqf6qL9XOY8tV','Such Great Heights','The Postal Service','English','Electronic / Dance','Give Up (Deluxe 10th Anniversary Edition)',2003,1),
('6YUTL4dYpB9xZO5qExPf05','Summer','Calvin Harris','English','Electronic / Dance','Motion',2014,1),
('0dnsJ8W8k4ncYstIsrz5pY','sun saawariya','Insaan, AtharvaMusic, Yaani Karn','Hindi/Urdu','Indie Pop','sun saawariya - Single',2026,1),
('2QjOHCTQ1Jl3zawyYOpxh6','Sweater Weather','The Neighbourhood','English','Alternative / Indie','I Love You.',2012,1),
('1jUkHIMc7UaJQuzWe5Iop2','Sweet Disposition','The Temper Trap','English','Soundtrack','(500) Days of Summer (Music from the Motion Picture)',2008,2),
('1QbOvACeYanja5pbnJbAmk','Take Me Home, Country Roads','John Denver','English','Singer/Songwriter','The Windstar Greatest Hits',1971,1),
('4w8niZpiMy6qz1mntFA5uM','Taki Taki','DJ Snake with Selena Gomez, Ozuna, and Cardi B','English','Urbano latino','Ozu Vivo (Live)',2018,1),
('48Ix6ReYdJf2H4mKb3TIpj','Tera Hone Laga Hoon','Atif Aslam and Alisha Chinai','Hindi','Bollywood','Ajab Prem Ki Ghazab Kahani (Original Motion Picture Soundtrack)',2009,1),
('5GfZTeR24ugCddSRj0BKU9','Tere Bin Laage','Rashmeet Kaur','Hindi','Indian Pop','Tere Bin Laage (Lofi Flip) - Single',2024,1),
('3yUcJwYu7fXAfqMj9krY6l','Thank You','Dido','English','Pop','No Angel',1999,1),
('5uI8omnLtzW4xTqJ5AoQtT','That''s All I Ask','Nina Simone','English','Jazz','Wild Is The Wind',1966,1),
('7ne4VBA60CxGM75vw0EYad','That''s So True','Gracie Abrams','English','Pop','The Secret of Us (Deluxe)',2024,2),
('0dzUHHAq5OotCEmIbm4l7a','The Clock','KIRK','English','Electronic / Dance','The Clock - Single',2026,1),
('2TjdnqlpwOjhijHCwHCP2d','The Great Gig in the Sky','Pink Floyd','English','Rock','The Dark Side of the Moon',1973,1),
('6NG2IIXZfC5Notpz0GIODU','The Ketchup Song (Aserejé)','Las Ketchup','Spanish','Pop','Aserejé (The Ketchup Song) - Single',2000,1),
('35E2eKIEXXnP5q9L51iOAk','The Killing Moon','Echo & the Bunnymen','English','Pop','Songs to Learn and Sing',1985,1),
('1FSRbSFPdDvt6kBzlbB1Qe','The Macarena','Los del Río','English','Pop Latino','Fiesta Macarena',1995,1),
('48RrDBpOSSl1aLVCalGl5C','The Monster','Eminem & Rihanna','English','Hip-Hop / Rap','The Marshall Mathers LP2',2013,1),
('5yJaXWIErrrsjQ3J0eR5aK','The Night We Met','Lord Huron','English','Indie Rock','Strange Trails',2015,1),
('0ct6r3EGTcMLPtrXHDvVjc','The Nights','Avicii','English','Electronic / Dance','The Days / Nights - EP',2014,1),
('75JFxkI2RXiU7L9VXzMkle','The Scientist','Coldplay','English','Alternative / Indie','A Rush of Blood to the Head',2002,1),
('7ugKZR6VSLm7Q13H7iHQOm','The Signs','Tash','English','Electronic / Dance','The Signs - EP',2024,1),
('3iEUDvanZwQhLCIqUmCR7N','The Spins','Mac Miller','English','Electronica','Arcade Versions of Mac Miller',2021,2),
('5nNNHAwXNpf8Nu7JgqizjJ','The Trip','Still Corners','English','Indie Pop','Strange Pleasures',2013,2),
('1ndGB6rvxKYN9seCYO1dTF','The Zephyr Song','Red Hot Chili Peppers','English','Alternative / Indie','By the Way',2002,1),
('291EE0CgyNOXAGneMelSuE','There''s Nothing Holding Me Back','Shawn Mendes','English','Unknown','',null,1),
('6M31fPFCYB8Job3MCjjrDV','They Don''t Know About Us','One Direction','English','Pop','Take Me Home (Yearbook Edition)',2012,1),
('34gCuhDGsG4bRPIf9bb02f','Thinking Out Loud','Ed Sheeran','English','Pop','x (Wembley Edition)',2014,1),
('57bgtoPSgt236HzfBOd8kj','Thunderstruck','AC/DC','English','Hard Rock','Iron Man 2',1990,1),
('56hwcJKj0M40A3qdhV3177','Time Bomb','Rancid','English','Rock','...and out Come the Wolves',1995,1),
('54KFQB6N4pn926IUUYZGzK','To Build a Home','The Cinematic Orchestra','English','Electronic / Dance','Ma Fleur',2007,2),
('0upFohXrGxIIAjyaJmCkMU','Tokyo Drift','Teriyaki Boyz','English','Soundtrack','The Fast And The Furious: Tokyo Drift',2006,1),
('2w0UbvgPMhAXxz5qakD9Ms','tolerance','Asal','English','Alternative / Indie','Kiss the Sun',2026,1),
('xd46c860e7b3f','TOMA NO PEITO','GIØ','English','Unknown','',null,1),
('0GO8y8jQk1PkHzS31d699N','Tongue Tied','Grouplove','English','Alternative / Indie','Never Trust a Happy Song',2011,1),
('1BXela7xASLw1DCrv9ACBA','Tortoise','Jordan Mackampa and Harvey Gunn, Joel Baker, Ashley Henry','English','Unknown','',null,1),
('7mSiG1E3UxhhbLiw11Hj0v','Touch','Bearcubs','English','Electronica','Touch - Single',2014,1),
('6Qb7YsAqH4wWFUMbGsCpap','Training Season','Dua Lipa','English','Pop','Training Season - Single',2024,4),
('6hcXtEoIWQErXqyvOMZnLs','Training Season (Acoustic Version)','Dua Lipa','English','Pop','Training Season (Acoustic Version) - Single',2023,1),
('3S7HNKPakdwNEBFIVTL6dZ','Treacherous (Taylor''s Version)','Taylor Swift','English','Pop','Red (Taylor’s Version) [+ A Message from Taylor]',2021,1),
('1kS9d4x0ftbfq65eaBGSCT','Try','Nelly Furtado','English','Pop','Folklore',2003,1),
('5kR2eJal3foVQ48L1Dp4hh','Trying Things','Odeal','English','R&B / Soul','For A Good Time...',2026,1),
('4uAQEXmgvtEDKQgeyYrlUd','Tum Se Tum Tak','Niyam','Hindi','Indie Pop','Tum Se Tum Tak - Single',2026,1),
('4gM2BugovNf4bvXdjZODzG','Turn Off The Light','Nelly Furtado','English','Pop','Whoa, Nelly!',2000,1),
('4B1rpPmQXwj78wk6aIGwwU','Two Ghosts','Harry Styles','English','Pop','Harry Styles',2017,1),
('4AajxCEwGEsmHmT4H1TwjY','undressed','sombr','English','Indie Rock','undressed - Single',2025,1),
('1rN9QoVxw5U7TJkyaUR8C1','unravel','TK from Ling tosite sigure','English','Rock','Fantastic Magic',2014,1),
('0T5iIrXA4p5GsubkhuBIKV','Until I Found You','Stephen Sanchez','English','Singer/Songwriter','Until I Found You - Single',2022,1),
('32OlwWuMpZ6b0aN2RZOeMS','Uptown Funk','Bruno Mars','English','Pop','Uptown Special',2014,1),
('4PIzo7o9Vydptg9Tw7ICcr','Velvet & Lace','TEXTILES','English','Pop','Textiles - EP',2021,1),
('5JQs2VdCFMSS4zDsN1cM01','Victory Lap','Dan Whitlam','English','Pop','Strangers (Again)',2026,1),
('6TFr1fKugaFyGF7hzH2XQo','Waka Waka (This Time for Africa)','Shakira','English','Children''s Music','Lullaby Renditions of Shakira',2020,1),
('x7cf1261e669b','Watch Me','Labrinth','English','Unknown','',null,1),
('6kISMRfweKSvgHR0urMQFG','We Are Never Ever Getting Back Together','Taylor Swift','English','Country','Red',2012,2),
('06KyNuuMOX1ROXRhj787tj','We Don''t Talk Anymore','Charlie Puth','English','Pop','Nine Track Mind',2016,1),
('4B0JvthVoAAuygILe3n4Bs','What Do You Mean?','Justin Bieber','English','Pop','Purpose (Deluxe)',2015,1),
('4cluDES4hQEUhmXj6TXkSo','What Makes You Beautiful','One Direction','English','Pop','Up All Night',2011,1),
('1XrSjpNe49IiygZfzb74pk','What Once Was','hers','English','Indie Rock','Songs of Her''s',2016,1),
('0gcjc7Vt5xtcfmJgf6g2IO','When You Say Nothing At All','Ronan Keating','English','Rock','10 Years of Hits',1999,1),
('7tI8dRuH2Yc6RuoTjxo4dU','Who','Jimin','English','K-Pop','MUSE',2024,1),
('0eKyHwckh9vQb8ncZ2DXCs','With Arms Wide Open','Creed','English','Hard Rock','Human Clay',1999,1),
('6ADSaE87h8Y3lccZlBJdXH','With Or Without You','U2','English','Rock','U218 Singles (Deluxe Edition)',1987,1),
('6FZDfxM3a3UCqtzo5pxSLZ','Without Me','Halsey & Kelsea Ballerini','English','Alternative / Indie','Manic',2018,2),
('2tO0QPdCA0jgDBshTuYYkc','Woh Ladki','Dua Lipa','Hindi','Unknown','',null,1),
('6zC0mpGYwbNTpk9SKwh08f','Wonderful Tonight','Eric Clapton','English','Rock','Slowhand (35th Anniversary Edition)',1977,1),
('72TFWvU3wUYdUuxejTTIzt','Work','Rihanna','English','Pop','ANTI',2016,1),
('0IOtFlCwTsHdekpZsaK0Ua','World Is Mine','Lane 8, Kasbo, BJOERN','English','Electronic / Dance','World Is Mine',2026,1),
('73R3ZGNODH8sl1oRtdGVl1','y como te digo que','Latin Mafia','Spanish','Latin','Todos los días todo el día',2024,1),
('3afNMElBBtkRPyR79DMyMJ','Yeh Duniya','Anubha Bajaj','Hindi','Unknown','',null,2),
('31ouz9wpEfWhzDWsqCMFRP','Young Blood','The Naked and Famous','English','Alternative / Indie','Young Blood (Tiësto & Hardwell Remix) - Single',2012,1),
('6UfEFq0rTAvaMvwnUyF9ub','Zulfien','Mehul Mahesh, DJ Anik','Hindi/Urdu','Unknown','',null,1)
on conflict (id) do update set title=excluded.title,artist=excluded.artist,language=excluded.language,genre=excluded.genre,
  album=excluded.album,year=excluded.year,popularity=excluded.popularity,updated_at=now();
