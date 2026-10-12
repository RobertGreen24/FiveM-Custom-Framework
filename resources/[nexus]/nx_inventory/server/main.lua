--[[
    Nexus Framework :: nx_inventory/server/main.lua
    Every client request lands here, gets validated against the player's real
    position and permissions, and only then touches a container.

    Security model
    --------------
    * The client never says "I have this item" - it only ever names a container
      and a slot, and the server looks the contents up itself.
    * Distance checks use the server's view of the ped where OneSync provides it,
      falling back to the last position the client reported.
    * Trunks and gloveboxes additionally require the vehicle to be unlocked or the
      player to hold its keys (nx_vehicles, when installed).
]]

Nexus = Nexus or {}
local Containers = Nexus.Inventory
local InvUtil = InvUtil

local useCooldowns = {}      -- [source] = gameTimer of last use
local USE_COOLDOWN = 1500

-- ===========================================================================
--  HELPERS
-- ===========================================================================

local function playerFor(source)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return nil end
    return player
end

local function coordsOf(source)
    local ped = GetPlayerPed(source)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        local coords = GetEntityCoords(ped)
        if coords and (coords.x ~= 0.0 or coords.y ~= 0.0) then
            return coords
        end
    end
    local player = Nexus.GetPlayer(source)
    return player and player:getCoords()
end

--- Resolves a container the client asked for, enforcing access rules.
---@param source number
---@param owner string
---@param opts table|nil { vehicleNetId }
---@return table|nil container, string|nil error
local function resolveContainer(source, owner, opts)
    opts = opts or {}
    local parsed = InvUtil.parseOwner(owner)
    if not parsed then return nil, 'bad_owner' end

    local player = playerFor(source)
    if not player then return nil, 'not_loaded' end

    if parsed.type == 'char' then
        if tonumber(parsed.id) ~= player.charId then return nil, 'not_yours' end
        return Containers.forPlayer(source)

    elseif parsed.type == 'trunk' or parsed.type == 'glove' then
        local plate = parsed.id
        local coords = coordsOf(source)
        local vehicle = nil

        if opts.vehicleNetId then
            vehicle = NetworkGetEntityFromNetworkId(tonumber(opts.vehicleNetId) or 0)
        end

        local trunkCoords
        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
            trunkCoords = GetEntityCoords(vehicle)
            -- the plate on the entity must match, or the player is trying to open
            -- somebody else's car by net id
            local entityPlate = (GetVehicleNumberPlateText(vehicle) or ''):gsub('%s+', '')
            if entityPlate ~= '' and entityPlate ~= plate then
                return nil, 'plate_mismatch'
            end
        end

        if not trunkCoords then
            -- look for the nearest vehicle with that plate within reach
            local found = nil
            local vehicles = GetGamePool and GetGamePool('CVehicle') or {}
            for _, candidate in ipairs(vehicles) do
                local candidatePlate = (GetVehicleNumberPlateText(candidate) or ''):gsub('%s+', '')
                if candidatePlate == plate then
                    local distance = coords and #(GetEntityCoords(candidate) - coords) or 999
                    if distance <= InvConfig.trunkDistance then
                        found = candidate
                        break
                    end
                end
            end
            if not found then return nil, 'too_far' end
            trunkCoords = GetEntityCoords(found)
            vehicle = found
        end

        if coords and #(trunkCoords - coords) > InvConfig.trunkDistance + 1.0 then
            return nil, 'too_far'
        end

        -- locked vehicles need keys
        if vehicle and vehicle ~= 0 and InvConfig.requireKeysForTrunk then
            local locked = GetVehicleDoorLockStatus(vehicle) or 0
            if locked >= 2 then
                local hasKeys = false
                if GetResourceState('nx_vehicles') == 'started' then
                    hasKeys = exports.nx_vehicles:hasKeys(source, plate) == true
                else
                    hasKeys = true
                end
                if not hasKeys then return nil, 'locked' end
            end
        end

        local kindLabel = parsed.type == 'trunk' and 'Trunk' or 'Glovebox'
        return Containers.load(owner, { label = ('%s · %s'):format(kindLabel, plate) })

    elseif parsed.type == 'stash' then
        local container, err = Containers.openStash(source, parsed.id)
        return container, err

    elseif parsed.type == 'drop' then
        local container = Containers.get(owner)
        if not container then return nil, 'no_drop' end
        if container.meta and container.meta.coords then
            local coords = coordsOf(source)
            if coords and #(vector3(container.meta.coords[1], container.meta.coords[2], container.meta.coords[3]) - coords) > 3.5 then
                return nil, 'too_far'
            end
        end
        return container

    elseif parsed.type == 'shop' then
        -- shops are driven by nx_shops, never by the client directly
        return nil, 'no_permission'
    end

    return nil, 'unknown_container'
