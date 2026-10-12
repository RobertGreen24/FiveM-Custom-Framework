--[[
    Nexus Framework :: shared/items.lua
    The single source of truth for every item on the server.

    An item definition accepts:
        label        string          display name
        weight       number          grams (1000 = 1kg)
        type         Nexus.ItemTypes
        stack        boolean         false = one per slot (weapons, phones)
        close        boolean         close inventory when used
        description  string          tooltip body
        rarity       string          common | uncommon | rare | epic | legendary
        usable       boolean         shows the "Use" button
        consumable   boolean         removes one on use (usually implied by usable)
        onUse        fn(source, item, inventory)  server callback
        onUseClient  fn(item)                     client callback (no removal)
        requiresDuty boolean          only usable while on duty
        jobs         table            restrict to a job or list of jobs
        rare         boolean          hidden from the crafting/dev item list
        image        string           overrides the default icon path
        metadata     table            default metadata keys
]]

Nexus = Nexus or {}
Nexus.Items = {}

--- Shorthand -----------------------------------------------------------------
local ITEM, WEAPON, AMMO, FOOD, DRINK, MEDICAL, TOOL, CLOTHING, KEY, MISC =
    'item', 'weapon', 'ammo', 'food', 'drink', 'medical', 'tool', 'clothing', 'key', 'misc'

--- Registers an item. Called by definitions below and by add-on resources. ---
---@param name string
---@param data table
function Nexus.RegisterItem(name, data)
    assert(type(name) == 'string', 'RegisterItem: name must be a string')
    assert(type(data) == 'table', 'RegisterItem: data must be a table')
    data.name = name
    data.label = data.label or (name:gsub('_', ' '):gsub('^%l', string.upper))
    data.weight = data.weight or 100
    data.type = data.type or ITEM
    data.rarity = data.rarity or 'common'
    data.stack = (data.stack ~= false)
    data.description = data.description or ''
    data.image = data.image or ('items/' .. name .. '.png')
    Nexus.Items[name] = data
    return Nexus.Items[name]
end

--- Looks up an item definition. Returns nil when unknown (callers should
--- treat unknown items as junk rather than erroring, so a bad row can never
--- halt a resource).
function Nexus.GetItem(name)
    return Nexus.Items[name]
end

function Nexus.GetItemLabel(name)
    local def = Nexus.Items[name]
    return def and def.label or tostring(name)
end

function Nexus.GetItemWeight(name, amount)
    local def = Nexus.Items[name]
    if not def then return 0 end
    return def.weight * (tonumber(amount) or 1)
end

--- Iterate every registered item (used by the admin item browser).
function Nexus.GetAllItems()
    return Nexus.Items
end

--- Returns true when the item is usable by this job.
function Nexus.ItemAllowedForJob(name, job)
    local def = Nexus.Items[name]
    if not def or not def.jobs then return true end
    if type(def.jobs) == 'string' then return def.jobs == job end
    return Nexus.Utils.contains(def.jobs, job)
end

--- Generic handler registry: items without a bespoke onUse can declare
--- `effect = 'hunger' | 'thirst' | 'health' | 'armour'` etc.
local effects = {
    hunger       = function(source, item, value) exports.nx_core:addVital(source, 'hunger', value) end,
    thirst       = function(source, item, value) exports.nx_core:addVital(source, 'thirst', value) end,
    health       = function(source, item, value) exports.nx_core:addVital(source, 'health', value) end,
    armour       = function(source, item, value) exports.nx_core:addVital(source, 'armour', value) end,
    stress       = function(source, item, value) exports.nx_core:addVital(source, 'stress', value) end,
}

function Nexus.applyItemEffect(source, effect, value)
    local fn = effects[effect]
    if fn then
        fn(source, nil, value)
        return true
    end
    return false
end

-- ============================================================================
--  CONSUMABLES
-- ============================================================================

