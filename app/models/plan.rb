# The four prepaid access windows, identified by our own code. Prices are MXN and live
# here, not in a provider's dashboard: the pricing page and the charge read the same
# number, so they cannot drift apart. A provider maps a code to whatever it needs.
#
# Windows never auto-renew. That is a product rule, not a default — see the plan.
class Plan < Data.define(:code, :months, :price)
  CURRENCY = "MXN".freeze

  CATALOG = {
    "one_month" => { months: 1, price: 199 },
    "three_months" => { months: 3, price: 449 },
    "six_months" => { months: 6, price: 749 },
    "twelve_months" => { months: 12, price: 1_099 }
  }.freeze

  def self.all
    CATALOG.map { |code, attributes| new(code: code, **attributes) }
  end

  def self.find(code)
    attributes = CATALOG[code.to_s]
    new(code: code.to_s, **attributes) if attributes
  end

  def self.codes
    CATALOG.keys
  end

  # Whole pesos, rounded, because "≈ $92 al mes" is a comparison, not a charge.
  def monthly_price
    (price.to_d / months).round
  end

  def amount_in_cents
    price * 100
  end

  def currency
    CURRENCY
  end
end
