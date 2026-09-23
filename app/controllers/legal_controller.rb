# Términos, aviso de privacidad and refund policy. The route admits only LegalPage::NAMES.
class LegalController < ApplicationController
  allow_unauthenticated_access
  allow_unverified_email

  def show
    @page = LegalPage.new(params[:page])
  end
end
