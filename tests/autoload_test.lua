-- installed-mod: FS25_UniversalAutoload.zip UniversalAutoload.lua UniversalAutoload.getPalletIsFull UniversalAutoload.getContainerType UniversalAutoload.getContainerTypeDimensions UniversalAutoload:createLoadingPlace UniversalAutoload:getIsValidObject UniversalAutoload.getNodeObject UniversalAutoload:ualLoadingTrigger_Callback UniversalAutoload:addAvailableObject
-- installed-mod: FS25_UniversalAutoload.zip UniversalAutoload.lua UniversalAutoload:countActivePallets UniversalAutoload:isValidForLoading UniversalAutoload:getMaxSingleLength UniversalAutoload.isPlayerHoldingItem UniversalAutoload:ualGetPalletCanDischargeToTrailer UniversalAutoload:getPalletIsSelectedMaterial UniversalAutoload:getPalletIsSelectedContainer UniversalAutoload:getPalletIsSelectedLoadside UniversalAutoload.getMaterialType UniversalAutoload.getMaterialTypeName UniversalAutoload:getSelectedMaterialType UniversalAutoload:getSelectedContainerType UniversalAutoload.getContainerTypeName UniversalAutoload.isValidForManualLoading UniversalAutoload:getIsLoadingKeyAllowed UniversalAutoload:getIsLoadingVehicleAllowed UniversalAutoload.getObjectRootNode UniversalAutoload.getObjectPositionNode UniversalAutoload.getWorldTranslation UniversalAutoload.localToWorld UniversalAutoload:resetLoadingArea UniversalAutoload:resetLoadingPattern UniversalAutoload:resetLoadingLayer
-- game: dataS/scripts/vehicles/specializations/Wheels.lua Wheels:getWheelByWheelNode
-- before: tests/autoload_env.lua
-- scripts: PalletDepotStack.lua
local tests = {}
local function close(actual, expected, label)
    assert(math.abs(actual - expected) < 0.000001, label .. ': ' .. tostring(actual))
end
local function pallet(size)
    local model = PALLET_MODELS[size]
    local collision = createTransformGroup()
    setTranslation(collision, 0, model.deck, 0)
    return {configFileName = '/mods/FS25_PalletDepot/vehicles/depotPallet' .. size .. '.xml',
        i3dFilename = '/mods/FS25_PalletDepot/vehicles/depotPallet' .. size .. '.i3d',
        isAddedToPhysics = true, size = {width = model.width, height = model.height, length = model.length},
        -- FS25 stores mapping records, not numeric node IDs (Wheels:getWheelByWheelNode).
        i3dMappings = {contentCollision = {nodeId = collision}}}
end

function tests.cachedOversizePalletStillPacksThreeAcrossUsingRealAutoload()
    PalletDepotStack.installAutoload()
    for _, size in ipairs({1000, 2500, 5000}) do
        local object = pallet(size)
        local bad = {sizeX = 1.3, sizeY = 1.6, sizeZ = 0.95, name = object.configFileName,
            width = 0.95, length = 1.3, offset = {x = 0.05, y = 0.1, z = 0.05}, type = 'EURO_PALLET'}
        UniversalAutoload.LOADING_TYPES[object.i3dFilename] = bad
        local before = {spec_universalAutoload = {loadArea = {{width = 2.44, length = 13.4,
            height = 2.5, startNode = createTransformGroup()}}, currentLayerCount = 0,
            currentLayerHeight = 0, nextLayerHeight = 0}}
        UniversalAutoload.createLoadingPlace(before, bad)
        close(before.spec_universalAutoload.currentActualWidth / 0.95, 2,
            'bad cached measurement reproduces two across')
        local corrected = UniversalAutoload.getContainerType(object)
        close(corrected.sizeX, 1.2, 'pallet width')
        close(corrected.sizeZ, 0.8, 'pallet length')
        close(corrected.sizeY, PALLET_MODELS[size].height, 'full pallet height')
        assertEqual(bad.sizeX, 1.3, 'shared cached type is untouched')
        assertEqual(bad.offset.x, 0.05, 'shared offset is untouched')
        local trailer = {spec_universalAutoload = {loadArea = {{width = 2.44, length = 13.4,
            height = 2.5, startNode = createTransformGroup()}}, currentLayerCount = 0,
            currentLayerHeight = 0, nextLayerHeight = 0}}
        for index, expected in ipairs({{0.8, -0.6}, {0, -0.6}, {-0.8, -0.6}, {0.8, -1.8}}) do
            UniversalAutoload.createLoadingPlace(trailer, corrected)
            local place = trailer.spec_universalAutoload.currentLoadingPlace
            assert(place, 'real Autoload should create place ' .. index)
            local x, y, z = getTranslation(place.node)
            close(x, expected[1], 'three-wide column')
            close(z, expected[2], 'row spacing')
            close(place.rotation, math.pi / 2, 'narrow side across the trailer')
        end
    end
end

function tests.partialHeightFollowsCollisionWithoutChangingOtherPallets()
    local full = pallet(5000)
    local partial = pallet(5000)
    local cached = {sizeX = 1.3, sizeY = 1.6, sizeZ = 0.95, offset = {x = 0, y = 0, z = 0}}
    AUTOLOAD_NODES[partial.i3dMappings.contentCollision.nodeId].scale[2] = 0.5
    local small = PalletDepotStack.getAutoloadType(partial, cached)
    local large = PalletDepotStack.getAutoloadType(full, cached)
    close(small.sizeY, 0.804, 'three layers on a partly emptied 5K pallet')
    close(large.sizeY, 1.464, 'another full 5K pallet')
    close(cached.sizeY, 1.6, 'cached source type is isolated')
    AUTOLOAD_NODES[partial.i3dMappings.contentCollision.nodeId].scale[2] = 0.001
    close(PalletDepotStack.getAutoloadType(partial, cached).sizeY, 0.14532, 'empty collision scale')
