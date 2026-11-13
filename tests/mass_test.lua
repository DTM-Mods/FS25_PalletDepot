-- game: dataS/scripts/vehicles/Vehicle.lua Vehicle:updateMass Vehicle:setMassDirty Vehicle:getTotalMass Vehicle:getComponentMass Vehicle:getAdditionalComponentMass
-- game: dataS/scripts/vehicles/specializations/FillUnit.lua FillUnit:getAdditionalComponentMass FillUnit:getFillUnitCapacity FillUnit:emptyAllFillUnits
-- game: dataS/scripts/placement/PalletSpawner.lua PalletSpawner:spawnPallet PalletSpawner:update PalletSpawner:onSpawnSearchFinished PalletSpawner:onFinishLoadingPallet
-- before: tests/game_env.lua
-- scripts: PalletDepotPalletMass.lua
--
-- The 400 kg cap, run through the GAME'S OWN code: PalletSpawner queues, places, loads and calls back; Vehicle:updateMass
-- and FillUnit:getAdditionalComponentMass work out the weight. The pallet is the Fed pack's buffalo butter pallet
-- with its real numbers (Palette_Molkerei_Bueffelbutter.xml: component mass 25 kg, no maxMass, 5,000 L; fillTypes.xml:
-- BUFFALOBUTTER massPerLiter 0.15 kg), which weighed 775 kg on the server.
local tests = {}

local BUTTER = 8
local FED = "/mods/FS25_Fed_Produktions_Pack/Paletten/Palette_Molkerei_Bueffelbutter.xml"
PALLET_XML[FED] = {componentMassKg = 25, maxMassKg = nil, capacity = 5000}
PALLET_XML["/mods/FS25_PalletDepot/vehicles/depotPallet1000.xml"] = {componentMassKg = 60, maxMassKg = 400, capacity = 1000}
PALLET_XML["/mods/FS25_PalletDepot/vehicles/depotPallet5000.xml"] = {componentMassKg = 60, maxMassKg = 400, capacity = 5000}
FILLTYPE_KG_PER_LITER[BUTTER] = 0.15
FILLTYPE_NAMES[BUTTER] = "BUFFALOBUTTER"

local LIMIT = 400.001       -- kg (float rounding)

local function reset()
    LOADED_VEHICLES, UPDATEABLES, STREAM = {}, {}, {}
end

local function production(isDepot, liters)
    local fedEntry = {filename = FED, capacity = 5000, size = {width = 1.2, length = 1, height = 1.5}}
    local pp = {
        palletSpawner = newGameSpawner({[BUTTER] = fedEntry}),
        storage = newStorage({[BUTTER] = liters or 20000}),
        outputFillTypeIds = {[BUTTER] = true},
        outputFillTypeIdsToPallets = {[BUTTER] = fedEntry},
        owningPlaceable = {customEnvironment = isDepot and "FS25_PalletDepot" or "FS25_Fed_Produktions_Pack"},
        fedEntry = fedEntry,
    }
    function pp:getName() return "PP" end
    function pp:getOwnerFarmId() return 1 end
    g_currentMission.productionChainManager = {productionPoints = {pp}}
    return pp
end

