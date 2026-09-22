# Re-derives archived guidelines' titles from text already stored.
#
# Title extraction is a heuristic over PDFs that span fifteen years of CENETEC
# templates, so it will keep improving. Because the extracted text lives on the
# section, improving it never means downloading 700 PDFs from a rate-limited archive
# a second time — this is the payoff for storing the document whole.
module Gpc
  class Retitler < ApplicationService
    def call
      counts = Hash.new(0)

      Guideline.source_web_archive.includes(:guideline_sections).find_each do |guideline|
        section = guideline.guideline_sections.find(&:kind_archived_document?)
        next counts[:no_text] += 1 if section.nil?

        title = ArchiveTitles.for(guideline.catalog_key) || DocumentTitle.call(section.body).payload
        counts[outcome(guideline, title)] += 1
      end

      success(counts)
    end

    private

    # A title the extractor will no longer vouch for has to be retracted, not merely
    # left in place — otherwise tightening the extractor can add good titles but never
    # remove bad ones, and the guidelines named after a bibliography entry stay named
    # after a bibliography entry forever. The catalog key is the honest fallback; it is
    # how a student cites the guideline anyway.
    def outcome(guideline, title)
      title = guideline.catalog_key if title.blank?
      return :unchanged if title == guideline.title

      was_named = guideline.title != guideline.catalog_key
      guideline.update!(title: title)
      title == guideline.catalog_key && was_named ? :retracted : :retitled
    end
  end
end
