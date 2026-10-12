--[[
    Nexus Framework :: nx_inventory/shared/utils.lua
    Helpers shared by the inventory's client and server halves.
]]

InvUtil = {}

--- Weight of a single unit of an item (grams), including metadata overrides.
function InvUtil.itemWeight(name, metadata, amount)
    local def = Nexus.Items[name]
    local weight = def and def.weight or 100

    -- weapon attachments / scopes add weight
    if metadata and metadata.attachments then
        local count = 0
        for _ in pairs(metadata.attachments) do count = count + 1 end
        weight = weight + (count * 250)
    end

    return weight * (tonumber(amount) or 1)
end

--- The two stacks are "the same" when name and metadata match.
function InvUtil.metadataMatches(a, b)
    if (a == nil) ~= (b == nil) then return false end
    if a == nil then return true end
    return Nexus.Utils.deepEqual(a, b)
end

--- Label to show in the UI (accounts for weapon metadata like the custom name).
function InvUtil.displayLabel(item)
    if not item then return '' end
    local def = Nexus.Items[item.name]
    local label = def and def.label or item.name

    if item.metadata and item.metadata.label then
        label = item.metadata.label
    end
    if item.metadata and item.metadata.serial then
        label = ('%s [%s]'):format(label, item.metadata.serial)
    end
    return label
end

--- The client-facing shape of a stack.
function InvUtil.serialise(item)
    if not item then return nil end
    local def = Nexus.Items[item.name] or {}
    return {
        slot = item.slot,
        name = item.name,
        label = InvUtil.displayLabel(item),
        description = def.description or '',
        amount = item.amount,
        weight = item.weight,
        stack = def.stack ~= false,
        type = def.type or 'item',
        rarity = def.rarity or 'common',
        usable = def.usable == true,
        image = def.image,
        metadata = item.metadata,
        ammoItem = def.ammoItem,
        weaponType = def.weaponType,
    }
end

--- Container id helpers -------------------------------------------------------
function InvUtil.charOwner(charId) return ('char:%s'):format(charId) end
function InvUtil.trunkOwner(plate) return ('trunk:%s'):format(plate) end
function InvUtil.gloveOwner(plate) return ('glove:%s'):format(plate) end
function InvUtil.stashOwner(stashId) return ('stash:%s'):format(stashId) end
function InvUtil.dropOwner(dropId) return ('drop:%s'):format(dropId) end
function InvUtil.shopOwner(shopId) return ('shop:%s'):format(shopId) end

--- Parses "trunk:ABC123" into { type = 'trunk', id = 'ABC123' }
function InvUtil.parseOwner(owner)
    if type(owner) ~= 'string' then return nil end
    local kind, id = owner:match('^([%w_]+):(.+)$')
    if not kind then return nil end
    return { type = kind, id = id }
end

--- The container config for a given owner type.
function InvConfigFor(kind)
    if kind == 'char' then
        return { slots = InvConfig.playerSlots, weight = InvConfig.playerWeight, persistent = true, label = 'Inventory' }
    elseif kind == 'trunk' then
        return { slots = InvConfig.trunkSlots, weight = InvConfig.trunkWeight, persistent = true, label = 'Trunk' }
    elseif kind == 'glove' then
        return { slots = InvConfig.gloveboxSlots, weight = InvConfig.gloveboxWeight, persistent = true, label = 'Glovebox' }
    elseif kind == 'stash' then
        return { slots = InvConfig.stashSlots, weight = InvConfig.stashWeight, persistent = true, label = 'Stash' }
    elseif kind == 'drop' then
        return { slots = InvConfig.dropSlots, weight = InvConfig.dropWeight, persistent = true, label = 'Ground' }
    elseif kind == 'shop' then
        return { slots = 60, weight = 1000000, persistent = false, label = 'Shop' }
    end
    return { slots = 20, weight = 20000, persistent = false, label = 'Container' }
end
