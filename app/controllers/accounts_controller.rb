# The student's own access window and purchase history.
class AccountsController < ApplicationController
  def show
    @user = Current.user
    @entitlements = @user.entitlements.recent
    @checkout_returned = params[:checkout] == "success"
  end
end
