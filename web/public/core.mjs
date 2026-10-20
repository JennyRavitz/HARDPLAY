export const FADES = {off:0,short:3,long:6};
export const clamp = (n,a=0,b=1)=>Math.max(a,Math.min(b,Number.isFinite(+n)?+n:a));
export const clock = n=>`${Math.floor(Math.max(0,n||0)/60)}:${String(Math.floor(Math.max(0,n||0)%60)).padStart(2,'0')}`;
export const bytes = n=>n>1073741824?`${(n/1073741824).toFixed(1)} GB`:`${(n/1048576).toFixed(1)} MB`;
export const escapeHTML = s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const fileTitle = s=>String(s).replace(/\.[a-z0-9]{1,8}$/i,'');
export const cutoff = (duration,seconds)=>Math.max(duration/2,duration-Math.max(0,seconds));
export function nextIndex(tracks,current,{shuffle=false,repeat=false}={},random=Math.random){
 if(!tracks.length)return -1;const i=tracks.findIndex(t=>t.id===current);
 if(shuffle&&tracks.length>1){const rest=tracks.map((_,i)=>i).filter(j=>j!==i);return rest[Math.min(rest.length-1,Math.floor(random()*rest.length))]}
 return i+1<tracks.length?i+1:repeat?0:-1;
}
export function crossfadeLength(requested,remaining,incoming){return Math.max(0,Math.min(requested,remaining,incoming/2))}
export function playDuration(track,sourceDuration=track?.duration){
 const full=Number.isFinite(sourceDuration)&&sourceDuration>0?sourceDuration:0;
 const limit=Number.isFinite(track?.playSeconds)&&track.playSeconds>0?track.playSeconds:0;
 return full?(limit?Math.min(full,limit):full):limit;
}
export function parsePlayTime(raw){
 const value=String(raw).trim();if(!value)return null;
 if(!/^(?:\d+(?:\.\d+)?|\d+:[0-5]\d(?:\.\d+)?)$/.test(value))throw Error('Use m:ss or seconds, for example 1:30 or 90.');
 const parts=value.split(':').map(Number),seconds=parts.length===2?parts[0]*60+parts[1]:parts[0];
 if(!Number.isFinite(seconds)||seconds<1||seconds>86400)throw Error('Choose a time from 1 second to 24 hours.');
 return seconds;
}
export function duplicateTrack(track,id){return {...structuredClone(track),id,position:0}}
export function setTiming(tracks,settings={}){
 let seconds=tracks.reduce((sum,t)=>sum+playDuration(t),0);
 if(settings.end!=='stop')for(let i=0;i<tracks.length-1;i++)seconds-=crossfadeLength(FADES[tracks[i].fade]||0,playDuration(tracks[i]),playDuration(tracks[i+1]));
 return {seconds:Math.max(0,seconds),unknown:tracks.some(t=>!t.duration),label:settings.end==='stop'?'Audio total':settings.repeat?'One pass':'Set',approximate:!!settings.shuffle};
}
export function validatePlaylist(value){
 if(value?.type!=='hardplay-web-playlist'||value.version!==1||!Array.isArray(value.tracks)||value.tracks.length>10000)throw Error('This playlist is invalid or uses an unsupported version.');
 const ids=new Set();
 for(const t of value.tracks){if(typeof t.id!=='string'||ids.has(t.id)||typeof t.name!=='string'||t.name.length>300||!Object.hasOwn(FADES,t.fade)||!Number.isFinite(t.position)||t.position<0)throw Error('Invalid track in playlist.');if(t.playSeconds!=null&&(!Number.isFinite(t.playSeconds)||t.playSeconds<1||t.playSeconds>86400))throw Error('Invalid track play time.');if(t.duration!==undefined&&(!Number.isFinite(t.duration)||t.duration<0))throw Error('Invalid track duration.');if(t.provider&&!['local','direct','drive','dropbox'].includes(t.provider))throw Error('Invalid audio source.');if(t.provider&&t.provider!=='local'&&typeof t.url!=='string')throw Error('Missing audio URL.');ids.add(t.id)}
 if(value.settings){const v=value.settings;if(v.volume!==undefined&&(!Number.isFinite(v.volume)||v.volume<0||v.volume>1)||v.stopBefore!==undefined&&(!Number.isFinite(v.stopBefore)||v.stopBefore<0||v.stopBefore>60)||v.start!==undefined&&!['restart','resume'].includes(v.start)||v.end!==undefined&&!['next','stop'].includes(v.end))throw Error('Invalid playlist settings.');for(const k of ['shuffle','repeat','hints','protectEdits','protectSelection','protectPlayback','protectSettings'])if(v[k]!==undefined&&typeof v[k]!=='boolean')throw Error('Invalid playlist setting.');}
 return value;
}
export const DEFAULT_SETTINGS={volume:0.8,shuffle:false,repeat:false,start:'restart',end:'next',stopBefore:0,hints:false,protectEdits:true,protectSelection:true,protectPlayback:false,protectSettings:true};
export const ACTIONS=[['play','Play / Pause',true,'toggle'],['previous','Previous Track'],['next','Next Track'],['restart','Restart'],['resume','Resume'],['mute','Mute',true,'toggle'],['shuffle','Shuffle',true,'toggle'],['repeat','Repeat Queue',true,'toggle'],['stop','Stop at End',true,'toggle'],['short','Short Fade',true],['long','Long Fade',true],['off','Fade Off'],['apply','Apply Fade to All'],['allOff','All Fades Off'],['allShort','All Fades 3 Seconds'],['allLong','All Fades 6 Seconds'],['volume','Master Volume'],['down','Volume Down'],['up','Volume Up'],['mini','Mini Player',true,'toggle'],['playlist','Playlist Window',true],['setup','Lock Setup',true],['lock','Lock All Controls']];
export function actionInfo(id){if(typeof id!=='string')return null;return ACTIONS.find(a=>a[0]===id)??(id.startsWith('track:')?[id,'Play track',true]:null)}
export function validateMaps(value){if(value?.version!==1||value.type!=='hardplay-web-controls'||!Array.isArray(value.bindings)||value.bindings.length>2000)throw Error('Invalid control set.');const inputs=new Set();for(const b of value.bindings){const a=actionInfo(b.action);if(!a||b.action==='volume'&&(b.input!=='midi'||b.mode!=='trigger'||!/:176:\d+:\d+$/.test(b.signal))||!['trigger','toggle'].includes(b.mode)||b.mode==='toggle'&&!a[2]||!['key','midi'].includes(b.input)||typeof b.signal!=='string'||b.signal.length>500||inputs.has(b.input+b.signal))throw Error('Invalid or duplicate assignment.');inputs.add(b.input+b.signal)}return value}
export function keySignal(e){return `${e.ctrlKey?'Ctrl+':''}${e.altKey?'Alt+':''}${e.shiftKey?'Shift+':''}${e.metaKey?'Meta+':''}${e.code}`}
export function keyLabel(e){return `${e.ctrlKey?'⌃':''}${e.altKey?'⌥':''}${e.shiftKey?'⇧':''}${e.metaKey?'⌘':''}${e.code==='Space'?'Space':e.code.replace(/^(Key|Digit)/,'')}`}
