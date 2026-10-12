--[[
    Nexus Framework :: nx_police/server/mdt.lua
    The Mobile Data Terminal backend: people, vehicles, warrants, BOLOs,
    incidents and the dispatch log.
]]

Nexus = Nexus or {}

local function officer(source)
    local player = Nexus.GetPlayer(source)
    local ok, err = Nexus.IsOfficer(player)
    if not ok then
        if player and player.loaded then player:notify('MDT access denied (' .. tostring(err) .. ').', 'error') end
        return nil
    end
    return player
end

local function jsonCoords(vector)
    if not vector then return nil end
    return ('{"x":%.2f,"y":%.2f,"z":%.2f}'):format(vector.x, vector.y, vector.z)
end

local function decodeCoords(raw)
    if not raw then return nil end
    local decoded = Nexus.Utils.decodeJson(raw)
    if not decoded then return nil end
    return decoded
end

--- Profile header for the MDT: identity, job, licences, vehicles, fines.
local function profileFor(charId)
    local row = Nexus.DB.single([[
        SELECT c.id, c.first_name, c.last_name, c.birth_date, c.job, c.job_grade, c.gang, c.gang_grade,
               c.phone, c.state_id, c.created_at, c.last_seen,
               p.admin_level, p.discord
        FROM nx_characters c
        LEFT JOIN nx_players p ON p.id = c.player_id
        WHERE c.id = ?
    ]], { charId })
    if not row then return nil end

    row.name = ('%s %s'):format(row.first_name, row.last_name)
    row.unpaidFines = tonumber(Nexus.DB.scalar(
        'SELECT COALESCE(SUM(amount),0) FROM nx_transactions WHERE char_id = ? AND type = ? AND balance_after IS NULL',
        { charId, 'fine' })) or 0

    row.licences = Nexus.DB.query(
        'SELECT name, points, revoked, issued_by, issued_at FROM nx_licences WHERE char_id = ?', { charId })
    row.vehicles = Nexus.DB.query(
        'SELECT plate, model, label, vtype, state, mileage, garage FROM nx_vehicles WHERE char_id = ? ORDER BY label', { charId })
    row.arrests = Nexus.DB.query([[
        SELECT id, code, title, details, coords, status, created_by, created_at
        FROM nx_incidents WHERE title LIKE ? ORDER BY id DESC LIMIT 25
    ]], { '%' .. row.name .. '%' })
    row.warrants = Nexus.DB.query(
        'SELECT * FROM nx_warrants WHERE char_id = ? ORDER BY active DESC, id DESC LIMIT 25', { charId })
    row.bolos = Nexus.DB.query(
        'SELECT * FROM nx_bolos WHERE details LIKE ? OR plate IN (SELECT plate FROM nx_vehicles WHERE char_id = ?) ORDER BY active DESC, id DESC LIMIT 25',
        { '%' .. row.name .. '%', charId })

    return row
end

-- ===========================================================================
--  OPEN / SEARCH
-- ===========================================================================

RegisterNetEvent('nx_police:openMDT', function()
    local source = source
    local player = officer(source)
    if not player then return end

    TriggerClientEvent('nx_police:openMDT', source, {
        officer = {
            name = player:getName(),
            callsign = player.callsign,
            grade = player.job.grade,
            gradeName = player.job.gradeName,
        },
        incidents = Nexus.DB.query(
            'SELECT id, code, title, details, coords, priority, status, created_by, created_at FROM nx_incidents WHERE status <> ? ORDER BY id DESC LIMIT 30',
            { 'closed' }),
        warrants = Nexus.DB.query(
            'SELECT w.*, c.first_name, c.last_name FROM nx_warrants w LEFT JOIN nx_characters c ON c.id = w.char_id WHERE w.active = 1 ORDER BY w.id DESC LIMIT 25'),
        bolos = Nexus.DB.query('SELECT * FROM nx_bolos WHERE active = 1 ORDER BY id DESC LIMIT 25'),
        calls = Nexus.DB.query(
            'SELECT * FROM nx_calls WHERE service = ? AND handled = 0 ORDER BY id DESC LIMIT 25', { 'police' }),
        officers = exports.nx_core:getDutySources('police'),
    })
end)

RegisterNetEvent('nx_police:mdtSearch', function(query)
    local source = source
    local player = officer(source)
    if not player then return end

    query = tostring(query or ''):sub(1, 48)
    if #query < 2 then
        player:notify('Enter at least two characters.', 'error')
        return
    end

    local like = '%' .. query .. '%'
    local numeric = tonumber((query:gsub('%D', '')))

    local people = Nexus.DB.query([[
        SELECT id, first_name, last_name, state_id, birth_date, phone, job, job_grade, last_seen
        FROM nx_characters
        WHERE CONCAT(first_name, ' ', last_name) LIKE ? OR phone LIKE ? OR id = ?
        LIMIT 12
    ]], { like, like, numeric or -1 })

    local vehicles = Nexus.DB.query([[
        SELECT v.plate, v.model, v.label, v.vtype, v.state, v.mileage, v.char_id,
               c.first_name, c.last_name
        FROM nx_vehicles v
        LEFT JOIN nx_characters c ON c.id = v.char_id
        WHERE v.plate LIKE ? OR v.model LIKE ?
        LIMIT 12
    ]], { like, like })

    TriggerClientEvent('nx_police:mdtResults', source, {
        query = query,
        people = people,
        vehicles = vehicles,
    })
end)