end

--- Sends both halves of an open inventory to the client.
local function pushInventory(source, container, other, extra)
    local payload = {
        self = container and {
            owner = container.owner,
            label = container.label,
            slots = container.slots,
            maxWeight = Containers.getMaxWeight(container),
            weight = Containers.getWeight(container),
            items = Nexus.Utils.map(Containers.toList(container), InvUtil.serialise),
        } or nil,
        other = other and {
            owner = other.owner,
            label = other.label,
            slots = other.slots,
            maxWeight = Containers.getMaxWeight(other),
            weight = Containers.getWeight(other),
            kind = other.kind,
            items = Nexus.Utils.map(Containers.toList(other), InvUtil.serialise),
        } or nil,
        money = {
            cash = Nexus.GetPlayer(source) and Nexus.GetPlayer(source):getMoney('cash') or 0,
            bank = Nexus.GetPlayer(source) and Nexus.GetPlayer(source):getMoney('bank') or 0,
            black = Nexus.GetPlayer(source) and Nexus.GetPlayer(source):getMoney('black') or 0,
        },
        hotbar = InvConfig.hotbarSlots,
        shop = extra and extra.shop or nil,
    }
    TriggerClientEvent('nexus:client:inventoryData', source, payload)
end

Nexus.InventoryPush = pushInventory

