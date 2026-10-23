local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]+$") or "."
package.path = here .. "/hammerspoon/?.lua;" .. package.path

local kit = {}
kit.config = require("kit_config")
kit.tabs = require("safari_tabs")
kit.profiles = require("safari_profiles")
kit.command = require("safari_command")
kit.sidebar = require("safari_sidebar")
kit.autoclose = require("safari_autoclose")
return kit
