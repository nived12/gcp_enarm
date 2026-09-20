require "rails_helper"

RSpec.describe GenerationRun do
  describe "#total_tokens" do
    it "sums both directions" do
      run = build(:generation_run, input_tokens: 1_200, output_tokens: 340)

      expect(run.total_tokens).to eq(1_540)
    end
  end

  describe "#attempts_per_case" do
    it "reports what it took to land a usable case" do
      run = build(:generation_run, attempts: 30, cases_created: 24)

      expect(run.attempts_per_case).to eq(1.25)
    end

    it "is nothing when the run produced no cases, rather than dividing by zero" do
      expect(build(:generation_run, attempts: 5, cases_created: 0).attempts_per_case).to be_nil
    end
  end

  it "leaves its cases behind when deleted, so a retired run does not take the bank with it" do
    run = create(:generation_run)
    kase = create(:clinical_case, generation_run: run)

    run.destroy

    expect(kase.reload.generation_run_id).to be_nil
  end
end
