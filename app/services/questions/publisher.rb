# Puts every case that has earned it in front of students, and nothing else.
#
# The exam builder reads `published` and nothing else, so this is the only door into the
# bank a student sees. A case walks through it when a second model family supported every
# one of its answers and nobody has withdrawn it; a published case that has since lost
# either goes back to draft.
module Questions
  class Publisher < ApplicationService
    def call
      withdrawn = ClinicalCase.status_published.where.not(id: ClinicalCase.publishable).update_all(status: "draft")
      published = ClinicalCase.status_draft.publishable.update_all(status: "published")

      success(published: published, withdrawn: withdrawn, live: ClinicalCase.status_published.count)
    end
  end
end
