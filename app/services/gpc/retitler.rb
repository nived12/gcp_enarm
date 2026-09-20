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

        counts[outcome(guideline, DocumentTitle.call(section.body).payload)] += 1
      end

      success(counts)
    end

    private

    def outcome(guideline, title)
      # A guideline whose header never extracted keeps its catalog key as its name,
      # which is how a student cites it anyway.
      return :unreadable if title.blank?
      return :unchanged if title == guideline.title

      guideline.update!(title: title)
      :retitled
    end
  end
end
