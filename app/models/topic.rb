# The unit a student filters by and a study-plan day is made of.
#
# #aliases holds the other names the same thing goes by, which is what lets a guideline
# titled "cetoacidosis diabética" reach the topic a student looks for as "complicaciones
# agudas de la diabetes".
class Topic < ApplicationRecord
  belongs_to :branch
  has_one :specialty, through: :branch
  has_many :guideline_topics, dependent: :destroy
  has_many :guidelines, through: :guideline_topics

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :position, presence: true

  scope :linked, -> { where(id: GuidelineTopic.select(:topic_id)) }
  scope :unlinked, -> { where.not(id: GuidelineTopic.select(:topic_id)) }

  # Every name this topic answers to, longest first: a phrase that contains another
  # phrase is the more specific match and should win.
  def search_phrases
    ([name] + aliases).map { |phrase| phrase.to_s.squish }.reject(&:blank?).sort_by { |p| -p.length }
  end
end
