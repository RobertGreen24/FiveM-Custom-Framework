--[[
    Nexus Framework :: server/characters.lua
    Character CRUD: list for the select screen, create, load, delete.
]]

Nexus = Nexus or {}
local Characters = {}
Nexus.Characters = Characters

local CFG = function() return Config.Multicharacter end

--- Phone numbers: 7 digits, never starting with 0 or 1, unique in the DB.
local function generatePhoneNumber()
    for _ = 1, 25 do
        local number = tostring(math.random(200, 999)) .. tostring(math.random(1000, 9999))
        local taken = Nexus.DB.scalar('SELECT COUNT(*) FROM nx_characters WHERE phone = ?', { number })
        local takenAccount = Nexus.DB.scalar('SELECT COUNT(*) FROM nx_players WHERE fivem = ?', { 'phone:' .. number })
        if (tonumber(taken) or 0) == 0 and (tonumber(takenAccount) or 0) == 0 then
            return number
        end
    end
    -- fall back to something almost certainly unique
    return ('%d%d%d%d%d%d%d'):format(
        math.random(2, 9), math.random(0, 9), math.random(0, 9), math.random(0, 9),
        math.random(0, 9), math.random(0, 9), math.random(0, 9)
    )
end

Characters.generatePhoneNumber = generatePhoneNumber

-- ===========================================================================
--  LIST
-- ===========================================================================

--- Every character on an account, in slot order.
function Characters.list(player)
    return Nexus.DB.query([[
        SELECT id, slot, state_id, first_name, last_name, birth_date, gender, nationality,
               phone, cash, bank, black_money, job, job_grade, gang, gang_grade,
               health, last_location, playtime, skin, metadata, last_played
        FROM nx_characters
        WHERE player_id = ?
        ORDER BY slot ASC
    ]], { player.accountId })
end

--- Has the account hit its slot cap?
function Characters.slotAvailable(player)
    local used = Nexus.DB.scalar('SELECT COUNT(*) FROM nx_characters WHERE player_id = ?', { player.accountId })
    local max = math.min(player:getMeta('slots', CFG().defaultSlots) or CFG().defaultSlots, CFG().maxSlots)
    if player:can('nexus.admin') then max = CFG().maxSlots end
    return (tonumber(used) or 0) < max, max - (tonumber(used) or 0)
end

function Characters.maxSlots(player)
    local max = player:getMeta('slots', CFG().defaultSlots) or CFG().defaultSlots
    if player:can('nexus.admin') then max = CFG().maxSlots end
    return math.min(max, CFG().maxSlots)
end

-- ===========================================================================
--  VALIDATION
-- ===========================================================================

local function validName(name, minLen, maxLen)
    if type(name) ~= 'string' then return false, 'Invalid name' end
    name = Nexus.Utils.trim(name)
    if #name < minLen or #name > maxLen then
        return false, ('Name must be %d-%d characters'):format(minLen, maxLen)
    end
    -- letters, apostrophes and hyphens only: O'Brien, Anne-Marie
    if name:find('[^%a\'%-]') then return false, 'Letters only, please' end
    if name:sub(1, 1):upper() ~= name:sub(1, 1) then return false, 'Names must start with a capital letter' end
    return true, name
end

local function ageFrom(birthDate)
    local y, m, d = tostring(birthDate):match('^(%d+)-(%d+)-(%d+)$')
    if not y then return nil end
    local now = os.date('*t')
    local age = now.year - tonumber(y)
    if (now.month < tonumber(m)) or (now.month == tonumber(m) and now.day < tonumber(d)) then
        age = age - 1
    end
    return age
end

Characters.ageFrom = ageFrom

