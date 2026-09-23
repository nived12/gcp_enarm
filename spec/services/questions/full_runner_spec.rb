require "rails_helper"

RSpec.describe Questions::FullRunner do
  let(:backup_dir) { Pathname.new(Dir.mktmpdir) }
  let(:lines) { [] }
  let(:generated) { [] }

  after { FileUtils.rm_rf(backup_dir) }

  def guideline_with(count)
    guideline = create(:guideline)
    section = create(:guideline_section, guideline: guideline, kind: "recommendation")
    create_list(:recommendation, count, guideline_section: section, text: "Se recomienda realizar electrocardiograma.")
    guideline
  end

  # A generation call as the runner sees it: one case citing the window's first
  # statement, so the corpus shrinks exactly as a real run's does.
  def generate(cost: 0.01, success: true)
    lambda do |guideline, run:, recommendations:, **|
      run.charge!(input_tokens: 1_000, output_tokens: 1_500, cost_usd: cost)
      generator = Questions::CaseGenerator.new(guideline)
      next generator.failure("sin JSON") unless success

      kase = create(:clinical_case, guideline: guideline, generation_run: run)
      create(:question, clinical_case: kase, recommendation: recommendations.first, source_quote: "electrocardiograma")
      run.increment!(:cases_created)
      generated << kase
      generator.success(cases: [kase], rejected: 0)
    end
  end

  def verify(verdict: "supported", cost: 0.001, success: true)
    lambda do |kase, run:|
      run.charge!(input_tokens: 400, output_tokens: 100, cost_usd: cost)
      verifier = Questions::Verifier.new(kase)
      next verifier.failure("caído") unless success

      kase.update!(verification_verdict: verdict, verified_at: Time.current)
      verifier.success(verdict: verdict)
    end
  end

  before do
    allow(Questions::CaseGenerator).to receive(:call, &generate)
    allow(Questions::Verifier).to receive(:call, &verify)
  end

  def full_run(calls: 5, budget: 1, **options)
    described_class.call(
      calls: calls, budget_usd: budget, chunk: 2, backup_dir: backup_dir, on_progress: ->(line) { lines << line },
      **options
    )
  end

  it "generates in chunks, backs each one up, then verifies and publishes it" do
    guideline_with(80)

    result = full_run(calls: 5)

    expect(result.payload).to include(stopped: :calls, calls: 5, cases: 5, live: 5, cost_usd: 0.055)
    expect(result.payload[:backups].size).to eq(4)
    expect(result.payload[:backups].last).to end_with("-final.jsonl.gz")
    expect(result.payload[:backups]).to all(satisfy { |path| File.exist?(path) })
    expect(GenerationRun.where(notes: "full_run:full").purpose_generation.pluck(:calls)).to eq([2, 2, 1])
    expect(generated.map { |kase| kase.reload.status }).to all(eq("published"))
    expect(lines).to include(a_string_starting_with("tanda 1: 2 llamadas"), a_string_starting_with("respaldo"))
  end

  it "deals the calls out by specialty unless told otherwise" do
    guideline_with(8)
    allow(Questions::GenerationRunner).to receive(:call).and_call_original

    full_run(calls: 1)

    expect(Questions::GenerationRunner).to have_received(:call).with(hash_including(order: "by_specialty"))
  end

  # The first chunk and its verification spend $0.022; the second chunk may make one
  # call before the cap is seen, and no more.
  it "stops at the dollar cap, counting verification too" do
    guideline_with(80)

    result = full_run(calls: 50, budget: 0.025)

    expect(result.payload).to include(stopped: :budget, calls: 3, cost_usd: 0.032)
  end

  # The point of a label: the same command after a crash goes on to the same totals.
  it "counts what earlier invocations under the same label made and spent" do
    guideline_with(80)
    full_run(calls: 2)

    expect(full_run(calls: 2).payload).to include(stopped: :calls, calls: 2)
    expect(full_run(calls: 3).payload).to include(calls: 3)
    expect(full_run(calls: 3, label: "otra").payload).to include(calls: 3)
  end

  # Each stub call cites one statement of eight, so the leftovers come round again
  # until every one is cited.
  it "stops when the corpus has no uncited statement left" do
    guideline_with(8)

    expect(full_run(calls: 50).payload).to include(stopped: :exhausted, calls: 8)
  end

  it "stops when generation keeps failing, still backing up and verifying what it has" do
    guideline_with(80)
    allow(Questions::CaseGenerator).to receive(:call, &generate(success: false))

    result = full_run(calls: 50)

    expect(result.payload).to include(stopped: :generation_failures)
    expect(result.payload[:backups]).to be_present
  end

  it "stops when verification keeps failing" do
    guideline_with(80)
    allow(Questions::Verifier).to receive(:call, &verify(success: false))

    expect(full_run(calls: 50, chunk: 10).payload).to include(stopped: :verification_failures, calls: 10)
  end

  it "verifies what an interrupted run left behind before paying for more, within the cap" do
    create_list(:clinical_case, 3)
    create(:generation_run, notes: "full_run:full", cost_usd: 0.9985)

    result = full_run(calls: 5)

    expect(result.payload).to include(stopped: :budget, calls: 0)
    expect(Questions::Verifier).to have_received(:call).twice
    expect(Questions::CaseGenerator).not_to have_received(:call)
  end

  it "pays for nothing once the label has spent its cap, and reports to no one when not asked" do
    guideline_with(8)
    create(:generation_run, notes: "full_run:full", cost_usd: 1)

    result = described_class.call(calls: 5, budget_usd: 1, backup_dir: backup_dir)

    expect(result.payload).to include(stopped: :budget, calls: 0)
    expect(Questions::CaseGenerator).not_to have_received(:call)
  end

  it "judges the rationales of supported cases the pilot left unjudged" do
    kase = create(:published_case, questions_count: 1)
    allow(Questions::RationaleVerifier).to receive(:call) { Questions::RationaleVerifier.new(kase).success({}) }

    full_run(calls: 0)

    expect(Questions::RationaleVerifier).to have_received(:call).with(kase, run: kind_of(GenerationRun))
  end

  it "stops before paying for the next chunk when a backup cannot be written" do
    guideline_with(80)
    allow(Questions::Exporter).to receive(:call) { Questions::Exporter.new("x").failure("disco lleno") }

    result = full_run(calls: 50)

    expect(result.payload).to include(stopped: :backup_failed, calls: 2, backups: [])
    expect(lines).to include("respaldo fallido: disco lleno")
  end

  it "refuses to run without a cap, or on a model whose price it does not know" do
    expect(full_run(budget: nil)).to be_failure

    ENV["LLM_VERIFIER_MODEL"] = "deepseek-experimental"
    expect(full_run.errors.full_messages.to_sentence).to include("deepseek/deepseek-experimental")
  ensure
    ENV.delete("LLM_VERIFIER_MODEL")
  end
end
