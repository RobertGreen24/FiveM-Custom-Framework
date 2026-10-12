--[[
    Nexus Framework :: nx_garages (server)
    Storing, retrieving and impounding vehicles.
]]

Nexus = Nexus or {}

local function nearPoint(source, coords, radius)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return true end
    return #(GetEntityCoords(ped) - coords) <= (radius or GarageConfig.spawnRadius)
end

local function garageOf(name)
    return GarageFind(name)
end

--- Can this player use this garage at all?
local function canUse(player, garage)
    if not player or not player.loaded then return false, 'not loaded' end
    if player:can('nexus.admin') then return true end
    if garage.type == 'job' then
        if player.job.name ~= garage.job then return false, 'wrong job' end
        if (garage.minGrade or 0) > player.job.grade then return false, 'grade too low' end
        if not player:isOnDuty() and garage.dutyOnly then return false, 'off duty' end
    end
    return true
end

--- The vehicle rows this player may see in this garage.
local function garageContents(player, garage, impound)
    if garage.fleet and garage.type == 'job' then
        local fleet = {}
        for _, vehicle in ipairs(garage.fleetVehicles or {}) do
            fleet[#fleet + 1] = {
                plate = 'FLEET',
                model = vehicle.model,
                label = vehicle.label,
                vtype = 'automobile',
                state = 1,
                fuel = 100, engine_health = 1000, body_health = 1000, mileage = 0,
                fleet = true,
            }
        end
        return fleet
    end

    if impound then
        return Nexus.DB.query([[
            SELECT * FROM nx_vehicles WHERE char_id = ? AND state = 2 ORDER BY label
        ]], { player.charId })
    end

    local rows = Nexus.DB.query([[
        SELECT * FROM nx_vehicles WHERE char_id = ? AND garage = ? AND state <> 2 ORDER BY state, label
    ]], { player.charId, garage.name })

    return rows or {}
end

local function impoundFee(row)
    local hours = 1
    if row.updated_at then
        local stamp = Nexus.Utils.parseTimestamp and Nexus.Utils.parseTimestamp(row.updated_at) or nil
        if stamp then
            hours = math.max(1, math.floor((os.time() - stamp) / 3600))
        end
    end
    return math.min(GarageConfig.impoundFeeCap,
        GarageConfig.impoundFee + (GarageConfig.impoundRate * (hours - 1)))
end

-- ===========================================================================
--  OPEN
-- ===========================================================================

RegisterNetEvent('nx_garages:open', function(garageName)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local garage = garageOf(garageName)
    if not garage then return end

    local ok, err = canUse(player, garage)
    if not ok then
        player:notify(('You cannot use this garage (%s).'):format(err or 'denied'), 'error')
        return
    end
    if not nearPoint(source, garage.coords) then
        player:notify('You are too far from the garage.', 'error')
        return
    end

    local impound = garage.type == 'impound'
    local vehicles = garageContents(player, garage, impound)

    for _, row in ipairs(vehicles) do
        if impound then
            row.fee = impoundFee(row)
            row.impound_reason = row.impound_reason
        end
        row.mods = nil         -- keep the payload small
        row.colors = nil
        row.extras = nil
        row.keys = nil
    end

    TriggerClientEvent('nexus:client:garageData', source, {
        garage = {
            name = garage.name,
            label = garage.label,
            type = garage.type,
            impound = impound,
            fleet = garage.fleet == true,
            spawn = { garage.spawn.x, garage.spawn.y, garage.spawn.z, garage.spawn.w },
        },
        vehicles = vehicles,
        types = GarageConfig.types,
        money = { cash = player:getMoney('cash'), bank = player:getMoney('bank') },
        fee = GarageConfig.impoundFee,
    })
end)

-- ===========================================================================
--  RETRIEVE
-- ===========================================================================