--- Validates the create-character payload from the UI.
---@return boolean ok, string|table errorOrClean
function Characters.validate(data)
    if type(data) ~= 'table' then return false, 'Malformed request' end

    local minLen, maxLen = CFG().nameMinLength, CFG().nameMaxLength

    local okFirst, firstName = validName(data.firstName, minLen, maxLen)
    if not okFirst then return false, 'First name: ' .. tostring(firstName) end

    local okLast, lastName = validName(data.lastName, minLen, maxLen)
    if not okLast then return false, 'Last name: ' .. tostring(lastName) end

    if data.gender == nil or (tonumber(data.gender) ~= 0 and tonumber(data.gender) ~= 1) then
        return false, 'Pick a gender'
    end

    local birthDate = tostring(data.birthDate or '')
    if not birthDate:match('^%d%d%d%d%-%d%d%-%d%d$') then
        return false, 'Pick a date of birth'
    end
    local age = ageFrom(birthDate)
    if not age or age < CFG().minAge or age > CFG().maxAge then
        return false, ('You must be between %d and %d years old'):format(CFG().minAge, CFG().maxAge)
    end

    local nationality = tostring(data.nationality or 'American')
    if not Nexus.Utils.contains(CFG().nationalities, nationality) then
        nationality = 'American'
    end

    return true, {
        firstName = Nexus.Utils.trim(firstName),
        lastName = Nexus.Utils.trim(lastName),
        gender = tonumber(data.gender),
        birthDate = birthDate,
        nationality = nationality,
        skin = data.skin,
    }
end

-- ===========================================================================
--  CREATE
-- ===========================================================================

---@return number|nil charId, string|nil error
function Characters.create(player, data)
    local ok, result = Characters.validate(data)
    if not ok then return nil, result end

    local available, free = Characters.slotAvailable(player)
    if not available then
        return nil, 'All character slots are in use'
    end

    -- no duplicate full names (roleplay servers always regret allowing them)
    local duplicate = Nexus.DB.scalar(
        'SELECT COUNT(*) FROM nx_characters WHERE first_name = ? AND last_name = ?',
        { result.firstName, result.lastName }
    )
    if (tonumber(duplicate) or 0) > 0 then
        return nil, 'A character with that name already exists'
    end

    -- claim the first free slot
    local takenSlots = Nexus.DB.query('SELECT slot FROM nx_characters WHERE player_id = ?', { player.accountId })
    local used = {}
    for _, row in ipairs(takenSlots or {}) do used[tonumber(row.slot)] = true end
    local slot = 1
    while used[slot] do slot = slot + 1 end

    local stateId = Nexus.AllocateStateId()
    local phone = generatePhoneNumber()

    local defaults = Nexus.Utils.merge({
        cash = Nexus.MoneyConfig.startCash,
        bank = Nexus.MoneyConfig.startBank,
        job = 'unemployed',
        jobGrade = 0,
        gang = 'none',
    }, data.defaults or {})

    local insertId = Nexus.DB.insert([[
        INSERT INTO nx_characters
            (player_id, slot, state_id, first_name, last_name, birth_date, gender, nationality, phone,
             cash, bank, black_money, job, job_grade, gang, gang_grade,
             x, y, z, heading, last_location, health, armour, hunger, thirst, stress,
             skin, metadata, licences)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, 0, ?, ?, ?, ?, ?, 200, 0, 100, 100, 0, ?, ?, ?)
    ]], {
        player.accountId, slot, stateId, result.firstName, result.lastName, result.birthDate,
        result.gender, result.nationality, phone,
        defaults.cash, defaults.bank, defaults.job, defaults.jobGrade, defaults.gang,
        Config.SpawnPoints[Config.DefaultSpawn].coords.x, Config.SpawnPoints[Config.DefaultSpawn].coords.y,
        Config.SpawnPoints[Config.DefaultSpawn].coords.z, Config.SpawnPoints[Config.DefaultSpawn].coords.w,
        Config.DefaultSpawn,
        result.skin and Nexus.Utils.encodeJson(result.skin) or nil,
        Nexus.Utils.encodeJson({ slots = free - 1 + Characters.maxSlots(player) }) or '{}',
        Nexus.Utils.encodeJson({}) or '{}',
    })

    if not insertId then
        Nexus.ReleaseStateId(stateId)
        return nil, 'Could not create the character (database error)'
    end

    -- starter licences for legal jobs
    local licences = { { 'driving', 0 }, { 'weapon', 0 } }
    for _, lic in ipairs(licences) do
        Nexus.DB.defer('INSERT IGNORE INTO nx_licences (char_id, name, points, issued_by) VALUES (?, ?, ?, ?)', {
            insertId, lic[1], lic[2], 'city hall',
        })
    end

    Nexus.Log.action('character_create', {
        actor = player:getName(), target = ('%s %s'):format(result.firstName, result.lastName),
        details = ('slot %d, char id %d'):format(slot, insertId),
    })

    return insertId, nil, slot, stateId
