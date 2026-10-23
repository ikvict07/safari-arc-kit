local tabsMod = require("safari_tabs")
local config = require("kit_config")

local M = {}

M.rules = config.autoclose

local safari = tabsMod.safari
local pending = {}

local function ruleFor(url)
  for _, r in ipairs(M.rules) do
    if url:match(r.pattern) then return r end
  end
  return nil
end

local function closeMatching()
  local tabs = safari.tabs()
  local victims = {}
  for _, t in ipairs(tabs) do
    if ruleFor(t.url or "") then victims[#victims + 1] = t.index end
  end
  table.sort(victims, function(a, b) return a > b end)
  for _, idx in ipairs(victims) do
    hs.osascript.applescript(string.format([[tell application "Safari" to close tab %d of window 1]], idx))
  end
  return #victims
end

local function scan()
  for _, t in ipairs(safari.tabs()) do
    local r = ruleFor(t.url or "")
    if r and not pending[t.url] then
      pending[t.url] = true
      hs.timer.doAfter(r.delay, function()
        pending[t.url] = nil
        local n = closeMatching()
        if n > 0 then print("[safari_autoclose] closed " .. n .. " tab(s): " .. r.name) end
      end)
    end
  end
end

local wf = hs.window.filter.new(false):setAppFilter("Safari")
wf:subscribe({hs.window.filter.windowTitleChanged, hs.window.filter.windowFocused}, function()
  hs.timer.doAfter(0.3, scan)
end)

M.scan = scan
M.windowFilter = wf
return M
