module BillingHelper
  # "$1,099". Explicit format because rails-i18n's `es` currency is Spain's ("1.099 €").
  def money(amount)
    number_to_currency(
      amount, unit: "$", format: "%u%n", precision: amount.to_d.frac.zero? ? 0 : 2,
      delimiter: ",", separator: "."
    )
  end
end
