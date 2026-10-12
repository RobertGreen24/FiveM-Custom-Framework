--[[
    Nexus Framework :: shared/utils.lua
    Dependency-free helpers used by every Nexus resource.
]]

Nexus = Nexus or {}
local Utils = {}
Nexus.Utils = Utils

--- Numbers ------------------------------------------------------------------

function Utils.round(num, dp)
    local mult = 10 ^ (dp or 0)
    return math.floor(num * mult + 0.5) / mult
end

function Utils.clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

--- Returns a value guaranteed to sit inside a vitals range from constants.
function Utils.clampVital(key, value)
    local cfg = Nexus.Vitals[key]
    if not cfg then return value end
    return Utils.clamp(math.floor(value), cfg.min, cfg.max)
end

function Utils.lerp(a, b, t)
    return a + (b - a) * t
end

--- Parses a MySQL DATETIME string ("YYYY-MM-DD HH:MM:SS") to a unix timestamp.
--- Returns nil when the value is not a recognisable timestamp.
function Utils.parseTimestamp(value)
    if type(value) ~= 'string' then return nil end

    local year, month, day, hour, minute, second =
        value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):(%d%d)')
    if not year then return nil end

    return os.time({
        year = tonumber(year), month = tonumber(month), day = tonumber(day),
        hour = tonumber(hour), min = tonumber(minute), sec = tonumber(second),
        isdst = false,
    })
end

--- Strings ------------------------------------------------------------------

function Utils.trim(str)
    return (tostring(str):gsub('^%s*(.-)%s*$', '%1'))
end

function Utils.capitalize(str)
    return (tostring(str):gsub('^%l', string.upper))
end

function Utils.titleCase(str)
    return (tostring(str):gsub('(%a)([%w]*)', function(a, b)
        return a:upper() .. b:lower()
    end))
end

function Utils.split(str, sep)
    local out = {}
    for piece in tostring(str):gmatch('([^' .. (sep or ',') .. ']+)') do
        out[#out + 1] = piece
    end
    return out
end

function Utils.startsWith(str, prefix)
    return str:sub(1, #prefix) == prefix
end

function Utils.formatNumber(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local sign, digits = '', s
    if s:sub(1, 1) == '-' then sign, digits = '-', s:sub(2) end
    local formatted = digits:reverse():gsub('(%d%d%d)', '%1,')
    formatted = formatted:reverse():gsub('^,', '')
    return sign .. formatted
end

function Utils.formatMoney(n, symbol)
    return (symbol or Nexus.MoneyConfig.symbol) .. Utils.formatNumber(n)
end

--- Converts seconds into "3d 4h 12m" -------------------------------------------------
function Utils.formatDuration(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    local days    = math.floor(seconds / 86400)
    local hours   = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local parts = {}
    if days > 0 then parts[#parts + 1] = days .. 'd' end
    if hours > 0 then parts[#parts + 1] = hours .. 'h' end
    parts[#parts + 1] = minutes .. 'm'
    return table.concat(parts, ' ')
end

--- Tables -------------------------------------------------------------------

function Utils.deepCopy(tbl)
    if type(tbl) ~= 'table' then return tbl end
    local out = {}
    for k, v in pairs(tbl) do
        out[k] = Utils.deepCopy(v)
    end
    return setmetatable(out, getmetatable(tbl))
end

function Utils.count(tbl)
    local n = 0
    if tbl then for _ in pairs(tbl) do n = n + 1 end end
    return n
end

function Utils.keys(tbl)
    local out = {}
    if tbl then for k in pairs(tbl) do out[#out + 1] = k end end
    return out
end

function Utils.values(tbl)
    local out = {}
    if tbl then for _, v in pairs(tbl) do out[#out + 1] = v end end
    return out
end

function Utils.shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

function Utils.indexOf(list, value)
    for i = 1, #list do
        if list[i] == value then return i end
    end
    return nil
end

function Utils.contains(list, value)
    return Utils.indexOf(list, value) ~= nil
end

function Utils.merge(base, override)
    local out = {}
    for k, v in pairs(base or {}) do out[k] = v end
    for k, v in pairs(override or {}) do
        if type(v) == 'table' and type(out[k]) == 'table' then
            out[k] = Utils.merge(out[k], v)
        else
            out[k] = v
        end
    end
    return out
end

--- Filter a table into a new array (predicate receives value, key) -----------
function Utils.filter(tbl, predicate)
    local out = {}
    for k, v in pairs(tbl) do
        if predicate(v, k) then out[#out + 1] = v end
    end
    return out
end

function Utils.map(tbl, fn)
    local out = {}
    for k, v in pairs(tbl) do out[k] = fn(v, k) end
    return out
end

--- JSON ---------------------------------------------------------------------
--- FiveM ships json.encode/json.decode in both runtimes; wrapping them means
--- a resource only has to guard against malformed data in one place.

function Utils.encodeJson(value)
    local ok, result = pcall(json.encode, value)
    if ok then return result end
    return nil
end

function Utils.decodeJson(value, fallback)
    if value == nil or value == '' then return fallback end
    if type(value) == 'table' then return value end
    local ok, result = pcall(json.decode, value)
    if ok and result ~= nil then return result end
    return fallback
end

--- Returns a safe, sanitised vector3 from loose input -----------------------
function Utils.toVec3(x, y, z)
    return vector3(tonumber(x) or 0.0, tonumber(y) or 0.0, tonumber(z) or 0.0)
end

--- Unique ids -----------------------------------------------------------------
--- random hex string, good enough for per-session ids / drop ids.
function Utils.uuid(length)
    length = length or 12
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    local out = template:gsub('[xy]', function(c)
        local v = (c == 'x') and math.random(0, 15) or math.random(8, 11)
        return string.format('%x', v)
    end)
    if length and length < #out then return out:sub(1, length) end
    return out
end

--- State helpers -------------------------------------------------------------
--- Namespaced key so Nexus state bags never clash with another framework.
function Utils.state(key)
    return ('nx:%s'):format(key)
end

--- Colours -------------------------------------------------------------------
--- GTA colour ids -> hex, used by the HUD and the vehicle colour picker.
Utils.ConvertRGBToHex = function(r, g, b)
    return string.format('#%02x%02x%02x', math.floor(r) % 256, math.floor(g) % 256, math.floor(b) % 256)
end

--- Time ----------------------------------------------------------------------
function Utils.timestamp()
    return os.time()
end

function Utils.formatTimestamp(ts, fmt)
    return os.date(fmt or '%Y-%m-%d %H:%M:%S', tonumber(ts) or os.time())
end

--- Returns a copy of a table with only the listed keys ----------------------
function Utils.pick(tbl, keys)
    local out = {}
    for i = 1, #keys do
        local k = keys[i]
        if tbl[k] ~= nil then out[k] = tbl[k] end
    end
    return out
end

--- Deep equality for small tables (config diffing, UI caching) ---------------
function Utils.deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for k, v in pairs(a) do
        if not Utils.deepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end
