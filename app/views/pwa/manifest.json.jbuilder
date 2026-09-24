# What makes the site installable. On iPhone and iPad, installing it — Share, then
# "Agregar a pantalla de inicio" — is the only way the site can receive Web Push, and
# iOS requires `display: standalone` for that.
json.name t("app.name")
json.short_name t("app.name")
json.description t("app.tagline")
json.lang I18n.locale
json.id "/"
json.start_url "/"
json.scope "/"
json.display "standalone"
# The cream ground token, so the splash screen and title bar match the first paint.
json.theme_color "#fffcf5"
json.background_color "#fffcf5"
json.icons [
  { src: "/icon-192.png", type: "image/png", sizes: "192x192", purpose: "any" },
  { src: "/icon-512.png", type: "image/png", sizes: "512x512", purpose: "any" },
  { src: "/icon-maskable-512.png", type: "image/png", sizes: "512x512", purpose: "maskable" }
]
