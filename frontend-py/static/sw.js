

const VERSION = 'sgit-1.3.0';
const PRECARGA = ['/offline', '/static/icon-192.png', '/static/icon.svg', '/static/tema.js', '/static/fonts/space-grotesk-latin-wght-normal.woff2', '/static/fonts/manrope-latin-wght-normal.woff2'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(PRECARGA)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((claves) => Promise.all(claves.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const r = e.request;
  if (r.method !== 'GET') return;
  const url = new URL(r.url);
  if (url.origin !== self.location.origin) return;

  if (url.pathname.startsWith('/static/')) {
    
    e.respondWith(caches.open(VERSION).then(async (c) => {
      const guardado = await c.match(r);
      const red = fetch(r).then((x) => { if (x.ok) c.put(r, x.clone()); return x; }).catch(() => guardado);
      return guardado || red;
    }));
    return;
  }
  if (r.mode === 'navigate') {
    
    e.respondWith(fetch(r).catch(() => caches.match('/offline')));
  }
});
