import ssh2 from 'ssh2';
import { createHash, generateKeyPairSync, createPrivateKey } from 'node:crypto';
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
const hostKey = ssh2.utils.generateKeyPairSync('ed25519').private;
const hostParsed = ssh2.utils.parseKey(hostKey);
const fingerprint = `SHA256:${createHash('sha256').update(hostParsed.getPublicSSH()).digest('base64').replace(/=+$/, '')}`;
const password = 'temporary-test-password';
const passphrase = 'temporary-test-passphrase';
const ed = ssh2.utils.generateKeyPairSync('ed25519').private;
const encryptedEd = ssh2.utils.generateKeyPairSync('ed25519',{cipher:'aes256-ctr',passphrase,rounds:4}).private;
const rsa = generateKeyPairSync('rsa',{modulusLength:2048,privateKeyEncoding:{type:'pkcs8',format:'pem',cipher:'aes-256-cbc',passphrase},publicKeyEncoding:{type:'spki',format:'pem'}}).privateKey;
const ec = generateKeyPairSync('ec',{namedCurve:'prime256v1',privateKeyEncoding:{type:'pkcs8',format:'pem'},publicKeyEncoding:{type:'spki',format:'pem'}}).privateKey;
const encryptedRsa = generateKeyPairSync('rsa',{modulusLength:2048,privateKeyEncoding:{type:'pkcs1',format:'pem',cipher:'aes-256-cbc',passphrase},publicKeyEncoding:{type:'spki',format:'pem'}}).privateKey;
const auths = [{label:'password',authMethod:'password',password},{label:'Ed25519',authMethod:'key',privateKey:ed},{label:'encrypted Ed25519',authMethod:'key',privateKey:encryptedEd,passphrase},{label:'encrypted RSA PKCS8',authMethod:'key',privateKey:rsa,passphrase},{label:'EC PKCS8',authMethod:'key',privateKey:ec},{label:'encrypted RSA PEM',authMethod:'key',privateKey:encryptedRsa,passphrase}];
const publicKeys = auths.filter(a=>a.authMethod==='key').map(a=> {
 let key=a.privateKey;
 if(key.includes('BEGIN PRIVATE KEY')||key.includes('BEGIN ENCRYPTED PRIVATE KEY')) {
   const parsed=createPrivateKey({key,passphrase:a.passphrase});key=parsed.export({type:parsed.asymmetricKeyType==='rsa'?'pkcs1':'sec1',format:'pem'});
 }
 return ssh2.utils.parseKey(key,a.passphrase);
});
const sockets = new Set();
const server = new ssh2.Server({hostKeys:[hostKey]},client=> {
 sockets.add(client);client.on('close',()=>sockets.delete(client));client.on('error',()=>{});
 client.on('authentication',ctx=> {
   if(ctx.username!=='root')return ctx.reject();
   if(ctx.method==='password'&&ctx.password===password)return ctx.accept();
   if(ctx.method==='publickey') {
     const key=publicKeys.find(k=>k.getPublicSSH().equals(ctx.key.data));
     if(key&&(!ctx.signature||key.verify(ctx.blob,ctx.signature,ctx.hashAlgo)===true))return ctx.accept();
   }
   ctx.reject();
 });
 client.on('ready',()=>client.on('session',accept=> {
   accept().on('exec',(acceptCommand, reject, info)=> {
     assert.match(info.command,/exec \/bin\/bash -s/);
     const stream=acceptCommand();let script='';
     stream.on('data',chunk=>script+=chunk.toString());
     stream.on('end',()=> {
       if(script==='hang')return;
       stream.stderr.write('secret-stderr-must-not-leak');
       stream.write(script==='large'?'x'.repeat(130*1024):'fixture-中文-ok');
       stream.exit(script==='sudo'?77:0);stream.end();
     });
   });
 }));
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
try {
 const direct=process.env.DART_COMMAND;
 const child=spawn(direct||'fvm', [...(direct?[]:['dart']),'run','tool/ssh_smoke.dart'],{stdio:['pipe','inherit','inherit'],shell:process.platform==='win32'});
 child.stdin.end(JSON.stringify({port:server.address().port,fingerprint,auths}));
 const timer=setTimeout(()=>child.kill('SIGTERM'),120000);
 const code=await new Promise(resolve=>child.on('exit',resolve));clearTimeout(timer);
 if(code!==0)throw new Error(`Dart SSH smoke failed: ${code}`);
} finally {
 for(const socket of sockets)socket.end();
 await new Promise(resolve=>server.close(resolve));
}
