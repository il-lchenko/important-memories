// Self-destructing Service Worker.
// Убивает себя + все кэши + перезагружает клиента.
// Deploy как /sw.js на VPS чтобы вычистить старые SW у пользователей.
self.addEventListener('install', function() {
  self.skipWaiting();
});
self.addEventListener('activate', function(event) {
  event.waitUntil(
    (async function(){
      try {
        var keys = await caches.keys();
        await Promise.all(keys.map(function(k){ return caches.delete(k); }));
      } catch(e) {}
      try { await self.registration.unregister(); } catch(e) {}
      var clients = await self.clients.matchAll({type:'window'});
      clients.forEach(function(c){ c.navigate(c.url); });
    })()
  );
});
self.addEventListener('fetch', function() {
  // Не перехватываем — пусть браузер сам делает fetch к nginx
});
