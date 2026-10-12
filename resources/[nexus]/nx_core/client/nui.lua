--[[
    Nexus Framework :: client/nui.lua
    The shared UI kit every Nexus resource uses: toasts, progress rings, text UI,
    input prompts, confirm dialogs and context menus.

    Everything is callback based because NUI is asynchronous:

        Nexus.Notify('You bought a coffee', 'success')
        Nexus.Progress({ label = 'Drilling the safe', duration = 8000 }, function(completed)
            if completed then print('done') end
        end)
        Nexus.Input({ title = 'Fine amount', fields = { { name = 'amount', label = '$', type = 'number' } } }, function(values)
            print(values and values.amount)
        end)
]]

Nexus = Nexus or {}

local uiCallbacks = {}
local uiCounter = 0

local function nextId(prefix)
    uiCounter = uiCounter + 1
    return ('%s-%d'):format(prefix or 'ui', uiCounter)
end

--- Low level: push a message to the nx_core NUI frame.
function Nexus.SendUI(action, data)
    SendNUIMessage({ action = action, data = data or {} })
end

RegisterNUICallback('nx:response', function(payload, cb)
    cb({ ok = true })
    if type(payload) ~= 'table' then return end
    local id = payload.id
    local entry = id and uiCallbacks[id]
    if not entry then return end
    uiCallbacks[id] = nil
    if entry.timer then Citizen.ClearTimeout(entry.timer) end
    local ok, err = pcall(entry.cb, payload.value, payload)
    if not ok then
        Nexus.Print.error('UI callback for "%s" errored: %s', tostring(id), tostring(err))
    end
end)

local function await(id, timeout, cb)
    uiCallbacks[id] = { cb = cb }
    if timeout then
        uiCallbacks[id].timer = Citizen.SetTimeout(timeout, function()
            local entry = uiCallbacks[id]
            uiCallbacks[id] = nil
            if entry then entry.cb(nil, { timedOut = true }) end
        end)
    end
end

-- ===========================================================================
--  NOTIFICATIONS
-- ===========================================================================

---@param message string
---@param ntype string|nil info|success|warning|error|police|ems|money
---@param duration number|nil ms
---@param title string|nil
function Nexus.Notify(message, ntype, duration, title)
    if message == nil then return end
    Nexus.SendUI('notify', {
        id = nextId('notify'),
        title = title or (Config.FrameworkName or 'Nexus'),
        message = tostring(message),
        type = ntype or 'info',
        duration = duration or (Config.Notifications and Config.Notifications.defaultDuration) or 5000,
    })
end

--- Notify with an icon name understood by the NUI (font-awesome style names).
function Nexus.NotifyIcon(message, ntype, icon, duration, title)
    Nexus.SendUI('notify', {
        id = nextId('notify'),
        title = title or (Config.FrameworkName or 'Nexus'),
        message = tostring(message),
        type = ntype or 'info',
        icon = icon,
        duration = duration or 5000,
    })
end

AddEventHandler(Nexus.Events.NOTIFY, function(message, ntype, duration, title)
    Nexus.Notify(message, ntype, duration, title)
end)

-- ===========================================================================
--  TEXT UI (interaction prompts)
-- ===========================================================================

local textUIVisible = false

---@param show boolean
---@param key string  e.g. '[E]'
---@param label string
function Nexus.TextUI(show, key, label)
    show = show == true
    -- avoid spamming the frame with identical states
    if show == textUIVisible then
        if not show then return end
        if Nexus.lastTextUIKey == key and Nexus.lastTextUILabel == label then return end
    end
    textUIVisible = show
    Nexus.lastTextUIKey = key
    Nexus.lastTextUILabel = label
    Nexus.SendUI('textui', { show = show, key = key, label = label })
end

AddEventHandler(Nexus.Events.TEXT_UI, function(show, key, label)
    Nexus.TextUI(show, key, label)
end)

--- Convenience: show for `duration` ms then hide.
function Nexus.TextUITimed(key, label, duration)
    Nexus.TextUI(true, key, label)
    Citizen.SetTimeout(duration or 4000, function()
        Nexus.TextUI(false)
    end)
end

-- ===========================================================================
--  PROGRESS
-- ===========================================================================

local progressActive = false
local progressCancel = false

function Nexus.IsProgressActive()
    return progressActive
end

--- Cancels whatever progress bar is running (used by damage/interaction code).
function Nexus.CancelProgress()
    progressCancel = true
end

