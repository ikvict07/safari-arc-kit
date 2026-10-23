package.path = "hammerspoon/?.lua;" .. package.path
local p = require("command_parse")
p.modes = {
  gh = {label = "GitHub my-org", url = "https://github.com/my-org?q=%s"},
  jira = {label = "Jira JQL", url = "https://example.atlassian.net/issues/?jql=%s"},
}

local function eq(a, b, msg) assert(a == b, msg .. ": got " .. tostring(a) .. " want " .. tostring(b)) end

local m, r = p.split("gh foo bar")
eq(m, "gh", "split mode"); eq(r, "foo bar", "split rest")
m, r = p.split("gh")
eq(m, "gh", "split bare mode"); eq(r, "", "split bare rest")
m, r = p.split("ghx")
eq(m, nil, "split non-mode"); eq(r, "ghx", "split non-mode rest")
m, r = p.split("  jira   project = ABC ")
eq(m, "jira", "split trims"); eq(r, "project = ABC", "split trims rest")
m, r = p.split("hello world")
eq(m, nil, "split plain"); eq(r, "hello world", "split plain rest")
m, r = p.split("   ")
eq(m, nil, "split blank"); eq(r, "", "split blank rest")

assert(p.isUrl("https://github.com/my-org"), "url scheme")
assert(p.isUrl("example.nl"), "url bare domain")
assert(p.isUrl("localhost:8080/x"), "url localhost")
assert(p.isUrl("github.com/my-org/close-ml-service"), "url with path")
assert(p.isUrl("127.0.0.1:3000"), "url ip")
assert(not p.isUrl("hello world"), "not url spaces")
assert(not p.isUrl("weather"), "not url word")
assert(not p.isUrl("example."), "not url trailing dot")
assert(not p.isUrl("3.5"), "not url number")

eq(p.toUrl("example.nl"), "https://example.nl", "toUrl adds scheme")
eq(p.toUrl("http://x.y"), "http://x.y", "toUrl keeps scheme")
eq(p.toUrl("localhost:8080"), "http://localhost:8080", "toUrl localhost http")

eq(p.encode("a b&c=d/é"), "a%20b%26c%3Dd%2F%C3%A9", "encode")
eq(p.modeUrl("gh", "close ml"), "https://github.com/my-org?q=close%20ml", "gh url")
eq(p.modeUrl("jira", "project = ABC"), "https://example.atlassian.net/issues/?jql=project%20%3D%20ABC", "jira url")
eq(p.searchUrl("hello world"), "https://www.google.com/search?q=hello%20world", "search url")

local tabs = {
  {url = "https://github.com/my-org/close-ml-service", name = "my-org/close-ml-service", index = 1},
  {url = "https://example.atlassian.net/browse/CMM-1", name = "CMM-1 Close ML bug", index = 2},
  {url = "https://youtube.com/watch", name = "(889) YouTube", index = 3},
  {url = "https://example.com/closet", name = "Furniture", index = 4},
}
local function names(list) local o = {} for i, t in ipairs(list) do o[i] = t.index end return table.concat(o, ",") end

eq(names(p.rankTabs(tabs, "close", {})), "1,2,4", "rank: name word-start > url, ties by index")
eq(names(p.rankTabs(tabs, "lose", {})), "1,2,4", "rank: name mid-word > url")
eq(names(p.rankTabs(tabs, "close", {["https://example.atlassian.net/browse/CMM-1|CMM-1 Close ML bug"] = 1})), "2,1,4", "rank: mru bonus")
eq(names(p.rankTabs(tabs, "close ml", {})), "1,2", "rank: all tokens required")
eq(names(p.rankTabs(tabs, "zzz", {})), "", "rank: no match")
eq(names(p.rankTabs(tabs, "", {})), "", "rank: empty query")
eq(names(p.rankTabs(tabs, "YOUTUBE", {})), "3", "rank: case-insensitive")

print("command_parse tests OK")
