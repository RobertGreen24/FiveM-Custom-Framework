--[[
    Nexus Framework :: nx_appearance/client/creator.lua
    The character creator. Works both for a brand new character (creation = true)
    and for editing an existing one (creation = false).
]]

Nexus = Nexus
local Client = Nexus.Client
local Appearance = Nexus.Appearance

local open = false
local creation = false
local preview = nil            -- the appearance table currently being edited
local cam = nil
local rotation = 0.0
local mode = 'creator'         -- 'creator' | 'clothes' | 'barber' | 'tattoo' | 'wardrobe'

local function defaultAppearance(model)
    return {
        model = model or AppearanceConfig.defaultModel,
        face = {
            shapeFirst = 0, shapeSecond = 0, skinFirst = 0, skinSecond = 0,
            shapeMix = 0.5, skinMix = 0.5, eyeColour = 0, hairColour = 0, hairHighlight = 0,
            noseWidth = 0.0, nosePeakHigh = 0.0, nosePeakSize = 0.0, noseBoneHigh = 0.0,
            nosePeakLower = 0.0, noseBoneTwist = 0.0, noseSize = 0.0, noseHeight = 0.0,
            cheekboneHigh = 0.0, cheekboneWidth = 0.0, cheekboneDepth = 0.0,
            eyeOpening = 0.0, lipThickness = 0.0, jawBoneWidth = 0.0, jawBoneBack = 0.0,
            chinBone = 0.0, chinBoneLength = 0.0, chinHole = 0.0, neckThickness = 0.0,
        },
        hair = 0, beard = 0, eyebrows = 0, makeup = 0, blush = 0, lipstick = 0,
        components = {}, props = {}, tattoos = {},
    }
end

local function currentGender()
    return (preview and preview.model == AppearanceConfig.femaleModel) and 'female' or 'male'
end

--- Camera sits in front of the ped and orbits slowly.
local function startCamera()
    if not AppearanceConfig.creatorCamera then return end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        coords.x, coords.y, coords.z + 0.65, 0.0, 0.0, 0.0, 50.0, false, 0)
    PointCamAtCoord(cam, coords.x, coords.y, coords.z + 0.35)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 500, true, true)
end

local function stopCamera()
    if not cam then return end
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(cam, false)
    cam = nil
end

local function pushState()
    SendNUIMessage({
        action = 'update',
        data = {
            mode = mode,
            creation = creation,
            gender = currentGender(),
            appearance = preview,
            components = AppearanceConfig.components,
            props = AppearanceConfig.props,
            features = AppearanceConfig.faceFeatures,
            hairColours = AppearanceConfig.hairColours,
            eyeColours = AppearanceConfig.eyeColours,
            prices = {
                barber = AppearanceConfig.barberPrice,
                tattoo = AppearanceConfig.tattooPrice,
                save = AppearanceConfig.saveCost,
            },
        },
    })
end

Nexus.Appearance.pushState = pushState

local function setFocus(state)
    open = state
    SetNuiFocus(state, state)
    TriggerEvent('nexus:client:setUIOpen', state)
    SendNUIMessage({ action = state and 'open' or 'close', data = { mode = mode, creation = creation } })
    if state then
        FreezeEntityPosition(PlayerPedId(), true)
        startCamera()
        pushState()
    else
        FreezeEntityPosition(PlayerPedId(), false)
        stopCamera()
    end
end

Nexus.Appearance.setFocus = setFocus
Nexus.Appearance.isOpen = function() return open end

--- Opens the creator / editor.
---@param charId number|nil
---@param opts table|nil  { mode = 'creator'|'clothes'|'barber'|'tattoo'|'wardrobe', creation = bool }
function Appearance.openEditor(charId, opts)
    opts = opts or {}
    mode = opts.mode or 'creator'
    creation = opts.creation == true or opts.mode == 'creator'

    local existing = Appearance.getCurrent()
    local stored = Client.getData() and Client.getData().appearance
    preview = Nexus.Utils.deepCopy(existing or stored or defaultAppearance())

    -- in the creator the ped always starts from the default model of its gender
    if mode == 'creator' then
        preview.model = preview.model or AppearanceConfig.defaultModel
    end

    setFocus(true)
end

RegisterNetEvent('nexus:client:appearance:create', function(charId)
    Appearance.openEditor(charId, { mode = 'creator', creation = true })
end)

