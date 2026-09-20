# Shared HTTP for the Wayback Machine.
#
# The archive is where the other ~690 guidelines live — CENETEC was dissolved and
# cenetec-difusion.com went with it. It rate-limits hard (429), goes down for
# maintenance (503) and resets connections mid-download, so callers must treat a
# failure as ordinary and come back later.
module Gpc
  class WebArchiveFetcher < HttpFetcher
    BASE_URL = "https://web.archive.org".freeze

    # A guideline PDF is ~1 MB from a service that is frequently slow.
    TIMEOUT_SECONDS = 180
    REQUEST_INTERVAL_SECONDS = 1.5
  end
end
