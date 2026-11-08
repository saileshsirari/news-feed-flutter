// Push notifications for the web app (Web Push, no Firebase).
//
// The browser runs this even when the app's tab is closed. Our server sends
// the message text encrypted for this browser only (the push service in
// between can't read it); the browser decrypts it and hands it here.
// Registered by lib/push/web_push_web.dart, with its own scope ("push/") so
// it never interferes with Flutter's own files.

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    // Not ours, or not JSON: show something generic rather than nothing.
  }
  event.waitUntil((async () => {
    // Looking at the app right now: it shows the message itself.
    const windows = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    if (windows.some((w) => w.focused && w.visibilityState === 'visible')) return;
    await self.registration.showNotification(data.title || 'News Feed', {
      body: data.body || 'New message',
      // One notification per chat, updated rather than piling up.
      tag: data.conversationId ? `conversation-${data.conversationId}` : undefined,
      renotify: true,
      icon: new URL('../icons/Icon-192.png', self.registration.scope).href,
      data: { conversationId: data.conversationId },
    });
  })());
});

// Tapping it brings the app forward (or opens it).
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const appUrl = new URL('../', self.registration.scope).href;
  event.waitUntil((async () => {
    const windows = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    const app = windows.find((w) => w.url.startsWith(appUrl));
    if (app) return app.focus();
    return clients.openWindow(appUrl);
  })());
});