end

-- ===========================================================================
--  LOAD
-- ===========================================================================

--- Loads a character onto the player object. Returns true on success.
function Characters.load(player, charId, opts)
    opts = opts or {}
    charId = tonumber(charId)
    if not charId then return false, 'Invalid character' end

    if Nexus.PlayerByCharId[charId] then
        return false, 'That character is already in the world'
    end

    local row = Nexus.DB.single([[
        SELECT * FROM nx_characters WHERE id = ? AND player_id = ?
    ]], { charId, player.accountId })

    if not row then return false, 'Character not found' end

    -- ban check at character level (a banned account never gets this far)
    player.charId = row.id
    player.stateId = Nexus.AllocateStateId(tonumber(row.state_id))
    player.firstName = row.first_name
    player.lastName = row.last_name
    player.gender = tonumber(row.gender) or 0
    player.birthDate = tostring(row.birth_date)
    player.nationality = row.nationality or 'American'
    player.phone = row.phone
    player.callsign = row.callsign
    player.skin = nil
    player.appearance = Nexus.Utils.decodeJson(row.skin, nil)

    player.money = {
        cash = tonumber(row.cash) or 0,
        bank = tonumber(row.bank) or 0,
        black = tonumber(row.black_money) or 0,
        savings = 0,
    }
    player.job = {
        name = row.job or 'unemployed',
        grade = tonumber(row.job_grade) or 0,
        onDuty = (tonumber(row.on_duty) or 0) == 1,
        label = Nexus.GetJobLabel(row.job or 'unemployed'),
        gradeName = Nexus.GetGradeLabel(row.job or 'unemployed', tonumber(row.job_grade) or 0),
        type = (Nexus.Jobs[row.job or 'unemployed'] or {}).type,
    }
    player.gang = {
        name = row.gang or 'none',
        grade = tonumber(row.gang_grade) or 0,
        label = Nexus.GetGangLabel(row.gang or 'none'),
        gradeName = Nexus.GetGangGradeLabel(row.gang or 'none', tonumber(row.gang_grade) or 0),
    }
    player.vitals = {
        health = tonumber(row.health) or 200,
        armour = tonumber(row.armour) or 0,
        hunger = tonumber(row.hunger) or 100,
        thirst = tonumber(row.thirst) or 100,
        stress = tonumber(row.stress) or 0,
    }
    player.position = {
        x = tonumber(row.x) or 0.0, y = tonumber(row.y) or 0.0,
        z = tonumber(row.z) or 0.0, w = tonumber(row.heading) or 0.0,
    }
    player.lastLocation = row.last_location or Config.DefaultSpawn
    player.metadata = Nexus.Utils.decodeJson(row.metadata, {}) or {}
    player.charPlaytime = tonumber(row.playtime) or 0
    player.isDead = (tonumber(row.is_dead) or 0) == 1

    -- licences
    player.licences = {}
    local licRows = Nexus.DB.query('SELECT name, points, revoked FROM nx_licences WHERE char_id = ?', { charId })
    for _, lic in ipairs(licRows or {}) do
        player.licences[lic.name] = {
            name = lic.name,
            points = tonumber(lic.points) or 0,
            revoked = (tonumber(lic.revoked) or 0) == 1,
        }
    end

    player.loaded = true
    player.lastSave = os.time()

    Nexus.PlayerByCharId[charId] = player
    Nexus.DB.defer('UPDATE nx_players SET playername = ?, ip = ? WHERE id = ?', {
        GetPlayerName(player.source), player.identifiers.ip, player.accountId,
    })

    player:pushState()
    player:pushData()

    TriggerClientEvent(Nexus.Events.PLAYER_LOADED, player.source, player:toClient())
    TriggerEvent(Nexus.Events.CHARACTER_SELECTED, player)
    TriggerEvent('nexus:server:playerLoaded', player)

    Nexus.Print.info('%s loaded character %s %s (state id %s).',
        GetPlayerName(player.source), player.firstName, player.lastName, tostring(player.stateId))

    -- hand the spawn decision to nx_spawn (falls back to core if not installed)
    if not opts.skipSpawn then
        TriggerEvent('nexus:server:requestSpawn', player)
    end

    return true
