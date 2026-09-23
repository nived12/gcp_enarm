require "rails_helper"

RSpec.describe LegalPage do
  # A page missing in one language is a 500 for every visitor using it.
  LegalPage::NAMES.product(%i[es en]).each do |name, locale|
    it "has the #{name} page in #{locale}" do
      page = described_class.new(name, locale: locale)

      expect(page.path).to exist
      expect(page.to_html).to include("<h2>")
    end
  end

  it "reads the current locale by default" do
    expect(described_class.new("terms").path.basename.to_s).to eq("terms.es.md")
  end
end
