# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# The Tailwind source is an input to the css build, not an asset. Propshaft
# serves everything under its load path, and `@import "tailwindcss"` means
# nothing to a browser — without this the raw source ships alongside the
# compiled bundle. Only app/assets/builds/application.css is served.
Rails.application.config.assets.excluded_paths << Rails.root.join("app/assets/stylesheets")
