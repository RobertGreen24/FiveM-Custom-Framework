--[[
    Nexus Framework :: server/society.lua
    Job/business bank accounts ("societies"): police, ambulance, mechanic...

    Society money is separate from player money. Job scripts pay wages, fines and
    repairs out of the society balance; the boss grade can withdraw it.
]]

Nexus = Nexus or {}
local Society = {}
Nexus.Society = Society

--- Loads a society row into the cache (or creates it).
function Society.get(name)
    if not name then return nil end
    Nexus.Societies = Nexus.Societies or {}

    if Nexus.Societies[name] then
        return Nexus.Societies[name]
    end

    local row = Nexus.DB.single('SELECT * FROM nx_societies WHERE name = ?', { name })
    if not row then
        -- auto-create so a new job works without a migration
        local label = Nexus.GetJobLabel(name)
        Nexus.DB.insert('INSERT IGNORE INTO nx_societies (name, label, balance) VALUES (?, ?, 0)', { name, label })
        row = { name = name, label = label, balance = 0 }
    end

    Nexus.Societies[name] = {
        name = row.name,
        label = row.label or Nexus.GetJobLabel(name),
        balance = tonumber(row.balance) or 0,
    }
    return Nexus.Societies[name]
end

function Society.getBalance(name)
    local society = Society.get(name)
    return society and society.balance or 0
end

function Society.setBalance(name, amount, reason, actor)
    local society = Society.get(name)
    if not society then return false end

    amount = math.floor(tonumber(amount) or 0)
    society.balance = math.max(0, amount)
    Nexus.DB.update('UPDATE nx_societies SET balance = ? WHERE name = ?', { society.balance, name })

    Nexus.Log.action('society_set', {
        actor = actor or 'system', target = name,
        details = ('balance -> %s (%s)'):format(Nexus.Utils.formatMoney(society.balance), reason or '-'),
    })

    TriggerEvent('nexus:server:societyChanged', name, society.balance)
    return true
end

function Society.addMoney(name, amount, reason, actor)
    local society = Society.get(name)
    if not society then return false end
    return Society.setBalance(name, society.balance + math.floor(tonumber(amount) or 0), reason, actor)
end

function Society.removeMoney(name, amount, reason, actor)
    local society = Society.get(name)
    if not society then return false end
    amount = math.floor(tonumber(amount) or 0)
    if society.balance < amount then return false end
    return Society.setBalance(name, society.balance - amount, reason, actor)
end

--- Pay every on-duty member of a job from the society balance.
---@return number paid count
function Society.payWages(jobName, amountPerPlayer, reason)
    local society = Society.get(jobName)
    if not society then return 0 end

    local players = Nexus.GetPlayersByJob(jobName, true)
    local paid = 0
    for _, player in ipairs(players) do
        if society.balance >= amountPerPlayer then
            society.balance = society.balance - amountPerPlayer
            player:addMoney('bank', amountPerPlayer, ('%s wage'):format(society.label))
            player:notify(('Wage paid: %s'):format(Nexus.Utils.formatMoney(amountPerPlayer)), 'money', 6000, society.label)
            paid = paid + 1
        end
    end

    if paid > 0 then
        Nexus.DB.update('UPDATE nx_societies SET balance = ? WHERE name = ?', { society.balance, jobName })
    end
    return paid
end

--- Online members of a job (used by boss menus).
function Society.getMembers(jobName)
    local out = {}
    for _, player in ipairs(Nexus.GetPlayersByJob(jobName)) do
        out[#out + 1] = {
            source = player.source,
            name = player:getName(),
            grade = player.job.grade,
            gradeName = player.job.gradeName,
            duty = player.job.onDuty,
        }
    end
    return out
end

--- Persist every dirty society to the DB (called on resource stop).
function Society.flush()
    if not Nexus.DB.available then return end
    for name, society in pairs(Nexus.Societies or {}) do
        Nexus.DB.update('UPDATE nx_societies SET balance = ? WHERE name = ?', { society.balance, name })
    end
end
