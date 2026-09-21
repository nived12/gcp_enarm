require "rails_helper"

RSpec.describe ReviewHelper, type: :helper do
  let(:text) { "Se recomienda realizar electrocardiograma de 12 derivaciones en diez minutos." }

  it "marks the quoted span inside the recommendation" do
    expect(helper.highlighted(text, "electrocardiograma de 12 derivaciones"))
      .to eq(
        "Se recomienda realizar <mark>electrocardiograma de 12 derivaciones</mark> " \
                     "en diez minutos."
      )
  end

  it "matches across a line break the model wrote as a space" do
    stored = "Se deben evitar:\nPicos hiperóxicos en el recién nacido."

    expect(helper.highlighted(stored, "Se deben evitar: Picos hiperóxicos"))
      .to include("<mark>Se deben evitar:\nPicos hiperóxicos</mark>")
  end

  it "ignores a difference in capitalisation" do
    expect(helper.highlighted(text, "se recomienda realizar")).to include("<mark>Se recomienda realizar</mark>")
  end

  it "returns the text untouched when there is no quote" do
    expect(helper.highlighted(text, nil)).to eq(text)
    expect(helper.highlighted(text, "  ")).to eq(text)
  end

  it "returns the text untouched when the quote is not in it" do
    expect(helper.highlighted(text, "angiografía coronaria")).to eq(text)
  end

  it "escapes markup in the source rather than rendering it" do
    result = helper.highlighted("Dosis de <b>5 mg</b> al día.", "<b>5 mg</b>")

    expect(result).to eq("Dosis de <mark>&lt;b&gt;5 mg&lt;/b&gt;</mark> al día.")
    expect(result).not_to include("<b>")
  end
end