RegisterNetEvent('nx_garages:retrieve', function(garageName, plate)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local garage = garageOf(garageName)
    if not garage then return end

    local ok = canUse(player, garage)
    if not ok then return end
    if not nearPoint(source, garage.coords) then
        player:notify('You are too far from the garage.', 'error')
        return
    end

    -- job fleets are not owned: spawn the model and skip the database
    if garage.fleet and garage.type == 'job' then
        local model
        for _, vehicle in ipairs(garage.fleetVehicles or {}) do
            if vehicle.model == plate or vehicle.label == plate then model = vehicle.model end
        end
        if not model then
            player:notify('That vehicle is not in the fleet.', 'error')
            return
        end

        TriggerClientEvent('nexus:client:garageSpawn', source, {
            garage = garage.name,
            fleet = true,
            model = model,
            plate = 'FLEET',
            vtype = 'automobile',
            fuel = 100.0,
            engineHealth = 1000.0,
            bodyHealth = 1000.0,
            spawn = { garage.spawn.x, garage.spawn.y, garage.spawn.z, garage.spawn.w },
            delay = GarageConfig.retrieveDelay,
        })
        return
    end

    local row = Nexus.DB.single('SELECT * FROM nx_vehicles WHERE plate = ? AND char_id = ?', { plate, player.charId })
    if not row then
        player:notify('You do not own that vehicle.', 'error')
        return
    end

    if row.state == 2 then
        -- impound release: pay the fee, get the car back
        if garage.type ~= 'impound' then
            player:notify('That vehicle is impounded.', 'error')
            return
        end

        local fee = impoundFee(row)
        if not player:removeMoney('bank', fee, 'impound release') then
            player:notify(('You need %s to release this vehicle.'):format(Nexus.Utils.formatMoney(fee)), 'error')
            return
        end

        if garage.job and Nexus.Society.get(garage.job) then
            Nexus.Society.addMoney(garage.job, fee, 'impound release')
        end

        Nexus.DB.update('UPDATE nx_vehicles SET state = 1, garage = ?, impound_reason = NULL WHERE plate = ?',
            { 'legion', plate })
        row.garage = 'legion'
        row.state = 1
        player:notify(('Released for %s.'):format(Nexus.Utils.formatMoney(fee)), 'money', 7000)
    else
        if row.state == 0 then
            player:notify('That vehicle is already out.', 'error')
            return
        end
        if row.garage ~= garage.name then
            player:notify('That vehicle is stored elsewhere.', 'error')
            return
        end
    end

    if not GarageAllowsType(garage, row.vtype or 'automobile') then
        player:notify('This garage cannot take that vehicle type.', 'error')
        return
    end

    Nexus.DB.update('UPDATE nx_vehicles SET state = 0, x = ?, y = ?, z = ?, heading = ? WHERE plate = ?', {
        garage.spawn.x, garage.spawn.y, garage.spawn.z, garage.spawn.w, plate,
    })

    local engineHealth = row.engine_health or 1000.0
    local bodyHealth = row.body_health or 1000.0
    if GarageConfig.repairOnRetrieve > 0 then
        engineHealth = engineHealth + ((1000.0 - engineHealth) * GarageConfig.repairOnRetrieve)
        bodyHealth = bodyHealth + ((1000.0 - bodyHealth) * GarageConfig.repairOnRetrieve)
    end

    TriggerClientEvent('nexus:client:garageSpawn', source, {
        garage = garage.name,
        plate = plate,
        model = row.model,
        vtype = row.vtype or 'automobile',
        fuel = GarageConfig.saveFuel and (row.fuel or 100.0) or 100.0,
        engineHealth = engineHealth,
        bodyHealth = bodyHealth,
        mileage = row.mileage or 0,
        mods = Nexus.Utils.decodeJson(row.mods or 'null'),
        colors = Nexus.Utils.decodeJson(row.colors or 'null'),
        extras = Nexus.Utils.decodeJson(row.extras or 'null'),
        neon = Nexus.Utils.decodeJson(row.neon or 'null'),
        tyres = Nexus.Utils.decodeJson(row.tyres or 'null'),
        spawn = { garage.spawn.x, garage.spawn.y, garage.spawn.z, garage.spawn.w },
        delay = GarageConfig.retrieveDelay,
        keys = GarageConfig.keysOnRetrieve,
    })

    Nexus.Log.action('vehicle_retrieved', {
        actor = player:getName(), target = plate, details = garage.label,
    })
end)

-- ===========================================================================
--  STORE
-- ===========================================================================

