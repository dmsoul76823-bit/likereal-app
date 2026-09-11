/* LiReal 本地測試伺服器 — 純 Node，不需安裝任何套件
   啟動：node server.js   或直接雙擊「啟動本地伺服器.bat」 */
const http = require('http');
const fs   = require('fs');
const path = require('path');

const PORT = 8080;
const ROOT = __dirname;

const TYPES = {
  '.html':'text/html; charset=utf-8',
  '.js'  :'text/javascript; charset=utf-8',
  '.json':'application/json; charset=utf-8',
  '.css' :'text/css; charset=utf-8',
  '.svg' :'image/svg+xml',
  '.png' :'image/png',
  '.jpg' :'image/jpeg',
  '.jpeg':'image/jpeg',
  '.webp':'image/webp',
  '.ico' :'image/x-icon',
  '.txt' :'text/plain; charset=utf-8'
};

const server = http.createServer((req, res) => {
  let p;
  try { p = decodeURIComponent(new URL(req.url, 'http://x').pathname); }
  catch (e) { p = '/'; }

  if (p === '/')       p = '/index.html';
  if (p === '/admin')  p = '/lireal_admin.html';
  // 前台分頁路由：全部指向同一個檔案（由前端 router 決定顯示哪一頁）
  if (['/app','/programs','/live','/ai','/ticket','/shop','/vip','/about','/dining','/event'].indexOf(p) >= 0)
    p = '/lireal_platform.html';
  // 沒有副檔名時，自動補 .html（對應 Vercel 的 cleanUrls）
  if (!path.extname(p)) {
    const guess = path.join(ROOT, p + '.html');
    if (fs.existsSync(guess)) p = p + '.html';
  }

  // 防止跳出資料夾
  const safe = path.normalize(p).replace(/^([.][.][\\/])+/, '');
  const file = path.join(ROOT, safe);

  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end('<h1 style="font-family:sans-serif">404</h1><p style="font-family:sans-serif">找不到檔案：' + p + '</p>');
      console.log('404  ' + p);
      return;
    }
    res.writeHead(200, {
      'Content-Type': TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream',
      'Cache-Control': 'no-store'
    });
    res.end(data);
    console.log('200  ' + p);
  });
});

server.on('error', (e) => {
  if (e.code === 'EADDRINUSE') {
    console.log('\n  [!] 連接埠 ' + PORT + ' 已被佔用。');
    console.log('      可能是先前的伺服器還在跑，關掉那個視窗再試一次。\n');
  } else {
    console.log('\n  [!] 啟動失敗：' + e.message + '\n');
  }
});

server.listen(PORT, () => {
  console.log('');
  console.log('  ==========================================');
  console.log('    LiReal 本地測試伺服器已啟動');
  console.log('  ==========================================');
  console.log('');
  console.log('    首頁：http://localhost:' + PORT + '/');
  console.log('    前台：http://localhost:' + PORT + '/app');
  console.log('    後台：http://localhost:' + PORT + '/admin');
  console.log('');
  console.log('    按 Ctrl+C 停止');
  console.log('');
  // 自動開啟瀏覽器
  require('child_process').exec('start "" "http://localhost:' + PORT + '/"');
});
