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
end
