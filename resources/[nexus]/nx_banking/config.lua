-- Nexus :: nx_banking/config.lua

BankConfig = {
    -- Fees
    atmFee        = 5,       -- flat $ charged per ATM withdrawal
    transferFee   = 0,       -- % of the amount (0 = free transfers)
    minTransfer   = 10,
    maxTransfer   = 500000,

    -- Savings: interest paid every `interestInterval` minutes
    savings = {
        enabled          = true,
        interestRate     = 0.0025,   -- 0.25% per interval
        interestInterval = 60,       -- minutes
        maxBalance       = 5000000,
    },

    -- Cash handling
    maxCash       = 250000,  -- hard cap on physical cash
    atmMaxWithdraw = 25000,  -- per transaction

    -- Passwords / cards: a 4 digit PIN stored in character metadata
    requirePin    = false,

    -- Ledger shown in the UI
    transactionLimit = 40,
}

--- Locations --------------------------------------------------------------
--- type = 'atm' | 'bank' (bank = counter, no ATM fee, full services)

BankLocations = {
    { name = 'legion_atm',    label = 'Legion Square ATM', type = 'atm',  coords = vector3(147.0, -1035.5, 29.3) },
    { name = 'legion_atm2',   label = 'Legion Square ATM', type = 'atm',  coords = vector3(241.7, -762.3, 30.7) },
    { name = 'airport_atm',   label = 'LSIA ATM',          type = 'atm',  coords = vector3(-1000.5, -2721.0, 13.9) },
    { name = 'sandy_atm',     label = 'Sandy ATM',         type = 'atm',  coords = vector3(1735.0, 3653.5, 34.5) },
    { name = 'paleto_atm',    label = 'Paleto ATM',        type = 'atm',  coords = vector3(-387.0, 6053.5, 31.5) },
    { name = 'vinewood_atm',  label = 'Vinewood ATM',      type = 'atm',  coords = vector3(295.7, -896.0, 29.2) },
    { name = 'route68_atm',   label = 'Route 68 ATM',      type = 'atm',  coords = vector3(1175.0, 2706.5, 38.1) },
    { name = 'bank_legion',   label = 'Legion Bank',       type = 'bank', coords = vector3(150.5, -1042.5, 29.3) },
    { name = 'bank_pillbox',  label = 'Pillbox Bank',      type = 'bank', coords = vector3(313.0, -283.0, 53.2) },
    { name = 'bank_vinewood', label = 'Vinewood Bank',     type = 'bank', coords = vector3(-1213.0, -330.5, 37.8) },
}

BankConfig.locations = BankLocations

--- Blips shown on the map
BankConfig.blips = {
    { coords = vector3(150.5, -1042.5, 29.3), sprite = 108, colour = 2, label = 'Legion Bank' },
    { coords = vector3(313.0, -283.0, 53.2),  sprite = 108, colour = 2, label = 'Pillbox Bank' },
    { coords = vector3(-1213.0, -330.5, 37.8), sprite = 108, colour = 2, label = 'Vinewood Bank' },
    { coords = vector3(-2962.0, 482.8, 15.7),  sprite = 108, colour = 2, label = 'Pacific Standard' },
}
