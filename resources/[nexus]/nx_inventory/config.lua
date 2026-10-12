-- Nexus :: nx_inventory/config.lua

InvConfig = {
    -- Player grid
    playerSlots   = 40,
    playerWeight  = 40000,       -- grams; backpacks add to this

    -- Containers
    trunkSlots    = 35,
    trunkWeight   = 75000,
    gloveboxSlots = 10,
    gloveboxWeight= 12000,
    stashSlots    = 50,
    stashWeight   = 100000,
    dropSlots     = 12,
    dropWeight    = 10000,

    hotbarSlots   = 5,

    -- Weight of the empty container itself when carried (backpacks etc)
    backpackWeight = true,

    -- Interaction
    keyOpen       = 289,          -- F2 (config also accepts a key mapping string)
    keyHotbar     = { 157, 158, 159, 160, 161 },   -- 1..5

    -- Dropping items on the floor
    allowDrop     = true,
    dropModel     = 'prop_paper_bag_small',
    dropLifetime  = 900,          -- seconds before a ground bag rots away
    dropDistance  = 2.5,

    -- Trunks
    requireKeysForTrunk = true,
    trunkDistance = 4.0,

    -- Stashes defined in nx_stashes. Job stashes need the matching job.
    stashDistance = 2.0,

    -- Weapon behaviour
    weapons = {
        removeOnDrop  = true,     -- take the gun off the ped when the item is dropped
        giveAmmoOnUse = true,     -- using an ammo box refills the matching weapon
        durability    = true,     -- weapons wear out and jam when broken
        jamChance     = 15,       -- % chance to jam at 0 durability
    },

    -- What cannot leave the player's possession
    undroppable   = { id_card = true, driving_licence = true, weapon_licence = true },

    -- Items that cannot be placed in a trunk or glovebox
    noVehicleStorage = { backpack_small = true, backpack_large = true },

    -- Consumable timings (ms)
    consumeTime   = 3500,

    -- Money shown in the UI header
    showMoney     = true,
}