Nexus.RegisterItem('water', {
    label = 'Bottled Water', weight = 500, type = DRINK, usable = true,
    description = 'Cold, clean water. Restores thirst.', effect = { thirst = 35, hunger = 2 },
})

Nexus.RegisterItem('water_bottle_full', {
    label = 'Full Water Bottle', weight = 750, type = DRINK, usable = true,
    description = 'Refillable bottle, straight from the tap.', effect = { thirst = 45 },
})
Nexus.RegisterItem('water_bottle_empty', {
    label = 'Empty Water Bottle', weight = 250, type = MISC,
    description = 'Fill it at a sink to reuse it.',
})

Nexus.RegisterItem('soda', {
    label = 'eCola', weight = 500, type = DRINK, usable = true,
    description = 'A cold can of eCola. Restores thirst.', effect = { thirst = 30, hunger = 4, stress = -3 },
})

Nexus.RegisterItem('sprunk', {
    label = 'Sprunk', weight = 500, type = DRINK, usable = true,
    description = 'The green stuff. Restores thirst.', effect = { thirst = 32, hunger = 4, stress = -4 },
})

Nexus.RegisterItem('coffee', {
    label = 'Coffee', weight = 400, type = DRINK, usable = true,
    description = 'Warm and strong. Wakes you up.', effect = { thirst = 15, stress = -8 },
})

Nexus.RegisterItem('burger', {
    label = 'Burger', weight = 800, type = FOOD, usable = true,
    description = 'Greasy and glorious.', effect = { hunger = 45, stress = -2 },
})

Nexus.RegisterItem('sandwich', {
    label = 'Sandwich', weight = 400, type = FOOD, usable = true,
    description = 'Packed lunch energy.', effect = { hunger = 35 },
})

Nexus.RegisterItem('donut', {
    label = 'Donut', weight = 300, type = FOOD, usable = true,
    description = 'Police issue. Still counts.', effect = { hunger = 20, stress = -5 },
})

Nexus.RegisterItem('taco', {
    label = 'Taco', weight = 400, type = FOOD, usable = true,
    description = 'Three bites, pure joy.', effect = { hunger = 32 },
})

Nexus.RegisterItem('hotdog', {
    label = 'Hot Dog', weight = 450, type = FOOD, usable = true,
    description = 'Street meat. You have made your choice.', effect = { hunger = 34, stress = -3 },
})

Nexus.RegisterItem('pizza', {
    label = 'Pizza Slice', weight = 350, type = FOOD, usable = true,
    description = 'A single slice. Nobody stops at one.', effect = { hunger = 30 },
})

Nexus.RegisterItem('chips', {
    label = 'Chips', weight = 250, type = FOOD, usable = true,
    description = 'Salt, but make it a meal.', effect = { hunger = 18 },
})

Nexus.RegisterItem('cigarette', {
    label = 'Cigarette', weight = 50, type = MISC, usable = true,
    description = 'It does not help anything. Helps a bit though.', effect = { stress = -12 },
})

Nexus.RegisterItem('joint', {
    label = 'Joint', weight = 60, type = MISC, usable = true,
    description = 'Relaxing, if illegal.', effect = { stress = -25, hunger = 5 },
})

Nexus.RegisterItem('beer', {
    label = 'Beer', weight = 600, type = DRINK, usable = true,
    description = 'Cold lager. Pairs well with bad decisions.', effect = { thirst = 20, stress = -10 },
})

Nexus.RegisterItem('whiskey', {
    label = 'Whiskey', weight = 700, type = DRINK, usable = true,
    description = 'A measure of something older than you.', effect = { thirst = 12, stress = -18 },
})

Nexus.RegisterItem('wine', {
    label = 'Marlowe Red', weight = 800, type = DRINK, usable = true,
    description = 'Locally pressed. Mostly honest.', effect = { thirst = 14, stress = -14 },
})

Nexus.RegisterItem('energy_drink', {
    label = 'Energy Drink', weight = 450, type = DRINK, usable = true,
    description = 'Fixes exactly one problem and creates two.', effect = { thirst = 25, stress = 5 },
})

