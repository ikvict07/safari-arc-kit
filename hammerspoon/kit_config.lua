local M = {}

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)/hammerspoon/[^/]+$") or "."
M.dir = here

local defaults = {
  profiles = {
    {key = "1", name = "Personal"},
    {key = "2", name = "Work"},
  },
  favorites = {},
  modes = {
    gh = {label = "GitHub", url = "https://github.com/search?type=repositories&q=%s"},
  },
  tabs = {maxEntries = 5, overlayDelay = 0.15},
  sidebar = {width = 280, stripWidth = 6, showDelay = 0.12},
  command = {width = 760, top = 0.3},
  autoclose = {
    {name = "oauth callback", pattern = "^https?://127%.0%.0%.1:%d+/oauth/callback%?.*code=", delay = 0.5},
    {name = "oauth callback", pattern = "^https?://localhost:%d+/oauth/callback%?.*code=", delay = 0.5},
  },
}

local function merge(base, over)
  if type(over) ~= "table" then return base end
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over) do
    if type(v) == "table" and type(base[k]) == "table" and #v == 0 and #base[k] == 0 then
      out[k] = merge(base[k], v)
    else
      out[k] = v
    end
  end
  return out
end

local userFile = os.getenv("HOME") .. "/.hammerspoon/safari-arc-kit-config.lua"
local chunk = loadfile(userFile)
local user = chunk and chunk() or nil
if chunk == nil then
  local legacy = loadfile(here .. "/config.lua")
  user = legacy and legacy() or nil
end

local cfg = merge(defaults, user)
for k, v in pairs(cfg) do M[k] = v end
M.html = function(name) return here .. "/hammerspoon/" .. name end
return M