RegisterNetEvent('nx_garages:store', function(garageName, netId, snapshot)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local garage = garageOf(garageName)
    if not garage then return end

    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or -1)
    if not vehicle or vehicle == 0 then
        player:notify('Could not find that vehicle.', 'error')
        return
    end

    if #(GetEntityCoords(vehicle) - player:getCoords()) > 12.0 or not nearPoint(source, garage.coords, 14.0) then
        player:notify('Bring the vehicle to the garage first.', 'error')
        return
    end

    snapshot = type(snapshot) == 'table' and snapshot or {}
    local plate = tostring(snapshot.plate or ''):upper():gsub('[^A-Z0-9]', '')

    if garage.fleet and garage.type == 'job' then
        -- job vehicles simply vanish (and respawn damaged next time)
        DeleteEntity(vehicle)
        player:notify('Fleet vehicle returned.', 'info')
        return
    end

    local row = Nexus.DB.single('SELECT id FROM nx_vehicles WHERE plate = ? AND char_id = ?', { plate, player.charId })
    if not row then
        player:notify('You do not own that vehicle.', 'error')
        return
    end

    local vtype = snapshot.vtype or 'automobile'
    if not GarageAllowsType(garage, vtype) and not garage.fleet then
        -- allow storing anywhere, but note it goes to this garage
    end

    Nexus.DB.update([[
        UPDATE nx_vehicles SET state = 1, garage = ?, x = ?, y = ?, z = ?, heading = ?,
            fuel = ?, engine_health = ?, body_health = ?, mileage = ?,
            mods = ?, colors = ?, extras = ?, neon = ?, tyres = ?, vtype = ?
        WHERE plate = ?
    ]], {
        garage.name, garage.spawn.x, garage.spawn.y, garage.spawn.z, garage.spawn.w,
        tonumber(snapshot.fuel) or 100.0,
        tonumber(snapshot.engineHealth) or 1000.0,
        tonumber(snapshot.bodyHealth) or 1000.0,
        tonumber(snapshot.mileage) or 0.0,
        Nexus.Utils.encodeJson(snapshot.mods or {}),
        Nexus.Utils.encodeJson(snapshot.colors or {}),
        Nexus.Utils.encodeJson(snapshot.extras or {}),
        Nexus.Utils.encodeJson(snapshot.neon or {}),
        Nexus.Utils.encodeJson(snapshot.tyres or {}),
        vtype,
        plate,
    })

    DeleteEntity(vehicle)
    if Nexus.SaveVehicleState then Nexus.SaveVehicleState(plate, snapshot) end

    player:notify(('%s stored at %s.'):format(snapshot.label or plate, garage.label), 'success', 6000)

    Nexus.Log.action('vehicle_stored', {
        actor = player:getName(), target = plate, details = garage.label,
    })
end)

-- ===========================================================================
--  IMPOUND (called by police / mechanic / exports)
-- ===========================================================================

RegisterNetEvent('nx_garages:impound', function(plate, reason)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end
    if not player:can('nexus.admin') and player.job.name ~= 'police' and player.job.name ~= 'mechanic' then
        player:notify('You cannot impound vehicles.', 'error')
        return
    end

    local result = Nexus.Impound(plate, reason or 'Impounded')
    if result then
        player:notify(('%s impounded.'):format(plate), 'success')
    else
        player:notify('No such vehicle.', 'error')
    end
end)

--- Deletes or impounds a vehicle regardless of who is online.
function Nexus.Impound(plate, reason)
    plate = tostring(plate or ''):upper():gsub('[^A-Z0-9]', '')
    local row = Nexus.DB.single('SELECT id FROM nx_vehicles WHERE plate = ?', { plate })
    if not row then return false end

    Nexus.DB.update('UPDATE nx_vehicles SET state = 2, impound_reason = ?, updated_at = NOW() WHERE plate = ?',
        { tostring(reason or 'Impounded'):sub(1, 120), plate })

    -- if the car is out there driving around, remove it
    for _, candidate in ipairs(GetAllVehicles()) do
        if tostring(Entity(candidate).state.nx_plate or ''):gsub('[^A-Z0-9]', '') == plate then
            DeleteEntity(candidate)
        end
    end

    local owner = Nexus.DB.single('SELECT char_id FROM nx_vehicles WHERE plate = ?', { plate })
    if owner and owner.char_id then
        local target = Nexus.GetPlayerByCharId(owner.char_id)
        if target and target.loaded then
            target:notify(('Your vehicle %s was impounded (%s).'):format(plate, reason or 'no reason'), 'error', 9000, 'Impound')
        end
    end

    return true
end

--- Kept for nx_police: Nexus.ImpoundVehicle(plate, reason, garage)
function Nexus.ImpoundVehicle(plate, reason, garageName)
    return Nexus.Impound(plate, reason, garageName)
end

exports('impound', function(plate, reason) return Nexus.Impound(plate, reason) end)
exports('impoundVehicle', function(plate, reason) return Nexus.Impound(plate, reason) end)
exports('release', function(plate)
    return Nexus.DB.update('UPDATE nx_vehicles SET state = 1 WHERE plate = ?', { plate }) ~= nil
end)
exports('garages', function() return Garages end)
exports('impounds', function() return Impounds end)
exports('find', function(name) return GarageFind(name) end)
