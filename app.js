// Poojith's Record Shop — grid view, auth, per-user state, playlists, recommendations. 3D store in store3d.js.
const SB_URL="https://mazrqepjgdtdraxpcptk.supabase.co",SB_KEY="sb_publishable_-2do3uyVQ4kcl7PfnBeDpw_mWEc7TXN";
const SITE=location.origin+location.pathname;
const $=s=>document.querySelector(s),$$=s=>[...document.querySelectorAll(s)];
const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const toast=m=>{const t=$("#toast");t.textContent=m;t.classList.add("show");clearTimeout(toast.h);toast.h=setTimeout(()=>t.classList.remove("show"),2200)};
const sb=(window.supabase&&!window.__NO_SB)?window.supabase.createClient(SB_URL,SB_KEY):(window.__MOCK_SB||null);
let user=null;

// ---------- genre families → label colours ----------
const FAM=[["Desi","#d6457a",g=>/bollywood|indian/i.test(g)],["Pop","#e0703a",g=>/^(pop|indie pop|adult contemporary|pop\/rock|children)/i.test(g)],
 ["Indie & Alt","#3f8f8f",g=>/alternative|indie rock|new wave|singer|folk/i.test(g)],["Rock","#b3392f",g=>/rock|metal/i.test(g)],
 ["Electronic","#6b4fbf",g=>/electr|dance|techno/i.test(g)],["Soul, R&B & Hip-Hop","#c9962b",g=>/r&b|soul|hip-hop|rap|jazz/i.test(g)],
 ["World","#2f8f5b",g=>/latin|latino|reggae|j-pop|k-pop/i.test(g)],["Screen & Stage","#3b6fb6",g=>/soundtrack|musical|classical/i.test(g)]];
export function family(s){if(/hindi|urdu|punjabi/i.test(s.l||"")&&!/^(pop|rock|alternative)/i.test(s.g||""))return FAM[0];for(const f of FAM)if(f[2](s.g||""))return f;return["Crate digging","#8a7458"]}
export const labelColor=s=>family(s)[1];
const pgrad=s=>{const c=labelColor(s);let h=0;for(const ch of s.t)h=(h*31+ch.charCodeAt(0))%360;return`linear-gradient(${h}deg,${c},hsl(${h},45%,22%))`};

// ---------- state ----------
let CAT=[],ADDED=[],ALL=[],BYID=new Map();
let ST=JSON.parse(localStorage.getItem("sp_status")||"{}");
let PLAYLISTS=[];   // [{id,name,items:Set}]
let PREFS=null,BACKEND={ok:null,why:""},RECS=null,RECSRC="";
let tab="all",plSel="";
const saveLocal=()=>localStorage.setItem("sp_status",JSON.stringify(ST));
const st=id=>ST[id]||{liked:false,want:false,played:false};
const yr=s=>parseInt(s.y)||0,dec=s=>yr(s)?Math.floor(yr(s)/10)*10:null;
const links=s=>{const q=encodeURIComponent(s.t+" "+s.a);const L=s.link||"";
  return{sp:s.sp||(/spotify\.com/.test(L)?L:"https://open.spotify.com/search/"+q),spd:s.spd||/spotify\.com\/track/.test(L),
    am:s.am||(/music\.apple\.com/.test(L)?L:"https://music.apple.com/us/search?term="+q),
    yt:s.yt||(/youtu/.test(L)?L:"https://www.youtube.com/results?search_query="+q),ytd:s.ytd||/youtu/.test(L)}};
const spId=s=>(s.sp||s.link||"").match(/spotify\.com\/track\/([A-Za-z0-9]{22})/)?.[1]||"";
const fromRow=r=>({id:"u_"+r.id,t:r.title,a:r.artist,l:r.language||"",g:r.genre||"",al:"",y:"",link:r.link||"",p:0,mine:true,n:"Added by you"});
function rebuildAll(){ALL=[...ADDED,...CAT];BYID=new Map(ALL.map(s=>[s.id,s]))}

