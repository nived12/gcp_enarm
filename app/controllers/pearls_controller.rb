# Pearls: guideline statements as flashcards, ten to a session. The session is carried in
# the address (`step`) rather than stored — it only numbers the cards on screen; what is
# counted towards the streak is each graded card, on the student's study day.
class PearlsController < ApplicationController
  SESSION_SIZE = StudyDay::PEARLS_PER_SESSION

  def show
    @step = params[:step].to_i.clamp(0, SESSION_SIZE)
    if @step == SESSION_SIZE
      @streak = Stats::StreakCalculator.call(Current.user).payload
      return render(:done)
    end

    @pearl = Pearls::CardPicker.call(Current.user).payload
    @new_allowance_spent = @pearl.nil? && Pearl.new_allowance_spent?(Current.user)
  end

  # Only a statement in the pool, or one the student already holds a card for, can be
  # graded; anything else is not a pearl.
  def review
    recommendation = Recommendation.find(params.expect(:recommendation_id))
    held = ReviewCard.where(user: Current.user, recommendation: recommendation).exists?
    return head(:not_found) unless held || Pearl.pool.exists?(recommendation.id)

    result = Pearls::ReviewRecorder.call(Current.user, recommendation, grade: params[:grade])
    step = params[:step].to_i.clamp(0, SESSION_SIZE - 1)
    # A new card left open in another tab after the day's allowance ran out: back to
    # the same step, which now says so.
    if result.failure?
      return head(:unprocessable_content) unless result.errors.of_kind?(:base, :new_allowance_spent)

      return redirect_to(pearls_path(step: step), status: :see_other)
    end

    # Sent on the tenth grade rather than from the done page, which a reload shows again.
    Analytics.capture(Current.user, "pearls_session_finished") if step + 1 == SESSION_SIZE
    redirect_to pearls_path(step: step + 1), status: :see_other
  end
end
