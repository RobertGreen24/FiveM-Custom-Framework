--[[
    Nexus Framework :: nx_banking (server)
    Deposits, withdrawals, transfers and savings interest.

    Every mutation goes through Nexus Player money methods, so it lands in the
    nx_transactions ledger and fires the same change events the HUD listens to.
]]

Nexus = Nexus or {}

local function locationByName(name)
    for _, location in ipairs(BankLocations) do
        if location.name == name then return location end
    end
    return nil
end

local function logTransaction(charId, account, amount, balance, kind, reason, actor)
    if not Nexus.DB.available then return end
    Nexus.DB.defer(
        'INSERT INTO nx_transactions (char_id, account, amount, balance_after, type, reason, actor) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { charId, account, amount, balance, kind, reason or '', actor or 'bank' }
    )
end

--- Pushes fresh balances to an open banking UI.
local function pushAccounts(source)
    local player = Nexus.GetPlayer(source)
    if not player then return end

    local rows = Nexus.DB.query(
        'SELECT account, amount, balance_after, type, reason, created_at FROM nx_transactions WHERE char_id = ? ORDER BY id DESC LIMIT ?',
        { player.charId, BankConfig.transactionLimit }
    )

    TriggerClientEvent('nexus:client:bankData', source, {
        money = {
            cash = player:getMoney('cash'),
            bank = player:getMoney('bank'),
            savings = player:getMoney('savings'),
            black = player:getMoney('black'),
        },
        transactions = rows or {},
        config = {
            atmFee = BankConfig.atmFee,
            transferFee = BankConfig.transferFee,
            minTransfer = BankConfig.minTransfer,
            maxTransfer = BankConfig.maxTransfer,
            atmMaxWithdraw = BankConfig.atmMaxWithdraw,
            savings = BankConfig.savings,
        },
        finance = player:getMeta('finance'),
    })
end

Nexus.BankingPush = pushAccounts

-- ===========================================================================
--  OPEN
-- ===========================================================================

RegisterNetEvent('nx_banking:open', function(locationName)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local location = locationByName(locationName)
    if not location then return end

    -- the player must actually be there (light anti-cheat on the location)
    local ped = GetPlayerPed(source)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        local coords = GetEntityCoords(ped)
        if #(coords - location.coords) > 8.0 then
            player:notify('You are not at that machine.', 'error')
            return
        end
    end

    player:setMeta('bankLocation', locationName)
    pushAccounts(source)
end)

RegisterNetEvent('nx_banking:refresh', function()
    pushAccounts(source)
end)

-- ===========================================================================
--  DEPOSIT / WITHDRAW
-- ===========================================================================

RegisterNetEvent('nx_banking:deposit', function(account, amount)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    account = (account == 'savings') and 'savings' or 'bank'
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    if not player:removeMoney('cash', amount, ('deposit to %s'):format(account)) then
        player:notify('You do not have that much cash.', 'error')
        return
    end

    if account == 'savings' and amount + player:getMoney('savings') > BankConfig.savings.maxBalance then
        player:addMoney('cash', amount, 'refund: savings limit')
        player:notify('Your savings account is full.', 'error')
        return
    end

    player:addMoney(account, amount, 'deposit')
    logTransaction(player.charId, account, amount, player:getMoney(account), 'deposit', 'cash deposit', player:getName())
    player:notify(('Deposited %s'):format(Nexus.Utils.formatMoney(amount)), 'money')
    pushAccounts(source)
end)

RegisterNetEvent('nx_banking:withdraw', function(account, amount)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    account = (account == 'savings') and 'savings' or 'bank'
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    local location = locationByName(player:getMeta('bankLocation'))
    local isAtm = location and location.type == 'atm'
    local fee = isAtm and BankConfig.atmFee or 0

    if isAtm and amount > BankConfig.atmMaxWithdraw then
        player:notify(('ATMs limit withdrawals to %s.'):format(Nexus.Utils.formatMoney(BankConfig.atmMaxWithdraw)), 'error')
        return
    end
    if player:getMoney('cash') + amount > BankConfig.maxCash then
        player:notify('You cannot carry that much cash.', 'error')
        return
    end

    if not player:removeMoney(account, amount + fee, 'withdrawal') then
        player:notify('Insufficient funds.', 'error')
        return
    end

    player:addMoney('cash', amount, 'withdrawal')
    if fee > 0 then
        logTransaction(player.charId, 'bank', fee, player:getMoney('bank'), 'fee', 'ATM fee', 'bank')
    end
    logTransaction(player.charId, account, -amount, player:getMoney(account), 'withdrawal', 'cash withdrawal', player:getName())

    player:notify(('Withdrew %s%s'):format(Nexus.Utils.formatMoney(amount), fee > 0 and (' (fee %s)'):format(Nexus.Utils.formatMoney(fee)) or ''), 'money')
    pushAccounts(source)
end)

