#!/usr/bin/env node
'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const args = process.argv.slice(2);
function arg(name, fallback) { const i = args.indexOf('--' + name); return i >= 0 ? args[i + 1] : fallback; }
const root = path.resolve(arg('root', 'build/web'));
const segment = arg('base', 'ucheb_itog').replace(/^\/+|\/+$/g, '');
const prefix = segment ? '/' + segment + '/' : '/';
const port = Number(arg('port', '5560'));
const mime = {'.html':'text/html; charset=utf-8','.js':'application/javascript','.mjs':'application/javascript','.wasm':'application/wasm','.json':'application/json','.css':'text/css','.ttf':'font/ttf','.png':'image/png','.svg':'image/svg+xml'};
http.createServer((req,res) => {
  const url = new URL(req.url, 'http://localhost');
  res.setHeader('Cache-Control','no-store');
  if (prefix !== '/' && url.pathname === prefix.slice(0,-1)) { res.writeHead(302,{Location:prefix}).end();return; }
  if (!url.pathname.startsWith(prefix)) { res.writeHead(404).end('Not found');return; }
  let relative;
  try { relative=decodeURIComponent(url.pathname.slice(prefix.length)); }
  catch { res.writeHead(400).end();return; }
  let file=path.resolve(root,relative||'index.html');
  if (!file.startsWith(root+path.sep)) { res.writeHead(403).end();return; }
  if (!fs.existsSync(file)||!fs.statSync(file).isFile()) {
    if (path.extname(relative)) { res.writeHead(404).end('Not found');return; }
    file=path.join(root,'index.html');
  }
  res.setHeader('Content-Type',mime[path.extname(file)]||'application/octet-stream');
  fs.createReadStream(file).on('error',()=>{res.destroy();}).pipe(res);
}).listen(port,'127.0.0.1',()=>console.log(`Web: http://localhost:${port}${prefix}; SPA fallback enabled`));
