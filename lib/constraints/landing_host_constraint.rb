module Constraints
  # Matches a request on the marketing host while the two hosts are split. The routes it
  # guards are the whole of that host; see config/routes.rb.
  class LandingHostConstraint
    def matches?(request)
      SiteHosts.landing?(request)
    end
  end
end
