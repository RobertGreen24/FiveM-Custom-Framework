--[[
    Nexus Framework :: nx_inventory/server/exports.lua
    The inventory API other resources use.

        if exports.nx_inventory:addItem(source, 'bandage', 2) then ... end
        exports.nx_inventory:removeItem(source, 'water', 1)

    Every function takes a *source* (online player) or a container owner string
    ('trunk:ABC123'), so job scripts can work with vehicle storage too.
]]

Nexus = Nexus or {}
local Containers = Nexus.Inventory
local InvUtil = InvUtil

local function containerOf(target)
    if type(target) == 'number' then
        return Containers.forPlayer(target)
    elseif type(target) == 'string' then
        return Containers.load(target)
    end
    return nil
end

-- ===========================================================================
--  ADD / REMOVE
-- ===========================================================================

exports('addItem', function(target, name, amount, metadata, slot)
    local container = containerOf(target)
    if not container then return false end
    local ok = Containers.addItem(container, name, amount or 1, metadata, slot)
    if ok and type(target) == 'number' then
        TriggerClientEvent('nx_inv:refresh', target)
    end
    return ok == true
end)

exports('removeItem', function(target, name, amount, metadata)
    local container = containerOf(target)
    if not container then return false end
    local removed = Containers.removeItem(container, name, amount or 1, metadata)
    if removed > 0 and type(target) == 'number' then
        TriggerClientEvent('nx_inv:refresh', target)
    end
    return removed > 0
end)

exports('hasItem', function(target, name, amount)
    local container = containerOf(target)
    if not container then return false end
    return Containers.hasItem(container, name, amount or 1)
end)

exports('getItemCount', function(target, name)
    local container = containerOf(target)
    if not container then return 0 end
    return Containers.countItem(container, name)
end)

