-- game: dataS/scripts/specialization/SpecializationUtil.lua SpecializationUtil.raiseEvent
-- game: dataS/scripts/vehicles/specializations/Pallet.lua Pallet:onFillUnitFillLevelChanged Pallet:setPalletTensionBeltNodesDirty Pallet:onPostLoad
-- game: dataS/scripts/vehicles/specializations/FillUnit.lua FillUnit:addFillUnitFillLevel FillUnit:getFillUnitFillLevelPercentage FillUnit:getFillUnitFillType FillUnit:getFillUnitSupportsToolTypeAndFillType FillUnit:getFillUnitSupportsToolType FillUnit:getFillUnitSupportsFillType FillUnit:getFillUnitAllowsFillType FillUnit:getFillTypeChangeThreshold FillUnit:updateFillUnitAutoAimTarget FillUnit:updateAlarmTriggers FillUnit:saveToXMLFile FillUnit:onPostLoad FillUnit:onWriteStream FillUnit:onReadStream FillUnit:setFillUnitLastValidFillType FillUnit:setFillUnitIsFilling
-- game: dataS/scripts/vehicles/specializations/AnimatedVehicle.lua AnimatedVehicle:getAnimationExists AnimatedVehicle:getAnimationTime AnimatedVehicle:setAnimationTime AnimatedVehicle:setRealAnimationTime AnimatedVehicle:resetAnimationValues AnimatedVehicle:resetAnimationPartValues AnimatedVehicle:setAnimationStopTime AnimatedVehicle:playAnimation AnimatedVehicle:stopAnimation AnimatedVehicle:getIsAnimationPlaying AnimatedVehicle:updateAnimationPart AnimatedVehicle.findCurrentPartIndex AnimatedVehicle.updateAnimationCurrentTime AnimatedVehicle.updateAnimation AnimatedVehicle.updateAnimationByName AnimatedVehicle.getDurationToEndOfPart AnimatedVehicle.getNextPartIsPlaying AnimatedVehicle.setMovedLimitedValuesN AnimatedVehicle.getMovedLimitedValue
-- game: dataS/scripts/vehicles/AnimationValueFloat.lua AnimationValueFloat:initValues AnimationValueFloat:update AnimationValueFloat:reset
-- before: tests/game_env.lua tests/stack_env.lua tests/native_cargo_env.lua
-- scripts: PalletDepotPalletMass.lua PalletDepotStack.lua PalletDepotGoodsLook.lua PalletDepotSpawnSizes.lua
-- Uses real game fill, save, stream, pallet and animation functions with XML-derived dimensions.
local tests = {}

local function close(actual, expected, label)
    if math.abs(actual - expected) > 0.000001 then
        error(label .. ': expected ' .. expected .. ', got ' .. actual, 2)
    end
end

local function shown(v)
    local count = 0
    for _, object in ipairs(v.spec_pallet.contents[1].objects) do
        if object.isActive and NODE_VISIBLE[object.node] then count = count + 1 end
    end
    return count
end

local function assertLayers(v, size, count)
    local model = PALLET_MODELS[size]
    assertEqual(shown(v), count, 'complete visible layers')
    local scale = NODE_SCALE[v.i3dMappings.contentCollision][2]
    close(scale, math.max(model.minScale, count / model.layers), 'built-in collision scale')
    local time = v:getAnimationTime('fillAnimation')
    close(model.minScale + (1 - model.minScale) * time, scale, 'animation scale matches collision')
    if count > 0 then
        close(0.144 + (model.height - 0.144) * scale, 0.144 + count * 0.22, 'collision top matches layer top')
    end
    assertEqual(v.spec_animatedVehicle.numActiveAnimations, 0, 'collision cannot drift between layers')
end

function tests.eachFullSizeShowsWholeLayersAtItsRealHeight()
    for _, size in ipairs({1000, 2500, 5000}) do
        local v = layeredPallet(size)
        PalletDepotPalletMass.applyCapacity(v, size)
        assertEqual(v:addFillUnitFillLevel(1, 1, size, 5, 0), size, 'litres preserved')
        assertLayers(v, size, PALLET_MODELS[size].layers)
    end
end

