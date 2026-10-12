--[[
    Nexus Framework :: nx_hud
    Reads everything it needs from nx_core's client state and pushes a compact
    payload to its NUI at a fixed rate. Nothing here talks to the server.

    Other resources can push extra HUD data with:
        TriggerEvent('nexus:client:hudData', { seatbelt = true })
    which gets merged into the payload (and cleared when set to nil).
]]

local Nexus = Nexus
local Client = Nexus.Client

local extras = {}          -- merged into every payload
local lastPayload = {}
local voiceLevel = 0

-- ===========================================================================
--  NATIVE HUD CLEANUP
-- ===========================================================================

local function configureMinimap()
    if not HudConfig.minimap then return end

    DisplayRadar(true)
    SetRadarZoom(1000)

    if HudConfig.minimap.square then
        -- square map with no health/armour arcs: we draw those ourselves
        RequestStreamedTextureDict('squaremap', false)
        local timeout = GetGameTimer() + 2000
        while not HasStreamedTextureDictLoaded('squaremap') and GetGameTimer() < timeout do
            Citizen.Wait(10)
        end
        SetMinimapClipType(0)
        AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', 'squaremap', 'radarmasksm')
        AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', 'squaremap', 'radarmasksm')
    end

    local scale = HudConfig.minimap.scale or 0.9
    SetMinimapComponentPosition('minimap', 'L', 'B', HudConfig.minimap.x or 0.0, HudConfig.minimap.y or 0.0, 0.152 * scale, 0.242 * scale)
    SetMinimapComponentPosition('minimap_mask', 'L', 'B', 0.084, 0.108, 0.118 * scale, 0.236 * scale)
    SetMinimapComponentPosition('minimap_blur', 'L', 'B', 0.012, 0.019, 0.236 * scale, 0.300 * scale)

    -- park the native health/armour rings off-screen
    SetMinimapComponentPosition('health', 'L', 'B', 0.0, -100.0, 0.0, 0.0)
    SetMinimapComponentPosition('armour', 'L', 'B', 0.0, -100.0, 0.0, 0.0)
end

CreateThread(function()
    configureMinimap()

    while true do
        Citizen.Wait(0)
        if HudConfig.enabled then
            for _, component in ipairs(HudConfig.hideNative or {}) do
                HideHudComponentThisFrame(component)
            end
        end
    end
end)

-- ===========================================================================
--  DATA GATHERING
-- ===========================================================================

local function unitFor(speedMs)
    if HudConfig.speedUnit == 'kph' then
        return math.floor(speedMs * 3.6)
    end
    return math.floor(speedMs * 2.23694)
end

local function vehicleData()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return nil end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or not DoesEntityExist(vehicle) then return nil end

    local speed = unitFor(GetEntitySpeed(vehicle))
    local fuel = GetVehicleFuelLevel(vehicle)

    -- prefer the value nx_vehicles keeps in the statebag (it is the source of truth)
    local stateFuel = Entity(vehicle).state.nx_fuel
    if stateFuel ~= nil then fuel = stateFuel end

    local rpm = GetVehicleCurrentRpm(vehicle)
    local gear = GetVehicleCurrentGear(vehicle)
    local engineHealth = GetVehicleEngineHealth(vehicle)
    local bodyHealth = GetVehicleBodyHealth(vehicle)
    local class = GetVehicleClass(vehicle)

    return {
        speed = speed,
        unit = HudConfig.speedUnit == 'kph' and 'km/h' or 'mph',
        fuel = math.floor(fuel + 0.5),
        rpm = math.floor(rpm * 100),
        gear = gear,
        engine = math.floor(math.max(0, engineHealth / 10)),
        body = math.floor(math.max(0, bodyHealth / 10)),
        class = class,
        plate = GetVehicleNumberPlateText(vehicle):gsub('%s+', ''),
        model = GetEntityModel(vehicle),
        seatbelt = extras.seatbelt == true,
        cruise = extras.cruise == true,
        locked = extras.locked == true,
    }
end

local function ammoData()
    local ped = PlayerPedId()
    if not IsPedArmed(ped, 4 | 2) then return nil end

    local _, weapon = GetCurrentPedWeapon(ped, true)
    if weapon == 0 or weapon == GetHashKey('WEAPON_UNARMED') then return nil end

    local ammo = GetAmmoInPedWeapon(ped, weapon)
    local clip = GetAmmoInClip(ped, weapon)
    return { weapon = weapon, ammo = ammo, clip = clip }
