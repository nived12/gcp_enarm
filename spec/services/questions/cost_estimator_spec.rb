require "rails_helper"

RSpec.describe Questions::CostEstimator do
  let(:pilot) do
    create(
      :generation_run, cases_created: 4, input_tokens: 4_000, output_tokens: 6_000, rejections: 2,
      started_at: 10.minutes.ago, finished_at: 10.minutes.ago + 60
    )
  end

  # Four pilot cases of two questions each, one of them with a stem that asks its own
  # question; three supported, one disputed.
  before do
    ["Paciente de 54 años.", "Paciente de 60 años.", "Paciente de 70 años.", "Mujer de 30 años. ¿Qué hacer?"]
      .zip(%w[supported supported supported unsupported]).each do |stem, verdict|
        kase = create(:clinical_case, generation_run: pilot, stem: stem, verification_verdict: verdict)
        create_list(:question, 2, clinical_case: kase)
      end
    create(:generation_run, purpose: "verification", attempts: 4, input_tokens: 3_200, output_tokens: 400)
    create(:generation_run, purpose: "rationales", attempts: 2, input_tokens: 2_000, output_tokens: 800)
    section = create(:guideline_section, guideline: create(:guideline), kind: "recommendation")
    create_list(:recommendation, 16, guideline_section: section)
  end

  def estimate(**options) = described_class.call(**options).payload

  it "measures its ratios from the runs on record, recovering the pilot's calls from its cases" do
    expect(estimate[:measured]).to include(
      reference_run: pilot.id, reference_calls: 2, cases_per_call: 2.0, questions_per_case: 2.0,
      rejection_share: 0.2, stem_asks_question_share: 0.25, published_share: 0.75, supported_share: 0.75
    )
  end

  it "takes the pilot's own call count once runs record one" do
    pilot.update!(calls: 4)

    expect(estimate[:measured]).to include(reference_calls: 4, cases_per_call: 1.0)
  end

  it "plans one pass over the uncited statements, and prices every known model" do
    result = estimate

    expect(result).to include(calls: 2, one_pass_calls: 2, guidelines: 1, pending_rationale_cases: 0)
    expect(result[:per_call][:output]).to eq(3_000 + (400 * 2))
    expect(result[:per_case]).to include(answers_input: 800, answers_output: 100, rationales_output: 300)
    expect(result[:yield]).to eq(cases: 3, questions: 6, published_cases: 2, published_questions: 5)
    expect(result[:costs].map { |row| row[:model] }).to eq(Llm::Provider::PRICES.keys)
    expect(result[:costs].first).to include(roles: [:generator])
    expect(result[:generation_hours]).to eq(0.0)
  end

  # 2 cases a call, a quarter lost to the stem check, 2 questions each, 3 in 4 published:
  # 2.25 published questions a call.
  it "says how many calls reach each target" do
    expect(estimate[:targets][3_000]).to include(calls: 1_334)
    expect(estimate(calls: 1_000)[:yield][:published_questions]).to eq(2_250)
  end

  it "prices the rationales still waiting on cases already supported, even with nothing to generate" do
    GenerationRun.purpose_rationales.update_all(input_tokens: 20_000_000)
    create(:published_case, questions_count: 1)

    result = estimate(calls: 0)

    expect(result[:pending_rationale_cases]).to eq(1)
    expect(result[:costs].map { |row| row[:verification] }).to all(be > 1)
  end

  it "counts no rationale cost before any rationale run, and no time for an unfinished pilot" do
    GenerationRun.purpose_rationales.delete_all
    pilot.update!(finished_at: nil)

    expect(estimate[:per_call][:output]).to eq(3_000)
    expect(estimate[:generation_hours]).to be_nil
  end

  it "assumes the denser tokenizer for a provider it has not measured, and no price for an unpriced model" do
    gemini = estimate
    ENV["LLM_PROVIDER"] = "anthropic"
    anthropic = estimate

    expect(anthropic[:per_call][:input]).to be > gemini[:per_call][:input]
    expect(anthropic[:targets][3_000][:cost_usd]).to be < gemini[:targets][3_000][:cost_usd]
    expect(anthropic[:costs].first[:roles]).to be_empty
  ensure
    ENV.delete("LLM_PROVIDER")
  end

  it "prices nothing when the corpus has nothing left to generate from" do
    Recommendation.find_each { |recommendation| create(:question, recommendation: recommendation) }

    expect(estimate).to include(calls: 0, one_pass_calls: 0)
    expect(estimate[:per_call][:input]).to eq(0)
  end

  it "refuses to guess without a pilot, or without a verified case" do
    ClinicalCase.update_all(verification_verdict: nil)
    expect(described_class.call.errors.full_messages.to_sentence).to include("verificados")

    GenerationRun.purpose_generation.update_all(cases_created: 0)
    expect(described_class.call.errors.full_messages.to_sentence).to include("referencia")
  end
end