RegisterNetEvent('nx_police:mdtProfile', function(charId)
    local source = source
    local player = officer(source)
    if not player then return end

    local profile = profileFor(tonumber(charId) or 0)
    if not profile then
        player:notify('No such record.', 'error')
        return
    end

    Nexus.Log.action('mdt_lookup', {
        actor = player:getName(), target = profile.name, details = ('char #%d'):format(profile.id),
    })
    TriggerClientEvent('nx_police:mdtProfile', source, profile)
end)

--- Look a plate up straight from the MDT's vehicle tab.
RegisterNetEvent('nx_police:mdtPlate', function(plate)
    local source = source
    local player = officer(source)
    if not player then return end

    plate = tostring(plate or ''):upper():gsub('%s+', '')
    local row = Nexus.DB.single([[
        SELECT v.*, c.id AS char_id, c.first_name, c.last_name, c.phone
        FROM nx_vehicles v
        LEFT JOIN nx_characters c ON c.id = v.char_id
        WHERE v.plate = ?
    ]], { plate })

    if not row then
        TriggerClientEvent('nx_police:mdtPlate', source, { plate = plate, found = false })
        return
    end

    row.found = true
    row.owner = row.first_name and ('%s %s'):format(row.first_name, row.last_name) or 'Unregistered'
    row.flags = Nexus.DB.query(
        'SELECT id, reason, priority, active FROM nx_bolos WHERE plate = ? ORDER BY id DESC LIMIT 10', { plate })

    TriggerClientEvent('nx_police:mdtPlate', source, row)
end)

-- ===========================================================================
--  RECORDS
-- ===========================================================================

