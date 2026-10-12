--[[
    Nexus Framework :: nx_police (server)
    Custody, fines, evidence, impounding and the callsign register.
]]

Nexus = Nexus or {}

local function isOfficer(player, minGrade)
    if not player or not player.loaded then return false, 'not loaded' end
    if player:can('nexus.admin') then return true end
    if player.job.name ~= PoliceConfig.job then return false, 'not police' end
    if player.job.grade < (minGrade or PoliceConfig.minGrade) then return false, 'grade too low' end
    return true
end

Nexus.IsOfficer = isOfficer

--- Officers on duty, used by dispatch, the MDT and pings.
local function onDutyOfficers()
    local list = {}
    for _, player in ipairs(Nexus.GetPlayers()) do
        if player.job.name == PoliceConfig.job and player:isOnDuty() then
            list[#list + 1] = player
        end
    end
    return list
end

Nexus.OnDutyOfficers = onDutyOfficers

-- ===========================================================================
--  CALLSIGNS
-- ===========================================================================

local function nextCallsign()
    local taken = {}
    for _, player in ipairs(Nexus.GetPlayers()) do
        if player.callsign then taken[player.callsign] = true end
    end
    for i = 1, 999 do
        local candidate = ('%d-%02d'):format(math.floor(i / 10) + 1, i % 10 + 1)
        if not taken[candidate] then return candidate end
    end
    return tostring(math.random(100, 999))
end

RegisterNetEvent('nx_police:setCallsign', function(callsign)
    local player = Nexus.GetPlayer(source)
    local ok = isOfficer(player)
    if not ok then return end

    if callsign == nil or callsign == '' then
        callsign = nextCallsign()
    else
        callsign = tostring(callsign):sub(1, 10)
        for _, other in ipairs(Nexus.GetPlayers()) do
            if other.source ~= player.source and other.callsign == callsign then
                player:notify('That callsign is already in use.', 'error')
                return
            end
        end
    end

    player:setCallsign(callsign)
    player:notify(('Your callsign is %s'):format(callsign), 'info', 6000, 'Police')
end)

RegisterCommand(PoliceConfig.callsignCommand, function(source, args)
    local player = Nexus.GetPlayer(source)
    if not isOfficer(player) then return end
    TriggerEvent('nx_police:setCallsign', source, args[1])
end, false)

-- ===========================================================================
--  PINGS / BACKUP
-- ===========================================================================

RegisterNetEvent('nx_police:backup', function(kind, coords)
    local player = Nexus.GetPlayer(source)
    if not isOfficer(player) then return end

    kind = kind or 'backup'
    coords = coords or player:getCoords()

    local officers = onDutyOfficers()
    for _, officer in ipairs(officers) do
        officer:notify(('%s requested %s'):format(player:getName(), kind:upper()), 'warning', 9000, 'Dispatch')
        TriggerClientEvent('nx_police:backupAlert', officer.source, {
            from = player:getName(),
            callsign = player.callsign,
            kind = kind,
            coords = { coords.x, coords.y, coords.z },
        })
    end

    player:notify(('Backup request sent to %d officer(s).'):format(#officers), 'success', 6000, 'Dispatch')
end)

RegisterNetEvent('nx_police:panic', function()
    local player = Nexus.GetPlayer(source)
    if not isOfficer(player) then return end
    TriggerEvent('nx_police:backup', source, 'PANIC BUTTON', player:getCoords())
end)

--- Dispatch alert helper used by other resources (nx_mechanic robberies, etc).
--- @usage TriggerEvent('nx_police:dispatch', coords, 'Armed robbery', '10-31')
RegisterNetEvent('nx_police:dispatch', function(coords, message, code, priority)
    if not coords then return end
    for _, officer in ipairs(onDutyOfficers()) do
        TriggerClientEvent('nx_police:dispatchAlert', officer.source, {
            message = message or 'Incident reported',
            code = code or '10-13',
            priority = priority or 'normal',
            coords = { coords.x, coords.y, coords.z },
        })
    end
end)

-- ===========================================================================
--  ARREST / JAIL
-- ===========================================================================

local cuffed = {}          -- [charId] = { by = charId, time = os.time() }
local jailed = {}          -- [charId] = { until = os.time() + secs, reason, fine, by }

Nexus.IsCuffed = function(charId) return cuffed[charId] ~= nil end
Nexus.GetCustody = function(charId) return jailed[charId] end

RegisterNetEvent('nx_police:cuff', function(targetSource)
    local player = Nexus.GetPlayer(source)
    local ok = isOfficer(player)
    if not ok then return end

    local target = Nexus.GetPlayer(tonumber(targetSource))
    if not target or not target.loaded then
        player:notify('No such player.', 'error')
        return
    end

    local myCoords = player:getCoords()
    if #(myCoords - target:getCoords()) > 3.0 then
        player:notify('You are too far away.', 'error')
        return
    end

    if cuffed[target.charId] then
        cuffed[target.charId] = nil
        target:setMeta('cuffed', false)
        TriggerClientEvent('nx_police:cuffState', target.source, false)
        target:notify('You have been released.', 'info')
        player:notify(('Released %s.'):format(target:getName()), 'info')
    else
        cuffed[target.charId] = { by = player.charId, time = os.time() }
        target:setMeta('cuffed', true)
        TriggerClientEvent('nx_police:cuffState', target.source, true, {
            officer = player:getName(),
            callsign = player.callsign,
        })
        target:notify('You have been cuffed.', 'warning')
        player:notify(('Cuffed %s.'):format(target:getName()), 'success')
    end

    Nexus.Log.action('police_cuff', {
        actor = player:getName(), target = target:getName(),
        details = cuffed[target.charId] and 'cuffed' or 'uncuffed',
    })
end)

RegisterNetEvent('nx_police:search', function(targetSource)
    local player = Nexus.GetPlayer(source)
    local ok = isOfficer(player)
    if not ok then return end

    local target = Nexus.GetPlayer(tonumber(targetSource))
    if not target or not target.loaded then return end
    if #(player:getCoords() - target:getCoords()) > 3.0 then
        player:notify('You are too far away.', 'error')
        return
    end

    local items = exports.nx_inventory:getItems(target.source)
    TriggerClientEvent('nx_police:searchResult', source, {
        name = target:getName(),
        stateId = target:getStateId(),
        items = items,
        cash = target:getMoney('cash'),
    })
end)

--- Snap a pair of cuffs: the officer takes everything in `seizableItems`.
RegisterNetEvent('nx_police:seize', function(targetSource)
    local player = Nexus.GetPlayer(source)
    local ok = isOfficer(player)
    if not ok then return end

    local target = Nexus.GetPlayer(tonumber(targetSource))
    if not target or not target.loaded then return end

    local seized = 0
    for _, item in ipairs(PoliceConfig.seizableItems) do
        local count = exports.nx_inventory:getItemCount(target.source, item)
        if count > 0 then
            if exports.nx_inventory:removeItem(target.source, item, count) then
                seized = seized + count
                exports.nx_inventory:addItem(source, item, count)
            end
        end
    end

    player:notify(('Seized %d item stack(s).'):format(seized), 'success')
    target:notify('Your possessions were seized.', 'error', 8000)

    Nexus.Log.action('police_seize', {
        actor = player:getName(), target = target:getName(),
        details = ('%d items'):format(seized),
    })
end)

RegisterNetEvent('nx_police:jail', function(targetSource, minutes, reason, fine)
    local player = Nexus.GetPlayer(source)
    local ok = isOfficer(player, 2)
    if not ok then
        if player and player.loaded then player:notify('You are not authorised to jail people.', 'error') end
        return
    end

    local target = Nexus.GetPlayer(tonumber(targetSource))
    if not target or not target.loaded then return end

    minutes = math.max(1, math.min(PoliceConfig.maxSentence, math.floor(tonumber(minutes) or 5)))
    fine = math.max(0, math.min(PoliceConfig.maxFine, math.floor(tonumber(fine) or (minutes * PoliceConfig.jailFinePerMin))))

    jailed[target.charId] = {
        releaseAt = os.time() + (minutes * 60),
        minutes = minutes,
        reason = reason or 'No reason given',
        fine = fine,
        by = player:getName(),
    }
    cuffed[target.charId] = nil

    if PoliceConfig.stripOnJail then
        for _, item in ipairs(PoliceConfig.seizableItems) do
            local count = exports.nx_inventory:getItemCount(target.source, item)
            if count > 0 then
                exports.nx_inventory:removeItem(target.source, item, count)
            end
        end
    end

    target:setMeta('cuffed', nil)
    target:setMeta('jailed', true)
    target:setMeta('jailRelease', os.time() + (minutes * 60))
    TriggerClientEvent('nx_police:jailPlayer', target.source, {
        minutes = minutes, reason = reason, fine = fine,
    })

    Nexus.Log.action('police_jail', {
        actor = player:getName(), target = target:getName(),
        details = ('%d min · %s · %s'):format(minutes, reason or '-', Nexus.Utils.formatMoney(fine)),
    })

    player:notify(('%s jailed for %d minute(s).'):format(target:getName(), minutes), 'success', 7000)
end)

RegisterNetEvent('nx_police:unjail', function(targetSource, release)
    local source = source
    local officer = Nexus.GetPlayer(source)
    local ok = officer and isOfficer(officer)

    local target
    if targetSource then
        target = Nexus.GetPlayer(tonumber(targetSource))
    else
        target = officer
    end
    if not target then return end

    local record = jailed[target.charId]
    if not record then return end
    if not ok and source ~= 0 and target.source ~= source then return end

    jailed[target.charId] = nil
    target:setMeta('jailed', false)
    target:setMeta('jailRelease', nil)

    -- pay the fine on release if they can afford it
    if release ~= false and record.fine > 0 then
        if target:removeMoney('bank', record.fine, 'jail fine') then
            Nexus.Society.addMoney('police', record.fine, 'fine')
            target:notify(('Fine of %s paid.'):format(Nexus.Utils.formatMoney(record.fine)), 'money')
        else
            target:setMeta('unpaidFines', (target:getMeta('unpaidFines', 0) + record.fine))
            target:notify(('Fine of %s added to your record.'):format(Nexus.Utils.formatMoney(record.fine)), 'warning', 8000)
        end
    end

    TriggerClientEvent('nx_police:releasePlayer', target.source)
    if officer and officer.source ~= target.source then
        officer:notify(('%s released.'):format(target:getName()), 'info')
    end
end)

--- Auto-release when the sentence runs out.
CreateThread(function()
    while true do
        Citizen.Wait(20 * 1000)
        for charId, record in pairs(jailed) do
            if os.time() >= record.releaseAt then
                local player = Nexus.GetPlayerByCharId(charId)
                jailed[charId] = nil
                if player and player.loaded then
                    player:setMeta('jailed', false)
                    player:setMeta('jailRelease', nil)
                    TriggerClientEvent('nx_police:releasePlayer', player.source)
                    player:notify('Your sentence is complete.', 'success', 8000, 'Police')
                end
            end
        end
    end
end)

-- ===========================================================================
--  FINES
-- ===========================================================================

Nexus.GiveFine = function(target, amount, reason, actor)
    amount = math.max(1, math.min(PoliceConfig.maxFine, math.floor(tonumber(amount) or 0)))
    if not target or not target.loaded then return false end

    target:setMeta('unpaidFines', (target:getMeta('unpaidFines', 0) + amount))
    target:notify(('You were fined %s · %s'):format(Nexus.Utils.formatMoney(amount), reason or 'No reason'), 'error', 9000, 'Citation')
    TriggerClientEvent('nx_police:fineAdded', target.source, amount, reason)

    Nexus.Log.action('fine_issued', {
        actor = actor or 'system', target = target:getName(),
        details = ('%s · %s'):format(Nexus.Utils.formatMoney(amount), reason or '-'),
    })
    return true
end

RegisterNetEvent('nx_police:fine', function(targetSource, amount, reason)
    local player = Nexus.GetPlayer(source)
    local ok = isOfficer(player)
    if not ok then return end

    local target = Nexus.GetPlayer(tonumber(targetSource))
    if not target or not target.loaded then
        player:notify('No such player.', 'error')
        return
    end

    if Nexus.GiveFine(target, amount, reason, player:getName()) then
        player:notify(('Fined %s %s'):format(target:getName(), Nexus.Utils.formatMoney(amount)), 'success')
    end
end)

RegisterCommand(PoliceConfig.fineCommand, function(source, args)
    if source == 0 then return end
    local target, amount = tonumber(args[1]), tonumber(args[2])
    local reason = table.concat(args, ' ', 3)
    if not target or not amount then
        local player = Nexus.GetPlayer(source)
        if player then player:notify('Usage: /fine [id] [amount] [reason]', 'error') end
        return
    end
    TriggerEvent('nx_police:fine', source, target, amount, reason)
end, false)

--- /payfine — clear outstanding fines from the MDT or a police station.
RegisterNetEvent('nx_police:payFines', function()
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local owed = tonumber(player:getMeta('unpaidFines', 0)) or 0
    if owed <= 0 then
        player:notify('You have no outstanding fines.', 'info')
        return
    end

    if not player:removeMoney('bank', owed, 'outstanding fines') then
        player:notify(('You owe %s but cannot pay it right now.'):format(Nexus.Utils.formatMoney(owed)), 'error')
        return
    end

    player:setMeta('unpaidFines', 0)
    Nexus.Society.addMoney('police', owed, 'fine payment')
    player:notify(('Paid %s in fines. You are clear.'):format(Nexus.Utils.formatMoney(owed)), 'success', 8000)
end)

-- ===========================================================================
--  IMPOUND
-- ===========================================================================

RegisterNetEvent('nx_police:impound', function(plate, reason)
    local player = Nexus.GetPlayer(source)
    local ok = isOfficer(player)
    if not ok or not PoliceConfig.canImpound then return end

    plate = tostring(plate or ''):upper():gsub('%s+', '')
    if plate == '' then return end

    local result = Nexus.ImpoundVehicle(plate, reason or 'Police impound', 'impound')
    if result then
        player:notify(('%s impounded.'):format(plate), 'success')
        Nexus.Log.action('vehicle_impound', {
            actor = player:getName(), target = plate, details = reason or 'police impound',
        })
    else
        player:notify('Could not find that vehicle.', 'error')
    end
end)

-- ===========================================================================
--  RADAR
-- ===========================================================================

RegisterNetEvent('nx_police:radarReport', function(plate, speed, model)
    local player = Nexus.GetPlayer(source)
    if not isOfficer(player) then return end

    local owner = Nexus.DB.single('SELECT char_id, label FROM nx_vehicles WHERE plate = ?', { plate })
    local line = owner
        and ('%s · %s · %d km/h'):format(plate, owner.label or model or 'vehicle', speed)
        or ('%s · unregistered · %d km/h'):format(plate, speed)

    for _, officer in ipairs(onDutyOfficers()) do
        officer:notify(line, 'warning', 6000, 'Radar')
    end
end)

-- ===========================================================================
--  CELL BLOCKS / STATIONS
-- ===========================================================================

--- Where jailed players are teleported to. `calls` are radio cells.
PoliceConfig.cells = {
    { name = 'mrpd_cell_1', coords = vector3(461.4, -990.9, 24.9), heading = 90.0 },
    { name = 'mrpd_cell_2', coords = vector3(461.4, -985.0, 24.9), heading = 90.0 },
    { name = 'mrpd_cell_3', coords = vector3(461.4, -979.1, 24.9), heading = 90.0 },
    { name = 'sandy_cell',  coords = vector3(1858.0, 3691.0, 34.2), heading = 180.0 },
}

RegisterNetEvent('nx_police:cellOf', function()
    local player = Nexus.GetPlayer(source)
    if not isOfficer(player) then return end
    TriggerClientEvent('nexus:client:policeCells', source, PoliceConfig.cells)
end)

-- ===========================================================================
--  LOADOUT
-- ===========================================================================

RegisterNetEvent('nx_police:requestLoadout', function()
    local player = Nexus.GetPlayer(source)
    local ok = isOfficer(player)
    if not ok then
        if player and player.loaded then player:notify('You are not a police officer.', 'error') end
        return
    end

    -- armoury is inside a station: check them against the cell block coords
    local coords = player:getCoords()
    local nearStation = false
    for _, cell in ipairs(PoliceConfig.cells) do
        if #(coords - cell.coords) < 150.0 then nearStation = true end
    end
    if not nearStation then
        player:notify('Visit a police station to draw equipment.', 'error')
        return
    end

    local grade = player.job.grade
    for _, entry in ipairs(PoliceConfig.loadout) do
        if entry.minGrade == nil or grade >= entry.minGrade then
            exports.nx_inventory:addItem(source, entry.item, entry.amount)
        end
    end

    player:notify('Equipment issued.', 'success')
    Nexus.Log.action('police_loadout', { actor = player:getName(), details = ('grade %d'):format(grade) })
end)

exports('isOfficer', function(source, minGrade) return (isOfficer(Nexus.GetPlayer(source), minGrade)) end)
exports('onDuty', function() return onDutyOfficers() end)
exports('fine', function(source, amount, reason) return Nexus.GiveFine(Nexus.GetPlayer(source), amount, reason, 'export') end)
exports('jail', function(source, minutes, reason) return TriggerEvent('nx_police:jail', 0, source, minutes, reason) end)
exports('isJailed', function(charId) return jailed[charId] ~= nil end)
exports('isCuffed', function(charId) return cuffed[charId] ~= nil end)
exports('dispatch', function(coords, message, code) TriggerEvent('nx_police:dispatch', coords, message, code) end)
