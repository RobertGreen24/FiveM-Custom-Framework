--[[
    Nexus Framework :: nx_appearance (server)
    Persistence for appearances, outfits and job uniforms.
]]

Nexus = Nexus or {}

-- ===========================================================================
--  APPEARANCE
-- ===========================================================================

RegisterNetEvent('nx_appearance:save', function(appearance, creation)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    if type(appearance) ~= 'table' then return end

    -- only accept known-ish keys to keep the JSON tidy
    local clean = {
        model      = appearance.model,
        face       = appearance.face,
        hair       = appearance.hair,
        facialHair = appearance.facialHair,
        eyebrows   = appearance.eyebrows,
        makeup     = appearance.makeup,
        blush      = appearance.blush,
        lipstick   = appearance.lipstick,
        beard      = appearance.beard,
        components = appearance.components or {},
        props      = appearance.props or {},
        tattoos    = appearance.tattoos or {},
    }

    Nexus.Characters.saveAppearance(player, clean)
    player:setMeta('appearanceSaved', os.time())

    if creation then
        TriggerEvent('nexus:server:creationComplete', player)
    end

    player:notify(creation and 'Welcome to Los Santos.' or 'Appearance saved.', 'success', 6000)
end)

--- Other resources (clothing shops, uniforms) can save too.
Nexus.SaveAppearance = function(source, appearance)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return false end
    Nexus.Characters.saveAppearance(player, appearance)
    player:setMeta('appearanceSaved', os.time())
    return true
end

exports('saveAppearance', function(source, appearance) return Nexus.SaveAppearance(source, appearance) end)

exports('getAppearance', function(source)
    local player = Nexus.GetPlayer(source)
    if not player then return nil end
    return player.appearance
end)

-- ===========================================================================
--  OUTFITS
-- ===========================================================================

local function outfitCount(charId)
    return tonumber(Nexus.DB.scalar('SELECT COUNT(*) FROM nx_outfits WHERE char_id = ?', { charId })) or 0
end

--- Lists the player's saved outfits for the wardrobe UI.
RegisterNetEvent('nx_appearance:requestOutfits', function()
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local outfits = Nexus.DB.query(
        'SELECT id, name, created_at FROM nx_outfits WHERE char_id = ? ORDER BY id DESC LIMIT ?',
        { player.charId, AppearanceConfig.outfitSlots })
    TriggerClientEvent('nx_appearance:outfitList', source, outfits or {})
end)

RegisterNetEvent('nx_appearance:saveOutfit', function(name, outfit)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    name = tostring(name or ''):sub(1, 48)
    if name == '' or type(outfit) ~= 'table' then return end

    if outfitCount(player.charId) >= AppearanceConfig.outfitSlots then
        player:notify('Your wardrobe is full.', 'error')
        return
    end

    Nexus.DB.insert('INSERT INTO nx_outfits (char_id, name, data) VALUES (?, ?, ?)', {
        player.charId, name, Nexus.Utils.encodeJson(outfit),
    })
    player:notify(('Saved outfit "%s".'):format(name), 'success')
end)

RegisterNetEvent('nx_appearance:deleteOutfit', function(outfitId)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    Nexus.DB.update('DELETE FROM nx_outfits WHERE id = ? AND char_id = ?', { tonumber(outfitId) or 0, player.charId })
    player:notify('Outfit deleted.', 'info')
end)

RegisterNetEvent('nx_appearance:wearOutfit', function(outfitId)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local row = Nexus.DB.single('SELECT * FROM nx_outfits WHERE id = ? AND char_id = ?', { tonumber(outfitId) or 0, player.charId })
    if not row then
        player:notify('Outfit not found.', 'error')
        return
    end

    local outfit = Nexus.Utils.decodeJson(row.data)
    if not outfit then
        player:notify('That outfit is corrupted.', 'error')
        return
    end

    TriggerClientEvent('nexus:client:appearance:apply', source, outfit, false)
    player:notify(('Wearing "%s".'):format(row.name), 'success')
end)

--- Pushes a job uniform to a player (no appearance save).
RegisterNetEvent('nx_appearance:setUniform', function(jobName)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end
    if jobName and jobName ~= player.job.name then
        player:notify('That uniform is not yours.', 'error')
        return
    end
    TriggerClientEvent('nexus:client:appearance:uniform', source, player.job.name)
end)

Nexus.SetUniform = function(source, jobName) TriggerEvent('nx_appearance:setUniform', source, jobName) end

exports('setUniform', function(source, jobName) TriggerEvent('nx_appearance:setUniform', source, jobName) end)

-- ===========================================================================
--  SHOP PAYMENTS (clothing / barber / tattoo)
-- ===========================================================================

--- Charges for a shop service. kind = 'clothes' | 'barber' | 'tattoo' | 'wardrobe'
RegisterNetEvent('nx_appearance:pay', function(kind, amount, details)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    kind = tostring(kind or 'clothes')
    amount = math.max(0, math.floor(tonumber(amount) or 0))

    if amount > 0 then
        local paid = player:removeMoney('bank', amount, ('%s fees'):format(kind))
        if not paid then
            paid = player:removeMoney('cash', amount, ('%s fees'):format(kind))
        end
        if not paid then
            player:notify('You cannot afford that.', 'error')
            TriggerClientEvent('nx_appearance:paymentFailed', source)
            return
        end
        Nexus.Log.action('appearance_purchase', {
            actor = player:getName(), details = ('%s · %s'):format(kind, Nexus.Utils.formatMoney(amount)),
        })
    end

    TriggerClientEvent('nx_appearance:paymentOk', source, kind, amount, details)
end)

exports('charge', function(source, kind, amount, details) TriggerEvent('nx_appearance:pay', source, kind, amount, details) end)
