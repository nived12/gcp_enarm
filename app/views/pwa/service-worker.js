// Here only for Web Push. There is deliberately no fetch handler: nothing is cached, and
// every page still comes from the network exactly as it did before the worker existed.

// Every push must show a notification. Safari revokes the subscription of a site that
// receives pushes without showing one, and Chrome shows a generic one in its place.
self.addEventListener("push", (event) => {
  const data = event.data ? event.data.json() : {}

  event.waitUntil(
    self.registration.showNotification(data.title || "GPCEnarm", {
      body: data.body,
      icon: "/icon-192.png",
      lang: "es",
      // One tag for every reminder: a new one replaces an unread old one instead of
      // stacking up in the notification centre.
      tag: "gpcenarm-reminder",
      data: { path: data.path || "/" }
    })
  )
})

// Take charge of pages already open, so a notification tap can steer one of them
// instead of opening a second window.
self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim())
})

// Reuse an open GPCEnarm window when there is one; navigate() refuses a window this
// worker does not control, and then a new one opens instead.
self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const path = event.notification.data.path

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((windows) => {
      const open = windows[0]
      if (!open) return clients.openWindow(path)

      return open.focus().then((client) => client.navigate(path)).catch(() => clients.openWindow(path))
    })
  )
})
