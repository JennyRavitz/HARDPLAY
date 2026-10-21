const extensions=/\.(mp3|m4a|aac|wav|aif|aiff|flac|alac|caf|mp4|ogg|opus|wma|ape)$/i;
export const isAudioFile=file=>file.type?.startsWith('audio/')||extensions.test(file.name||'');
export async function droppedAudioFiles(transfer){
 const files=[];let visited=0;
 async function walk(entry){
  if(++visited>10000)throw Error('This folder contains too many items. Drop a smaller selection.');
  if(entry.isFile){const file=await new Promise((resolve,reject)=>entry.file(resolve,reject));if(isAudioFile(file))files.push(file)}
  else if(entry.isDirectory){const reader=entry.createReader();for(;;){const entries=await new Promise((resolve,reject)=>reader.readEntries(resolve,reject));if(!entries.length)break;for(const child of entries)await walk(child)}}
 }
 const items=[...(transfer.items||[])].filter(item=>item.kind==='file');
 const entries=items.map(item=>item.webkitGetAsEntry?.());
 if(entries.some(Boolean)){for(let i=0;i<items.length;i++){if(entries[i])await walk(entries[i]);else{const file=items[i].getAsFile?.();if(file&&isAudioFile(file))files.push(file)}}}
 else files.push(...[...(transfer.files||[])].filter(isAudioFile));
 return files;
}
