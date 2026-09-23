require "rails_helper"

RSpec.describe QuestionReport do
  let(:student) { create(:user) }
  let(:question) { create(:question) }
  let(:admin) { create(:user, :admin) }

  describe "validations" do
    it "rejects a reason it does not know rather than raising" do
      report = build(:question_report, reason: "bored")

      expect(report).not_to be_valid
      expect(report.errors).to be_of_kind(:reason, :inclusion)
    end

    it "requires a reason" do
      expect(build(:question_report, reason: nil)).not_to be_valid
    end

    it "asks for a comment when the reason is other, which says nothing on its own" do
      report = build(:question_report, reason: "other", comment: " ")

      expect(report).not_to be_valid
      expect(report.errors).to be_of_kind(:comment, :blank)
    end

    it "takes any other reason without a comment" do
      expect(build(:question_report, reason: "typo", comment: nil)).to be_valid
    end

    it "caps the comment length" do
      report = build(:question_report, comment: "a" * (QuestionReport::COMMENT_LIMIT + 1))

      expect(report).not_to be_valid
      expect(report.errors).to be_of_kind(:comment, :too_long)
    end

    it "allows one open report per student per question" do
      create(:question_report, user: student, question: question)
      duplicate = build(:question_report, user: student, question: question)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors).to be_of_kind(:question_id, :taken)
    end

    it "lets the student report again once the first report is closed" do
      create(:question_report, user: student, question: question).close(status: "resolved", note: nil, by: admin)

      expect(build(:question_report, user: student, question: question)).to be_valid
    end

    it "lets another student report the same question" do
      create(:question_report, user: student, question: question)

      expect(build(:question_report, question: question)).to be_valid
    end

    it "requires whoever closed it" do
      report = build(:question_report, status: "dismissed")

      expect(report).not_to be_valid
      expect(report.errors).to be_of_kind(:resolved_by, :blank)
    end
  end

  describe "#close" do
    let(:report) { create(:question_report) }

    it "records the outcome, the note, who closed it and when" do
      freeze_time do
        expect(report.close(status: "resolved", note: "Corregida la opción B.", by: admin)).to be(true)

        expect(report.reload).to have_attributes(
          status: "resolved", resolution_note: "Corregida la opción B.", resolved_by: admin, resolved_at: Time.current
        )
      end
    end

    it "stores a blank note as none" do
      report.close(status: "dismissed", note: "", by: admin)

      expect(report.reload.resolution_note).to be_nil
    end

    it "refuses anything but resolved or dismissed" do
      expect(report.close(status: "open", note: nil, by: admin)).to be(false)
      expect(report.reload).to be_status_open
    end
  end

  it "reaches its case through the question" do
    report = create(:question_report, question: question)

    expect(report.clinical_case).to eq(question.clinical_case)
    expect(question.clinical_case.question_reports).to contain_exactly(report)
  end

  it "keeps a closed report when the admin who closed it leaves" do
    report = create(:question_report)
    report.close(status: "resolved", note: nil, by: admin)

    admin.destroy!

    expect(report.reload.resolved_by).to be_nil
  end

  it "orders the newest first" do
    older = create(:question_report, created_at: 2.days.ago)
    newer = create(:question_report)

    expect(described_class.recent).to eq([newer, older])
  end
end