// ---------- backend helpers ----------
const sync=m=>{const e=$("#syncM");if(e)e.textContent=m};
async function pushStatus(id){const v=st(id);if(!user||!sb)return;
  try{let r;if(!v.liked&&!v.want&&!v.played)r=await sb.from("song_status").delete().eq("user_id",user.id).eq("song_id",id);
   else r=await sb.from("song_status").upsert({user_id:user.id,song_id:id,liked:v.liked,want:v.want,played:v.played,updated_at:new Date().toISOString()},{onConflict:"user_id,song_id"});
   if(r.error)throw r.error;sync("Synced ✓")}catch(e){backendDown(e);sync("Saved on this device (sync failed)")}}
function backendDown(e){if(BACKEND.ok!==false){BACKEND={ok:false,why:e?.message||String(e)};console.warn("Supabase song tables unavailable:",BACKEND.why)}}
async function loadUser(){if(!sb||!user)return;sync("⏳ Loading…");
  try{const[a,b,c,d]=await Promise.all([sb.from("song_status").select("song_id,liked,want,played"),sb.from("song_user_titles").select("id,title,artist,language,genre,link,created_at").order("created_at",{ascending:false}),
      sb.from("song_playlists").select("id,name,created_at,song_playlist_items(song_id)").order("created_at"),sb.from("song_prefs").select("languages,genres,artists").maybeSingle()]);
    for(const r of[a,b,c,d])if(r.error)throw r.error;
    const server={};for(const r of a.data)server[r.song_id]={liked:r.liked,want:r.want,played:r.played};
    const localOnly=Object.keys(ST).filter(k=>!server[k]&&(ST[k].liked||ST[k].want||ST[k].played));
    ST={...ST,...server};saveLocal();for(const k of localOnly)pushStatus(k);
    ADDED=b.data.map(fromRow);rebuildAll();
    PLAYLISTS=c.data.map(p=>({id:p.id,name:p.name,items:new Set((p.song_playlist_items||[]).map(i=>i.song_id))}));
    PREFS=d.data||null;BACKEND={ok:true,why:""};sync("Synced ✓")}
  catch(e){backendDown(e);sync("Backend tables not set up yet — saved on this device")}
  RECS=null;plUI();render();S3?.refresh()}

// ---------- recommendations ----------
function clientRecs(limit=40){const mine=Object.entries(ST).map(([id,v])=>({s:BYID.get(id),v,w:(v.liked?2:0)+(v.want?.8:0)+(v.played?.5:0)})).filter(x=>x.s&&x.w>0);
  const A={},G={},Lg={},D={},add=(M,k,w)=>{if(k!=null&&k!=="")M[k]=(M[k]||0)+w};const cnt={g:{},l:{},d:{}};
  for(const{s,w}of mine){add(A,s.a.toLowerCase(),w);if(s.g&&s.g!=="Unknown"){add(G,s.g,w);add(cnt.g,s.g,1)}if(s.l){add(Lg,s.l,w);add(cnt.l,s.l,1)}if(dec(s)){add(D,dec(s),w);add(cnt.d,dec(s),1)}}
  for(const k in G)G[k]/=Math.sqrt(cnt.g[k]);for(const k in Lg)Lg[k]/=Math.sqrt(cnt.l[k]);for(const k in D)D[k]/=Math.sqrt(cnt.d[k]);
  if(PREFS){(PREFS.artists||[]).forEach(a=>add(A,a.toLowerCase(),1));(PREFS.genres||[]).forEach(g=>add(G,g,1));(PREFS.languages||[]).forEach(l=>add(Lg,l,1))}
  const any=Object.keys(A).length+Object.keys(G).length+Object.keys(Lg).length>0;
  const liked=mine.filter(x=>x.v.liked).map(x=>x.s);
  let sc=ALL.filter(s=>!(st(s.id).liked||st(s.id).played)).map(s=>{const a=A[s.a.toLowerCase()]||0;
    return{s,score:Math.min(a,6)*2+(G[s.g]||0)+(Lg[s.l]||0)*.6+(D[dec(s)]||0)*.3+Math.log(1+s.p)*.25,
      reasons:any?[a>0&&"More "+s.a,G[s.g]>0&&"Genre: "+s.g,Lg[s.l]>0&&s.l!=="English"&&"Language: "+s.l,D[dec(s)]>.9&&dec(s)+"s"].filter(Boolean):["Most saved"]}});
  sc.sort((x,y)=>y.score-x.score||y.s.p-x.s.p);const seen={};
  sc.forEach(x=>{const k=x.s.a.toLowerCase();x.score-=.15*(seen[k]=(seen[k]??-1)+1)});sc.sort((x,y)=>y.score-x.score||y.s.p-x.s.p);
  return sc.slice(0,limit).map(x=>{const b=liked.slice().sort((p,q)=>sim(q,x.s)-sim(p,x.s))[0];return{id:x.s.id,score:x.score,reasons:x.reasons,because_title:any&&b?b.t:null}})}
