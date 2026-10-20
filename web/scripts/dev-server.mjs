import http from 'node:http';
import {Readable} from 'node:stream';
import worker from '../dist/server/index.js';
const port=Number(process.env.PORT||4173);
function wav(){const samples=22050*12,data=Buffer.alloc(44+samples*2);data.write('RIFF');data.writeUInt32LE(data.length-8,4);data.write('WAVEfmt ',8);data.writeUInt32LE(16,16);data.writeUInt16LE(1,20);data.writeUInt16LE(1,22);data.writeUInt32LE(22050,24);data.writeUInt32LE(44100,28);data.writeUInt16LE(2,32);data.writeUInt16LE(16,34);data.write('data',36);data.writeUInt32LE(samples*2,40);return data}
const server=http.createServer(async(req,res)=>{try{if(req.url.startsWith('/qa/silence')){const data=wav();res.writeHead(200,{'content-type':'audio/wav','content-length':data.length});res.end(data);return}const controller=new AbortController();req.on('aborted',()=>controller.abort());const request=new Request(`http://localhost:${port}${req.url}`,{method:req.method,headers:req.headers,signal:controller.signal});const response=await worker.fetch(request,{},{});res.writeHead(response.status,Object.fromEntries(response.headers));if(response.body)Readable.fromWeb(response.body).pipe(res);else res.end()}catch(e){res.writeHead(500);res.end(e.message)}});
server.listen(port,'127.0.0.1',()=>console.log(`HARDPLAY preview http://localhost:${port}`));
process.on('SIGTERM',()=>server.close());
