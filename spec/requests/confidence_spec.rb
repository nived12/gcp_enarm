require "rails_helper"

# How sure the student is, chosen with the answer: labelled buttons one question at a
# time, icons named once at the top on the single page. Always optional.
RSpec.describe "Confidence", type: :request do
  let(:student) { create(:user) }
  let!(:kase) { create(:published_case, questions_count: 2) }

  before { post session_path, params: { email: student.email, password: "contrasena-segura" } }

  def start(mode)
    post exams_path, params: { mode: mode }
    Exam.last
  end

  def submit(exam, position, text: nil, confidence: nil, turbo: false)
    exam_question = exam.exam_questions.find_by!(position: position)
    option_id = text && exam_question.question.answer_options.find_by!(text: text).id
    post exam_question_answer_path(exam, position),
      headers: turbo ? { "Accept" => "text/vnd.turbo-stream.html" } : {},
      params: { answer_option_id: option_id, confidence: confidence }.compact
  end

  def answer_at(exam, position)
    exam.exam_questions.find_by!(position: position).answer
  end

  describe "one question at a time" do
    let(:exam) { start("quick_quiz") }

    it "offers the three levels with their words, marked optional and none chosen" do
      get exam_question_path(exam, 1)

      page = Nokogiri::HTML(response.body)
      expect(page.css("input[name=confidence]").map { |input| input["value"] }).to eq(%w[sure unsure guess])
      expect(page.css("input[name=confidence][checked]")).to be_empty
      expect(response.body).to include(
        I18n.t("exams.confidence.legend"), I18n.t("exams.confidence.optional"),
        *Answer::CONFIDENCES.map { |level| I18n.t("exams.confidence.levels.#{level}") }
      )
    end

    it "keeps the confidence given with the answer and says what a lucky guess means" do
      submit(exam, 1, text: "Electrocardiograma de 12 derivaciones", confidence: "guess")

      expect(answer_at(exam, 1)).to have_attributes(correct: true, confidence: "guess")
      get exam_question_path(exam, 1)
      expect(response.body).to include(I18n.t("exams.confidence.notes.lucky_guess"))
    end

    it "calls out a miss the student was sure of" do
      submit(exam, 1, text: "Troponina I", confidence: "sure")

      get exam_question_path(exam, 1)
      expect(response.body).to include(
        I18n.t("exams.confidence.you_marked", level: I18n.t("exams.confidence.levels.sure")),
        I18n.t("exams.confidence.notes.confident_miss")
      )
    end

    it "says nothing more for a right answer the student knew" do
      submit(exam, 1, text: "Electrocardiograma de 12 derivaciones", confidence: "sure")

      get exam_question_path(exam, 1)
      expect(response.body).not_to include(I18n.t("exams.confidence.notes.confident_miss"))
      expect(response.body).not_to include(I18n.t("exams.confidence.notes.lucky_guess"))
    end

    it "takes an answer with no confidence, or one it does not know, as not said" do
      submit(exam, 1, text: "Troponina I")
      submit(exam, 2, text: "Troponina I", confidence: "certisimo")

      expect([ answer_at(exam, 1).confidence, answer_at(exam, 2).confidence ]).to eq([ nil, nil ])
      get exam_question_path(exam, 1)
      expect(response.body).not_to include(I18n.t("exams.confidence.you_marked", level: ""))
    end

    it "cannot be changed once the explanation has been shown" do
      submit(exam, 1, text: "Troponina I", confidence: "sure")
      submit(exam, 1, confidence: "guess")

      expect(flash[:alert]).to eq(I18n.t("exams.answers.already_answered"))
      expect(answer_at(exam, 1).confidence).to eq("sure")
    end
  end

  describe "on the single page" do
    let(:exam) { start("full_exam") }

    it "names the icons once at the top and puts them beside each question" do
      get exam_path(exam)

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("aside").text).to include(
        I18n.t("exams.confidence.sheet_hint"),
        I18n.t("exams.confidence.optional")
      )
      icons = page.css("input[name=confidence]")
      expect(icons.size).to eq(3 * exam.question_count)
      expect(icons.first["aria-label"]).to eq(I18n.t("exams.confidence.levels.sure"))
    end

    it "saves it with the option, changes it alone later, and shows it checked" do
      submit(exam, 1, text: "Troponina I", confidence: "unsure", turbo: true)
      submit(exam, 1, confidence: "guess", turbo: true)

      expect(response.body).to include(I18n.t("exams.sheet.saved"))
      expect(answer_at(exam, 1)).to have_attributes(confidence: "guess", correct: false)

      get exam_path(exam)
      checked = Nokogiri::HTML(response.body).css("input[name=confidence][checked]")
      expect(checked.map { |input| input["value"] }).to eq(%w[guess])
    end

    it "keeps the confidence when only the option changes" do
      submit(exam, 1, text: "Troponina I", confidence: "sure", turbo: true)
      submit(exam, 1, text: "Electrocardiograma de 12 derivaciones", turbo: true)

      expect(answer_at(exam, 1)).to have_attributes(confidence: "sure", correct: true)
    end

    it "needs an option before a confidence alone can be saved" do
      submit(exam, 1, confidence: "sure")

      expect(flash[:alert]).to eq(I18n.t("exams.answers.choose_option"))
      expect(answer_at(exam, 1)).to be_nil
    end

    it "marks each answer's confidence in the results, a confident miss in the error colour" do
      submit(exam, 1, text: "Troponina I", confidence: "sure", turbo: true)
      submit(exam, 2, text: "Electrocardiograma de 12 derivaciones", confidence: "guess", turbo: true)
      patch complete_exam_path(exam)

      get exam_path(exam)
      page = Nokogiri::HTML(response.body)
      marks = page.css("span[title]").to_h { |mark| [ mark["title"], mark["class"] ] }
      expect(marks[I18n.t("exams.confidence.levels.sure")]).to include("text-incorrect")
      expect(marks[I18n.t("exams.confidence.levels.guess")]).to include("text-ink-faint")
    end
  end

  describe "the stats page" do
    it "shows accuracy by confidence only once the student has marked some" do
      get stats_path
      expect(response.body).not_to include(I18n.t("stats.show.by_confidence"))

      exam = start("quick_quiz")
      submit(exam, 1, text: "Troponina I", confidence: "sure")
      get stats_path

      expect(response.body).to include(I18n.t("stats.show.by_confidence"), I18n.t("exams.confidence.levels.sure"))
    end
  end
end
