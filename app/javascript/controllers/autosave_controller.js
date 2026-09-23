import { Controller } from "@hotwired/stimulus"

// Saves an answer the moment an option is chosen. The single-page exam has no submit
// button per question — the real exam's answer sheet does not either — and the server
// answers with a Turbo Stream, so the page never moves.
export default class extends Controller {
  save() {
    this.element.requestSubmit()
  }
}
