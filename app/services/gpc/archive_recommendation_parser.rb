# Splits an archived guideline's extracted text into the graded statements it contains.
#
# The live site marks every statement up; a PDF only lays it out. CENETEC's template
# from 2008 to 2022 is a three-column table — a marker (E for evidence, R for
# recommendation, a tick for good practice), the statement, and a grading column
# stacking grade, scale and citation — and pdf-reader keeps that layout as runs of
# spaces. So this reads columns by position and statements by shape:
#
#   * The marker and the grading column are centred on their row, not aligned to its
#     first line, so a row cannot be read top-down. Lines are grouped into rows first,
#     then each row takes the marker and grades that fall inside it.
#   * Rows are separated by vertical space, which survives as blank lines — but so
#     does the space between two paragraphs of one statement. A blank line is only a
#     row boundary when the text on either side of it reads as two sentences.
#
# The output contract matches Gpc::RecommendationParser's, plus the kind the marker
# gave and the numbered heading the row sat under, which the importer turns into
# sections.
module Gpc
  class ArchiveRecommendationParser < ApplicationService
    TABLE_HEADER = %r{Evidencia\s*/\s*Recomendaci|Nivel\s*/\s*Grado}i

    # Every guideline explains its own grading with the same two sample rows before the
    # first real table. They are laid out exactly like the real thing.
    SAMPLE_ROWS = /zanamivir|escala de Braden|Matheson/i

    # The chapter that follows the graded statements. Only a whole line counts, so a
    # statement that mentions an algorithm does not end the table.
    CHAPTER_END = /\A(?:\d+\.?\s*)?(?:Anexos?|Bibliograf[íi]a|Algoritmos?|Definiciones\s+operativas|Glosario|
                   Agradecimientos|Comit[ée]\s+acad[ée]mico)\s*\z/ix

    NUMBERED_HEADING = /\A(\d{1,2}(?:\.\d{1,2})+)\.?\s*(\p{Lu}.*)\z/
    TABLE_OF_CONTENTS_LEADER = /\.{4,}/
    PAGE_NUMBER = /\A\d{1,3}\z/

    MARKER_KINDS = { "E" => "evidence", "R" => "recommendation" }.freeze
    # The good-practice tick is a Wingdings glyph that extracts as a private-use
    # character — U+F0FC on its own, or another in front of "/R" — or as nothing at all.
    GOOD_PRACTICE_MARKER = %r{\A[^\p{Alnum}\s]{0,2}\s?/\s?R\z|\A(?:PBP|[✓√✔\u{F0FC}])\z}

    # Justified text opens gaps of up to five spaces; the gutter before the grading
    # column is wider.
    GUTTER = 6

    SYMBOLS_ONLY = /\A[^\p{Alnum}]+\z/
    RUN_TOGETHER = /\p{L}{24,}/

    # Fewer marker letters than this and the markers were images.
    MIN_MARKERS = 3

    # Grading content sits well right of where the statement starts. Measured from
    # the statement column so that a page indented differently still reads right.
    GRADING_OFFSET = 20
    # A lone run this far right, with nothing else on its line, is grading content even
    # when it matches no pattern below — a citation's second line, say.
    LONE_GRADING_OFFSET = 30

    # Case matters for the letter grades: a justified line routinely ends in "a".
    GRADE_LEVEL = /\A(?:(?:I{1,3}|IV|V)(?:[- ]?[a-cA-C])?|[1-4](?:\+{1,2}|-|[a-cA-C])?|[A-D][+-]?)\z/
    GRADE_PHRASE = /\A(?:(?:muy\s+)?(?:alt|moderad|baj)[ao]s?(?:\s+calidad)?|fuerte|d[ée]bil|condicional|
                    (?:punto\s+de\s+)?buena(?:\s+pr[áa]ctica)?|pr[áa]ctica|PBP)\z/ix
    GRADE_WORDS = Regexp.union(GRADE_LEVEL, GRADE_PHRASE)
    CITATION_END = /\A[\p{Lu}(\[].*\d{4}[a-z]?\s*[)\]]?[.,;]?\z/
    BRACKETED = /\A[(\[]/
    EVIDENCE_SYMBOLS = /[⨁⊕◯○]/
    ET_AL = /\bet\.?\s*al\b/i

    TRAILING_CITATION = /\s(\p{Lu}[\p{L}\-']+(?:\s[A-Z]{1,3}\.?)*(?:\set\.?\s?al\.?)?,?\s?\d{4}[a-z]?\.?)\z/

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

    TERMINAL = /[.:;!?)]\z/
    CONTINUATION = /\A[\p{Ll},;)]/
    LIST_ITEM = /\A(?:[•·\-–]|\d{1,2}[.)]\s|[a-z][.)]\s)/
    PRIVATE_USE = /[\u{E000}-\u{F8FF}]/

    Line = Struct.new(:index, :marker, :text, :grading, :garbled, keyword_init: true)

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
      region = table_region
      return [] if region.empty?

      @text_column = text_column(region)
      return [] if @text_column.nil?

      @text_edge = text_edge(region)

      parsed = zones(region).flat_map { |heading, lines| rows(lines).filter_map { |row| statement(row, heading) } }
      intact = parsed.reject { |statement| damaged?(statement) }
      intact.size < parsed.size * (1 - DAMAGE_LIMIT) ? [] : intact
    end

    # A statement that opens lower-case is the tail of one the row cut went through.
    def damaged?(statement)
      text = statement[:text]
      statement[:garbled] || text.length < SHORTEST_STATEMENT || text.match?(/\A\p{Ll}/) ||
        text.match?(BLED_CITATION) || text.match?(WELDED)
    end

    # From the first real table header to the chapter after the tables, with running
    # headers and page numbers taken out so a row broken across a page reads as one.
    def table_region
      lines = without_page_furniture(text.split("\n").map { |line| line.gsub("\t", "    ").rstrip })
      start = lines.each_index.find { |i| lines[i].match?(TABLE_HEADER) && !sample?(lines, i) }
      return [] if start.nil?

      start = headings_above(lines, start)

      finish = (start...lines.size).find { |i| chapter_end?(lines[i]) } || lines.size
      lines[start...finish]
    end

    # The first table's own headings sit just above its header row.
    def headings_above(lines, start)
      index = start
      index -= 1 while index.positive? && (lines[index - 1].blank? || heading_text?(lines[index - 1]))
      index += 1 while index < start && lines[index].blank?
      index
    end

    def heading_text?(line)
      stripped = line.strip
      stripped.match?(NUMBERED_HEADING) && !stripped.match?(TABLE_OF_CONTENTS_LEADER)
    end

    def sample?(lines, index)
      lines[index, 12].join("\n").match?(SAMPLE_ROWS)
    end

    def chapter_end?(line)
      stripped = line.strip
      stripped.match?(CHAPTER_END) && !stripped.match?(TABLE_OF_CONTENTS_LEADER)
    end

    # A page ends in its number and the next opens with the guideline's running
    # header. Whatever follows a page number on three or more pages is that header.
    def without_page_furniture(lines)
      headers = Hash.new(0)
      lines.each_with_index do |line, i|
        next unless line.strip.match?(PAGE_NUMBER)

        headers[lines[(i + 1)..].find(&:present?).to_s.strip] += 1
      end
      running = headers.select { |_, count| count >= 3 }.keys.to_set

      lines.reject { |line| line.strip.match?(PAGE_NUMBER) || running.include?(line.strip) }
    end

    # Where statements start: the most common position of the text that follows a
    # marker on the same line.
    #
    # Some templates draw the markers as images, which extract as nothing. Those tables
    # are read without markers: the statement column is simply the most common place a
    # line starts, and each row is anchored on its grade instead.
    def text_column(region)
      starts = region.filter_map do |line|
        segments = segments(line)
        segments[1].first if segments.size > 1 && marker_kind(segments.first.last)
      end
      # A template can draw E and R as images and still print the good-practice tick as
      # a glyph, so only the letters decide which way the table is read.
      letters = region.count { |line| MARKER_KINDS.key?(segments(line).first&.last) }
      @anchored_on_grade = letters < MIN_MARKERS
      if @anchored_on_grade
        starts = region.filter_map { |line| segments(line).first.first if statement_line?(line) }
      end
      starts.tally.max_by(&:last)&.first
    end

    # Where statements end. Justified text ends on one column, so the most common end
    # is the column's right edge; grading content never starts left of it, which keeps
    # a justified line's last word — "peritoneal)" — out of the grading column. Ragged
    # text has no common end, and the furthest a line's text runs before a gutter
    # stands in.
    def text_edge(region)
      ends = region.filter_map { |raw| classified_text_end(raw) }
      edge, count = ends.select { |column| column >= @text_column + LONE_GRADING_OFFSET }.tally.max_by(&:last)
      return edge if count.to_i >= MIN_MARKERS

      region.filter_map { |raw| run_end(raw) }.max
    end

    def classified_text_end(raw)
      line = classify(raw, 0)
      return if line.text.nil?

      column, token = segments(raw).reverse.find { |_, candidate| line.text.end_with?(candidate) }
      column + token.length
    end

    def run_end(raw)
      segments = segments(raw).select { |column, _| column >= @text_column - 1 }
      return if segments.empty?

      run = segments.slice_when { |(a, token), (b, _)| b - a - token.length >= GUTTER }.first
      run.last.first + run.last.last.length
    end

    def statement_line?(line)
      line.split.size >= 4 && !line.match?(TABLE_HEADER)
    end

    # Runs of text separated by two or more spaces, with the column each starts at.
    def segments(line)
      line.to_enum(:scan, /\S+(?: \S+)*/).map { [Regexp.last_match.begin(0), Regexp.last_match[0]] }
    end

    # Rows never cross a numbered heading, so the region is cut at each one and every
    # piece remembers the headings above it.
    def zones(region)
      headings = []
      lines = region.each_with_index.filter_map do |raw, index|
        heading = numbered_heading(raw)
        next [headings, classify(raw, index)] unless heading

        headings = headings.select { |number, _| heading.first.start_with?("#{number}.") } + [heading]
        nil
      end
      lines.chunk_while { |a, b| a.first.equal?(b.first) }.map { |pairs| [pairs.first.first, pairs.map(&:last)] }
    end

    def numbered_heading(raw)
      segments = segments(raw)
      return unless segments.size == 1 && segments.first.first < @text_column + GRADING_OFFSET

      match = segments.first.last.match(NUMBERED_HEADING)
      [match[1], match[2].squish] if match && !match[2].match?(TABLE_OF_CONTENTS_LEADER)
    end

    def classify(raw, index)
      return Line.new(index: index) if raw.blank? || raw.match?(TABLE_HEADER)

      segments = segments(raw)
      in_marker_column = segments.first.first < @text_column - 1
      marker = marker_kind(segments.first.last) if !@anchored_on_grade && in_marker_column
      segments = segments.drop(1) if marker || (in_marker_column && icon?(segments))
      return Line.new(index: index, marker: marker) if segments.empty?

      trailing = grading_segments(segments)
      segments, trailing = split_glued_citation(segments - trailing, trailing)
      text = segments.map(&:last).join(" ")
      grading = trailing.map(&:last).join(" ").presence
      marker ||= kind_from_grade(grading) if @anchored_on_grade && grading
      Line.new(index: index, marker: marker, text: text.presence, grading: grading, garbled: garbled?(text))
    end

    # A marker drawn as an icon we cannot name is still not statement text. A list
    # bullet is a glyph too, but it sits right against its item; a marker stands a
    # gutter away from the statement.
    def icon?(segments)
      (column, token), following = segments
      return false unless token.match?(SYMBOLS_ONLY)

      following.nil? || following.first - column - token.length >= GUTTER
    end

    # pdf-reader sometimes drops the spaces of a justified line:
    # "Larehidrataciónvíaintravenosa serecomiendaenpacientes". Measured across the
    # archive, the longest real words run to 23 letters (colangiopancreatografía) and
    # text that lost its spaces starts at about 21.
    def garbled?(text)
      text.match?(RUN_TOGETHER)
    end

    # A long line can close the gutter to a single space, which the two-space split
    # cannot see: "…aproximadamente de Latenser BA, 2009". A citation that starts at the
    # statement column's right edge is grading content however little space precedes it.
    def split_glued_citation(segments, trailing)
      return [segments, trailing] if segments.empty? || @text_edge.nil?

      column, token = segments.last
      match = token.match(TRAILING_CITATION)
      return [segments, trailing] unless match && column + match.begin(1) >= @text_edge - 3

      head = token[0...match.begin(1)].rstrip
      [[*segments[0...-1], [column, head]], [[column + match.begin(1), match[1]], *trailing]]
    end

    # Without a marker, the grade is the only clue to what a row is. The convention
    # every scale in the corpus follows: evidence is graded with numbers, recommendations
    # with letters or strength words.
    def kind_from_grade(grading)
      return "good_practice" if grading.match?(/\A(?:PBP|punto de buena)/i)

      first = grading.split.first
      return "recommendation" if first.match?(/\A(?:[A-D][+-]?|fuerte|d[ée]bil|condicional)\z/i)

      "evidence" if first.match?(GRADE_LEVEL) || first.match?(/\A(?:muy|alt[ao]|moderad[ao]|baj[ao])\z/i)
    end

    def marker_kind(token)
      return "good_practice" if token.match?(GOOD_PRACTICE_MARKER)

      MARKER_KINDS[token]
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
        break unless column >= @text_column + GRADING_OFFSET
        break if @text_edge && column < @text_edge - 3

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
      return column >= @text_column + LONE_GRADING_OFFSET || ambiguous?(token) if gap.nil?

      gap >= GUTTER && (ambiguous?(token) || (@text_edge.present? && column > @text_edge + 1))
    end

    def unmistakable?(token)
      token.match?(CITATION_END) || token.match?(BRACKETED) || token.match?(EVIDENCE_SYMBOLS) ||
        token.match?(ET_AL) || token.match?(/\AShekelle/i) || (token.length > 1 && token.match?(GRADE_LEVEL))
    end

    def ambiguous?(token)
      token.match?(GRADE_WORDS) || scale_name(token).present?
    end

    def scale_name(token)
      cleaned = token.delete("[]()").sub(/\A[ER]\s*:\s*/, "").squish
      cleaned if cleaned.length >= 3 && cleaned.match?(RecommendationParser::SCALE_SHAPE) &&
                 !RecommendationParser::NON_SCALE_TOKENS.include?(cleaned) &&
                 !cleaned.match?(RecommendationParser::ROMAN_GRADE)
    end

    # Lines between blank lines form a block. A block runs into the next when the text
    # does — the first ends mid-sentence, or the second starts lower-case — and each
    # resulting group of blocks is one row per marker it holds.
    def rows(lines)
      groups = glued(blocks(lines))
      attach_unmarked(groups).flat_map { |group| split_by_marker(group) }
    end

    def blocks(lines)
      lines.slice_when { |a, b| empty?(a) || empty?(b) }.reject { |block| block.all? { |line| empty?(line) } }
    end

    def empty?(line)
      line.text.nil? && line.marker.nil? && line.grading.nil?
    end

    def glued(blocks)
      blocks.slice_when { |a, b| !continues?(a, b) }.to_a
    end

    def continues?(before, after)
      last = before.filter_map(&:text).last
      first = after.filter_map(&:text).first
      return false unless last && first

      first.match?(CONTINUATION) || !last.match?(TERMINAL)
    end

    # A group with no marker is a paragraph standing between two rows. It joins the row
    # whose marker is nearer, since both marker and statement are centred on the row.
    # Grading with no text is the tail of the stack above it — the grade and scale
    # printed, then a page or a gap, then the citation — so it joins the row before.
    def attach_unmarked(groups)
      marked = groups.select { |group| markers(group).any? }
      return [] if marked.empty?

      (groups - marked).each { |group| owner(group, marked).concat(group) }
      marked.map { |group| group.sort_by { |block| block.first.index } }
    end

    def owner(group, marked)
      lines = group.flatten
      start = lines.first.index
      previous = marked.select { |candidate| candidate.flatten.first.index < start }.last
      return previous if previous && lines.none?(&:text)

      middle = lines.sum(&:index) / lines.size.to_f
      marked.min_by { |candidate| markers(candidate).map { |line| (line.index - middle).abs }.min }
    end

    def markers(group)
      group.flatten.select(&:marker)
    end

    # Two markers in one group means two rows the blank-line test could not separate.
    # The cut goes between them, where the text most looks like a new statement.
    def split_by_marker(group)
      lines = group.flatten
      block_starts = group.map { |block| lines.index(block.first) }.to_set
      marker_positions = lines.each_index.select { |i| lines[i].marker }
      cuts = marker_positions.each_cons(2).map { |a, b| cut_between(lines, a, b, block_starts) }
      [0, *cuts, lines.size].each_cons(2).map { |from, to| lines[from...to] }
    end

    # A sentence break outranks a blank line, since a page break leaves blank lines in
    # the middle of a sentence; nearness to the midpoint between markers settles ties.
    # The cut may land on a line with no text — a marker or a grade standing alone —
    # and is then judged by the text that follows it.
    def cut_between(lines, first, second, block_starts)
      midpoint = (first + second + 1) / 2.0
      candidates = ((first + 1)..second).select do |i|
        following = lines[i..].filter_map(&:text).first
        following && !following.match?(CONTINUATION)
      end
      best = candidates.max_by { |i| [break_score(lines, i, block_starts), -(i - midpoint).abs] }
      best || midpoint.ceil
    end

    def break_score(lines, index, block_starts)
      before = lines[0...index].filter_map(&:text).last
      after = lines[index..].filter_map(&:text).first
      score = block_starts.include?(index) ? 1 : 0
      score += 2 if before.nil? || before.match?(TERMINAL)
      score += 2 if after.match?(/\A[\p{Lu}¿¡•]/) || after.match?(LIST_ITEM)
      score
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

      grading(label, kind).merge(
        text: text, label: label, kind: kind,
        chapter: headings.first&.join(" "), heading: headings.last&.join(" ")
      )
    end

    def statement_text(row)
      row.filter_map(&:text).map { |line| line.gsub(/\A#{PRIVATE_USE}\s*/o, "• ").gsub(PRIVATE_USE, "") }
         .map(&:squish).compact_blank
         .slice_before { |line| line.match?(LIST_ITEM) }
         .map { |lines| lines.join(" ") }
         .join("\n")
    end

    # "III (Shekelle,1999) Humes, 2008", "Ia [E: Shekelle] Matheson, 2007",
    # "ALTO GRADE Turc G, 2019", "Punto de Buena Práctica". The grade leads, the scale
    # is the first thing that names one, and what is left is the citation.
    def grading(label, kind)
      return { grade: "PBP", scale: nil, citation: nil } if good_practice_label?(label, kind)

      scale_match = label.match(/[\[(]\s*(?:[ER]\s*:\s*)?(Shekelle(?:\s+modificada)?)[^\])]*[\])]/i) ||
                    label.match(/\b(Shekelle)\b/i)
      rest = scale_match ? label.sub(scale_match[0], " ") : label
      tokens = rest.split

      scale = scale_match ? "Shekelle" : nil
      if scale.nil?
        index = tokens.index { |token| scale_name(token) }
        scale = scale_name(tokens.delete_at(index)) if index
      end

      grade = leading_grade(tokens)
      { grade: grade, scale: scale, citation: tokens.join(" ").delete("[]").squish.presence }
    end

    def good_practice_label?(label, kind)
      kind == "good_practice" && (label == "PBP" || label.match?(/buena\s+pr[áa]ctica/i))
    end

    # The grade usually leads, sometimes behind a word naming it ("Nivel 3", "Clase I").
    # When a row's cut put the citation first, the grade follows the citation's year.
    def leading_grade(tokens)
      tokens.shift if tokens.first.to_s.match?(/\A(?:nivel|grado|clase)\z/i) && tokens[1].to_s.match?(GRADE_WORDS)
      return tokens.shift(2).join(" ") if tokens.size > 1 && tokens.first(2).join(" ").match?(GRADE_PHRASE)
      return tokens.shift if tokens.first.to_s.match?(GRADE_WORDS)

      symbols = tokens.take_while { |token| token.match?(EVIDENCE_SYMBOLS) }
      return tokens.shift(symbols.size).join(" ") if symbols.any?

      index = tokens.each_index.find { |i| i.positive? && trailing_grade?(tokens, i) }
      tokens.delete_at(index) if index
    end

    # A letter grade is also an author's initial ("Smith D, 2010"), so a lone letter
    # only counts straight after a year or a closing mark. Longer grades are unambiguous.
    def trailing_grade?(tokens, index)
      token = tokens[index]
      return true if token.length > 1 && token.match?(GRADE_LEVEL)

      token.match?(/\A[A-D]\z/) && tokens[index - 1].match?(/[\d.)\]]\z/)
    end
  end
end
