import { Controller } from "@hotwired/stimulus"

// Plays the streak heart's moment once: a double beat the first time a day is seen to
// count, the pulse flattening the first time a lost streak is seen. What was last seen
// is kept in this browser only; with storage unavailable nothing plays, which is fine.
const KEY = "streak-heart-seen"

export default class extends Controller {
  static values = { moment: String }

  connect() {
    const moment = this.momentValue
    let seen
    try {
      seen = localStorage.getItem(KEY)
      localStorage.setItem(KEY, moment)
    } catch {
      return
    }
    if (seen === moment) return

    if (moment.startsWith("counted:")) this.play("streak-heart--beat")
    else if (moment === "lost" && seen !== null) this.play("streak-heart--flatline")
  }

  play(name) {
    this.element.classList.add(name)
    this.element.addEventListener("animationend", () => this.element.classList.remove(name), { once: true })
  }
}