Nexus.RegisterItem('snack_bar', {
    label = 'Protein Bar', weight = 200, type = FOOD, usable = true,
    description = 'Tastes like the number 4.', effect = { hunger = 22 },
})

-- ============================================================================
--  MEDICAL
-- ============================================================================

Nexus.RegisterItem('bandage', {
    label = 'Bandage', weight = 100, type = MEDICAL, usable = true,
    description = 'Stops the bleeding. Mostly.', effect = { health = 20 },
})

Nexus.RegisterItem('painkillers', {
    label = 'Painkillers', weight = 80, type = MEDICAL, usable = true,
    description = 'Take two and get back out there.', effect = { health = 15, stress = -20 },
})

Nexus.RegisterItem('medikit', {
    label = 'Medikit', weight = 2500, type = MEDICAL, usable = true,
    description = 'Full trauma kit. EMS issue.', effect = { health = 75 },
    jobs = { 'ambulance' },
})

Nexus.RegisterItem('defibrillator', {
    label = 'Defibrillator', weight = 4000, type = MEDICAL,
    description = 'Restarts a stopped heart. Use on a downed player.', jobs = { 'ambulance' },
})

Nexus.RegisterItem('blood_bag', {
    label = 'Blood Bag', weight = 900, type = MEDICAL,
    description = 'O negative, if you are lucky.', jobs = { 'ambulance' },
})

Nexus.RegisterItem('epipen', {
    label = 'Epinephrine Pen', weight = 70, type = MEDICAL, usable = true,
    description = 'Emergency stimulant.', effect = { health = 25, stress = 10 },
})

Nexus.RegisterItem('stretcher', {
    label = 'Stretcher', weight = 8000, type = TOOL,
    description = 'Folds into the ambulance.', jobs = { 'ambulance' },
})

-- ============================================================================
--  TOOLS / EQUIPMENT
-- ============================================================================

Nexus.RegisterItem('phone', {
    label = 'Phone', weight = 250, type = ITEM, stack = false,
    description = 'Your lifeline. Opens the NexusOS phone.',
    metadata = { number = nil, battery = 100 },
})

Nexus.RegisterItem('radio', {
    label = 'Radio', weight = 350, type = ITEM, stack = false,
    description = 'Department radio. Access dispatch channels.',
})

Nexus.RegisterItem('lockpick', {
    label = 'Lockpick', weight = 150, type = TOOL, usable = true,
    description = 'A tension wrench and hope.',
})

Nexus.RegisterItem('advanced_lockpick', {
    label = 'Advanced Lockpick', weight = 200, type = TOOL, usable = true,
    description = 'Picks cars without the drama.', rarity = 'uncommon',
})

Nexus.RegisterItem('screwdriver', {
    label = 'Screwdriver', weight = 220, type = TOOL, usable = true,
    description = 'Flathead. Useful for plates and dashboards.',
})

Nexus.RegisterItem('screwdriverset', {
    label = 'Screwdriver Set', weight = 900, type = TOOL,
    description = 'Every head you will ever need.', jobs = { 'mechanic' },
})

Nexus.RegisterItem('wrench', {
    label = 'Wrench', weight = 700, type = TOOL,
    description = 'Vehicle repairs, tools of the trade.', jobs = { 'mechanic' },
})

Nexus.RegisterItem('repairkit', {
    label = 'Repair Kit', weight = 3000, type = TOOL, usable = true,
    description = 'Field repair. Restores engine and body.',
})

Nexus.RegisterItem('advanced_repairkit', {
    label = 'Advanced Repair Kit', weight = 3500, type = TOOL, usable = true,
    description = 'Restores a vehicle to near factory condition.', rarity = 'uncommon',
})

Nexus.RegisterItem('jerrycan', {
    label = 'Jerry Can', weight = 8000, type = TOOL, usable = true,
    description = 'Holds 20 litres of fuel.',
})

