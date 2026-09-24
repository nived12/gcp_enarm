# Read by the push handler in app/views/pwa/service-worker.js.
json.title message[:title]
json.body message[:lines].join(" ")
json.path message[:path]
