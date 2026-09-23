# One legal document, read from Markdown in the current locale. The text lives in
# app/content/legal, one file per page and locale, because a lawyer edits prose, not
# YAML. The files are ours, so their HTML is trusted; Commonmarker still drops raw HTML.
class LegalPage
  NAMES = %w[terms privacy refunds].freeze
  DIRECTORY = Rails.root.join("app/content/legal")

  attr_reader :name

  def initialize(name, locale: I18n.locale)
    @name = name
    @locale = locale
  end

  def path
    DIRECTORY.join("#{name}.#{@locale}.md")
  end

  # No heading anchors: Commonmarker labels them in English ("Link to heading").
  def to_html
    Commonmarker.to_html(path.read(encoding: "UTF-8"), options: { extension: { header_ids: nil } }).html_safe
  end
end
