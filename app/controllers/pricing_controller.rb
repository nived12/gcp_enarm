# The four prepaid windows. Public: a classmate sent the link, and nobody should have
# to make an account to see what it costs.
class PricingController < ApplicationController
  allow_unauthenticated_access only: :show
  allow_unverified_email only: :show

  def show
    @plans = Plan.all
    @checkout_available = Billing::StripeAdapter.checkout_available?
    # The plan a visitor picked before signing up, brought back by return_to.
    @chosen_plan = Plan.find(params[:plan])&.code
  end
end
