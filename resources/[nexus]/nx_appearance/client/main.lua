--[[
    Nexus Framework :: nx_appearance (client)
    Applies saved appearances and job uniforms to the local ped.
]]

Nexus = Nexus
local Client = Nexus.Client

Nexus.Appearance = Nexus.Appearance or {}
local Appearance = Nexus.Appearance

local current = nil

--- Face feature indices used by SetPedFaceFeature (0-19).
local FACE_ORDER = {
    'noseWidth', 'nosePeakHigh', 'nosePeakSize', 'noseBoneHigh', 'nosePeakLower',
    'noseBoneTwist', 'noseSize', 'noseHeight', 'cheekboneHigh', 'cheekboneWidth',
    'cheekboneDepth', 'eyeOpening', 'lipThickness', 'jawBoneWidth', 'jawBoneBack',
    'chinBone', 'chinBoneLength', 'chinHole', 'neckThickness',
}

local function loadModel(model)
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Citizen.Wait(10)
    end
    return HasModelLoaded(hash)
end

Appearance.loadModel = loadModel

--- Applies an appearance table to the local player. `keepModel` skips the ped
--- model swap (used when only clothing changed).
function Appearance.apply(data, keepModel)
    if type(data) ~= 'table' then return end
    current = data

    local ped = PlayerPedId()
    local model = data.model or AppearanceConfig.defaultModel
    if not keepModel and GetEntityModel(ped) ~= GetHashKey(model) then
        if loadModel(model) then
            SetPlayerModel(PlayerId(), GetHashKey(model))
            SetModelAsNoLongerNeeded(GetHashKey(model))
            ped = PlayerPedId()
        end
    end

    local face = data.face or {}

    -- head blend
    SetPedHeadBlendData(ped,
        face.shapeFirst or 0, face.shapeSecond or 0, 0,
        face.skinFirst or 0, face.skinSecond or 0, 0,
        face.shapeMix or 0.5, face.skinMix or 0.5, 0.0, false)

    -- face features
    for index, key in ipairs(FACE_ORDER) do
        SetPedFaceFeature(ped, index - 1, tonumber(face[key]) or 0.0)
    end

    -- hair + colours
    SetPedComponentVariation(ped, 2, tonumber(data.hair) or 0, 0, 0)
    SetPedHairColor(ped, tonumber(face.hairColour) or 0, tonumber(face.hairHighlight) or 0)
    SetPedEyeColour(ped, tonumber(face.eyeColour) or 0)

    -- overlays: 1 beard, 2 eyebrows, 4 makeup, 5 blush, 8 lipstick
    local overlays = {
        { 1, data.beard, face.beardOpacity },
        { 2, data.eyebrows, face.eyebrowOpacity },
        { 4, data.makeup, face.makeupOpacity },
        { 5, data.blush, face.blushOpacity },
        { 8, data.lipstick, face.lipstickOpacity },
        { 10, data.facialHair, face.facialHairOpacity },
    }
    for _, overlay in ipairs(overlays) do
        local id, value, opacity = overlay[1], overlay[2], overlay[3]
        if value ~= nil then
            SetPedHeadOverlay(ped, id, tonumber(value) or 0, tonumber(opacity) or 1.0)
        end
    end
    SetPedHeadOverlayColor(ped, 1, 1, tonumber(face.hairColour) or 0, tonumber(face.hairColour) or 0)
    SetPedHeadOverlayColor(ped, 2, 1, tonumber(face.hairColour) or 0, tonumber(face.hairColour) or 0)

    -- components (clothing)
    for _, component in ipairs(data.components or {}) do
        SetPedComponentVariation(ped, tonumber(component.id) or 0,
            tonumber(component.drawable) or 0, tonumber(component.texture) or 0, 0)
    end

    -- props (hats, glasses, watches)
    for slot = 0, 7 do
        ClearPedProp(ped, slot)
    end
    for _, prop in ipairs(data.props or {}) do
        SetPedPropIndex(ped, tonumber(prop.id) or 0,
            tonumber(prop.drawable) or 0, tonumber(prop.texture) or 0, true)
    end

    -- tattoos need a decoration pack; store them for the tattooist UI
    if data.tattoos and #data.tattoos > 0 then
        for _, tattoo in ipairs(data.tattoos) do
            if tattoo.collection and tattoo.overlay then
                AddPedDecorationFromHashes(ped, joaat(tattoo.collection), joaat(tattoo.overlay))
            end
        end
    end
