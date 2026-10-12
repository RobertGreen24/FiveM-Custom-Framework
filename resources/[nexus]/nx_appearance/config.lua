-- Nexus :: nx_appearance/config.lua
--
-- Character creator, clothing shops and the wardrobe.

AppearanceConfig = {
    command         = 'appearance',   -- re-open the creator (finish mode)
    clothingCommand = 'outfit',       -- save/load outfits
    barberCommand   = 'barber',
    tattooCommand   = 'tattoo',
    wardrobeCommand = 'wardrobe',

    -- Creator
    creatorCamera   = true,
    defaultModel    = 'mp_m_freemode_01',
    femaleModel     = 'mp_f_freemode_01',
    pedRotationPeriod = 12000,        -- ms per full turn in the creator

    -- Clothing shops can be used by anyone; barbers/tattooists charge.
    barberPrice     = 250,
    tattooPrice     = 450,            -- per tattoo
    outfitSlots     = 10,             -- saved outfit slots per character
    saveCost        = 0,              -- 0 = wardrobe is free

    -- Items that must be worn for the job (checked by other resources)
    uniforms = {
        police = {
            male   = { components = {
                { id = 11, drawable = 55, texture = 0 },
                { id = 8,  drawable = 58, texture = 0 },
                { id = 4,  drawable = 35, texture = 0 },
                { id = 6,  drawable = 25, texture = 0 },
            } },
            female = { components = {
                { id = 11, drawable = 48, texture = 0 },
                { id = 8,  drawable = 35, texture = 0 },
                { id = 4,  drawable = 34, texture = 0 },
                { id = 6,  drawable = 25, texture = 0 },
            } },
        },
        ambulance = {
            male   = { components = {
                { id = 11, drawable = 250, texture = 0 },
                { id = 8,  drawable = 15,  texture = 0 },
                { id = 4,  drawable = 96,  texture = 0 },
                { id = 6,  drawable = 25,  texture = 0 },
            } },
            female = { components = {
                { id = 11, drawable = 249, texture = 0 },
                { id = 8,  drawable = 14,  texture = 0 },
                { id = 4,  drawable = 99,  texture = 0 },
                { id = 6,  drawable = 25,  texture = 0 },
            } },
        },
        mechanic = {
            male   = { components = {
                { id = 11, drawable = 98, texture = 0 },
                { id = 8,  drawable = 39, texture = 0 },
                { id = 4,  drawable = 100, texture = 0 },
                { id = 6,  drawable = 25, texture = 0 },
            } },
            female = { components = {
                { id = 11, drawable = 87, texture = 0 },
                { id = 8,  drawable = 38, texture = 0 },
                { id = 4,  drawable = 97, texture = 0 },
                { id = 6,  drawable = 25, texture = 0 },
            } },
        },
    },
}

--- Clothing stores (open the wardrobe/creator in "clothes" mode).
AppearanceConfig.clothingShops = {
    { name = 'binco',     label = 'Binco',        coords = vector3(427.0, -800.0, 29.5), blip = { sprite = 73, colour = 4 } },
    { name = 'suburban',  label = 'Suburban',     coords = vector3(127.0, -212.0, 54.6), blip = { sprite = 73, colour = 4 } },
    { name = 'ponsonbys', label = 'Ponsonbys',    coords = vector3(-164.0, -303.0, 39.7), blip = { sprite = 73, colour = 4 } },
    { name = 'perseus',   label = 'Perseus',      coords = vector3(-1447.0, -242.0, 49.8), blip = { sprite = 73, colour = 4 } },
    { name = 'sandy',     label = 'Sandy Surplus',coords = vector3(613.0, 2762.0, 42.0), blip = { sprite = 73, colour = 4 } },
    { name = 'paleto',    label = 'Paleto Threads',coords = vector3(-121.0, 6470.0, 31.6), blip = { sprite = 73, colour = 4 } },
}

