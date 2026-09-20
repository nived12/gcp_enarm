# Downloads one archived guideline summary as raw bytes.
#
# The archive truncates under load: it answers 200 with a Content-Length of exactly
# 1 MiB and a PDF that stops mid-object. Both halves of that are convincing — the status
# is fine and the bytes really do start with %PDF — so the download is checked for its
# end marker rather than its beginning, and retried. The same capture served the
# complete 12 MB file minutes later, which is why this retries instead of hunting for a
# different capture.
module Gpc
  class ArchivePdfFetcher < WebArchiveFetcher
    ATTEMPTS = 3
    RETRY_INTERVAL_SECONDS = 5

    # Trailers carry padding after %%EOF, and some writers leave a good deal of it.
    TRAILER_WINDOW = 2048

    def initialize(document_url, attempts: ATTEMPTS, retry_interval: RETRY_INTERVAL_SECONDS)
      super()
      @document_url = document_url
      @attempts = attempts
      @retry_interval = retry_interval
    end

    def call
      attempts.times do |attempt|
        clear_errors
        bytes = attempt_download
        return success(bytes) if bytes

        sleep(retry_interval) if retry_interval.positive? && attempt < attempts - 1
      end

      failure
    end

    def context_for_logging
      { document_url: document_url }
    end

    private

    attr_reader :document_url, :attempts, :retry_interval

    # Returns the bytes, or nil after recording why they were refused. Never the
    # Response that failure builds — that object is truthy, and returning it once made
    # a rejected download read as a successful one.
    def attempt_download
      bytes = get(document_url, "El PDF archivado")
      return if bytes.nil?

      # A missing or throttled capture comes back as an HTML page with a 200, so the
      # bytes themselves have to say what they are.
      return reject("El PDF archivado no es un PDF") unless bytes.start_with?("%PDF")
      return reject("El PDF archivado llegó incompleto") unless complete?(bytes)

      bytes
    end

    def reject(message)
      failure(message)
      nil
    end

    def complete?(bytes)
      window = [bytes.bytesize, TRAILER_WINDOW].min
      bytes.byteslice(bytes.bytesize - window, window).to_s.include?("%%EOF")
    end
  end
end