RegisterNetEvent('nx_police:addWarrant', function(charId, reason, charges, fine, priority)
    local source = source
    local player = officer(source)
    if not player or player.job.grade < 1 then
        if player then player:notify('Only a supervisor may issue warrants.', 'error') end
        return
    end

    charId = tonumber(charId)
    reason = tostring(reason or ''):sub(1, 160)
    if not charId or reason == '' then
        player:notify('A warrant needs a subject and a reason.', 'error')
        return
    end

    Nexus.DB.insert([[
        INSERT INTO nx_warrants (char_id, reason, charges, fine, priority, issued_by)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { charId, reason, charges, math.max(0, math.floor(tonumber(fine) or 0)),
          priority or 'normal', player:getName() })

    local target = Nexus.GetPlayerByCharId(charId)
    if target and target.loaded then
        target:notify('A warrant has been issued for your arrest.', 'error', 9000, 'Police')
    end

    Nexus.Log.action('warrant_issued', {
        actor = player:getName(), target = ('char #%d'):format(charId), details = reason,
    })
    player:notify('Warrant filed.', 'success')
    TriggerEvent('nx_police:openMDT')  -- refresh for the officer
    TriggerClientEvent('nx_police:mdtRefresh', source)
end)

RegisterNetEvent('nx_police:clearWarrant', function(warrantId)
    local source = source
    local player = officer(source)
    if not player then return end

    Nexus.DB.update('UPDATE nx_warrants SET active = 0, cleared_by = ?, cleared_at = NOW() WHERE id = ?',
        { player:getName(), tonumber(warrantId) or 0 })

    Nexus.Log.action('warrant_cleared', { actor = player:getName(), target = tostring(warrantId) })
    player:notify('Warrant cleared.', 'success')
    TriggerClientEvent('nx_police:mdtRefresh', source)
end)

RegisterNetEvent('nx_police:addBolo', function(data)
    local source = source
    local player = officer(source)
    if not player then return end

    data = data or {}
    if (data.plate == nil or data.plate == '') and (data.model == nil or data.model == '') then
        player:notify('A BOLO needs a plate or a model.', 'error')
        return
    end

    Nexus.DB.insert('INSERT INTO nx_bolos (plate, model, reason, details, priority, issued_by) VALUES (?, ?, ?, ?, ?, ?)', {
        data.plate and data.plate:upper() or nil,
        data.model or nil,
        tostring(data.reason or 'BOLO'):sub(1, 160),
        data.details,
        data.priority or 'normal',
        player:getName(),
    })

    -- notify every on-duty officer
    for _, other in ipairs(Nexus.OnDutyOfficers()) do
        other:notify(('BOLO: %s %s'):format(data.plate or data.model or '?', data.reason or ''), 'warning', 9000, 'Dispatch')
    end

    Nexus.Log.action('bolo_issued', { actor = player:getName(), details = tostring(data.reason) })
    TriggerClientEvent('nx_police:mdtRefresh', source)
end)

RegisterNetEvent('nx_police:clearBolo', function(boloId)
    local source = source
    local player = officer(source)
    if not player then return end

    Nexus.DB.update('UPDATE nx_bolos SET active = 0 WHERE id = ?', { tonumber(boloId) or 0 })
    player:notify('BOLO cleared.', 'success')
    TriggerClientEvent('nx_police:mdtRefresh', source)
end)

RegisterNetEvent('nx_police:addIncident', function(data)
    local source = source
    local player = officer(source)
    if not player then return end

    data = data or {}
    local title = tostring(data.title or ''):sub(1, 120)
    if title == '' then
        player:notify('Give the incident a title.', 'error')
        return
    end

    Nexus.DB.insert([[
        INSERT INTO nx_incidents (code, title, details, coords, priority, created_by)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        data.code or '10-13', title, data.details,
        jsonCoords(player:getCoords()), data.priority or 'normal', player:getName(),
    })

    for _, other in ipairs(Nexus.OnDutyOfficers()) do
        other:notify(('[%s] %s'):format(data.code or '10-13', title), 'warning', 9000, 'Dispatch')
    end

    TriggerClientEvent('nx_police:mdtRefresh', source)
end)

RegisterNetEvent('nx_police:closeIncident', function(incidentId, note)
    local source = source
    local player = officer(source)
    if not player then return end

    local row = Nexus.DB.single('SELECT id, status, details FROM nx_incidents WHERE id = ?', { tonumber(incidentId) or 0 })
    if not row then
        player:notify('No such incident.', 'error')
        return
    end

    local details = row.details
    if note and note ~= '' then
        details = ('%s\\n[close] %s: %s'):format(details or '', player:getName(), note)
    end

    Nexus.DB.update('UPDATE nx_incidents SET status = ?, details = ?, closed_by = ?, closed_at = NOW() WHERE id = ?',
        { 'closed', details, player:getName(), row.id })

    player:notify('Incident closed.', 'success')
    TriggerClientEvent('nx_police:mdtRefresh', source)
end)

RegisterNetEvent('nx_police:addNote', function(charId, title, details)
    local source = source
    local player = officer(source)
    if not player then return end

    charId = tonumber(charId)
    if not charId then return end

    Nexus.DB.insert([[
        INSERT INTO nx_incidents (code, title, details, coords, status, created_by, closed_by, closed_at)
        VALUES ('NOTE', ?, ?, NULL, 'closed', ?, ?, NOW())
    ]], { ('%s'):format(tostring(title or 'Note'):sub(1, 120)), details, player:getName(), player:getName() })

    -- the note is attached to the subject by name so the profile query finds it
    local subject = Nexus.DB.single('SELECT CONCAT(first_name, " ", last_name) AS name FROM nx_characters WHERE id = ?', { charId })
    if subject then
        Nexus.DB.update('UPDATE nx_incidents SET title = ? WHERE id = LAST_INSERT_ID()', { subject.name })
    end

    player:notify('Note saved to the record.', 'success')
    TriggerClientEvent('nx_police:mdtRefresh', source)
end)

--- Dispatch calls from nx_phone (911) land here for the police MDT.
RegisterNetEvent('nx_police:registerCall', function(call)
    if type(call) ~= 'table' then return end
    local id = Nexus.DB.insert([[
        INSERT INTO nx_calls (caller, number, service, message, coords)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        call.caller, call.number, call.service or 'police',
        tostring(call.message or ''):sub(1, 240), call.coords,
    })

    local payload = {
        id = id, caller = call.caller, number = call.number,
        service = call.service or 'police', message = call.message,
        coords = decodeCoords(call.coords), created_at = os.date('%Y-%m-%d %H:%M'),
    }

    if (call.service or 'police') == 'police' then
        for _, other in ipairs(Nexus.OnDutyOfficers()) do
            other:notify(('911: %s'):format(call.message or ''), 'warning', 10000, 'Dispatch')
            TriggerClientEvent('nx_police:dispatchAlert', other.source, {
                message = call.message, code = '911', priority = 'high',
                coords = payload.coords and { payload.coords.x, payload.coords.y, payload.coords.z },
            })
        end
    end

    TriggerEvent('nexus:server:emergencyCall', payload)
end)

RegisterNetEvent('nx_police:handleCall', function(callId)
    local source = source
    local player = officer(source)
    if not player then return end
    Nexus.DB.update('UPDATE nx_calls SET handled = 1, handled_by = ? WHERE id = ?', { player:getName(), tonumber(callId) or 0 })
    TriggerClientEvent('nx_police:mdtRefresh', source)
end)

exports('openMDT', function(source) TriggerEvent('nx_police:openMDT', source) end)
exports('getWarrants', function(charId)
    return Nexus.DB.query('SELECT * FROM nx_warrants WHERE char_id = ? AND active = 1', { charId })
end)
exports('hasWarrant', function(charId)
    return tonumber(Nexus.DB.scalar('SELECT COUNT(*) FROM nx_warrants WHERE char_id = ? AND active = 1', { charId })) > 0
end)
exports('addCall', function(call) TriggerEvent('nx_police:registerCall', call) end)
