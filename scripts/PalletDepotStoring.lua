-- Logistics Hub: our own "Storing" output mode, so a hub keeps its stock without any other mod.
--
-- The game's own mode for an output (KEEP) spawns a pallet as soon as a whole pallet is in stock, for every output
-- listed in productionPoint.outputFillTypeIdsToPallets. Storing = KEEP with that product left out of the list: the
-- stock stays in the building until it is spawned with Spawn goods, delivered or sold. No new output mode is added,
-- so the game's menus and other mods keep working.
--
-- Hubs store by default; other productions keep the game's behaviour unless set. With Production Storage Control
-- installed its own Storing mode (which it sets for everything by default) stays in charge, so the default is off.
-- The server owns the choice: saved with the savegame (palletDepotStoring.xml, by the building's unique id and the
-- product's name), every change sent to all clients, joining clients get it with the production point's join data.

PalletDepotStoring = {}
PalletDepotStoring.FILENAME = "palletDepotStoring.xml"
PalletDepotStoring.data = {}        -- productionPoint -> {[fillTypeIndex] = true / false}: the choices made

local function hasOtherStoreMode()
    return ProductionPoint.OUTPUT_MODE ~= nil and ProductionPoint.OUTPUT_MODE.STORE ~= nil
end

function PalletDepotStoring.isDefault(productionPoint)
    return PalletDepot.isDepot(productionPoint) and not hasOtherStoreMode()
end

-- true when the product stays in stock in the game's KEEP mode
function PalletDepotStoring.isStored(productionPoint, fillTypeIndex)
    local choices = PalletDepotStoring.data[productionPoint]
    local choice = nil
    if choices ~= nil then
        choice = choices[fillTypeIndex]     -- false is a choice too: not "x and y or nil"
    end
    if choice == nil then
        return PalletDepotStoring.isDefault(productionPoint)
    end
    return choice
end

local function store(productionPoint, fillTypeIndex, stored)
    local choices = PalletDepotStoring.data[productionPoint] or {}
    PalletDepotStoring.data[productionPoint] = choices
    choices[fillTypeIndex] = stored
    PalletDepotPallets.apply(productionPoint)       -- rebuilds the spawn list without the stored products
end
PalletDepotStoring.store = store

-- The server applies the default once a production runs (also for buildings placed during the game).
function PalletDepotStoring.onUpdateProduction(productionPoint)
    if not productionPoint.palletDepotStoringApplied and productionPoint.palletSpawner ~= nil then
        productionPoint.palletDepotStoringApplied = true
        PalletDepotPallets.apply(productionPoint)
    end
end

if ProductionPoint.updateProduction ~= nil then
    ProductionPoint.updateProduction = Utils.prependedFunction(ProductionPoint.updateProduction, PalletDepotStoring.onUpdateProduction)
end

-- --- editing -------------------------------------------------------------------------------------------

function PalletDepotStoring.request(productionPoint, fillTypeIndex, stored)
    store(productionPoint, fillTypeIndex, stored)       -- shown at once, the server confirms
    local event = PalletDepotStoringEvent.new(productionPoint, fillTypeIndex, stored)
    if g_server ~= nil then
        g_server:broadcastEvent(event)
    else
        g_client:getServerConnection():sendEvent(event)
    end
end

PalletDepotStoringEvent = {}
local PalletDepotStoringEvent_mt = Class(PalletDepotStoringEvent, Event)
InitEventClass(PalletDepotStoringEvent, "PalletDepotStoringEvent")

function PalletDepotStoringEvent.emptyNew()
    return Event.new(PalletDepotStoringEvent_mt)
end

function PalletDepotStoringEvent.new(productionPoint, fillTypeIndex, stored)
    local self = PalletDepotStoringEvent.emptyNew()
    self.productionPoint = productionPoint
    self.fillTypeIndex = fillTypeIndex
    self.stored = stored == true
    return self
end

function PalletDepotStoringEvent:readStream(streamId, connection)
    self.productionPoint = NetworkUtil.readNodeObject(streamId)
    self.fillTypeIndex = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
    self.stored = streamReadBool(streamId)
    self:run(connection)
end

function PalletDepotStoringEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.productionPoint)
    streamWriteUIntN(streamId, self.fillTypeIndex, FillTypeManager.SEND_NUM_BITS)
    streamWriteBool(streamId, self.stored)
end

