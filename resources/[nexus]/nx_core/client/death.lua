--[[
    Nexus Framework :: client/death.lua
    Downed state, EMS revival and the respawn timer.

    Flow
    ----
    1. The ped's health hits zero -> we put the player into the "downed" state:
       the body stays in the world (ragdolled, invincible, no firing) so EMS can
       reach them, instead of the GTA wasted screen.
    2. nx_ems (or /revive) calls back into the core -> the server fires
       nexus:client:respawn, we patch the ped up and hand control back.
    3. If nobody arrives within Config.Death.respawnTime the server respawns the
       player at the hospital and the fee is taken from their bank.
]]

Nexus = Nexus or {}
local Client = Nexus.Client

local state = {
    downed = false,
    since = 0,
    respawnAt = 0,
    cause = 'unknown',
    killer = nil,
}

--- Public read-only accessor used by nx_hud / nx_ems to draw the timer.
function Nexus.Client.getDownedState()
    return state
end

function Nexus.Client.isDowned()
    return state.downed
end

local function disableDownedControls()
    local controls = { 24, 25, 22, 23, 44, 37, 47, 58, 140, 141, 142, 143, 75, 68, 69, 70, 91, 92, 73 }
    for _, control in ipairs(controls) do
        DisableControlAction(0, control, true)
    end
    DisablePlayerFiring(PlayerId(), true)
end

local function enterDowned(cause, killer)
    if state.downed then return end

    state.downed = true
    state.since = GetGameTimer()
    state.cause = cause or 'unknown'
    state.killer = killer

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    TriggerServerEvent('nexus:server:death', cause)

    -- Keep the body in the world instead of letting GTA respawn us.
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
    SetEntityHealth(ped, 100)
    SetPedToRagdoll(ped, 30000, 30000, 0, true, true, false)
    SetPlayerInvincible(PlayerId(), true)

    if Config.Death.blackoutOnDeath then
        TriggerScreenblurFadeIn(500)
    end

    -- free the hands (weapons are dropped by the inventory resource)
    RemoveAllPedWeapons(ped, true)

    Nexus.Notify('You are down. EMS has been alerted.', 'ems', 10000, 'Incapacitated')
    TriggerEvent('nexus:client:downed', cause)
    Client.emit('downed', cause)

    -- let every ambulance on duty know where we are
    TriggerServerEvent('nexus:server:downedAlert', coords)

    if Config.Death.respawnTime > 0 then
        state.respawnAt = GetGameTimer() + (Config.Death.respawnTime * 1000)
    end

    CreateThread(function()
        while state.downed do
            Citizen.Wait(0)
            disableDownedControls()
        end
    end)
end

local function exitDowned(health, armour)
    if not state.downed then return end
    state.downed = false
    state.respawnAt = 0

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    SetPlayerInvincible(PlayerId(), false)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
    ClearPedTasksImmediately(ped)
    ClearPedBloodDamage(ped)
    SetEntityHealth(ped, math.floor(health or Config.Death.reviveHealth))
    SetPedArmour(ped, math.floor(armour or Config.Death.reviveArmour))
    if Config.Death.blackoutOnDeath then
        TriggerScreenblurFadeOut(500)
    end

    Nexus.Notify('You have been revived.', 'success', 6000, 'Medical')
    TriggerEvent('nexus:client:revived')
    Client.emit('revived')
end

--- Death detection -----------------------------------------------------------
CreateThread(function()
    while true do
        Citizen.Wait(250)

        if Client.loaded and Client.spawned and not state.downed then
            local ped = PlayerPedId()
            if DoesEntityExist(ped) then
                local dead = IsEntityDead(ped) or IsPedFatallyInjured(ped) or GetEntityHealth(ped) <= 0
                if dead then
                    -- who did it? remember the closest player for the kill feed
                    enterDowned('unknown')
                end
            end
        end
    end
end)

--- Auto respawn after the timer runs out -------------------------------------
CreateThread(function()
    while true do
        Citizen.Wait(1000)
        if state.downed and state.respawnAt > 0 and GetGameTimer() >= state.respawnAt then
            state.respawnAt = 0
            if state.downed then
                Nexus.Notify('You were taken to Pillbox Hill.', 'info', 6000, 'Hospital')
                TriggerServerEvent('nexus:server:respawnRequest')
            end
        end
    end
end)

--- Server events -------------------------------------------------------------
RegisterNetEvent(Nexus.Events.RESPAWN, function()
    exitDowned()
end)

RegisterNetEvent(Nexus.Events.DEATH, function(cause, killer)
    enterDowned(cause, killer)
end)

--- Public helpers -------------------------------------------------------------
function Nexus.Client.forceDown(cause)
    enterDowned(cause or 'forced')
end

function Nexus.Client.revive(local_only)
    if local_only then
        exitDowned()
    end
end

--- /respawn — pay the fee and skip the wait.
RegisterCommand('respawn', function()
    if not state.downed then
        Nexus.Notify('You are not down.', 'error')
        return
    end
    Nexus.Confirm({
        title = 'Check in to hospital',
        message = ('Respawn now for %s?'):format(Nexus.Utils.formatMoney(Config.Death.manualRespawnCost)),
        confirmLabel = 'Respawn',
    }, function(confirmed)
        if confirmed then
            TriggerServerEvent('nexus:server:respawnRequest')
        end
    end)
end, false)

RegisterCommand('suicide', function()
    if not Config.Death.allowSuicideCmd then return end
    Nexus.Confirm({
        title = 'Give up',
        message = 'This will kill your character.',
        confirmLabel = 'Give up',
        danger = true,
    }, function(confirmed)
        if confirmed and not state.downed then
            local ped = PlayerPedId()
            SetEntityHealth(ped, 0)
        end
    end)
end, false)
