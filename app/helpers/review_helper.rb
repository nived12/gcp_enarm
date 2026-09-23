module ReviewHelper
  # Marks the quoted span inside the full recommendation, so a reviewer can see at a
  # glance whether the question used it fairly or lifted it out of context.
  #
  # Matched with any run of whitespace allowed between the quote's words, because the
  # stored text keeps the line breaks the source had and the model writes a space. The
  # match runs against the original string, so what renders is the guideline as written
  # rather than a flattened copy.
  def highlighted(text, quote)
    return text if quote.blank?

    match = text.match(pattern_for(quote))
    return text if match.nil?

    # No classes: the stylesheet styles `mark` inside .vignette, and that is the only
    # place --highlight is permitted to appear.
    safe_join([match.pre_match, tag.mark(match[0]), match.post_match])
  end

  # The second opinion's verdict on a case, naming the cases it has not read yet too.
  def verdict_of(clinical_case)
    clinical_case.verification_verdict || "unverified"
  end

  # Words carry the verdict; colour only agrees with them, as it does for answers. A
  # dispute is the one that must stand out, and "not read yet" the one that should not.
  VERDICT_CLASSES = {
    "supported" => "border-correct text-correct",
    "ambiguous" => "border-line-strong text-ink",
    "unsupported" => "border-incorrect bg-incorrect-soft text-incorrect",
    "unverified" => "border-line text-ink-faint"
  }.freeze

  def verdict_classes(verdict)
    VERDICT_CLASSES.fetch(verdict)
  end

  private

  def pattern_for(quote)
    Regexp.new(
      quote.squish.split(" ").map { |word| Regexp.escape(word) }.join('\s+'),
      Regexp::IGNORECASE
    )
  end
end