const sim=(a,b)=>(a.a.toLowerCase()===b.a.toLowerCase()?3:0)+(a.g===b.g&&a.g!=="Unknown"?2:0)+(a.l===b.l?1:0)+(dec(a)&&dec(a)===dec(b)?.5:0);
async function getRecs(){if(RECS)return RECS;
  if(sb&&user&&BACKEND.ok!==false){try{const{data,error}=await sb.rpc("song_recommend",{p_limit:40});if(error)throw error;
      RECS=data.filter(r=>BYID.has(r.id));RECSRC="server";return RECS}catch(e){console.warn("song_recommend unavailable, using on-device scoring",e?.message)}}
  RECS=clientRecs(40);RECSRC="device";return RECS}
async function similar(s,n=12){if(sb&&!s.mine){try{const{data,error}=await sb.rpc("song_similar",{p_id:s.id,p_limit:n});if(error)throw error;if(data.length)return data.map(r=>BYID.get(r.id)).filter(Boolean)}catch(e){}}
  return ALL.filter(x=>x.id!==s.id).map(x=>[x,sim(s,x)+Math.log(1+x.p)*.2]).sort((a,b)=>b[1]-a[1]).slice(0,n).map(x=>x[0])}

// ---------- filtering ----------
export function filtered(){const q=$("#q").value.trim().toLowerCase(),L=$("#fLang").value,T=$("#fType").value,so=$("#sort").value;
  let r=ALL.filter(s=>(!q||(s.t+" "+s.a+" "+s.al).toLowerCase().includes(q))&&(!L||s.l===L)&&(!T||s.g===T));
  if(tab==="liked")r=r.filter(s=>st(s.id).liked);else if(tab==="want")r=r.filter(s=>st(s.id).want);else if(tab==="played")r=r.filter(s=>st(s.id).played);
  else if(tab==="mine")r=r.filter(s=>s.mine);else if(tab==="pl"){const p=PLAYLISTS.find(p=>p.id===plSel);r=r.filter(s=>p?.items.has(s.id))}
  const cmp={pop:(a,b)=>b.p-a.p||a.t.localeCompare(b.t),title:(a,b)=>a.t.localeCompare(b.t),artist:(a,b)=>a.a.localeCompare(b.a)||a.t.localeCompare(b.t),new:(a,b)=>yr(b)-yr(a),old:(a,b)=>(yr(a)||9999)-(yr(b)||9999)}[so];
  return r.sort(cmp)}
const sleeveHTML=s=>s.art?`<img loading="lazy" alt="" src="art/${esc(s.id)}.jpg" onerror="this.replaceWith(Object.assign(document.createElement('div'),{className:'proc',style:'--pg:${pgrad(s)}',innerHTML:'<b>${esc(s.t).replace(/'/g,"&#39;")}</b>'}))">`
  :`<div class="proc" style="--pg:${pgrad(s)}"><b>${esc(s.t)}</b><i>${esc(s.a)}</i></div>`;
