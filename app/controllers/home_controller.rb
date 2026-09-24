class HomeController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    return if authenticated?
    # With the hosts split the landing page lives on the marketing host; the app's own
    # front door, for someone signed out, is the sign-in page.
    return redirect_to new_session_path if SiteHosts.split? && !landing_host?

    @sample = LandingSample.draw(params[:caso])
    @stats = LandingStats.current
  end
end
