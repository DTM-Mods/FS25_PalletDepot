-- Pallet Depot: own pallets of 1,000 L and 5,000 L for every production (Settings page of the productions window).
--
-- Each production with pickup lanes spawns either the game's pallet of each product (0) or that same pallet (its
-- own model and textures) holding 1,000 L or 5,000 L: for every product it already puts on pallets, and in a depot
-- for every product it stores. Only a product without a pallet of its own gets our plain pallet
-- (vehicles/depotPallet*.xml), whose fill unit is opened to all fill types when it loads. A production spawns once a whole pallet is in stock, so 5,000 L pallets come out
-- full.
-- The server owns the choice: it saves it with the savegame (palletDepotPallets.xml, keyed by the building's unique
-- id), applies it and sends every change to all clients; joining clients get it with the production point's join data.

PalletDepotPallets = {}
PalletDepotPallets.FILENAME = "palletDepotPallets.xml"
PalletDepotPallets.SIZES = {0, 1000, 5000}
PalletDepotPallets.FILES = {[1000] = "vehicles/depotPallet1000.xml", [5000] = "vehicles/depotPallet5000.xml"}
PalletDepotPallets.data = {}        -- productionPoint -> pallet size in liters (0 = the game's pallets)

function PalletDepotPallets.get(productionPoint)
    return PalletDepotPallets.data[productionPoint] or 0
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

-- true for the xml of one of our pallets (spawned or loaded from a savegame)
local function isOwnPallet(filename)
    if filename == nil or string.find(filename, PalletDepot.modName, 1, true) == nil then
        return false
    end
    for _, file in pairs(PalletDepotPallets.FILES) do
        if filename:sub(-#file) == file then
            return true
        end
    end
    return false
end

-- --- our pallets take any product ----------------------------------------------------------------------

function PalletDepotPallets.onFillUnitLoad(vehicle, savegame)
    local spec = vehicle.spec_fillUnit
    if spec == nil or spec.fillUnits == nil or not isOwnPallet(vehicle.configFileName) then
        return
    end
    for _, fillUnit in ipairs(spec.fillUnits) do
        fillUnit.ignoreFillLimit = true     -- maxMass caps the weight only, the pallet still takes its full litres
        for fillTypeIndex in pairs(g_fillTypeManager.indexToFillType) do
            if fillTypeIndex ~= FillType.UNKNOWN then
                fillUnit.supportedFillTypes[fillTypeIndex] = true
            end
        end
    end
end

-- before onPostLoad, which puts a savegame pallet's product back in
FillUnit.onLoad = Utils.appendedFunction(FillUnit.onLoad, PalletDepotPallets.onFillUnitLoad)

-- --- applying (server and clients) ---------------------------------------------------------------------

-- our pallet of that size as a spawner entry; the spawner's own table is left as it was (loading a pallet would
-- otherwise make it the pallet of every product)
local function loadPallet(spawner, size)
    spawner.palletDepotPallets = spawner.palletDepotPallets or {}
    if spawner.palletDepotPallets[size] == nil then
        local filename = PalletDepot.modDirectory .. PalletDepotPallets.FILES[size]
        local before = copy(spawner.fillTypeIdToPallet)
        spawner.palletDepotPallets[size] = spawner:loadPalletFromFilename(filename) or false
        spawner.fillTypeIdToPallet = before
    end
    return spawner.palletDepotPallets[size] or nil
end
PalletDepotPallets.loadPallet = loadPallet

-- the pallets the production had before any of ours: fill type -> spawner entry (the game's or the mod's pallet)
function PalletDepotPallets.getGamePallets(productionPoint)
    local spawner = productionPoint.palletSpawner
    if spawner == nil or spawner.fillTypeIdToPallet == nil then
        return {}
    end
    if productionPoint.palletDepotSpawnerPallets == nil then
        productionPoint.palletDepotSpawnerPallets = copy(spawner.fillTypeIdToPallet)
    end
    return productionPoint.palletDepotSpawnerPallets
end

-- The product's own pallet file (its model and textures): the production's pallet for it, else the fill type's.
-- nil when the product has no pallet of its own (then our plain pallet is used).
function PalletDepotPallets.getProductPalletFile(productionPoint, fillType)
    local spawner = productionPoint.palletSpawner
    local game = productionPoint.palletDepotSpawnerPallets or (spawner ~= nil and spawner.fillTypeIdToPallet) or {}
    local entry = game[fillType]
    if entry ~= nil and entry.filename ~= nil and entry.palletDepotCapacity == nil and not isOwnPallet(entry.filename) then
        return entry.filename
    end
    local desc = g_fillTypeManager:getFillTypeByIndex(fillType)
    return desc ~= nil and desc.palletFilename or nil
end

-- A spawner pallet entry of `size` liters for a product: it points at the product's own pallet file (nothing is
-- copied) and carries palletDepotCapacity, which PalletDepotPalletMass sets on the pallet when it spawns.
function PalletDepotPallets.getSizedPallet(productionPoint, fillType, size)
    local spawner = productionPoint.palletSpawner
    local filename = PalletDepotPallets.getProductPalletFile(productionPoint, fillType)
    if filename == nil then
        return loadPallet(spawner, size)            -- no pallet of its own: our plain pallet
    end
    spawner.palletDepotSized = spawner.palletDepotSized or {}
    local key = size .. "|" .. filename
    if spawner.palletDepotSized[key] == nil then
        spawner.palletDepotSized[key] = {
            filename = filename,
            size = StoreItemUtil.getSizeValues(filename, "vehicle", 0, {}),
            capacity = size,
            palletDepotCapacity = size,
        }
    end
    return spawner.palletDepotSized[key]