end

function tests.otherPalletsNilAndAbsentAutoloadKeepTheirBehavior()
    local object = pallet(5000)
    local cached = {sizeX = 2.8, sizeY = 0.95, sizeZ = 0.95}
    object.configFileName = '/otherMod/woodBeamPallet.xml'
    UniversalAutoload.LOADING_TYPES[object.i3dFilename] = cached
    PalletDepotStack.installAutoload()
    assertEqual(UniversalAutoload.getContainerType(object), cached, 'other mod pallets are untouched')
    assertEqual(UniversalAutoload.getContainerType(nil), nil, 'nil objects retain UAL behavior')
    assertEqual(PalletDepotStack.getAutoloadType(pallet(5000), nil), nil, 'not-yet-measurable objects wait')
    local wrapper = UniversalAutoload.getContainerType
    PalletDepotStack.installAutoload()
    assertEqual(UniversalAutoload.getContainerType, wrapper, 'installation is idempotent')
    local old = _G.FS25_UniversalAutoload
    _G.FS25_UniversalAutoload = nil
    PalletDepotStack.autoloadInstalled = nil
    PalletDepotStack.installAutoload()
    assertEqual(PalletDepotStack.autoloadInstalled, nil, 'Autoload is optional')
    _G.FS25_UniversalAutoload = old
    PalletDepotStack.autoloadInstalled = true
end

function tests.pickupTriggerRecognizesRealMappingRecordsBeforeAddingPallets()
    PalletDepotStack.installAutoload()
    g_currentMission.nodeToObject = {}
    g_currentMission.getNodeObject = function(_, node) return g_currentMission.nodeToObject[node] end
    g_currentMission.accessHandler = {canFarmAccess = function(_, farm, object)
        return farm == object:getOwnerFarmId()
    end}
    AccessHandler = {NOBODY = 0}
    g_currentMission.players = {}
    local root = createTransformGroup()
    local trailer = {rootNode = root, components = {{node = root}},
        getActiveFarm = function() return 2 end,
        ualGetIsFilled = function() return false end, ualGetIsAttaching = function() return false end,
        spec_universalAutoload = {availableObjects = {}, loadedObjects = {}, autoLoadingObjects = {},
            totalAvailableCount = 0, validLoadCount = 0, validUnloadCount = 0,
            isAutoloadAvailable = true, currentMaterialIndex = 1, currentContainerIndex = 1,
            currentLoadside = 'both', loadArea = {{length = 13.4}}}}
    for _, size in ipairs({1000, 2500, 5000}) do
        local object = pallet(size)
        object.rootNode = createTransformGroup()
        object.spec_fillUnit = {fillUnits = {{fillType = 5}}}
        object.getOwnerFarmId = function() return 2 end
        g_currentMission.nodeToObject[object.rootNode] = object
        UniversalAutoload.LOADING_TYPES[object.i3dFilename] = {
            sizeX = 1.3, sizeY = 1.6, sizeZ = 0.95, type = 'EURO_PALLET',
            offset = {x = 0, y = 0, z = 0}}
        -- Real UAL callback -> getIsValidObject -> our wrapper -> engine transform getters.
        UniversalAutoload.ualLoadingTrigger_Callback(trailer, 1, object.rootNode, true, false, false, 0)
        assertEqual(trailer.spec_universalAutoload.availableObjects[object], object,
            'pickup detection must add the depot pallet')
    end
    assertEqual(trailer.spec_universalAutoload.totalAvailableCount, 3, 'all three sizes are detected')
    UniversalAutoload.countActivePallets(trailer)
    assertEqual(trailer.spec_universalAutoload.validLoadCount, 3, 'all detected sizes qualify for loading')
    assertEqual(UniversalAutoload.getIsLoadingKeyAllowed(trailer), true,
        'recognized eligible pallets enable the loading action')
    trailer.spec_universalAutoload.currentMaterialIndex = 2
    trailer.spec_universalAutoload.countedPallets = nil
    UniversalAutoload.countActivePallets(trailer)
    assertEqual(trailer.spec_universalAutoload.validLoadCount, 0, 'material filter remains in force')
    assertEqual(UniversalAutoload.getIsLoadingKeyAllowed(trailer), false,
        'loading action remains disabled for excluded materials')
    local foreign = pallet(5000)
    foreign.getOwnerFarmId = function() return 3 end
    assertEqual(UniversalAutoload.getIsValidObject(trailer, foreign), false,
        'farm access rules remain in force')
end

function tests.mappingFixtureMatchesTheGamesOwnNodeLookup()
    local object = pallet(5000)
    local wheel = {repr = object.i3dMappings.contentCollision.nodeId}
    object.spec_wheels = {wheels = {wheel}}
    assertEqual(Wheels.getWheelByWheelNode(object, 'contentCollision'), wheel,
        'mapping records must resolve through the real game node lookup')
end

function tests.unavailableCollisionMappingKeepsAutoloadMeasurement()
    local object = pallet(5000)
    local measured = {sizeX = 1.3, sizeY = 1.6, sizeZ = 0.95}
    for _, mappings in ipairs({{}, {contentCollision = {}}, {contentCollision = {nodeId = 0}}}) do
        object.i3dMappings = mappings
        assertEqual(PalletDepotStack.getAutoloadType(object, measured), measured,
            'unresolved collision mapping retains measured dimensions')
    end
    object.i3dMappings = nil
    assertEqual(PalletDepotStack.getAutoloadType(object, measured), measured,
        'absent mapping retains measured dimensions')
end

return tests