local function refreshIfOpen(source, container)
    -- the client tracks which containers it has open; re-push after a change so
    -- the grid stays in sync (drag between two players' drops, shops, etc.)
    local open = Nexus.openInventories[source]
    if not open then return end
    if open.self and open.self.owner == container.owner then
        pushInventory(source, Containers.get(open.self.owner), open.other and Containers.get(open.other) or nil)
    elseif open.other and open.other == container.owner then
        pushInventory(source, Containers.get(open.self), Containers.get(open.other))
    end
end

Nexus.RefreshInventory = refreshIfOpen

Nexus.openInventories = Nexus.openInventories or {}

-- ===========================================================================
--  OPEN / CLOSE
-- ===========================================================================

RegisterNetEvent('nx_inv:requestOpen', function(owner, targetOwner, opts)
    local source = source
    local player = playerFor(source)
    if not player then return end

    opts = opts or {}
    local selfContainer = Containers.forPlayer(source)
    if not selfContainer then return end

    local other, err
    if targetOwner then
        other, err = resolveContainer(source, targetOwner, opts)
        if not other then
            player:notify(err == 'too_far' and 'Too far away.' or (err == 'locked' and 'It is locked.' or 'You cannot open that.'),
                'error')
            return
        end
    end

    Nexus.openInventories[source] = {
        self = { owner = selfContainer.owner },
        other = other and other.owner or nil,
    }

    pushInventory(source, selfContainer, other)
end)

RegisterNetEvent('nx_inv:close', function()
    local source = source
    Nexus.openInventories[source] = nil
end)

--- Refresh request (after an external resource changed something).
RegisterNetEvent('nx_inv:refresh', function()
    local source = source
    local open = Nexus.openInventories[source]
    if not open then return end
    pushInventory(source, Containers.get(open.self.owner), open.other and Containers.get(open.other) or nil)
end)

-- ===========================================================================
--  MOVEMENT
-- ===========================================================================

local function applyAndPush(source, fromContainer, toContainer, fromSlot, toSlot, amount)
    local ok, err = Containers.moveItem(fromContainer, fromSlot, toContainer, toSlot, amount)
    if not ok then
        local messages = {
            weight = 'Not enough space (weight).',
            slots = 'Not enough space.',
            slot_occupied = 'That slot is taken.',
            empty_slot = 'Nothing to move.',
        }
        local player = Nexus.GetPlayer(source)
        if player then player:notify(messages[err] or 'Cannot move that.', 'error') end
        pushInventory(source, fromContainer, toContainer)
        return false
    end

    -- keep both open grids fresh
    pushInventory(source, fromContainer.kind == 'char' and fromContainer or toContainer,
        fromContainer.kind == 'char' and toContainer or fromContainer)
    return true
end

RegisterNetEvent('nx_inv:move', function(fromOwner, fromSlot, toOwner, toSlot, amount)
    local source = source
    local player = playerFor(source)
    if not player then return end

    fromSlot, toSlot = tonumber(fromSlot), tonumber(toSlot)
    if not fromSlot or not toSlot then return end

    local from = resolveContainer(source, fromOwner)
    if not from then return end

    local to
    if toOwner == 'give' then
        -- handled by nx_inv:give
        return
    end
    to = resolveContainer(source, toOwner)
    if not to then return end

    applyAndPush(source, from, to, fromSlot, toSlot, amount)
end)

RegisterNetEvent('nx_inv:split', function(owner, slot, amount)
    local source = source
    if not playerFor(source) then return end
    local container = resolveContainer(source, owner)
    if not container then return end

    local ok, targetSlot = Containers.splitSlot(container, tonumber(slot), tonumber(amount))
    if not ok then
        local player = Nexus.GetPlayer(source)
        if player then player:notify('Cannot split that stack.', 'error') end
    end
    pushInventory(source, container, Nexus.openInventories[source] and Nexus.openInventories[source].other
        and Containers.get(Nexus.openInventories[source].other) or nil)
end)

--- Quick move: shift-click sends an item to the other open container.
RegisterNetEvent('nx_inv:quickMove', function(fromOwner, slot)
    local source = source
    local player = playerFor(source)
    if not player then return end

    local open = Nexus.openInventories[source]
    if not open or not open.other then return end

    local from = resolveContainer(source, fromOwner)
    if not from then return end

    local toOwner = (from.owner == open.self.owner) and open.other or open.self.owner
    local to = resolveContainer(source, toOwner)
    if not to then return end

    local item = from.items[tonumber(slot)]
    if not item then return end

    local free = Containers.nextFreeSlot(to)
    if not free then
        player:notify('No space in that container.', 'error')
        return
    end
    applyAndPush(source, from, to, tonumber(slot), free, item.amount)
end)

-- ===========================================================================
--  USE
-- ===========================================================================

--- Item "use" registry. nx_core's generic effects handle food/drink/medical;
--- resources can register their own handlers with:
---     exports.nx_inventory:registerItemUse('lockpick', function(source, item) ... end)
local useHandlers = {}

--- Registers a custom 'use' action. Return (true, false) to keep the item.
function Containers.registerUse(name, fn)
    useHandlers[name] = fn
end

--- Applies the generic on-use effect table from nx_core/shared/items.lua.
local function applyEffects(source, item)
    local def = Nexus.Items[item.name]
    if not def or not def.effect then return end

    for effect, value in pairs(def.effect) do
        if effect ~= 'job' then
            Nexus.applyItemEffect(source, effect, value)
        end
    end
end

local function consumeItem(source, container, slot)
    local item = container.items[slot]
    if not item then return end

    local def = Nexus.Items[item.name]
    if not def then return end

    -- job restriction
    local player = Nexus.GetPlayer(source)
    if def.jobs and not Nexus.ItemAllowedForJob(item.name, player.job.name) then
        player:notify('You are not trained to use that.', 'error')
        return
    end
    if def.requiresDuty and not player:isOnDuty() then
        player:notify(Nexus.L and Nexus.L('duty.required') or 'You must be on duty to use that.', 'error')
        return
    end

    -- custom handler first
    if useHandlers[item.name] then
        local ok, consumed = useHandlers[item.name](source, item, container)
        if ok and consumed ~= false then
            Containers.removeSlot(container, slot)
            Containers.markDirty(container, true)
        end
        pushInventory(source, container, Nexus.openInventories[source] and Nexus.openInventories[source].other
            and Containers.get(Nexus.openInventories[source].other) or nil)
        return
    end

    -- weapons equip rather than get consumed
    if def.type == 'weapon' then
        if def.requiresLicence and not player:hasLicence(def.requiresLicence) then
            player:notify('You do not hold the required licence.', 'error')
            return
        end
        TriggerClientEvent('nexus:client:equipWeapon', source, item.name, item.metadata or {})
        pushInventory(source, container, nil)
        return
    end

    -- ammo boxes load the matching weapon
    if def.type == 'ammo' then
        local loaded = false
        for _, other in pairs(container.items) do
            local otherDef = Nexus.Items[other.name]
            if otherDef and otherDef.type == 'weapon' and otherDef.ammoItem == item.name then
                other.metadata = other.metadata or {}
                other.metadata.ammo = (other.metadata.ammo or 0) + 30
                loaded = true
                TriggerClientEvent('nexus:client:weaponAmmo', source, other.name, other.metadata.ammo)
                break
            end
        end
        if loaded then
            Containers.removeSlot(container, slot)
            Containers.markDirty(container, true)
            player:notify('Magazine loaded.', 'success')
            pushInventory(source, container, nil)
        else
            player:notify('You have no weapon that takes those rounds.', 'error')
        end
        return
    end

    -- consumables
    if def.usable and (def.effect or def.type == 'food' or def.type == 'drink' or def.type == 'medical') then
        TriggerClientEvent('nexus:client:consume', source, item.name, InvConfig.consumeTime,
            (def.type == 'drink') and 'drink' or 'eat')

        Citizen.SetTimeout(InvConfig.consumeTime, function()
            -- re-check the item is still there (they may have dropped it mid-eat)
            local live = Containers.get(container.owner)
            local liveItem = live and live.items[slot]
            if not liveItem or liveItem.name ~= item.name then return end

            applyEffects(source, liveItem)
            Containers.removeSlot(live, slot)
            Containers.markDirty(live, true)
            pushInventory(source, live, Nexus.openInventories[source] and Nexus.openInventories[source].other
                and Containers.get(Nexus.openInventories[source].other) or nil)
        end)
        return
    end

    -- anything else with a client-side action
    TriggerClientEvent('nexus:client:useItem', source, item.name, item.metadata or {})
end

RegisterNetEvent('nx_inv:use', function(owner, slot)
    local source = source
    local player = playerFor(source)
    if not player then return end

    local now = GetGameTimer()
    if useCooldowns[source] and now - useCooldowns[source] < USE_COOLDOWN then return end
    useCooldowns[source] = now

    local container = resolveContainer(source, owner)
    if not container then return end

    slot = tonumber(slot)
    if not slot then return end

    consumeItem(source, container, slot)
end)

--- Hotbar: keys 1-5 map to the first five slots.
RegisterNetEvent('nx_inv:hotbar', function(slot)
    local source = source
    local player = playerFor(source)
    if not player then return end
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > (InvConfig.hotbarSlots or 5) then return end

    local container = Containers.forPlayer(source)
    if not container then return end
    local item = container.items[slot]
    if not item then return end
    if not (Nexus.Items[item.name] or {}).usable then return end

    consumeItem(source, container, slot)
end)

-- ===========================================================================
--  DROP / PICK UP / GIVE
-- ===========================================================================

--- Creates a ground container at a position and tells every client about it.
function Nexus.Inventory.createDrop(coords, items, label, ownerSource)
    local dropId = ('%s%s'):format(os.time() % 100000, math.random(1000, 9999))
    local owner = InvUtil.dropOwner(dropId)

    local container = Containers.create(owner, {
        label = label or 'Ground',
        slots = InvConfig.dropSlots,
        weight = InvConfig.dropWeight,
        persistent = false,
        meta = {
            coords = { coords.x, coords.y, coords.z },
            expires = os.time() + (InvConfig.dropLifetime or 900),
            source = ownerSource,
        },
    })

    for _, item in ipairs(items or {}) do
        Containers.addItem(container, item.name, item.amount, item.metadata)
    end

    TriggerClientEvent('nexus:client:addDrop', -1, {
        id = dropId,
        coords = { coords.x, coords.y, coords.z },
        label = container.label,
    })

    return dropId, container
end

RegisterNetEvent('nx_inv:drop', function(owner, slot, amount)
    local source = source
    local player = playerFor(source)
    if not player or not InvConfig.allowDrop then return end

    local container = resolveContainer(source, owner)
    if not container then return end

    local item = container.items[tonumber(slot)]
    if not item then return end
    if InvConfig.undroppable[item.name] then
        player:notify('You cannot drop that.', 'error')
        return
    end

    local dropCount = math.min(tonumber(amount) or item.amount, item.amount)
    local coords = coordsOf(source)
    if not coords then return end

    -- don't drop under the map
    local _, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1.0, false)
    if groundZ and groundZ > 0.0 then coords = vector3(coords.x, coords.y, groundZ) end

    if dropCount == item.amount then
        local removed = Containers.removeSlot(container, tonumber(slot))
        if removed then
            Nexus.Inventory.createDrop(coords, { removed }, ('%s\'s bag'):format(player:getName()), source)
        end
    else
        item.amount = item.amount - dropCount
        item.weight = InvUtil.itemWeight(item.name, item.metadata, item.amount)
        Containers.markDirty(container)
        Nexus.Inventory.createDrop(coords, {
            { name = item.name, amount = dropCount, metadata = item.metadata },
        }, ('%s\'s bag'):format(player:getName()), source)
    end

    pushInventory(source, container, nil)
end)

