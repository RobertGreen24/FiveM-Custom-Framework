--[[
    Nexus Framework :: client/util.lua
    Small client-side helpers shared by every Nexus resource: blips, waypoints,
    nearby player queries, world interaction checks.
]]

Nexus = Nexus or {}
local Client = Nexus.Client

local activeBlips = {}
local activeWaypoint = nil

--- Blips ---------------------------------------------------------------------

--- Creates a blip and remembers it so it can be cleaned up by name.
function Client.addBlip(name, coords, sprite, colour, scale, label, shortRange)
    if not Config.Blips.enabled then return nil end
    if activeBlips[name] then
        RemoveBlip(activeBlips[name])
    end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite or 1)
    SetBlipColour(blip, colour or 0)
    SetBlipScale(blip, scale or 0.8)
    SetBlipAsShortRange(blip, shortRange ~= false)
    if label then
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(label)
        EndTextCommandSetBlipName(blip)
    end
    activeBlips[name] = blip
    return blip
end

function Client.removeBlip(name)
    if activeBlips[name] then
        RemoveBlip(activeBlips[name])
        activeBlips[name] = nil
    end
end

function Client.clearBlips()
    for name in pairs(activeBlips) do
        Client.removeBlip(name)
    end
end

--- Waypoints ------------------------------------------------------------------

function Client.setWaypoint(coords, blipType)
    Client.deleteWaypoint()
    if type(coords) == 'table' and not coords.x then
        coords = vector3(coords[1], coords[2], coords[3])
    end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, blipType or 4)
    SetBlipColour(blip, 5)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, 5)
    SetBlipScale(blip, 0.9)
    activeWaypoint = { blip = blip, coords = coords }

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Destination')
    EndTextCommandSetBlipName(blip)
    return blip
end

function Client.deleteWaypoint()
    if activeWaypoint then
        RemoveBlip(activeWaypoint.blip)
        activeWaypoint = nil
    end
end

function Client.getWaypoint()
    if not activeWaypoint then return nil end
    return activeWaypoint.coords
end

--- Players --------------------------------------------------------------------

--- Nearby players with their server ids and statebag data (name, job, health).
--- Used by EMS/police target pickers and the phone's nearby list.
function Client.getNearbyPlayers(radius)
    radius = radius or 10.0
    local out = {}
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)

    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= myPed and DoesEntityExist(ped) then
            local coords = GetEntityCoords(ped)
            local distance = #(coords - myCoords)
            if distance <= radius then
                local serverId = GetPlayerServerId(player)
                out[#out + 1] = {
                    source = serverId,
                    playerId = player,
                    ped = ped,
                    name = GetPlayerName(player),
                    distance = distance,
                    coords = coords,
                    isDead = IsEntityDead(ped) or IsPedFatallyInjured(ped),
                    health = GetEntityHealth(ped),
                    armour = GetPedArmour(ped),
                    -- statebag values set by nx_core on the server
                    charName = Player(serverId).state.nx_name,
                    stateId = Player(serverId).state.nx_state_id,
                    job = Player(serverId).state.nx_job,
                    jobLabel = Player(serverId).state.nx_job_label,
                    duty = Player(serverId).state.nx_duty,
                    gang = Player(serverId).state.nx_gang_label,
                    isAdmin = Player(serverId).state.nx_admin,
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.distance < b.distance end)
    return out
end

--- Closest player inside `radius` (nil when nobody is close).
function Client.getClosestPlayer(radius)
    local nearby = Client.getNearbyPlayers(radius or 3.0)
    return nearby[1]
end

--- Every player holding a given job, online, from the server's perspective.
--- Populated lazily by nx_core: the server pushes this on job/duty changes.
Client.dutyPlayers = {}

function Client.getDutyPlayers()
    return Client.dutyPlayers
end

RegisterNetEvent('nexus:client:dutyRoster', function(list)
    Client.dutyPlayers = list or {}
    Client.emit('dutyRoster', Client.dutyPlayers)
end)

--- Ped / world helpers --------------------------------------------------------

function Client.isInVehicle()
    return IsPedInAnyVehicle(PlayerPedId(), false)
end

function Client.getVehicle()
    return GetVehiclePedIsIn(PlayerPedId(), false)
end

function Client.hasWeaponOut()
    return IsPedArmed(PlayerPedId(), 4)
end

--- True when a vehicle seat is free for the player to enter.
function Client.vehicleHasFreeSeat(vehicle)
    local maxSeats = GetVehicleMaxNumberOfPassengers(vehicle)
    local occupied = 0
    for seat = 0, maxSeats - 1 do
        if not IsVehicleSeatFree(vehicle, seat) then occupied = occupied + 1 end
    end
    return occupied < maxSeats
end

--- Networked entity lookup (police MDT, mechanic towing, evidence).
function Client.getEntityFromNetId(netId)
    return NetworkGetEntityFromNetworkId(netId)
end

function Client.getNetIdFromEntity(entity)
    return NetworkGetNetworkIdFromEntity(entity)
end

--- Simple sphere check used by every interaction script.
function Client.isNear(coords, radius)
    return #(GetEntityCoords(PlayerPedId()) - vector3(coords.x, coords.y, coords.z)) <= (radius or 2.0)
end

--- Interaction prompt: shows text UI while the player is inside a marker and
--- calls `cb` when they press E. Returns nothing; the caller's thread owns it.
---@param coords vector3
---@param radius number
---@param label string
---@param cb function
function Client.interact(coords, radius, label, cb)
    Citizen.CreateThread(function()
        local wasInside = false
        while true do
            local sleep = 750
            if Client.isLoaded() then
                local inside = Client.isNear(coords, radius)
                if inside ~= wasInside then
                    wasInside = inside
                    Nexus.TextUI(inside, 'E', label)
                end
                if inside then
                    sleep = 0
                    if IsControlJustPressed(0, Config.Interaction.key) then
                        cb()
                    end
                end
            end
            Citizen.Wait(sleep)
        end
    end)
end
