# Unset outside production is fine: development then writes mail to tmp/mails instead.
Resend.api_key = ENV["RESEND_API_KEY"].presence
