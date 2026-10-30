// Walk-in 3D record store (three.js). Crates of vinyl by genre family, face-out wall shelves, pick-up turntable view.
import * as THREE from "https://cdn.jsdelivr.net/npm/three@0.160.1/build/three.module.min.js";
const $=s=>document.querySelector(s);
const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const PER_CRATE=24,SW=0.31,ST=0.006;

function cv(w,h,fn){const c=document.createElement("canvas");c.width=w;c.height=h;fn(c.getContext("2d"),w,h);const t=new THREE.CanvasTexture(c);t.colorSpace=THREE.SRGBColorSpace;t.anisotropy=4;return t}
function wrapText(g,text,x,y,maxW,lh,maxLines=3){const words=String(text).split(/\s+/);let line="",n=0;for(const w of words){const t=line?line+" "+w:w;if(g.measureText(t).width>maxW&&line){g.fillText(line,x,y);y+=lh;line=w;if(++n>=maxLines-1){line=(line+" "+words.slice(words.indexOf(w)+1).join(" ")).trim();if(g.measureText(line).width>maxW){while(line&&g.measureText(line+"…").width>maxW)line=line.slice(0,-1);line+="…"}break}}else line=t}g.fillText(line,x,y);return y+lh}
const hash=s=>{let h=0;for(const c of s)h=(h*31+c.charCodeAt(0))>>>0;return h};

