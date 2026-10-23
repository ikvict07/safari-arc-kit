local tabsMod = require("safari_tabs")
local config = require("kit_config")
local favorites = config.favorites

local M = {}

local SAFARI = "com.apple.Safari"
local STRIP_W = config.sidebar.stripWidth
local PANEL_W = config.sidebar.width
local SHOW_DELAY = config.sidebar.showDelay

local safari = tabsMod.safari
local state = {window = nil, strip = nil, panel = nil, visible = false, hover = false, showTimer = nil}

local function host(url)
  return (url or ""):match("^%a[%w+.-]*://([^/:?#]+)")
end

local function favicon(url)
  local h = host(url)
  return h and ("https://www.google.com/s2/favicons?sz=64&domain=" .. h) or nil
end

local function js(code)
  if state.panel then state.panel:evaluateJavaScript(code) end
end

local function profileOf(w)
  local title = w and w:title() or ""
  return title:match("^(.-) — ") or "Safari"
end

local function render()
  if not state.visible or not state.window then return end
  local current = safari.currentTab()
  local tabs = safari.tabs()
  local rows, openHosts = {}, {}
  for _, t in ipairs(tabs) do
    rows[#rows + 1] = {index = t.index, title = t.name ~= "" and t.name or t.url, url = t.url, icon = favicon(t.url),
      active = current ~= nil and current.index == t.index}
    local h = host(t.url)
    if h then openHosts[h] = true end
  end
  local profile = profileOf(state.window)
  local favs = {}
  for _, f in ipairs(favorites[profile] or {}) do
    favs[#favs + 1] = {title = f.title, url = f.url, icon = favicon(f.url), open = openHosts[host(f.url) or ""] == true}
  end
  js("render(" .. hs.json.encode({profile = profile, tabs = rows, favorites = favs}) .. ")")
end

local function hidePanel()
  if state.showTimer then state.showTimer:stop() state.showTimer = nil end
  if not state.visible then return end
  state.visible = false
  state.panel:hide()
end

local function showPanel()
  local w = state.window
  if not w or state.visible then return end
  local wf = w:frame()
  state.panel:frame({x = wf.x, y = wf.y, w = PANEL_W, h = wf.h})
  state.visible = true
  state.entered = false
  render()
  state.panel:show()
  state.panel:bringToFront()
  hs.timer.doAfter(1.0, function()
    if not state.visible or state.entered then return end
    local p = hs.mouse.absolutePosition()
    local f = state.panel:frame()
    if not hs.geometry.point(p):inside(hs.geometry.rect(f)) then hidePanel() end
  end)
end

local function onStripMouse(_, event)
  if event == "mouseEnter" then
    state.hover = true
    if state.showTimer then state.showTimer:stop() end
    state.showTimer = hs.timer.doAfter(SHOW_DELAY, function()
      state.showTimer = nil
      if state.hover then showPanel() end
    end)
  elseif event == "mouseExit" then
    local p = hs.mouse.absolutePosition()
    local f = state.strip and state.strip:frame()
    state.hover = f ~= nil and p.x <= f.x + 1
  end
end

local function destroyStrip()
  if state.strip then state.strip:delete() state.strip = nil end
end

local function placeStrip(w)
  local wf = w:frame()
  local frame = {x = wf.x, y = wf.y, w = STRIP_W, h = wf.h}
  if state.strip then
    local f = state.strip:frame()
    if f.x == frame.x and f.y == frame.y and f.h == frame.h then return end
    destroyStrip()
  end
  state.strip = hs.canvas.new(frame)
  state.strip:level(hs.canvas.windowLevels.overlay)
  state.strip:behavior({hs.canvas.windowBehaviors.canJoinAllSpaces, hs.canvas.windowBehaviors.stationary})
  state.strip:canvasMouseEvents(false, false, true, false)
  state.strip:mouseCallback(onStripMouse)
  state.strip:appendElements({type = "rectangle", action = "fill", fillColor = {white = 0, alpha = 0.01}, trackMouseEnterExit = true})
  state.strip:show()
end

local function attach(w)
  if not w or not w:isStandard() or w:application():bundleID() ~= SAFARI then return end
  state.window = w
  placeStrip(w)
  if state.visible then
    local wf = w:frame()
    state.panel:frame({x = wf.x, y = wf.y, w = PANEL_W, h = wf.h})
  end
end

local function detach()
  hidePanel()
  destroyStrip()
  state.window = nil
  state.hover = false
end

local function refocusSafari()
  local w = state.window
  local app = hs.application.get(SAFARI)
  if app then app:activate() end
  if w then w:focus() end
  hs.timer.doAfter(0.1, function()
    if app then app:activate() end
    if w then w:focus() end
  end)
end

local function onMessage(msg)
  local body = msg.body
  if type(body) ~= "table" then return end
  if body.type == "activate" or body.type == "favorite" or body.type == "newtab" or body.type == "close" then
    refocusSafari()
  end
  if body.type == "activate" then
    safari.activate(body.index)
    hs.timer.doAfter(0.15, render)
  elseif body.type == "close" then
    hs.osascript.applescript(string.format([[tell application "Safari" to close tab %d of window 1]], body.index))
    hs.timer.doAfter(0.2, render)
  elseif body.type == "favorite" then
    local h = host(body.url)
    local found = nil
    for _, t in ipairs(safari.tabs()) do
      if h and host(t.url) == h then found = t.index break end
    end
    if found then
      safari.activate(found)
    else
      hs.osascript.applescript(string.format([[tell application "Safari" to tell window 1 to set current tab to (make new tab with properties {URL:"%s"})]], body.url))
    end
    hs.timer.doAfter(0.2, render)
  elseif body.type == "newtab" then
    hs.osascript.applescript([[tell application "Safari" to tell window 1 to set current tab to (make new tab)]])
    hs.timer.doAfter(0.2, render)
  elseif body.type == "enter" then
    state.entered = true
  elseif body.type == "leave" then
    hidePanel()
  end
end

local function build()
  local uc = hs.webview.usercontent.new("sidebar"):setCallback(onMessage)
  local wv = hs.webview.new({x = 0, y = 0, w = PANEL_W, h = 600}, {developerExtrasEnabled = false}, uc)
  wv:windowStyle({"borderless", "nonactivating"})
  wv:level(hs.drawing.windowLevels.overlay)
  wv:transparent(true)
  wv:shadow(false)
  wv:allowTextEntry(false)
  wv:closeOnEscape(false)
  wv:deleteOnClose(false)
  wv:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces | hs.drawing.windowBehaviors.stationary)
  local f = io.open(config.html("sidebar.html"), "r")
  wv:html(f:read("a"))
  f:close()
  state.panel = wv
