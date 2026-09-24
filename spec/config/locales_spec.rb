require "rails_helper"

# es.yml and en.yml drift the moment one of them is edited alone, and the failure is
# silent: a missing key renders as "translation missing" in production only.
RSpec.describe "locale files" do
  def flatten_keys(hash, prefix = nil)
    hash.flat_map do |key, value|
      path = [prefix, key].compact.join(".")
      value.is_a?(Hash) ? flatten_keys(value, path) : [path]
    end
  end

  let(:es) { YAML.load_file(Rails.root.join("config/locales/es.yml")).fetch("es") }
  let(:en) { YAML.load_file(Rails.root.join("config/locales/en.yml")).fetch("en") }

  it "defines exactly the same keys in both languages" do
    expect(flatten_keys(es).sort).to eq(flatten_keys(en).sort)
  end

  it "defaults to Spanish" do
    expect(I18n.default_locale).to eq(:es)
  end

  # The landing page's whole claim is that a question never exists without the span it
  # was generated from. The same invariant Phase 2 enforces on generated questions has
  # to hold for the shop window: the highlight is part of the quote, not a gloss on it.
  %i[es en].each do |locale|
    it "highlights a span that is really inside the sample recommendation (#{locale})" do
      html = I18n.t("landing.anatomy.recommendation_html", locale: locale)
      highlighted = html[%r{<mark>(.*?)</mark>}, 1]

      expect(highlighted).to be_present
      expect(html.gsub(%r{</?mark>}, "")).to include(highlighted)
    end
  end
end
