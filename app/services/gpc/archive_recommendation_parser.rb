# Splits an archived guideline's extracted text into the graded statements it contains.
#
# The live site marks every statement up; a PDF only lays it out. CENETEC's template from
# 2008 to 2022 is a three-column table — a marker (E for evidence, R for recommendation,
# a tick for good practice), the statement, and a grading column stacking grade, scale
# and citation. Reading it takes four steps, each in Gpc::ArchiveTable:
#
#   1. Region        — find the tables in the whole document's text.
#   2. Layout        — measure where the columns sit and split each line into them.
#   3. RowAssembler  — group lines into rows, one per marker.
#   4. GradingLabel  — read grade, scale and citation out of a row's grading column.
#
# What this class adds is the last judgement: a row the extraction damaged is dropped,
# not repaired, and a document where too many rows are damaged yields nothing.
#
# The output contract matches Gpc::RecommendationParser's, plus the kind the marker gave
# and the numbered heading the row sat under, which the section builder turns into
# sections.
module Gpc
  class ArchiveRecommendationParser < ApplicationService
    # What is left of the grading column once it has run into a statement: a citation
    # outside any parenthesis, or one welded to the word before it. Rows carrying either
    # are dropped rather than repaired — the characters underneath are gone.
    BLED_CITATION = /(?<![(\[;,]\s)(?<![(\[])\b\p{Lu}[\p{Ll}\-]+
                     (?:\s[A-Z]{1,3}\.?)?(?:\set\.?\s?al\.?)?,\s?(?:19|20)\d{2}\b/x
    WELDED = /[\p{Ll}\d:](?:\p{Lu}[\p{Ll}\-]+(?:\s[A-Z]{1,3}\.?)?|[A-Z]{3,}),\s?\d{4}/
    SHORTEST_STATEMENT = 25

    # A guideline where this many rows came out damaged is laid out in a way this
    # parser does not understand, and its clean-looking rows are not to be trusted either.
    DAMAGE_LIMIT = 0.4

    PRIVATE_USE = /[\u{E000}-\u{F8FF}]/

    def initialize(text)
      super()
      @text = text.to_s
    end

    def call
      success(statements)
    end

    private

    attr_reader :text

    def statements
      region = ArchiveTable::Region.new(text).lines
      return [] if region.empty?

      layout = ArchiveTable::Layout.new(region)
      return [] unless layout.readable?

      parsed = zones(region, layout).flat_map do |headings, lines|
        ArchiveTable::RowAssembler.new(lines).rows.filter_map { |row| statement(row, headings) }
      end
      intact = parsed.reject { |statement| damaged?(statement) }
      intact.size < parsed.size * (1 - DAMAGE_LIMIT) ? [] : intact
    end

    # Rows never cross a numbered heading, so the region is cut at each one and every
    # piece remembers the headings above it.
    def zones(region, layout)
      headings = []
      lines = region.each_with_index.filter_map do |raw, index|
        heading = layout.numbered_heading(raw)
        next [headings, layout.classify(raw, index)] unless heading

        headings = headings.select { |number, _| heading.first.start_with?("#{number}.") } + [heading]
        nil
      end
      lines.chunk_while { |a, b| a.first.equal?(b.first) }.map { |pairs| [pairs.first.first, pairs.map(&:last)] }
    end

    # Every row holds exactly one marker: rows are cut between markers, never around one.
    def statement(row, headings)
      kind = row.find(&:marker).marker
      text = statement_text(row)
      label = row.filter_map(&:grading).join(" ").squish
      return if text.blank?
      return { text: text, garbled: true } if row.any?(&:garbled)

      label = "PBP" if label.blank? && kind == "good_practice"
      return if label.blank?

      ArchiveTable::GradingLabel.parse(label, kind).merge(
        text: text, label: label, kind: kind,
        chapter: headings.first&.join(" "), heading: headings.last&.join(" ")
      )
    end

    # A list item keeps its own line, and a private-use glyph opening a line is a bullet
    # drawn in a symbol font.
    def statement_text(row)
      row.filter_map(&:text).map { |line| line.gsub(/\A#{PRIVATE_USE}\s*/o, "• ").gsub(PRIVATE_USE, "") }
         .map(&:squish).compact_blank
         .slice_before { |line| line.match?(ArchiveTable::RowAssembler::LIST_ITEM) }
         .map { |lines| lines.join(" ") }
         .join("\n")
    end

    # A statement that opens lower-case is the tail of one the row cut went through.
    def damaged?(statement)
      text = statement[:text]
      statement[:garbled] || text.length < SHORTEST_STATEMENT || text.match?(/\A\p{Ll}/) ||
        text.match?(BLED_CITATION) || text.match?(WELDED)
    end
  end
end