end

build()

local wf = hs.window.filter.new(false):setAppFilter("Safari")
local function attachFocused()
  local front = hs.application.frontmostApplication()
  if not front or front:bundleID() ~= SAFARI then return end
  local w = hs.window.focusedWindow()
  if w then attach(w) end
end

wf:subscribe({hs.window.filter.windowFocused, hs.window.filter.windowMoved}, function(w)
  local front = hs.application.frontmostApplication()
  if front and front:bundleID() == SAFARI then attach(w) end
  hs.timer.doAfter(0.2, attachFocused)
end)
wf:subscribe({hs.window.filter.windowUnfocused, hs.window.filter.windowDestroyed}, function(w)
  if state.window and w:id() == state.window:id() then detach() end
end)
wf:subscribe(hs.window.filter.windowTitleChanged, function(w)
  if state.visible and state.window and w:id() == state.window:id() then render() end
end)

M.appWatcher = hs.application.watcher.new(function(name, event, app)
  if app and app:bundleID() == SAFARI then
    if event == hs.application.watcher.deactivated then
      local front = hs.application.frontmostApplication()
      if front and front:name() == "Hammerspoon" then return end
      detach()
    elseif event == hs.application.watcher.activated then
      attachFocused()
      hs.timer.doAfter(0.2, attachFocused)
      hs.timer.doAfter(0.6, attachFocused)
    end
  end
end)
M.appWatcher:start()

do
  local front = hs.application.frontmostApplication()
  if front and front:bundleID() == SAFARI then
    local w = hs.window.focusedWindow()
    if w then attach(w) end
  end
end

M.show = showPanel
M.hide = hidePanel
M.state = state
M.windowFilter = wf
return M
