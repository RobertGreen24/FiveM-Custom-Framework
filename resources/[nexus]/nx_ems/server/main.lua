--[[
    Nexus Framework :: nx_ems (server)
    Revives, treatment, billing and patient charts.
]]

Nexus = Nexus or {}

local function isMedic(player, minGrade)
    if not player or not player.loaded then return false, 'not loaded' end
    if player:can('nexus.admin') then return true end
    if player.job.name ~= EmsConfig.job then return false, 'not ems' end
    if player.job.grade < (minGrade or 0) then return false, 'grade too low' end
    return true
end

Nexus.IsMedic = isMedic

local function onDutyMedics()
    local list = {}
    for _, player in ipairs(Nexus.GetPlayers()) do
        if player.job.name == EmsConfig.job and player:isOnDuty() then
            list[#list + 1] = player
        end
    end
    return list
end

Nexus.OnDutyMedics = onDutyMedics

--- Records a chart entry so the EMS MDT can show history.
local function addRecord(charId, kind, title, details, medic)
    if not Nexus.DB.available then return end
    Nexus.DB.defer('INSERT INTO nx_medical (char_id, type, title, details, medic) VALUES (?, ?, ?, ?, ?)', {
        charId, kind, title, details, medic or 'system',
    })
end

Nexus.AddMedicalRecord = addRecord

--- Bills the patient (bank first, then cash) and credits the ambulance society.
local function bill(player, amount, reason, actor)
    if not EmsConfig.billPatients or amount <= 0 then return false end

    local paid = player:removeMoney('bank', amount, reason)
    if not paid then
        paid = player:removeMoney('cash', amount, reason)
    end
    if not paid then
        player:setMeta('unpaidMedical', (tonumber(player:getMeta('unpaidMedical', 0)) or 0) + amount)
        player:notify(('Medical bill of %s added to your account.'):format(Nexus.Utils.formatMoney(amount)), 'warning', 8000, 'Hospital')
        return false
    end

    Nexus.Society.addMoney(EmsConfig.job, amount, reason)
    player:notify(('You were billed %s for treatment.'):format(Nexus.Utils.formatMoney(amount)), 'money', 8000, 'Hospital')
    return true
end

Nexus.BillPatient = bill

-- ===========================================================================
--  ALERTS
-- ===========================================================================

--- Downed players broadcast their position to on-duty medics.
RegisterNetEvent('nexus:server:downedAlert', function(coords)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end
    if not coords then return end

    player:setMeta('downedAt', os.time())

    local medics = onDutyMedics()
    for _, medic in ipairs(medics) do
        medic:notify(('DOWN: %s is down.'):format(player:getName()), 'error', 12000, 'Ambulance')
        TriggerClientEvent('nx_ems:downAlert', medic.source, {
            name = player:getName(),
            stateId = player:getStateId(),
            coords = { coords.x, coords.y, coords.z },
        })
    end

    -- log it to the ambulance feed for the MDT
    Nexus.DB.insert('INSERT INTO nx_calls (caller, number, service, message, coords) VALUES (?, ?, ?, ?, ?)', {
        player:getName(), tostring(player:getStateId()), 'ambulance',
        ('%s is down and needs assistance'):format(player:getName()),
        ('{"x":%.2f,"y":%.2f,"z":%.2f}'):format(coords.x, coords.y, coords.z),
    })
end)

--- Player death hook from nx_core.
AddEventHandler('nexus:server:playerDied', function(player, cause)
    if not player then return end
    addRecord(player.charId, 'death', 'Brought in by the coroner', ('Cause: %s'):format(
        EmsConfig.causes[tonumber(cause) or 0] or EmsConfig.causes[0]), 'system')

    for _, medic in ipairs(onDutyMedics()) do
        medic:notify(('MORGUE: %s died (%s).'):format(player:getName(),
            EmsConfig.causes[tonumber(cause) or 0] or 'unknown'), 'warning', 10000, 'Ambulance')
    end
end)

-- ===========================================================================
--  REVIVE / TREAT
-- ===========================================================================

local function nearEnough(medic, target, distance)
    return #(medic:getCoords() - target:getCoords()) <= (distance or 2.5)
end

RegisterNetEvent('nx_ems:revive', function(targetSource)
    local source = source
    local medic = Nexus.GetPlayer(source)
    local ok = isMedic(medic)
    if not ok then
        if medic and medic.loaded then medic:notify('Only EMS can do that.', 'error') end
        return
    end

    local target = Nexus.GetPlayer(tonumber(targetSource))
    if not target or not target.loaded then
        medic:notify('No such patient.', 'error')
        return
    end
    if not nearEnough(medic, target) then
        medic:notify('You are too far from the patient.', 'error')
        return
    end

    -- permission or a medikit
    if not medic:hasJobPermission('revivify') then
        if exports.nx_inventory:getItemCount(source, EmsConfig.reviveItem) < 1 then
            medic:notify(('You need a %s to revive someone.'):format(EmsConfig.reviveItem), 'error')
            return
        end
        exports.nx_inventory:removeItem(source, EmsConfig.reviveItem, 1)
    end

    target:revive(EmsConfig.reviveHealth)
    target:setMeta('downedAt', nil)

    medic:notify(('You revived %s.'):format(target:getName()), 'success', 7000)
    target:notify(('You were revived by %s.'):format(medic:getName()), 'success', 7000, 'Paramedic')

    addRecord(target.charId, 'revive', 'Revived in the field',
        ('By %s'):format(medic:getName()), medic:getName())
    bill(target, EmsConfig.reviveFee, 'emergency revive', medic:getName())

    Nexus.Log.action('ems_revive', { actor = medic:getName(), target = target:getName() })
end)

RegisterNetEvent('nx_ems:treat', function(targetSource, full)
    local source = source
    local medic = Nexus.GetPlayer(source)
    local ok = isMedic(medic)
    if not ok then return end

    local target = Nexus.GetPlayer(tonumber(targetSource))
    if not target or not target.loaded then return end
    if not nearEnough(medic, target) then
        medic:notify('You are too far from the patient.', 'error')
        return
    end

    if full and not medic:hasJobPermission('surgery') then
        if exports.nx_inventory:getItemCount(source, EmsConfig.reviveItem) < 1 then
            medic:notify('A full treatment needs a medikit.', 'error')
            return
        end
        exports.nx_inventory:removeItem(source, EmsConfig.reviveItem, 1)
    elseif not exports.nx_inventory:getItemCount(source, EmsConfig.bandageItem) then
        medic:notify('You have no bandages.', 'error')
        return
    end

    local health = full and EmsConfig.reviveHealth * 2 or EmsConfig.treatHealth
    local vitals = target:getVitals()
    target:setHealth(math.min(100, (vitals.health or 100) + health))
    target:addVital('armour', full and EmsConfig.treatArmour * 2 or EmsConfig.treatArmour)

    if not full then
        exports.nx_inventory:removeItem(source, EmsConfig.bandageItem, 1)
    end

    medic:notify(('Treated %s.'):format(target:getName()), 'success')
    target:notify(('You were treated by %s.'):format(medic:getName()), 'success', 6000, 'Paramedic')

    addRecord(target.charId, full and 'treatment' or 'note',
        full and 'Full treatment' or 'Field dressing',
        ('By %s'):format(medic:getName()), medic:getName())
    bill(target, full and EmsConfig.treatFee * 2 or EmsConfig.treatFee, 'medical treatment', medic:getName())
end)

--- Self-heal with a bandage (any player).
RegisterNetEvent('nx_ems:selfTreat', function()
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    if not exports.nx_inventory:removeItem(source, EmsConfig.bandageItem, 1) then
        player:notify('You have no bandages.', 'error')
        return
    end

    local vitals = player:getVitals()
    player:setHealth(math.min(100, (vitals.health or 100) + 15))
    player:notify('You patched yourself up.', 'success')
end)

-- ===========================================================================
--  HOSPITAL RESPAWN / BEDS
-- ===========================================================================

--- Called by nx_core's respawn flow: puts the patient in a bed.
RegisterNetEvent('nx_ems:checkIn', function(hospitalName)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local hospital
    for _, entry in ipairs(EmsConfig.hospitals) do
        if entry.name == hospitalName then hospital = entry end
    end
    if not hospital then
        player:notify('Unknown hospital.', 'error')
        return
    end

    player:teleport({ x = hospital.bed.x, y = hospital.bed.y, z = hospital.bed.z, w = hospital.heading })
    player:revive(60.0)
    player:setMeta('hospital', hospital.name)

    if EmsConfig.billAtHospital then
        bill(player, EmsConfig.treatFee, 'hospital admission', 'hospital')
    end
    addRecord(player.charId, 'admission', ('Admitted to %s'):format(hospital.label), nil, 'hospital')
end)

RegisterNetEvent('nx_ems:requestHospitals', function()
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end
    TriggerClientEvent('nexus:client:hospitalList', source, EmsConfig.hospitals)
end)

-- ===========================================================================
--  SUPPLIES + LOADOUT
-- ===========================================================================

RegisterNetEvent('nx_ems:requestSupplies', function()
    local source = source
    local medic = Nexus.GetPlayer(source)
    local ok = isMedic(medic)
    if not ok then
        if medic and medic.loaded then medic:notify('Only EMS can do that.', 'error') end
        return
    end

    local owner = exports.nx_inventory:ensureContainer('stash:ambulance_locker', {
        label = 'Pillbox Supply Room', slots = 60, weight = 150000, persistent = true,
    })
    if not owner then
        medic:notify('The supply room is unavailable.', 'error')
        return
    end
    exports.nx_inventory:openForPlayer(source, owner, { label = 'Pillbox Supply Room' })
end)

RegisterNetEvent('nx_ems:requestLoadout', function()
    local source = source
    local medic = Nexus.GetPlayer(source)
    local ok = isMedic(medic)
    if not ok then return end

    local coords = medic:getCoords()
    local nearHospital = false
    for _, hospital in ipairs(EmsConfig.hospitals) do
        if #(coords - hospital.coords) < 120.0 then nearHospital = true end
    end
    if not nearHospital then
        medic:notify('Visit a hospital to draw supplies.', 'error')
        return
    end

    for _, entry in ipairs(EmsConfig.loadout) do
        exports.nx_inventory:addItem(source, entry.item, entry.amount)
    end
    medic:notify('Supplies issued.', 'success', 6000, 'Paramedic')
    Nexus.Log.action('ems_loadout', { actor = medic:getName() })
end)

-- ===========================================================================
--  CHARTS (MDT)
-- ===========================================================================

RegisterNetEvent('nx_ems:openMDT', function()
    local source = source
    local medic = Nexus.GetPlayer(source)
    local ok = isMedic(medic)
    if not ok then
        if medic and medic.loaded then medic:notify('EMS access only.', 'error') end
        return
    end

    TriggerClientEvent('nx_ems:openMDT', source, {
        medic = { name = medic:getName(), grade = medic.job.grade, gradeName = medic.job.gradeName },
        calls = Nexus.DB.query(
            'SELECT * FROM nx_calls WHERE service = ? AND handled = 0 ORDER BY id DESC LIMIT 30', { 'ambulance' }),
        recent = Nexus.DB.query([[
            SELECT m.*, c.first_name, c.last_name FROM nx_medical m
            LEFT JOIN nx_characters c ON c.id = m.char_id
            ORDER BY m.id DESC LIMIT 40
        ]]),
        medics = exports.nx_core:getDutySources(EmsConfig.job),
        hospitals = EmsConfig.hospitals,
    })
end)

RegisterNetEvent('nx_ems:mdtSearch', function(query)
    local source = source
    local medic = Nexus.GetPlayer(source)
    local ok = isMedic(medic)
    if not ok then return end

    query = tostring(query or ''):sub(1, 48)
    if #query < 2 then return end
    local like = '%' .. query .. '%'

    local patients = Nexus.DB.query([[
        SELECT id, first_name, last_name, state_id, phone, job, birth_date
        FROM nx_characters
        WHERE CONCAT(first_name, ' ', last_name) LIKE ? OR phone LIKE ? OR id = ?
        LIMIT 12
    ]], { like, like, tonumber(query) or -1 })

    TriggerClientEvent('nx_ems:mdtResults', source, { query = query, patients = patients })
end)

RegisterNetEvent('nx_ems:mdtChart', function(charId)
    local source = source
    local medic = Nexus.GetPlayer(source)
    local ok = isMedic(medic)
    if not ok then return end

    charId = tonumber(charId)
    local chart = Nexus.DB.single([[
        SELECT id, first_name, last_name, state_id, phone, birth_date, metadata
        FROM nx_characters WHERE id = ?
    ]], { charId })
    if not chart then
        medic:notify('No chart found.', 'error')
        return
    end

    chart.records = Nexus.DB.query(
        'SELECT * FROM nx_medical WHERE char_id = ? ORDER BY id DESC LIMIT 30', { charId })

    local meta = Nexus.Utils.decodeJson(chart.metadata or '{}') or {}
    chart.bloodType = meta.bloodType or 'Unknown'
    chart.allergies = meta.allergies or 'None recorded'
    chart.metadata = nil

    local patient = Nexus.GetPlayerByCharId(charId)
    chart.unpaid = patient and (tonumber(patient:getMeta('unpaidMedical', 0)) or 0) or 0
    chart.online = patient ~= nil and patient.loaded or false

    TriggerClientEvent('nx_ems:mdtChart', source, chart)
end)

RegisterNetEvent('nx_ems:mdtNote', function(charId, title, details)
    local source = source
    local medic = Nexus.GetPlayer(source)
    local ok = isMedic(medic)
    if not ok then return end
    charId = tonumber(charId)
    if not charId then return end

    addRecord(charId, 'note', tostring(title or 'Note'):sub(1, 120), details, medic:getName())
    medic:notify('Chart updated.', 'success')
    TriggerClientEvent('nx_ems:mdtRefresh', source)
end)

RegisterNetEvent('nx_ems:handleCall', function(callId)
    local source = source
    local medic = Nexus.GetPlayer(source)
    local ok = isMedic(medic)
    if not ok then return end
    Nexus.DB.update('UPDATE nx_calls SET handled = 1, handled_by = ? WHERE id = ?', { medic:getName(), tonumber(callId) or 0 })
    TriggerClientEvent('nx_ems:mdtRefresh', source)
end)

--- Chart lookup used by the police MDT and other resources.
exports('isMedic', function(source, minGrade) return (isMedic(Nexus.GetPlayer(source), minGrade)) end)
exports('onDuty', function() return onDutyMedics() end)
exports('revive', function(source, health)
    local player = Nexus.GetPlayer(source)
    if player then player:revive(health or EmsConfig.reviveHealth) end
end)
exports('records', function(charId)
    return Nexus.DB.query('SELECT * FROM nx_medical WHERE char_id = ? ORDER BY id DESC LIMIT 30', { charId })
end)
exports('hospitals', function() return EmsConfig.hospitals end)
exports('hospitalsByProximity', function(coords)
    local list = {}
    for _, hospital in ipairs(EmsConfig.hospitals) do
        list[#list + 1] = {
            name = hospital.name, label = hospital.label,
            distance = #(vector3(coords.x, coords.y, coords.z) - hospital.coords),
            coords = { hospital.coords.x, hospital.coords.y, hospital.coords.z },
        }
    end
    table.sort(list, function(a, b) return a.distance < b.distance end)
    return list
end)
