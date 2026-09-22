module Gpc
  module ArchiveTable
    # Groups a table's classified lines into rows, one per marker.
    #
    # The marker and the grading column are centred on their row, not aligned to its first
    # line, so a row cannot be read top-down: lines are grouped first, and each group then
    # takes the marker and grades that fall inside it. Rows are separated by vertical
    # space, which survives as blank lines — but so does the space between two paragraphs
    # of one statement, so a blank line is only a boundary when the text on either side of
    # it reads as two sentences.
    class RowAssembler
      TERMINAL = /[.:;!?)]\z/
      CONTINUATION = /\A[\p{Ll},;)]/
      LIST_ITEM = /\A(?:[•·\-–]|\d{1,2}[.)]\s|[a-z][.)]\s)/

      def initialize(lines)
        @lines = lines
      end

      # Each row is an array of Lines holding exactly one marker.
      def rows
        attach_unmarked(glued(blocks)).flat_map { |group| split_by_marker(group) }
      end

      private

      attr_reader :lines

      # Lines between blank lines form a block.
      def blocks
        lines.slice_when { |a, b| a.empty? || b.empty? }.reject { |block| block.all?(&:empty?) }
      end

      # A block runs into the next when the text does: the first ends mid-sentence, or the
      # second starts lower-case.
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
    end
  end
end