function tests.partSoldPalletFollowsFillInWholeLayers()
    local v, unit = layeredPallet(5000)
    v:addFillUnitFillLevel(1, 1, 5000, 5, 0)
    v:addFillUnitFillLevel(1, 1, -2900, 5, 0)
    assertEqual(unit.fillLevel, 2100, 'part sold litres')
    assertLayers(v, 5000, 3)
    v:addFillUnitFillLevel(1, 1, -2100, 5, 0)
    assertLayers(v, 5000, 0)
end

function tests.newEmptyPalletInitializesItsCollisionAndShowsNoGoods()
    for _, size in ipairs({1000, 2500, 5000}) do
        local v = layeredPallet(size)
        Pallet.onPostLoad(v)
        assertLayers(v, size, 0)
    end
end

function tests.allLayerBoundariesRoundUpTogether()
    for _, size in ipairs({1000, 2500, 5000}) do
        local v, unit = layeredPallet(size)
        for layer = 1, PALLET_MODELS[size].layers do
            local target = size * layer / PALLET_MODELS[size].layers
            v:addFillUnitFillLevel(1, 1, target - unit.fillLevel, 5, 0)
            assertLayers(v, size, layer)
            if layer < PALLET_MODELS[size].layers then
                v:addFillUnitFillLevel(1, 1, 1, 5, 0)
                assertLayers(v, size, layer + 1)
            end
        end
    end
end

function tests.realSaveAndLoadRestoresLitresLayersCollisionAndLook()
    for _, size in ipairs({1000, 2500, 5000}) do
        local before, unit = layeredPallet(size)
        PalletDepotPalletMass.applyCapacity(before, size)
        before:addFillUnitFillLevel(1, 1, size * 0.41, 5, 0)
        local xml = stackSaveXML()
        Vehicle.saveToXMLFile(before, xml, 'v')
        FillUnit.saveToXMLFile(before, xml, 'v.fillUnit')
        local after, afterUnit = layeredPallet(size)
        local save = {xmlFile = xml, key = 'v'}
        FillUnit.onLoad(after, save)
        FillUnit.onPostLoad(after, save)
        Pallet.onPostLoad(after, save)
        close(afterUnit.fillLevel, unit.fillLevel, 'saved litres')
        assertEqual(after.palletDepotCapacity, size, 'saved capacity')
        assertEqual(after.palletDepotMaxMass, 400, 'saved mass cap')
        assertLayers(after, size, math.ceil(PALLET_MODELS[size].layers * 0.41))
        assertEqual(after.palletDepotGoodsFillType, 5, 'product look restored')
    end
end

