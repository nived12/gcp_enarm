# The marketing host (SiteHosts.landing) shows the landing page and the legal pages to
# anyone, signed in or not; the owner wants to be able to read them from an account. A page
# that holds a form is different: posted from the marketing host it would carry that host's
# CSRF token to the app host and be refused. So a signed-in student asking for such a page
# (the prices, with their checkout buttons) is sent to the same page on the app host.
module LandingHost
  extend ActiveSupport::Concern

  included do
    before_action :send_signed_in_to_app_host, if: :landing_host?, unless: :readable_signed_in?
    helper_method :landing_host?, :app_host_url, :landing_root_url
  end

  private

  # Pages without a form, which a signed-in reader may see on the marketing host.
  def readable_signed_in?
    (controller_name == "home" || controller_name == "legal") && action_name == "show"
  end

  def landing_host?
    SiteHosts.landing?(request)
  end

  # A path on the app host: absolute while the hosts are split, unchanged otherwise.
  def app_host_url(path)
    SiteHosts.split? ? "#{request.protocol}#{SiteHosts.app}#{path}" : path
  end

  def landing_root_url
    SiteHosts.split? ? "#{request.protocol}#{SiteHosts.landing}/" : root_path
  end

  # Temporary, unlike AppHostRedirect: the same address shows the landing page again once
  # the student signs out.
  def send_signed_in_to_app_host
    redirect_to app_host_url(request.fullpath), allow_other_host: true if authenticated?
  end
end
