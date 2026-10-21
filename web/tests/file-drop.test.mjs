import test from 'node:test';
import assert from 'node:assert/strict';
import {droppedAudioFiles} from '../public/file-drop.mjs';
import {setName} from '../public/core.mjs';
import {createHistory} from '../public/history.mjs';

const fileEntry=file=>({isFile:true,file:resolve=>resolve(file)});
const folder=batches=>({isDirectory:true,createReader(){let i=0;return {readEntries(resolve){resolve(batches[i++]||[])}}}});
test('Finder folder drops read all batches, nested folders and audio only in order',async()=>{
 const a={name:'Трек 1.WAV',type:''},b={name:'two.mp3',type:'audio/mpeg'},c={name:'three',type:'audio/aiff'};
 const root=folder([[fileEntry(a),fileEntry({name:'readme.txt',type:'text/plain'})],[folder([[fileEntry(b)]]),fileEntry(c)]]);
 const result=await droppedAudioFiles({items:[{kind:'file',webkitGetAsEntry:()=>root}]});
 assert.deepEqual(result,[a,b,c]);
});
test('file drop fallback supports normal FileList and mixed entry providers',async()=>{
 const a={name:'one.flac'},b={name:'two.caf'};
 assert.deepEqual(await droppedAudioFiles({files:[a,{name:'cover.png'}]}),[a]);
 assert.deepEqual(await droppedAudioFiles({items:[{kind:'file',webkitGetAsEntry:()=>fileEntry(a)},{kind:'file',getAsFile:()=>b}]}),[a,b]);
});
test('a failed directory read reports failure instead of silently adding an incomplete folder',async()=>{
 const root={isDirectory:true,createReader:()=>({readEntries:(_resolve,reject)=>reject(Error('Access denied'))})};
 await assert.rejects(droppedAudioFiles({items:[{kind:'file',webkitGetAsEntry:()=>root}]}),/Access denied/);
});
test('custom set names normalize empty and multiline text, and remain independent through undo/redo',()=>{
 assert.equal(setName('  '),'My Set');assert.equal(setName('  Вечер\nсцена\tA  '),'Вечер сцена A');assert.equal(setName('x'.repeat(120)).length,100);
 const h=createHistory();h.reset({name:'My Set',tracks:[]});h.commit({name:setName('Evening set'),tracks:[]});
 assert.equal(h.undo().name,'My Set');assert.equal(h.redo().name,'Evening set');
});
