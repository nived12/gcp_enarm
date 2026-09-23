# The student's own access window, purchase history and time zone.
class AccountsController < ApplicationController
  def show
    @user = Current.user
    @entitlements = @user.entitlements.recent
    @checkout_returned = params[:checkout] == "success"
  end

  # Only the time zone is edited here: the study day, the streak and the free allowance
  # all end at 4 a.m. in it.
  def update
    if Current.user.update(time_zone: params.expect(:time_zone))
      redirect_to account_path, notice: t("time_zones.updated"), status: :see_other
    else
      redirect_to account_path, alert: t("time_zones.invalid"), status: :see_other
    end
  end
end
