# Shared HTTP for the live Secretaría de Salud site.
#
# Every request this app makes to gpc.salud.gob.mx goes through here, so the timeout,
# the User-Agent that says who we are, and the pause between calls are decided once.
# It is a small government server with no CDN and a full ingestion is ~3,100 requests;
# being slow on purpose is the price of being allowed to keep doing this.
module Gpc
  class LiveSiteFetcher < ApplicationService
    BASE_URL = "https://gpc.salud.gob.mx".freeze
    TIMEOUT_SECONDS = 30
    REQUEST_INTERVAL_SECONDS = 0.25

    private

    # Returns the response body, or nil after recording a failure. `subject` names
    # what was being read so the error says which request went wrong.
    def get(path, subject, query = {})
      response = HTTParty.get(
        "#{BASE_URL}#{path}", query: query, timeout: TIMEOUT_SECONDS,
        headers: { "User-Agent" => user_agent }
      )
      return response.body if response.success?

      failure("#{subject} respondió #{response.code}")
      nil
    rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED => e
      failure("No se pudo leer #{subject.downcase}: #{e.message}")
      nil
    end

    def user_agent
      ENV.fetch("GPC_USER_AGENT", "GPCEnarm/1.0 (+https://gpcenarm.mx; contacto@gpcenarm.mx)")
    end
  end
end
