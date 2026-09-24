# The two public hosts: LANDING_HOST (gpcenarm.com) shows the signed-out marketing pages,
# APP_HOST (app.gpcenarm.com) everything else. The split is on only when both are set, so
# development, the test suite and the Railway preview domain serve every page on one host.
#
# Read from Rails.configuration.x on every call rather than captured at boot, so a spec can
# turn the split on for one example.
module SiteHosts
  module_function

  def landing = Rails.configuration.x.landing_host
  def app = Rails.configuration.x.app_host

  def split?
    landing.present? && app.present?
  end

  def landing?(request)
    split? && request.host == landing
  end

  # The sign-in cookie is set on the parent domain so the landing page can tell a signed-in
  # visitor and send them to the app. Given as a list, Rails applies it only to a request on
  # that domain or below it and leaves the cookie host-only elsewhere (the Railway preview
  # domain), where a foreign domain would make the browser drop it.
  def cookie_domain
    [landing] if split?
  end
end
