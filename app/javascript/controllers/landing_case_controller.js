import { Controller } from "@hotwired/stimulus"

// The landing page's sample case, answered without an account. The key is in the page:
// this is one public sample, nothing is recorded, and checking in the browser keeps the
// page cacheable and free of a round trip. Answering reveals the citation the question
// was built from; the highlight sweep itself is CSS (.landing-citation.is-revealed).
export default class extends Controller {
  static targets = ["question", "announcer"]
  static values = { correct: String, incorrect: String }

  answer(event) {
    const chosen = event.currentTarget
    const question = chosen.closest("[data-landing-case-target='question']")
    if (question.dataset.answered) return
    question.dataset.answered = "true"

    question.querySelectorAll(".landing-option").forEach((option) => {
      const correct = option.dataset.correct === "true"
      option.dataset.state = correct ? "correct" : option === chosen ? "incorrect" : "idle"
      option.disabled = true
    })

    const right = chosen.dataset.correct === "true"
    this.announcerTarget.textContent = right ? this.correctValue : this.incorrectValue

    const after = question.querySelector("[data-landing-case-after]")
    after.hidden = false
    // Two frames so the panel is laid out unhighlighted before the sweep starts.
    requestAnimationFrame(() => requestAnimationFrame(() => {
      after.querySelector(".landing-citation").classList.add("is-revealed")
    }))
  }

  next(event) {
    const current = event.currentTarget.closest("[data-landing-case-target='question']")
    const following = this.questionTargets[this.questionTargets.indexOf(current) + 1]
    current.hidden = true
    following.hidden = false
    following.querySelector("[data-landing-case-heading]").focus()
  }
}