end

-- ===========================================================================
--  DELETE
-- ===========================================================================

function Characters.delete(player, charId)
    charId = tonumber(charId)
    if not charId then return false, 'Invalid character' end
    if player.charId == charId then return false, 'You cannot delete the character you are playing' end

    local row = Nexus.DB.single('SELECT id, state_id, first_name, last_name FROM nx_characters WHERE id = ? AND player_id = ?',
        { charId, player.accountId })
    if not row then return false, 'Character not found' end

    -- vehicles are released, not deleted (plates stay in the world history)
    Nexus.DB.update('UPDATE nx_vehicles SET char_id = NULL, state = 1 WHERE char_id = ?', { charId })
    Nexus.DB.update('DELETE FROM nx_inventory WHERE owner = ?', { 'char:' .. charId })
    Nexus.DB.update('DELETE FROM nx_licences WHERE char_id = ?', { charId })
    Nexus.DB.update('DELETE FROM nx_outfits WHERE char_id = ?', { charId })
    Nexus.DB.update('DELETE FROM nx_phone_contacts WHERE char_id = ?', { charId })
    Nexus.DB.update('DELETE FROM nx_phone_notes WHERE char_id = ?', { charId })
    Nexus.DB.update('DELETE FROM nx_characters WHERE id = ?', { charId })

    Nexus.Log.action('character_delete', {
        actor = GetPlayerName(player.source) or player:getName(),
        target = ('%s %s'):format(row.first_name, row.last_name),
        details = ('char id %d deleted'):format(charId),
        colour = 0xef4444,
    })

    TriggerEvent(Nexus.Events.CHARACTER_DELETED, player, charId)
    return true
end

-- ===========================================================================
--  APPEARANCE
-- ===========================================================================

function Characters.saveAppearance(player, appearance)
    if not player.charId then return false end
    player.appearance = appearance
    return Nexus.DB.update('UPDATE nx_characters SET skin = ? WHERE id = ?', {
        Nexus.Utils.encodeJson(appearance), player.charId,
    })
end

--- Default appearance used by the creator when nothing is saved yet.
function Characters.defaultAppearance()
    return {
        model = 'mp_m_freemode_01',
        face = {
            shapeFirst = 0, shapeSecond = 0, shapeThird = 0, skinFirst = 0, skinSecond = 0,
            shapeMix = 0.5, skinMix = 0.5, eyeColour = 0, hairColour = 0, hairHighlight = 0,
            noseWidth = 0.0, nosePeakHigh = 0.0, nosePeakSize = 0.0, noseBoneHigh = 0.0,
            nosePeakLower = 0.0, noseBoneTwist = 0.0, noseSize = 0.0, noseHeight = 0.0,
            cheekboneHigh = 0.0, cheekboneWidth = 0.0, cheekboneDepth = 0.0,
            eyeOpening = 0.0, lipThickness = 0.0, jawBoneWidth = 0.0, jawBoneBack = 0.0,
            chinBone = 0.0, chinBoneLength = 0.0, chinHole = 0.0, neckThickness = 0.0,
        },
        hair = 0,
        facialHair = 0,
        eyebrows = 0,
        makeup = 0,
        blush = 0,
        lipstick = 0,
        beard = 0,
        components = {},
        props = {},
        tattoos = {},
    }
end
