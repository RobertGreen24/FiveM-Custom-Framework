--[[
    Nexus Framework :: locales/en.lua
    Strings used across resources. Add a new file next to this one (es.lua,
    de.lua ...) and set `Config.Locale` in shared/config.lua to switch.

    Usage: Nexus.L('duty.on')  -- falls back to the key if missing
]]

Nexus = Nexus or {}

local strings = {
    ['framework.name']        = 'Nexus',
    ['framework.welcome']     = 'Welcome to the city, %s.',

    ['duty.on']               = 'You are now on duty.',
    ['duty.off']              = 'You are now off duty.',
    ['duty.required']         = 'You must be on duty to do that.',
    ['duty.denied']           = 'Your role does not allow that.',

    ['job.too_far']           = 'You are too far away.',
    ['job.unknown']           = 'That job does not exist.',
    ['job.set']               = 'You are now %s.',

    ['money.insufficient']    = 'You do not have enough money.',
    ['money.paid']            = 'You paid %s.',
    ['money.received']        = 'You received %s.',

    ['vitals.hungry']         = 'You are getting hungry.',
    ['vitals.thirsty']        = 'You are getting thirsty.',
    ['vitals.exhausted']      = 'You are too weak to run.',

    ['death.downed']          = 'You are down. EMS has been alerted.',
    ['death.revived']         = 'You have been revived.',
    ['death.respawned']       = 'You were taken to Pillow Hill Medical.',

    ['inventory.full']        = 'Not enough space.',
    ['inventory.no_item']     = 'You do not have that item.',
    ['inventory.locked']      = 'That container is locked.',

    ['vehicle.locked']        = 'The vehicle is locked.',
    ['vehicle.no_keys']       = 'You do not have the keys.',
    ['vehicle.parked']        = 'Vehicle parked.',
    ['vehicle.retrieved']     = 'Vehicle retrieved.',

    ['shop.bought']           = 'You bought %s.',
    ['shop.sold']             = 'You sold %s.',
    ['shop.no_money']         = 'You cannot afford that.',

    ['admin.no_permission']   = 'You do not have permission to do that.',
    ['admin.player_not_found']= 'Player not found.',
    ['admin.duty_on']         = 'Admin duty enabled.',
    ['admin.duty_off']        = 'Admin duty disabled.',

    ['ui.confirm']            = 'Confirm',
    ['ui.cancel']             = 'Cancel',
    ['ui.submit']             = 'Submit',
    ['ui.loading']            = 'Loading…',
}

Nexus.Locales = Nexus.Locales or {}
Nexus.Locales[Config and Config.Locale or 'en'] = strings

--- Translate a key. Extra args are passed to string.format.
function Nexus.L(key, ...)
    local locale = (Config and Config.Locale) or 'en'
    local table_ = Nexus.Locales[locale] or Nexus.Locales.en or {}
    local value = table_[key] or (Nexus.Locales.en and Nexus.Locales.en[key]) or key
    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, value, ...)
        if ok then return formatted end
    end
    return value
end
