module Gpc
  module ArchiveTable
    # Finds the evidence tables inside a whole guideline's text: from the first real table
    # header to the chapter after the tables, with running headers and page numbers taken
    # out so a row broken across a page reads as one.
    class Region
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

      def initialize(text)
        @text = text.to_s
      end

      # Empty when the text holds no table.
      def lines
        lines = without_page_furniture(text.split("\n").map { |line| line.gsub("\t", "    ").rstrip })
        start = lines.each_index.find { |i| lines[i].match?(TABLE_HEADER) && !sample?(lines, i) }
        return [] if start.nil?

        start = headings_above(lines, start)
        finish = (start...lines.size).find { |i| chapter_end?(lines[i]) } || lines.size
        lines[start...finish]
      end

      private

      attr_reader :text

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
    end
  end
end