function card(s,why){const v=st(s.id);return`<div class="rec" tabindex="0" data-id="${esc(s.id)}" style="--lab:${labelColor(s)}"><div class="wrap"><div class="vinyl"></div><div class="sleeve">${sleeveHTML(s)}</div>
  <div class="badges">${v.liked?"<span>♥</span>":""}${v.want?"<span>🎧</span>":""}${v.played?"<span>✓</span>":""}</div></div>
  <div class="meta"><div class="t">${esc(s.t)}</div><div class="a">${esc(s.a)}</div>${why?`<div class="why">${esc(why)}</div>`:""}<span class="tag">${esc(s.g||"—")}</span>${s.l&&s.l!=="English"?`<span class="tag" style="background:#555">${esc(s.l)}</span>`:""}</div></div>`}
let renderTok=0;
export async function render(){const tok=++renderTok;const g=$("#grid");let list=filtered(),why={};$("#recNote").hidden=true;
  if(tab==="foryou"){const R=await getRecs();if(tok!==renderTok)return;const ids=new Set(list.map(s=>s.id));
    list=R.filter(r=>ids.has(r.id)).map(r=>{why[r.id]=(r.because_title?"Because you liked "+r.because_title+" · ":"")+(r.reasons||[]).join(" · ");return BYID.get(r.id)});
    const n=$("#recNote");n.hidden=false;n.innerHTML=(RECSRC==="server"?"✨ Picked for you by the recommendation engine (Supabase).":"✨ Picked on this device"+(user?" (backend recommender not available yet)":" — sign in to get recommendations from your account"))+
      ` Like, want or play records to tune it. <button class="link" id="tasteBtn">${user?"Edit your taste profile":""}</button>`;const tb=$("#tasteBtn");if(tb&&user)tb.onclick=openPrefs}
  g.innerHTML=list.map(s=>card(s,why[s.id])).join("");$("#empty").hidden=list.length>0;
  $("#count").textContent=`${ALL.length} records · ${CAT.filter(s=>s.spd).length} on Spotify${ADDED.length?` · ${ADDED.length} added by you`:""}`}
$("#grid").onclick=e=>{const r=e.target.closest(".rec");if(r)openDetail(r.dataset.id)};
$("#grid").onkeydown=e=>{if(e.key==="Enter"){const r=e.target.closest(".rec");if(r)openDetail(r.dataset.id)}};

// ---------- status / playlists actions (shared by grid dialog and 3D store) ----------
export function toggle(id,k){const v={...st(id)};v[k]=!v[k];if(k==="played"&&v.played)v.want=false;ST[id]=v;if(!v.liked&&!v.want&&!v.played)delete ST[id];saveLocal();RECS=null;pushStatus(id);
  toast({liked:v.liked?"♥ Liked":"Unliked",want:v.want?"🎧 Added to Want to listen":"Removed from Want to listen",played:v.played?"✓ Marked played":"Unmarked played"}[k]);
  updateCard(id);S3?.statusChanged(id);return v}
function updateCard(id){const el=$(`#grid .rec[data-id="${CSS.escape(id)}"]`),s=BYID.get(id);if(el&&s){const t=document.createElement("div");t.innerHTML=card(s,el.querySelector(".why")?.textContent);el.replaceWith(t.firstChild)}}
async function addToPlaylist(id,plId){if(!user)return openAuth();const p=PLAYLISTS.find(p=>p.id===plId);if(!p)return;
  if(p.items.has(id)){const{error}=await sb.from("song_playlist_items").delete().eq("playlist_id",plId).eq("song_id",id);if(error)return toast("Couldn't update playlist");p.items.delete(id);toast("Removed from "+p.name)}
  else{const{error}=await sb.from("song_playlist_items").insert({playlist_id:plId,song_id:id});if(error){backendDown(error);return toast("Couldn't add — playlists need the backend set up")}p.items.add(id);toast("Added to "+p.name)}}
async function newPlaylist(id){if(!user)return openAuth();const name=(prompt("New playlist name")||"").trim().slice(0,60);if(!name)return;
  const{data,error}=await sb.from("song_playlists").insert({user_id:user.id,name}).select("id,name").single();
  if(error){backendDown(error);return toast(/duplicate/.test(error.message)?"You already have a playlist with that name":"Couldn't create playlist")}
  PLAYLISTS.push({id:data.id,name:data.name,items:new Set()});plUI();if(id)await addToPlaylist(id,data.id)}