RegisterNetEvent('nx_inv:pickup', function(dropId, slot, amount)
    local source = source
    local player = playerFor(source)
    if not player then return end

    local drop = Containers.get(InvUtil.dropOwner(dropId))
    if not drop then
        player:notify('That bag is gone.', 'error')
        return
    end

    local coords = coordsOf(source)
    if coords and drop.meta and drop.meta.coords then
        local distance = #(vector3(drop.meta.coords[1], drop.meta.coords[2], drop.meta.coords[3]) - coords)
        if distance > InvConfig.dropDistance + 1.5 then
            player:notify('Too far away.', 'error')
            return
        end
    end

    local selfContainer = Containers.forPlayer(source)
    if not selfContainer then return end

    if slot then
        -- taking one stack out of the bag
        local item = drop.items[tonumber(slot)]
        if not item then return end
        local take = math.min(tonumber(amount) or item.amount, item.amount)

        local removed
        if take == item.amount then
            removed = Containers.removeSlot(drop, tonumber(slot))
        else
            item.amount = item.amount - take
            item.weight = InvUtil.itemWeight(item.name, item.metadata, item.amount)
            removed = { name = item.name, amount = take, metadata = item.metadata }
        end

        local ok, reason = Containers.addItem(selfContainer, removed.name, removed.amount, removed.metadata)
        if not ok then
            -- put it back
            Containers.addItem(drop, removed.name, removed.amount, removed.metadata)
            player:notify(reason == 'weight' and 'You cannot carry that much.' or 'No space.', 'error')
            return
        end
        TriggerEvent('nexus:inventory:pickedUp', source, removed)
    else
        -- whole bag
        for _, item in ipairs(Containers.toList(drop)) do
            local ok = Containers.addItem(selfContainer, item.name, item.amount, item.metadata)
            if ok then
                Containers.removeItem(drop, item.name, item.amount, item.metadata)
            else
                player:notify('Some items did not fit.', 'warning')
                break
            end
        end
    end

    if Containers.countItems(drop) == 0 then
        local entry = Nexus.openInventories[source]
        if entry and entry.other == drop.owner then entry.other = nil end
        Containers.unload(drop.owner, false)
        TriggerClientEvent('nexus:client:removeDrop', -1, dropId)
    end

    pushInventory(source, selfContainer, nil)
end)

