local mru = require("mru")
local config = require("kit_config")

local M = {}

local SAFARI = "com.apple.Safari"
local OVERLAY_DELAY = config.tabs.overlayDelay
local SNAPSHOT_DELAY = 0.25
local REFRESH_EVERY = 5
local MAX_PREVIEWS = 50
local MAX_CARDS = 8
local MAX_ENTRIES = config.tabs.maxEntries
local CARD_W, PREVIEW_H, TITLE_H, GAP, PAD = 240, 150, 22, 16, 24

local state = {windows = {}, session = nil, warnedSnapshot = false}

local function log(...) print("[safari_tabs]", ...) end

local function isSafariFront()
  local app = hs.application.frontmostApplication()
  return app ~= nil and app:bundleID() == SAFARI
end

local function focusedSafariWindow()
  if not isSafariFront() then return nil end
  local w = hs.window.focusedWindow()
  if w and w:application():bundleID() == SAFARI and w:isStandard() then return w end
  return nil
end

local safari = {}

local function run(script)
  local ok, result = hs.osascript.applescript(script)
  if not ok then
    log("applescript failed", hs.inspect(result))
    return nil
  end
  return result
end

local function parseTabs(text)
  local tabs = {}
  if not text or text == "" then return tabs end
  for line in text:gmatch("[^\n]+") do
    local url, name = line:match("^(.-)\t(.*)$")
    if url then tabs[#tabs + 1] = {url = url, name = name, index = #tabs + 1} end
  end
  return tabs
end

function safari.tabs()
  local text = run([[
    tell application "Safari"
      set out to ""
      try
        set urls to URL of tabs of window 1
        set names to name of tabs of window 1
        repeat with i from 1 to count of urls
          set u to item i of urls
          if u is missing value then set u to ""
          set n to item i of names
          if n is missing value then set n to ""
          set out to out & u & (character id 9) & n & linefeed
        end repeat
      end try
      return out
    end tell]])
  return parseTabs(text)
end

function safari.currentTab()
  local text = run([[
    tell application "Safari"
      try
        set t to current tab of window 1
        set u to URL of t
        if u is missing value then set u to ""
        set n to name of t
        if n is missing value then set n to ""
        return u & (character id 9) & n & (character id 9) & (index of t as text)
      on error
        return ""
      end try
    end tell]])
  if not text or text == "" then return nil end
  local url, name, index = text:match("^(.-)\t(.-)\t(%d+)$")
  if not url then return nil end
  return {url = url, name = name, index = tonumber(index)}
end

function safari.activate(index)
  run(string.format([[
    tell application "Safari"
      try
        set current tab of window 1 to tab %d of window 1
      end try
    end tell]], index))
end

local function winState(w)
  local id = w:id()
  if not state.windows[id] then state.windows[id] = {mru = mru.new(), previews = {}} end
  return state.windows[id]
end

local function storePreview(ws, key, image)
  ws.previews[key] = {image = image, touched = hs.timer.secondsSinceEpoch()}
  local count = 0
  for _ in pairs(ws.previews) do count = count + 1 end
  if count > MAX_PREVIEWS then
    local oldestKey, oldest = nil, math.huge
    for k, p in pairs(ws.previews) do
      if p.touched < oldest then oldestKey, oldest = k, p.touched end
    end
    ws.previews[oldestKey] = nil
  end
end

local function snapshotCurrent()
  local w = focusedSafariWindow()
  if not w or state.session then return end
  local tab = safari.currentTab()
  if not tab then return end
  local img = w:snapshot()
  if not img then
    if not state.warnedSnapshot then
      state.warnedSnapshot = true
      hs.alert.show("safari_tabs: no previews. Grant Hammerspoon Screen Recording in System Settings.", 4)
    end
    return
  end
  storePreview(winState(w), mru.key(tab.url, tab.name), img)
end

local pendingTrack = nil
local function track(w)
  if pendingTrack then pendingTrack:stop() end
  pendingTrack = hs.timer.doAfter(0.2, function()
    pendingTrack = nil
    if state.session then track(w) return end
    local fw = focusedSafariWindow()
    if not fw or fw:id() ~= w:id() then return end
    local tab = safari.currentTab()
    if not tab then return end
    local ws = winState(fw)
    local key = mru.key(tab.url, tab.name)
    local head = ws.mru[1]
    if head and head.key ~= key and head.index == tab.index then
      if ws.previews[head.key] and not ws.previews[key] then
        ws.previews[key] = ws.previews[head.key]
      end
      ws.previews[head.key] = nil
      ws.mru = mru.remove(ws.mru, head.key)
    end
    ws.mru = mru.reconcile(mru.touch(ws.mru, key, tab), safari.tabs())
    hs.timer.doAfter(SNAPSHOT_DELAY, snapshotCurrent)
  end)
end

local wf = hs.window.filter.new(false):setAppFilter("Safari")
wf:subscribe({hs.window.filter.windowTitleChanged, hs.window.filter.windowFocused}, function(w)
  track(w)
end)
wf:subscribe(hs.window.filter.windowDestroyed, function(w)
  state.windows[w:id()] = nil
end)

M.refreshTimer = hs.timer.doEvery(REFRESH_EVERY, function()
  if isSafariFront() then snapshotCurrent() end
end)

local function fitFrame(img, box)
  local size = img:size()
  local scale = math.min(box.w / size.w, box.h / size.h)
  local w, h = size.w * scale, size.h * scale
  return {x = box.x + (box.w - w) / 2, y = box.y + (box.h - h) / 2, w = w, h = h}
end

local function renderOverlay()
  local s = state.session
  if not s or not s.window then return end
  local n = #s.entries
  local first, last = mru.visibleWindow(n, s.sel, MAX_CARDS)
  local shown = last - first + 1
  local width = PAD * 2 + shown * CARD_W + (shown - 1) * GAP
  local height = PAD * 2 + PREVIEW_H + 8 + TITLE_H
  local wf = s.window:frame()
  local frame = {x = wf.x + (wf.w - width) / 2, y = wf.y + (wf.h - height) / 2, w = width, h = height}

  if s.canvas then s.canvas:delete() end
  local c = hs.canvas.new(frame)
  c:level(hs.canvas.windowLevels.overlay)
  c:behavior({hs.canvas.windowBehaviors.canJoinAllSpaces, hs.canvas.windowBehaviors.stationary})
  c:appendElements({type = "rectangle", action = "fill", roundedRectRadii = {xRadius = 16, yRadius = 16},
    fillColor = {red = 0.08, green = 0.08, blue = 0.1, alpha = 0.92}})

  local ws = winState(s.window)
  for i = first, last do
    local e = s.entries[i]
    local x = PAD + (i - first) * (CARD_W + GAP)
    local box = {x = x, y = PAD, w = CARD_W, h = PREVIEW_H}
    c:appendElements({type = "rectangle", action = "fill", frame = box, roundedRectRadii = {xRadius = 8, yRadius = 8},
      fillColor = {red = 0.2, green = 0.2, blue = 0.22, alpha = 1}})
    local p = ws.previews[e.key]
    if p then
      c:appendElements({type = "image", image = p.image, imageScaling = "scaleProportionally", frame = fitFrame(p.image, box)})
    end
    if i == s.sel then
      c:appendElements({type = "rectangle", action = "stroke", frame = {x = box.x - 3, y = box.y - 3, w = box.w + 6, h = box.h + 6},
        roundedRectRadii = {xRadius = 10, yRadius = 10}, strokeWidth = 3,
        strokeColor = {red = 0.45, green = 0.6, blue = 1, alpha = 1}})
    end
    c:appendElements({type = "text", text = e.name ~= "" and e.name or e.url, textSize = 13, textAlignment = "center",
      textLineBreak = "truncateTail", textColor = {white = 1, alpha = i == s.sel and 1 or 0.7},
      frame = {x = x, y = PAD + PREVIEW_H + 8, w = CARD_W, h = TITLE_H}})
  end
  c:show()
  s.canvas = c
end

local function endSession()
  local s = state.session
  state.session = nil
  if not s then return end
  if s.showTimer then s.showTimer:stop() end
  if s.canvas then s.canvas:delete() end
end

local function activateEntry(entry)
  if not entry or not entry.index then return end
  hs.timer.doAfter(0, function() safari.activate(entry.index) end)
end

local function finishSession(target)
  local s = state.session
  if not s then return end
  endSession()
  if not target or target == s.entries[1] then return end
  activateEntry(target)
  local ws = winState(s.window)
  ws.mru = mru.touch(ws.mru, target.key, target)
  hs.timer.doAfter(0.05, function() track(s.window) end)
end

local function commitSession()
  local s = state.session
  if s then finishSession(s.entries[s.sel]) end
end

local function cancelSession()
  endSession()
end

local function startSession(delta)
  local w = focusedSafariWindow()
  if not w then return false end
  local ws = winState(w)
  local head = ws.mru[1]
  local title = w:title() or ""
  if not head or head.name == "" or not title:find(head.name, 1, true) then
    local tab = safari.currentTab()
    if tab then ws.mru = mru.touch(ws.mru, mru.key(tab.url, tab.name), tab) end
  end
  if #ws.mru < 2 then return false end
  local entries = {}
  for i = 1, math.min(MAX_ENTRIES, #ws.mru) do entries[i] = ws.mru[i] end
  local s = {window = w, entries = entries, sel = mru.step(#entries, 1, delta)}
  state.session = s
  hs.timer.doAfter(0, function()
    if state.session ~= s or s.canvas then return end
    local img = w:snapshot()
    if img then storePreview(ws, entries[1].key, img) end
  end)
  s.showTimer = hs.timer.doAfter(OVERLAY_DELAY, function()
    if state.session == s then renderOverlay() end
  end)
  return true
end

local function stepSession(delta)
  local s = state.session
  s.sel = mru.step(#s.entries, s.sel, delta)
  if s.showTimer then s.showTimer:stop() s.showTimer = nil end
  renderOverlay()
end

local TAB, ESC = hs.keycodes.map.tab, hs.keycodes.map.escape
local types = hs.eventtap.event.types

M.tap = hs.eventtap.new({types.keyDown, types.flagsChanged}, function(e)
  local flags = e:getFlags()
  if e:getType() == types.flagsChanged then
    if state.session and not flags.ctrl then commitSession() end
    return false
  end
  if not isSafariFront() then return false end
  local code = e:getKeyCode()
  if state.session then
    if code == TAB then stepSession(flags.shift and -1 or 1) return true end
    if code == ESC then cancelSession() return true end
    return false
  end
  if code == TAB and flags.ctrl and not flags.cmd and not flags.alt then
    return startSession(flags.shift and -1 or 1)
  end
  return false
end)
M.tap:start()

function M.cancel() endSession() end

function M.debugShow(delta)
  if not startSession(delta or 1) then return "no session" end
  state.session.showTimer:stop()
  renderOverlay()
  return "sel=" .. state.session.sel .. " entries=" .. #state.session.entries
end

M.windowFilter = wf
M.state = state
M.safari = safari
return M