function plUI(){const s=$("#plSel");s.innerHTML=`<option value="">🎶 Playlists…</option>`+PLAYLISTS.map(p=>`<option value="${p.id}" ${p.id===plSel?"selected":""}>${esc(p.name)} (${p.items.size})</option>`).join("")+`<option value="__new">＋ New playlist…</option>`}
$("#plSel").onchange=async e=>{const v=e.target.value;if(v==="__new"){e.target.value=plSel;await newPlaylist();return}plSel=v;setTab(v?"pl":"all")};
export function actionsHTML(s){const v=st(s.id),L=links(s);return`<div class="acts"><button class="btn ${v.liked?"on":""}" data-act="liked">♥ ${v.liked?"Liked":"Like"}</button><button class="btn ${v.want?"on":""}" data-act="want">🎧 Want to listen</button><button class="btn ${v.played?"on":""}" data-act="played">✓ Played</button></div>
  <div class="plays"><a class="sp" target="_blank" rel="noopener" href="${esc(L.sp)}">Spotify${L.spd?"":" (search)"}</a><a class="am" target="_blank" rel="noopener" href="${esc(L.am)}">Apple Music${s.am?"":" (search)"}</a><a class="yt" target="_blank" rel="noopener" href="${esc(L.yt)}">YouTube${L.ytd?"":" (search)"}</a></div>
  <div class="plmenu"><b style="font-size:.85rem">Add to playlist:</b>${user?PLAYLISTS.map(p=>`<button class="btn ${p.items.has(s.id)?"on":""}" data-pl="${p.id}">${p.items.has(s.id)?"✓ ":""}${esc(p.name)}</button>`).join(""):""}<button class="btn" data-pl="__new">＋ New playlist…</button></div>`}
export function wireActions(root,s,rerender){root.querySelectorAll("[data-act]").forEach(b=>b.onclick=()=>{toggle(s.id,b.dataset.act);rerender()});
  root.querySelectorAll("[data-pl]").forEach(b=>b.onclick=async()=>{b.dataset.pl==="__new"?await newPlaylist(s.id):await addToPlaylist(s.id,b.dataset.pl);plUI();rerender()})}
export function detailsKV(s){return`<div class="kv">${s.al?`<b>Album:</b> ${esc(s.al)}<br>`:""}${s.y?`<b>Year:</b> ${esc(s.y)} · `:""}<b>Language:</b> ${esc(s.l||"—")} · <b>Type:</b> ${esc(s.g||"—")}<br>${s.p?`<b>Saved in</b> ${s.p} post${s.p>1?"s":""}`:""}${s.n?` · <i>${esc(s.n)}</i>`:""}</div>`}

// ---------- detail dialog ----------
async function openDetail(id){const s=BYID.get(id);if(!s)return;const d=$("#dlg"),b=$("#dlgBody"),sid=spId(s);
  const draw=()=>{b.innerHTML=`<div class="det" style="--lab:${labelColor(s)}"><div><div class="art"><div class="vinyl"></div><div class="sleeve">${sleeveHTML(s)}</div></div></div>
   <div><h2>${esc(s.t)}</h2><div class="by">${esc(s.a)}</div><span class="tag">${esc(family(s)[0])}</span>${detailsKV(s)}${actionsHTML(s)}
   ${sid?`<iframe style="border-radius:12px;margin-top:10px" src="https://open.spotify.com/embed/track/${sid}?utm_source=generator&theme=0" width="100%" height="80" frameborder="0" allow="autoplay; clipboard-write; encrypted-media; fullscreen; picture-in-picture" loading="lazy"></iframe>`:""}</div></div>
   <h3 style="margin:16px 0 8px">More like this</h3><div class="mlt" id="mlt"><span class="hint">Finding similar records…</span></div>`;wireActions(b,s,draw);fillMLT()};
  const fillMLT=async()=>{const m=await similar(s,12);const el=$("#mlt");if(!el)return;el.innerHTML=m.map(x=>card(x)).join("");el.onclick=e=>{const r=e.target.closest(".rec");if(r)openDetail(r.dataset.id)}};
  draw();if(!d.open)d.showModal();d.scrollTop=0}