RegisterNetEvent('nx_inv:give', function(slot, amount, targetSource)
    local source = source
    local giver = playerFor(source)
    if not giver then return end

    local target = Nexus.GetPlayer(tonumber(targetSource))
    if not target or not target.loaded then
        giver:notify('That player is not available.', 'error')
        return
    end

    -- must be standing next to each other
    local targetPed = GetPlayerPed(target.source)
    local sourcePed = GetPlayerPed(source)
    if targetPed and targetPed ~= 0 and sourcePed and sourcePed ~= 0 then
        if #(GetEntityCoords(targetPed) - GetEntityCoords(sourcePed)) > 4.0 then
            giver:notify('You are too far away.', 'error')
            return
        end
    end

    local container = Containers.forPlayer(source)
    local item = container and container.items[tonumber(slot)]
    if not item then return end

    local give = math.min(tonumber(amount) or item.amount, item.amount)
    local targetContainer = Containers.forPlayer(target.source)
    if not targetContainer then return end

    local ok, reason = Containers.canCarry(targetContainer, item.name, give, item.metadata)
    if not ok then
        giver:notify(reason == 'weight' and 'They cannot carry that much.' or 'They have no space.', 'error')
        return
    end

    local metadata = item.metadata
    if give == item.amount then
        Containers.removeSlot(container, tonumber(slot))
    else
        item.amount = item.amount - give
        item.weight = InvUtil.itemWeight(item.name, metadata, item.amount)
        Containers.markDirty(container)
    end

    Containers.addItem(targetContainer, item.name, give, metadata)

    -- move the weapon itself if a gun changed hands
    if (Nexus.Items[item.name] or {}).type == 'weapon' then
        TriggerClientEvent('nexus:client:removeWeapon', source, item.name)
        TriggerClientEvent('nexus:client:equipWeapon', target.source, item.name, metadata or {})
    end

    giver:notify(('You gave %sx %s'):format(give, Nexus.GetItemLabel(item.name)), 'success')
    target:notify(('You received %sx %s'):format(give, Nexus.GetItemLabel(item.name)), 'success')

    pushInventory(source, container, nil)
    TriggerClientEvent('nx_inv:refresh', target.source)
end)

