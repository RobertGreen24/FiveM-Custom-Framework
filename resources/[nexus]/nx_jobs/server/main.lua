--[[
    Nexus Framework :: nx_jobs (server)
    Duty clock, payroll, grades and the employment office.
]]

Nexus = Nexus or {}

local function dutyPointByName(name)
    for _, point in ipairs(DutyPoints) do
        if point.name == name then return point end
    end
    return nil
end

Nexus.DutyPoint = dutyPointByName

local function atPoint(source, coords, radius)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return true end
    return #(GetEntityCoords(ped) - coords) <= (radius or JobConfig.dutyRange)
end

--- Salary for a grade, with the configured per-grade bonus.
local function salaryFor(job, grade)
    local base = (job.salary or 0)
    local bonus = 1 + (math.max(0, grade or 0) * JobConfig.gradeBonus)
    return math.floor(base * bonus)
end

Nexus.SalaryFor = salaryFor

-- ===========================================================================
--  DUTY
-- ===========================================================================

--- Shared duty toggle. Returns true when the state changed.
local function setDuty(source, pointName, state)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return false, 'not loaded' end

    local point = dutyPointByName(pointName)
    if not point then return false, 'no such point' end

    if point.job ~= player.job.name then
        player:notify('This is not your workplace.', 'error')
        return false, 'wrong job'
    end
    if not atPoint(source, point.coords) then
        player:notify('You are too far from the duty point.', 'error')
        return false, 'too far'
    end
    if JobConfig.requireDutyPermission and not player:hasJobPermission('duty') then
        player:notify('You are not allowed to clock in.', 'error')
        return false, 'no permission'
    end

    state = state and true or false
    if state == player:isOnDuty() then return true, 'unchanged' end

    player:setDuty(state)
    player:notify(state and 'You are now on duty.' or 'You are now off duty.', 'info', 5000, player.job.label)

    if JobConfig.announceDuty then
        for _, colleague in ipairs(Nexus.GetPlayers()) do
            if colleague.source ~= source and colleague.job.name == player.job.name then
                colleague:notify(('%s is now %s'):format(player:getName(), state and 'on duty' or 'off duty'), 'info')
            end
        end
    end

    TriggerEvent('nexus:server:dutyChanged', player, state)
    return true
end

Nexus.SetDuty = setDuty

RegisterNetEvent('nx_jobs:setDuty', function(pointName, state)
    setDuty(source, pointName, state)
end)

RegisterNetEvent('nx_jobs:toggleDuty', function(pointName)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end
    setDuty(source, pointName, not player:isOnDuty())
end)

--- /duty — toggles at the nearest duty point the player can use.
RegisterCommand('duty', function(source)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then
        if source == 0 then print('nx_jobs: /duty must be used in game.') end
        return
    end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end
    local coords = GetEntityCoords(ped)

    for _, point in ipairs(DutyPoints) do
        if point.job == player.job.name and #(coords - point.coords) <= JobConfig.dutyRange then
            setDuty(source, point.name, not player:isOnDuty())
            return
        end
    end

    player:notify('You are not at a duty point for your job.', 'error')
end, false)

-- ===========================================================================
--  EMPLOYMENT OFFICE
-- ===========================================================================

RegisterNetEvent('nx_jobs:requestCentre', function()
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local jobs = {}
    for _, name in ipairs(JobConfig.jobCentre.open) do
        local job = Nexus.Jobs[name]
        if job then
            jobs[#jobs + 1] = {
                name = job.name,
                label = job.label,
                description = job.description,
                grades = #job.grades,
                salary = salaryFor(job, 0),
                current = player.job.name == job.name,
            }
        end
    end
    table.sort(jobs, function(a, b) return a.label < b.label end)

    TriggerClientEvent('nexus:client:jobCentreData', source, {
        job = player.job,
        jobs = jobs,
        duty = player:isOnDuty(),
    })
end)

RegisterNetEvent('nx_jobs:takeJob', function(jobName)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local allowed = false
    for _, name in ipairs(JobConfig.jobCentre.open) do
        if name == jobName then allowed = true end
    end
    if not allowed then
        player:notify('That job is not available here.', 'error')
        return
    end

    if not Nexus.Jobs[jobName] then return end
    if player.job.name == jobName then
        player:notify('You already work here.', 'error')
        return
    end

    local previous = player.job.name
    player:setJob(jobName, 0)
    TriggerEvent('nexus:server:jobChanged', player, jobName, previous)

    Nexus.Log.action('job_change', {
        actor = player:getName(), target = jobName,
        details = ('%s -> %s via job centre'):format(previous, jobName),
    })
    player:notify(('You are now employed as %s.'):format(player.job.label), 'success', 7000)
end)

RegisterNetEvent('nx_jobs:quitJob', function()
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end
    if player.job.name == 'unemployed' then return end

    local previous = player.job.name
    player:setJob('unemployed', 0)
    TriggerEvent('nexus:server:jobChanged', player, 'unemployed', previous)
    player:notify('You have quit your job.', 'info', 6000)
end)

-- ===========================================================================
--  GRADES / HIRING
-- ===========================================================================