Nexus.RegisterItem('tyrekit', {
    label = 'Tyre Kit', weight = 2000, type = TOOL, usable = true,
    description = 'Swap a blown tyre roadside.',
})

Nexus.RegisterItem('cleaningkit', {
    label = 'Cleaning Kit', weight = 1200, type = TOOL, usable = true,
    description = 'Wash a vehicle without the car wash.',
})

Nexus.RegisterItem('weapon_cleaningkit', {
    label = 'Weapon Cleaning Kit', weight = 600, type = TOOL, usable = true,
    description = 'Restores weapon durability.',
})

Nexus.RegisterItem('drill', {
    label = 'Power Drill', weight = 3500, type = TOOL,
    description = 'For the ambitious criminal.', rarity = 'uncommon',
})

Nexus.RegisterItem('thermite', {
    label = 'Thermite', weight = 700, type = TOOL, usable = true,
    description = 'Burns through almost anything.', rarity = 'rare',
})

Nexus.RegisterItem('c4', {
    label = 'C4 Charge', weight = 1200, type = TOOL, usable = true,
    description = 'Shaped charge. Very loud.', rarity = 'epic',
})

Nexus.RegisterItem('hacking_device', {
    label = 'Hacking Device', weight = 500, type = TOOL, usable = true,
    description = 'Bypasses electronic locks.', rarity = 'rare',
})

Nexus.RegisterItem('gps_tracker', {
    label = 'GPS Tracker', weight = 200, type = TOOL, usable = true,
    description = 'Attach it and watch the map.', rarity = 'uncommon',
})

Nexus.RegisterItem('binoculars', {
    label = 'Binoculars', weight = 800, type = TOOL, usable = true,
    description = 'Long distance eyes.',
})

Nexus.RegisterItem('flashlight', {
    label = 'Flashlight', weight = 400, type = TOOL, usable = true,
    description = 'Cuts through the dark.',
})

Nexus.RegisterItem('handcuffs', {
    label = 'Handcuffs', weight = 300, type = TOOL, usable = true,
    description = 'Restrain a suspect.', jobs = { 'police' },
})

Nexus.RegisterItem('zipties', {
    label = 'Zip Ties', weight = 100, type = TOOL, usable = true,
    description = 'Cheaper than handcuffs. Less reusable.', rarity = 'uncommon',
})

Nexus.RegisterItem('spikestrip', {
    label = 'Spike Strip', weight = 6000, type = TOOL, usable = true,
    description = 'Deployable tyre shredder.', jobs = { 'police' },
})

Nexus.RegisterItem('barrier', {
    label = 'Traffic Cone', weight = 2500, type = TOOL, usable = true,
    description = 'Scene management.', jobs = { 'police', 'ambulance' },
})

Nexus.RegisterItem('bodybag', {
    label = 'Body Bag', weight = 1500, type = TOOL,
    description = 'Coroner issue.', jobs = { 'ambulance' },
})

Nexus.RegisterItem('evidence_bag', {
    label = 'Evidence Bag', weight = 150, type = TOOL, usable = true,
    description = 'Tag and store physical evidence.', jobs = { 'police' },
})

Nexus.RegisterItem('fingerprint_kit', {
    label = 'Fingerprint Kit', weight = 400, type = TOOL, usable = true,
    description = 'Lift prints from a scene.', jobs = { 'police' },
})

Nexus.RegisterItem('camera', {
    label = 'Camera', weight = 700, type = TOOL, usable = true,
    description = 'Photograph evidence and scenes.', jobs = { 'police' },
})

Nexus.RegisterItem('tow_rope', {
    label = 'Tow Rope', weight = 5000, type = TOOL, usable = true,
    description = 'Drag a wreck to the shop.', jobs = { 'mechanic' },
})

Nexus.RegisterItem('spraycan', {
    label = 'Spray Can', weight = 300, type = TOOL, usable = true, stack = false,
    description = 'Tag the city.',
    metadata = { durability = 100, colour = 'red' },
})