end

-- The spawner's table says which pallet gets spawned, the production's own table when: once its capacity is in stock.
-- Both get the product's own pallet, sized to the chosen liters, for the same products.
function PalletDepotPallets.apply(productionPoint)
    local spawner = productionPoint.palletSpawner
    if spawner == nil or spawner.fillTypeIdToPallet == nil then
        return
    end
    -- the game's tables, kept before our pallet is loaded
    PalletDepotPallets.getGamePallets(productionPoint)
    if productionPoint.palletDepotOutputPallets == nil and productionPoint.outputFillTypeIdsToPallets ~= nil then
        productionPoint.palletDepotOutputPallets = copy(productionPoint.outputFillTypeIdsToPallets)
    end
    local gameOutputs = productionPoint.palletDepotOutputPallets or {}

    local size = PalletDepotPallets.get(productionPoint)
    local spawnerMap = copy(productionPoint.palletDepotSpawnerPallets)
    local outputMap = copy(gameOutputs)
    if size > 0 then
        local isDepot = PalletDepot.isDepot(productionPoint)
        for fillType in pairs(productionPoint.outputFillTypeIds or {}) do
            -- other productions keep products without a pallet off pallets
            if isDepot or gameOutputs[fillType] ~= nil then
                local pallet = PalletDepotPallets.getSizedPallet(productionPoint, fillType, size)
                if pallet ~= nil then
                    spawnerMap[fillType] = pallet
                    outputMap[fillType] = pallet
                end
            end
        end
    end
    spawner.fillTypeIdToPallet = spawnerMap
    if productionPoint.outputFillTypeIdsToPallets ~= nil then
        productionPoint.outputFillTypeIdsToPallets = outputMap
    end
end

local function store(productionPoint, size)
    if PalletDepotPallets.FILES[size] == nil then
        size = 0
    end
    PalletDepotPallets.data[productionPoint] = size > 0 and size or nil
    PalletDepotPallets.apply(productionPoint)
end
PalletDepotPallets.store = store

-- --- editing -------------------------------------------------------------------------------------------

function PalletDepotPallets.request(productionPoint, size)
    store(productionPoint, size)        -- shown at once, the server confirms
    if g_server ~= nil then
        g_server:broadcastEvent(PalletDepotPalletsEvent.new(productionPoint, size))
    else
        g_client:getServerConnection():sendEvent(PalletDepotPalletsEvent.new(productionPoint, size))
    end
end

PalletDepotPalletsEvent = {}
local PalletDepotPalletsEvent_mt = Class(PalletDepotPalletsEvent, Event)
InitEventClass(PalletDepotPalletsEvent, "PalletDepotPalletsEvent")

function PalletDepotPalletsEvent.emptyNew()
    return Event.new(PalletDepotPalletsEvent_mt)
end

function PalletDepotPalletsEvent.new(productionPoint, size)
    local self = PalletDepotPalletsEvent.emptyNew()
    self.productionPoint = productionPoint
    self.size = size
    return self