end

--- Reads the current ped back into an appearance table (creator + shops).
function Appearance.capture()
    local ped = PlayerPedId()
    local data = {
        model = GetEntityModel(ped) == GetHashKey(AppearanceConfig.femaleModel)
            and AppearanceConfig.femaleModel or AppearanceConfig.defaultModel,
        face = {},
        components = {},
        props = {},
        tattoos = current and current.tattoos or {},
    }

    data.hair = GetPedDrawableVariation(ped, 2)
    data.beard = GetPedHeadOverlayValue(ped, 1)
    data.eyebrows = GetPedHeadOverlayValue(ped, 2)
    data.makeup = GetPedHeadOverlayValue(ped, 4)
    data.blush = GetPedHeadOverlayValue(ped, 5)
    data.lipstick = GetPedHeadOverlayValue(ped, 8)
    data.facialHair = data.beard

    for index, key in ipairs(FACE_ORDER) do
        data.face[key] = GetPedFaceFeature(ped, index - 1)
    end

    local ok, shapeFirst, shapeSecond, shapeThird, skinFirst, skinSecond, skinThird, shapeMix, skinMix, thirdMix =
        GetPedHeadBlendData(ped)
    if ok then
        data.face.shapeFirst = shapeFirst
        data.face.shapeSecond = shapeSecond
        data.face.skinFirst = skinFirst
        data.face.skinSecond = skinSecond
        data.face.shapeMix = shapeMix
        data.face.skinMix = skinMix
        data.face.thirdMix = thirdMix
    end

    local hairColour, hairHighlight = GetPedHairColor(ped)
    data.face.hairColour = hairColour
    data.face.hairHighlight = hairHighlight
    data.face.eyeColour = GetPedEyeColour(ped)

    for _, component in ipairs(AppearanceConfig.components) do
        data.components[#data.components + 1] = {
            id = component.id,
            drawable = GetPedDrawableVariation(ped, component.id),
            texture = GetPedTextureVariation(ped, component.id),
        }
    end

    for _, prop in ipairs(AppearanceConfig.props) do
        if GetPedPropIndex(ped, prop.id) ~= -1 then
            data.props[#data.props + 1] = {
                id = prop.id,
                drawable = GetPedPropIndex(ped, prop.id),
                texture = GetPedPropTextureIndex(ped, prop.id),
            }
        end
    end

    return data
end

function Appearance.getCurrent() return current end

-- ===========================================================================
--  EVENTS
-- ===========================================================================

--- The appearance rides along with the player data payload.
local function storedAppearance()
    local data = Client.getData()
    return data and data.appearance or nil
end

RegisterNetEvent('nexus:client:playerLoaded', function()
    local data = storedAppearance()
    if data then Appearance.apply(data) end
end)

RegisterNetEvent('nexus:client:playerData', function()
    local data = storedAppearance()
    if data and not current then Appearance.apply(data) end
end)

RegisterNetEvent('nexus:client:appearance:apply', function(outfit, keepModel)
    Appearance.apply(outfit, keepModel)
end)

RegisterNetEvent('nexus:client:appearance:uniform', function(jobName)
    local uniform = AppearanceConfig.uniforms[jobName]
    if not uniform then
        Nexus.Notify('No uniform set for that job.', 'error')
        return
    end

    local gender = GetEntityModel(PlayerPedId()) == GetHashKey(AppearanceConfig.femaleModel) and 'female' or 'male'
    local set = uniform[gender] or uniform.male
    if not set then return end

    for _, component in ipairs(set.components or {}) do
        SetPedComponentVariation(PlayerPedId(), component.id, component.drawable, component.texture or 0, 0)
    end
    Nexus.Notify('Uniform equipped.', 'success', 5000)
end)

--- The creator hands us the saved table so future outfits keep the face.
exports('applyAppearance', function(data, keepModel) Appearance.apply(data, keepModel) end)
exports('captureAppearance', function() return Appearance.capture() end)
exports('getAppearance', function() return current end)

--- Re-apply the stored appearance to the current ped (e.g. after being revived).
RegisterNetEvent('nexus:client:appearance:refresh', function()
    local data = storedAppearance() or current
    if data then Appearance.apply(data, true) end
end)