function tests.realJoinStreamRestoresPartialLayersAndProductLook()
    STREAM = {}
    local server = layeredPallet(5000)
    PalletDepotPalletMass.applyCapacity(server, 5000)
    server:addFillUnitFillLevel(1, 1, 2100, 5, 0)
    FillUnit.onWriteStream(server, STREAM, {getIsServer = function() return false end})
    local client, unit = layeredPallet(5000, false)
    FillUnit.onReadStream(client, STREAM, {getIsServer = function() return true end})
    assertEqual(#STREAM, 0, 'stream fully consumed')
    assertEqual(unit.fillLevel, 2100, 'joining client litres')
    assertEqual(client.palletDepotCapacity, 5000, 'joining client capacity')
    assertLayers(client, 5000, 3)
    assertEqual(client.palletDepotGoodsFillType, 5, 'joining client product look')
end

function tests.nativeGeometryKeepsMaterialsAndChangesWithTheProduct()
    local butter = layeredPallet(1000)
    local cheese = layeredPallet(1000)
    butter:addFillUnitFillLevel(1, 1, 1000, 5, 0)
    cheese:addFillUnitFillLevel(1, 1, 1000, 6, 0)
    local a = butter.palletDepotGoodsNodes[1]
    local b = cheese.palletDepotGoodsNodes[1]
    local function firstBox(scene) return getChildAt(getChildAt(getChildAt(scene, 0), 1), 0) end
    assertEqual(NATIVE_NODES[firstBox(a)].material, 305, 'original product material')
    assertEqual(NATIVE_NODES[firstBox(b)].material, 306, 'other original material')
    butter:addFillUnitFillLevel(1, 1, -1000, 5, 0)
    butter:addFillUnitFillLevel(1, 1, 1000, 6, 0)
    assertEqual(NATIVE_NODES[a].deleted, true, 'old native scene removed')
    assertEqual(NATIVE_NODES[firstBox(butter.palletDepotGoodsNodes[1])].material, 306, 'changed product geometry')
end

function tests.requestedLayerCountsAreExplicit()
    assertEqual(PALLET_MODELS[1000].layers, 1, '1K one box tall')
    assertEqual(PALLET_MODELS[2500].layers, 3, '2.5K three boxes tall')
    assertEqual(PALLET_MODELS[5000].layers, 6, '5K existing height')
end

function tests.relativeProductionModelUsesOriginalModRoot()
    -- Real reported failure: vehicle.base.filename is a schema STRING, not a resolved FILENAME.
    NATIVE_RAW_FILENAME_BY_TYPE[5] = 'Paletten/models/Palette_Suppe_Rahmspinat.i3d'
    local v = layeredPallet(2500)
    local ok, err = pcall(function() v:addFillUnitFillLevel(1, 1, 2500, 5, 0) end)
    NATIVE_RAW_FILENAME_BY_TYPE[5] = nil
    assert(ok, tostring(err))
    assertEqual(v.palletDepotGoodsRequest.i3d,
        '/products/Paletten/models/Palette_Suppe_Rahmspinat.i3d', 'original mod root prefixes raw model filename')
    assertEqual(v.palletDepotGoodsFillType, 5, 'actual native cargo attached')
end

function tests.gameDataModelMacroIsResolvedBeforeNativeLoad()
    NATIVE_RAW_FILENAME_BY_TYPE[5] = '$data/objects/pallets/lettuceBoxPallet/lettuceBoxPallet.i3d'
    local v = layeredPallet(1000)
    local ok, err = pcall(function() v:addFillUnitFillLevel(1, 1, 1000, 5, 0) end)
    NATIVE_RAW_FILENAME_BY_TYPE[5] = nil
    assert(ok, tostring(err))
    assertEqual(v.palletDepotGoodsRequest.i3d,
        '/game/data/objects/pallets/lettuceBoxPallet/lettuceBoxPallet.i3d', 'game data macro resolved')
    assertEqual(v.palletDepotGoodsFillType, 5, 'game native cargo attached')
end

function tests.originalSourceLookupIncludesIBCStoreCategories()
    local oldManager, oldXML, oldCache = g_storeManager, XMLFile.loadIfExists, PalletDepotPallets.storePallets
    g_storeManager = {getItems = function() return {
        {xmlFilename = '/products/trailer.xml', categoryName = 'trailers'},
        {xmlFilename = '/products/ibc.xml', categoryName = 'ibc palletFertilizerHerbicide'}
    } end}
    XMLFile.loadIfExists = function(_, filename)
        assertEqual(filename, '/products/ibc.xml', 'only original package categories are read')
        return {getValue = function() return 'CARROTBAG' end, delete = function() end}
    end
    PalletDepotPallets.storePallets = nil
    local result = PalletDepotPallets.findStorePallet(5)
    g_storeManager, XMLFile.loadIfExists, PalletDepotPallets.storePallets = oldManager, oldXML, oldCache
    assertEqual(result, '/products/ibc.xml', 'IBC packages can supply native cargo')
end

function tests.nativeClonesKeepSkinGraphAndOnlyBottomRow()
    local v = layeredPallet(2500)
    v:addFillUnitFillLevel(1, 1, 2500, 5, 0)
    assertEqual(#v.palletDepotGoodsNodes, 3, 'one native row per depot layer')
    for _, scene in ipairs(v.palletDepotGoodsNodes) do
        local root = getChildAt(scene, 0)
        local content = getChildAt(root, 1)
        local first = getChildAt(content, 0)
        assertEqual(#NATIVE_NODES[first].skin, 12, 'all original skin joints retained')
        for i = 0, 11 do
            local box = getChildAt(content, i)
            assertEqual(NODE_VISIBLE[box], i < 4, 'only complete bottom row visible')
            assertEqual(NATIVE_NODES[first].skin[i + 1], box, 'cloned skin binding remapped')
        end
        local function check(n)
            if NATIVE_NODES[n].shape then
                assertEqual(NATIVE_NODES[n].body, 0, 'native node has no rigid body')
                assertEqual(NATIVE_NODES[n].compound, false, 'native node is not a compound child')
                assertEqual(NATIVE_NODES[n].filter, 0, 'native node excluded from physics/UAL')
            end
            for _, child in ipairs(NATIVE_NODES[n].children) do check(child) end
        end
        check(scene)
    end
end

function tests.pendingLoadCannotAttachAfterProductChangesOrDeletion()
    NATIVE_DEFER_LOAD = true
    local v = layeredPallet(1000)
    v:addFillUnitFillLevel(1, 1, 1000, 5, 0)
    local old = v.palletDepotGoodsRequest
    v:addFillUnitFillLevel(1, 1, -1000, 5, 0)
    v:addFillUnitFillLevel(1, 1, 1000, 6, 0)
    finishNativeLoad(old.id)
    assertEqual(v.palletDepotGoodsNodes, nil, 'stale load cannot attach')
    assertEqual(NATIVE_RELEASES[old.id], 1, 'old request released once')
    local pending = v.palletDepotGoodsRequest
    v.isDeleted = true
    PalletDepotGoodsLook.clear(v)
    finishNativeLoad(pending.id)
    assertEqual(v.palletDepotGoodsNodes, nil, 'deleted vehicle receives no visuals')
    assertEqual(NATIVE_RELEASES[pending.id], 1, 'deleted request released once')
    NATIVE_DEFER_LOAD = false
end

function tests.failedNativeLoadReleasesResourcesWithoutCartons()
    NATIVE_DEFER_LOAD = true
    local v = layeredPallet(1000)
    v:addFillUnitFillLevel(1, 1, 1000, 5, 0)
    local pending = v.palletDepotGoodsRequest
    finishNativeLoad(pending.id, true)
    assertEqual(NATIVE_RELEASES[pending.id], 1, 'failed request released')
    assertEqual(v.palletDepotGoodsNodes, nil, 'failed load invents no substitute carton')
    NATIVE_DEFER_LOAD = false
end

function tests.indivisibleNativeCargoFollowsPartialCollision()
    local v = layeredPallet(5000)
    v.spec_fillUnit.fillUnits[1].supportedFillTypes[7] = true
    v:addFillUnitFillLevel(1, 1, 5000, 7, 0)
    local whole = v.palletDepotGoodsWhole
    assert(whole, 'indivisible source keeps its complete native assembly')
    v:addFillUnitFillLevel(1, 1, -2900, 7, 0)
    close(NODE_SCALE[whole.node][2], whole.sy / 2, 'whole cargo follows three of six collision layers')
end

function tests.legacyProductPalletsKeepTheGamesOwnGeometry()
    local v = layeredPallet(5000)
    v.configFileName = '/otherMod/productPallet.xml'
    v:addFillUnitFillLevel(1, 1, 2100, 5, 0)
    assertEqual(shown(v), 2, 'unrelated pallet uses real game floor rule')
    assertEqual(v.palletDepotShownLayers, nil, 'no depot collision handling')
end

function tests.everyProductUsesOurSizedModelAndPSCQueueDoesToo()
    local pp = newProductionPoint(true)
    for _, size in ipairs({1000, 2500, 5000}) do
        for _, fillType in ipairs({5, 6, 7}) do
            local entry = PalletDepotPallets.getSizedPallet(pp, fillType, size)
            assertEqual(entry.filename, '/mods/FS25_PalletDepot/vehicles/depotPallet' .. size .. '.xml', 'own file')
            assertEqual(entry.capacity, size, 'capacity')
            assertEqual(entry.palletDepotCapacity, size, 'save/sync marker')
        end
        pp.palletSpawner.pendingItem = {[5] = {}}
        PalletDepotSpawnSizes.fixSpawn(pp, 5, size, 6)
        assertEqual(pp.palletSpawner.pendingItem[5].palletDepotCapacity, size, 'PSC queued size marker')
        assertEqual(pp.palletSpawner.pendingItem[5].filename,
            '/mods/FS25_PalletDepot/vehicles/depotPallet' .. size .. '.xml', 'PSC own model')
    end
end

return tests
