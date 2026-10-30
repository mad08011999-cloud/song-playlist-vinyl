# Builds catalog.json (compact) + atlas/art-N.jpg (sleeve art textures) from data/songs-*.json
import json,glob,hashlib,io,os,sys,urllib.request
R=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S=[s for f in sorted(glob.glob(R+'/data/songs-*.json')) for s in json.load(open(f))]
out=[]
for s in S:
    sid=s['spotify_track_id'] or 'x'+hashlib.md5((s['title']+'|'+s['artist']).lower().encode()).hexdigest()[:12]
    out.append(dict(id=sid,t=s['title'],a=s['artist'],l=s['language'],g=s['type'],al=s['album'] or '',y=s['release_year'] or '',
      sp=s['spotify_url'],spd=s['spotify_url_type']=='direct',am=s['apple_music_url'] or '',yt=s['youtube_url'],ytd=s['youtube_url_type']=='direct',
      art=s['artwork_url'] or '',n=s['notes'] or '',p=len(s['source_posts']),col=s['source_collections'],v=s['verification']))
assert len({o['id'] for o in out})==len(out)
# atlas: 16x16 tiles of 128px per 2048 jpg
try:
    from PIL import Image
    T,N=128,16;atl={};imgs=[]
    for o in [o for o in out if o['art']]:
        cache=R+'/scripts/.artcache/'+o['id']+'.jpg';os.makedirs(os.path.dirname(cache),exist_ok=True)
        if not os.path.exists(cache):
            try:open(cache,'wb').write(urllib.request.urlopen(o['art'],timeout=20).read())
            except Exception as e:print('art fail',o['t'],e);continue
        imgs.append((o,cache))
    for i,(o,c) in enumerate(imgs):
        k=i//(N*N)
        if k not in atl:atl[k]=Image.new('RGB',(T*N,T*N),(30,20,15))
        try:atl[k].paste(Image.open(c).convert('RGB').resize((T,T)),((i%N)*T,((i//N)%N)*T))
        except Exception as e:print('bad',c,e);continue
        o['ax']=[k,i%(N*N)]
    for k,im in atl.items():im.save(R+f'/atlas/art-{k}.jpg',quality=85)
except ImportError:print('no pillow; skipping atlas')
json.dump(out,open(R+'/catalog.json','w'),ensure_ascii=False,separators=(',',':'))
print(len(out),'songs')
