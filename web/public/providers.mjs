export function cloudTarget(provider,raw){
 const u=new URL(raw);if(u.protocol!=='https:'||u.username||u.password)throw Error('Use an HTTPS sharing link without embedded credentials.');
 if(provider==='drive'){
  if(!['drive.google.com','drive.usercontent.google.com','docs.google.com'].includes(u.hostname))throw Error('Use a Google Drive file sharing link.');
  const id=u.pathname.match(/\/file\/d\/([\w-]+)/)?.[1]??u.searchParams.get('id');
  if(!id||!/^[\w-]{8,200}$/.test(id))throw Error('Google Drive file ID was not found. Folder links are not audio files.');
  const target=new URL('https://drive.usercontent.google.com/download');target.searchParams.set('id',id);target.searchParams.set('export','download');target.searchParams.set('confirm','t');
  if(u.searchParams.has('resourcekey'))target.searchParams.set('resourcekey',u.searchParams.get('resourcekey'));
  return target;
 }
 if(provider==='dropbox'){
  if(!['dropbox.com','www.dropbox.com','dl.dropboxusercontent.com'].includes(u.hostname)||!/^\/(s|scl\/fi)\//.test(u.pathname))throw Error('Use a Dropbox file sharing link.');
  u.searchParams.delete('raw');u.searchParams.set('dl','1');return u;
 }
 throw Error('Unsupported cloud provider.');
}
export function allowedCloudHost(provider,host){
 if(provider==='drive')return host==='drive.google.com'||host==='drive.usercontent.google.com'||host==='googleusercontent.com'||host.endsWith('.googleusercontent.com');
 return provider==='dropbox'&&(host==='dropbox.com'||host==='www.dropbox.com'||host==='dropboxusercontent.com'||host.endsWith('.dropboxusercontent.com'));
}
