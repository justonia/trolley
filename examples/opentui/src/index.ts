import {
  createCliRenderer,
  BoxRenderable,
  TextRenderable,
  type KeyEvent,
} from "@opentui/core"

const MAX_HISTORY = 30

const renderer = await createCliRenderer({
  exitOnCtrlC: true,
  targetFps: 60,
  useKittyKeyboard: { events: true },
})

renderer.setBackgroundColor("#0D1117")

// --- Layout ---

const root = new BoxRenderable(renderer, {
  id: "root",
  flexDirection: "column",
  width: "100%",
  height: "100%",
})

// Header
const header = new BoxRenderable(renderer, {
  id: "header",
  height: 3,
  border: true,
  borderColor: "#6BCF7F",
  borderStyle: "rounded",
  backgroundColor: "#161B22",
  alignItems: "center",
  justifyContent: "center",
})

const headerText = new TextRenderable(renderer, {
  id: "header-text",
  content: "Trolley Key Event Viewer (OpenTUI)",
  fg: "#6BCF7F",
  attributes: 1, // bold
})
header.add(headerText)

// Last key display
const lastKeyBox = new BoxRenderable(renderer, {
  id: "last-key-box",
  height: 5,
  border: true,
  borderColor: "#FFA657",
  borderStyle: "rounded",
  backgroundColor: "#161B22",
  flexDirection: "column",
  paddingLeft: 2,
  paddingTop: 1,
})

const lastKeyLabel = new TextRenderable(renderer, {
  id: "last-key-label",
  content: "Last Key: (none)",
  fg: "#FFA657",
  attributes: 1,
})

const lastKeyDetail = new TextRenderable(renderer, {
  id: "last-key-detail",
  content: "",
  fg: "#8B949E",
})

lastKeyBox.add(lastKeyLabel)
lastKeyBox.add(lastKeyDetail)

// History
const historyBox = new BoxRenderable(renderer, {
  id: "history-box",
  flexGrow: 1,
  border: true,
  borderColor: "#79C0FF",
  borderStyle: "rounded",
  backgroundColor: "#161B22",
  title: "History",
  titleAlignment: "left",
  flexDirection: "column",
  paddingLeft: 1,
  paddingRight: 1,
  overflow: "hidden",
})

// Footer
const footer = new BoxRenderable(renderer, {
  id: "footer",
  height: 3,
  border: true,
  borderColor: "#484F58",
  borderStyle: "rounded",
  backgroundColor: "#161B22",
  alignItems: "center",
  justifyContent: "center",
})

const footerText = new TextRenderable(renderer, {
  id: "footer-text",
  content: "ctrl+c quit",
  fg: "#484F58",
})
footer.add(footerText)

root.add(header)
root.add(lastKeyBox)
root.add(historyBox)
root.add(footer)
renderer.root.add(root)

// --- Key handling ---

let historyCount = 0

function formatModifiers(event: KeyEvent): string {
  const mods: string[] = []
  if (event.ctrl) mods.push("ctrl")
  if (event.shift) mods.push("shift")
  if (event.meta) mods.push("meta")
  if (event.option) mods.push("opt")
  if (event.super) mods.push("super")
  if (event.hyper) mods.push("hyper")
  return mods.length > 0 ? mods.join("+") + "+" : ""
}

function formatKeyDisplay(event: KeyEvent): string {
  const mods = formatModifiers(event)
  const name = event.name || "?"
  return `${mods}${name}`
}

function formatDetail(event: KeyEvent): string {
  const parts: string[] = []
  if (event.sequence) {
    parts.push(`seq=${JSON.stringify(event.sequence)}`)
  }
  if (event.raw) {
    parts.push(`raw=${JSON.stringify(event.raw)}`)
  }
  return parts.join("  ")
}

renderer.keyInput.on("keypress", (event: KeyEvent) => {
  const display = formatKeyDisplay(event)
  const detail = formatDetail(event)

  lastKeyLabel.content = `Last Key: ${display}`
  lastKeyDetail.content = detail

  historyCount++
  const entry = new TextRenderable(renderer, {
    id: `hist-${historyCount}`,
    content: `${display}  ${detail}`,
    fg: "#C9D1D9",
  })
  historyBox.add(entry)

  // Trim old entries
  const children = historyBox.getChildren()
  while (children.length > MAX_HISTORY) {
    const oldest = children.shift()
    if (oldest) {
      historyBox.remove(oldest.id)
      oldest.destroy()
    }
  }

  renderer.requestRender()
})

renderer.start()
