require "rails_helper"

RSpec.describe Gpc::GuidelineImporter do
  let(:guideline) { create(:guideline) }

  def section(external_id: "36777", body: nil, heading: "RECOMENDACIONES", kind: "recommendation")
    body ||= <<~HTML
      <div class="separador">A NICE Hong K, 2021</div>
      <p>Se recomienda otorgar educación prenatal.</p>
      <div class="separador">B SIGN Shi Y, 2015</div>
      <p>Se recomienda integrar a toda mujer embarazada.</p>
    HTML

    { external_id: external_id, heading: heading, clinical_question: "¿QUÉ BENEFICIOS APORTA?",
      kind: kind, position: 1, body: body, content_hash: Digest::SHA256.hexdigest(body) }
  end

  it "creates a section and the statements inside it" do
    response = described_class.call(guideline, [section])

    expect(response).to be_success
    expect(response.payload).to eq(created: 1, updated: 0, unchanged: 0, recommendations: 2)
  end

  it "stores each statement with its grading split out" do
    described_class.call(guideline, [section])

    expect(guideline.recommendations.map { |r| [r.grade, r.scale, r.citation] })
      .to eq([["A", "NICE", "Hong K, 2021"], ["B", "SIGN", "Shi Y, 2015"]])
  end

  it "writes nothing on a re-run of unchanged sections" do
    described_class.call(guideline, [section])
    updated_at = guideline.guideline_sections.sole.updated_at

    response = described_class.call(guideline, [section])

    expect(response.payload).to eq(created: 0, updated: 0, unchanged: 1, recommendations: 2)
    expect(guideline.guideline_sections.sole.updated_at).to eq(updated_at)
  end

  it "rebuilds the statements when the site republishes a section" do
    described_class.call(guideline, [section])
    revised = section(body: "<div class=\"separador\">D GRADE Nuevo A, 2026</div><p>Texto nuevo.</p>")

    response = described_class.call(guideline, [revised])

    expect(response.payload).to include(updated: 1, recommendations: 1)
    expect(guideline.reload.recommendations.map(&:citation)).to eq(["Nuevo A, 2026"])
  end

  it "keeps sections of other guidelines out of the count" do
    create(:guideline_section, external_id: "36777")

    expect(described_class.call(guideline, [section]).payload).to include(created: 1)
  end

  it "stores a section that yields no statements" do
    response = described_class.call(guideline, [section(body: "<p>Sin evidencia suficiente.</p>")])

    expect(response.payload).to include(created: 1, recommendations: 0)
    expect(guideline.guideline_sections.sole.body).to include("Sin evidencia")
  end

  # The anexos reuse div.separador for the directory and for the tables that define
  # the scales, so parsing them would manufacture recommendations out of institution
  # names. The section is still stored whole.
  it "stores a non-graded section without reading statements out of it" do
    directory = section(
      heading: "DIRECTORIO SECTORIAL", kind: "other",
      body: "<div class=\"separador\">Secretaría de Salud</div><p>Titular.</p>"
    )

    response = described_class.call(guideline, [directory])

    expect(response.payload).to include(created: 1, recommendations: 0)
    expect(guideline.guideline_sections.sole.body).to include("Secretaría de Salud")
  end

  it "fails without writing anything when a section is invalid" do
    response = described_class.call(guideline, [section.merge(heading: "")])

    expect(response).not_to be_success
    expect(guideline.guideline_sections).to be_empty
  end
end