--- Hiring/firing/promotion used by nx_police, nx_ems, nx_mechanic and bosses.
--- action = 'hire' | 'fire' | 'promote' | 'demote' | 'setgrade'
Nexus.JobManage = function(actor, targetCharId, jobName, grade, action)
    local target = Nexus.GetPlayerByCharId(targetCharId)
    local job = Nexus.Jobs[jobName]
    if not job then return false, 'no such job' end
    if not target or not target.loaded then return false, 'player offline' end

    grade = math.max(0, math.min(#job.grades - 1, math.floor(tonumber(grade) or 0)))

    if action == 'fire' then
        target:setJob('unemployed', 0)
        target:notify('You have been let go.', 'error', 8000)
        return true
    end

    if action == 'hire' then
        target:setJob(jobName, grade)
        target:notify(('You have been hired as %s.'):format(job.label), 'success', 8000)
        return true
    end

    -- promote / demote / setgrade
    if JobConfig.allowGradeChange and actor then
        local actorGrade = actor.job.name == jobName and actor.job.grade or -1
        local maxGrade = #job.grades - 1
        if actorGrade < maxGrade and actorGrade < 4 and not actor:isAdmin(3) then
            local delta = math.abs(grade - target.job.grade)
            if delta > JobConfig.maxGradeDelta then
                return false, 'too big a jump'
            end
            if grade > actorGrade then
                return false, 'cannot promote above yourself'
            end
        end
    end

    if target:setJob(jobName, grade) then
        target:notify(('Your rank is now %s (%s).'):format(job.grades[grade + 1].label, job.label), 'success', 8000)
        return true
    end
    return false, 'failed'
end

--- Exports used by the department resources.
exports('manage', function(actorSource, targetCharId, jobName, grade, action)
    return Nexus.JobManage(Nexus.GetPlayer(actorSource), targetCharId, jobName, grade, action)
end)

exports('hired', function(charId, jobName)
    local player = Nexus.GetPlayerByCharId(charId)
    return player ~= nil and player.loaded and player.job.name == jobName or false
end)

exports('onDutyStaff', function(jobName)
    local list = {}
    for _, player in ipairs(Nexus.GetPlayers()) do
        if player.job.name == jobName and player:isOnDuty() then
            list[#list + 1] = {
                source = player.source,
                charId = player.charId,
                name = player:getName(),
                grade = player.job.grade,
                callsign = player.callsign,
            }
        end
    end
    return list
end)

-- ===========================================================================
--  PAYROLL
-- ===========================================================================

CreateThread(function()
    while true do
        Citizen.Wait(JobConfig.payInterval * 60 * 1000)

        for _, player in ipairs(Nexus.GetPlayers()) do
            local job = Nexus.Jobs[player.job.name]
            if job and job.salary and job.salary > 0 then
                if not JobConfig.payDutyOnly or player:isOnDuty() then
                    local gross = salaryFor(job, player.job.grade)
                    local tax = math.floor(gross * JobConfig.taxRate)
                    local net = gross - tax

                    if net > 0 then
                        player:addMoney('bank', net, ('%s pay'):format(job.label))
                        player:notify(('Paycheque: %s%s'):format(
                            Nexus.Utils.formatMoney(net),
                            tax > 0 and (' (tax %s)'):format(Nexus.Utils.formatMoney(tax)) or ''),
                            'money', 8000, job.label)
                    end

                    local society = Nexus.Society.get(job.society or job.name)
                    if society and tax > 0 then
                        Nexus.Society.addMoney(society.name, tax, 'payroll tax')
                    end
                end
            end
        end
    end
end)

-- ===========================================================================
--  JOB STASHES (duty point lockers)
-- ===========================================================================

local function ensureStash(point)
    if not point.stash then return nil, nil end
    local owner = exports.nx_inventory:ensureContainer('stash:job_' .. point.name, {
        label = point.stash.label or ('%s Storage'):format(point.label),
        slots = point.stash.slots or 40,
        weight = point.stash.weight or 100000,
        persistent = true,
    })
    return owner ~= nil, owner
end

RegisterNetEvent('nx_jobs:openStash', function(pointName)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local point = dutyPointByName(pointName)
    if not point or not point.stash then return end
    if point.job ~= player.job.name then
        player:notify('That locker is not yours.', 'error')
        return
    end
    if not atPoint(source, point.coords, 3.0) then
        player:notify('You are too far from the locker.', 'error')
        return
    end

    local _, owner = ensureStash(point)
    if not owner then
        player:notify('That locker is unavailable right now.', 'error')
        return
    end
    exports.nx_inventory:openForPlayer(source, owner, {
        label = point.stash.label or point.label,
        slots = point.stash.slots or 40,
        weight = point.stash.weight or 100000,
        persistent = true,
    })
end)

CreateThread(function()
    Citizen.Wait(2000)
    for _, point in ipairs(DutyPoints) do
        if point.stash then ensureStash(point) end
    end
end)

exports('getDutyPoints', function() return DutyPoints end)
exports('getDutyPoint', function(name) return dutyPointByName(name) end)
exports('salary', function(jobName, grade) return salaryFor(Nexus.Jobs[jobName] or {}, grade) end)
