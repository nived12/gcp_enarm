# Downloads one figure from the live site.
#
# Separate from the ingester so the bytes can be fetched without re-deciding which
# figures are worth having, and so a failed download is one recorded failure rather than
# the end of a run.
module Gpc
  class ImageFetcher < LiveSiteFetcher
    # The site writes image paths relative to the guideline view, so what it stores as
    # "~imagenes/doc_4081/diagrama_1.jpg" is served from the application root. Note this
    # is the single-DDIMBE form: the doubled path that the content endpoints accept
    # returns 404 for images.
    ROOT = "/DDIMBE/".freeze

    CONTENT_TYPES = {
      ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg",
      ".png" => "image/png", ".gif" => "image/gif", ".webp" => "image/webp"
    }.freeze

    def initialize(remote_path)
      super()
      @remote_path = remote_path
    end

    def call
      bytes = get("#{ROOT}#{remote_path}", "La imagen #{remote_path}")
      return failure if bytes.nil?
      return failure("La imagen #{remote_path} llegó vacía") if bytes.empty?

      success(bytes: bytes, filename: File.basename(remote_path), content_type: content_type)
    end

    def context_for_logging
      { remote_path: remote_path }
    end

    private

    attr_reader :remote_path

    def content_type
      CONTENT_TYPES.fetch(File.extname(remote_path).downcase, "application/octet-stream")
    end
  end
end
