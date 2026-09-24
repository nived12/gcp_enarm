import { Controller } from "@hotwired/stimulus"

// Plays the streak heart's moments. Once each: a double beat the first time a day is
// seen to count, the pulse flattening the first time a lost streak is seen. What was
// last seen is kept in this browser only; with storage unavailable neither plays.
//
// While a streak is alive the heart also beats whenever the pointer rests on it (a tap,
// on a phone).
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

  // A lost or unstarted streak has no pulse to show.
  hover() {
    const alive = this.momentValue === "active" || this.momentValue.startsWith("counted:")
    if (alive) this.play("streak-heart--beat")
  }

  play(name) {
    if (this.element.classList.contains(name)) return

    this.element.classList.add(name)
    this.element.addEventListener("animationend", () => this.element.classList.remove(name), { once: true })
  }
}
