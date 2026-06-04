import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/blenny_example_app"
import topbar from "../vendor/topbar"
import "../vendor/datastar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

document.addEventListener("datastar-fetch", (e) => {
  if (e.detail.type !== "datastar-patch-signals") return
  const log = document.getElementById("event-log")
  if (!log) return
  const signals = e.detail.argsRaw?.signals
  if (!signals) return
  const time = new Date().toLocaleTimeString()
  const entry = document.createElement("div")
  entry.className = "text-xs"
  entry.textContent = `[${time}] signals: ${signals}`
  log.appendChild(entry)
  log.scrollTop = log.scrollHeight
})

let BlennyHook = {
  mounted() {
    this.handleEvent("blenny:patch", (msg) => {
      if (msg.html) {
        this.el.insertAdjacentHTML("beforeend", `<div class="text-xs text-blue-600">${msg.html}</div>`)
      }
      if (msg.signals) {
        for (const [key, val] of Object.entries(msg.signals)) {
          const el = this.el.querySelector(`[data-text="$.${key}"]`)
          if (el) el.textContent = val
        }
      }
    })
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {BlennyHook, ...colocatedHooks},
})

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    reloader.enableServerLogs()
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)
    window.liveReloader = reloader
  })
}

