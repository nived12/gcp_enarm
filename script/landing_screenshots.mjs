// Captures the phone screens shown on the landing page, in both themes, and the Open
// Graph image a WhatsApp link preview shows. Run against a server holding the demo
// account from script/landing_demo_user.rb:
//
//   DATABASE_URL=postgres:///gpc_enarm_preview bin/rails runner script/landing_demo_user.rb
//   node script/landing_screenshots.mjs            # BASE_URL defaults to localhost:3001
//
// Writes app/assets/images/landing/{screen}-{phone,desktop}-{light,dark}.jpg and og.png.
import { chromium } from "playwright"
import { readFileSync } from "node:fs"

const BASE = process.env.BASE_URL || "http://localhost:3001"
const OUT = new URL("../app/assets/images/landing/", import.meta.url).pathname
const demo = JSON.parse(readFileSync(new URL("../tmp/landing_demo.json", import.meta.url)))

const SCREENS = {
  quiz: `/exams/${demo.quiz_id}/questions/1`,
  mock: `/exams/${demo.mock_id}`,
  review: "/reviews",
  calendar: "/study_plan",
  stats: "/stats",
}

// The phone at a common iPhone size; the computer small enough that, shown beside the
// phone on the landing page, its text is still legible (the app reads at max-w-3xl).
const DEVICES = {
  phone: { viewport: { width: 390, height: 844 }, questionOffset: 360 },
  desktop: { viewport: { width: 1100, height: 720 }, questionOffset: 300 },
}

function nextMonth() {
  const today = new Date()
  const next = new Date(today.getFullYear(), today.getMonth() + 1, 1)
  return `${next.getFullYear()}-${String(next.getMonth() + 1).padStart(2, "0")}`
}

const browser = await chromium.launch()

// Sign in once and reuse the session: four sign-ins a run trip the login rate limit.
const login = await browser.newContext()
const loginPage = await login.newPage()
await loginPage.goto(`${BASE}/session/new`)
await loginPage.fill("input[name=email]", demo.email)
await loginPage.fill("input[name=password]", demo.password)
await Promise.all([loginPage.waitForURL(`${BASE}/`), loginPage.press("input[name=password]", "Enter")])
const storageState = await login.storageState()
await login.close()

for (const [device, { viewport, questionOffset }] of Object.entries(DEVICES)) {
  for (const scheme of ["light", "dark"]) {
    const context = await browser.newContext({
      viewport, deviceScaleFactor: 2, colorScheme: scheme,
      locale: "es-MX", timezoneId: "America/Mexico_City", reducedMotion: "reduce", storageState,
    })
    const page = await context.newPage()

    for (const [name, path] of Object.entries(SCREENS)) {
      // The computer shows the month grid, and the plan starts today, so this month is
      // mostly empty days. Next month is planned from its first day to its last.
      const url = device === "desktop" && name === "calendar" ? `${path}?month=${nextMonth()}` : path
      await page.goto(`${BASE}${url}`)
      await page.evaluate(() => document.fonts.ready)
      // A vignette fills a screen by itself, and a question screen without its options
      // does not read as a quiz. Scroll until the question and its first options show,
      // with the end of the vignette above them.
      if (name === "quiz") {
        await page.evaluate((offset) => {
          const question = document.querySelector("article h1")
          window.scrollTo(0, question.getBoundingClientRect().top + window.scrollY - offset)
        }, questionOffset)
      }
      await page.screenshot({ path: `${OUT}${name}-${device}-${scheme}.jpg`, type: "jpeg", quality: 80 })
    }
    await context.close()
  }
}

// The preview card: the logo, the product's claim as the page shows it, one highlighted
// citation. The logo sits centred at the top because a small link preview (WhatsApp on a
// computer) crops the image to its middle square.
const og = await browser.newPage({ viewport: { width: 1200, height: 630 }, colorScheme: "light" })
await og.goto(`${BASE}/`)
await og.evaluate(() => {
  const figure = document.querySelector("figure.card").cloneNode(true)
  figure.querySelectorAll(".anatomy-pin").forEach((pin) => pin.remove())
  document.body.innerHTML = ""
  document.body.style.cssText = "margin:0;display:grid;place-items:center;height:630px;padding:0 72px;box-sizing:border-box"
  const wrap = document.createElement("div")
  wrap.style.cssText = "width:100%"
  wrap.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:center;gap:14px;margin:0 0 22px;font:700 34px/1 'Alan Sans',sans-serif;letter-spacing:-0.02em">
      <img src="/icon.svg" width="52" height="52" alt=""><span><span style="color:var(--ink)">GPC</span><span style="color:var(--accent)">Enarm</span></span>
    </div>
    <p style="font:600 36px/1.15 'Alan Sans',sans-serif;letter-spacing:-0.02em;margin:0 0 24px;color:var(--ink);text-align:center">Simulador ENARM con la GPC detrás de cada respuesta.</p>`
  figure.style.cssText = "margin:0"
  wrap.append(figure)
  document.body.append(wrap)
})
await og.evaluate(() => document.fonts.ready)
await og.screenshot({ path: `${OUT}og.png` })

await browser.close()
