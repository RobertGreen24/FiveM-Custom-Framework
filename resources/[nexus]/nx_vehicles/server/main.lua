--[[
    Nexus Framework :: nx_vehicles (server)
    Ownership, keys, and persistence of the vehicles currently out in the world.
]]

Nexus = Nexus or {}

local Vehicles = {}
Nexus.Vehicles = Vehicles

--- plate -> { netId, model, owner, keys = { [charId] = true }, fuel, engineHealth,
---             bodyHealth, dirtySince, spawnedAt }
local spawned = {}

local function normalisePlate(plate)
    plate = tostring(plate or ''):upper():gsub('[^A-Z0-9]', '')
    return plate:sub(1, 8)
end

local function generatePlate()
    local alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    local digits = '0123456789'
    for _ = 1, 40 do
        local plate = ''
        for _ = 1, 3 do
            local index = math.random(1, #alphabet)
            plate = plate .. alphabet:sub(index, index)
        end
        for _ = 1, 3 do
            local index = math.random(1, #digits)
            plate = plate .. digits:sub(index, index)
        end
        if not Nexus.DB.single('SELECT plate FROM nx_vehicles WHERE plate = ?', { plate }) then
            return plate
        end
    end
    return 'NX' .. tostring(os.time()):sub(-5)
end

--- Keys ---------------------------------------------------------------------

--- All char ids that may drive this plate (owner + spare keys + gang).
local function keyHolders(row)
    local holders = {}
    if row.char_id then holders[tostring(row.char_id)] = true end

    local keys = Nexus.Utils.decodeJson(row.keys or '[]') or {}
    for _, charId in ipairs(keys) do holders[tostring(charId)] = true end

    -- gang-shared vehicles
    if row.gang and row.gang ~= '' and row.gang ~= 'none' then
        for _, player in ipairs(Nexus.GetPlayers()) do
            if player.gang.name == row.gang then holders[tostring(player.charId)] = true end
        end
    end
    return holders
end

function Vehicles.hasKeys(source, plate)
    local player = Nexus.GetPlayer(source)
    if not player or not player.charId then return false end

    plate = normalisePlate(plate)
    local live = spawned[plate]
    if live and live.keys[tostring(player.charId)] then return true end

    local row = Nexus.DB.single('SELECT char_id, `keys`, gang FROM nx_vehicles WHERE plate = ?', { plate })
    if not row then return false end

    return keyHolders(row)[tostring(player.charId)] == true
end

function Vehicles.giveKeys(source, plate, targetSource)
    local player = Nexus.GetPlayer(source)
    local target = Nexus.GetPlayer(tonumber(targetSource))
    if not player or not target or not player.loaded or not target.loaded then return false, 'offline' end

    plate = normalisePlate(plate)
    if not Vehicles.hasKeys(source, plate) then return false, 'no keys' end
    if #(player:getCoords() - target:getCoords()) > VehicleConfig.keys.shareDistance then
        return false, 'too far'
    end

    local row = Nexus.DB.single('SELECT id, `keys` FROM nx_vehicles WHERE plate = ?', { plate })
    if not row then return false, 'unknown plate' end

    local keys = Nexus.Utils.decodeJson(row.keys or '[]') or {}
    for _, charId in ipairs(keys) do
        if tostring(charId) == tostring(target.charId) then return false, 'already has keys' end
    end

    keys[#keys + 1] = target.charId
    Nexus.DB.update('UPDATE nx_vehicles SET `keys` = ? WHERE plate = ?', { Nexus.Utils.encodeJson(keys), plate })

    local live = spawned[plate]
    if live then live.keys[tostring(target.charId)] = true end

    TriggerClientEvent('nexus:client:vehicleKeys', target.source, { plate = plate, add = true })
    TriggerClientEvent('nexus:client:vehicleKeys', source, { plate = plate, add = true })

    Nexus.Log.action('vehicle_keys_given', {
        actor = player:getName(), target = target:getName(), details = plate,
    })
    return true
end

--- Spawning ------------------------------------------------------------------

--- Registers a vehicle that just came out of a garage or dealership.
---@return string|nil plate
function Vehicles.spawn(source, model, coords, opts)
    opts = opts or {}
    local player = Nexus.GetPlayer(source)
    local plate = normalisePlate(opts.plate)
    if plate == '' then plate = generatePlate() end
    local row = {
        plate = plate,
        model = model,
        owner = player and player.charId or opts.owner,
        keys = {},
        fuel = opts.fuel or 100.0,
        engineHealth = opts.engineHealth or 1000.0,
        bodyHealth = opts.bodyHealth or 1000.0,
        spawnedAt = os.time(),
    }
    if player and player.charId then row.keys[tostring(player.charId)] = true end
    if opts.keys then
        for charId in pairs(opts.keys) do row.keys[tostring(charId)] = true end
    end

    spawned[plate] = row
    return plate, row
end

function Vehicles.attach(plate, netId, model, opts)
    plate = normalisePlate(plate)
    local row = spawned[plate]
    if not row then
        row = { plate = plate, keys = {}, fuel = 100.0, spawnedAt = os.time() }
        spawned[plate] = row
    end
    row.netId = netId
    row.model = model or row.model
    if opts then
        row.owner = opts.owner or row.owner
        row.fuel = opts.fuel or row.fuel
        row.engineHealth = opts.engineHealth or row.engineHealth
        row.bodyHealth = opts.bodyHealth or row.bodyHealth
    end
    return row
end

function Vehicles.get(plate)
    return spawned[normalisePlate(plate)]
end

--- Removes a plate from the live registry (the DB row is untouched).
--- Used by nx_vehicleshop when a test drive ends or a vehicle is sold.
function Vehicles.detach(plate)
    spawned[normalisePlate(plate)] = nil
    return true
end

function Vehicles.getEntity(plate)
    local row = spawned[normalisePlate(plate)]
    if not row or not row.netId then return nil end
    local entity = NetworkGetEntityFromNetworkId(row.netId)
    return entity ~= 0 and entity or nil
end

--- Persists fuel/health for a plate that has a database row.
function Vehicles.saveState(plate, state)
    plate = normalisePlate(plate)
    local live = spawned[plate]
    if live and state then
        live.fuel = state.fuel or live.fuel
        live.engineHealth = state.engine or live.engineHealth
        live.bodyHealth = state.body or live.bodyHealth
    end

    local row = Nexus.DB.single('SELECT id, mileage FROM nx_vehicles WHERE plate = ?', { plate })
    if not row then return false end

    Nexus.DB.update([[
        UPDATE nx_vehicles SET fuel = ?, engine_health = ?, body_health = ?, mileage = ?, updated_at = NOW()
        WHERE plate = ?
    ]], {
        math.floor((state and state.fuel or live and live.fuel or 100.0) * 10) / 10,
        math.floor(state and state.engine or live and live.engineHealth or 1000.0),
        math.floor(state and state.body or live and live.bodyHealth or 1000.0),
        math.floor((state and state.mileage) or (row.mileage or 0)),
        plate,
    })
    return true
end

--- Creates a brand new owned vehicle and returns its plate.
function Vehicles.register(model, charId, opts)
    opts = opts or {}
    model = tostring(model or ''):lower()
    if model == '' then return nil, 'no model' end
    if VehicleConfig.restrictedModels[model] then return nil, 'restricted' end

    local count = tonumber(Nexus.DB.scalar('SELECT COUNT(*) FROM nx_vehicles WHERE char_id = ?', { charId })) or 0
    if count >= VehicleConfig.ownership.maxPerCharacter and not opts.ignoreLimit then
        return nil, 'limit'
    end

    local plate = normalisePlate(opts.plate)
    if plate == '' then plate = generatePlate() end
    if Nexus.DB.single('SELECT id FROM nx_vehicles WHERE plate = ?', { plate }) then
        plate = generatePlate()
    end

    Nexus.DB.insert([[
        INSERT INTO nx_vehicles (plate, char_id, model, label, fuel, engine_health, body_health, garage, state, stored, vtype)
        VALUES (?, ?, ?, ?, 100.0, 1000.0, 1000.0, ?, 1, 1, ?)
    ]], {
        plate, charId, model, opts.label or model,
        opts.garage or 'legion',
        opts.vtype or 'automobile',
    })

    TriggerClientEvent('nexus:client:vehicleKeys', Nexus.GetPlayerByCharId(charId) and
        Nexus.GetPlayerByCharId(charId).source or -1, { plate = plate, add = true })

    return plate
end

function Vehicles.delete(plate)
    plate = normalisePlate(plate)
    spawned[plate] = nil
    Nexus.DB.update('DELETE FROM nx_vehicles WHERE plate = ?', { plate })
end

function Vehicles.listFor(charId)
    return Nexus.DB.query('SELECT * FROM nx_vehicles WHERE char_id = ? ORDER BY state, label', { charId })
end

-- ===========================================================================
--  LOCK / UNLOCK
-- ===========================================================================

RegisterNetEvent('nx_vehicles:setLock', function(plate, locked)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    plate = normalisePlate(plate)
    if not Vehicles.hasKeys(source, plate) then
        player:notify('You do not have the keys to that vehicle.', 'error')
        return
    end

    local live = spawned[plate]
    if live then live.locked = locked == true end

    -- tell everyone nearby so the lock sound and lights are consistent
    TriggerClientEvent('nexus:client:vehicleLockChanged', -1, plate, locked == true, source)
end)

RegisterNetEvent('nx_vehicles:giveKeys', function(targetSource, plate)
    local source = source
    local ok, err = Vehicles.giveKeys(source, plate, targetSource)
    local player = Nexus.GetPlayer(source)
    if not player then return end

    if ok then
        player:notify('Spare keys handed over.', 'success')
    else
        player:notify(('Could not hand over the keys (%s).'):format(err or 'error'), 'error')
    end
end)

RegisterNetEvent('nx_vehicles:requestKeys', function()
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.charId then return end

    local rows = Nexus.DB.query('SELECT plate, `keys`, gang, char_id FROM nx_vehicles WHERE char_id = ? OR gang = ?',
        { player.charId, player.gang.name })

    for _, row in ipairs(rows or {}) do
        if keyHolders(row)[tostring(player.charId)] then
            TriggerClientEvent('nexus:client:vehicleKeys', source, { plate = row.plate, add = true })
        end
    end
end)

-- ===========================================================================
--  STATE SYNC
-- ===========================================================================

RegisterNetEvent('nx_vehicles:updateState', function(netId, state)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded or type(state) ~= 'table' then return end

    local entity = NetworkGetEntityFromNetworkId(tonumber(netId) or -1)
    if not entity or entity == 0 then return end

    local plate = normalisePlate(Entity(entity).state.nx_plate)
    if plate == '' then return end

    if not Vehicles.hasKeys(source, plate) then return end

    local live = spawned[plate]
    if live then
        live.fuel = tonumber(state.fuel) or live.fuel
        live.engineHealth = tonumber(state.engine) or live.engineHealth
        live.bodyHealth = tonumber(state.body) or live.bodyHealth
        live.mileage = tonumber(state.mileage) or live.mileage
        live.occupied = state.occupied == true
        live.instance = source
    end

    Entity(entity).state:set('nx_fuel', tonumber(state.fuel) or (live and live.fuel), true)
end)

--- Called by nx_garages when a vehicle is stored.
RegisterNetEvent('nx_vehicles:storeState', function(plate, state)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    plate = normalisePlate(plate)
    if Vehicles.hasKeys(source, plate) then
        Vehicles.saveState(plate, state)
    end
end)

--- Vehicle persistence thread: writes every vehicle with an owner row.
CreateThread(function()
    if not VehicleConfig.damage.enabled then return end
    while true do
        Citizen.Wait(VehicleConfig.damage.saveFrequency * 1000)

        for plate, live in pairs(spawned) do
            -- state comes from the driving client (see nx_vehicles:updateState)
            Vehicles.saveState(plate, {
                fuel = live.fuel,
                engine = live.engineHealth,
                body = live.bodyHealth,
                mileage = live.mileage,
            })
        end
    end
end)

--- Cleans up empty abandoned vehicles.
CreateThread(function()
    while true do
        Citizen.Wait(60 * 1000)
        for plate, live in pairs(spawned) do
            local empty = live.occupied ~= true
            if empty and (os.time() - (live.spawnedAt or os.time())) > VehicleConfig.cleanup.emptyAfter then
                Vehicles.saveState(plate, {
                    fuel = live.fuel, engine = live.engineHealth,
                    body = live.bodyHealth, mileage = live.mileage,
                })

                local entity = live.netId and NetworkGetEntityFromNetworkId(live.netId) or 0
                if entity and entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
                spawned[plate] = nil
            end
        end
    end
end)

-- ===========================================================================
--  OWNERSHIP / PLATES
-- ===========================================================================

RegisterCommand(VehicleConfig.ownership.transferCommand, function(source, args)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local targetSource = tonumber(args[1])
    local plate = normalisePlate(args[2])
    if not targetSource or plate == '' then
        player:notify('Usage: /givecar [id] [plate]', 'error')
        return
    end

    local target = Nexus.GetPlayer(targetSource)
    if not target or not target.loaded then
        player:notify('That player is not online.', 'error')
        return
    end

    local row = Nexus.DB.single('SELECT * FROM nx_vehicles WHERE plate = ? AND char_id = ?', { plate, player.charId })
    if not row then
        player:notify('You do not own that vehicle.', 'error')
        return
    end

    local price = math.floor((row.purchase_price or row.price or 0) * VehicleConfig.ownership.transferFeeRatio)
    Nexus.DB.update('UPDATE nx_vehicles SET char_id = ? WHERE plate = ?', { target.charId, plate })

    player:notify(('%s is now owned by %s.'):format(plate, target:getName()), 'success')
    target:notify(('%s transferred you a vehicle (%s).'):format(player:getName(), plate), 'success', 8000, 'Vehicle')
    TriggerClientEvent('nexus:client:vehicleKeys', target.source, { plate = plate, add = true })

    Nexus.Log.action('vehicle_transfer', {
        actor = player:getName(), target = target:getName(), details = plate,
    })
end, false)

RegisterCommand(VehicleConfig.plate.changeCommand, function(source, args)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local newPlate = table.concat(args, ' '):upper():gsub('[^A-Z0-9]', '')
    if #newPlate < 3 or #newPlate > 8 then
        player:notify('Plates must be 3-8 characters.', 'error')
        return
    end

    -- find the vehicle the player is currently sitting in (the client keeps
    -- this state bag up to date)
    local ped = GetPlayerPed(source)
    local coords = ped and ped ~= 0 and GetEntityCoords(ped) or nil
    if not coords then return end

    local vehicle = nil
    for _, entity in ipairs(GetAllVehicles()) do
        local state = Entity(entity).state
        if (state.nx_driver == source or #(GetEntityCoords(entity) - coords) < 3.0) then
            local plate = normalisePlate(state.nx_plate)
            if plate ~= '' then
                vehicle = entity
                break
            end
        end
    end

    if not vehicle then
        player:notify('You must be in a vehicle you own.', 'error')
        return
    end

    local current = normalisePlate(Entity(vehicle).state.nx_plate)
    local row = Nexus.DB.single('SELECT id FROM nx_vehicles WHERE plate = ? AND char_id = ?', { current, player.charId })
    if not row then
        player:notify('You do not own this vehicle.', 'error')
        return
    end
    if Nexus.DB.single('SELECT id FROM nx_vehicles WHERE plate = ?', { newPlate }) then
        player:notify('That plate is already taken.', 'error')
        return
    end
    if not player:removeMoney('bank', VehicleConfig.plate.changePrice, 'private plate') then
        player:notify(('You need %s to change your plate.'):format(
            Nexus.Utils.formatMoney(VehicleConfig.plate.changePrice)), 'error')
        return
    end

    Nexus.DB.update('UPDATE nx_vehicles SET plate = ? WHERE id = ?', { newPlate, row.id })
    Entity(vehicle).state:set('nx_plate', newPlate, true)
    TriggerClientEvent('nx_vehicles:applyPlate', -1, vehicle, newPlate)

    local live = spawned[current]
    if live then
        spawned[current] = nil
        live.plate = newPlate
        spawned[newPlate] = live
    end

    player:notify(('Your plate is now %s.'):format(newPlate), 'success', 7000)
end, false)

-- ===========================================================================
--  EXPORTS
-- ===========================================================================

exports('hasKeys', function(source, plate) return Vehicles.hasKeys(source, plate) end)
exports('giveKeys', function(source, plate, target) return Vehicles.giveKeys(source, plate, target) end)
exports('getVehicle', function(plate) return Vehicles.get(plate) end)
exports('spawn', function(source, model, coords, opts) return Vehicles.spawn(source, model, coords, opts) end)
exports('register', function(model, charId, opts) return Vehicles.register(model, charId, opts) end)
exports('saveState', function(plate, state) return Vehicles.saveState(plate, state) end)
exports('listFor', function(charId) return Vehicles.listFor(charId) end)
exports('delete', function(plate) return Vehicles.delete(plate) end)

Nexus.SaveVehicleState = function(plate, state)
    local live = spawned[normalisePlate(plate)]
    if live and state then
        live.fuel = state.fuel or live.fuel
        live.engineHealth = state.engineHealth or live.engineHealth
        live.bodyHealth = state.bodyHealth or live.bodyHealth
        live.mileage = state.mileage or live.mileage
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for plate, live in pairs(spawned) do
        Vehicles.saveState(plate, {
            fuel = live.fuel, engine = live.engineHealth,
            body = live.bodyHealth, mileage = live.mileage,
        })
    end
end)

-- ===========================================================================
--  FUEL PURCHASES
-- ===========================================================================

--- The client finished pumping; charge them and tell the client to fill up.
RegisterNetEvent('nx_vehicles:payFuel', function(cost, litres)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    cost = math.max(0, math.floor(tonumber(cost) or 0))
    litres = math.max(0.0, tonumber(litres) or 0.0)
    if cost <= 0 or litres <= 0 then return end

    local paid = player:removeMoney('bank', cost, 'fuel')
    if not paid then
        paid = player:removeMoney('cash', cost, 'fuel')
    end
    if not paid then
        TriggerClientEvent('nx_vehicles:fuelFailed', source)
        return
    end

    local job = player.job.name
    if Nexus.Society and Nexus.Society.addMoney and Nexus.Society.get(job) then
        Nexus.Society.addMoney(job, cost, 'fuel sales')
    end

    TriggerClientEvent('nx_vehicles:fuelPaid', source, litres, cost)
end)

--- A player started a car they have no keys for.
RegisterNetEvent('nx_vehicles:stolen', function(netId)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local entity = NetworkGetEntityFromNetworkId(tonumber(netId) or -1)
    if not entity or entity == 0 then return end

    local plate = normalisePlate(Entity(entity).state.nx_plate)
    if plate == '' then return end

    Nexus.Log.action('vehicle_hotwire', {
        actor = player:getName(), target = plate, colour = 0xf59e0b,
    })

    -- let the department know if the owner wants it reported
    TriggerEvent('nx_police:dispatch', player:getCoords(),
        ('Stolen vehicle reported: %s'):format(plate), '10-31', 'normal')
end)

exports('payFuel', function(source, cost, litres) TriggerEvent('nx_vehicles:payFuel', source, cost, litres) end)
