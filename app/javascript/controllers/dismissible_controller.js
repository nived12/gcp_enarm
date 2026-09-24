import { Controller } from "@hotwired/stimulus"

// Removes the element it sits on. Nothing is remembered: whatever uses it must already
// be something that shows only once.
export default class extends Controller {
  dismiss() {
    this.element.remove()
  }
}
