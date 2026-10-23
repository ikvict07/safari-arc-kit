local config = require("kit_config")

local M = {}

local SAFARI = "com.apple.Safari"

M.profiles = config.profiles

local function safariWindows()
  local app = hs.application.get(SAFARI)
  if not app then return {}, nil end
  return app:allWindows(), app
end

local function findProfileWindow(name)
  local wins = safariWindows()
  local prefix = name .. " — "
  local best = nil
  for _, w in ipairs(wins) do
    local title = w:title() or ""
    if w:isStandard() and title:sub(1, #prefix) == prefix then
      if not best or (w:isVisible() and not best:isVisible()) then best = w end
    end
  end
  return best
end

function M.switchTo(name)
  local w = findProfileWindow(name)
  if w then
    w:focus()
    return true
  end
  local app = hs.application.get(SAFARI)
  if not app then
    hs.application.launchOrFocusByBundleID(SAFARI)
    hs.timer.doAfter(1.5, function() M.switchTo(name) end)
    return false
  end
  app:activate()
  if not app:selectMenuItem({"File", "New " .. name .. " Window"}) then
    hs.alert.show("Safari profile '" .. name .. "' not found", 2)
    return false
  end
  return true
end

local byCode = {}
for _, p in ipairs(M.profiles) do byCode[hs.keycodes.map[p.key]] = p.name end

M.tap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(e)
  local f = e:getFlags()
  if not (f.ctrl and not f.cmd and not f.alt and not f.shift) then return false end
  local front = hs.application.frontmostApplication()
  if not front or front:bundleID() ~= SAFARI then return false end
  local name = byCode[e:getKeyCode()]
  if not name then return false end
  M.switchTo(name)
  return true
end)
M.tap:start()

return M