export const openDetailFn=openDetail;
document.addEventListener("click",e=>{if(e.target.matches("[data-close]"))e.target.closest("dialog").close()});

// ---------- tabs / filters ----------
function setTab(t){tab=t;$$("#tabs [data-t]").forEach(b=>b.classList.toggle("on",b.dataset.t===t));if(t!=="pl"){plSel="";$("#plSel").value=""}render();S3?.refresh()}
$("#tabs").onclick=e=>{const b=e.target.closest("[data-t]");if(b)setTab(b.dataset.t)};
let deb;for(const el of["#q","#fLang","#fType","#sort"])$(el).addEventListener("input",()=>{clearTimeout(deb);deb=setTimeout(()=>{render();S3?.refresh()},150)});
$("#spot").addEventListener("toggle",e=>{const f=$("#spot iframe");if(e.target.open&&!f.src)f.src=f.dataset.src});

// ---------- auth ----------
let mode="in";const emOk=e=>/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e);
const show=(el,m,ok)=>{el.hidden=false;el.textContent=m;el.classList.toggle("ok",!!ok)};
const friendly=e=>{const m=e?.message||String(e);if(/invalid login/i.test(m))return"Wrong email or password.";if(/already registered/i.test(m))return"That email already has an account — sign in instead.";if(/not confirmed/i.test(m))return"Please confirm your email first (check your inbox).";if(/rate|security purposes/i.test(m))return"Too many attempts — wait a minute and try again.";return m};
function setMode(m){mode=m;$$("#auth .seg button").forEach(b=>b.classList.toggle("on",b.dataset.m===m));$("#aSub").textContent=m==="in"?"Sign in":"Create account";$("#aPw").autocomplete=m==="in"?"current-password":"new-password";$("#auth h2").textContent=m==="in"?"Sign in":"Create account"}
export function openAuth(rec){if(!sb)return toast("Sign-in is unavailable right now");$("#msg").hidden=true;$("#aForm").hidden=!!rec;$("#aRec").hidden=!rec;$(".seg").hidden=!!rec;$("#auth .row").hidden=!!rec;if(rec)$("#auth h2").textContent="Set a new password";$("#auth").showModal()}
if(sb){$$("#auth .seg button").forEach(b=>b.onclick=()=>setMode(b.dataset.m));
 $("#aForm").onsubmit=async e=>{e.preventDefault();$("#msg").hidden=true;const em=$("#aEm").value.trim(),pw=$("#aPw").value;let bad=false;$("#eEm").textContent=$("#ePw").textContent="";
  if(!emOk(em)){$("#eEm").textContent="Enter a valid email address.";bad=true}if(pw.length<6){$("#ePw").textContent=pw?"Password must be at least 6 characters.":"Enter your password.";bad=true}if(bad)return;
  const b=$("#aSub");b.disabled=true;try{if(mode==="in"){const{error}=await sb.auth.signInWithPassword({email:em,password:pw});if(error)throw error;$("#auth").close();toast("Signed in ✓")}
   else{const{data,error}=await sb.auth.signUp({email:em,password:pw,options:{emailRedirectTo:SITE}});if(error)throw error;if(data.user?.identities?.length===0)throw new Error("already registered");
    if(data.session){$("#auth").close();toast("Account created ✓")}else show($("#msg"),"Almost there! Check your inbox to confirm your email, then sign in.",true)}}catch(x){show($("#msg"),friendly(x))}b.disabled=false};
 $("#forgot").onclick=async()=>{const em=$("#aEm").value.trim();if(!emOk(em))return $("#eEm").textContent="Enter your email above first.";const{error}=await sb.auth.resetPasswordForEmail(em,{redirectTo:SITE});error?show($("#msg"),friendly(error)):show($("#msg"),"Password reset link sent — check your email.",true)};
 $("#magic").onclick=async()=>{const em=$("#aEm").value.trim();if(!emOk(em))return $("#eEm").textContent="Enter your email above first.";const{error}=await sb.auth.signInWithOtp({email:em,options:{emailRedirectTo:SITE}});error?show($("#msg"),friendly(error)):show($("#msg"),"Sign-in link sent — check your email.",true)};
 $("#aRec").onsubmit=async e=>{e.preventDefault();const pw=$("#nPw").value;if(pw.length<6)return $("#eN").textContent="At least 6 characters.";const{error}=await sb.auth.updateUser({password:pw});error?show($("#msg"),friendly(error)):($("#auth").close(),toast("Password updated ✓"))};
 document.addEventListener("click",e=>{if(!e.target.closest(".acct"))$("#acctMenu")?.classList.remove("open")})}
