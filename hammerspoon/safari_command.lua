local parse = require("command_parse")
local tabsMod = require("safari_tabs")
local config = require("kit_config")
parse.modes = config.modes

local M = {}

local SAFARI = "com.apple.Safari"
local SUGGEST_DELAY = 0.15
local MAX_SUGGESTIONS = 5
local MAX_ROWS = 9
local PANEL_W = config.command.width
local PANEL_TOP = config.command.top
local PLACEHOLDER = "Search tabs, Google, or type gh / jira"

local safari = tabsMod.safari
local state = {mode = nil, tabs = {}, mruKeys = {}, query = "", suggestions = {}, suggestTimer = nil, rows = {}, visible = false}

local function log(...) print("[safari_command]", ...) end

local function isSafariFront()
  local app = hs.application.frontmostApplication()
  return app ~= nil and app:bundleID() == SAFARI
end

local function asString(s)
  return s:gsub("\\", "\\\\"):gsub('"', '\\"')
end

local function openInNewTab(url)
  hs.osascript.applescript(string.format([[
    tell application "Safari"
      tell window 1
        set t to make new tab with properties {URL:"%s"}
        set current tab to t
      end tell
    end tell]], asString(url)))
end

local function newTab()
  hs.osascript.applescript([[
    tell application "Safari"
      tell window 1
        set current tab to (make new tab)
      end tell
    end tell]])
end

local function loadWindowState()
  state.tabs = safari.tabs()
  state.mruKeys = {}
  local w = hs.window.focusedWindow()
  local ws = w and tabsMod.state.windows[w:id()]
  if ws then
    for i, e in ipairs(ws.mru) do state.mruKeys[e.key] = i end
  end
end

local function host(url)
  return (url or ""):match("^%a[%w+.-]*://([^/:?#]+)")
end

local function favicon(url)
  local h = host(url)
  return h and ("https://www.google.com/s2/favicons?sz=64&domain=" .. h) or nil
end

local function tabRow(t)
  return {title = t.name ~= "" and t.name or t.url, sub = host(t.url) or t.url, icon = favicon(t.url), tag = "tab", kind = "tab", index = t.index}
end