Nexus.RegisterItem('fertilizer', {
    label = 'Fertiliser', weight = 2000, type = MISC,
    description = 'Innocent in a garden, useful elsewhere.',
})

Nexus.RegisterItem('weapon_parts', {
    label = 'Weapon Parts', weight = 900, type = MISC,
    description = 'Machined components.',
})

Nexus.RegisterItem('metal_scrap', {
    label = 'Metal Scrap', weight = 1500, type = MISC,
    description = 'Recyclable junk.',
})

Nexus.RegisterItem('plastic', {
    label = 'Plastic', weight = 400, type = MISC,
    description = 'Recycling feedstock.',
})

Nexus.RegisterItem('copper_wire', {
    label = 'Copper Wire', weight = 700, type = MISC,
    description = 'Sells well at the scrapyard.',
})

--- Gathered raw materials (mining / farming / fishing) ----------------------
Nexus.RegisterItem('stone', { label = 'Stone', weight = 2500, type = MISC, description = 'Raw quarry stone.' })
Nexus.RegisterItem('iron_ore', { label = 'Iron Ore', weight = 3000, type = MISC, description = 'Smelt it down.' })
Nexus.RegisterItem('gold_ore', { label = 'Gold Ore', weight = 3000, type = MISC, rarity = 'uncommon', description = 'Shiny.' })
Nexus.RegisterItem('iron_bar', { label = 'Iron Bar', weight = 2500, type = MISC, description = 'Refined and ready.' })
Nexus.RegisterItem('gold_bar', { label = 'Gold Bar', weight = 2000, type = MISC, rarity = 'rare', description = 'Hard currency.' })
Nexus.RegisterItem('wheat', { label = 'Wheat', weight = 900, type = MISC, description = 'Harvested grain.' })
Nexus.RegisterItem('corn', { label = 'Corn', weight = 800, type = MISC, description = 'Straight off the stalk.' })
Nexus.RegisterItem('strawberry', { label = 'Strawberry', weight = 400, type = MISC, description = 'Vine ripened.' })
Nexus.RegisterItem('wood_log', { label = 'Wood Log', weight = 4000, type = MISC, description = 'Freshly felled.' })
Nexus.RegisterItem('fish', { label = 'Fish', weight = 1200, type = MISC, description = 'Caught this morning.' })
Nexus.RegisterItem('fishing_rod', { label = 'Fishing Rod', weight = 900, type = TOOL, usable = true, description = 'Cast off from any shore.' })
Nexus.RegisterItem('pickaxe', { label = 'Pickaxe', weight = 3500, type = TOOL, usable = true, description = 'Swing it at a rock face.' })
Nexus.RegisterItem('farming_hoe', { label = 'Hoe', weight = 2000, type = TOOL, usable = true, description = 'Work the fields.' })

-- ============================================================================
--  ILLEGAL / CRIME
-- ============================================================================

Nexus.RegisterItem('cocaine', {
    label = 'Cocaine', weight = 200, type = MISC, rarity = 'uncommon',
    description = 'Highly illegal. Highly profitable.',
})
Nexus.RegisterItem('cocaine_powder', {
    label = 'Uncut Cocaine', weight = 250, type = MISC, rarity = 'uncommon',
    description = 'Needs cutting before sale.',
})
Nexus.RegisterItem('weed', {
    label = 'Weed', weight = 300, type = MISC, rarity = 'common',
    description = 'Cured buds.',
})
Nexus.RegisterItem('weed_seed', {
    label = 'Cannabis Seed', weight = 20, type = MISC,
    description = 'Plant it somewhere quiet.',
})
Nexus.RegisterItem('meth', {
    label = 'Methamphetamine', weight = 250, type = MISC, rarity = 'rare',
    description = 'Blue, crystalline, illegal.',
})
Nexus.RegisterItem('meth_powder', {
    label = 'Meth Powder', weight = 300, type = MISC, rarity = 'rare',
    description = 'Before the crystals form.',
})
Nexus.RegisterItem('heroin', {
    label = 'Heroin', weight = 200, type = MISC, rarity = 'rare',
    description = 'Cut and bagged.',
})
Nexus.RegisterItem('ecstasy', {
    label = 'Ecstasy', weight = 120, type = MISC, rarity = 'uncommon',
    description = 'Pressed tablets.',
})
Nexus.RegisterItem('joint_paper', {
    label = 'Rolling Papers', weight = 20, type = MISC,
    description = 'Every good joint starts here.',
})
Nexus.RegisterItem('money_wash_token', {
    label = 'Laundry Token', weight = 10, type = MISC, rarity = 'uncommon',
    description = 'Proof of a laundering session.',
})

