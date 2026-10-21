import Foundation

enum ViewerPage {
    static let html = #"""
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"><title>Hard Play · Live Set</title><link rel="stylesheet" href="/viewer.css"><script defer src="/viewer.js"></script></head>
<body><main><header><div class="brand" aria-label="HARDPLAY">HARDPLAY</div><span id="connection" role="status">Connecting…</span></header>
<div class="setline"><span class="eyebrow">LIVE SET · VIEW ONLY</span><h1 id="set">Your stage, in view.</h1></div>
<section class="decks" aria-label="Playback"><article class="deck now"><div class="decktop"><span class="eyebrow" id="nowLabel">NOW</span><span id="nowNumber" class="number">—</span></div><h2 id="nowTitle">Connect to HARDPLAY</h2><div class="clock"><strong id="elapsed">—:—</strong><span id="total">/ —:—</span></div><progress id="progress" max="1" value="0" aria-label="Track progress"></progress><div class="bottom"><span id="playState">WAITING</span><span id="remaining">— remaining</span></div></article>
<article class="deck next"><div class="decktop"><span class="eyebrow" id="nextLabel">NEXT</span><span id="nextNumber" class="number">—</span></div><h2 id="nextTitle">—</h2><p id="transition">Waiting for a live connection</p></article></section>
<section class="queue"><div class="queuehead"><h2>Queue</h2><span id="count">— tracks</span></div><ol id="tracks"></ol><p id="empty" hidden>No tracks in this set.</p></section>
<footer>HARD PLAY · Local live view<span id="updated">No live data yet</span></footer></main></body></html>
"""#
    static let css = #"""
@font-face{font-family:HardplayMarker;src:url(/viewer.ttf) format('truetype');font-display:swap}:root{font-family:HardplayMarker,"Marker Felt",sans-serif;color:#edf3ff;background:#0b1120;font-synthesis:none;color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:radial-gradient(ellipse at 0 0,#23374d80,transparent 60%);min-height:100vh}main{max-width:920px;margin:auto;padding:28px 24px}header,.setline,.decktop,.bottom,.queuehead,footer,li{display:flex;align-items:center;justify-content:space-between;gap:16px}header{margin-bottom:38px}.brand{font-size:15px;font-weight:900;letter-spacing:2px;color:#f5f8ff;text-decoration:none;line-height:1.05}.brand{background:#adc9e4;color:#171b20;padding:8px 12px;letter-spacing:0;clip-path:polygon(2% 0,99% 2%,98% 18%,100% 43%,98% 75%,99% 100%,1% 98%,2% 76%,0 52%,2% 20%)}#connection{font-size:12px;color:#b6c5d8;padding:8px 12px;border:1px solid #cadbff24;border-radius:20px}#connection.live{color:#b6d8ff;background:#5495d51a}#connection.lost{color:#ffd39e;border-color:#e0a86b50}.setline{display:block;margin-bottom:22px}.eyebrow{font-size:10px;font-weight:750;letter-spacing:1.6px;color:#9fb5ce}h1{font-size:28px;line-height:1.2;margin:10px 0;overflow-wrap:anywhere}h2{font-size:21px;line-height:1.3;margin:18px 0;overflow-wrap:anywhere}.decks{display:grid;grid-template-columns:1.6fr 1fr;gap:14px}.deck{border:1px solid #c1d9ff24;background:#ebf5ff06;border-radius:20px;padding:24px}.now{background:linear-gradient(130deg,#6ba4e01b,#ebf5ff06)}.number{font-variant-numeric:tabular-nums;color:#b5d7ff;font-weight:700}.clock{display:flex;align-items:baseline;gap:10px;font-variant-numeric:tabular-nums;margin:24px 0 18px}.clock strong{font-size:52px;font-weight:550;letter-spacing:-2px}.clock span{color:#9baec7;font-size:15px}progress{appearance:none;width:100%;height:4px;border:0;border-radius:8px;background:#e9f2ff15;display:block}progress::-webkit-progress-bar{background:#e9f2ff15;border-radius:8px}progress::-webkit-progress-value{background:#9ecbff;border-radius:8px}progress::-moz-progress-bar{background:#9ecbff;border-radius:8px}.bottom{margin-top:16px;font-size:11px;color:#a8bad1;font-variant-numeric:tabular-nums}#playState{font-weight:750;letter-spacing:1px}.next p{font-size:13px;line-height:1.6;color:#a8bad1}.queue{margin-top:28px}.queuehead{padding:0 4px}.queuehead h2{font-size:16px;margin:14px 0}.queuehead span,footer{font-size:11px;color:#8fa3bf}ol{list-style:none;margin:8px 0 0;padding:0}li{padding:14px 12px;border-top:1px solid #eaf3ff0c;font-size:14px;border-radius:8px}li.current{background:#88bdff13}li .num{font-size:12px;font-variant-numeric:tabular-nums;color:#91aac8;min-width:24px}li .title{flex:1;overflow-wrap:anywhere}li .tag{font-size:9px;font-weight:750;letter-spacing:1px;color:#b8d9ff}li .fade{color:#8fa3bf;font-size:11px;min-width:34px;text-align:right}footer{margin-top:32px;padding:18px 0;border-top:1px solid #eaf3ff12;flex-wrap:wrap}.stale .decks{opacity:.55}.stale #playState{color:#ffd39e}#empty{font-size:13px;color:#9fb5ce}button:focus-visible,a:focus-visible{outline:2px solid #b8d9ff;outline-offset:4px}@media(max-width:600px){main{padding:22px 18px}header{margin-bottom:28px}.decks{grid-template-columns:1fr}.deck{padding:20px}.next{padding:16px 20px}.next h2{font-size:17px;margin:10px 0}.next p{margin:4px 0}.clock strong{font-size:48px}h1{font-size:24px}li{padding:14px 8px}}@media(prefers-reduced-motion:no-preference){.decks{transition:opacity .2s}}
"""#
    static let js = #"""
'use strict';
const $=id=>document.getElementById(id);
// Session key is a URL fragment and memory only: no cookies or persistent storage.
let key=location.hash.slice(1);
let lastSuccess=0,lastQueue='',busy=false,expired=false;
const time=value=>{if(!Number.isFinite(value)||value<0)return '—:—';const n=Math.floor(value);return `${Math.floor(n/60)}:${String(n%60).padStart(2,'0')}`;};
function connection(text,mode){$('connection').textContent=text;$('connection').className=mode;document.body.classList.toggle('stale',mode==='lost');}
function render(s){
 $('set').textContent=s.set;$('nowLabel').textContent=s.crossfading?'FADING OUT':'NOW';$('nextLabel').textContent=s.crossfading?'FADING IN':'NEXT';
 $('nowNumber').textContent=s.now.number?String(s.now.number).padStart(2,'0'):'—';$('nextNumber').textContent=s.next.number?String(s.next.number).padStart(2,'0'):'—';
 $('nowTitle').textContent=s.now.title;$('nextTitle').textContent=s.next.title;
 $('elapsed').textContent=s.now.duration>0?time(s.now.elapsed):'—:—';$('total').textContent='/ '+(s.now.duration>0?time(s.now.duration):'—:—');
 $('remaining').textContent=s.now.duration>0?time(Math.max(0,s.now.duration-s.now.elapsed))+' remaining':'Duration unavailable';
 $('progress').value=s.now.duration>0?Math.min(1,s.now.elapsed/s.now.duration):0;
 $('playState').textContent=s.playing?'PLAYING':'PAUSED';
 $('transition').textContent=s.crossfading?`Crossfade · ${s.transitionRemaining.toFixed(1)} s · ${Math.round(s.now.gain*100)}% → ${Math.round(s.next.gain*100)}%`:s.endMode==='stop'?'Auto stop at the end of the track':s.next.number?'Continues to the next track':'End of queue';
 $('count').textContent=s.totalTracks+' '+(s.totalTracks===1?'track':'tracks');$('empty').hidden=s.totalTracks!==0;
 const signature=JSON.stringify([s.tracks,s.now.number,s.next.number,s.crossfading]);
 if(signature!==lastQueue){lastQueue=signature;const rows=s.tracks.map(item=>{const li=document.createElement('li');li.className=item.number===s.now.number?'current':'';const num=document.createElement('span');num.className='num';num.textContent=String(item.number).padStart(2,'0');const title=document.createElement('span');title.className='title';title.textContent=item.title;const tag=document.createElement('span');tag.className='tag';tag.textContent=item.number===s.now.number?(s.crossfading?'OUT':'NOW'):item.number===s.next.number?(s.crossfading?'IN':'NEXT'):'';const fade=document.createElement('span');fade.className='fade';fade.textContent=item.fade?item.fade+' s':'—';li.append(num,title,tag,fade);return li;});$('tracks').replaceChildren(...rows);}
 $('updated').textContent='Updated '+new Date().toLocaleTimeString([], {hour:'2-digit',minute:'2-digit',second:'2-digit'});
}
async function refresh(){
 if(busy||expired||document.hidden)return;
 if(!/^[a-fA-F0-9]{64}$/.test(key)){expired=true;connection('Open the link from HARDPLAY','lost');$('transition').textContent='Enable Web Viewer in the Mac app and scan its QR code or open its full link.';return;}
 busy=true;const controller=new AbortController();const timeout=setTimeout(()=>controller.abort(),2500);
 try{const response=await fetch('/api/state',{headers:{Authorization:'Bearer '+key},cache:'no-store',signal:controller.signal});if(response.status===401){expired=true;key='';throw new Error('expired');}if(!response.ok)throw new Error('network');const state=await response.json();render(state);lastSuccess=Date.now();connection('Live · view only','live');}
 catch(error){if(expired){connection('Link expired · reconnect','lost');$('playState').textContent='DISCONNECTED';}else if(!lastSuccess||Date.now()-lastSuccess>3000){connection('Connection lost · retrying','lost');$('playState').textContent='LAST KNOWN STATE';}}
 finally{clearTimeout(timeout);busy=false;}
}
setInterval(refresh,1000);setInterval(()=>{if(lastSuccess&&Date.now()-lastSuccess>3500){connection(expired?'Link expired · reconnect':'Connection lost · retrying','lost');$('playState').textContent='LAST KNOWN STATE';}},1000);
document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh();});refresh();
"""#
}
