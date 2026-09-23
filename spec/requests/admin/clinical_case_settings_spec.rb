require "rails_helper"

RSpec.describe "Correcting a case's setting", type: :request do
  let(:reviewer) { create(:user, role: "reviewer") }
  let!(:emergency) { create(:emergency_setting) }
  let!(:family) { create(:family_medicine_setting) }
  let(:clinical_case) { create(:published_case, setting: emergency) }

  def sign_in(user)
    post session_path, params: { email: user.email, password: "contrasena-segura" }
  end

  it "shows the case's setting on the review screen, with every context and unknown to choose from" do
    sign_in(reviewer)

    get review_clinical_case_path(clinical_case)

    page = Nokogiri::HTML(response.body)
    buttons = page.css("form[action='#{admin_clinical_case_setting_path(clinical_case)}'] button")
    expect(buttons.map(&:text).map(&:squish)).to eq(
      ["Urgencias", "Medicina Familiar", I18n.t("admin.clinical_cases.setting.unknown")]
    )
    expect(buttons.map { |button| button["aria-pressed"] }).to eq(%w[true false false])
  end

  it "lets a reviewer move a case to another context and back to the review screen" do
    sign_in(reviewer)

    patch admin_clinical_case_setting_path(clinical_case), params: { setting_id: family.id },
      headers: { "HTTP_REFERER" => review_clinical_case_url(clinical_case) }

    expect(clinical_case.reload.setting).to eq(family)
    expect(response).to redirect_to(review_clinical_case_url(clinical_case))
    expect(flash[:notice]).to eq(I18n.t("admin.clinical_cases.setting.done", setting: "Medicina Familiar"))
  end

  it "lets a reviewer say the setting is unknown" do
    sign_in(reviewer)

    patch admin_clinical_case_setting_path(clinical_case), params: { setting_id: "" }

    expect(clinical_case.reload.setting).to be_nil
    expect(response).to redirect_to(review_clinical_case_path(clinical_case))
    expect(flash[:notice]).to include(I18n.t("admin.clinical_cases.setting.unknown"))
  end

  it "never files a case's setting under a troncal" do
    sign_in(create(:user, :admin))

    patch admin_clinical_case_setting_path(clinical_case), params: { setting_id: create(:specialty).id }

    expect(response).to have_http_status(:not_found)
    expect(clinical_case.reload.setting).to eq(emergency)
  end

  it "is a 404 to a student" do
    sign_in(create(:user))

    patch admin_clinical_case_setting_path(clinical_case), params: { setting_id: family.id }

    expect(response).to have_http_status(:not_found)
    expect(clinical_case.reload.setting).to eq(emergency)
  end
end
