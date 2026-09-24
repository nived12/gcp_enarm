module ApplicationHelper
  # The launch domain (owner, 2026-09-23). The landing page's canonical and Open Graph
  # URL, fixed rather than read from the request so a preview host never becomes canonical.
  CANONICAL_URL = "https://gpcenarm.com/".freeze

  # The app reads at one narrow column; the landing page asks for a wide one with
  # `content_for :wide_page`, and the header and footer follow it so their edges line up.
  def page_width
    content_for?(:wide_page) ? "max-w-6xl" : "max-w-3xl"
  end
end