RegisterCommand(AppearanceConfig.command, function()
    if open then
        setFocus(false)
        return
    end
    if not Client.isLoaded() then return end
    Appearance.openEditor(Client.getCharId(), { mode = 'creator', creation = false })
end, false)

-- ===========================================================================
--  LIVE PREVIEW
-- ===========================================================================

local function applyPreview(keepModel)
    if not preview then return end
    Appearance.apply(preview, keepModel)
end

local function setGender(gender)
    if not preview then return end
    preview.model = gender == 'female' and AppearanceConfig.femaleModel or AppearanceConfig.defaultModel
    applyPreview(false)
    pushState()
end

--- Thread that slowly rotates the ped so the creator feels alive.
CreateThread(function()
    while true do
        Citizen.Wait(0)
        if open and cam then
            rotation = (rotation + 0.25) % 360.0
            local ped = PlayerPedId()
            SetEntityHeading(ped, rotation)

            local coords = GetEntityCoords(ped)
            SetCamCoord(cam, coords.x, coords.y, coords.z + 0.65)
            PointCamAtCoord(cam, coords.x, coords.y, coords.z + 0.35)
        end
    end
end)

CreateThread(function()
    while true do
        Citizen.Wait(open and 0 or 400)
        if open then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 36, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 45, true)
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)
        end
    end
end)

-- ===========================================================================
--  NUI CALLBACKS
-- ===========================================================================

RegisterNUICallback('nx:close', function(_, cb)
    cb({ ok = true })
    setFocus(false)
end)

RegisterNUICallback('nx:gender', function(payload, cb)
    cb({ ok = true })
    setGender(payload.gender)
end)

--- A single face feature slider moved.
RegisterNUICallback('nx:feature', function(payload, cb)
    cb({ ok = true })
    if not preview then return end
    preview.face = preview.face or {}
    preview.face[payload.key] = tonumber(payload.value) or 0.0
    applyPreview(true)
end)

--- Head blend (parents) and colour updates.
RegisterNUICallback('nx:blend', function(payload, cb)
    cb({ ok = true })
    if not preview then return end
    preview.face = preview.face or {}

    if payload.face then
        for key, value in pairs(payload.face) do
            preview.face[key] = tonumber(value) or preview.face[key]
        end
    end
    applyPreview(true)
end)

--- Hair / overlay / colour change.
RegisterNUICallback('nx:style', function(payload, cb)
    cb({ ok = true })
    if not preview then return end

    if payload.hair ~= nil then preview.hair = tonumber(payload.hair) or 0 end
    if payload.beard ~= nil then preview.beard = tonumber(payload.beard) or 0 end
    if payload.eyebrows ~= nil then preview.eyebrows = tonumber(payload.eyebrows) or 0 end
    if payload.makeup ~= nil then preview.makeup = tonumber(payload.makeup) or 0 end
    if payload.blush ~= nil then preview.blush = tonumber(payload.blush) or 0 end
    if payload.lipstick ~= nil then preview.lipstick = tonumber(payload.lipstick) or 0 end

    preview.face = preview.face or {}
    if payload.hairColour ~= nil then preview.face.hairColour = tonumber(payload.hairColour) or 0 end
    if payload.hairHighlight ~= nil then preview.face.hairHighlight = tonumber(payload.hairHighlight) or 0 end
    if payload.eyeColour ~= nil then preview.face.eyeColour = tonumber(payload.eyeColour) or 0 end

    applyPreview(true)
end)

--- Clothing component change from the creator or a shop.
RegisterNUICallback('nx:component', function(payload, cb)
    cb({ ok = true })
    if not preview then return end

    preview.components = preview.components or {}
    local id = tonumber(payload.id)
    local found = false

    for _, component in ipairs(preview.components) do
        if tonumber(component.id) == id then
            component.drawable = tonumber(payload.drawable) or 0
            component.texture = tonumber(payload.texture) or 0
            found = true
        end
    end
    if not found then
        preview.components[#preview.components + 1] = {
            id = id,
            drawable = tonumber(payload.drawable) or 0,
            texture = tonumber(payload.texture) or 0,
        }
    end

    SetPedComponentVariation(PlayerPedId(), id,
        tonumber(payload.drawable) or 0, tonumber(payload.texture) or 0, 0)
end)

