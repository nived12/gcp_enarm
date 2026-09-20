import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "gpcenarm-theme"

// The layout's inline script sets data-theme before paint; this only handles the
// toggle and keeps the icon in sync. Every storage call is guarded — in a private
// window localStorage throws rather than returning null.
export default class extends Controller {
  static targets = ["sun", "moon"]

  connect() {
    this.render()
    this.media = window.matchMedia("(prefers-color-scheme: dark)")
    this.onSystemChange = () => { if (!this.stored) this.render() }
    this.media.addEventListener("change", this.onSystemChange)
  }

  disconnect() {
    this.media?.removeEventListener("change", this.onSystemChange)
  }

  toggle() {
    const next = this.current === "dark" ? "light" : "dark"
    document.documentElement.setAttribute("data-theme", next)
    try {
      localStorage.setItem(STORAGE_KEY, next)
    } catch (e) {
      // Theme still applies for this page view; it just will not survive a reload.
    }
    this.render()
  }

  render() {
    const dark = this.current === "dark"
    this.sunTarget.classList.toggle("hidden", !dark)
    this.moonTarget.classList.toggle("hidden", dark)
  }

  get stored() {
    try {
      return localStorage.getItem(STORAGE_KEY)
    } catch (e) {
      return null
    }
  }

  // The attribute wins when set; otherwise the system preference is what the CSS
  // is actually rendering, so the icon must follow it.
  get current() {
    const attr = document.documentElement.getAttribute("data-theme")
    if (attr === "dark" || attr === "light") return attr

    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
  }
}
