local parse = {}

parse.modes = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function parse.split(query)
  local q = trim(query or "")
  local word, rest = q:match("^(%S+)%s*(.*)$")
  if word and parse.modes[word:lower()] and (rest ~= "" or q == word) then
    return word:lower(), trim(rest)
  end
  return nil, q
end

function parse.isUrl(text)
  local t = trim(text or "")
  if t == "" or t:find("%s") then return false end
  if t:match("^%a[%w+.-]*://%S+$") then return true end
  local host = t:match("^([^/:?#]+)")
  if not host then return false end
  if host == "localhost" then return true end
  if host:match("^%d+%.%d+%.%d+%.%d+$") then return true end
  if host:match("^[%w-]+%.[%w.-]*%a[%w-]*$") and host:match("%.%a%a+$") then return true end
  return false
end

function parse.toUrl(text)
  local t = trim(text)
  if t:match("^%a[%w+.-]*://") then return t end
  if t:match("^localhost") or t:match("^%d+%.%d+%.%d+%.%d+") then return "http://" .. t end
  return "https://" .. t
end

function parse.encode(text)
  return (text:gsub("[^%w%-_.~]", function(c)
    return string.format("%%%02X", c:byte())
  end))
end

function parse.modeUrl(mode, text)
  return string.format(parse.modes[mode].url, parse.encode(trim(text)))
end

function parse.searchUrl(text)
  return "https://www.google.com/search?q=" .. parse.encode(trim(text))
end

local function tokens(query)
  local out = {}
  for w in (query or ""):lower():gmatch("%S+") do out[#out + 1] = w end
  return out
end

local function scoreField(field, token, startBonus, midBonus)
  local s, e = field:find(token, 1, true)
  if not s then return nil end
  if s == 1 or field:sub(s - 1, s - 1):match("[%s%p]") then return startBonus end
  return midBonus
end

function parse.rankTabs(tabs, query, mruKeys)
  local toks = tokens(query)
  if #toks == 0 then return {} end
  local ranked = {}
  for _, t in ipairs(tabs) do
    local name, url = (t.name or ""):lower(), (t.url or ""):lower()
    local total, ok = 0, true
    for _, tok in ipairs(toks) do
      local s = scoreField(name, tok, 3, 2) or scoreField(url, tok, 1, 1)
      if not s then ok = false break end
      total = total + s
    end
    if ok then
      local pos = mruKeys[(t.url or "") .. "|" .. (t.name or "")]
      if pos and pos <= 5 then total = total + 2 end
      ranked[#ranked + 1] = {tab = t, score = total}
    end
  end
  table.sort(ranked, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.tab.index < b.tab.index
  end)
  local out = {}
  for i, r in ipairs(ranked) do out[i] = r.tab end
  return out
end

return parse
