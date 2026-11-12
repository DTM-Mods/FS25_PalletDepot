-- scripts/PalletDepotStoring.lua: our Storing mode keeps products out of the automatic spawning.
local tests = {}

local function autoSpawned(pp)
    local out = {}
    for fillType in pairs(pp.outputFillTypeIdsToPallets) do
        out[fillType] = true
    end
    return out
end

function tests.hubsStoreByDefault()
    local pp = newProductionPoint(true)
    PalletDepotStoring.onUpdateProduction(pp)
    local auto = autoSpawned(pp)
    assertEqual(auto[5], nil, "carrot bags stay in stock")
    assertEqual(auto[7], nil, "flour stays in stock")
end

function tests.otherProductionsKeepTheGamesBehaviour()
    local pp = newProductionPoint(false)
    PalletDepotStoring.onUpdateProduction(pp)
    local auto = autoSpawned(pp)
    assertEqual(auto[5], true, "carrot bags still come out as pallets")
    assertEqual(auto[7], true, "flour still comes out as pallets")
end

function tests.spawningCanBeChosenPerProduct()
    local pp = newProductionPoint(true)
    PalletDepotStoring.store(pp, 5, false)
    local auto = autoSpawned(pp)
    assertEqual(auto[5], true, "carrot bags set to Spawning")
    assertEqual(auto[7], nil, "flour still stored")
    assertEqual(PalletDepotStoring.isStored(pp, 5), false, "choice")
end

function tests.storingCanBeChosenOutsideHubs()
    local pp = newProductionPoint(false)
    PalletDepotStoring.store(pp, 7, true)
    local auto = autoSpawned(pp)
    assertEqual(auto[7], nil, "flour stored")
    assertEqual(auto[5], true, "carrot bags unchanged")
end

function tests.otherStoreModeTakesOverTheDefault()
    ProductionPoint.OUTPUT_MODE.STORE = 3           -- Production Storage Control installed
    local pp = newProductionPoint(true)
    local stored = PalletDepotStoring.isStored(pp, 5)
    ProductionPoint.OUTPUT_MODE.STORE = nil
    assertEqual(stored, false, "no default of ours next to its own Storing")
end

function tests.spawnGoodsStillWorksForStoredProducts()
    local pp = newProductionPoint(true)
    PalletDepotStoring.onUpdateProduction(pp)
    PalletDepotSpawn.request(pp, 5, 0, 1, 2)
    pp.palletSpawner:run()
    assertEqual(#pp.palletSpawner.spawned, 2, "spawned by hand")
    assertEqual(pp.storage.fillLevels[5], 28987, "stock")
end

function tests.storingAndPalletSizeTogether()
    local pp = newProductionPoint(true)
    PalletDepotPallets.store(pp, 5000)
    PalletDepotStoring.store(pp, 5, false)
    assertEqual(pp.outputFillTypeIdsToPallets[5].palletDepotCapacity, 5000, "spawning product gets the 5,000 L pallet")
    assertEqual(pp.outputFillTypeIdsToPallets[7], nil, "stored product stays in stock")
    assertEqual(pp.palletSpawner.fillTypeIdToPallet[7].palletDepotCapacity, 5000, "but Spawn goods uses the size")
end

function tests.appliedOncePerProduction()
    local pp = newProductionPoint(true)
    PalletDepotStoring.onUpdateProduction(pp)
    pp.outputFillTypeIdsToPallets[5] = pp.gamePallet        -- something else changed it afterwards
    PalletDepotStoring.onUpdateProduction(pp)
    assertEqual(pp.outputFillTypeIdsToPallets[5], pp.gamePallet, "not rebuilt every update")
end

return tests
