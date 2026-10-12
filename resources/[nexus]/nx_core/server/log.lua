--[[
    Nexus Framework :: server/log.lua
    Console logging + optional Discord webhook mirroring.

    Usage:
        Nexus.Print.info('loaded %d players', 12)
        Nexus.Log.action('ban', { actor = 'Admin Bob', target = 'x', details = '...' })
]]

Nexus = Nexus or {}

local Print = {}
Nexus.Print = Print

local webhookUrl = (GetConvar('nx_log_webhook', '') or ''):gsub('%s', '')
local debugEnabled = false

local function shouldLog(level)
    if not debugEnabled then
        return true
    end
    return true
end

local function format(fmt, ...)
    if select('#', ...) == 0 then return fmt end
    local ok, result = pcall(string.format, fmt, ...)
    return ok and result or fmt
end

local function emit(prefix, colour, message)
    if not shouldLog() then return end
    print(('%s[%s]^7 %s'):format(colour, prefix, message))
end

function Print.info(fmt, ...)  emit('Nexus', '^5', format(fmt, ...)) end

function Print.success(fmt, ...) emit('Nexus', '^2', format(fmt, ...)) end

function Print.warn(fmt, ...) emit('Nexus', '^3', format(fmt, ...)) end

function Print.error(fmt, ...) emit('Nexus', '^1', format(fmt, ...)) end

function Print.debug(fmt, ...)
    if not (Config and Config.Debug) then return end
    emit('Nexus:debug', '^6', format(fmt, ...))
end

--- Runtime convar toggle: setr nx_log_level debug
CreateThread(function()
    local level = GetConvar('nx_log_level', 'info')
    debugEnabled = (level == 'debug' or level == 'trace')
    if debugEnabled then Print.warn('Debug logging enabled.') end
end)

-- ---------------------------------------------------------------------------
--  Discord webhooks
-- ---------------------------------------------------------------------------

local Log = {}
Nexus.Log = Log

--- Sends a rich embed to the configured webhook (no-op when unset).
---@param title string
---@param fields table|nil list of { name, value, inline }
---@param colour number|nil decimal colour
function Log.webhook(title, fields, colour)
    if webhookUrl == '' then return end
    local embeds = { { title = title, color = colour or 0x8b5cf6, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'), fields = {} } }
    for _, f in ipairs(fields or {}) do
        embeds[1].fields[#embeds[1].fields + 1] = {
            name = tostring(f.name or ''),
            value = tostring(f.value or 'n/a'):sub(1, 1020),
            inline = f.inline ~= false,
        }
    end
    PerformHttpRequest(webhookUrl, function() end, 'POST', json.encode({ embeds = embeds }), {
        ['Content-Type'] = 'application/json',
    })
end

--- Structured admin/audit log: console + DB + webhook.
---@param action string     short slug, e.g. 'kick', 'money_add', 'job_set'
---@param data table        { actor, target, details, colour }
function Log.action(action, data)
    data = data or {}
    local actor = data.actor or 'System'
    local target = data.target or '-'
    local details = data.details or ''

    Print.info('[action] %s | actor=%s target=%s %s', action, actor, tostring(target), details)

    -- persist to nx_admin_logs for the in-game audit trail
    if Nexus.DB and Nexus.DB.available then
        Nexus.DB.defer('INSERT INTO nx_admin_logs (actor, action, target, details) VALUES (?, ?, ?, ?)', {
            actor, action, tostring(target), details,
        })
    end

    Log.webhook(('Action · %s'):format(action), {
        { name = 'Actor',   value = actor,   inline = true },
        { name = 'Target',  value = tostring(target), inline = true },
        { name = 'Details', value = details ~= '' and details or '-', inline = false },
    }, data.colour or 0x8b5cf6)
end

--- convenience wrappers -------------------------------------------------------
function Log.money(actor, target, account, amount, reason)
    Log.action(amount >= 0 and 'money_add' or 'money_remove', {
        actor = actor, target = target,
        details = ('%s %d (%s)'):format(account, amount, reason or 'no reason'),
        colour = 0x22c55e,
    })
end

function Log.cheat(source, reason)
    Log.action('possible_cheat', {
        actor = 'anticheat', target = source,
        details = reason, colour = 0xef4444,
    })
end

--- Trigger an in-game staff alert (ACE group: nexus.admin)
function Log.staffAlert(message, source)
    TriggerEvent('nexus:server:staffAlert', message, source)
end
