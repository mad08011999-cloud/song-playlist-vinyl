# Poojith's Record Shop — song playlist as vinyl

Live: https://mad08011999-cloud.github.io/song-playlist-vinyl/

358 songs from [poojithmalla8/song_playlist](https://github.com/poojithmalla8/song_playlist) (data copied into `data/`, built into `catalog.json` + sleeve art in `art/` and `atlas/` by `scripts/build_catalog.py`).

- **Grid** (default): search, language / type filters, sort, Spotify / Apple Music / YouTube links, embedded Spotify player, More like this.
- **Record store** (3D, three.js): crates by genre family, flip through records, pick one up — the vinyl slides out of its sleeve onto a spinning turntable; drag to turn, flip the sleeve to read the back. Face-out "For you" and "Most saved" shelves. WebGL fallback + always-visible *Back to grid*.
- **Accounts** (Supabase, same project/accounts as the movie site): Liked / Want to listen / Played, named playlists, add your own songs (plain RLS insert — no Edge Function), taste profile.
- **Recommendations**: `song_recommend()` SQL function (artists, genres, languages, decades of liked/wanted/played songs + taste profile; most-saved fallback for new users) and `song_similar()`; on-device scoring if the SQL isn't installed.

Backend setup: run `supabase/songs.sql` once in Supabase → SQL Editor (idempotent). Rebuild data: `python3 scripts/build_catalog.py && python3 scripts/make_sql.py`.