local function only(what)
    assertEqual(#LOADED_VEHICLES, 1, what .. ": pallets loaded")
    return LOADED_VEHICLES[1]
end

local function assertCapped(v, what)
    v:update()
    if v:massKg() > LIMIT then
        error(string.format("%s: weighs %.1f kg (limit 400)", what, v:massKg()), 2)
    end
    if v:physicsKg() > LIMIT then
        error(string.format("%s: physics mass %.1f kg (limit 400)", what, v:physicsKg()), 2)
    end
end

-- the screenshot's pallet: Spawn goods at a depot, 5,000 L of buffalo butter
function tests.depotSpawnGoods5000LButterIsAtMost400kg()
    reset()
    local pp = production(true)
    PalletDepotSpawn.request(pp, BUTTER, 5000, 1, 1)
    runUpdates()
    local v = only("5,000 L")
    assertEqual(v.configFileName, FED, "the product's own pallet")
    assertEqual(v:getFillUnitFillLevel(1), 5000, "litres on it")
    assertCapped(v, "5,000 L butter at the depot")
end

function tests.uncappedTheSamePalletWouldWeigh775kg()
    -- proves the test sees the problem: the same pallet loaded and filled with no cap
    reset()
    local v = loadPalletVehicle(FED, 1, nil, true)
    v:addFillUnitFillLevel(1, 1, 5000, BUTTER)
    v:update()
    assertEqual(math.floor(v:massKg() + 0.5), 775, "uncapped weight")
end

function tests.depot1000LIsNotRaised()
    reset()
    local pp = production(true)
    PalletDepotSpawn.request(pp, BUTTER, 1000, 1, 1)
    runUpdates()
    local v = only("1,000 L")
    v:update()
    assertEqual(math.floor(v:massKg() + 0.5), 175, "25 kg + 1,000 L x 0.15 kg, under the cap")
end

function tests.depotAutomaticSpawnIsCapped()
    -- the production spawning by itself through its spawner (the game's call), the game's own pallet
    reset()
    local pp = production(true)
    pp.palletSpawner:spawnPallet(1, BUTTER, function(_, vehicle)
        vehicle:addFillUnitFillLevel(1, 1, 5000, BUTTER)
    end, nil)
    runUpdates()
    assertCapped(only("automatic"), "automatic spawn at the depot")
end

function tests.capSurvivesSaveAndServerRestart()
    reset()
    local pp = production(true)
    PalletDepotSpawn.request(pp, BUTTER, 5000, 1, 1)
    runUpdates()
    local xml = newSaveXML()
    Vehicle.saveToXMLFile(only("before saving"), xml, "vehicles.vehicle(0)")
    -- restart: the game loads the pallet from the save, then puts the saved litres back
    local v = loadPalletVehicle(FED, 1, {xmlFile = xml, key = "vehicles.vehicle(0)"}, true)
    v:addFillUnitFillLevel(1, 1, 5000, BUTTER)
    assertEqual(v:getFillUnitFillLevel(1), 5000, "litres after loading")
    assertCapped(v, "after a restart")
end

function tests.palletSavedWithoutTheCapGetsItOnLoad()
    -- a pallet of our size saved by a build that did not cap it (only #palletDepotCapacity in the save)
    reset()
    local xml = newSaveXML()
    setXMLInt(xml.handle, "v#palletDepotCapacity", 5000)
    local v = loadPalletVehicle(FED, 1, {xmlFile = xml, key = "v"}, true)
    v:addFillUnitFillLevel(1, 1, 5000, BUTTER)
    assertCapped(v, "old uncapped save")
end

function tests.joiningPlayerGetsTheCap()
    reset()
    local pp = production(true)
    PalletDepotSpawn.request(pp, BUTTER, 5000, 1, 1)
    runUpdates()
    local server = only("server")
    -- the server writes the pallet for a joining player: the specializations' streams, then Vehicle's
    FillUnit.onWriteStream(server, STREAM, {getIsServer = function() return false end})
    Vehicle.writeStream(server, STREAM, nil)
    local client = loadPalletVehicle(FED, 1, nil, false)
    FillUnit.onReadStream(client, STREAM, {getIsServer = function() return true end})
    Vehicle.readStream(client, STREAM, nil)
    client:addFillUnitFillLevel(1, 1, 5000, BUTTER)
    assertEqual(client:getFillUnitCapacity(1), 5000, "client capacity")
    assertCapped(client, "on the joining player's side")
end

function tests.playersOnlineGetTheCapWithTheSpawnEvent()
    reset()
    local server = loadPalletVehicle(FED, 1, nil, true)
    local client = loadPalletVehicle(FED, 1, nil, false)
    PalletDepotPalletMassEvent.new(server, 400, 5000):writeStream(STREAM, nil)
    STREAM[1] = client          -- the node id resolves to the client's copy of the pallet
    local event = PalletDepotPalletMassEvent.emptyNew()
    event:readStream(STREAM, nil)
    client:addFillUnitFillLevel(1, 1, 5000, BUTTER)
    assertCapped(client, "online player's copy")
end

function tests.otherProductionsKeepTheGamesPallets()
    reset()
    local pp = production(false)
    assertEqual(#PalletDepotSpawn.getPallets(pp, BUTTER), 0, "no 1,000 / 5,000 L pallets outside the depots")
end

return tests
