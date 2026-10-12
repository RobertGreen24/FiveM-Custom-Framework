--[[
    Nexus Framework :: nx_appearance/client/shops.lua
    Clothing stores, barbers, tattooists and the wardrobe.
]]

Nexus = Nexus
local Client = Nexus.Client
local Appearance = Nexus.Appearance

-- ===========================================================================
--  BLIPS
-- ===========================================================================

local function addBlip(coords, info, label)
    if not info then return end
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, info.sprite or 73)
    SetBlipColour(blip, info.colour or 4)
    SetBlipScale(blip, 0.75)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, shop in ipairs(AppearanceConfig.clothingShops) do addBlip(shop.coords, shop.blip, shop.label) end
    for _, shop in ipairs(AppearanceConfig.barbers) do addBlip(shop.coords, shop.blip, shop.label) end
    for _, shop in ipairs(AppearanceConfig.tattooists) do addBlip(shop.coords, shop.blip, shop.label) end
end)

-- ===========================================================================
--  MENUS
-- ===========================================================================

--- Choose what to edit at a clothing store.
local function clothingMenu(shop)
    Nexus.Menu({
        title = shop.label,
        options = {
            { label = 'Clothing', description = 'Change your outfit', value = 'clothes' },
            { label = 'Hair & make-up', description = 'Barber services', value = 'barber' },
            { label = 'Wardrobe', description = 'Saved outfits', value = 'wardrobe' },
            { label = 'Cancel', value = 'cancel' },
        },
    }, function(choice)
        if not choice or choice == 'cancel' then return end
        if choice == 'clothes' then
            Appearance.openEditor(Client.getCharId(), { mode = 'clothes', creation = false })
        elseif choice == 'barber' then
            Appearance.openEditor(Client.getCharId(), { mode = 'barber', creation = false })
        else
            wardrobeMenu()
        end
    end)
end

local function wardrobeMenu()
    Nexus.Menu({
        title = 'Wardrobe',
        options = {
            { label = 'Saved outfits', description = 'Wear a saved outfit', value = 'list' },
            { label = 'Save current look', description = 'Add an outfit to the wardrobe', value = 'save' },
            { label = 'Cancel', value = 'cancel' },
        },
    }, function(choice)
        if not choice or choice == 'cancel' then return end
        if choice == 'save' then
            Appearance.openEditor(Client.getCharId(), { mode = 'wardrobe', creation = false })
        else
            TriggerServerEvent('nx_appearance:requestOutfits')
        end
    end)
end

RegisterNetEvent('nx_appearance:outfitList', function(outfits)
    local options = {}
    for _, outfit in ipairs(outfits) do
        options[#options + 1] = {
            label = outfit.name,
            description = ('Saved %s'):format(outfit.created_at or ''),
            value = outfit.id,
        }
    end
    if #options == 0 then
        Nexus.Notify('You have no saved outfits.', 'info')
        return
    end
    options[#options + 1] = { label = 'Cancel', value = 'cancel' }

    Nexus.Menu({ title = 'Wardrobe', options = options }, function(choice)
        if not choice or choice == 'cancel' then return end
        TriggerServerEvent('nx_appearance:wearOutfit', choice)
    end)
end)

-- ===========================================================================
--  INTERACTION LOOP
-- ===========================================================================

local function nearest(coords, list, radius)
    for _, entry in ipairs(list) do
        if #(coords - entry.coords) <= radius then return entry end
    end
    return nil
end

CreateThread(function()
    while true do
        local sleep = 600
        if Client.isLoaded() and not Appearance.isOpen() then
            local coords = GetEntityCoords(PlayerPedId())

            local shop = nearest(coords, AppearanceConfig.clothingShops, 2.0)
            local barber = nearest(coords, AppearanceConfig.barbers, 2.0)
            local tattoo = nearest(coords, AppearanceConfig.tattooists, 2.0)

            if shop then
                sleep = 0
                Nexus.TextUI(true, 'E', ('Browse %s'):format(shop.label))
                if IsControlJustPressed(0, 38) then
                    Nexus.TextUI(false)
                    clothingMenu(shop)
                end
            elseif barber then
                sleep = 0
                Nexus.TextUI(true, 'E', ('%s · $%d'):format(barber.label, AppearanceConfig.barberPrice))
                if IsControlJustPressed(0, 38) then
                    Nexus.TextUI(false)
                    Appearance.openEditor(Client.getCharId(), { mode = 'barber', creation = false })
                end
            elseif tattoo then
                sleep = 0
                Nexus.TextUI(true, 'E', ('%s · $%d per tattoo'):format(tattoo.label, AppearanceConfig.tattooPrice))
                if IsControlJustPressed(0, 38) then
                    Nexus.TextUI(false)
                    Nexus.Notify('Tattoo artists are not taking walk-ins yet.', 'info')
                end
            else
                Nexus.TextUI(false)
            end
        end
        Citizen.Wait(sleep)
    end
end)

-- ===========================================================================
--  COMMANDS
-- ===========================================================================

RegisterCommand(AppearanceConfig.wardrobeCommand, function()
    if not Client.isLoaded() then return end
    wardrobeMenu()
end, false)

RegisterCommand(AppearanceConfig.barberCommand, function()
    if not Client.isLoaded() then return end
    local coords = GetEntityCoords(PlayerPedId())
    if not nearest(coords, AppearanceConfig.barbers, 30.0) then
        Nexus.Notify('Visit a barber shop first.', 'error')
        return
    end
    Appearance.openEditor(Client.getCharId(), { mode = 'barber', creation = false })
end, false)

exports('openCreator', function(opts)
    opts = opts or {}
    Appearance.openEditor(Client.getCharId(), { mode = opts.mode or 'creator', creation = opts.creation })
end)
exports('openWardrobe', function()
    if not Client.isLoaded() then return end
    wardrobeMenu()
end)
