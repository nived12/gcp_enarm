require "rails_helper"
require "rake"

# The bank import is run by hand against production, where the printed counts are the
# only report of what landed. So the tasks are exercised end to end over a real file.
RSpec::Matchers.define_negated_matcher :not_output, :output

RSpec.describe "questions:import and questions:import_new" do
  let(:path) { Rails.root.join("tmp/spec-import-task-#{SecureRandom.hex(4)}.jsonl.gz").to_s }

  before(:context) do
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join("lib/tasks/questions.rake")
  end

  after { FileUtils.rm_f(path) }

  def run(task, file = path)
    Rake::Task[task].execute(Rake::TaskArguments.new([:path], [file]))
  end

  def build_case(stem)
    guideline = Guideline.find_by(catalog_key: "IMSS-028-22") || create(:guideline, catalog_key: "IMSS-028-22")
    section = guideline.guideline_sections.first || create(:guideline_section, guideline: guideline)
    recommendation = create(
      :recommendation, guideline_section: section,
      text: "Se recomienda realizar electrocardiograma."
    )
    kase = create(:clinical_case, guideline: guideline, generation_run: create(:generation_run), stem: stem)
    question = create(
      :question, clinical_case: kase, recommendation: recommendation,
      source_quote: "electrocardiograma"
    )
    create(:answer_option, question: question, position: 1, correct: true)
    kase
  end

  describe "questions:import_new" do
    it "keeps the cases production has, brings in the rest and says how many of each" do
      kept = build_case("Paciente de 54 años con dolor torácico.")
      build_case("Paciente de 60 años con disnea.")
      Questions::Exporter.call(path)
      ClinicalCase.where.not(id: kept.id).destroy_all
      kept.update!(status: "retired")

      expect { run("questions:import_new") }
        .to output(/casos importados: 1, omitidos por existir: 1, rechazados: 0/).to_stdout

      expect(ClinicalCase.count).to eq(2)
      expect(kept.reload.status).to eq("retired")
    end

    it "prints the counts before naming the refused cases and failing" do
      build_case("Paciente de 54 años con dolor torácico.")
      Questions::Exporter.call(path)
      ClinicalCase.destroy_all
      Recommendation.destroy_all

      expect { run("questions:import_new") }
        .to output(/casos importados: 0, omitidos por existir: 0, rechazados: 1/).to_stdout
        .and output(/El caso .* cita la recomendación/).to_stderr
        .and raise_error(SystemExit)
    end

    it "reads the default export path when none is given" do
      # Stubbed, so a real export sitting in tmp/ is never loaded by the suite.
      nothing = ApplicationService::Response.new(success: true, payload: Hash.new(0), errors: nil)
      allow(Questions::Importer).to receive(:call).and_return(nothing)

      expect { run("questions:import_new", nil) }.to output(/casos importados: 0/).to_stdout
      expect(Questions::Importer).to have_received(:call).with("tmp/question-bank.jsonl.gz", only_new: true)
    end

    it "prints no counts when the file cannot be read" do
      expect { run("questions:import_new", "#{path}-nope") }
        .to not_output.to_stdout
        .and output(/No existe el archivo/).to_stderr
        .and raise_error(SystemExit)
    end
  end

  describe "questions:import" do
    it "still overwrites the cases production has" do
      kase = build_case("Paciente de 54 años con dolor torácico.")
      Questions::Exporter.call(path)
      kase.update!(status: "retired")

      expect { run("questions:import") }
        .to output(/casos importados: 1, omitidos por existir: 0, rechazados: 0\n.*cases_updated: 1/).to_stdout

      expect(kase.reload.status).to eq("draft")
    end
  end
end
