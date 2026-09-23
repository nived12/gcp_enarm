module AdminHelper
  # Four decimals: a verification call costs a fraction of a cent, and rounding it to
  # cents would show most runs as free. Separators come from number.format, which es.yml
  # sets to Mexican notation; rails-i18n's es currency format would write Spain's.
  def usd(amount)
    number_to_currency(
      amount, unit: "US$", format: "%u%n", precision: 4,
      separator: t("number.format.separator"), delimiter: t("number.format.delimiter")
    )
  end

  # A bar's share of the widest one, for plain CSS bars.
  def bar_percent(value, max)
    return 0 unless max.positive?

    (100.0 * value / max).round(1)
  end

  # The sections of /admin a user may open, in the order the nav shows them.
  def admin_sections
    sections = { dashboard: admin_root_path, clinical_cases: admin_clinical_cases_path,
                 question_reports: admin_question_reports_path }
    return sections unless Current.user.role_admin?

    sections.merge(costs: admin_costs_path, ingestion: admin_ingestion_path, users: admin_users_path)
  end
end
