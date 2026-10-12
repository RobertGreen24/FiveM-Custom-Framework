--[[
    Nexus Framework :: nx_inventory/server/containers.lua
    The container model. Everything that can hold items - player inventories,
    trunks, gloveboxes, stashes, shops and ground drops - is a container with the
    same shape, so all the item logic below is written once.

    Containers live in memory while in use and are written back to nx_inventory
    with a short debounce, which keeps hot paths (dragging 20 stacks around) off
    the database entirely.
]]

Nexus = Nexus or {}
local Containers = {}
Nexus.Inventory = Containers
InvUtil = InvUtil or {}

local memory = {}          -- [owner] = container
local SAVE_DEBOUNCE = 2500 -- ms

-- ===========================================================================
--  CONTAINER LIFECYCLE
-- ===========================================================================

local function now()
    return os.time()
end

--- Loads a container from the database into memory.
---@param owner string e.g. 'char:12'
---@param opts table|nil { label, slots, weight, persistent, owner_job }
function Containers.load(owner, opts)
    if memory[owner] then
        -- refresh mutable fields, keep the items
        if opts then
            memory[owner].label = opts.label or memory[owner].label
            memory[owner].slots = opts.slots or memory[owner].slots
            memory[owner].weight = opts.weight or memory[owner].weight
        end
        return memory[owner]
    end

    local parsed = InvUtil.parseOwner(owner)
    if not parsed then return nil end
    local config = InvConfigFor(parsed.type)

    local container = {
        owner = owner,
        kind = parsed.type,
        id = parsed.id,
        label = (opts and opts.label) or config.label,
        slots = (opts and opts.slots) or config.slots,
        weight = (opts and opts.weight) or config.weight,
        persistent = (opts and opts.persistent ~= nil) and opts.persistent or config.persistent,
        items = {},          -- [slot] = { name, amount, metadata, slot, weight }
        meta = {},           -- arbitrary extra data (stash owner, shop data...)
        dirty = false,
        saveTimer = nil,
        loaded = true,
    }

    -- temporary/instanced containers (shops, pockets) are never read from disk
    if container.persistent and Nexus.DB.available then
        local rows = Nexus.DB.query('SELECT slot, name, amount, metadata FROM nx_inventory WHERE owner = ?', { owner })
        for _, row in ipairs(rows or {}) do
            container.items[tonumber(row.slot)] = {
                slot = tonumber(row.slot),
                name = row.name,
                amount = tonumber(row.amount) or 1,
                metadata = Nexus.Utils.decodeJson(row.metadata, nil),
                weight = InvUtil.itemWeight(row.name, Nexus.Utils.decodeJson(row.metadata, nil), tonumber(row.amount) or 1),
            }
        end
    end

    memory[owner] = container
    return container
end

--- Creates a brand new container (drops, shops) that is not read from disk.
function Containers.create(owner, opts)
    opts = opts or {}
    local parsed = InvUtil.parseOwner(owner)
    local config = InvConfigFor(parsed and parsed.type or 'shop')
    local container = {
        owner = owner,
        kind = parsed and parsed.type or 'shop',
        id = parsed and parsed.id or owner,
        label = opts.label or config.label,
        slots = opts.slots or config.slots,
        weight = opts.weight or config.weight,
        persistent = opts.persistent == true,
        items = {},
        meta = opts.meta or {},
        dirty = false,
        loaded = true,
    }
    memory[owner] = container
    return container
end

function Containers.get(owner)
    return memory[owner]
end

function Containers.getByKind(kind, id)
    return memory[('%s:%s'):format(kind, id)]
end

--- Write-through with debounce. `force` writes immediately (drops, shutdown).
function Containers.markDirty(container, force)
    if not container or not container.persistent or not Nexus.DB.available then return end
    container.dirty = true

    if force then
        Containers.save(container)
        return
    end

    if container.saveTimer then return end
    container.saveTimer = Citizen.SetTimeout(SAVE_DEBOUNCE, function()
        if container.saveTimer then container.saveTimer = nil end
        Containers.save(container)
    end)
