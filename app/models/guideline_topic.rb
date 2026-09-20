# Which guidelines are about which topics, and how strongly.
#
# Built by Gpc::TopicLinker rather than curated by hand, which is what lets the taxonomy
# survive CENETEC republishing the catalog under us.
class GuidelineTopic < ApplicationRecord
  belongs_to :guideline
  belongs_to :topic

  validates :relevance, presence: true, numericality: { in: 0.0..1.0 }
  validates :guideline_id, uniqueness: { scope: :topic_id }

  scope :confident, -> { where(relevance: 0.2..) }
end
