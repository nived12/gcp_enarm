# Reads a section's stored HTML and returns the figures worth keeping.
#
# Runs on stored text only — no network — so the accept and reject rules can be changed
# and replayed over the whole corpus, the same way Gpc::RecommendationParser can.
#
# The corpus does not separate a guideline's clinical figures from its editorial ones.
# Both are anexos, both are images, and both sit under a heading like "CUADRO 4". What
# separates them is the filename the site assigns: a criteria table is cuadro_4.jpg and
# the GRADE appraisal of that same recommendation is cuadro_de_evidencia_4.jpg. So the
# heading decides whether a section holds figures at all, and the filename decides
# whether each one is medicine or methodology.
module Gpc
  class ImageParser < ApplicationService
    FIGURE_HEADING = /\A(CUADRO|TABLA|ALGORITMO|DIAGRAMA|FLUJOGRAMA|FIGURA|ESCALA)S?\b/

    # Evidence grids, GRADE profiles and the scale-definition tables. They are the
    # guideline's working papers: correct, published, and of no use to a student.
    METHODOLOGY_FILE = /evidencia|grade|_sign|_nice|shekelle|oxford/

    # The site writes its own paths relative to the guideline view, so the leading "~"
    # has to come off before the path means anything.
    PATH_PREFIX = "~".freeze

    def initialize(section)
      super()
      @section = section
    end

    def call
      return success([]) unless heading.match?(FIGURE_HEADING)

      success(images)
    end

    private

    attr_reader :section

    def heading
      @heading ||= I18n.transliterate(section.heading.to_s.squish).upcase
    end

    def images
      document.css("img").filter_map { |tag| path_for(tag) }
              .reject { |path| File.basename(path).match?(METHODOLOGY_FILE) }
              .map.with_index(1) { |path, position| attributes_for(path, position) }
    end

    def attributes_for(path, position)
      {
        label: section.heading.squish, caption: caption, position: position,
        kind: ClinicalImage.kind_for(section.heading), remote_path: path, source: "gpc"
      }
    end

    def path_for(tag)
      source = tag["src"].to_s.strip.delete_prefix(PATH_PREFIX).delete_prefix("/")
      source.presence
    end

    # What the guideline says the figure shows — "MARCADORES CLÍNICOS DE CONGESTIÓN".
    # The heading is only a number, so this is the whole of what a reader, or a prompt,
    # can know about the figure without looking at it.
    def caption
      @caption ||= begin
        text = document.dup
        text.css("img").remove
        text.text.squish.delete_prefix(section.heading.squish).squish.presence
      end
    end

    def document
      @document ||= Nokogiri::HTML.fragment(section.body.to_s)
    end
  end
end
