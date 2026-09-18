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
    icon: 'icon-192.png',
    badge: 'icon-192.png',
    requireInteraction: true,
    vibrate: [200, 100, 200, 100, 200],
    tag: 'noodalarm-' + Date.now()
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow('./');
    })
  );
});
