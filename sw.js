// NORI service worker: shows the emergency push notification and
// focuses/opens the app when the person taps it. No caching/offline logic —
// this app always needs a live connection to Supabase, so there is
// deliberately no fetch handler here.

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
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
    actions: data.alarmId && !data.testMode ? [
      { action: 'omw', title: '✅ Ik kom eraan' },
      { action: 'call112', title: '📞 Bel 112' }
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