local function buildChoices(query)
  local mode, rest = state.mode, query
  if not mode then mode, rest = parse.split(query) end
  if mode then
    local m = parse.modes[mode]
    if rest == "" then
      return {{title = m.label, sub = "Enter, then type a query", kind = "enter-mode", mode = mode}}
    end
    return {{title = m.label .. ": " .. rest, sub = host(parse.modeUrl(mode, rest)), kind = "url", url = parse.modeUrl(mode, rest), icon = favicon(parse.modeUrl(mode, rest))}}
  end

  local rows = {}
  if rest == "" then
    local byKey = {}
    for _, t in ipairs(state.tabs) do
      local k = (t.url or "") .. "|" .. (t.name or "")
      if not byKey[k] then byKey[k] = t end
    end
    local ordered = {}
    for key, pos in pairs(state.mruKeys) do
      if pos <= 5 and byKey[key] then ordered[#ordered + 1] = {pos = pos, tab = byKey[key]} end
    end
    table.sort(ordered, function(a, b) return a.pos < b.pos end)
    for _, r in ipairs(ordered) do rows[#rows + 1] = tabRow(r.tab) end
    rows[#rows + 1] = {title = "New tab", sub = "⌘T", kind = "new-tab"}
    return rows
  end

  for _, t in ipairs(parse.rankTabs(state.tabs, rest, state.mruKeys)) do rows[#rows + 1] = tabRow(t) end
  for _, s in ipairs(state.suggestions) do
    rows[#rows + 1] = {title = s, kind = "google", tag = "google", url = parse.searchUrl(s)}
  end
  if parse.isUrl(rest) then
    rows[#rows + 1] = {title = parse.toUrl(rest), tag = "open", kind = "url", url = parse.toUrl(rest), icon = favicon(parse.toUrl(rest))}
  end
  rows[#rows + 1] = {title = "Search Google: " .. rest, kind = "google", tag = "search", url = parse.searchUrl(rest)}
  while #rows > MAX_ROWS do table.remove(rows, #rows - 1) end
  return rows
end

local wv

local function js(code)
  if wv then wv:evaluateJavaScript(code) end
end

local function render()
  state.rows = buildChoices(state.query)
  local payload = {}
  for i, r in ipairs(state.rows) do
    payload[i] = {title = r.title, sub = r.sub, icon = r.icon, tag = r.tag, kind = r.kind}
  end
  js("render(" .. hs.json.encode({rows = payload, selected = 0}) .. ")")
end

local function setMode(mode)
  state.mode = mode
  local badge = mode and parse.modes[mode].label or ""
  local placeholder = mode and (parse.modes[mode].label .. " query…") or PLACEHOLDER
  js("setMode(" .. hs.json.encode({badge = badge, placeholder = placeholder}) .. ")")
end

local function fetchSuggestions(query)
  local url = "https://suggestqueries.google.com/complete/search?client=firefox&q=" .. parse.encode(query)
  hs.http.asyncGet(url, nil, function(status, body)
    if status ~= 200 or state.query ~= query or state.mode or not state.visible then return end
    local ok, data = pcall(hs.json.decode, body)
    if not ok or type(data) ~= "table" or type(data[2]) ~= "table" then return end
    local out = {}
    for i, s in ipairs(data[2]) do
      if i > MAX_SUGGESTIONS then break end
      if s:lower() ~= query:lower() then out[#out + 1] = s end
    end
    state.suggestions = out
    render()
  end)
end

local function onQuery(text)
  state.query = text
  state.suggestions = {}
  if state.suggestTimer then state.suggestTimer:stop() state.suggestTimer = nil end
  render()
  local mode, rest = state.mode, text
  if not mode then mode, rest = parse.split(text) end
  if not mode and rest ~= "" and not parse.isUrl(rest) then
    state.suggestTimer = hs.timer.doAfter(SUGGEST_DELAY, function() fetchSuggestions(text) end)
  end
end

local function hide()
  if not state.visible then return end
  state.visible = false
  wv:hide()
  state.mode = nil
  state.query = ""
  state.suggestions = {}
  if state.suggestTimer then state.suggestTimer:stop() state.suggestTimer = nil end
  local app = hs.application.get(SAFARI)
  if app then app:activate() end
end

local function select(index)
  local choice = state.rows[index] or state.rows[1]
  if not choice then hide() return end
  if choice.kind == "enter-mode" then
    setMode(choice.mode)
    state.query = ""
    js("setQuery('')")
    render()
    return
  end
  hide()
  if choice.kind == "tab" then
    safari.activate(choice.index)
  elseif choice.kind == "url" or choice.kind == "google" then
    openInNewTab(choice.url)
  elseif choice.kind == "new-tab" then
    newTab()
  end
end

local function onMessage(msg)
  local body = msg.body
  if type(body) ~= "table" then return end
  if body.type == "query" then onQuery(body.text or "")
  elseif body.type == "select" then select(body.index or 1)
  elseif body.type == "cancel" or body.type == "blur" then hide()
  elseif body.type == "backspace-empty" then
    if state.mode then setMode(nil) render() end
  elseif body.type == "height" then
    local f = wv:frame()
    wv:size({w = PANEL_W, h = body.h})
  end
end

local function build()
  local uc = hs.webview.usercontent.new("cmdbar"):setCallback(onMessage)
  wv = hs.webview.new({x = 0, y = 0, w = PANEL_W, h = 64}, {developerExtrasEnabled = false}, uc)
  wv:windowStyle({"borderless", "nonactivating"})
  wv:level(hs.drawing.windowLevels.overlay)
  wv:transparent(true)
  wv:shadow(true)
  wv:allowTextEntry(true)
  wv:closeOnEscape(false)
  wv:deleteOnClose(false)
  wv:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces | hs.drawing.windowBehaviors.stationary)
  local f = io.open(config.html("command_bar.html"), "r")
  local html = f:read("a")
  f:close()
  wv:html(html)
end

function M.show()
  if state.visible then return end
  local w = hs.window.focusedWindow()
  if not w then return end
  loadWindowState()
  local wf = w:frame()
  wv:frame({x = wf.x + (wf.w - PANEL_W) / 2, y = wf.y + math.floor(wf.h * PANEL_TOP), w = PANEL_W, h = 64})
  state.visible = true
  state.query = ""
  setMode(nil)
  js("setQuery('')")
  render()
  wv:show()
  wv:bringToFront()
  hs.timer.doAfter(0.05, function() js("focusInput()") end)
end

function M.hide() hide() end

build()

local T = hs.keycodes.map.t
M.tap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(e)
  local f = e:getFlags()
  if not (f.cmd and not f.ctrl and not f.alt and not f.shift) then return false end
  if e:getKeyCode() ~= T or not isSafariFront() then return false end
  if state.visible then return true end
  if e:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) ~= 0 then return true end
  if not hs.window.focusedWindow() then return false end
  M.show()
  return true
end)
M.tap:start()

function M.debugChoices(query)
  loadWindowState()
  state.mode = nil
  local rows = buildChoices(query)
  local out = {}
  for i, r in ipairs(rows) do out[i] = r.kind .. " | " .. r.title .. " | " .. tostring(r.sub) end
  return table.concat(out, "\n")
end

M.state = state
M.webview = function() return wv end
return M
