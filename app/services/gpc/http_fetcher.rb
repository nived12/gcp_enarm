# Shared HTTP for both sources of guidelines.
#
# Everything this app fetches comes from a server it does not control and cannot ask to
# behave: a small government site with no CDN, and an archive that throttles. Neither
# failing is exceptional, so failures are recorded and returned rather than raised — an
# ingestion run that dies on guideline 194 of 694 has wasted the 193 before it.
#
# NETWORK_ERRORS is deliberately broad for that reason. HTTParty wraps some of these and
# not others, and the ones it does not wrap are exactly the ones a long run hits.
module Gpc
  class HttpFetcher < ApplicationService
    NETWORK_ERRORS = [
      HTTParty::Error, SocketError, Timeout::Error, OpenSSL::SSL::SSLError,
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EPIPE, Errno::EHOSTUNREACH,
      Errno::ETIMEDOUT, Net::OpenTimeout, Net::ReadTimeout, EOFError
    ].freeze

    private

    # Returns the response body, or nil after recording a failure. `subject` names what
    # was being read, so the error says which request went wrong.
    def get(url, subject, query = {})
      response = HTTParty.get(
        url, query: query, timeout: timeout_seconds, follow_redirects: true,
        headers: { "User-Agent" => user_agent }
      )
      return response.body if response.success?

      failure("#{subject} respondió #{response.code}")
      nil
    rescue *NETWORK_ERRORS => e
      failure("No se pudo leer #{subject.downcase}: #{e.class} #{e.message}")
      nil
    end

    def timeout_seconds
      self.class::TIMEOUT_SECONDS
    end

    def user_agent
      ENV.fetch("GPC_USER_AGENT", "GPCEnarm/1.0 (+https://gpcenarm.mx; contacto@gpcenarm.mx)")
    end
  end
end
