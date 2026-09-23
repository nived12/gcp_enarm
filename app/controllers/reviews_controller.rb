# Everything due again today: the missed cases the schedule brings back, and pearls.
class ReviewsController < ApplicationController
  def index
    @summary = Reviews::DueSummary.for(Current.user)
  end
end
