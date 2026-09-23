import { Controller } from "@hotwired/stimulus"

// Fills a hidden field with the zone the browser reports, so the student's day ends at
// midnight where they are. Left empty when the browser cannot say; the server then keeps
// its default.
export default class extends Controller {
  connect() {
    try {
      this.element.value = Intl.DateTimeFormat().resolvedOptions().timeZone || ""
    } catch (e) {
      this.element.value = ""
    }
  }
}
