# Correcting where a case happens. Any reviewer may: the setting decides which areas count
# the case — coverage, the specialty filter, a context's study days — and never what a
# student reads, so it is filing, like the topic, not a decision about the bank.
#
# Only the three contexts or unknown; a troncal id is a 404, not a validation message,
# since the form never offers one.
module Admin
  class ClinicalCaseSettingsController < BaseController
    def update
      clinical_case = ClinicalCase.find(params[:clinical_case_id])
      setting = Specialty.kind_cross_cutting.find(params[:setting_id]) if params[:setting_id].present?
      clinical_case.update!(setting: setting)

      redirect_back_or_to review_clinical_case_path(clinical_case),
        notice: t(
          "admin.clinical_cases.setting.done",
          setting: setting&.name || t("admin.clinical_cases.setting.unknown")
        ),
        status: :see_other
    end
  end
end
