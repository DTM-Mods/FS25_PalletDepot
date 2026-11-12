-- scripts/PalletDepotSpawn.lua: what the Spawn goods window offers and what the server spawns.
local tests = {}

function tests.offersPalletsPerProduct()
    local pp = newProductionPoint(true)
    local products = PalletDepotSpawn.getProducts(pp)
    assertEqual(#products, 3, "products in stock")
    assertEqual(products[1].fillType, 5, "sorted by name")
    assertEqual(#products[1].pallets, 3, "own pallet in normal size + 1,000 L + 5,000 L")
    assertEqual(#products[2].pallets, 2, "a hub product without a pallet of its own gets our two sizes")
end

function tests.otherProductionsOnlyOfferProductsWithPallets()
    local pp = newProductionPoint(false)
    local products = PalletDepotSpawn.getProducts(pp)
    assertEqual(#products, 2, "cheese has no pallet outside a hub")
end

function tests.maxPallets()
    assertEqual(PalletDepotSpawn.getMaxPallets(30987, 5000), 7, "with the rest")
    assertEqual(PalletDepotSpawn.getMaxPallets(30987, 5000, true), 6, "full only")
    assertEqual(PalletDepotSpawn.getMaxPallets(4000, 5000, true), 0, "not enough for a full one")
end

function tests.spawnsSizedOwnPalletsAndTakesTheRest()
    local pp = newProductionPoint(true)
    local spawner = pp.palletSpawner
    PalletDepotSpawn.request(pp, 5, 5000, 2, 7)
    assertEqual(spawner.fillTypeIdToPallet[5], pp.gamePallet, "spawner table restored")
    spawner:run()
    assertEqual(#spawner.spawned, 7, "pallets")
    assertEqual(spawner.spawned[1].file, "/data/carrotPallet.xml", "the product's own pallet")
    assertEqual(spawner.spawned[1].sized, 5000, "holding 5,000 L")
    assertEqual(spawner.spawned[1].farm, 2, "for the chosen farm")
    assertEqual(spawner.spawned[6].fill, 5000, "full")
    assertEqual(spawner.spawned[7].fill, 987, "the last one takes the rest")
    assertEqual(pp.storage.fillLevels[5], 0, "stock")
end

function tests.fullOnlyLeavesTheRest()
    local pp = newProductionPoint(true, {[5] = 12500})
    PalletDepotSpawn.request(pp, 5, 5000, 1, 5, true)
    assertEqual(#pp.palletSpawner.queue, 2, "clamped to full pallets")
    pp.palletSpawner:run()
    assertEqual(pp.storage.fillLevels[5], 2500, "rest stays")
end

function tests.fullOnlyRemovesAPalletTheStockCanNoLongerFill()
    local pp = newProductionPoint(true, {[5] = 5000})
    PalletDepotSpawn.request(pp, 5, 5000, 1, 1, true)
    pp.storage.fillLevels[5] = 4000
    pp.palletSpawner:run()
    assertEqual(pp.palletSpawner.spawned[1].deleted, true, "removed")
    assertEqual(pp.storage.fillLevels[5], 4000, "nothing taken")
end

function tests.noSpaceIsReported()
    local pp = newProductionPoint(true, {[5] = 1500})
    pp.palletSpawner.space = 1
    notifications = {}
    PalletDepotSpawn.request(pp, 5, 0, 1, 50)
    assertEqual(#pp.palletSpawner.queue, 2, "clamped to the stock")
    pp.palletSpawner:run()
    assertEqual(pp.storage.fillLevels[5], 500, "one pallet came out")
    assertEqual(notifications[2], "pdo_spawnNoSpace", "warning")
end

function tests.rejectsBadRequests()
    local pp = newProductionPoint(true)
    PalletDepotSpawn.request(pp, 5, 0, 7, 1)        -- unknown farm
    PalletDepotSpawn.request(pp, 5, 2500, 1, 1)     -- size not offered
    PalletDepotSpawn.request(pp, 9, 1000, 1, 1)     -- not an output
    assertEqual(#pp.palletSpawner.queue, 0, "nothing queued")
end

function tests.plainPalletForProductsWithoutOne()
    local pp = newProductionPoint(true)
    PalletDepotSpawn.request(pp, 6, 1000, 1, 1)
    pp.palletSpawner:run()
    assertEqual(pp.palletSpawner.spawned[1].file:find("depotPallet1000") ~= nil, true, "our plain 1,000 L pallet")
    assertEqual(pp.palletSpawner.spawned[1].fill, 400, "the cheese in stock")
end

return tests