--- Stolen goods -------------------------------------------------------------
Nexus.RegisterItem('stolen_watch', { label = 'Luxury Watch', weight = 300, type = MISC, rarity = 'uncommon', description = 'Still ticking.' })
Nexus.RegisterItem('stolen_phone', { label = 'Stolen Phone', weight = 250, type = MISC, description = 'Locked, but sellable.' })
Nexus.RegisterItem('stolen_tv', { label = 'Stolen TV', weight = 6000, type = MISC, description = 'Awkward to run with.' })
Nexus.RegisterItem('stolen_laptop', { label = 'Stolen Laptop', weight = 2000, type = MISC, description = 'Encrypted. Probably.' })
Nexus.RegisterItem('wanted_package', { label = 'Package', weight = 1000, type = MISC, rarity = 'uncommon', description = 'Do not open it.' })

--- Cash bundles ---------------------------------------------------------------
Nexus.RegisterItem('money_bundle', { label = 'Money Bundle', weight = 300, type = MISC, rarity = 'uncommon', description = 'Rubber banded notes.' })
Nexus.RegisterItem('marked_bills', { label = 'Marked Bills', weight = 250, type = MISC, rarity = 'rare', description = 'Best laundered before spending.' })

-- ============================================================================
--  CLOTHING / MISC
-- ============================================================================

Nexus.RegisterItem('clothing_bag', {
    label = 'Clothing Bag', weight = 1200, type = CLOTHING, stack = false,
    description = 'A saved outfit, folded up.',
    metadata = { outfit = nil },
})

Nexus.RegisterItem('backpack_small', {
    label = 'Small Backpack', weight = 500, type = CLOTHING,
    description = '+5000 carry weight while worn.', metadata = { capacity = 5000 },
})

Nexus.RegisterItem('backpack_large', {
    label = 'Large Backpack', weight = 900, type = CLOTHING,
    description = '+12000 carry weight while worn.', metadata = { capacity = 12000 },
})

Nexus.RegisterItem('id_card', {
    label = 'ID Card', weight = 20, type = ITEM, stack = false,
    description = 'Government issued identification.',
})

Nexus.RegisterItem('driving_licence', {
    label = 'Driving Licence', weight = 20, type = ITEM, stack = false,
    description = 'Class B entitlement.',
})

Nexus.RegisterItem('weapon_licence', {
    label = 'Firearms Licence', weight = 20, type = ITEM, stack = false,
    description = 'Permitted to carry.',
})

Nexus.RegisterItem('lottery_ticket', {
    label = 'Lottery Ticket', weight = 10, type = MISC, usable = true,
    description = 'Scratch and pray.',
})

Nexus.RegisterItem('scratchcard', {
    label = 'Scratch Card', weight = 10, type = MISC, usable = true,
    description = 'A dollar and a dream.',
})

Nexus.RegisterItem('newspaper', {
    label = 'Newspaper', weight = 400, type = MISC, usable = true,
    description = 'Los Santos Today.',
})

Nexus.RegisterItem('book', {
    label = 'Book', weight = 600, type = MISC, usable = true,
    description = 'Reduces stress. Slowly.',
})

