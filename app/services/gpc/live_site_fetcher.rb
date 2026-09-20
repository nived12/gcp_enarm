# Shared HTTP for the live Secretaría de Salud site.
#
# A full ingestion is ~3,100 requests to one small government server with no CDN, so
# every request out of this app goes through here: same timeout, same User-Agent that
# says who we are, same pause between calls. Being slow on purpose is the price of
# being allowed to keep doing this.
module Gpc
  class LiveSiteFetcher < HttpFetcher
    BASE_URL = "https://gpc.salud.gob.mx".freeze
    TIMEOUT_SECONDS = 30
    REQUEST_INTERVAL_SECONDS = 0.25

    private

    # Callers pass a path; the host is not theirs to choose.
    def get(path, subject, query = {})
      super("#{BASE_URL}#{path}", subject, query)
    end
  end
end
