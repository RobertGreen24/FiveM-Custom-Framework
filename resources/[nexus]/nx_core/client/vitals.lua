--[[
    Nexus Framework :: client/vitals.lua
    Hunger, thirst and stress simulation, plus the ped's real health/armour.

    The client owns the decay (it can see if you are sprinting), the server owns
    the authoritative numbers (it applies food, medicine and admin effects). The
    two are reconciled every 15 seconds and on every significant change.
]]

Nexus = Nexus or {}
local Client = Nexus.Client

local DECAY_TICK = 1000        -- ms
local SYNC_INTERVAL = 15000    -- ms

local warned = { hunger = 0, thirst = 0, stress = 0 }
local lastSync = 0
local lastSentValues = {}
local healthDrainAt = 0

--- Pull real health/armour off the ped. Health is 0-200 in GTA.
local function readPed()
    local ped = PlayerPedId()
    return {
        health = math.max(0, math.floor(GetEntityHealth(ped))),
        armour = math.max(0, math.floor(GetPedArmour(ped))),
    }
end

--- How hard is the player working right now?
local function activityMultiplier()
    local ped = PlayerPedId()
    if IsPedSwimming(ped) then return 2.2 end
    if IsPedSprinting(ped) or IsPedRunning(ped) then return 2.4 end
    if IsPedInAnyVehicle(ped, false) then return 0.35 end
    if IsPedClimbing(ped) or IsPedJumping(ped) then return 1.6 end
    return 1.0
end

--- Stress sources: gunfire nearby, high speed driving, fist fights.
local function stressFromEnvironment(seconds)
    local ped = PlayerPedId()
    local stress = 0

    if IsPedShooting(ped) then
        stress = stress + Config.Vitals.stressFromCombat * seconds
    end
    if IsPedInMeleeCombat(ped) then
        stress = stress + 2 * seconds
    end

    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        local speed = GetEntitySpeed(vehicle) * 3.6   -- km/h
        if speed > 110 then
            stress = stress + Config.Vitals.stressFromFastDriving * seconds * ((speed - 110) / 90)
        end
    end

    return stress
end

local function applyLowVitalEffects(hunger, thirst, stress)
    local ped = PlayerPedId()

    -- can't sprint when starving or dehydrated
    if hunger <= Config.Vitals.sprintDisabledAt or thirst <= Config.Vitals.sprintDisabledAt then
        DisableControlAction(0, 21, true)   -- sprint
        RestorePlayerStamina(PlayerId(), 1.0)
        if not warned.sprintNotified or GetGameTimer() - warned.sprintNotified > 60000 then
            warned.sprintNotified = GetGameTimer()
            Nexus.Notify('You are too weak to run.', 'warning', 5000, 'Exhausted')
        end
    end

    -- stress visuals
    if stress >= 70 then
        SetPedMotionBlur(ped, true)
        SetTimecycleModifier('spectator5')
        SetTimecycleModifierStrength((stress - 70) / 120)
    else
        SetPedMotionBlur(ped, false)
        ClearTimecycleModifier()
    end
end

local function warnLow(key, value, label)
    if value > Config.Vitals.warnAt then return end
    local now = GetGameTimer()
    if now - (warned[key] or 0) < 120000 then return end
    warned[key] = now
    Nexus.Notify(('%s is getting low.'):format(label), 'warning', 5000, 'Vitals')
end

CreateThread(function()
    while true do
        Citizen.Wait(DECAY_TICK)

        if Client.loaded and Client.spawned and Config.Vitals.enabled then
            local ped = PlayerPedId()
            if DoesEntityExist(ped) and not IsEntityDead(ped) then
                local seconds = DECAY_TICK / 1000
                local multiplier = activityMultiplier()

                -- hunger / thirst drain (config values are per minute)
                local hunger = Client.getVital and Client.getVital('hunger') or (Client.data.vitals.hunger or 100)
                local thirst = Client.getVital and Client.getVital('thirst') or (Client.data.vitals.thirst or 100)
                local stress = Client.data.vitals.stress or 0

                hunger = Nexus.Utils.clamp(hunger - (Config.Vitals.hungerDecay / 60) * multiplier * seconds, 0, 100)
                thirst = Nexus.Utils.clamp(thirst - (Config.Vitals.thirstDecay / 60) * multiplier * seconds, 0, 100)

                -- stress goes up from action, comes down when calm
                local calm = (not IsPedInAnyVehicle(ped, false)) and not IsPedShooting(ped) and not IsPedInMeleeCombat(ped)
                local delta = stressFromEnvironment(seconds)
                if calm and delta <= 0 then
                    delta = -(Config.Vitals.stressDecay / 60) * seconds
                end
                stress = Nexus.Utils.clamp(stress + delta, 0, 100)

                -- ped health/armour
                local pedVitals = readPed()
                local previousHealth = Client.data.vitals.health or 200

                Client.data.vitals.hunger = hunger
                Client.data.vitals.thirst = thirst
                Client.data.vitals.stress = stress
                Client.data.vitals.health = pedVitals.health
                Client.data.vitals.armour = pedVitals.armour

                applyLowVitalEffects(hunger, thirst, stress)

                -- starvation damage
                local starving = hunger <= 0 or thirst <= 0
                if starving and GetGameTimer() > healthDrainAt then
                    healthDrainAt = GetGameTimer() + (Config.Vitals.healthDrainInterval * 1000)
                    local damage = 4
                    SetEntityHealth(ped, math.max(1, pedVitals.health - damage))
                    if not warned.starving or GetGameTimer() - warned.starving > 60000 then
                        warned.starving = GetGameTimer()
                        Nexus.Notify('You are starving — find food and water.', 'error', 6000, 'Vitals')
                    end
                end

                if Client.data.vitals.health < previousHealth and previousHealth > 0 then
                    Client.emit('healthChanged', Client.data.vitals.health, previousHealth)
                end

                warnLow('hunger', hunger, 'Hunger')
                warnLow('thirst', thirst, 'Thirst')
                warnLow('stress', stress, 'Stress')

                -- periodic reconciliation with the server
                local now = GetGameTimer()
                if now - lastSync > SYNC_INTERVAL then
                    lastSync = now
                    TriggerServerEvent('nexus:server:syncVitals', {
                        hunger = math.floor(hunger),
                        thirst = math.floor(thirst),
                        stress = math.floor(stress),
                        health = pedVitals.health,
                        armour = pedVitals.armour,
                    })
                end
            end
        end
    end
end)

--- React to the server pushing a vital (food, medicine, admin).
RegisterNetEvent('nexus:client:vitalChanged', function(key, value)
    if not Client.data then return end
    Client.data.vitals[key] = value

    if key == 'health' then
        local ped = PlayerPedId()
        if GetEntityHealth(ped) < value then SetEntityHealth(ped, math.floor(value)) end
    elseif key == 'armour' then
        SetPedArmour(PlayerPedId(), math.floor(value))
    end
end)

--- Called by the inventory when a consumable is used, purely for the animation.
RegisterNetEvent('nexus:client:playConsume', function(kind)
    local ped = PlayerPedId()
    local dict, anim = 'mp_player_inteat@burger', 'mp_player_int_eat_burger'
    if kind == 'drink' then
        dict, anim = 'mp_player_intdrink', 'loop_bottle'
    end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 1500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Citizen.Wait(10) end
    TaskPlayAnim(ped, dict, anim, 3.0, 3.0, 2500, 49, 0, false, false, false)
    Citizen.Wait(2500)
    ClearPedTasks(ped)
end)
