# Downloads one archived guideline summary as raw bytes.
module Gpc
  class ArchivePdfFetcher < WebArchiveFetcher
    def initialize(document_url)
      super()
      @document_url = document_url
    end

    def call
      bytes = get(document_url, "El PDF archivado")
      return failure if has_errors?

      # The archive answers a missing or rate-limited capture with an HTML page and a
      # 200, so the bytes themselves have to say they are a PDF.
      return failure("El PDF archivado no es un PDF") unless bytes.to_s.start_with?("%PDF")

      success(bytes)
    end

    def context_for_logging
      { document_url: document_url }
    end

    private

    attr_reader :document_url
  end
end
