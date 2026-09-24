# The marketing host (SiteHosts.landing) is for visitors who are not signed in. A student
# who is signed in is sent to the same page on the app host, where the header, the checkout
# buttons and every form belong: a form posted from the marketing host would carry that
# host's CSRF token to the app host and be refused.
module LandingHost
  extend ActiveSupport::Concern

  included do
    before_action :send_signed_in_to_app_host, if: :landing_host?
    helper_method :landing_host?, :app_host_url, :landing_root_url
  end

  private

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