export async function mount(canvas,api){
  const gl=canvas.getContext("webgl2")||canvas.getContext("webgl");if(!gl)throw new Error("no webgl");
  const R=new THREE.WebGLRenderer({canvas,antialias:true,context:gl});R.setPixelRatio(Math.min(devicePixelRatio,2));R.outputColorSpace=THREE.SRGBColorSpace;
  R.toneMapping=THREE.ACESFilmicToneMapping;R.toneMappingExposure=1.15;
  const scene=new THREE.Scene();scene.background=new THREE.Color(0x1a110b);scene.fog=new THREE.Fog(0x1a110b,10,26);
  const cam=new THREE.PerspectiveCamera(62,1,.05,60);
  // ---------- room ----------
  const W=14,D=16,H=3.6;
  const wood=cv(512,512,(g,w,h)=>{for(let i=0;i<8;i++){const y=i*h/8;g.fillStyle=`hsl(${24+(i*7)%10},${40+(i*13)%15}%,${22+(i*5)%9}%)`;g.fillRect(0,y,w,h/8);g.strokeStyle="rgba(0,0,0,.35)";g.lineWidth=3;g.strokeRect(-2,y,w+4,h/8);
    for(let k=0;k<40;k++){g.strokeStyle=`rgba(0,0,0,${.05+Math.random()*.08})`;g.lineWidth=1;g.beginPath();const yy=y+Math.random()*h/8;g.moveTo(0,yy);g.bezierCurveTo(w/3,yy+6*Math.random(),2*w/3,yy-6*Math.random(),w,yy);g.stroke()}}});
  wood.wrapS=wood.wrapT=THREE.RepeatWrapping;wood.repeat.set(5,6);
  const floor=new THREE.Mesh(new THREE.PlaneGeometry(W,D),new THREE.MeshStandardMaterial({map:wood,roughness:.8}));floor.rotation.x=-Math.PI/2;scene.add(floor);
  const wall=cv(512,512,(g,w,h)=>{g.fillStyle="#6b3a22";g.fillRect(0,0,w,h);for(let y=0;y<h;y+=32)for(let x=(y/32)%2*32;x<w;x+=64){g.fillStyle=`hsl(${14+Math.random()*8},45%,${26+Math.random()*8}%)`;g.fillRect(x+2,y+2,60,28)}});
  wall.wrapS=wall.wrapT=THREE.RepeatWrapping;wall.repeat.set(4,1.5);const wm=new THREE.MeshStandardMaterial({map:wall,roughness:.95});
  const mkWall=(w,x,z,ry)=>{const m=new THREE.Mesh(new THREE.PlaneGeometry(w,H),wm);m.position.set(x,H/2,z);m.rotation.y=ry;scene.add(m)};
  mkWall(W,0,-D/2,0);mkWall(W,0,D/2,Math.PI);mkWall(D,-W/2,0,Math.PI/2);mkWall(D,W/2,0,-Math.PI/2);
  const ceil=new THREE.Mesh(new THREE.PlaneGeometry(W,D),new THREE.MeshStandardMaterial({color:0x22160f}));ceil.rotation.x=Math.PI/2;ceil.position.y=H;scene.add(ceil);
  scene.add(new THREE.HemisphereLight(0xffe2c0,0x2a1a10,.85));
  for(const[x,z]of[[-3.5,-4],[0,-4],[3.5,-4],[-3.5,0],[0,0],[3.5,0],[-3.5,4],[0,4],[3.5,4]]){const p=new THREE.PointLight(0xffc98a,6,9,1.6);p.position.set(x,H-.5,z);scene.add(p);
    const shade=new THREE.Mesh(new THREE.ConeGeometry(.28,.25,20,1,true),new THREE.MeshStandardMaterial({color:0x2d5a3d,side:THREE.DoubleSide,emissive:0x221100}));shade.position.set(x,H-.38,z);scene.add(shade);
    const bulb=new THREE.Mesh(new THREE.SphereGeometry(.07),new THREE.MeshBasicMaterial({color:0xffe0a0}));bulb.position.set(x,H-.5,z);scene.add(bulb)}
  // neon sign
  const neon=new THREE.Mesh(new THREE.PlaneGeometry(4.2,.9),new THREE.MeshBasicMaterial({transparent:true,map:cv(1024,220,(g,w,h)=>{g.font="bold 120px Fraunces, Georgia, serif";g.textAlign="center";g.shadowColor="#ff7b3a";g.shadowBlur=30;g.fillStyle="#ffd2a0";g.fillText("RECORD SHOP",w/2,150)})}));
  neon.position.set(0,H-.75,-D/2+.02);scene.add(neon);
  // ---------- textures ----------
  const atlas={},loader=new THREE.TextureLoader();
  const atlasTex=k=>atlas[k]||(atlas[k]=loader.load(`atlas/art-${k}.jpg`,t=>{t.colorSpace=THREE.SRGBColorSpace}));
  const sideMat=new THREE.MeshStandardMaterial({color:0xd9c7a4,roughness:.9}),kraft=new THREE.MeshStandardMaterial({color:0xc8a878,roughness:.95});
  const texCache=new Map();
  function sleeveTex(s){if(texCache.has(s.id))return texCache.get(s.id);let t;
    if(s.ax){t=atlasTex(s.ax[0]).clone();t.colorSpace=THREE.SRGBColorSpace;t.repeat.set(1/16,1/16);t.offset.set((s.ax[1]%16)/16,1-(Math.floor(s.ax[1]/16)+1)/16);t.needsUpdate=true}
    else{const c=api.labelColor(s),h=hash(s.t)%360;t=cv(256,256,(g,w,hh)=>{const gr=g.createLinearGradient(0,0,w,hh);gr.addColorStop(0,c);gr.addColorStop(1,`hsl(${h},45%,18%)`);g.fillStyle=gr;g.fillRect(0,0,w,hh);
      g.globalAlpha=.25;g.strokeStyle="#fff";g.lineWidth=2;for(let r=30;r<200;r+=14){g.beginPath();g.arc(w*.8,hh*.2,r,0,7);g.stroke()}g.globalAlpha=1;
      g.fillStyle="#fff";g.font="bold 30px Fraunces, Georgia, serif";const y=wrapText(g,s.t,16,150,224,32,3);g.font="18px DM Sans, sans-serif";g.globalAlpha=.85;wrapText(g,s.a,16,Math.min(y,232),224,20,1)})}
    texCache.set(s.id,t);return t}
  const sleeveGeo=new THREE.BoxGeometry(SW,SW,ST);sleeveGeo.translate(0,SW/2,0);
  function sleeveMesh(s){const front=new THREE.MeshStandardMaterial({map:sleeveTex(s),roughness:.55});const m=new THREE.Mesh(sleeveGeo,[sideMat,sideMat,sideMat,sideMat,front,kraft]);m.userData.song=s;return m}
  const crateWood=new THREE.MeshStandardMaterial({color:0x8a5a33,roughness:.85}),tableMat=new THREE.MeshStandardMaterial({color:0x3b2416,roughness:.7});
  function crateBox(){const g=new THREE.Group(),w=.4,d=.62,h=.2,t=.02;const add=(sx,sy,sz,x,y,z)=>{const m=new THREE.Mesh(new THREE.BoxGeometry(sx,sy,sz),crateWood);m.position.set(x,y,z);g.add(m)};
    add(w,t,d,0,t/2,0);add(t,h,d,-w/2,h/2,0);add(t,h,d,w/2,h/2,0);add(w,h*.6,t,0,h*.3,d/2);add(w,h,t,0,h/2,-d/2);return g}
  function signTex(title,sub,color){return cv(512,160,(g,w,h)=>{g.fillStyle="#f3e6cf";g.fillRect(0,0,w,h);g.fillStyle=color;g.fillRect(0,0,w,26);g.fillStyle="#2a1d14";g.font="bold 54px Fraunces, Georgia, serif";g.textAlign="center";g.fillText(title,w/2,90,w-20);g.font="30px DM Sans, sans-serif";g.fillText(sub,w/2,136,w-20)})}
  // ---------- store contents (rebuilt on filter change) ----------
  let content=new THREE.Group();scene.add(content);let crates=[],clickables=[],shelfItems=[];
  function build(){scene.remove(content);content.traverse(o=>{if(o.geometry&&o.geometry!==sleeveGeo)o.geometry.dispose();if(o.material&&!Array.isArray(o.material)&&o.material.map&&o.userData.own)o.material.map.dispose()});
    content=new THREE.Group();scene.add(content);crates=[];clickables=[];
    const list=api.filtered(),fams=new Map();for(const s of list){const f=api.family(s);if(!fams.has(f[0]))fams.set(f[0],{name:f[0],color:f[1],songs:[]});fams.get(f[0]).songs.push(s)}
    const groups=[];for(const f of[...fams.values()].sort((a,b)=>b.songs.length-a.songs.length)){const ss=f.songs.slice().sort((a,b)=>a.a.localeCompare(b.a));const nC=Math.ceil(ss.length/PER_CRATE),per=Math.ceil(ss.length/nC);for(let i=0;i<ss.length;i+=per){const ch=ss.slice(i,i+per);groups.push({...f,songs:ch,range:ch[0].a[0].toUpperCase()+"–"+ch[ch.length-1].a[0].toUpperCase()})}}
    // tables: rows along x, 4 crates per table, tables in a 2-column x 4-row grid
    const slots=[];for(let r=0;r<5;r++)for(const tx of[-3.2,3.2])for(let k=0;k<4;k++)slots.push({x:tx+(k-1.5)*.48,z:-4.6+r*2.4,table:r*2+(tx>0?1:0)});
    const usedTables=new Set();
    groups.slice(0,slots.length).forEach((gp,i)=>{const sl=slots[i];usedTables.add(sl.table);const cg=new THREE.Group();cg.position.set(sl.x,.78,sl.z);content.add(cg);cg.add(crateBox());
      const recs=gp.songs.map((s,j)=>{const m=sleeveMesh(s);m.position.set(0,.022,.27-j*(.54/PER_CRATE));m.rotation.x=-.18;cg.add(m);clickables.push(m);m.userData.crate=crates.length;m.userData.idx=j;return m});
      const sign=new THREE.Mesh(new THREE.PlaneGeometry(.44,.14),new THREE.MeshBasicMaterial({map:signTex(gp.name,gp.range+" · "+gp.songs.length,gp.color)}));sign.position.set(0,.5,-.31);sign.material.userData=1;cg.add(sign);
      const post=new THREE.Mesh(new THREE.BoxGeometry(.015,.42,.015),crateWood);post.position.set(0,.22,-.315);cg.add(post);
      crates.push({group:cg,recs,cur:0,name:gp.name,range:gp.range,color:gp.color})});
    for(const t of usedTables){const r=Math.floor(t/2),tx=t%2?3.2:-3.2;const top=new THREE.Mesh(new THREE.BoxGeometry(2.1,.06,.8),tableMat);top.position.set(tx,.75,-4.6+r*2.4);content.add(top);
      for(const dx of[-1,1])for(const dz of[-1,1]){const l=new THREE.Mesh(new THREE.BoxGeometry(.06,.72,.06),tableMat);l.position.set(tx+dx*.98,.36,-4.6+r*2.4+dz*.34);content.add(l)}}
    if(groups.length>slots.length)console.warn("more crates than slots");
    crates.forEach(layoutCrate);buildShelves()}
  function layoutCrate(c){c.recs.forEach((m,j)=>{m.userData.tx=j<c.cur?.62:-.18-(j-c.cur)*.004;m.userData.ty=j===c.cur&&focus===c?.05:.022})}
  // face-out wall shelves: For you (back wall) and Most saved (left wall)
  async function buildShelves(){const recs=(await api.getRecs()).slice(0,14).map(r=>api.all.find(s=>s.id===r.id)).filter(Boolean);
    const top=api.all.slice().sort((a,b)=>b.p-a.p).slice(0,14);
    const shelf=(songs,title,place)=>{const g=new THREE.Group();place(g);content.add(g);
      for(let row=0;row<2;row++){const b=new THREE.Mesh(new THREE.BoxGeometry(4.4,.04,.22),tableMat);b.position.set(0,1.1+row*.62,.11);g.add(b)}
      const sg=new THREE.Mesh(new THREE.PlaneGeometry(1.6,.5),new THREE.MeshBasicMaterial({map:signTex(title,"face-out picks","#e9b44c")}));sg.position.set(0,2.65,.02);g.add(sg);
      songs.forEach((s,i)=>{const m=sleeveMesh(s);m.position.set(-1.95+(i%7)*.65,1.12+Math.floor(i/7)*.62,.12);m.rotation.x=-.12;g.add(m);clickables.push(m);m.userData.shelf=true})};
    shelf(recs,"For you",g=>g.position.set(0,0,-D/2+.01));
    shelf(top,"Most saved",g=>{g.position.set(-W/2+.01,0,-2);g.rotation.y=Math.PI/2})}
  // counter with a spinning turntable (ambient)
  const counter=new THREE.Group();counter.position.set(0,0,D/2-1.6);scene.add(counter);
  const ctop=new THREE.Mesh(new THREE.BoxGeometry(3,1,.8),tableMat);ctop.position.y=.5;counter.add(ctop);
  // ---------- vinyl + turntable ----------
  const grooves=cv(1024,1024,(g,w)=>{const c=w/2;g.fillStyle="#0b0b0b";g.fillRect(0,0,w,w);for(let r=c*.36;r<c*.99;r+=1.6){g.strokeStyle=`rgba(${40+Math.random()*30},${40+Math.random()*30},${40+Math.random()*30},${.5+Math.random()*.5})`;g.lineWidth=.8;g.beginPath();g.arc(c,c,r,0,7);g.stroke()}
    for(const r of[.55,.72,.86]){g.strokeStyle="#050505";g.lineWidth=5;g.beginPath();g.arc(c,c,c*r,0,7);g.stroke()}
    const sh=g.createConicGradient?g.createConicGradient(.6,c,c):null;if(sh){sh.addColorStop(0,"rgba(255,255,255,0)");sh.addColorStop(.08,"rgba(255,240,220,.16)");sh.addColorStop(.16,"rgba(255,255,255,0)");sh.addColorStop(.5,"rgba(255,255,255,0)");sh.addColorStop(.58,"rgba(255,240,220,.12)");sh.addColorStop(.66,"rgba(255,255,255,0)");g.fillStyle=sh;g.beginPath();g.arc(c,c,c*.99,0,7);g.fill()}});
  function labelTex(s){return cv(512,512,(g,w)=>{const c=w/2;g.fillStyle=api.labelColor(s);g.beginPath();g.arc(c,c,c,0,7);g.fill();g.strokeStyle="rgba(255,255,255,.35)";g.lineWidth=4;g.beginPath();g.arc(c,c,c*.92,0,7);g.stroke();
    g.fillStyle="#fff";g.textAlign="center";g.font="bold 44px Fraunces, Georgia, serif";wrapText(g,s.t,c,150,380,46,2);g.font="30px DM Sans, sans-serif";g.fillText(s.a,c,370,380);g.font="22px DM Sans, sans-serif";g.globalAlpha=.8;g.fillText(`SIDE A · 33⅓ RPM${s.y?" · "+s.y:""}`,c,410,380);
    g.globalAlpha=1;g.fillStyle="#111";g.beginPath();g.arc(c,c,14,0,7);g.fill()})}
  function makeVinyl(s){const g=new THREE.Group();const disc=new THREE.Mesh(new THREE.CylinderGeometry(.15,.15,.003,96),[new THREE.MeshStandardMaterial({color:0x080808,roughness:.3}),new THREE.MeshStandardMaterial({map:grooves,roughness:.28,metalness:.35}),new THREE.MeshStandardMaterial({map:grooves,roughness:.3,metalness:.3})]);g.add(disc);
    const lab=new THREE.Mesh(new THREE.CircleGeometry(.05,48),new THREE.MeshStandardMaterial({map:labelTex(s),roughness:.6}));lab.rotation.x=-Math.PI/2;lab.position.y=.0018;g.add(lab);return g}
  function makeTurntable(){const g=new THREE.Group();const base=new THREE.Mesh(new THREE.BoxGeometry(.46,.06,.36),new THREE.MeshStandardMaterial({color:0x6b3f22,roughness:.5}));base.position.y=-.03;g.add(base);
    const plat=new THREE.Mesh(new THREE.CylinderGeometry(.155,.155,.016,64),new THREE.MeshStandardMaterial({color:0x9a9a9a,metalness:.8,roughness:.3}));plat.position.set(-.06,.008,0);g.add(plat);
    const arm=new THREE.Group();arm.position.set(.16,.03,-.12);const post=new THREE.Mesh(new THREE.CylinderGeometry(.015,.018,.05),new THREE.MeshStandardMaterial({color:0xcccccc,metalness:.9,roughness:.2}));arm.add(post);
    const rod=new THREE.Mesh(new THREE.CylinderGeometry(.004,.004,.26),post.material);rod.rotation.z=Math.PI/2;rod.rotation.y=.5;rod.position.set(-.11,.025,.06);arm.add(rod);g.add(arm);g.userData={plat,arm};return g}
  const amb=makeTurntable();amb.position.set(.6,1.03,0);amb.scale.setScalar(1.3);counter.add(amb);let ambV=null;
  { const s=api.all[0];if(s){ambV=makeVinyl(s);ambV.position.set(-.06,.018,0);amb.add(ambV)} }
  // ---------- inspect scene ----------
  const iscene=new THREE.Scene();iscene.background=new THREE.Color(0x140d08);const icam=new THREE.PerspectiveCamera(40,1,.01,20);icam.position.set(0,.32,1.05);icam.lookAt(0,.05,0);
  iscene.add(new THREE.HemisphereLight(0xfff0dd,0x332211,1.1));const key=new THREE.SpotLight(0xffd6a8,25,6,.6,.5);key.position.set(.6,1.6,1);iscene.add(key);const rim=new THREE.PointLight(0xff8a50,3,4);rim.position.set(-1,.6,-.6);iscene.add(rim);
  const ifloor=new THREE.Mesh(new THREE.CircleGeometry(1.4,64),new THREE.MeshStandardMaterial({color:0x2b1b10,roughness:.9}));ifloor.rotation.x=-Math.PI/2;ifloor.position.y=-.065;iscene.add(ifloor);
  let insp=null;
  function backTex(s){return cv(512,512,(g,w)=>{g.fillStyle="#d8bf93";g.fillRect(0,0,w,w);g.fillStyle="rgba(0,0,0,.05)";for(let i=0;i<800;i++)g.fillRect(Math.random()*w,Math.random()*w,2,2);
    g.fillStyle=api.labelColor(s);g.fillRect(0,0,w,14);g.fillStyle="#2a1d14";g.font="bold 40px Fraunces, Georgia, serif";let y=wrapText(g,s.t,28,70,456,42,2);g.font="28px DM Sans, sans-serif";g.fillText(s.a,28,y+4,456);y+=50;
    g.font="22px DM Sans, sans-serif";const rows=[["Album",s.al],["Year",s.y],["Language",s.l],["Type",s.g],["Family",api.family(s)[0]],["Saved in",s.p?s.p+" post"+(s.p>1?"s":""):""]].filter(r=>r[1]);
    for(const[k,v]of rows){g.globalAlpha=.6;g.fillText(k.toUpperCase(),28,y);g.globalAlpha=1;y=wrapText(g,v,170,y,310,26,2)+4}
    if(s.n){g.font="italic 20px DM Sans, sans-serif";g.globalAlpha=.8;wrapText(g,"“"+s.n+"”",28,Math.max(y+10,420),456,24,3)}
    g.globalAlpha=1;g.font="16px DM Sans, sans-serif";g.fillText("POOJITH'S RECORD SHOP · STEREO",28,492)})}
  function pick(s){if(insp)drop(true);const root=new THREE.Group();iscene.add(root);
    const sl=new THREE.Mesh(new THREE.BoxGeometry(.32,.32,.006),[sideMat,sideMat,sideMat,sideMat,new THREE.MeshStandardMaterial({map:sleeveTex(s),roughness:.5}),new THREE.MeshStandardMaterial({map:backTex(s),roughness:.9})]);
    const sleeveG=new THREE.Group();sleeveG.add(sl);root.add(sleeveG);const tt=makeTurntable();tt.position.set(.2,-.035,0);tt.visible=false;root.add(tt);
    const v=makeVinyl(s);const vg=new THREE.Group();vg.add(v);v.rotation.x=Math.PI/2;sleeveG.add(vg);
    insp={s,root,sleeveG,tt,vg,v,t:0,flip:0,flipT:0,yaw:0,pitch:0};$("#crateUI").hidden=true;$("#pad").hidden=true;$("#hud").textContent="Drag to turn the record · Flip sleeve to read the back";drawPick();$("#pickUI").hidden=false;resize()}
  function drawPick(){if(!insp)return;const s=insp.s,el=$("#pickInfo"),sid=api.spId(s);
    el.innerHTML=`<h2>${esc(s.t)}</h2><div style="color:#6d5a45;margin:2px 0 6px">${esc(s.a)}</div>${api.detailsKV(s)}${api.actionsHTML(s)}
     ${sid?`<iframe style="border-radius:12px;margin-top:8px" src="https://open.spotify.com/embed/track/${sid}?utm_source=generator&theme=0" width="100%" height="80" frameborder="0" allow="autoplay; clipboard-write; encrypted-media; fullscreen; picture-in-picture" loading="lazy"></iframe>`:""}
     <div class="row"><button class="btn" id="pFlip">↻ Flip sleeve</button><button class="btn" id="pMore">More like this</button><button class="btn acc" id="pBack">Put it back</button></div>`;
    api.wireActions(el,s,drawPick);$("#pFlip").onclick=()=>{insp.flip=insp.flip?0:1;insp.yaw=0;insp.pitch=0};$("#pBack").onclick=()=>drop();$("#pMore").onclick=()=>api.openDetail(s.id)}
  function drop(silent){if(!insp)return;iscene.remove(insp.root);insp.root.traverse(o=>{o.geometry?.dispose?.()});insp=null;$("#pickUI").hidden=true;if(!silent){$("#crateUI").hidden=!focus;$("#pad").hidden=!!focus;$("#hud").textContent=HUD}}
  const HUD=$("#hud").textContent;
  // ---------- navigation ----------
  let yaw=0,pitch=-.12;const pos=new THREE.Vector3(0,1.6,6);let focus=null,camT=null;const keys={};
  addEventListener("keydown",e=>{if(e.target.closest?.("input,select,textarea,dialog"))return;keys[e.key.toLowerCase()]=true;if(focus&&!insp){if(e.key==="ArrowRight"||e.key==="ArrowDown")flip(1);if(e.key==="ArrowLeft"||e.key==="ArrowUp")flip(-1);if(e.key==="Enter")pickCur()}});
  addEventListener("keyup",e=>keys[e.key.toLowerCase()]=false);
  document.querySelectorAll("#pad button").forEach(b=>{const k={f:"w",b:"s",l:"a",r:"d"}[b.dataset.k];b.onpointerdown=e=>{e.preventDefault();keys[k]=true};b.onpointerup=b.onpointerleave=()=>keys[k]=false});
  let drag=null;const ray=new THREE.Raycaster(),ndc=new THREE.Vector2();
  canvas.addEventListener("pointerdown",e=>{drag={x:e.clientX,y:e.clientY,moved:0,yaw,pitch};canvas.setPointerCapture(e.pointerId)});
  canvas.addEventListener("pointermove",e=>{if(!drag)return;const dx=e.clientX-drag.x,dy=e.clientY-drag.y;drag.moved=Math.max(drag.moved,Math.abs(dx)+Math.abs(dy));
    if(insp){insp.yaw+=(e.movementX||0)*.01;insp.pitch=Math.max(-.6,Math.min(.9,insp.pitch+(e.movementY||0)*.006))}else if(!focus){yaw=drag.yaw-dx*.005;pitch=Math.max(-1.1,Math.min(.6,drag.pitch-dy*.004))}
    else if(Math.abs(dx)>40){flip(dx<0?1:-1);drag.x=e.clientX}});
  canvas.addEventListener("pointerup",e=>{const d=drag;drag=null;if(!d||d.moved>6||insp)return;const r=canvas.getBoundingClientRect();ndc.set((e.clientX-r.left)/r.width*2-1,-(e.clientY-r.top)/r.height*2+1);ray.setFromCamera(ndc,cam);
    const hit=ray.intersectObjects(clickables,false)[0];if(!hit)return;const m=hit.object;
    if(m.userData.shelf)return pick(m.userData.song);const c=crates[m.userData.crate];if(focus!==c)return focusCrate(m.userData.crate);
    if(m.userData.idx===c.cur)pickCur();else{c.cur=m.userData.idx;layoutCrate(c);crateInfo()}});
  canvas.addEventListener("wheel",e=>{e.preventDefault();if(insp)return;if(focus)flip(e.deltaY>0?1:-1);else{const f=new THREE.Vector3(-Math.sin(yaw),0,-Math.cos(yaw));pos.addScaledVector(f,-e.deltaY*.003);clamp()}},{passive:false});
  function clamp(){pos.x=Math.max(-W/2+.6,Math.min(W/2-.6,pos.x));pos.z=Math.max(-D/2+.8,Math.min(D/2-.8,pos.z))}
  function focusCrate(i){const c=crates[i];if(!c)return;if(focus&&focus!==c){const o=focus;focus=null;layoutCrate(o)}focus=c;c.cur=Math.min(c.cur,c.recs.length-1);layoutCrate(c);
    const wp=new THREE.Vector3();c.group.getWorldPosition(wp);camT={pos:new THREE.Vector3(wp.x,wp.y+.75,wp.z+.75),look:new THREE.Vector3(wp.x,wp.y+.12,wp.z-.02)};
    $("#crateUI").hidden=false;$("#pad").hidden=true;crateInfo()}
  function leave(){if(!focus)return;const c=focus;focus=null;layoutCrate(c);camT=null;pos.set(c.group.position.x,1.6,c.group.position.z+1.9);yaw=0;pitch=-.35;$("#crateUI").hidden=true;$("#pad").hidden=false}
  function flip(n){if(!focus)return;const c=focus;c.cur=Math.max(0,Math.min(c.recs.length-1,c.cur+n));layoutCrate(c);crateInfo()}
  function crateInfo(){const c=focus;if(!c)return;const s=c.recs[c.cur].userData.song;$("#cInfo").innerHTML=`<b>${esc(s.t)}</b> — ${esc(s.a)} <span style="opacity:.6">(${c.cur+1}/${c.recs.length} · ${esc(c.name)})</span>`}
  function pickCur(){if(focus)pick(focus.recs[focus.cur].userData.song)}
  $("#cPrev").onclick=()=>flip(-1);$("#cNext").onclick=()=>flip(1);$("#cPick").onclick=pickCur;$("#cLeave").onclick=leave;
  // ---------- loop ----------
  function resize(){const w=canvas.clientWidth||innerWidth,h=canvas.clientHeight||innerHeight;R.setSize(w,h,false);cam.aspect=w/h;cam.updateProjectionMatrix();
    const side=!$("#pickUI").hidden&&w>700;icam.aspect=w/h;icam.position.set(0,w<h?.55:.32,w<h?2.5:1.05);icam.lookAt(0,w<h?.12:.05,0);icam.setViewOffset(w,h,side?Math.min(180,w*.14):0,w<=700&&insp?h*.18:0,w,h);icam.updateProjectionMatrix()}
  addEventListener("resize",resize);resize();
  let running=true,last=performance.now();const tmp=new THREE.Vector3(),lookM=new THREE.Vector3();
  function tick(now){if(!running)return;requestAnimationFrame(tick);const dt=Math.min(.05,(now-last)/1000);last=now;
    if(!focus&&!insp){const f=new THREE.Vector3(-Math.sin(yaw),0,-Math.cos(yaw)),r=new THREE.Vector3(-f.z,0,f.x),sp=2.4*dt;
      if(keys.w||keys.arrowup)pos.addScaledVector(f,sp);if(keys.s||keys.arrowdown)pos.addScaledVector(f,-sp);if(keys.a||keys.arrowleft)pos.addScaledVector(r,-sp);if(keys.d||keys.arrowright)pos.addScaledVector(r,sp);clamp();
      cam.position.lerp(pos,.25);cam.rotation.set(0,0,0);cam.rotation.order="YXZ";cam.rotation.y=yaw;cam.rotation.x=pitch}
    else if(focus&&camT){cam.position.lerp(camT.pos,.12);lookM.lerp(camT.look,.2);cam.lookAt(lookM)}
    if(!focus)lookM.copy(cam.position).add(new THREE.Vector3(-Math.sin(yaw),Math.sin(pitch),-Math.cos(yaw)));
    for(const c of crates)for(const m of c.recs){const tx=m.userData.tx??-.18,ty=m.userData.ty??.022;m.rotation.x+=(tx-m.rotation.x)*.2;m.position.y+=(ty-m.position.y)*.2}
    if(ambV)ambV.rotation.y-=dt*3.49;
    if(insp){const I=insp;I.t+=dt;const t=I.t,e=x=>x<0?0:x>1?1:1-Math.pow(1-x,3);
      const a=e(t/.6),b=e((t-.6)/.8),c=e((t-1.4)/.9);
      I.sleeveG.position.set(-.2*c,.16-(1-a)*.3,-.05*c);I.sleeveG.rotation.set(-.05,(1-a)*.8,0);
      I.flipT+=(I.flip-I.flipT)*.12;I.sleeveG.rotation.y+=I.flipT*Math.PI;
      // vinyl: inside sleeve -> slides out to the right -> lies on platter
      if(c<=0){I.vg.position.set(.2*b,0,-.004);I.vg.rotation.set(0,0,0)}
      else{if(I.vg.parent!==I.root){I.root.add(I.vg)}const from=new THREE.Vector3(.2,.16,-.004),to=new THREE.Vector3(.14,-.016,0);I.vg.position.lerpVectors(from,to,c);I.vg.position.y+=Math.sin(c*Math.PI)*.08;I.vg.rotation.x=-Math.PI/2*c}
      I.tt.visible=t>1.1;I.tt.position.y=-.035-(1-e((t-1.1)/.4))*.1;
      if(c>=1){I.v.rotation.y-=dt*3.49;I.tt.userData.arm.rotation.y+=(-.35-I.tt.userData.arm.rotation.y)*.05}
      I.root.rotation.y+=(I.yaw-I.root.rotation.y)*.15;I.root.rotation.x+=(I.pitch*.5-I.root.rotation.x)*.15;R.render(iscene,icam)}
    else R.render(scene,cam)}
  requestAnimationFrame(tick);
  build();
  let rb;const S={refresh(){clearTimeout(rb);rb=setTimeout(()=>{const was=focus?crates.indexOf(focus):-1;focus=null;build();if(was>=0&&crates[was])focusCrate(was);else{camT=null;$("#crateUI").hidden=true}},120)},
    pause(){running=false},resume(){if(!running){running=true;last=performance.now();requestAnimationFrame(tick)}resize()},
    statusChanged(id){if(insp&&insp.s.id===id)drawPick()},escape(){if(insp){drop();return true}if(focus){leave();return true}return false},
    focusCrate,flip,pick:id=>{const s=api.all.find(x=>x.id===id);if(s)pick(s)},drop,leave,get crates(){return crates.map(c=>({name:c.name,n:c.recs.length,cur:c.cur}))},get inspecting(){return insp?insp.s.id:null},
    walk(x,z,y){pos.set(x,1.6,z);if(y!=null)yaw=y}};
  return S}