Nexus.RegisterItem('umbrella', {
    label = 'Umbrella', weight = 700, type = MISC, usable = true,
    description = 'For the two days a year it rains.',
})

Nexus.RegisterItem('mask', {
    label = 'Balaclava', weight = 200, type = CLOTHING, stack = false,
    description = 'Hides a face, invites attention.',
})

Nexus.RegisterItem('harness', {
    label = 'Climbing Harness', weight = 1500, type = CLOTHING,
    description = 'For the more vertical jobs.',
})

Nexus.RegisterItem('parachute', {
    label = 'Parachute', weight = 6000, type = TOOL, usable = true,
    description = 'Single use, high reward.',
})

Nexus.RegisterItem('flour', { label = 'Flour', weight = 1000, type = MISC, description = 'Baking supplies.' })
Nexus.RegisterItem('dough', { label = 'Dough', weight = 1100, type = MISC, description = 'Ready to bake.' })
Nexus.RegisterItem('bread', { label = 'Bread', weight = 700, type = FOOD, usable = true, description = 'Fresh out of the oven.', effect = { hunger = 25 } })

--- Cash as a physical item, used by robberies and drops ---------------------
Nexus.RegisterItem('cash', {
    label = 'Cash', weight = 0, type = 'money', stack = true,
    description = 'Stack of bills.', rare = true,
})

-- ============================================================================
--  AMMUNITION
-- ============================================================================

local ammoTypes = {
    pistol      = { label = 'Pistol Ammo',   weight = 12 },
    smg         = { label = 'SMG Ammo',      weight = 14 },
    rifle       = { label = 'Rifle Ammo',    weight = 18 },
    shotgun     = { label = 'Shotgun Shells',weight = 24 },
    sniper      = { label = 'Sniper Ammo',   weight = 30 },
    mg          = { label = 'MG Ammo',       weight = 22 },
    heavy       = { label = 'Heavy Ammo',    weight = 40 },
}

for name, data in pairs(ammoTypes) do
    Nexus.RegisterItem('ammo_' .. name, {
        label = data.label, weight = data.weight, type = AMMO,
        description = 'Box of ammunition.',
    })
end

-- ============================================================================
--  WEAPONS
-- ============================================================================