function authUI(){const b=$("#authBox");if(!sb){b.innerHTML="";return}
  if(user){const ini=esc((user.email||"?")[0].toUpperCase());b.innerHTML=`<button class="btn acc" id="addBtn">＋ Add a song</button><div class="acct"><button class="btn" id="acctBtn"><span class="av">${ini}</span> ▾</button>
   <div class="menu" id="acctMenu"><span>${esc(user.email)}</span><p class="hint" id="syncM">Synced</p><button class="btn wide" id="prefBtn">🎚 Your taste profile</button><button class="btn wide" id="out">Sign out</button></div></div>`;
   $("#addBtn").onclick=openAdd;$("#acctBtn").onclick=()=>$("#acctMenu").classList.toggle("open");$("#prefBtn").onclick=openPrefs;$("#out").onclick=async()=>{await sb.auth.signOut();toast("Signed out")}}
  else{b.innerHTML=`<button class="btn" id="addBtn">＋ Add a song</button><button class="btn acc" id="in">Sign in</button>`;$("#in").onclick=()=>openAuth();$("#addBtn").onclick=()=>{toast("Sign in to add songs");openAuth()}}}

// ---------- add a song (plain RLS insert, no Edge Function) ----------
function openAdd(){if(!user)return openAuth();$("#addForm").reset();$("#adErr").textContent="";$("#addDlg").showModal()}
$("#addForm").onsubmit=async e=>{e.preventDefault();const t=$("#adT").value.trim(),a=$("#adA").value.trim(),l=$("#adL").value.trim(),g=$("#adG").value.trim(),u=$("#adU").value.trim();
  if(!t||!a)return $("#adErr").textContent="Song title and artist are required.";if(u&&!/^https:\/\/\S+$/i.test(u))return $("#adErr").textContent="Link must start with https://";
  const dup=ALL.find(s=>s.t.toLowerCase()===t.toLowerCase()&&s.a.toLowerCase()===a.toLowerCase());if(dup){$("#addDlg").close();toast("Already in the shop!");return openDetail(dup.id)}
  const btn=$("#adSub");btn.disabled=true;try{const{data,error}=await sb.from("song_user_titles").insert({user_id:user.id,title:t,artist:a,language:l||null,genre:g||null,link:u||null}).select("id,title,artist,language,genre,link,created_at").single();
    if(error)throw error;const s=fromRow(data);ADDED.unshift(s);rebuildAll();RECS=null;$("#addDlg").close();toast("Added “"+t+"” to your crate ✓");render();S3?.refresh()}
  catch(x){backendDown(x);$("#adErr").textContent=/relation|schema cache|does not exist/i.test(x.message||"")?"The song tables aren't set up in Supabase yet (run supabase/songs.sql).":friendly(x)}btn.disabled=false};

