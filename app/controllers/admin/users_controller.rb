# Looking up an account for a support request, and the two things an admin changes on
# one: its role and its granted-premium window.
module Admin
  class UsersController < BaseController
    before_action :require_admin
    before_action :set_user, only: %i[show update]

    LIMIT = 25

    def index
      @query = params[:q].to_s.strip
      users = User.order(created_at: :desc).limit(LIMIT)
      if @query.present?
        pattern = "%#{User.sanitize_sql_like(@query)}%"
        users = users.where(
          "email ILIKE :pattern OR concat_ws(' ', first_name, last_name) ILIKE :pattern",
          pattern: pattern
        )
      end
      @users = users
    end

    def show; end

    def update
      until_date = parse_date(params.dig(:user, :granted_premium_until))
      if until_date == :invalid
        flash.now[:alert] = t("admin.users.invalid_date")
        return render(:show, status: :unprocessable_content)
      end

      @user.update!(granted_premium_until: until_date, role: new_role)
      redirect_to admin_user_path(@user), notice: t("admin.users.saved"), status: :see_other
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    # An admin cannot change their own role: one mistaken tap would lock the only admin
    # out of the screen that could undo it.
    def new_role
      return @user.role if @user == Current.user

      params.dig(:user, :role).presence_in(User.roles.keys) || @user.role
    end

    # Premium runs to the end of the day chosen, so "hasta el 31" includes the 31st.
    def parse_date(value)
      return if value.blank?

      Date.iso8601(value).end_of_day
    rescue Date::Error
      :invalid
    end
  end
end