end

function PalletDepotPalletsEvent:readStream(streamId, connection)
    self.productionPoint = NetworkUtil.readNodeObject(streamId)
    self.size = streamReadUInt16(streamId)
    self:run(connection)
end

function PalletDepotPalletsEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.productionPoint)
    streamWriteUInt16(streamId, self.size)
end

function PalletDepotPalletsEvent:run(connection)
    local productionPoint = self.productionPoint
    if productionPoint == nil then
        return
    end
    if not connection:getIsServer() then
        -- a client's change arrives at the server: only players allowed to manage this farm's productions
        if not g_currentMission:getHasPlayerPermission("manageProductions", connection, productionPoint:getOwnerFarmId()) then
            return
        end
        store(productionPoint, self.size)
        g_server:broadcastEvent(PalletDepotPalletsEvent.new(productionPoint, self.size))
    else
        store(productionPoint, self.size)
    end
end

-- --- join synchronisation -------------------------------------------------------------------------------

function PalletDepotPallets.writeStream(productionPoint, streamId, connection)
    if connection:getIsServer() then
        return
    end
    streamWriteUInt16(streamId, PalletDepotPallets.get(productionPoint))
end

function PalletDepotPallets.readStream(productionPoint, streamId, connection)
    if not connection:getIsServer() then
        return
    end
    local size = streamReadUInt16(streamId)
    if size > 0 then
        store(productionPoint, size)
    end
end

ProductionPoint.writeStream = Utils.appendedFunction(ProductionPoint.writeStream, PalletDepotPallets.writeStream)
ProductionPoint.readStream = Utils.appendedFunction(ProductionPoint.readStream, PalletDepotPallets.readStream)
if ProductionPoint.delete ~= nil then
    ProductionPoint.delete = Utils.prependedFunction(ProductionPoint.delete, function(productionPoint)
        PalletDepotPallets.data[productionPoint] = nil
    end)
end

-- --- savegame (server) ---------------------------------------------------------------------------------

local function getFilename()
    local dir = g_currentMission ~= nil and g_currentMission.missionInfo ~= nil and g_currentMission.missionInfo.savegameDirectory or nil
    return dir ~= nil and (dir .. "/" .. PalletDepotPallets.FILENAME) or nil
end

local function getKey(productionPoint)
    local placeable = productionPoint.owningPlaceable
    return placeable ~= nil and placeable.getUniqueId ~= nil and placeable:getUniqueId() or nil
end

function PalletDepotPallets.save()
    local filename = getFilename()
    if filename == nil or g_server == nil then
        return
    end
    local xmlId = createXMLFile("palletDepotPallets", filename, "palletDepotPallets")
    local i = 0
    for productionPoint, size in pairs(PalletDepotPallets.data) do
        local placeableKey = getKey(productionPoint)
        if placeableKey ~= nil then
            local key = string.format("palletDepotPallets.production(%d)", i)
            setXMLString(xmlId, key .. "#placeable", placeableKey)
            setXMLInt(xmlId, key .. "#pallet", size)
            i = i + 1
        end
    end
    saveXMLFile(xmlId)
    delete(xmlId)
end

function PalletDepotPallets.load()
    local filename = getFilename()
    if filename == nil or g_server == nil or not fileExists(filename) then
        return
    end
    local byKey = {}
    for _, productionPoint in ipairs(g_currentMission.productionChainManager.productionPoints or {}) do
        local key = getKey(productionPoint)
        if key ~= nil then
            byKey[key] = productionPoint
        end
    end
    local xmlId = loadXMLFile("palletDepotPallets", filename)
    local i = 0
    while hasXMLProperty(xmlId, string.format("palletDepotPallets.production(%d)", i)) do
        local key = string.format("palletDepotPallets.production(%d)", i)
        local productionPoint = byKey[getXMLString(xmlId, key .. "#placeable") or ""]
        if productionPoint ~= nil then
            store(productionPoint, Utils.getNoNil(getXMLInt(xmlId, key .. "#pallet"), 0))
        end
        i = i + 1
    end
    delete(xmlId)
end

FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, PalletDepotPallets.save)
-- not at loadMission00Finished: the buildings of the savegame are still loading then
Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission, PalletDepotPallets.load)