// ---------- taste profile ----------
function openPrefs(){if(!user)return openAuth();const P=PREFS||{languages:[],genres:[],artists:[]};
  const langs=[...new Set(CAT.map(s=>s.l))].sort(),gens=[...new Set(CAT.map(s=>s.g).filter(g=>g&&g!=="Unknown"))].sort();
  $("#pLang").innerHTML=langs.map(l=>`<button class="${P.languages.includes(l)?"on":""}" data-v="${esc(l)}">${esc(l)}</button>`).join("");
  $("#pGen").innerHTML=gens.map(l=>`<button class="${P.genres.includes(l)?"on":""}" data-v="${esc(l)}">${esc(l)}</button>`).join("");
  $("#pArt").value=(P.artists||[]).join(", ");$("#prefDlg").showModal()}
$("#prefDlg").addEventListener("click",e=>{if(e.target.matches(".chips button"))e.target.classList.toggle("on")});
$("#pSave").onclick=async()=>{const p={languages:$$("#pLang .on").map(b=>b.dataset.v),genres:$$("#pGen .on").map(b=>b.dataset.v),artists:$("#pArt").value.split(",").map(s=>s.trim()).filter(Boolean).slice(0,40)};
  const{error}=await sb.from("song_prefs").upsert({user_id:user.id,...p,updated_at:new Date().toISOString()},{onConflict:"user_id"});
  if(error){backendDown(error);toast("Couldn't save — backend not set up yet");PREFS=p}else{PREFS=p;toast("Taste saved ✓")}RECS=null;$("#prefDlg").close();if(tab==="foryou")render()};

// ---------- 3D store ----------
let S3=null,S3load=null;
const api={get all(){return ALL},filtered,st,toggle,labelColor,family,actionsHTML,wireActions,detailsKV,links,spId,getRecs,similar,openDetail};
async function setView(v){$$(".vbtn").forEach(b=>b.classList.toggle("on",b.dataset.v===v));const store=v==="store";
  $("#storeView").hidden=!store;document.body.style.overflow=store?"hidden":"";if(location.hash!==(store?"#store":"")&&!(location.hash===""&&!store))history.replaceState(null,"",store?"#store":location.pathname);
  if(store){if(!S3){try{S3load=S3load||import("./store3d.js");const m=await S3load;S3=await m.mount($("#c3"),api);window.S3=S3}catch(e){console.error(e);$("#glFail").hidden=false;$("#hud").hidden=$("#pad").hidden=true}}else S3.resume()}else S3?.pause()}
$$(".vbtn").forEach(b=>b.onclick=()=>setView(b.dataset.v));$("#backGrid").onclick=$("#glBack").onclick=()=>setView("grid");
document.addEventListener("keydown",e=>{if(e.key==="Escape"&&!$("#storeView").hidden&&!document.querySelector("dialog[open]"))S3?.escape()||setView("grid")});

// ---------- boot ----------
(async()=>{CAT=await (await fetch("catalog.json")).json();rebuildAll();
  const langs=[...new Set(CAT.map(s=>s.l))].sort(),types=[...new Set(CAT.map(s=>s.g))].sort();
  $("#fLang").insertAdjacentHTML("beforeend",langs.map(l=>`<option>${esc(l)}</option>`).join(""));$("#fType").insertAdjacentHTML("beforeend",types.map(l=>`<option>${esc(l)}</option>`).join(""));
  $("#langList").innerHTML=langs.map(l=>`<option value="${esc(l)}">`).join("");$("#typeList").innerHTML=types.filter(t=>t!=="Unknown").map(l=>`<option value="${esc(l)}">`).join("");
  plUI();authUI();render();
  if(sb){sb.auth.onAuthStateChange((ev,s)=>{const nu=s?.user||null,ch=nu?.id!==user?.id;user=nu;RECS=null;if(ch){PLAYLISTS=[];ADDED=[];PREFS=null;rebuildAll();authUI();plUI();render();S3?.refresh();if(nu)setTimeout(loadUser,0)}
    if(ev==="PASSWORD_RECOVERY")setTimeout(()=>openAuth(true),0)})}
  if(location.hash==="#store")setView("store");addEventListener("hashchange",()=>setView(location.hash==="#store"?"store":"grid"))})();
window.__app={api,setTab,openDetail,openAdd,openPrefs,openAuth,get user(){return user},get backend(){return BACKEND},get recsrc(){return RECSRC}};
