# Loads a file written by Gpc::CorpusExporter into this environment's database.
#
# Idempotent on the same keys the fetchers use, so running it over a database that was
# populated by scraping is a no-op rather than a duplication. What it does not do is
# rebuild recommendations, the taxonomy or the topic links — those are separate tasks
# that cost nothing to run and belong to the code, not to the file.
module Gpc
  class CorpusImporter < ApplicationService
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
      when "guideline" then import_guideline(attributes, counts)
      when "section" then import_section(attributes, counts)
      else failure("Registro desconocido en el archivo")
      end
    rescue JSON::ParserError
      failure("El archivo tiene una línea que no es JSON")
    end

    def import_guideline(attributes, counts)
      guideline = Guideline.find_or_initialize_by(catalog_key: attributes["catalog_key"])
      counts[guideline.new_record? ? :guidelines_created : :guidelines_updated] += 1
      guideline.update!(attributes)
    end

    def import_section(attributes, counts)
      guideline = guideline_for(attributes.delete("catalog_key"))
      return if guideline.nil?

      section = guideline.guideline_sections.find_or_initialize_by(external_id: attributes["external_id"])
      counts[section.new_record? ? :sections_created : :sections_updated] += 1
      section.update!(attributes)
    end

    # Guidelines are written before their sections, so a missing one means a truncated
    # or hand-edited file. Say so rather than dropping content silently.
    def guideline_for(catalog_key)
      @guidelines ||= {}
      @guidelines[catalog_key] ||= Guideline.find_by(catalog_key: catalog_key)
      failure("La sección cita una guía ausente: #{catalog_key}") if @guidelines[catalog_key].nil?
      @guidelines[catalog_key]
    end
  end
end
