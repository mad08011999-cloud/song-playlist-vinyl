import json,os
R=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
C=json.load(open(R+'/catalog.json'))
q=lambda s:"'"+str(s).replace("'","''")+"'"
head=open(R+'/scripts/songs_schema.sql').read()
rows=",\n".join(f"({q(c['id'])},{q(c['t'])},{q(c['a'])},{q(c['l'])},{q(c['g'])},{q(c['al'])},{c['y'] or 'null'},{c['p']})" for c in C)
seed=f"""
-- ---------- seed: the {len(C)} catalog songs (re-runnable) ----------
insert into public.song_catalog (id,title,artist,language,genre,album,year,popularity) values
{rows}
on conflict (id) do update set title=excluded.title,artist=excluded.artist,language=excluded.language,genre=excluded.genre,
  album=excluded.album,year=excluded.year,popularity=excluded.popularity,updated_at=now();
"""
open(R+'/supabase/songs.sql','w').write(head+seed);open('/workspace/songs.sql','w').write(head+seed);print('ok')
