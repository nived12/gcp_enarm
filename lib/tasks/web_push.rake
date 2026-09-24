namespace :web_push do
  desc "Print a new VAPID key pair for Web Push reminders"
  task :generate_keys do
    require "web_push"

    key = WebPush.generate_key
    puts "VAPID_PUBLIC_KEY=#{key.public_key}"
    puts "VAPID_PRIVATE_KEY=#{key.private_key}"
    puts "VAPID_SUBJECT=mailto:soporte@gpcenarm.com"
    warn "\nGenerate once per environment and keep it: a new pair orphans every browser that " \
         "subscribed with the old one, and those students stop getting reminders until they " \
         "turn notifications on again."
  end
end