function PalletDepotStoringEvent:run(connection)
    local productionPoint = self.productionPoint
    if productionPoint == nil or productionPoint.outputFillTypeIds == nil
        or not productionPoint.outputFillTypeIds[self.fillTypeIndex] then
        return
    end
    if not connection:getIsServer() then
        -- a client's change arrives at the server: only players allowed to manage this farm's productions
        if not g_currentMission:getHasPlayerPermission("manageProductions", connection, productionPoint:getOwnerFarmId()) then
            return
        end
        store(productionPoint, self.fillTypeIndex, self.stored)
        g_server:broadcastEvent(PalletDepotStoringEvent.new(productionPoint, self.fillTypeIndex, self.stored), nil, connection)
    else
        store(productionPoint, self.fillTypeIndex, self.stored)
    end
end

-- --- join synchronisation -------------------------------------------------------------------------------

function PalletDepotStoring.writeStream(productionPoint, streamId, connection)
    if connection:getIsServer() then
        return
    end
    local choices = PalletDepotStoring.data[productionPoint] or {}
    local count = 0
    for _ in pairs(choices) do
        count = count + 1
    end
    streamWriteUInt16(streamId, count)
    for fillTypeIndex, stored in pairs(choices) do
        streamWriteUIntN(streamId, fillTypeIndex, FillTypeManager.SEND_NUM_BITS)
        streamWriteBool(streamId, stored)
    end
end

function PalletDepotStoring.readStream(productionPoint, streamId, connection)
    if not connection:getIsServer() then
        return
    end
    local count = streamReadUInt16(streamId)
    for _ = 1, count do
        local fillTypeIndex = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
        local choices = PalletDepotStoring.data[productionPoint] or {}
        PalletDepotStoring.data[productionPoint] = choices
        choices[fillTypeIndex] = streamReadBool(streamId)
    end
end

ProductionPoint.writeStream = Utils.appendedFunction(ProductionPoint.writeStream, PalletDepotStoring.writeStream)
ProductionPoint.readStream = Utils.appendedFunction(ProductionPoint.readStream, PalletDepotStoring.readStream)
if ProductionPoint.delete ~= nil then
    ProductionPoint.delete = Utils.prependedFunction(ProductionPoint.delete, function(productionPoint)
        PalletDepotStoring.data[productionPoint] = nil
    end)
end

-- --- savegame (server) ---------------------------------------------------------------------------------

local function getFilename()
    local dir = g_currentMission ~= nil and g_currentMission.missionInfo ~= nil and g_currentMission.missionInfo.savegameDirectory or nil
    return dir ~= nil and (dir .. "/" .. PalletDepotStoring.FILENAME) or nil
end

local function getKey(productionPoint)
    local placeable = productionPoint.owningPlaceable
    return placeable ~= nil and placeable.getUniqueId ~= nil and placeable:getUniqueId() or nil
end

function PalletDepotStoring.save()
    local filename = getFilename()
    if filename == nil or g_server == nil then
        return
    end
    local xmlId = createXMLFile("palletDepotStoring", filename, "palletDepotStoring")
    local i = 0
    for productionPoint, choices in pairs(PalletDepotStoring.data) do
        local placeableKey = getKey(productionPoint)
        if placeableKey ~= nil then
            local key = string.format("palletDepotStoring.production(%d)", i)
            setXMLString(xmlId, key .. "#placeable", placeableKey)
            local j = 0
            for fillTypeIndex, stored in pairs(choices) do
                local name = g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex)
                if name ~= nil then
                    local productKey = string.format("%s.product(%d)", key, j)
                    setXMLString(xmlId, productKey .. "#fillType", name)
                    setXMLBool(xmlId, productKey .. "#store", stored)
                    j = j + 1
                end
            end
            i = i + 1
        end
    end
    saveXMLFile(xmlId)
    delete(xmlId)
end

function PalletDepotStoring.load()
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
    local xmlId = loadXMLFile("palletDepotStoring", filename)
    local i = 0
    while hasXMLProperty(xmlId, string.format("palletDepotStoring.production(%d)", i)) do
        local key = string.format("palletDepotStoring.production(%d)", i)
        local productionPoint = byKey[getXMLString(xmlId, key .. "#placeable") or ""]
        local j = 0
        while productionPoint ~= nil and hasXMLProperty(xmlId, string.format("%s.product(%d)", key, j)) do
            local productKey = string.format("%s.product(%d)", key, j)
            local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(getXMLString(xmlId, productKey .. "#fillType") or "")
            if fillTypeIndex ~= nil and productionPoint.outputFillTypeIds ~= nil and productionPoint.outputFillTypeIds[fillTypeIndex] then
                store(productionPoint, fillTypeIndex, Utils.getNoNil(getXMLBool(xmlId, productKey .. "#store"), true))
            end
            j = j + 1
        end
        i = i + 1
    end
    delete(xmlId)
end

FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, PalletDepotStoring.save)
-- not at loadMission00Finished: the buildings of the savegame are still loading then
Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission, PalletDepotStoring.load)
