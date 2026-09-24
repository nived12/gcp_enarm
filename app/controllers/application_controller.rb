class ApplicationController < ActionController::Base
  # Before Authentication, so a signed-in visitor on the marketing host is sent to the app
  # rather than to the email-verification page on a host that does not serve it.
  include LandingHost
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
end
