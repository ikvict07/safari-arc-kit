package.path = "hammerspoon/?.lua;" .. package.path
local mru = require("mru")

local function keys(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.key end
  return out
end

local function eq(a, b, msg)
  assert(#a == #b, msg .. ": length " .. #a .. " vs " .. #b)
  for i = 1, #a do assert(a[i] == b[i], msg .. ": at " .. i .. " got " .. tostring(a[i]) .. " want " .. tostring(b[i])) end
end

local function tab(url, name, index) return {url = url, name = name, index = index} end

assert(mru.key("https://a", "A") == "https://a|A", "key format")

local l = mru.new()
l = mru.touch(l, "a", tab("https://a", "A", 1))
l = mru.touch(l, "b", tab("https://b", "B", 2))
eq(keys(l), {"b", "a"}, "touch inserts at head")
l = mru.touch(l, "a", tab("https://a", "A", 1))
eq(keys(l), {"a", "b"}, "touch moves to head")
assert(l[1].index == 1 and l[1].name == "A", "touch stores meta")

local tabs = {tab("https://b", "B", 1), tab("https://c", "C", 2), tab("https://d", "D", 3)}
local r = mru.reconcile(l, tabs)
eq(keys(r), {"https://b|B", "https://c|C", "https://d|D"}, "reconcile with key-mismatched entries drops them")

l = mru.new()
l = mru.touch(l, mru.key("https://a", "A"), tab("https://a", "A", 1))
l = mru.touch(l, mru.key("https://b", "B"), tab("https://b", "B", 2))
tabs = {tab("https://b", "B", 1), tab("https://c", "C", 2)}
r = mru.reconcile(l, tabs)
eq(keys(r), {"https://b|B", "https://c|C"}, "reconcile drops closed a, appends new c")
assert(r[1].index == 1, "reconcile refreshes index")

tabs = {tab("https://x", "X", 1), tab("https://x", "X", 2)}
r = mru.reconcile(mru.new(), tabs)
eq(keys(r), {"https://x|X"}, "duplicates collapse")
assert(r[1].index == 1, "duplicate keeps first index")

l = mru.remove(r, "https://x|X")
eq(keys(l), {}, "remove")

assert(mru.step(3, 1, 1) == 2, "step forward")
assert(mru.step(3, 3, 1) == 1, "step wraps forward")
assert(mru.step(3, 1, -1) == 3, "step wraps backward")
assert(mru.step(1, 1, 1) == 1, "step single")

local f, t = mru.visibleWindow(5, 2, 8)
assert(f == 1 and t == 5, "all fit")
f, t = mru.visibleWindow(20, 2, 8)
assert(f == 1 and t == 8, "start")
f, t = mru.visibleWindow(20, 12, 8)
assert(f == 5 and t == 12, "middle keeps selection at right edge")
f, t = mru.visibleWindow(20, 20, 8)
assert(f == 13 and t == 20, "end")

print("mru tests OK")
