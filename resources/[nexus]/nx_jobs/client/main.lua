--[[
    Nexus Framework :: nx_jobs (client)
    Duty points, the employment office and the job HUD bits.
]]

local Nexus = Nexus
local Client = Nexus.Client

local uiOpen = false
local centreOpen = false
local jobData = nil

-- ===========================================================================
--  BLIPS
-- ===========================================================================

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for _, point in ipairs(DutyPoints) do
        if point.blip then
            local blip = AddBlipForCoord(point.coords.x, point.coords.y, point.coords.z)
            SetBlipSprite(blip, point.blip.sprite or 407)
            SetBlipColour(blip, point.blip.colour or 4)
            SetBlipScale(blip, point.blip.scale or 0.8)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(point.label)
            EndTextCommandSetBlipName(blip)
            point._blip = blip
        end
    end

    if JobCentre.blip then
        local blip = AddBlipForCoord(JobCentre.coords.x, JobCentre.coords.y, JobCentre.coords.z)
        SetBlipSprite(blip, JobCentre.blip.sprite or 407)
        SetBlipColour(blip, JobCentre.blip.colour or 4)
        SetBlipScale(blip, JobCentre.blip.scale or 0.8)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(JobCentre.label)
        EndTextCommandSetBlipName(blip)
    end
end)

--- Show the "on duty" dot on duty blips so colleagues can find each other.
CreateThread(function()
    while true do
        Citizen.Wait(4000)
        local job = Client.getJob()
        local jobName = job.name
        local onDuty = Client.isOnDuty()

        for _, point in ipairs(DutyPoints) do
            if point._blip and point.dutyBlip then
                local relevant = point.job == jobName
                SetBlipAlpha(point._blip, (not relevant or (job and job.type == 'leo') or onDuty) and 255 or 130)
            end
        end
    end
end)

-- ===========================================================================
--  INTERACTION
-- ===========================================================================

local function nearestDutyPoint()
    local coords = GetEntityCoords(PlayerPedId())
    for _, point in ipairs(DutyPoints) do
        if #(coords - point.coords) <= JobConfig.dutyRange + 1.0 then
            return point, #(coords - point.coords)
        end
    end
    return nil
end

CreateThread(function()
    while true do
        local sleep = 500
        if Client.isLoaded() and not uiOpen then
            local point = nearestDutyPoint()
            if point then
                sleep = 0
                local jobName = Client.getJob().name
                local label

                if point.job ~= jobName then
                    label = ('%s · %s only'):format(point.label, (Nexus.GetJob(point.job) or {}).label or point.job)
                elseif Client.isOnDuty() then
                    label = 'Clock out'
                else
                    label = 'Clock in'
                end

                Nexus.TextUI(true, 'E', label)
                if IsControlJustPressed(0, 38) then
                    Nexus.TextUI(false)
                    if point.job == jobName then
                        TriggerServerEvent('nx_jobs:toggleDuty', point.name)
                    else
                        Nexus.Notify(('This is the %s workplace.'):format((Nexus.GetJob(point.job) or {}).label or point.job), 'error')
                    end
                end
            else
                local coords = GetEntityCoords(PlayerPedId())
                if #(coords - JobCentre.coords) <= 2.5 then
                    sleep = 0
                    Nexus.TextUI(true, 'E', JobCentre.label)
                    if IsControlJustPressed(0, 38) then
                        Nexus.TextUI(false)
                        TriggerServerEvent('nx_jobs:requestCentre')
                    end
                else
                    Nexus.TextUI(false)
                end
            end
        end
        Citizen.Wait(sleep)
    end
end)

-- ===========================================================================
--  JOB CENTRE UI
-- ===========================================================================

local function setFocus(state)
    uiOpen = state
    centreOpen = state
    SetNuiFocus(state, state)
    TriggerEvent('nexus:client:setUIOpen', state)
    SendNUIMessage({ action = state and 'open' or 'close', data = jobData })
end

RegisterNetEvent('nexus:client:jobCentreData', function(data)
    jobData = data
    if not uiOpen then
        setFocus(true)
    else
        SendNUIMessage({ action = 'update', data = data })
    end
end)

RegisterNUICallback('nx:close', function(_, cb)
    cb({ ok = true })
    setFocus(false)
end)

RegisterNUICallback('nx:take', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_jobs:takeJob', payload.job)
end)

RegisterNUICallback('nx:quit', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_jobs:quitJob')
end)

RegisterNUICallback('nx:refresh', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_jobs:requestCentre')
end)

-- ===========================================================================
--  COMMANDS
-- ===========================================================================

RegisterCommand('jobcentre', function()
    local coords = GetEntityCoords(PlayerPedId())
    if #(coords - JobCentre.coords) > 25.0 then
        Nexus.Notify('The employment office is in Pillbox Hill.', 'error')
        return
    end
    TriggerServerEvent('nx_jobs:requestCentre')
end, false)

RegisterCommand('jobs', function()
    local current = Client.getJob()
    local job = Nexus.GetJob(current.name)
    local grade = job and job.grades and job.grades[(current.grade or 0) + 1]
    Nexus.Notify(('%s · %s%s'):format(
        job and job.label or 'Unemployed',
        grade and grade.name or 'Civilian',
        Client.isOnDuty() and ' · on duty' or ''), 'info', 8000, 'Employment')
end, false)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if uiOpen then SetNuiFocus(false, false) end
end)

exports('openJobCentre', function() TriggerServerEvent('nx_jobs:requestCentre') end)
exports('getDutyPoints', function() return DutyPoints end)
exports('isOnDuty', function() return Client.isOnDuty() end)
