// NORI service worker: shows the emergency push notification, focuses/opens
// the app when the person taps it, and caches the (static) app shell as an
// OFFLINE FALLBACK. Actual data (Supabase) is never cached here — those
// requests go to a different origin, which the fetch handler below leaves
// completely untouched, so the app still always talks to a live Supabase
// connection for anything that matters (alarms, messages, contacts, ...).
// Network-first, not cache-first: every open tries a fresh fetch first
// (normally just as fast as before, since it's a small single file on a
// working connection) and only falls back to the cached copy when that
// fetch fails — e.g. genuinely offline or on a very bad connection. A
// cache-first / stale-while-revalidate strategy was tried here first, but
// that meant a freshly shipped fix only ever showed up on someone's SECOND
// open after a deploy (the first open still served the old cached shell)
// — confusing during active development, and in an emergency app "shows
// the version that was actually just fixed" matters more than shaving a
// few ms off an already-fast load on a normal connection.
const SHELL_CACHE = 'nori-shell-v2-uitlegvideo';
const SHELL_ASSETS = ['./', './noodalarm.html', './manifest.json', './icon-192.png', './icon-512.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE)
      .then((cache) => cache.addAll(SHELL_ASSETS))
      .catch(() => {}) // een enkel mislukt asset (bv. offline install) mag de rest niet blokkeren
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== SHELL_CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  // Nooit Supabase (of enige andere cross-origin) request aanraken — alleen
  // onze eigen statische bestanden lopen via deze cache.
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;
  event.respondWith(
    fetch(req).then((resp) => {
      if (resp && resp.ok) caches.open(SHELL_CACHE).then((cache) => cache.put(req, resp.clone()));
      return resp;
    }).catch(() => caches.match(req))
  );
});

self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) { /* ignore malformed payload */ }

  const title = data.title || '🚨 NORI';
  const options = {
    body: data.body || 'Een noodcontact heeft een noodalarm geactiveerd.',
    icon: 'icon-192.png?v=2',
    badge: 'icon-192.png?v=2',
    requireInteraction: true,
    // silent:false + een lang, zwaar vibratiepatroon is het luidst/dwingendst
    // wat een webmelding kan zijn — de stille-stand/mute-knop van het
    // toestel blijft altijd de baas over daadwerkelijk geluid, dat kan geen
    // website omzeilen (bewuste OS-grens, niet iets wat wij kunnen fixen).
    silent: false,
    vibrate: [500, 200, 500, 200, 500, 200, 500, 200, 500],
    tag: 'noodalarm-' + Date.now(),
    data: { alarmId: data.alarmId || null },
    // Rechtstreeks vanaf de melding reageren, zonder de app te hoeven
    // openen — alleen zinvol bij een écht alarm, niet bij een oefening.
    // De labels komen al vertaald mee in de payload (in de taal van DEZE
    // ontvanger) — de service worker kent zelf geen taalvoorkeur.
    actions: data.alarmId && !data.testMode ? [
      { action: 'omw', title: data.actionOmwLabel || '✅ Ik kom eraan' },
      { action: 'call112', title: data.actionCall112Label || '📞 Bel 112' }
    ] : []
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const alarmId = event.notification.data && event.notification.data.alarmId;
  const action = event.action;

  // "Bel 112" heeft niets met de app zelf te maken — direct het belscherm
  // openen, geen reden om onze eigen app ook nog te focussen/openen.
  if (action === 'call112') {
    event.waitUntil(self.clients.openWindow('tel:112'));
    return;
  }

  const messageType = action === 'omw' ? 'omw' : 'open-chat';
  const urlParam = action === 'omw' ? 'omw' : 'chat';
  const targetPath = alarmId ? ('./?' + urlParam + '=' + alarmId) : './';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          client.focus();
          if (alarmId) client.postMessage({ type: messageType, alarmId });
          return;
        }
      }
      if (self.clients.openWindow) return self.clients.openWindow(targetPath);
    })
  );
});