exports('getItems', function(target)
    local container = containerOf(target)
    if not container then return {} end
    local out = {}
    for _, item in ipairs(Containers.toList(container)) do
        out[#out + 1] = InvUtil.serialise(item)
    end
    return out
end)

exports('getRawItems', function(target)
    local container = containerOf(target)
    if not container then return {} end
    return Containers.toList(container)
end)

exports('getItemBySlot', function(target, slot)
    local container = containerOf(target)
    if not container then return nil end
    local item = Containers.getSlot(container, tonumber(slot))
    return item and InvUtil.serialise(item) or nil
end)

exports('canCarryItem', function(target, name, amount, metadata)
    local container = containerOf(target)
    if not container then return false end
    return Containers.canCarry(container, name, amount or 1, metadata)
end)

exports('getWeight', function(target)
    local container = containerOf(target)
    if not container then return 0 end
    return Containers.getWeight(container)
end)

exports('getMaxWeight', function(target)
    local container = containerOf(target)
    if not container then return 0 end
    return Containers.getMaxWeight(container)
end)

exports('getFreeWeight', function(target)
    local container = containerOf(target)
    if not container then return 0 end
    return Containers.freeWeight(container)
end)

exports('getFreeSlots', function(target)
    local container = containerOf(target)
    if not container then return 0 end
    return Containers.freeSlots(container)
end)

exports('clearInventory', function(target)
    local container = containerOf(target)
    if not container then return false end
    Containers.clear(container)
    if type(target) == 'number' then
        TriggerClientEvent('nx_inv:refresh', target)
        local player = Nexus.GetPlayer(target)
        if player then
            TriggerClientEvent('nexus:client:clearWeapons', target)
        end
    end
    return true
end)

--- Sets metadata on a specific stack (durability, serial, plates...).
exports('setMetadata', function(target, slot, metadata, merge)
    local container = containerOf(target)
    if not container then return false end
    local item = container.items[tonumber(slot)]
    if not item then return false end

    if merge then
        item.metadata = Nexus.Utils.merge(item.metadata or {}, metadata or {})
    else
        item.metadata = metadata
    end
    item.weight = InvUtil.itemWeight(item.name, item.metadata, item.amount)
    Containers.markDirty(container, true)

    if type(target) == 'number' then
        TriggerClientEvent('nx_inv:refresh', target)
        if (Nexus.Items[item.name] or {}).type == 'weapon' then
            TriggerClientEvent('nexus:client:equipWeapon', target, item.name, item.metadata or {})
        end
    end
    return true
end)

exports('getMetadata', function(target, slot)
    local container = containerOf(target)
    if not container then return nil end
    local item = container.items[tonumber(slot)]
    return item and item.metadata or nil
end)

-- ===========================================================================
--  CONTAINERS
-- ===========================================================================

exports('getInventory', function(target)
    local container = containerOf(target)
    if not container then return nil end
    return {
        owner = container.owner,
        label = container.label,
        slots = container.slots,
        weight = Containers.getWeight(container),
        maxWeight = Containers.getMaxWeight(container),
        items = Nexus.Utils.map(Containers.toList(container), InvUtil.serialise),
    }
end)

--- Opens a container for a player (used by job scripts: lockers, evidence, etc).
exports('openInventory', function(source, owner, opts)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return false end

    local container = Containers.load(owner, opts)
    if not container then return false end

    local selfContainer = Containers.forPlayer(source)
    Nexus.openInventories[source] = {
        self = { owner = selfContainer.owner },
        other = container.owner,
    }
    Nexus.InventoryPush(source, selfContainer, container)
    return true
end)

exports('closeInventory', function(source)
    Nexus.openInventories[source] = nil
    TriggerClientEvent('nx_inv:forceClose', source)
end)

exports('createContainer', function(owner, opts)
    return Containers.create(owner, opts) ~= nil
end)

exports('getContainer', function(owner)
    return Containers.get(owner)
end)

exports('saveContainer', function(owner)
    local container = Containers.get(owner)
    if not container then return false end
    Containers.save(container)
    return true
end)

--- Creates a ground drop. `items` is a list of { name, amount, metadata }.
exports('createDrop', function(coords, items, label, ownerSource)
    if type(coords) == 'table' and not coords.x then
        coords = vector3(coords[1] or coords.x, coords[2] or coords.y, coords[3] or coords.z)
    end
    local dropId = Nexus.Inventory.createDrop(coords, items or {}, label, ownerSource)
    return dropId
end)

exports('registerItemUse', function(name, fn)
    Containers.registerUse(name, fn)
end)

exports('refreshInventory', function(source)
    TriggerClientEvent('nx_inv:refresh', source)
end)

--- Weapon durability helper used by combat resources.
exports('damageWeapon', function(source, amount)
    local container = Containers.forPlayer(source)
    if not container then return false end

    for _, item in pairs(container.items) do
        local def = Nexus.Items[item.name]
        if def and def.type == 'weapon' and def.weaponType ~= 'melee' then
            item.metadata = item.metadata or {}
            item.metadata.durability = math.max(0, (item.metadata.durability or 100) - (amount or 1))
            Containers.markDirty(container)
            TriggerClientEvent('nx_inv:refresh', source)
            return true
        end
    end
    return false
end)

--- Opens an arbitrary owner container for a player. Used by job scripts
--- (lockers, evidence, gloveboxes) that have already checked permissions —
--- this deliberately skips the proximity checks in `nx_inv:requestOpen`.
---@param source number
---@param owner string  e.g. 'stash:police_evidence' or 'glove:ABC123'
---@param opts? table  { label, slots, weight, persistent }
exports('openForPlayer', function(source, owner, opts)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return false end

    local container = Containers.load(owner, opts)
    if not container then return false end

    local selfContainer = Containers.forPlayer(source)
    if not selfContainer then return false end

    Nexus.openInventories[source] = {
        self = { owner = selfContainer.owner },
        other = container.owner,
    }
    Nexus.InventoryPush(source, selfContainer, container)
    return true
end)

--- Ensures a persistent container exists (creating it if needed). Returns the
--- owner string so callers can pass it to openForPlayer.
exports('ensureContainer', function(owner, opts)
    if Containers.get(owner) then
        local existing = Containers.get(owner)
        if opts then
            existing.label = opts.label or existing.label
            existing.slots = opts.slots or existing.slots
            existing.weight = opts.weight or existing.weight
        end
        return owner
    end

    if Containers.load(owner, opts) then return owner end
    if Containers.create(owner, opts) then return owner end
    return nil
end)