--- Prop (hat/glasses/watch) change.
RegisterNUICallback('nx:prop', function(payload, cb)
    cb({ ok = true })
    if not preview then return end

    preview.props = preview.props or {}
    local id = tonumber(payload.id)

    if payload.drawable == nil or tonumber(payload.drawable) < 0 then
        ClearPedProp(PlayerPedId(), id)
        for index, prop in ipairs(preview.props) do
            if tonumber(prop.id) == id then
                table.remove(preview.props, index)
                break
            end
        end
        return
    end

    local found = false
    for _, prop in ipairs(preview.props) do
        if tonumber(prop.id) == id then
            prop.drawable = tonumber(payload.drawable) or 0
            prop.texture = tonumber(payload.texture) or 0
            found = true
        end
    end
    if not found then
        preview.props[#preview.props + 1] = {
            id = id,
            drawable = tonumber(payload.drawable) or 0,
            texture = tonumber(payload.texture) or 0,
        }
    end

    SetPedPropIndex(PlayerPedId(), id, tonumber(payload.drawable) or 0, tonumber(payload.texture) or 0, true)
end)

--- Randomised appearance (the "surprise me" button).
RegisterNUICallback('nx:random', function(_, cb)
    cb({ ok = true })
    if not preview then return end

    preview.face.shapeFirst = math.random(0, 45)
    preview.face.shapeSecond = math.random(0, 45)
    preview.face.skinFirst = math.random(0, 45)
    preview.face.skinSecond = math.random(0, 45)
    preview.face.shapeMix = math.random() * 1.0
    preview.face.skinMix = math.random() * 1.0
    preview.face.hairColour = math.random(0, #AppearanceConfig.hairColours - 1)
    preview.face.eyeColour = math.random(0, #AppearanceConfig.eyeColours - 1)
    preview.hair = math.random(0, 20)
    preview.beard = math.random(0, 10)

    for _, feature in ipairs(AppearanceConfig.faceFeatures) do
        preview.face[feature.key] = (math.random() * 2 - 1) * 0.6
    end

    applyPreview(true)
    pushState()
end)

--- Save & finish.
RegisterNUICallback('nx:save', function(payload, cb)
    cb({ ok = true })
    if not preview then return end

    -- optional outfit name when saving from the wardrobe
    if payload and payload.capture then
        preview = Appearance.capture()
    end

    applyPreview(false)
    TriggerServerEvent('nx_appearance:save', preview, creation)

    if creation then
        -- nx_core finishes the creation: saves, sets the spawn and fades in
        TriggerServerEvent('nexus:server:creationComplete', preview)
        creation = false
    end

    setFocus(false)
end)

--- Saving the current look as a named outfit.
RegisterNUICallback('nx:saveOutfit', function(payload, cb)
    cb({ ok = true })
    local outfit = Appearance.capture()
    TriggerServerEvent('nx_appearance:saveOutfit', payload.name or ('Outfit %s'):format(os.date('%H:%M')), outfit)
end)

--- Wearing a saved outfit by id.
RegisterNUICallback('nx:wearOutfit', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_appearance:wearOutfit', payload.id)
end)

RegisterNUICallback('nx:deleteOutfit', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_appearance:deleteOutfit', payload.id)
end)

--- Leaving a paid shop service (clothes / barber / tattoo).
RegisterNUICallback('nx:checkout', function(payload, cb)
    cb({ ok = true })
    if not preview then return end

    local kind = payload.kind or mode
    local amount = tonumber(payload.amount) or 0

    -- charges first; the server replies with paymentOk/paymentFailed
    TriggerServerEvent('nx_appearance:pay', kind, amount)
end)

RegisterNetEvent('nx_appearance:paymentOk', function(kind)
    if not preview then return end
    applyPreview(false)
    TriggerServerEvent('nx_appearance:save', preview, false)
    Nexus.Notify(('%s purchase complete.'):format(kind or 'Clothing'), 'success')
    setFocus(false)
end)

RegisterNetEvent('nx_appearance:paymentFailed', function()
    Nexus.Notify('Not enough money.', 'error')
end)

--- Outfit list requested by the wardrobe tab.
RegisterNetEvent('nexus:client:appearance:outfits', function(outfits)
    SendNUIMessage({ action = 'outfits', data = outfits })
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if open then SetNuiFocus(false, false) end
    stopCamera()
end)