--- Weapons are generated from the table below so every gun shares the same
--- shape (durability metadata, ammo bookkeeping, licence requirements).
local weapons = {
    -- melee
    { 'weapon_knife',        'Knife',            'melee',     0,     nil,      nil },
    { 'weapon_machete',      'Machete',          'melee',     0,     nil,      nil },
    { 'weapon_hatchet',      'Hatchet',          'melee',     0,     nil,      nil },
    { 'weapon_crowbar',      'Crowbar',          'melee',     0,     nil,      nil },
    { 'weapon_hammer',       'Hammer',           'melee',     0,     nil,      nil },
    { 'weapon_bat',          'Baseball Bat',     'melee',     0,     nil,      nil },
    { 'weapon_golfclub',     'Golf Club',        'melee',     0,     nil,      nil },
    { 'weapon_bottle',       'Bottle',           'melee',     0,     nil,      nil },
    { 'weapon_knuckle',      'Knuckle Dusters',  'melee',     0,     nil,      nil },
    -- handguns
    { 'weapon_pistol',       'Pistol',           'handgun',   1000,  'ammo_pistol',  'weapon_licence' },
    { 'weapon_pistol50',     'Pistol .50',       'handgun',   1500,  'ammo_pistol',  'weapon_licence' },
    { 'weapon_combatpistol', 'Combat Pistol',    'handgun',   1200,  'ammo_pistol',  'weapon_licence' },
    { 'weapon_appistol',     'AP Pistol',        'handgun',   1400,  'ammo_pistol',  'weapon_licence' },
    { 'weapon_pistol_mk2',   'Pistol MK2',       'handgun',   1800,  'ammo_pistol',  'weapon_licence' },
    -- smg
    { 'weapon_microsmg',     'Micro SMG',        'smg',       1800,  'ammo_smg',     'weapon_licence' },
    { 'weapon_smg',          'SMG',              'smg',       2400,  'ammo_smg',     'weapon_licence' },
    { 'weapon_assaultsmg',   'Assault SMG',      'smg',       2600,  'ammo_smg',     'weapon_licence' },
    -- shotguns
    { 'weapon_pumpshotgun',  'Pump Shotgun',     'shotgun',   2900,  'ammo_shotgun', 'weapon_licence' },
    { 'weapon_sawnoffshotgun','Sawn-Off Shotgun','shotgun',   2500,  'ammo_shotgun', nil },
    { 'weapon_assaultshotgun','Assault Shotgun', 'shotgun',   3600,  'ammo_shotgun', 'weapon_licence' },
    -- rifles
    { 'weapon_assaultrifle', 'Assault Rifle',    'rifle',     3400,  'ammo_rifle',   'weapon_licence' },
    { 'weapon_carbinerifle', 'Carbine Rifle',    'rifle',     3300,  'ammo_rifle',   'weapon_licence' },
    { 'weapon_advancedrifle', 'Advanced Rifle',  'rifle',     3200,  'ammo_rifle',   'weapon_licence' },
    { 'weapon_specialcarbine','Special Carbine', 'rifle',     3500,  'ammo_rifle',   'weapon_licence' },
    { 'weapon_bullpuprifle', 'Bullpup Rifle',    'rifle',     3400,  'ammo_rifle',   'weapon_licence' },
    -- mg
    { 'weapon_mg',           'Machine Gun',      'machinegun',6000,  'ammo_mg',      'weapon_licence' },
    { 'weapon_combatmg',     'Combat MG',        'machinegun',6400,  'ammo_mg',      'weapon_licence' },
    -- snipers
    { 'weapon_sniperrifle',  'Sniper Rifle',     'sniper',    6000,  'ammo_sniper',  'weapon_licence' },
    { 'weapon_heavysniper',  'Heavy Sniper',     'sniper',    7500,  'ammo_sniper',  'weapon_licence' },
    { 'weapon_marksmanrifle','Marksman Rifle',   'sniper',    4800,  'ammo_sniper',  'weapon_licence' },
    -- throwable
    { 'weapon_grenade',      'Grenade',          'throwable', 600,   nil,            nil },
    { 'weapon_stickybomb',   'Sticky Bomb',      'throwable', 600,   nil,            nil },
    { 'weapon_molotov',      'Molotov',          'throwable', 500,   nil,            nil },
    { 'weapon_snowball',     'Snowball',         'throwable', 200,   nil,            nil },
    -- misc
    { 'weapon_stungun',      'Taser',            'handgun',   900,   nil,            nil },
    { 'weapon_flaregun',     'Flare Gun',        'handgun',   900,   nil,            nil },
    { 'weapon_fireextinguisher','Fire Extinguisher','misc',   2500,  nil,            nil },
    { 'weapon_petrolcan',    'Petrol Can',       'misc',      3000,  nil,            nil },
}

for _, w in ipairs(weapons) do
    local name, label, wtype, weight, ammo, licence = w[1], w[2], w[3], w[4], w[5], w[6]
    Nexus.RegisterItem(name, {
        label = label,
        weight = weight,
        type = 'weapon',
        stack = false,
        usable = (wtype ~= 'throwable'),
        equippable = true,
        weaponType = wtype,
        ammoItem = ammo,
        requiresLicence = licence,
        rarity = (wtype == 'melee' and 'common' or 'uncommon'),
        description = ('%s · %s'):format(label, wtype),
        metadata = { durability = 100, ammo = 0, serial = nil, registered = false },
    })
end

-- ============================================================================
--  Compat shims so external resources (ox_inventory style) can read the table
-- ============================================================================

Nexus.ItemsByName = Nexus.Items