-- ===========================================================================
--  TRANSFERS
-- ===========================================================================

--- Finds an online recipient by phone number, state id or character name.
local function findRecipient(needle)
    if not needle then return nil end
    needle = tostring(needle):gsub('%s+', '')

    -- phone number
    for _, player in ipairs(Nexus.GetPlayers()) do
        if player.phone == needle then return player end
    end

    -- account number = char id
    local byId = Nexus.GetPlayerByCharId(tonumber(needle))
    if byId then return byId end

    -- state id shown in the HUD
    local numeric = tonumber(needle)
    if numeric then
        for _, player in ipairs(Nexus.GetPlayers()) do
            if player.stateId == numeric then return player end
        end
    end

    -- name
    for _, player in ipairs(Nexus.GetPlayers()) do
        if player:getName():lower():find(needle:lower(), 1, true) then return player end
    end
    return nil
end

Nexus.FindPlayerByAccount = findRecipient

RegisterNetEvent('nx_banking:transfer', function(account, target, amount, note)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    account = (account == 'savings') and 'savings' or 'bank'
    amount = math.floor(tonumber(amount) or 0)

    if amount < BankConfig.minTransfer or amount > BankConfig.maxTransfer then
        player:notify(('Transfers must be between %s and %s.'):format(
            Nexus.Utils.formatMoney(BankConfig.minTransfer), Nexus.Utils.formatMoney(BankConfig.maxTransfer)), 'error')
        return
    end

    local recipient = findRecipient(target)
    if not recipient then
        player:notify('No account matches that number.', 'error')
        return
    end
    if recipient.source == source then
        player:notify('You cannot transfer to yourself.', 'error')
        return
    end

    local fee = math.floor(amount * (BankConfig.transferFee / 100))
    if not player:removeMoney(account, amount + fee, ('transfer to %s'):format(recipient:getName())) then
        player:notify('Insufficient funds.', 'error')
        return
    end

    recipient:addMoney('bank', amount, ('transfer from %s'):format(player:getName()))

    logTransaction(player.charId, account, -(amount + fee), player:getMoney(account), 'transfer_out',
        ('%s%s'):format(recipient:getName(), note and (' · ' .. note) or ''), player:getName())
    logTransaction(recipient.charId, 'bank', amount, recipient:getMoney('bank'), 'transfer_in',
        ('%s%s'):format(player:getName(), note and (' · ' .. note) or ''), player:getName())

    player:notify(('Transferred %s to %s'):format(Nexus.Utils.formatMoney(amount), recipient:getName()), 'money')
    recipient:notify(('You received %s from %s'):format(Nexus.Utils.formatMoney(amount), player:getName()), 'money', 8000)

    Nexus.Log.action('bank_transfer', {
        actor = player:getName(), target = recipient:getName(),
        details = ('%s from %s'):format(Nexus.Utils.formatMoney(amount), account),
    })

    pushAccounts(source)
end)

--- Cash transfer: hand over physical notes to someone standing next to you.
RegisterNetEvent('nx_banking:giveCash', function(targetSource, amount)
    local source = source
    local player = Nexus.GetPlayer(source)
    local target = Nexus.GetPlayer(tonumber(targetSource))
    if not player or not target or not player.loaded or not target.loaded then return end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    local sourcePed = GetPlayerPed(source)
    local targetPed = GetPlayerPed(target.source)
    if sourcePed and targetPed and sourcePed ~= 0 and targetPed ~= 0 then
        if #(GetEntityCoords(sourcePed) - GetEntityCoords(targetPed)) > 4.0 then
            player:notify('They are too far away.', 'error')
            return
        end
    end

    if not player:removeMoney('cash', amount, ('cash handed to %s'):format(target:getName())) then
        player:notify('You do not have that much cash.', 'error')
        return
    end
    target:addMoney('cash', amount, ('cash from %s'):format(player:getName()))

    player:notify(('Handed over %s'):format(Nexus.Utils.formatMoney(amount)), 'money')
    target:notify(('You received %s in cash'):format(Nexus.Utils.formatMoney(amount)), 'money', 8000)
end)

-- ===========================================================================
--  PAYMENT REQUESTS (invoices between players)
-- ===========================================================================

local pendingCharges = {}   -- [targetSource] = { from, amount, reason, expires }

