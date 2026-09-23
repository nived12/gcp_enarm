# What is waiting in the student's review deck: cases and pearls due today, and the cases
# coming back over the next week. Counts only published cases: one withdrawn after the
# student missed it keeps its schedule but is never shown.
module Reviews
  DueSummary = Data.define(:cases_due, :pearls_due, :cases_this_week) do
    def self.for(user)
      today = user.study_date
      cards = ReviewCard.where(user: user)
      new(
        cases_due: cards.published_cases.due(today).count,
        pearls_due: cards.pearls.due(today).count,
        cases_this_week: cards.published_cases.where(due_on: (today + 1)..(today + 7)).count
      )
    end

    def anything_due? = (cases_due + pearls_due).positive?
  end
end
