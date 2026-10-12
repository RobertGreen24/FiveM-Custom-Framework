--[[
    Nexus Framework :: nx_inventory/client/weapons.lua
    Keeps the ped's weapons in step with the inventory items: equipping, ammo,
    durability and the jam chance when a gun is worn out.
]]

local Nexus = Nexus

Nexus.Weapons = Nexus.Weapons or {}

local tracked = {}       -- [weaponName] = metadata
local lastAmmo = {}
local jammed = false

local function hash(name)
    return type(name) == 'number' and name or GetHashKey(name)
end

--- Equips a weapon the player actually owns.
function Nexus.Weapons.equip(name, metadata)
    local ped = PlayerPedId()
    local weaponHash = hash(name)

    if not HasPedGotWeapon(ped, weaponHash, false) then
        GiveWeaponToPed(ped, weaponHash, 0, false, false)
    end

    local ammo = (metadata and metadata.ammo) or 30
    SetPedAmmo(ped, weaponHash, ammo)
    SetCurrentPedWeapon(ped, weaponHash, true)

    tracked[name] = metadata or {}
    tracked[name].equipped = true

    if metadata and metadata.tint then
        SetPedWeaponTintIndex(ped, weaponHash, tonumber(metadata.tint) or 0)
    end

    Nexus.Notify(('%s equipped'):format(Nexus.GetItemLabel(name)), 'info', 2500)
    TriggerEvent('nexus:client:weaponEquipped', name, metadata)
end

function Nexus.Weapons.remove(name)
    local ped = PlayerPedId()
    local weaponHash = hash(name)
    if HasPedGotWeapon(ped, weaponHash, false) then
        RemoveWeaponFromPed(ped, weaponHash)
    end
    tracked[name] = nil
end

function Nexus.Weapons.clear()
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
    tracked = {}
end

function Nexus.Weapons.getTracked()
    return tracked
end

function Nexus.Weapons.setAmmo(name, ammo)
    local ped = PlayerPedId()
    local weaponHash = hash(name)
    if HasPedGotWeapon(ped, weaponHash, false) then
        SetPedAmmo(ped, weaponHash, tonumber(ammo) or 0)
    end
    if tracked[name] then
        tracked[name].ammo = tonumber(ammo) or 0
    end
end

--- Durability ------------------------------------------------------------------
--- Guns wear out as they are fired. At zero they jam constantly until cleaned.

local function currentWeaponName()
    local ped = PlayerPedId()
    local _, weaponHash = GetCurrentPedWeapon(ped, true)
    if not weaponHash or weaponHash == 0 or weaponHash == GetHashKey('WEAPON_UNARMED') then return nil end

    for name in pairs(tracked) do
        if hash(name) == weaponHash then return name end
    end
    return nil
end

CreateThread(function()
    while true do
        Citizen.Wait(0)
        if Nexus.Client.isLoaded() then
            local name = currentWeaponName()
            if name then
                local meta = tracked[name] or {}
                local ped = PlayerPedId()
                local _, weaponHash = GetCurrentPedWeapon(ped, true)
                local ammo = GetAmmoInPedWeapon(ped, weaponHash)

                -- shot fired?
                if lastAmmo[name] and ammo < lastAmmo[name] then
                    local durability = math.max(0, (meta.durability or 100) - 0.35)
                    meta.durability = durability
                    tracked[name].durability = durability

                    if durability <= 0 and not jammed and math.random(100) <= InvConfig.weapons.jamChance then
                        jammed = true
                        Nexus.Notify('Your weapon jammed — it needs cleaning.', 'error', 4000, 'Weapon')
                        Citizen.SetTimeout(2500, function() jammed = false end)
                    end
                end

                -- holding a jammed gun stops you firing
                if jammed and Config and InvConfig.weapons.jamChance > 0 then
                    DisableControlAction(0, 24, true)
                    DisableControlAction(0, 142, true)
                    DisablePlayerFiring(PlayerId(), true)
                end

                lastAmmo[name] = ammo

                -- push durability to the server when it moves enough to matter
                if math.floor(meta.durability or 100) < math.floor((meta.reported or 100)) - 4 then
                    meta.reported = math.floor(meta.durability or 100)
                    TriggerServerEvent('nx_inv:damageWeapon', name, 5)
                end
            end
            Citizen.Wait(250)
        else
            Citizen.Wait(1000)
        end
    end
end)

--- Events ----------------------------------------------------------------------

RegisterNetEvent('nexus:client:equipWeapon', function(name, metadata)
    Nexus.Weapons.equip(name, metadata)
end)

RegisterNetEvent('nexus:client:removeWeapon', function(name)
    Nexus.Weapons.remove(name)
end)

RegisterNetEvent('nexus:client:clearWeapons', function()
    Nexus.Weapons.clear()
end)

RegisterNetEvent('nexus:client:weaponAmmo', function(name, ammo)
    Nexus.Weapons.setAmmo(name, ammo)
end)

RegisterNetEvent('nexus:client:syncWeapons', function(list)
    --- The server owns the list; equip whatever they are carrying so a reconnect
    --- or resource restart does not lose the guns.
    for _, entry in ipairs(list or {}) do
        if not tracked[entry.name] then
            Nexus.Weapons.equip(entry.name, entry.metadata)
        end
    end
end)

--- Clean a weapon (used by the weapon cleaning kit).
RegisterNetEvent('nexus:client:cleanWeapons', function()
    for name, meta in pairs(tracked) do
        meta.durability = 100
    end
    Nexus.Notify('Weapons cleaned.', 'success')
end)

exports('equipWeapon', function(name, metadata) Nexus.Weapons.equip(name, metadata) end)
exports('removeWeapon', function(name) Nexus.Weapons.remove(name) end)
exports('clearWeapons', function() Nexus.Weapons.clear() end)
