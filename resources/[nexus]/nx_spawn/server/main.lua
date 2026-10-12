--[[
    Nexus Framework :: nx_spawn (server)
    Takes over `nexus:server:requestSpawn` from nx_core: instead of dropping the
    player at their last location we send a list of allowed spawn points to the
    client and wait for a choice.
]]

local Nexus = Nexus

--- Every spawn key this player may use, in display order.
local function allowedSpawns(player)
    local list = {}
    local seen = {}

    local function push(key, reason)
        local point = Config.SpawnPoints[key]
        if not point or seen[key] then return end
        seen[key] = true
        list[#list + 1] = {
            key = key,
            label = point.label,
            coords = { point.coords.x, point.coords.y, point.coords.z, point.coords.w },
            reason = reason,
        }
    end

    -- 1. their last location, if it still exists
    if SpawnConfig.highlightLast and player.lastLocation and Config.SpawnPoints[player.lastLocation] then
        push(player.lastLocation, 'last')
    end

    -- 2. public points
    for _, key in ipairs(SpawnConfig.public or {}) do
        push(key, 'public')
    end

    -- 3. job-restricted points
    local jobSpawns = (SpawnConfig.jobRestricted or {})[player.job.name]
    if jobSpawns then
        for _, key in ipairs(jobSpawns) do
            push(key, 'job')
        end
    end

    -- 4. block anything inside a blocked zone (safety net for bad configs)
    for _, zone in ipairs(SpawnConfig.blockedZones or {}) do
        local coords = zone.coords
        local kept = {}
        for _, entry in ipairs(list) do
            local distance = #(vector3(entry.coords[1], entry.coords[2], entry.coords[3]) - vector3(coords.x, coords.y, coords.z))
            if distance > (zone.radius or 25.0) then
                kept[#kept + 1] = entry
            end
        end
        list = kept
    end

    return list
end

AddEventHandler('nexus:server:requestSpawn', function(player)
    local spawns = allowedSpawns(player)

    -- Straight to the ground when someone is mid-respawn or the list is trivial.
    if #spawns == 0 then
        Nexus.FinishSpawn(player, Config.DefaultSpawn)
        return
    end

    TriggerClientEvent('nexus:client:openSpawnSelector', player.source, {
        spawns = spawns,
        lastLocation = player.lastLocation,
        lastCoords = SpawnConfig.lastPosition and {
            player.position.x, player.position.y, player.position.z, player.position.w,
        } or nil,
        timeout = SpawnConfig.autoSelectTimeout,
        name = player:getName(),
        job = player.job.label,
    })
end)

--- The client picked a spot (or we timed out and it picked for them).
RegisterNetEvent('nexus:server:chooseSpawn', function(key, useLastPosition)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end
    if player.spawned then return end   -- never double-spawn

    -- validate the key against what we offered
    local valid = false
    for _, entry in ipairs(allowedSpawns(player)) do
        if entry.key == key then valid = true break end
    end
    if not valid then key = Config.DefaultSpawn end

    if useLastPosition and SpawnConfig.lastPosition then
        local x, y, z, w = player.position.x, player.position.y, player.position.z, player.position.w
        -- Never resume inside a blocked zone or at world origin (first login).
        if x ~= 0.0 or y ~= 0.0 then
            local blocked = false
            for _, zone in ipairs(SpawnConfig.blockedZones or {}) do
                if #(vector3(x, y, z) - vector3(zone.coords.x, zone.coords.y, zone.coords.z)) <= (zone.radius or 25.0) then
                    blocked = true
                    break
                end
            end
            if not blocked then
                Nexus.FinishSpawn(player, player.lastLocation or key, vector4(x, y, z, w))
                return
            end
        end
    end

    Nexus.FinishSpawn(player, key)
end)

--- Auto-pick for players who close the UI or idle: fall back to their last spot.
RegisterNetEvent('nexus:server:spawnTimeout', function()
    local player = Nexus.GetPlayer(source)
    if not player or player.spawned then return end
    Nexus.FinishSpawn(player, player.lastLocation or Config.DefaultSpawn)
end)
