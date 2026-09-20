# Pulls the text out of an archived guideline PDF, and names it.
#
# The naming is Gpc::DocumentTitle's job, so that a title can be re-derived later from
# text already stored rather than by downloading the PDF again.
module Gpc
  class PdfExtractor < ApplicationService
    def initialize(bytes)
      super()
      @bytes = bytes
    end

    def call
      pages = page_texts
      return failure if has_errors?
      return failure("El PDF no contiene texto") if pages.all?(&:blank?)

      text = pages.join("\n")
      success(text: text, title: DocumentTitle.call(text).payload, page_count: pages.size)
    end

    private

    attr_reader :bytes

    def page_texts
      PDF::Reader.new(StringIO.new(bytes)).pages.map(&:text)
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError, ArgumentError => e
      failure("No se pudo leer el PDF: #{e.message}")
      []
    end
  end
end
