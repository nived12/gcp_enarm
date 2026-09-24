class ApplicationMailer < ActionMailer::Base
  # The address must be on a domain verified in Resend, or every send is refused.
  default from: ENV.fetch("MAILER_FROM", "GPCEnarm <no-responder@gpcenarm.com>"),
    reply_to: ENV.fetch("MAILER_REPLY_TO", "GPCEnarm <soporte@gpcenarm.com>")
  layout "mailer"
end