-- ===========================================================================
--  WEAPON SYNC
-- ===========================================================================

RegisterNetEvent('nx_inv:syncWeapons', function()
    local source = source
    local player = playerFor(source)
    if not player then return end

    local container = Containers.forPlayer(source)
    if not container then return end

    local weapons = {}
    for _, item in ipairs(Containers.toList(container)) do
        if (Nexus.Items[item.name] or {}).type == 'weapon' then
            weapons[#weapons + 1] = { name = item.name, metadata = item.metadata or {} }
        end
    end
    TriggerClientEvent('nexus:client:syncWeapons', source, weapons)
end)

--- Weapon durability coming back from the client (it knows when a shot fires).
RegisterNetEvent('nx_inv:damageWeapon', function(weaponName, amount)
    local source = source
    local player = playerFor(source)
    if not player then return end

    local container = Containers.forPlayer(source)
    if not container then return end

    for _, item in pairs(container.items) do
        if item.name == weaponName and (Nexus.Items[item.name] or {}).type == 'weapon' then
            item.metadata = item.metadata or {}
            item.metadata.durability = math.max(0, (item.metadata.durability or 100) - (tonumber(amount) or 1))
            Containers.markDirty(container)
            return
        end
    end
end)

-- ===========================================================================
--  LIFECYCLE HOOKS
-- ===========================================================================

AddEventHandler('nexus:server:playerLoaded', function(player)
    local container = Containers.forPlayer(player.source)
    if not container then return end
    player.inventory = container
    TriggerClientEvent('nexus:client:inventoryReady', player.source, {
        weight = Containers.getWeight(container),
        maxWeight = Containers.getMaxWeight(container),
        slots = container.slots,
    })
end)

AddEventHandler('nexus:server:playerDropped', function(player)
    if not player.charId then return end
    Containers.unload(InvUtil.charOwner(player.charId), true)
    Nexus.openInventories[player.source] = nil
    useCooldowns[player.source] = nil
end)

--- Death: everything that can be dropped spills into a bag where they fell.
AddEventHandler('nexus:server:playerDied', function(player, cause)
    if not InvConfig.allowDrop or not Config.Death.lootOnDeath then return end

    local container = Containers.forPlayer(player.source)
    if not container then return end

    local items = Containers.clear(container, true)
    if #items == 0 then return end

    local coords = player:getCoords()
    local dropId = Nexus.Inventory.createDrop(coords, items, ('%s\'s belongings'):format(player:getName()), player.source)

    -- strip the weapons off the ped
    for _, item in ipairs(items) do
        if (Nexus.Items[item.name] or {}).type == 'weapon' then
            TriggerClientEvent('nexus:client:removeWeapon', player.source, item.name)
        end
    end

    Nexus.Log.action('death_loot', {
        actor = player:getName(), target = dropId,
        details = ('%d stack(s) dropped'):format(#items),
    })
end)

exports('registerItemUse', function(name, fn)
    Containers.registerUse(name, fn)
end)