RegisterNetEvent('nx_banking:requestCharge', function(targetSource, amount, reason)
    local source = source
    local requester = Nexus.GetPlayer(source)
    local target = Nexus.GetPlayer(tonumber(targetSource))
    if not requester or not target or not requester.loaded or not target.loaded then return end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 or amount > BankConfig.maxTransfer then
        requester:notify('That is not a valid amount.', 'error')
        return
    end

    -- must be standing together
    local from = GetPlayerPed(source)
    local to = GetPlayerPed(target.source)
    if from and to and from ~= 0 and to ~= 0 then
        if #(GetEntityCoords(from) - GetEntityCoords(to)) > 4.0 then
            requester:notify('They are too far away.', 'error')
            return
        end
    end

    pendingCharges[target.source] = {
        from = source, amount = amount, reason = reason or '',
        expires = os.time() + 60,
    }

    TriggerClientEvent('nx_banking:chargePrompt', target.source, source, amount, reason)
    requester:notify(('Payment request sent: %s'):format(Nexus.Utils.formatMoney(amount)), 'info')
end)

RegisterNetEvent('nx_banking:respondCharge', function(fromSource, amount, reason, accepted)
    local source = source
    local payer = Nexus.GetPlayer(source)
    if not payer or not payer.loaded then return end

    local pending = pendingCharges[source]
    pendingCharges[source] = nil
    if not pending or pending.expires < os.time() then return end
    if not accepted then
        local requester = Nexus.GetPlayer(pending.from)
        if requester then requester:notify('They declined the payment.', 'warning') end
        return
    end

    local requester = Nexus.GetPlayer(pending.from)
    if not requester or not requester.loaded then
        payer:notify('That player is no longer available.', 'error')
        return
    end

    amount = pending.amount
    local paid = payer:removeMoney('bank', amount, ('payment to %s'):format(requester:getName()))
    if not paid then
        paid = payer:removeMoney('cash', amount, ('payment to %s'):format(requester:getName()))
    end
    if not paid then
        payer:notify('You cannot afford that.', 'error')
        return
    end

    requester:addMoney('bank', amount, ('payment from %s'):format(payer:getName()))

    logTransaction(payer.charId, 'bank', -amount, payer:getMoney('bank'), 'invoice_out',
        ('%s · %s'):format(requester:getName(), reason ~= '' and reason or 'payment request'), payer:getName())
    logTransaction(requester.charId, 'bank', amount, requester:getMoney('bank'), 'invoice_in',
        ('%s · %s'):format(payer:getName(), reason ~= '' and reason or 'payment request'), payer:getName())

    payer:notify(('Paid %s to %s'):format(Nexus.Utils.formatMoney(amount), requester:getName()), 'money')
    requester:notify(('%s paid you %s'):format(payer:getName(), Nexus.Utils.formatMoney(amount)), 'money', 8000)
end)

-- ===========================================================================
--  SAVINGS INTEREST
-- ===========================================================================

CreateThread(function()
    if not BankConfig.savings.enabled then return end
    while true do
        Citizen.Wait(BankConfig.savings.interestInterval * 60 * 1000)
        for _, player in ipairs(Nexus.GetPlayers()) do
            local balance = player:getMoney('savings')
            if balance > 0 then
                local interest = math.floor(balance * BankConfig.savings.interestRate)
                if interest > 0 then
                    player:addMoney('savings', interest, 'savings interest')
                    logTransaction(player.charId, 'savings', interest, player:getMoney('savings'), 'interest',
                        'savings interest', 'bank')
                    player:notify(('Interest paid: %s'):format(Nexus.Utils.formatMoney(interest)), 'money', 6000, 'Savings')
                end
            end
        end
    end
end)

-- ===========================================================================
--  EXPORTS
-- ===========================================================================

exports('getBalance', function(source, account)
    local player = Nexus.GetPlayer(source)
    if not player then return 0 end
    return player:getMoney(account or 'bank')
end)

exports('getTransactions', function(source, limit)
    local player = Nexus.GetPlayer(source)
    if not player then return {} end
    return Nexus.DB.query(
        'SELECT account, amount, balance_after, type, reason, created_at FROM nx_transactions WHERE char_id = ? ORDER BY id DESC LIMIT ?',
        { player.charId, tonumber(limit) or 20 })
end)

--- Charges an account directly (fines, bills, rent). Returns false when broke.
exports('charge', function(source, account, amount, reason)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    return player:removeMoney(account or 'bank', math.floor(tonumber(amount) or 0), reason or 'charge')
end)

exports('credit', function(source, account, amount, reason)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    return player:addMoney(account or 'bank', math.floor(tonumber(amount) or 0), reason or 'credit')
end)

exports('findAccount', function(needle)
    local player = findRecipient(needle)
    if not player then return nil end
    return { source = player.source, charId = player.charId, name = player:getName(), phone = player.phone }
end)

exports('openBank', function(source, locationName) TriggerClientEvent('nx_banking:openUI', source, locationName) end)
exports('getLocations', function() return BankLocations end)
