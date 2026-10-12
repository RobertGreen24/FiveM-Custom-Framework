--[[
    Nexus Framework :: server/database.lua
    A thin, promise-aware wrapper around oxmysql.

    Why not use the `@oxmysql/lib/MySQL.lua` import? Because a missing oxmysql
    would then stop nx_core from starting at all, and a half-started framework is
    harder to debug than a loud error. Everything here talks to the exports
    directly and degrades with a clear message.
]]

Nexus = Nexus or {}
local DB = {}
Nexus.DB = DB

local RESOURCE = GetCurrentResourceName()
DB.available = false
DB.resourceName = 'oxmysql'

local promise = promise  -- citizen's promise library is global

--- Detect the driver once, at startup.
function DB.detect()
    if GetResourceState('oxmysql') ~= 'started' then
        DB.available = false
        return false
    end
    DB.available = true
    return true
end

--- The raw call. Returns rows (select), affected rows (update) or insertId.
---@param method string 'query'|'single'|'scalar'|'insert'|'update'|'prepare'
function DB.call(method, query, params)
    if not DB.available then
        Nexus.Print.error('Database call attempted while oxmysql is unavailable: %s', query)
        return nil
    end

    local fn = exports.oxmysql[method]
    if not fn then
        Nexus.Print.error('oxmysql has no method "%s" (is it up to date?)', method)
        return nil
    end

    params = params or {}

    -- Modern oxmysql returns a promise when no callback is supplied.
    local ok, result = pcall(fn, query, params)

    if ok and result ~= nil then
        -- promise object
        if type(result) == 'table' and (result.await ~= nil or getmetatable(result) ~= nil) then
            local awaited = Citizen.Await(result)
            return awaited
        end
        return result
    end

    -- Legacy callback signature.
    local p = promise.new()
    local ok2 = pcall(fn, query, params, function(res)
        p:resolve(res)
    end)

    if not ok2 then
        Nexus.Print.error('Database %s failed: %s | query: %s', method, tostring(result), query)
        return nil
    end

    local timer = Citizen.SetTimeout(10000, function()
        if p then p:reject('timeout') end
    end)

    local value = Citizen.Await(p)
    Citizen.ClearTimeout(timer)
    return value
end

--- SELECT many ----------------------------------------------------------------
function DB.query(query, params)
    return DB.call('query', query, params) or {}
end

--- SELECT one ------------------------------------------------------------------
function DB.single(query, params)
    local result = DB.call('single', query, params)
    if type(result) == 'table' and result[1] ~= nil and result.id == nil then
        return result[1]
    end
    return result
end

--- SELECT a single column value ------------------------------------------------
function DB.scalar(query, params)
    return DB.call('scalar', query, params)
end

--- INSERT, returns insertId -----------------------------------------------------
function DB.insert(query, params)
    return DB.call('insert', query, params)
end

--- UPDATE / DELETE, returns affected rows ---------------------------------------
function DB.update(query, params)
    return DB.call('update', query, params)
end

--- Multiple statements in one transaction --------------------------------------
---@param queries table list of { query = string, params = table }
function DB.transaction(queries)
    if not DB.available then return nil end
    local payload = {}
    for i = 1, #queries do
        payload[i] = { queries[i].query, queries[i].params or {} }
    end
    local ok, result = pcall(exports.oxmysql.transaction, payload)
    if ok then return result end
    Nexus.Print.error('Transaction failed: %s', tostring(result))
    return nil
end

--- Fire-and-forget (used for logs/analytics so a slow insert never blocks) -----
function DB.defer(query, params)
    Citizen.CreateThread(function()
        DB.call('update', query, params)
    end)
end

--- Schema presence check so a forgotten import gives a useful error ------------
function DB.verifySchema()
    local row = DB.single("SELECT COUNT(*) AS count FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name IN ('nx_players','nx_characters','nx_inventory','nx_vehicles')")
    local count = tonumber(row and row.count or 0)
    if count < 4 then
        Nexus.Print.error('=========================================================')
        Nexus.Print.error(' nx_core: database schema is missing or incomplete.')
        Nexus.Print.error(' Import sql/nexus.sql into your database, then restart.')
        Nexus.Print.error(' Found %d/4 core tables.', count)
        Nexus.Print.error('=========================================================')
        return false
    end
    Nexus.Print.info('Schema verified (%d core tables present).', count)
    return true
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= 'oxmysql' then return end
    DB.detect()
    Nexus.Print.info('oxmysql became available.')
end)
