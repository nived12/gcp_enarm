import { Controller } from "@hotwired/stimulus"

// Filters the topic list as the student types and names what is chosen on the closed
// picker. Matching ignores case and accents: nobody types "vías" on a phone keyboard
// when "vias" will do.
export default class extends Controller {
  static targets = ["details", "summary", "search", "option", "group", "empty"]
  static values = { all: String, many: String }

  filter() {
    const query = this.normalize(this.searchTarget.value)
    let shown = 0

    this.optionTargets.forEach((option) => {
      const match = this.normalize(option.textContent).includes(query)
      option.hidden = !match
      if (match) shown++
    })
    this.groupTargets.forEach((group) => {
      group.hidden = !group.querySelector("[data-topic-picker-target='option']:not([hidden])")
    })
    this.emptyTarget.classList.toggle("hidden", shown > 0)
  }

  update() {
    const chosen = this.optionTargets.filter((option) => option.querySelector("input").checked)
    this.summaryTarget.textContent =
      chosen.length === 0 ? this.allValue
        : chosen.length === 1 ? chosen[0].querySelector("[data-topic-picker-target='name']").textContent
          : this.manyValue.replace("%{count}", chosen.length)
  }

  clear() {
    this.optionTargets.forEach((option) => { option.querySelector("input").checked = false })
    this.update()
  }

  close() {
    this.detailsTarget.open = false
    this.searchTarget.value = ""
    this.filter()
  }

  normalize(text) {
    return text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim()
  }
}