---@param opts table { label, duration, icon, canCancel, disableMovement, disableCombat, animation, prop, colour }
---@param cb function(completed:boolean)
function Nexus.Progress(opts, cb)
    if type(opts) == 'string' then
        opts = { label = opts }
    end

    if progressActive then
        if cb then cb(false) end
        return
    end

    opts.duration = math.max(250, tonumber(opts.duration) or 3000)
    opts.canCancel = opts.canCancel ~= false
    progressActive = true
    progressCancel = false

    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        local animation = opts.animation or { dict = 'mini@repair', name = 'fixing_a_ped', flag = 49 }
        local prop = nil

        if animation then
            RequestAnimDict(animation.dict)
            local timeout = GetGameTimer() + 2000
            while not HasAnimDictLoaded(animation.dict) and GetGameTimer() < timeout do Citizen.Wait(10) end
            TaskPlayAnim(ped, animation.dict, animation.name, 3.0, 3.0, -1, animation.flag or 49, 0, false, false, false)
        end
        if opts.prop then
            local model = GetHashKey(opts.prop)
            RequestModel(model)
            local timeout = GetGameTimer() + 2000
            while not HasModelLoaded(model) and GetGameTimer() < timeout do Citizen.Wait(10) end
            local coords = GetEntityCoords(ped)
            prop = CreateObject(model, coords.x, coords.y, coords.z + 0.2, true, true, false)
            AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, opts.propBone or 57005), 0.12, 0.0, 0.0, 0, 0, 0, true, true, false, true, 1, true)
        end

        Nexus.SendUI('progress', {
            id = nextId('progress'),
            label = opts.label or 'Working',
            duration = opts.duration,
            icon = opts.icon,
            colour = opts.colour,
        })

        local start = GetGameTimer()
        local completed = false
        local startCoords = GetEntityCoords(ped)

        while GetGameTimer() - start < opts.duration do
            Citizen.Wait(0)

            -- movement check
            if opts.disableMovement then
                DisableControlAction(0, 30, true)
                DisableControlAction(0, 31, true)
            end
            if opts.disableCombat then
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
            end

            if not DoesEntityExist(ped) or IsEntityDead(ped) then
                break
            end

            if opts.canCancel and (IsControlJustPressed(0, 73) or IsControlJustPressed(0, 177)) then
                break
            end

            if opts.disableMovement and #(GetEntityCoords(ped) - startCoords) > 2.0 then
                break
            end

            if progressCancel then break end

            if animation and not IsEntityPlayingAnim(ped, animation.dict, animation.name, 3) then
                TaskPlayAnim(ped, animation.dict, animation.name, 3.0, 3.0, -1, animation.flag or 49, 0, false, false, false)
            end
        end

        completed = (GetGameTimer() - start) >= opts.duration and not progressCancel

        if prop then DeleteObject(prop) end
        if animation then StopAnimTask(ped, animation.dict, animation.name, 1.0) end

        Nexus.SendUI('progressEnd', {})
        progressActive = false

        if cb then cb(completed) end
    end)
end

--- Coroutine-friendly wrapper so scripts can write linear code:
---     if not Nexus.ProgressSync({ label = 'Lockpicking', duration = 5000 }) then return end
function Nexus.ProgressSync(opts)
    local p = promise.new()
    Nexus.Progress(opts, function(completed) p:resolve(completed) end)
    return Citizen.Await(p)
end

-- ===========================================================================
--  INPUT / CONFIRM / MENU
-- ===========================================================================

---@param opts table { title, description, fields = { { name, label, type, value, placeholder, options, min, max } } }
---@param cb function(values|nil)
function Nexus.Input(opts, cb)
    local id = nextId('input')
    Nexus.SendUI('input', {
        id = id,
        title = opts.title or 'Input',
        description = opts.description,
        submitLabel = opts.submitLabel or 'Confirm',
        fields = opts.fields or {},
    })
    await(id, nil, cb)
end

---@param cb function(confirmed:boolean)
function Nexus.Confirm(opts, cb)
    if type(opts) == 'string' then
        opts = { title = 'Confirm', message = opts }
    end
    local id = nextId('confirm')
    Nexus.SendUI('confirm', {
        id = id,
        title = opts.title or 'Are you sure?',
        message = opts.message or '',
        confirmLabel = opts.confirmLabel or 'Confirm',
        cancelLabel = opts.cancelLabel or 'Cancel',
        danger = opts.danger == true,
    })
    await(id, 30000, function(value)
        if cb then cb(value == true) end
    end)
end

--- Context menu: opts.options = { { label, value, icon, description, disabled } }
function Nexus.Menu(opts, cb)
    local id = nextId('menu')
    Nexus.SendUI('menu', {
        id = id,
        title = opts.title or 'Menu',
        subtitle = opts.subtitle,
        options = opts.options or {},
    })
    await(id, nil, cb)
end

--- Closes any open core UI (called when the player dies, gets arrested, etc).
function Nexus.CloseUI()
    Nexus.SendUI('closeAll', {})
end

-- ===========================================================================
--  EXPORTS
-- ===========================================================================

exports('notify', function(message, ntype, duration, title) Nexus.Notify(message, ntype, duration, title) end)
exports('notifyIcon', function(message, ntype, icon, duration, title) Nexus.NotifyIcon(message, ntype, icon, duration, title) end)
exports('textUI', function(show, key, label) Nexus.TextUI(show, key, label) end)
exports('progress', function(label, duration, cb) Nexus.Progress({ label = label, duration = duration }, cb) end)
exports('cancelProgress', function() Nexus.CancelProgress() end)
exports('isProgressActive', function() return Nexus.IsProgressActive() end)
exports('input', function(opts, cb) Nexus.Input(opts, cb) end)
exports('confirm', function(opts, cb) Nexus.Confirm(opts, cb) end)
exports('menu', function(opts, cb) Nexus.Menu(opts, cb) end)
exports('closeUI', function() Nexus.CloseUI() end)
