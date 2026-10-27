// Synthetic conformance samples; no camera photos or copyrighted footage.
const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const out = path.resolve(__dirname, '../testdata/photo_media');
fs.mkdirSync(out, {recursive:true});
const ffmpeg = process.env.FFMPEG_FIXTURE_ENCODER || 'ffmpeg';
function run(args) { execFileSync(ffmpeg, ['-v','error','-y',...args], {stdio:'inherit'}); }
function box(type, ...parts) {
  const body = Buffer.concat(parts); const head=Buffer.alloc(8);
  head.writeUInt32BE(body.length+8); head.write(type,4); return Buffer.concat([head,body]);
}
function boxes(bytes) {
  const result=[];
  for(let p=0;p+8<=bytes.length;) {
    const n=bytes.readUInt32BE(p); if(n<8||p+n>bytes.length) throw Error('box bounds');
    result.push({type:bytes.toString('ascii',p+4,p+8),bytes:bytes.subarray(p,p+n)}); p+=n;
  }
  return result;
}
run(['-f','lavfi','-i','color=c=orange:s=96x64','-frames:v','1',path.join(out,'cover.jpg')]);
for(const [name,encoder,extra] of [
  ['h264','libx264',['-preset','fast','-bf','2']],
  ['hevc','libx265',['-x265-params','log-level=error:pools=1:frame-threads=1']],
  ['av1','libaom-av1',['-cpu-used','8']],
]) {
  run(['-f','lavfi','-i','testsrc2=s=96x64:r=12:d=2','-f','lavfi','-i','sine=frequency=440:duration=2',
    '-c:v',encoder,...extra,'-pix_fmt','yuv420p','-c:a','aac','-shortest',path.join(out,name+'.mp4')]);
}
run(['-f','lavfi','-i','testsrc2=s=96x64:r=12:d=2',
  '-f','lavfi','-i','color=c=0x808080:s=96x64:r=12:d=2',
  '-f','lavfi','-i','color=c=white:s=96x64:r=12:d=2',
  '-map','0:v','-map','1:v','-map','2:v','-c:v','libx265',
  '-x265-params','log-level=error:pools=1:frame-threads=1', '-tag:v','hvc1','-f','mp4',path.join(out,'aux.mp4')]);
const cover=fs.readFileSync(path.join(out,'cover.jpg'));
function jpeg(name,video,properties='',padding=Buffer.alloc(0),tail=Buffer.alloc(0)) {
  const xml='<x:xmpmeta xmlns:x="adobe:ns:meta/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:GCamera="http://ns.google.com/photos/1.0/camera/" xmlns:Container="http://ns.google.com/photos/1.0/container/" xmlns:Item="http://ns.google.com/photos/1.0/container/item/"><rdf:RDF><rdf:Description '+properties+'/></rdf:RDF></x:xmpmeta>';
  const data=Buffer.concat([Buffer.from('http://ns.adobe.com/xap/1.0/\0'),Buffer.from(xml)]);
  const app=Buffer.alloc(4);app[0]=255;app[1]=225;app.writeUInt16BE(data.length+2,2);
  fs.writeFileSync(path.join(out,name),Buffer.concat([cover.subarray(0,2),app,data,cover.subarray(2),padding,video,tail]));
}
for(const codec of ['h264','hevc','av1']) {
  const video=fs.readFileSync(path.join(out,codec+'.mp4'));
  jpeg('motion-'+codec+'.jpg',video,'GCamera:MicroVideo="1" GCamera:MicroVideoOffset="'+video.length+'"');
}
const video=fs.readFileSync(path.join(out,'hevc.mp4'));
run(['-i',path.join(out,'hevc.mp4'),'-f','lavfi','-i','sine=frequency=880:duration=2',
  '-map','0:v','-map','0:a','-map','1:a','-c:v','copy','-c:a:0','copy',
  '-c:a:1','libopus','-ac:a:1','2',path.join(out,'multi.mp4')]);
const multi=fs.readFileSync(path.join(out,'multi.mp4'));
jpeg('motion-multiple-audio.jpg',multi,'GCamera:MicroVideoOffset="'+multi.length+'"');
run(['-itsoffset','0.5','-i',path.join(out,'hevc.mp4'),'-i',path.join(out,'hevc.mp4'),
  '-map','0:v','-map','1:a','-c','copy',path.join(out,'offset.mp4')]);
