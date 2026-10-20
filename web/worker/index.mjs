import {cloudTarget,allowedCloudHost} from '../public/providers.mjs';
const failure=(message,status=400)=>Response.json({error:message},{status,headers:{'cache-control':'no-store'}});
export async function cloudProxy(request,fetcher=fetch){
 if(request.method!=='GET')return failure('Method not allowed.',405);
 const url=new URL(request.url),provider=url.searchParams.get('provider');let target;
 try{target=cloudTarget(provider,url.searchParams.get('url'))}catch(e){return failure(e.message)}
 try{
  for(let count=0;count<6;count++){
   if(target.protocol!=='https:'||target.username||target.password||target.port||!allowedCloudHost(provider,target.hostname))return failure('The sharing link redirected outside its cloud provider.',403);
   const response=await fetcher(target.href,{redirect:'manual',signal:request.signal,headers:{Accept:'audio/*,application/octet-stream;q=0.9'}});
   if([301,302,303,307,308].includes(response.status)){
    const location=response.headers.get('location');await response.body?.cancel();if(!location)return failure('The cloud returned an invalid redirect.',502);target=new URL(location,target);continue;
   }
   if(!response.ok){await response.body?.cancel();return failure(`Cloud download failed (${response.status}). Check sharing permissions.`,502)}
   const type=response.headers.get('content-type')||'application/octet-stream';
   if(/text\/|application\/json/i.test(type)){await response.body?.cancel();return failure('This cloud link needs sign-in or confirmation, or is not a downloadable audio file.',422)}
   const length=Number(response.headers.get('content-length'))||0;if(length>1073741824){await response.body?.cancel();return failure('This file exceeds the 1 GB per-file limit.',413)}
   const headers=new Headers({'content-type':type,'cache-control':'no-store','x-content-type-options':'nosniff'});
   for(const key of ['content-disposition','content-length','content-encoding'])if(response.headers.has(key))headers.set(key,response.headers.get(key));
   return new Response(response.body,{status:200,headers});
  }
  return failure('Too many cloud redirects.',502);
 }catch(e){return failure(e.name==='AbortError'?'Download cancelled.':'The cloud download could not be reached. Try again.',502)}
}
