# One question asked about a clinical case, with the recommendation it came from.
#
# source_quote is the span of that recommendation the model claims to be using, and it
# must be a literal substring of it. That check runs in Ruby before the row is written —
# deterministic, free, and it catches a fabricated citation from any model, which is what
# makes generating on a cheap model acceptable at all.
class Question < ApplicationRecord
  belongs_to :clinical_case
  belongs_to :recommendation, optional: true

  has_many :answer_options, -> { order(:position) }, dependent: :destroy, inverse_of: :question

  OPTION_COUNT = 4

  validates :text, presence: true
  validates :position, presence: true, uniqueness: { scope: :clinical_case_id }
  validate :quote_must_come_from_the_recommendation

  def correct_option
    answer_options.find(&:correct?)
  end

  # What the review screen shows: the recommendation, its grade, and the year, so a
  # student can judge an eight-year-old guideline for herself.
  def citation
    recommendation&.cited_as
  end

  private

  # Compared with whitespace collapsed on both sides. The stored text keeps the line
  # breaks that PDF and HTML extraction leave behind — "se deben evitar:\nPicos
  # hiperóxicos" — and no model reproduces those when quoting; it writes a space.
  # Measured: that alone accounted for every citation failure in the first provider
  # comparison, across two different model families. Collapsing whitespace removes a
  # formatting difference and nothing else, so a paraphrase still cannot pass.
  def quote_must_come_from_the_recommendation
    return if source_quote.blank? || recommendation.nil?
    return if recommendation.text.to_s.squish.include?(source_quote.squish)

    errors.add(:source_quote, :not_in_recommendation)
  end
end
