# Given names and surnames, which the name split of existing accounts could only guess at
# and a Google profile may have wrong.
class AccountNamesController < ApplicationController
  def update
    if Current.user.update(params.expect(user: %i[first_name last_name]))
      redirect_to account_path, notice: t("account_names.updated"), status: :see_other
    else
      redirect_to account_path, alert: Current.user.errors.full_messages.to_sentence, status: :see_other
    end
  end
end
