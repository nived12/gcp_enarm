# Sends a request that reached the marketing host for a page it does not serve to the same
# path and query on the app host. Permanent, because the path will never be served there:
# 301 for a page, 308 for anything else, which keeps the method and body where a 301 lets
# the browser turn a POST into a GET.
class AppHostRedirect
  def self.call(env)
    request = ActionDispatch::Request.new(env)
    status = request.get? || request.head? ? 301 : 308

    [status, { "location" => "#{request.protocol}#{SiteHosts.app}#{request.fullpath}" }, []]
  end
end
