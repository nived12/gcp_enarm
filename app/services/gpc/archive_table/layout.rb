module Gpc
  module ArchiveTable
    # Where a table's columns sit, measured from the table itself, and each line split into
    # them: the marker (E, R, a tick), the statement, and the grading column stacking grade,
    # scale and citation.
    #
    # pdf-reader keeps the layout as runs of spaces, so a column is a position, not a tag.
    # Positions are measured per document because templates and page margins vary.
    class Layout
      MARKER_KINDS = { "E" => "evidence", "R" => "recommendation" }.freeze
      # The good-practice tick is a Wingdings glyph that extracts as a private-use
      # character — U+F0FC on its own, or another in front of "/R" — or as nothing at all.
      GOOD_PRACTICE_MARKER = %r{\A[^\p{Alnum}\s]{0,2}\s?/\s?R\z|\A(?:PBP|[✓√✔\u{F0FC}])\z}

      # Fewer marker letters than this and the markers were images.
      MIN_MARKERS = 3

      # Justified text opens gaps of up to five spaces; the gutter before the grading
      # column is wider.
      GUTTER = 6

      # Grading content sits well right of where the statement starts. Measured from
      # the statement column so that a page indented differently still reads right.
      GRADING_OFFSET = 20
      # A lone run this far right, with nothing else on its line, is grading content even
      # when it matches no pattern below — a citation's second line, say.
      LONE_GRADING_OFFSET = 30

      # What a grade-anchored row's grading opens with when it is evidence: "alta", "baja".
      EVIDENCE_WORD = /\A(?:muy|alt[ao]|moderad[ao]|baj[ao])\z/i

      SYMBOLS_ONLY = /\A[^\p{Alnum}]+\z/
      CITATION_END = /\A[\p{Lu}(\[].*\d{4}[a-z]?\s*[)\]]?[.,;]?\z/
      BRACKETED = /\A[(\[]/
      ET_AL = /\bet\.?\s*al\b/i
      TRAILING_CITATION = /\s(\p{Lu}[\p{L}\-']+(?:\s[A-Z]{1,3}\.?)*(?:\set\.?\s?al\.?)?,?\s?\d{4}[a-z]?\.?)\z/

      # pdf-reader sometimes drops the spaces of a justified line:
      # "Larehidrataciónvíaintravenosa serecomiendaenpacientes". Measured across the
      # archive, the longest real words run to 23 letters (colangiopancreatografía) and
      # text that lost its spaces starts at about 21.
      RUN_TOGETHER = /\p{L}{24,}/

      # Runs of text separated by two or more spaces, with the column each starts at.
      def self.segments(line)
        line.to_enum(:scan, /\S+(?: \S+)*/).map { [Regexp.last_match.begin(0), Regexp.last_match[0]] }
      end

      attr_reader :text_column

      def initialize(region)
        @region = region
        @text_column = measure_text_column
        @text_edge = measure_text_edge if @text_column
      end

      # False when nothing in the region looks like a statement column.
      def readable?
        !text_column.nil?
      end

      # A heading alone on its line, near the statement column: ["4.2.1", "Diagnóstico"].
      def numbered_heading(raw)
        segments = segments(raw)
        return unless segments.size == 1 && segments.first.first < text_column + GRADING_OFFSET

        match = segments.first.last.match(Region::NUMBERED_HEADING)
        [match[1], match[2].squish] if match && !match[2].match?(Region::TABLE_OF_CONTENTS_LEADER)
      end

      def classify(raw, index)
        return Line.new(index: index) if raw.blank? || Region.table_header?(raw)

        segments = segments(raw)
        in_marker_column = segments.first.first < text_column - 1
        marker = marker_kind(segments.first.last) if !anchored_on_grade? && in_marker_column
        segments = segments.drop(1) if marker || (in_marker_column && icon?(segments))
        return Line.new(index: index, marker: marker) if segments.empty?

        trailing = grading_segments(segments)
        segments, trailing = split_glued_citation(segments - trailing, trailing)
        text = segments.map(&:last).join(" ")
        grading = trailing.map(&:last).join(" ").presence
        marker ||= kind_from_grade(grading) if anchored_on_grade? && grading
        Line.new(
          index: index, marker: marker, text: text.presence, grading: grading,
          garbled: text.match?(RUN_TOGETHER)
        )
      end

      private

      attr_reader :region, :text_edge

      def segments(line) = self.class.segments(line)

      # Some templates draw the markers as images, which extract as nothing. Those tables
      # are read without markers, and each row is anchored on its grade instead. A
      # template can draw E and R as images and still print the good-practice tick as a
      # glyph, so only the letters decide which way the table is read.
      def anchored_on_grade?
        return @anchored_on_grade if defined?(@anchored_on_grade)

        @anchored_on_grade = region.count { |line| MARKER_KINDS.key?(segments(line).first&.last) } < MIN_MARKERS
      end

      # Where statements start: the most common position of the text that follows a
      # marker on the same line — or, without markers, the most common place a line starts.
      def measure_text_column
        starts = if anchored_on_grade?
          region.filter_map { |line| segments(line).first.first if statement_line?(line) }
        else
          region.filter_map do |line|
            segments = segments(line)
            segments[1].first if segments.size > 1 && marker_kind(segments.first.last)
          end
        end
        starts.tally.max_by(&:last)&.first
      end

      def statement_line?(line)
        line.split.size >= 4 && !Region.table_header?(line)
      end

      # Where statements end. Justified text ends on one column, so the most common end
      # is the column's right edge; grading content never starts left of it, which keeps
      # a justified line's last word — "peritoneal)" — out of the grading column. Ragged
      # text has no common end, and the furthest a line's text runs before a gutter
      # stands in.
      def measure_text_edge
        ends = region.filter_map { |raw| classified_text_end(raw) }
        edge, count = ends.select { |column| column >= text_column + LONE_GRADING_OFFSET }.tally.max_by(&:last)
        return edge if count.to_i >= MIN_MARKERS

        region.filter_map { |raw| run_end(raw) }.max
      end

      # Runs before the edge exists, so the edge is measured from lines classified
      # without one.
      def classified_text_end(raw)
        line = classify(raw, 0)
        return if line.text.nil?

        column, token = segments(raw).reverse.find { |_, candidate| line.text.end_with?(candidate) }
        column + token.length
      end

      def run_end(raw)
        segments = segments(raw).select { |column, _| column >= text_column - 1 }
        return if segments.empty?

        run = segments.slice_when { |(a, token), (b, _)| b - a - token.length >= GUTTER }.first
        run.last.first + run.last.last.length
      end

      def marker_kind(token)
        return "good_practice" if token.match?(GOOD_PRACTICE_MARKER)

        MARKER_KINDS[token]
      end

      # A marker drawn as an icon we cannot name is still not statement text. A list
      # bullet is a glyph too, but it sits right against its item; a marker stands a
      # gutter away from the statement.
      def icon?(segments)
        (column, token), following = segments
        return false unless token.match?(SYMBOLS_ONLY)

        following.nil? || following.first - column - token.length >= GUTTER
      end

      # Without a marker, the grade is the only clue to what a row is. The convention
      # every scale in the corpus follows: evidence is graded with numbers, recommendations
      # with letters or strength words.
      def kind_from_grade(grading)
        return "good_practice" if grading.match?(/\A(?:PBP|punto de buena)/i)

        first = grading.split.first
        return "recommendation" if first.match?(/\A(?:[A-D][+-]?|fuerte|d[ée]bil|condicional)\z/i)

        "evidence" if first.match?(GradingLabel::GRADE_LEVEL) || first.match?(EVIDENCE_WORD)
      end

      # A long line can close the gutter to a single space, which the two-space split
      # cannot see: "…aproximadamente de Latenser BA, 2009". A citation that starts at the
      # statement column's right edge is grading content however little space precedes it.
      def split_glued_citation(segments, trailing)
        return [segments, trailing] if segments.empty? || text_edge.nil?

        column, token = segments.last
        match = token.match(TRAILING_CITATION)
        return [segments, trailing] unless match && column + match.begin(1) >= text_edge - 3

        head = token[0...match.begin(1)].rstrip
        [[*segments[0...-1], [column, head]], [[column + match.begin(1), match[1]], *trailing]]
      end

      # Read from the right: trailing runs belong to the grading column while they sit far
      # enough right and look like grading content. The first run that does not stops it,
      # because the grading column is always the rightmost thing on a line.
      #
      # A run past the statement column's right edge is grading content whatever it says —
      # a citation's long title — but only across a real gutter: an indented list item
      # can overshoot the edge, and justification opens gaps of up to five spaces inside it.
      def grading_segments(segments)
        grading = []
        segments.each_with_index.reverse_each do |(column, token), index|
          break unless column >= text_column + GRADING_OFFSET
          break if text_edge && column < text_edge - 3

          gap = index.zero? ? nil : column - segments[index - 1].first - segments[index - 1].last.length
          break unless grading?(token, column, gap)

          grading.unshift([column, token])
        end
        grading
      end

      # Unmistakable grading content needs only the two spaces that separate any runs.
      # Anything a statement could also end with — a letter, "alta", an acronym, or text
      # past the right edge — needs a gutter wider than justification ever opens, or a
      # line of its own.
      def grading?(token, column, gap)
        return true if unmistakable?(token)
        return column >= text_column + LONE_GRADING_OFFSET || ambiguous?(token) if gap.nil?

        gap >= GUTTER && (ambiguous?(token) || (text_edge.present? && column > text_edge + 1))
      end

      def unmistakable?(token)
        token.match?(CITATION_END) || token.match?(BRACKETED) || token.match?(GradingLabel::EVIDENCE_SYMBOLS) ||
          token.match?(ET_AL) || token.match?(/\AShekelle/i) ||
          (token.length > 1 && token.match?(GradingLabel::GRADE_LEVEL))
      end

      def ambiguous?(token)
        token.match?(GradingLabel::GRADE_WORDS) || GradingLabel.scale_name(token).present?
      end
    end
  end
end
