// Service worker del SGIT (PWA). Los datos del taller NUNCA se guardan en el dispositivo:
// solo se guardan los archivos estaticos y una pantalla de aviso para cuando no hay conexion.
const VERSION = 'sgit-1.1.0';
const PRECARGA = ['/offline', '/static/icon-192.png', '/static/icon.svg'];

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
    // Estaticos: se sirven desde el dispositivo y se actualizan en segundo plano (ahorra ancho de banda).
    e.respondWith(caches.open(VERSION).then(async (c) => {
      const guardado = await c.match(r);
      const red = fetch(r).then((x) => { if (x.ok) c.put(r, x.clone()); return x; }).catch(() => guardado);
      return guardado || red;
    }));
    return;
  }
  if (r.mode === 'navigate') {
    // Paginas con datos: siempre de la red. Sin conexion se muestra un aviso claro; nunca se guardan.
    e.respondWith(fetch(r).catch(() => caches.match('/offline')));
  }
});
