import { Controller } from "@hotwired/stimulus"

// Turns reminders on and off for the browser the page is open in.
//
// Each state is a hidden element in the page, so every word stays in the locale files;
// this only decides which one to show. Detection is by feature, not by browser, with one
// exception: iPhone and iPad hide the Push API from Safari tabs entirely and expose it
// only to a site opened from the Home Screen (iOS 16.4 and later). Without naming that
// case the student would read "not supported" and never learn the way in.
export default class extends Controller {
  static targets = ["state"]
  static values = { publicKey: String, url: String }

  async connect() {
    try {
      this.show(await this.detect())
    } catch (error) {
      this.show("unsupported")
    }
  }

  async detect() {
    if (!this.supported()) {
      if (!this.appleMobile()) return "unsupported"
      return this.standalone() ? "update_ios" : "install"
    }
    if (Notification.permission === "denied") return "denied"

    const subscription = await (await this.registration()).pushManager.getSubscription()
    if (!subscription) return "off"

    // The browser remembers a subscription the server may have dropped (a 410 cleaned it
    // up, or another account used this device). Saving again is idempotent.
    await this.save(subscription)
    return "on"
  }

  // subscribe() has to run inside the tap: Safari and Firefox refuse a permission prompt
  // that no user gesture asked for.
  async enable() {
    this.show("working")
    try {
      const permission = await Notification.requestPermission()
      if (permission !== "granted") return this.show(permission === "denied" ? "denied" : "off")

      const registration = await this.registration()
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: this.applicationServerKey()
      })
      await this.save(subscription)
      this.show("on")
    } catch (error) {
      this.show("error")
    }
  }

  async disable() {
    this.show("working")
    try {
      const subscription = await (await this.registration()).pushManager.getSubscription()
      if (subscription) {
        await this.request("DELETE", { endpoint: subscription.endpoint })
        await subscription.unsubscribe()
      }
      this.show("off")
    } catch (error) {
      this.show("error")
    }
  }

  async save(subscription) {
    const { endpoint, keys } = subscription.toJSON()
    await this.request("POST", { push_subscription: { endpoint, keys: { p256dh: keys.p256dh, auth: keys.auth } } })
  }

  async request(method, body) {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const response = await fetch(this.urlValue, {
      method,
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify(body),
      credentials: "same-origin"
    })
    if (!response.ok) throw new Error(`Push subscription ${method} failed: ${response.status}`)
  }

  async registration() {
    await navigator.serviceWorker.register("/service-worker.js", { scope: "/" })
    return navigator.serviceWorker.ready
  }

  supported() {
    return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window
  }

  // iPadOS reports itself as a Mac; a Mac has no touch screen.
  appleMobile() {
    const agent = navigator.userAgent
    return /iPhone|iPad|iPod/.test(agent) || (/Macintosh/.test(agent) && navigator.maxTouchPoints > 1)
  }

  standalone() {
    return window.matchMedia("(display-mode: standalone)").matches || navigator.standalone === true
  }

  // The VAPID public key arrives base64url-encoded; PushManager wants the raw bytes.
  applicationServerKey() {
    const base64 = this.publicKeyValue.replace(/-/g, "+").replace(/_/g, "/")
    const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4)
    return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0))
  }

  show(state) {
    this.stateTargets.forEach((element) => {
      element.hidden = element.dataset.state !== state
    })
  }
}