end

local function voiceData()
    if not HudConfig.elements.voice then return nil end

    local talking = NetworkIsPlayerTalking(PlayerId()) or (MumbleIsPlayerTalking and MumbleIsPlayerTalking(PlayerId()))
    local level = extras.voiceLevel or (talking and 3 or 0)

    -- pma-voice exposes its radio state through the player statebag
    local radioChannel = LocalPlayer.state.radioChannel or LocalPlayer.state.nx_radio
    return {
        talking = talking == true,
        level = math.floor(level or 0),
        radio = radioChannel,
        range = extras.voiceRange,
    }
end

--- Street name via the native street-name lookup.
local function streetName()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    local crossing = crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash) or nil
    local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
    return street, crossing, zone
end

local function buildPayload()
    local ped = PlayerPedId()
    local street, crossing, zone = streetName()

    local payload = {
        visible = Client.isLoaded() and Client.spawned and not IsPauseMenuActive(),
        account = {
            name = Client.getName(),
            id = Client.getStateId(),
        },
        money = {
            cash = Client.getMoney('cash'),
            bank = Client.getMoney('bank'),
            black = Client.getMoney('black'),
        },
        job = {
            label = Client.getJob().label,
            grade = Client.getJob().gradeName,
            onDuty = Client.isOnDuty(),
            gang = Client.getGang().label,
            callsign = Client.data and Client.data.callsign,
        },
        vitals = {
            health = math.floor(GetEntityHealth(ped) / 2),   -- to 0-100 for the UI
            armour = math.floor(GetPedArmour(ped)),
            hunger = math.floor(Client.getVitals().hunger or 100),
            thirst = math.floor(Client.getVitals().thirst or 100),
            stress = math.floor(Client.getVitals().stress or 0),
        },
        downed = Client.isDowned(),
        vehicle = HudConfig.elements.vehicle and vehicleData() or nil,
        ammo = HudConfig.elements.ammo and ammoData() or nil,
        voice = voiceData(),
        location = { street = street, crossing = crossing, zone = zone },
        time = { hours = GetClockHours(), minutes = GetClockMinutes() },
        players = extras.players,
        serverName = extras.serverName,
        talkingLevel = voiceLevel,
    }

    for key, value in pairs(extras) do
        if payload[key] == nil then payload[key] = value end
    end

    return payload
end

-- ===========================================================================
--  PUSH LOOP
-- ===========================================================================

CreateThread(function()
    while true do
        Citizen.Wait(HudConfig.updateInterval)
        if HudConfig.enabled and Client.isLoaded() then
            local payload = buildPayload()
            -- town down obvious no-ops so we are not sending 10 messages a second
            -- with identical data
            local changed = false
            for key, value in pairs(payload) do
                if value ~= lastPayload[key] then changed = true break end
            end
            if changed or payload.vehicle then
                lastPayload = payload
                SendNUIMessage({ action = 'update', data = payload })
            end
        elseif lastPayload.visible then
            lastPayload = { visible = false }
            SendNUIMessage({ action = 'update', data = lastPayload })
        end
    end
end)

-- ===========================================================================
--  EXTERNAL EVENTS
-- ===========================================================================

--- Merge extra fields into the HUD payload (nx_vehicles uses this for seatbelt,
--- cruise control and the lock state).
RegisterNetEvent('nexus:client:hudData', function(data)
    if type(data) ~= 'table' then return end
    for key, value in pairs(data) do
        extras[key] = value
    end
end)

RegisterNetEvent('nexus:client:voiceLevel', function(level)
    voiceLevel = tonumber(level) or 0
end)

--- Hide the HUD entirely (cinematic mode, cutscenes, admin spectate).
RegisterNetEvent('nexus:client:hudVisible', function(state)
    HudConfig.enabled = state ~= false
    SendNUIMessage({ action = 'toggle', data = { visible = HudConfig.enabled } })
end)

exports('setHudVisible', function(state)
    HudConfig.enabled = state ~= false
    SendNUIMessage({ action = 'toggle', data = { visible = HudConfig.enabled } })
end)

exports('setHudData', function(key, value)
    if type(key) ~= 'string' then return end
    extras[key] = value
end)
