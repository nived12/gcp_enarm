# Reads a guideline's title out of its extracted PDF text.
#
# The cover sets the title in display type that extracts as fragments ("S OBREPESO Y
# O BESIDAD"), so the title is taken from the running header instead — one clean line
# the template repeats on nearly every page. Two signals find it: the header is the line
# that follows "Catálogo Maestro", and it is among the most repeated lines in the file.
# The first is precise, the second is the fallback when a scan lost the marker.
#
# Kept apart from PdfExtractor so a title can be re-derived from text already stored,
# without downloading 700 PDFs from the archive a second time.
module Gpc
  class DocumentTitle < ApplicationService
    LENGTH = (20..200).freeze
    CATALOG_MARKER = /Cat[áa]logo Maestro/i

    # The cover and every page footer print the catalog key, and the running header sits
    # directly under it. The legal boilerplate says "Catálogo Maestro" too, in prose, so
    # the key itself — not the phrase — is what identifies the real marker.
    KEY_LINE = /\A.{0,120}\z/m
    CATALOG_KEY = /(?<![[:alnum:]])[A-Z]{1,7}-\d{3,4}-\d{2}(?![[:alnum:]])/

    # Content that repeats as often as a running header does, and is not one. Search
    # strategies, bibliography entries, metadata tables, bullet lists and table cells all
    # recur across pages, and when pdf-reader cannot recover a guideline's header they
    # are what the most-repeated-line fallback lands on instead. A wrong title is worse
    # than none: the student reads nonsense, and TopicLinker matches the nonsense.
    JUNK = [
      /#\d/, /\[PDAT\]/i, /\[Mesh/i, /\bOR\b.*\bAND\b/, /[•✓]/, /["“”]/,
      /\A\d+\.\s/, /\A[-–]/, /\bet al\b/i, /\d\.\d+\./, %r{ / },
      /\A(Profesionales|Secretario|Director|Resultados|Actualizaci[óo]n Fecha)\b/i,
      /Fecha de publicaci[óo]n/i,
      /\A(Fuente|Bibliograf|Algoritmo de b[úu]squeda|Divisi[óo]n de Excelencia|Coordinaci[óo]n de UMAE)/i,
      /\bUMAE\b|\bIMSS\b.*\bCoordinaci/i
    ].freeze

    # A guideline title is a title: it starts with a capital. Nearly everything the
    # fallback otherwise lands on is a fragment cut out of the middle of a sentence, a
    # flowchart cell or an English journal citation — "pronation in paralytic supination
    # posture", "sin antecedentes de cardiopatía", "en los tres niveles de atención".
    SENTENCE_START = /\A[[:upper:]]/

    # The bibliography is English and the guidelines are not. Two function words is
    # enough to tell them apart and far too few to appear in a Spanish title.
    ENGLISH_MARKERS = /(?<![[:alnum:]])(the|of|and|in|for|with|from|study|journal)(?![[:alnum:]])/i
    MAXIMUM_ENGLISH_MARKERS = 1

    # A title is prose: mostly letters and spaces, and more than a couple of words.
    MINIMUM_WORDS = 2
    MINIMUM_LETTER_RATIO = 0.75

    # Lines the template repeats as often as the title.
    EXCLUSIONS = [
      CATALOG_MARKER, /\AGu[íi]a de Pr[áa]ctica Cl[íi]nica/i, /\AEvidencias y Recomendaciones/i,
      /\AResumen de Evidencias/i, /DIRECTORIO/i, /CENETEC/i, /\Awww\./i, /\Ahttps?:/i,
      /\AAv(enida|\.)/i, /\AC\. ?P\. ?\d/i, /Colonia|Col\./i, /Copyright|©/i,
      /\AEditor/i, /\AISBN/i, /\bJournal\b|\bdoi\b/i
    ].freeze

    # Pre-2015 scans come back with every space dropped. Title case puts the boundaries
    # back where it can; what is still one long run afterwards is unreadable, and the
    # caller falls back to the catalog key — which is how a student cites it anyway.
    # A scan spaced letter by letter is beyond repair — collapsing it yields one
    # 28-character word — so it is refused outright rather than returned as a title
    # no one can read.
    RUN_TOGETHER = /\p{Lower}\p{Upper}/
    LETTER_SPACED = /\A(?:\S ){6,}/
    LONGEST_REAL_WORD = 24

    def initialize(text)
      super()
      @text = text
    end

    def call
      lines = @text.to_s.lines.map(&:squish)
      title = from_key_line(lines) || most_repeated(lines)
      return failure("No se encontró un título legible") if title.blank?

      success(title)
    end

    private

    # The running header is printed directly after the catalog key, so the line after a
    # key line is the title far more often than not. Taking the most frequent such line
    # rather than the first keeps one odd page from deciding the name.
    def from_key_line(lines)
      candidates = lines.each_cons(2).filter_map do |marker, following|
        repaired = repair(following)
        repaired if key_line?(marker) && usable?(repaired)
      end

      candidates.tally.max_by { |line, count| [count, line.length] }&.first
    end

    def key_line?(line)
      line.match?(KEY_LINE) && line.match?(CATALOG_KEY)
    end

    # Only reached when pdf-reader did not recover the running header.
    def most_repeated(lines)
      counts = Hash.new(0)
      lines.uniq.each do |line|
        repaired = repair(line)
        counts[repaired] += lines.count(line) if usable?(repaired)
      end

      counts.max_by { |line, count| [count, line.length] }&.first
    end

    def prose?(line)
      return false unless line.match?(SENTENCE_START)
      return false if JUNK.any? { |pattern| line.match?(pattern) }
      return false if line.scan(ENGLISH_MARKERS).size > MAXIMUM_ENGLISH_MARKERS
      return false if line.split(" ").size < MINIMUM_WORDS

      # scan, not count: String#count reads "[[:alpha:]]" as a literal set of brackets
      # and letters rather than as a character class, and silently scores every title
      # about 0.30.
      letters = line.scan(/[[:alpha:][:space:]]/).size
      letters.to_f / line.length >= MINIMUM_LETTER_RATIO
    end

    def usable?(line)
      return false unless LENGTH.cover?(line.to_s.length)
      return false if line.match?(LETTER_SPACED)
      return false if EXCLUSIONS.any? { |pattern| line.match?(pattern) }
      return false unless prose?(line)

      line.split(" ").none? { |word| word.length > LONGEST_REAL_WORD }
    end

    def repair(line)
      return line.squish unless line.match?(RUN_TOGETHER)

      line.gsub(/(\p{Lower})(\p{Upper})/, '\1 \2').squish
    end
  end
end
