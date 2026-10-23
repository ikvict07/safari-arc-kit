local mru = {}

function mru.key(url, name)
  return (url or "") .. "|" .. (name or "")
end

function mru.new()
  return {}
end

function mru.touch(list, key, meta)
  local out = {{key = key, url = meta.url, name = meta.name, index = meta.index}}
  for _, e in ipairs(list) do
    if e.key ~= key then out[#out + 1] = e end
  end
  return out
end

function mru.reconcile(list, tabs)
  local byKey = {}
  for _, t in ipairs(tabs) do
    local k = mru.key(t.url, t.name)
    if not byKey[k] then byKey[k] = {key = k, url = t.url, name = t.name, index = t.index} end
  end
  local out, seen = {}, {}
  for _, e in ipairs(list) do
    local fresh = byKey[e.key]
    if fresh and not seen[e.key] then
      out[#out + 1] = fresh
      seen[e.key] = true
    end
  end
  for _, t in ipairs(tabs) do
    local k = mru.key(t.url, t.name)
    if not seen[k] then
      out[#out + 1] = byKey[k]
      seen[k] = true
    end
  end
  return out
end

function mru.remove(list, key)
  local out = {}
  for _, e in ipairs(list) do
    if e.key ~= key then out[#out + 1] = e end
  end
  return out
end

function mru.step(n, current, delta)
  if n <= 1 then return 1 end
  return ((current - 1 + delta) % n) + 1
end

function mru.visibleWindow(n, sel, max)
  if n <= max then return 1, n end
  local first = math.max(1, sel - max + 1)
  if first + max - 1 > n then first = n - max + 1 end
  return first, first + max - 1
end

return mru
