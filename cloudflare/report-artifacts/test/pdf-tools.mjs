import{createCanvas,DOMMatrix,ImageData,Path2D}from'@napi-rs/canvas';
globalThis.DOMMatrix??=DOMMatrix;globalThis.ImageData??=ImageData;globalThis.Path2D??=Path2D;
const pdfjs=await import('pdfjs-dist/legacy/build/pdf.mjs');
export async function loadPdf(bytes){return pdfjs.getDocument({data:new Uint8Array(bytes),disableWorker:true,useSystemFonts:false,isEvalSupported:false}).promise}
export async function renderPages(bytes,scale=1){const doc=await loadPdf(bytes),out=[];for(let i=1;i<=doc.numPages;i++){const page=await doc.getPage(i),viewport=page.getViewport({scale}),canvas=createCanvas(Math.ceil(viewport.width),Math.ceil(viewport.height)),context=canvas.getContext('2d');await page.render({canvasContext:context,viewport,canvas}).promise;out.push(canvas)}return out}
export async function extractedText(bytes){const doc=await loadPdf(bytes),parts=[];for(let i=1;i<=doc.numPages;i++){const content=await(await doc.getPage(i)).getTextContent();parts.push(content.items.map(x=>'str'in x?x.str:'').join(' '))}return parts.join('\n')}
