import { Controller } from "@hotwired/stimulus"

// Saves an answer the moment an option is chosen. The single-page exam has no submit
// button per question — the real exam's answer sheet does not either — and the server
// answers with a Turbo Stream, so the page never moves.
//
// Confidence rides in the same form. Chosen before an option, it waits and is sent with
// the option; chosen after, it saves on its own.
export default class extends Controller {
  save() {
    if (this.element.querySelector("input[name=answer_option_id]:checked")) this.element.requestSubmit()
  }
}
