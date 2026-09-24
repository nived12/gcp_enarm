class HomeController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    return if authenticated?

    @sample = LandingSample.draw(params[:caso])
    @stats = LandingStats.current
  end
end
