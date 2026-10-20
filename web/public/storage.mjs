const NAME='hardplay-web-v1';let db;
export function openStore(){return db?Promise.resolve(db):new Promise((resolve,reject)=>{const r=indexedDB.open(NAME,1);r.onupgradeneeded=()=>{for(const s of ['audio','tracks','state'])r.result.createObjectStore(s,{keyPath:'id'})};r.onerror=()=>reject(r.error);r.onsuccess=()=>{db=r.result;db.onversionchange=()=>db.close();resolve(db)}})}
async function tx(stores,mode,run){const d=await openStore();return new Promise((resolve,reject)=>{const t=d.transaction(stores,mode);let result;try{result=run(t)}catch(e){t.abort();reject(e);return}t.oncomplete=()=>resolve(result?.result);t.onerror=()=>reject(t.error??Error('Storage failed'));t.onabort=()=>reject(t.error??Error('Storage transaction cancelled'))})}
export const allTracks=()=>tx(['tracks'],'readonly',t=>t.objectStore('tracks').getAll());
export const cachedIDs=()=>tx(['audio'],'readonly',t=>t.objectStore('audio').getAllKeys());
export const readAudio=id=>tx(['audio'],'readonly',t=>t.objectStore('audio').get(id));
export const readState=()=>tx(['state'],'readonly',t=>t.objectStore('state').get('session'));
export const saveState=value=>tx(['state'],'readwrite',t=>t.objectStore('state').put({id:'session',value:structuredClone(value)}));
export const saveTrack=value=>tx(['tracks'],'readwrite',t=>t.objectStore('tracks').put(structuredClone(value)));
export function commitAudio(track,blob){if(!blob?.size)throw Error('The audio file is empty (0 bytes).');return tx(['audio','tracks'],'readwrite',t=>{t.objectStore('audio').put({id:track.id,blob,size:blob.size});t.objectStore('tracks').put(structuredClone(track))})}
export const removeAudio=id=>tx(['audio','tracks'],'readwrite',t=>{t.objectStore('audio').delete(id);t.objectStore('tracks').delete(id)});
export async function completeDownload(response,onProgress=()=>{},signal){
 signal?.throwIfAborted();
 if(!response.ok)throw Error(`Download failed (${response.status}).`);
 if(response.type==='opaque')throw Error('This link does not allow audio downloads from this app.');
 const type=response.headers.get('content-type')??'';
 if(/text\/html|application\/json|text\/plain/.test(type)){
  let text='';try{text=(await response.text()).slice(0,500)}catch{};
  throw Error(text.startsWith('{')?JSON.parse(text).error??'The cloud returned an error.':'This sharing link requires sign-in, confirmation, or is not an audio file.');
 }
 const length=Number(response.headers.get('content-length'))||0,compressed=response.headers.has('content-encoding');
 const chunks=[];let loaded=0;const reader=response.body?.getReader();
 if(!reader){const blob=await response.blob();signal?.throwIfAborted();if(!blob.size)throw Error('The audio file is empty.');if(blob.size>1073741824)throw Error('This file exceeds the 1 GB per-file download limit.');if(length&&!compressed&&blob.size!==length)throw Error('Download was interrupted. The incomplete file was not saved.');return blob}
 try{while(true){signal?.throwIfAborted();const {done,value}=await reader.read();if(done)break;loaded+=value.byteLength;if(loaded>1073741824)throw Error('This file exceeds the 1 GB per-file download limit.');chunks.push(value);onProgress(loaded,length)}
 }catch(e){await reader.cancel().catch(()=>{});throw e}
 if(!loaded)throw Error('The audio file is empty (0 bytes).');
 if(length&&!compressed&&loaded!==length)throw Error('Download was interrupted. The incomplete file was not saved.');
 signal?.throwIfAborted();return new Blob(chunks,{type:type||'application/octet-stream'});
}
