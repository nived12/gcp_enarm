require "rails_helper"

RSpec.describe Questions::GenerationRunner do
  let(:run) { create(:generation_run) }
  let(:calls) { [] }

  def guideline_with(count, **attributes)
    guideline = create(:guideline, **attributes)
    section = create(:guideline_section, guideline: guideline, kind: "recommendation")
    create_list(:recommendation, count, guideline_section: section)
    guideline
  end

  def answer(cases: 1, rejected: 0, cost: 0.002, success: true)
    lambda do |guideline, run:, recommendations:, **options|
      calls << { guideline: guideline, recommendations: recommendations, **options }
      run.increment!(:cost_usd, cost)
      generator = Questions::CaseGenerator.new(guideline)
      success ? generator.success(cases: Array.new(cases), rejected: rejected) : generator.failure("sin JSON")
    end
  end

  before { allow(Questions::CaseGenerator).to receive(:call, &answer) }

  def generate(**options) = described_class.call(run: run, calls: 10, **options)

  it "gives every guideline its first window before any guideline its second" do
    newer = guideline_with(10, catalog_key: "IMSS-001-24", year: 2024)
    older = guideline_with(3, catalog_key: "IMSS-002-10", year: 2010)

    generate

    expect(calls.map { |c| [c[:guideline], c[:recommendations].size] }).to eq([[newer, 8], [older, 3], [newer, 2]])
  end

  it "skips statements a question already cites, so a second run continues the first" do
    guideline = guideline_with(3)
    cited = guideline.recommendations.first
    create(:question, recommendation: cited)

    generate

    expect(calls.sole[:recommendations]).not_to include(cited)
    expect(calls.sole[:recommendations].size).to eq(2)
  end

  it "stops at the number of calls it was given" do
    guideline_with(40)

    described_class.call(run: run, calls: 2)

    expect(calls.size).to eq(2)
  end

  it "stops once the run has spent its budget" do
    guideline_with(40)

    result = generate(budget_usd: 0.003)

    expect(calls.size).to eq(2)
    expect(result.payload).to include(stopped_at_budget: 1, cost_usd: 0.004)
  end

  it "refuses a budget it cannot measure" do
    ENV["LLM_MODEL"] = "gemini-9-experimental"
    guideline_with(3)

    result = generate(budget_usd: 1)

    expect(result).to be_failure
    expect(calls).to be_empty
  ensure
    ENV.delete("LLM_MODEL")
  end

  it "tallies cases, rejections and failures, and reports each call" do
    guideline_with(3, catalog_key: "IMSS-003-22")
    guideline_with(3, catalog_key: "IMSS-004-22")
    allow(Questions::CaseGenerator).to receive(:call).and_invoke(answer(cases: 2, rejected: 1), answer(success: false))
    lines = []

    result = generate(on_progress: ->(line) { lines << line })

    expect(result.payload).to include(calls: 2, cases: 2, rejected: 1, failed: 1)
    expect(lines).to eq(["IMSS-003-22 [full_workup/es/figura] 2 casos", "IMSS-004-22 [focused/en] sin JSON"])
  end

  it "rotates vignette length, language and figures on a fixed schedule" do
    guideline_with(8 * 14)

    described_class.call(run: run, calls: 14)

    # One case in 12.5 is English, so the first falls on the fourteenth call.
    expect(calls.map { |c| c[:detail] }.first(2)).to eq(%i[full_workup focused])
    expect(calls.each_index.select { |i| calls[i][:locale] == "en" }).to eq([13])
    expect(calls.each_index.select { |i| calls[i][:with_image] }).to eq([0, 7])
  end

  it "draws from generatable guidelines only" do
    guideline_with(3, title: "Intervenciones de enfermería en el paciente con diabetes")

    generate

    expect(calls).to be_empty
  end
end
