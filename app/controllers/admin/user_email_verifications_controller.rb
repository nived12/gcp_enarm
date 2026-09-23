# For the student whose verification email never arrives: an admin who has confirmed the
# address another way — a support chat from it, say — marks it proven by hand.
module Admin
  class UserEmailVerificationsController < BaseController
    before_action :require_admin

    def create
      user = User.find(params[:user_id])
      user.verify_email!
      redirect_to admin_user_path(user), notice: t("admin.users.email.done"), status: :see_other
    end
  end
end