const offset=fs.readFileSync(path.join(out,'offset.mp4'));
jpeg('motion-offset.jpg',offset,'GCamera:MicroVideoOffset="'+offset.length+'"');
// Modern Container directory, primary padding, and a non-video trailing item.
const directory='<Container:Directory><rdf:Seq><rdf:li><Container:Item Item:Semantic="Primary" Item:Mime="image/jpeg" Item:Length="0" Item:Padding="8"/></rdf:li><rdf:li><Container:Item Item:Semantic="MotionPhoto" Item:Mime="video/mp4" Item:Length="'+video.length+'"/></rdf:li><rdf:li><Container:Item Item:Semantic="GainMap" Item:Length="12"/></rdf:li></rdf:Seq></Container:Directory>';
jpeg('motion-directory.jpg',video,'GCamera:MotionPhoto="1"',Buffer.alloc(8),Buffer.alloc(12));
let modern=fs.readFileSync(path.join(out,'motion-directory.jpg'));
// Rebuild APP1 with nested properties rather than an attribute-only Description.
const appEnd=4+modern.readUInt16BE(4);
const xml=Buffer.from('http://ns.adobe.com/xap/1.0/\0<x:xmpmeta xmlns:x="adobe:ns:meta/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:Container="http://ns.google.com/photos/1.0/container/" xmlns:Item="http://ns.google.com/photos/1.0/container/item/">'+directory+'</x:xmpmeta>');
const app=Buffer.from([255,225,0,0]);app.writeUInt16BE(xml.length+2,2);
fs.writeFileSync(path.join(out,'motion-directory.jpg'),Buffer.concat([modern.subarray(0,2),app,xml,modern.subarray(appEnd)]));
jpeg('motion-samsung.jpg',video,'GCamera:MotionPhoto="1"',Buffer.from('MotionPhoto_Data'),Buffer.from('SEFT'));
function heif(input,output,aux=false) {
  const original=fs.readFileSync(path.join(out,input));
  const result=boxes(original).map(b=>{
    if(b.type==='ftyp') return box('ftyp',Buffer.from('msf1\0\0\0\0msf1hevc'));
    if(b.type!=='moov') return b.bytes;
    let index=0;
    return box('moov',...boxes(b.bytes.subarray(8)).map(t=> {
      if(t.type!=='trak')return t.bytes;
      const i=index++;
      const urn=Buffer.from(i===1?'urn:mpeg:hevc:2015:auxid:1\0':'urn:mpeg:hevc:2015:auxid:2\0');
      function mdia(bytes) {
        return box('mdia',...boxes(bytes.subarray(8)).map(c=>{
          if(c.type==='hdlr') { const copy=Buffer.from(c.bytes);copy.write(i===0?'pict':'auxv',16);return copy; }
          if(!aux||i===0||c.type!=='minf')return c.bytes;
          return box('minf',...boxes(c.bytes.subarray(8)).map(d=>d.type!=='stbl'?d.bytes:
            box('stbl',...boxes(d.bytes.subarray(8)).map(e=>e.type!=='stsd'?e.bytes:
              box('stsd',e.bytes.subarray(8,16),...boxes(e.bytes.subarray(16)).map(entry=>
                box(entry.type,entry.bytes.subarray(8),box('auxi',Buffer.alloc(4),urn))))))));
        }));
      }
      const children=boxes(t.bytes.subarray(8)).map(c=>c.type==='mdia'?mdia(c.bytes):c.bytes);
      if(!aux||i===0)return box('trak',...children);
      const reference=Buffer.alloc(4);reference.writeUInt32BE(1);
      return box('trak',...children,box('tref',box('auxl',reference)));
    }));
  });
  // ftyp length must stay unchanged to retain absolute chunk offsets.
  const ftyp=boxes(original)[0];
  result[0]=Buffer.from(ftyp.bytes);result[0].write('msf1',8);
  fs.writeFileSync(path.join(out,output),Buffer.concat(result));
}
heif('hevc.mp4','sequence.heic');
heif('aux.mp4','sequence-alpha-depth.heic',true);
run(['-i',path.join(out,'hevc.mp4'),'-map','0:v','-frames:v','1','-c','copy','-f','mp4',path.join(out,'single.mp4')]);
heif('single.mp4','single.heic');
fs.writeFileSync(path.join(out,'motion-heic.heic'),Buffer.concat([fs.readFileSync(path.join(out,'single.heic')),box('mpvd',video)]));
// Reuse exact synthetic HDR bitstreams from the playback profile research.
if(process.env.FFMPEG_RESEARCH_FIXTURES) for(const name of ['hevc-main10-pq-aac.mp4','hevc-main10-hlg-aac.mp4','av1-main10-pq-aac.mp4']) {
  const bytes=fs.readFileSync(path.join(process.env.FFMPEG_RESEARCH_FIXTURES,name));
  jpeg('motion-'+name.replace('.mp4','.jpg'),bytes,'GCamera:MicroVideoOffset="'+bytes.length+'"');
}
for(const name of ['h264.mp4','hevc.mp4','av1.mp4','aux.mp4','single.mp4','multi.mp4','offset.mp4'])fs.unlinkSync(path.join(out,name));
