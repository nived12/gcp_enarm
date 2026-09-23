# Where a free student lands after using today's allowance: the pricing page, with the
# reason on top. Nothing is lost — an unfinished exam waits for tomorrow or for a window.
module UpgradePath
  extend ActiveSupport::Concern

  private

  def daily_limit_reached?(result)
    result.errors.of_kind?(:base, :daily_limit_reached)
  end

  def redirect_to_upgrade(result)
    Analytics.capture(Current.user, "daily_limit_reached")
    redirect_to pricing_path, notice: result.errors.full_messages.to_sentence, status: :see_other
  end
end