AppearanceConfig.barbers = {
    { name = 'barber_legion',  label = 'Hair on Hawick', coords = vector3(-32.0, -152.0, 57.1), blip = { sprite = 71, colour = 4 } },
    { name = 'barber_sandy',   label = 'Sandy Barbers',  coords = vector3(1392.0, 3611.0, 34.9), blip = { sprite = 71, colour = 4 } },
    { name = 'barber_paleto',  label = 'Paleto Cuts',    coords = vector3(-276.0, 6226.0, 31.7), blip = { sprite = 71, colour = 4 } },
}

AppearanceConfig.tattooists = {
    { name = 'tattoo_legion',  label = 'Ink Inc',      coords = vector3(1322.0, -1652.0, 52.3), blip = { sprite = 75, colour = 4 } },
    { name = 'tattoo_vinewood',label = 'The Pit',      coords = vector3(-292.0, 6200.0, 31.5),  blip = { sprite = 75, colour = 4 } },
}

--- Component/prop slot tables used by the NUI (max drawables are fetched
--- client-side at runtime, these are just labels).
AppearanceConfig.components = {
    { id = 0,  name = 'Face' },
    { id = 1,  name = 'Mask' },
    { id = 2,  name = 'Hair' },
    { id = 3,  name = 'Torso' },
    { id = 4,  name = 'Legs' },
    { id = 5,  name = 'Bags' },
    { id = 6,  name = 'Shoes' },
    { id = 7,  name = 'Accessories' },
    { id = 8,  name = 'Undershirt' },
    { id = 9,  name = 'Body Armour' },
    { id = 10, name = 'Decals' },
    { id = 11, name = 'Tops' },
}

AppearanceConfig.props = {
    { id = 0, name = 'Hat' },
    { id = 1, name = 'Glasses' },
    { id = 2, name = 'Ears' },
    { id = 6, name = 'Watch' },
    { id = 7, name = 'Bracelet' },
}

--- Face features exposed in the creator (index, label, key in the appearance
--- table). `max` is the vanilla GTA upper bound.
AppearanceConfig.faceFeatures = {
    { key = 'noseWidth',      label = 'Nose width',      max = 1.0 },
    { key = 'nosePeakHigh',   label = 'Nose height',     max = 1.0 },
    { key = 'nosePeakSize',   label = 'Nose length',     max = 1.0 },
    { key = 'noseBoneHigh',   label = 'Nose bone',       max = 1.0 },
    { key = 'nosePeakLower',  label = 'Nose tip',        max = 1.0 },
    { key = 'noseBoneTwist',  label = 'Nose twist',      max = 1.0 },
    { key = 'noseSize',       label = 'Nose size',       max = 1.0 },
    { key = 'noseHeight',     label = 'Nose position',   max = 1.0 },
    { key = 'cheekboneHigh',  label = 'Cheekbones',      max = 1.0 },
    { key = 'cheekboneWidth', label = 'Cheek width',     max = 1.0 },
    { key = 'cheekboneDepth', label = 'Cheek depth',     max = 1.0 },
    { key = 'eyeOpening',     label = 'Eyes',            max = 1.0 },
    { key = 'lipThickness',   label = 'Lips',            max = 1.0 },
    { key = 'jawBoneWidth',   label = 'Jaw width',       max = 1.0 },
    { key = 'jawBoneBack',    label = 'Jaw shape',       max = 1.0 },
    { key = 'chinBone',       label = 'Chin',            max = 1.0 },
    { key = 'chinBoneLength', label = 'Chin length',     max = 1.0 },
    { key = 'chinHole',       label = 'Chin cleft',      max = 1.0 },
    { key = 'neckThickness',  label = 'Neck',            max = 1.0 },
}

--- Hair / makeup colour palettes (indices match the GTA colour tables).
AppearanceConfig.hairColours = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63 }
AppearanceConfig.eyeColours = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31 }
