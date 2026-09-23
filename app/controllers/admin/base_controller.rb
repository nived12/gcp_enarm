# Everything under /admin. Plain controllers, authorised here rather than by a gem.
#
# Reviewers — the doctors reading generated cases — see the review queue and the
# students' reports and may act on them; spending, ingestion and accounts are the
# admin's alone. Anyone else gets the same 404 as a page that does not exist, so the
# admin surface is not advertised to students.
#
# Current.user is never nil here: Authentication has already redirected anyone not
# signed in.
module Admin
  class BaseController < ApplicationController
    before_action :require_staff

    private

    def require_staff
      render_not_found unless Current.user.role_admin? || Current.user.role_reviewer?
    end

    def require_admin
      render_not_found unless Current.user.role_admin?
    end

    def render_not_found
      render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
    end
  end
end