end

function Containers.save(container)
    if not container or not container.persistent or not Nexus.DB.available then return end

    local payload = {}
    for slot, item in pairs(container.items) do
        payload[#payload + 1] = {
            slot, item.name, item.amount, item.metadata and Nexus.Utils.encodeJson(item.metadata) or nil,
        }
    end

    -- one transaction: wipe the owner's rows, insert the current state
    Nexus.DB.update('DELETE FROM nx_inventory WHERE owner = ?', { container.owner })

    if #payload > 0 then
        local values, params = {}, {}
        for _, entry in ipairs(payload) do
            values[#values + 1] = '(?, ?, ?, ?, ?)'
            params[#params + 1] = container.owner
            params[#params + 1] = entry[2]
            params[#params + 1] = entry[3]
            params[#params + 1] = entry[1]
            params[#params + 1] = entry[4]
        end
        Nexus.DB.update(
            ('INSERT INTO nx_inventory (owner, name, amount, slot, metadata) VALUES %s'):format(table.concat(values, ',')),
            params
        )
    end

    container.dirty = false
end

function Containers.unload(owner, save)
    local container = memory[owner]
    if not container then return end
    if save ~= false then
        Containers.save(container)
    end
    memory[owner] = nil
end

--- Save every container (resource stop, /save).
function Containers.saveAll()
    for _, container in pairs(memory) do
        Containers.save(container)
    end
end

--- Containers that are created at runtime and should not survive a restart.
function Containers.sweepDrops()
    local removed = 0
    for owner, container in pairs(memory) do
        if container.kind == 'drop' then
            local expires = container.meta and container.meta.expires
            if expires and expires < now() then
                for _, item in pairs(container.items) do
                    TriggerEvent('nexus:inventory:dropExpired', owner, item)
                end
                Nexus.DB.update('DELETE FROM nx_inventory WHERE owner = ?', { owner })
                memory[owner] = nil
                TriggerClientEvent('nexus:client:removeDrop', -1, container.id)
                removed = removed + 1
            end
        end
    end
    return removed
end

-- ===========================================================================
--  QUERIES
-- ===========================================================================

--- Current total weight in grams.
function Containers.getWeight(container)
    local total = 0
    for _, item in pairs(container.items) do
        total = total + InvUtil.itemWeight(item.name, item.metadata, item.amount)
    end
    return total
end

function Containers.getMaxWeight(container)
    local bonus = 0
    -- backpacks extend the limit while carried
    if container.kind == 'char' and InvConfig.backpackWeight then
        for _, item in pairs(container.items) do
            local capacity = (Nexus.Items[item.name] or {}).metadata
            if capacity and capacity.capacity then
                bonus = bonus + (capacity.capacity * (item.amount or 1))
            end
        end
    end
    return container.weight + bonus
end

function Containers.freeWeight(container)
    return math.max(0, Containers.getMaxWeight(container) - Containers.getWeight(container))
end

function Containers.countItem(container, name)
    local total = 0
    for _, item in pairs(container.items) do
        if item.name == name then total = total + item.amount end
    end
    return total
end

function Containers.hasItem(container, name, amount)
    return Containers.countItem(container, name) >= (amount or 1)
end

function Containers.findItem(container, name)
    for slot, item in pairs(container.items) do
        if item.name == name then return item, slot end
    end
    return nil
end

function Containers.countItems(container)
    local total = 0
    for _ in pairs(container.items) do total = total + 1 end
    return total
end

function Containers.freeSlots(container)
    return container.slots - Containers.countItems(container)
end

--- Next empty slot number, or nil when the container is full.
function Containers.nextFreeSlot(container)
    for slot = 1, container.slots do
        if not container.items[slot] then return slot end
    end
    return nil
end

function Containers.canCarry(container, name, amount, metadata)
    local def = Nexus.Items[name]
    if not def then return false, 'unknown_item' end

    amount = tonumber(amount) or 1
    if amount <= 0 then return false, 'invalid_amount' end

    local addedWeight = InvUtil.itemWeight(name, metadata, amount)
    if addedWeight > Containers.freeWeight(container) then
        return false, 'weight'
    end

    if def.stack == false or metadata ~= nil then
        -- one slot per unit
        if Containers.freeSlots(container) < amount then
            return false, 'slots'
        end
    else
        -- stackable: does it fit in an existing partial stack or a free slot?
        local needed = 0
        local maxStack = 10000
        for _, item in pairs(container.items) do
            if item.name == name and item.amount < maxStack then
                needed = needed - (maxStack - item.amount)
            end
        end
        if needed < amount and Containers.freeSlots(container) < 1 then
            return false, 'slots'
        end
        -- exact check: how many slots would the remainder need
        local remaining = amount - math.max(0, -needed)
        if remaining > 0 then
            local slotsNeeded = math.ceil(remaining / maxStack)
            if Containers.freeSlots(container) < slotsNeeded then
                return false, 'slots'
            end
        end
    end

    return true
end

-- ===========================================================================
--  MUTATIONS
-- ===========================================================================

---@return boolean ok, number|string addedOrError
function Containers.addItem(container, name, amount, metadata, slot)
    local def = Nexus.Items[name]
    if not def then
        Nexus.Print.warn('addItem: unknown item "%s"', tostring(name))
        return false, 'unknown_item'
    end

    amount = tonumber(amount) or 1
    if amount <= 0 then return false, 'invalid_amount' end

    local can, reason = Containers.canCarry(container, name, amount, metadata)
    if not can then return false, reason end

    local remaining = amount

    -- 1. top up matching stacks
    if def.stack ~= false and metadata == nil then
        for targetSlot = 1, container.slots do
            local item = container.items[targetSlot]
            if item and item.name == name and InvUtil.metadataMatches(item.metadata, nil) then
                local space = 10000 - item.amount
                if space > 0 then
                    local move = math.min(space, remaining)
                    item.amount = item.amount + move
                    item.weight = InvUtil.itemWeight(name, item.metadata, item.amount)
                    remaining = remaining - move
                    if remaining <= 0 then
                        Containers.markDirty(container)
                        return true, amount
                    end
                end
            end
        end
    end

    -- 2. place the rest in the requested slot or the first free one
    while remaining > 0 do
        local targetSlot = slot
        if not targetSlot or container.items[targetSlot] then
            targetSlot = Containers.nextFreeSlot(container)
        end
        if not targetSlot then break end

        local stackSize = (def.stack == false or metadata ~= nil) and 1 or math.min(remaining, 10000)
        container.items[targetSlot] = {
            slot = targetSlot,
            name = name,
            amount = stackSize,
            metadata = metadata,
            weight = InvUtil.itemWeight(name, metadata, stackSize),
        }
        remaining = remaining - stackSize
        slot = nil
    end

    Containers.markDirty(container)

    local added = amount - remaining
    if added <= 0 then
        return false, 'slots'
    end

    TriggerEvent('nexus:inventory:itemAdded', container, name, added, metadata)
    return true, added
end

--- Removes up to `amount` of an item. Returns how many were actually removed.
function Containers.removeItem(container, name, amount, metadata)
    amount = tonumber(amount) or 1
    if amount <= 0 then return 0 end

    local removed = 0

    -- remove single-slot items first so partial stacks stay tidy
    local slots = {}
    for slot, item in pairs(container.items) do
        if item.name == name and InvUtil.metadataMatches(item.metadata, metadata) then
            slots[#slots + 1] = slot
        end
    end
    table.sort(slots)

    for _, slot in ipairs(slots) do
        if removed >= amount then break end
        local item = container.items[slot]
        if item then
            local take = math.min(item.amount, amount - removed)
            item.amount = item.amount - take
            removed = removed + take
            if item.amount <= 0 then
                container.items[slot] = nil
            else
                item.weight = InvUtil.itemWeight(name, item.metadata, item.amount)
            end
        end
    end

    if removed > 0 then
        Containers.markDirty(container)
        TriggerEvent('nexus:inventory:itemRemoved', container, name, removed, metadata)
    end
    return removed
end

--- Removes exactly one stack at a slot (used by drop/give/move).
function Containers.removeSlot(container, slot)
    local item = container.items[slot]
    if not item then return nil end
    container.items[slot] = nil
    Containers.markDirty(container)
    TriggerEvent('nexus:inventory:itemRemoved', container, item.name, item.amount, item.metadata)
    return item
end

function Containers.getSlot(container, slot)
    return container.items[slot]
end

--- Splits a stack in half (or into `amount` + rest).
function Containers.splitSlot(container, slot, amount)
    local item = container.items[slot]
    if not item or item.amount <= 1 then return false, 'nothing_to_split' end

    amount = math.floor(tonumber(amount) or math.floor(item.amount / 2))
    amount = math.max(1, math.min(amount, item.amount - 1))

    local freeSlot = Containers.nextFreeSlot(container)
    if not freeSlot then
        -- try to top up an existing partial stack instead
        local can, _ = Containers.canCarry(container, item.name, amount, item.metadata)
        if not can then return false, 'no_space' end
    end

    item.amount = item.amount - amount
    item.weight = InvUtil.itemWeight(item.name, item.metadata, item.amount)

    local targetSlot = freeSlot or Containers.nextFreeSlot(container)
    if not targetSlot and item.amount > 0 then
        -- we have no free slot: try stacking onto an existing stack of the same item
        local placed = Containers.addItem(container, item.name, amount, item.metadata)
        if not placed then
            -- roll back
            item.amount = item.amount + amount
            item.weight = InvUtil.itemWeight(item.name, item.metadata, item.amount)
            return false, 'no_space'
        end
        return true, nil
    end

    container.items[targetSlot] = {
        slot = targetSlot,
        name = item.name,
        amount = amount,
        metadata = item.metadata,
        weight = InvUtil.itemWeight(item.name, item.metadata, amount),
    }

    Containers.markDirty(container)
    return true, targetSlot
end

--- Moves a stack (or part of one) between containers/slots.
---@return boolean ok, string|nil error
function Containers.moveItem(fromContainer, fromSlot, toContainer, toSlot, amount)
    local item = fromContainer.items[fromSlot]
    if not item then return false, 'empty_slot' end

    amount = math.floor(tonumber(amount) or item.amount)
    amount = math.max(1, math.min(amount, item.amount))

    local target = toContainer.items[toSlot]

    -- simple case: same container, swap two slots
    if fromContainer == toContainer and target then
        fromContainer.items[fromSlot], fromContainer.items[toSlot] = target, item
        item.slot = toSlot
        target.slot = fromSlot
        Containers.markDirty(fromContainer)
        return true
    end

    -- merging into a compatible stack
    if target and target.name == item.name and InvUtil.metadataMatches(target.metadata, item.metadata)
        and (Nexus.Items[item.name] or {}).stack ~= false and target.metadata == nil then
        local space = 10000 - target.amount
        local move = math.min(space, amount)
        if move > 0 then
            local weightCheck, reason = Containers.canCarry(toContainer, item.name, move, item.metadata)
            -- target stack already exists so weight is the only concern
            if not weightCheck and reason == 'weight' then
                return false, 'weight'
            end
            target.amount = target.amount + move
            target.weight = InvUtil.itemWeight(target.name, target.metadata, target.amount)
            item.amount = item.amount - move
            if item.amount <= 0 then
                fromContainer.items[fromSlot] = nil
            else
                item.weight = InvUtil.itemWeight(item.name, item.metadata, item.amount)
            end
            Containers.markDirty(fromContainer)
            Containers.markDirty(toContainer)
            return true
        end
    end

    -- swapping with an occupied slot in another container
    if target and amount == item.amount then
        fromContainer.items[fromSlot] = target
        toContainer.items[toSlot] = item
        item.slot = toSlot
        target.slot = fromSlot
        Containers.markDirty(fromContainer)
        Containers.markDirty(toContainer)
        return true
    end

    if target then
        return false, 'slot_occupied'
    end

    -- plain move
    local can, reason = Containers.canCarry(toContainer, item.name, amount, item.metadata)
    if not can then return false, reason end

    if amount == item.amount then
        toContainer.items[toSlot] = item
        item.slot = toSlot
        fromContainer.items[fromSlot] = nil
    else
        item.amount = item.amount - amount
        item.weight = InvUtil.itemWeight(item.name, item.metadata, item.amount)
        toContainer.items[toSlot] = {
            slot = toSlot, name = item.name, amount = amount,
            metadata = item.metadata, weight = InvUtil.itemWeight(item.name, item.metadata, amount),
        }
    end

    Containers.markDirty(fromContainer)
    Containers.markDirty(toContainer)
    return true
end

--- Swaps the contents of two slots, wherever they live.
function Containers.swapSlots(aContainer, aSlot, bContainer, bSlot)
    local a, b = aContainer.items[aSlot], bContainer.items[bSlot]
    aContainer.items[aSlot], bContainer.items[bSlot] = b, a
    if a then a.slot = bSlot end
    if b then b.slot = aSlot end
    Containers.markDirty(aContainer)
    if bContainer ~= aContainer then Containers.markDirty(bContainer) end
end

--- Wipes a container (death, /clearinv).
function Containers.clear(container, keepUndroppable)
    local cleared = {}
    for slot, item in pairs(container.items) do
        if not (keepUndroppable and InvConfig.undroppable[item.name]) then
            cleared[#cleared + 1] = item
            container.items[slot] = nil
        end
    end
    Containers.markDirty(container, true)
    return cleared
end

--- Everything in the container as a plain array (drops, transfers).
function Containers.toList(container)
    local list = {}
    for _, item in pairs(container.items) do
        list[#list + 1] = item
    end
    table.sort(list, function(a, b) return a.slot < b.slot end)
    return list
end

-- ===========================================================================
--  PLAYER CONTAINER HELPERS
-- ===========================================================================

function Containers.forPlayer(source)
    local player = Nexus.GetPlayer(source)
    if not player or not player.charId then return nil end
    return Containers.load(InvUtil.charOwner(player.charId), {
        label = player:getName() .. "'s pockets",
        slots = InvConfig.playerSlots,
        weight = InvConfig.playerWeight,
    })
end

--- Applies a config-driven override for special containers (stashes from DB).
---@param stashId string
function Containers.openStash(source, stashId)
    local player = Nexus.GetPlayer(source)
    if not player then return nil, 'no_player' end

    local row = Nexus.DB.single('SELECT * FROM nx_stashes WHERE stash_id = ?', { stashId })
    if not row then return nil, 'unknown_stash' end

    -- permission: owned stashes need the matching job/gang, or are shared
    if row.owner and not row.is_shared then
        local isJobOwner = player.job.name == row.owner
        local isGangOwner = player.gang.name == row.owner
        if not (isJobOwner or isGangOwner) and not player:can('nexus.admin.inventory') then
            return nil, 'no_permission'
        end
    elseif row.is_shared == 2 then
        -- shared with the whole job, gated by grade 0 (locker rooms)
        if player.job.name ~= row.owner and not player:can('nexus.admin.inventory') then
            return nil, 'no_permission'
        end
    end

    local container = Containers.load(InvUtil.stashOwner(stashId), {
        label = row.label,
        slots = tonumber(row.slots) or InvConfig.stashSlots,
        weight = tonumber(row.weight) or InvConfig.stashWeight,
    })
    return container
end

-- Housekeeping ---------------------------------------------------------------

CreateThread(function()
    while true do
        Citizen.Wait(60000)
        Containers.sweepDrops()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Containers.saveAll()
end)
