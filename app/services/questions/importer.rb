# Loads a file written by Questions::Exporter into this environment's database.
#
# Idempotent on `export_key`, so a file can be replayed over a database that already holds
# part of it without paying for those cases twice.
#
# Every reference in the file is resolved against what this database actually has, and a
# reference that does not resolve fails the import. That is deliberate: a case whose
# guideline is missing, or whose question lost its recommendation, would import looking
# complete while citing nothing — which is the one failure this product cannot afford,
# because the citation is what makes a generated question trustworthy at all.
module Questions
  class Importer < ApplicationService
    # Raised and caught inside this class only, to abandon one case without abandoning
    # the file. Nothing escapes; the caller still gets a Response.
    MissingReference = Class.new(StandardError)

    def initialize(path)
      super()
      @path = path
    end

    def call
      return failure("No existe el archivo #{path}") unless File.exist?(path)

      counts = Hash.new(0)
      Zlib::GzipReader.open(path) { |file| file.each_line { |line| import(line, counts) } }
      return failure if has_errors?

      success(counts)
    rescue Zlib::GzipFile::Error => e
      failure("El archivo no se pudo descomprimir: #{e.message}")
    end

    private

    attr_reader :path

    def import(line, counts)
      attributes = ActiveSupport::JSON.decode(line)

      case attributes.delete("record")
      when "run" then import_run(attributes, counts)
      when "case" then import_case(attributes, counts)
      else failure("Registro desconocido en el archivo")
      end
    rescue JSON::ParserError
      failure("El archivo tiene una línea que no es JSON")
    end

    def import_run(attributes, counts)
      run = GenerationRun.find_or_initialize_by(export_key: attributes["export_key"])
      counts[run.new_record? ? :runs_created : :runs_updated] += 1
      run.update!(attributes)
    end

    def import_case(attributes, counts)
      questions = attributes.delete("questions")
      figure = attributes.delete("image")
      references = attributes.extract!("run_key", "catalog_key", "topic_slug", "specialty_slug", "setting_slug")

      ClinicalCase.transaction do
        kase = ClinicalCase.find_or_initialize_by(export_key: attributes["export_key"])
        counts[kase.new_record? ? :cases_created : :cases_updated] += 1
        kase.update!(attributes.merge(resolve(references), clinical_image: image_for(figure)))
        Array(questions).each { |question| import_question(kase, question, counts) }
      end
    rescue MissingReference => e
      failure("El caso #{attributes["export_key"]} cita #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      failure("El caso #{attributes["export_key"]} no se pudo guardar: #{e.record.errors.full_messages.to_sentence}")
    end

    def resolve(references)
      {
        generation_run: find_by!(GenerationRun, :export_key, references["run_key"], "la corrida"),
        guideline: find_by!(Guideline, :catalog_key, references["catalog_key"], "la guía"),
        topic: find_by!(Topic, :slug, references["topic_slug"], "el tema"),
        specialty: find_by!(Specialty, :slug, references["specialty_slug"], "la especialidad")
      }.merge(setting(references))
    end

    # A file written before cases carried a setting says nothing about it, and replaying
    # it must not erase a setting this database has since classified. Only a file that
    # names the key — nil included — decides it.
    def setting(references)
      return {} unless references.key?("setting_slug")

      { setting: find_by!(Specialty, :slug, references["setting_slug"], "el contexto") }
    end

    # Figures are rebuilt here by gpc:images rather than carried in the file, so a
    # missing one means that task has not run — say so instead of quietly dropping the
    # image out of a case that was written around it.
    def image_for(reference)
      return if reference.nil?

      section = section_for(reference)
      section.clinical_images.find_by(position: reference["position"]) ||
        missing("la figura #{reference["position"]} de la sección #{reference["section"]}")
    end

    def import_question(kase, attributes, counts)
      options = attributes.delete("options")
      reference = attributes.delete("recommendation")

      question = kase.questions.find_or_initialize_by(position: attributes["position"])
      counts[question.new_record? ? :questions_created : :questions_updated] += 1
      question.update!(attributes.merge(recommendation: recommendation_for(reference, attributes["source_quote"])))

      Array(options).each do |option|
        question.answer_options.find_or_initialize_by(position: option["position"]).update!(option)
      end
    end

    # The far side rebuilds recommendations with its own parser rather than receiving
    # them, so the path in the file — section and position — is only as stable as the
    # parser. Sections carved out of an archived PDF are named by it: a database that
    # kept an older carving because a case cited it (gpc:reparse never drops a cited row)
    # exports names a fresh reparse elsewhere does not produce. So the path is tried
    # first, and when it is gone or lands on a statement without the quote, the one
    # recommendation of that guideline that does contain the quote is used instead.
    # None or several and the path's answer stands: nothing, which fails as missing, or
    # the wrong statement, which Question's citation gate refuses. A case never arrives
    # mis-cited.
    def recommendation_for(reference, quote)
      return if reference.nil?

      guideline = find_by!(Guideline, :catalog_key, reference["catalog_key"], "la guía")
      at_path = guideline.guideline_sections.find_by(external_id: reference["section"])
        &.recommendations&.find_by(position: reference["position"])
      return at_path if quote.blank? || (at_path && Question.quote_in?(at_path.text, quote))

      by_quote = guideline.recommendations.select { |candidate| Question.quote_in?(candidate.text, quote) }
      return by_quote.sole if by_quote.one?

      at_path || missing(
        "la recomendación #{reference["position"]} de la sección #{reference["section"]} de #{guideline.catalog_key}"
      )
    end

    def section_for(reference)
      guideline = find_by!(Guideline, :catalog_key, reference["catalog_key"], "la guía")
      guideline.guideline_sections.find_by(external_id: reference["section"]) ||
        missing("la sección #{reference["section"]} de #{reference["catalog_key"]}")
    end

    def find_by!(model, column, value, noun)
      return if value.blank?

      model.find_by(column => value) || missing("#{noun} #{value}")
    end

    def missing(what)
      raise MissingReference, "#{what}, que no existe en esta base"
    end
  end
end
