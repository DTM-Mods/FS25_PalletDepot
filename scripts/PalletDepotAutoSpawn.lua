-- Logistics Hub: Auto spawn. Ticked products of a hub keep coming out as full 5,000 L pallets at its pickup lanes.
--
-- The Logistics page (scripts/PalletDepotOverview.lua) has a tick box per product of every Logistics Hub (key D, the
-- AUTO column) and the farm's AUTO SPAWN on/off button in its page strip (the farm setting "autoSpawn",
-- PalletDepotAutoManager). A tick does not change the product's output (Storing, Distributing, Selling): while the
-- farm's switch is on, the server spawns a group of pallets (as many full ones as the stock
-- has, at most GROUP; the lanes take what fits) of a ticked product with at least 5,000 L in stock, through
-- the same code as Spawn goods (PalletDepotSpawn). When the lanes are full it waits and tries again; a truck that takes
-- the pallets away frees the lanes for the next ones. A hub works down its ticked products in the order of the
-- Logistics page: one product until it is done (less than a full pallet left after spawning from it), then its tick
-- is taken off and the next ticked product follows. A ticked product that has not had a full pallet yet is skipped
-- and keeps its tick until it has.
-- The ticks are saved with the savegame (palletDepotAutoSpawn.xml, by the building's unique id and the product's name),
-- sent to all clients on every change and to joining clients with the production point's join data.

PalletDepotAutoSpawn = {}
PalletDepotAutoSpawn.FILENAME = "palletDepotAutoSpawn.xml"
PalletDepotAutoSpawn.SIZE = 5000                -- liters per pallet: our 5,000 L pallet
PalletDepotAutoSpawn.GROUP = 20                 -- pallets asked for at once; the lanes take what fits
PalletDepotAutoSpawn.CHECK_INTERVAL = 1000      -- ms between checks
PalletDepotAutoSpawn.RETRY_DELAY = 8000         -- ms to wait after the lanes were full

PalletDepotAutoSpawn.data = {}      -- productionPoint -> {[fillTypeIndex] = true}: the ticked products
PalletDepotAutoSpawn.busy = {}      -- productionPoint -> true while a pallet is being spawned (server)
PalletDepotAutoSpawn.waitUntil = {} -- productionPoint -> mission time before which it does not try again (server)
PalletDepotAutoSpawn.started = {}   -- productionPoint -> {[fillTypeIndex] = true}: pallets spawned from it (server)
PalletDepotAutoSpawn.timer = 0

-- only Logistics Hubs: our 5,000 L pallet exists there only
function PalletDepotAutoSpawn.canTick(productionPoint)
    return productionPoint ~= nil and productionPoint.palletSpawner ~= nil and productionPoint.storage ~= nil
        and PalletDepot.isDepot(productionPoint)
end

function PalletDepotAutoSpawn.isTicked(productionPoint, fillTypeIndex)
    local ticks = PalletDepotAutoSpawn.data[productionPoint]
    return ticks ~= nil and ticks[fillTypeIndex] == true
end

function PalletDepotAutoSpawn.isOn(farmId)
    return PalletDepotAutoManager.getSettings(farmId).autoSpawn == true
end

local function store(productionPoint, fillTypeIndex, ticked)
    local ticks = PalletDepotAutoSpawn.data[productionPoint] or {}
    PalletDepotAutoSpawn.data[productionPoint] = ticks
    ticks[fillTypeIndex] = ticked == true or nil
end

-- --- editing -------------------------------------------------------------------------------------------

function PalletDepotAutoSpawn.request(productionPoint, fillTypeIndex, ticked)
    store(productionPoint, fillTypeIndex, ticked)       -- shown at once, the server confirms
    local event = PalletDepotAutoSpawnEvent.new(productionPoint, fillTypeIndex, ticked)
    if g_server ~= nil then
        g_server:broadcastEvent(event)
    else
        g_client:getServerConnection():sendEvent(event)
    end
end

-- the farm's on/off switch is a farm setting: the same rights, sync and savegame as the other farm settings
function PalletDepotAutoSpawn.requestOn(farmId, on)
    local settings = {}
    for k, v in pairs(PalletDepotAutoManager.getSettings(farmId)) do
        settings[k] = v
    end
    settings.autoSpawn = on == true
    PalletDepotAutoManager.requestSettings(farmId, settings)
end

PalletDepotAutoSpawnEvent = {}
local PalletDepotAutoSpawnEvent_mt = Class(PalletDepotAutoSpawnEvent, Event)
InitEventClass(PalletDepotAutoSpawnEvent, "PalletDepotAutoSpawnEvent")

function PalletDepotAutoSpawnEvent.emptyNew()
    return Event.new(PalletDepotAutoSpawnEvent_mt)
end

function PalletDepotAutoSpawnEvent.new(productionPoint, fillTypeIndex, ticked)
    local self = PalletDepotAutoSpawnEvent.emptyNew()
    self.productionPoint = productionPoint
    self.fillTypeIndex = fillTypeIndex
    self.ticked = ticked == true
    return self
end

function PalletDepotAutoSpawnEvent:readStream(streamId, connection)
    self.productionPoint = NetworkUtil.readNodeObject(streamId)
    self.fillTypeIndex = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
    self.ticked = streamReadBool(streamId)
    self:run(connection)
end

function PalletDepotAutoSpawnEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.productionPoint)
    streamWriteUIntN(streamId, self.fillTypeIndex, FillTypeManager.SEND_NUM_BITS)
    streamWriteBool(streamId, self.ticked)
end

function PalletDepotAutoSpawnEvent:run(connection)
    local productionPoint = self.productionPoint
    if not PalletDepotAutoSpawn.canTick(productionPoint) or productionPoint.outputFillTypeIds == nil
        or not productionPoint.outputFillTypeIds[self.fillTypeIndex] then
        return
    end
    if not connection:getIsServer() then
        -- a client's change arrives at the server: only players allowed to manage this farm's productions
        if not g_currentMission:getHasPlayerPermission("manageProductions", connection, productionPoint:getOwnerFarmId()) then
            return
        end
        store(productionPoint, self.fillTypeIndex, self.ticked)
        g_server:broadcastEvent(PalletDepotAutoSpawnEvent.new(productionPoint, self.fillTypeIndex, self.ticked), nil, connection)
    else
        store(productionPoint, self.fillTypeIndex, self.ticked)
    end
end

-- --- spawning (server) ---------------------------------------------------------------------------------

local function productFillType(production)
    if production.primaryProductFillType ~= nil then
        return production.primaryProductFillType
    end
    local output = production.outputs ~= nil and production.outputs[1] or nil
    return output ~= nil and output.type or nil
end

-- the first ticked product, in the order of the Logistics page, with a full pallet in stock; products that are done
-- (spawned from and now below a full pallet) lose their tick on the way
local function nextProduct(productionPoint)
    local storage = productionPoint.storage
    local started = PalletDepotAutoSpawn.started[productionPoint] or {}
    PalletDepotAutoSpawn.started[productionPoint] = started
    local seen = {}
    for _, production in ipairs(productionPoint.productions or {}) do
        local fillTypeIndex = productFillType(production)
        if fillTypeIndex ~= nil and not seen[fillTypeIndex] then
            seen[fillTypeIndex] = true
            if PalletDepotAutoSpawn.isTicked(productionPoint, fillTypeIndex) then
                if (storage:getFillLevel(fillTypeIndex) or 0) >= PalletDepotAutoSpawn.SIZE then
                    return fillTypeIndex
                elseif started[fillTypeIndex] then
                    started[fillTypeIndex] = nil
                    PalletDepotAutoSpawn.request(productionPoint, fillTypeIndex, false)     -- done: tick off
                end
            end
        end
    end
    return nil
end

function PalletDepotAutoSpawn.check()
    local now = g_currentMission.time or 0
    for productionPoint in pairs(PalletDepotAutoSpawn.data) do
        local farmId = productionPoint:getOwnerFarmId()
        if PalletDepotAutoSpawn.canTick(productionPoint) and farmId ~= nil and farmId ~= FarmManager.SPECTATOR_FARM_ID
            and PalletDepotAutoSpawn.isOn(farmId) and not PalletDepotAutoSpawn.busy[productionPoint]
            and now >= (PalletDepotAutoSpawn.waitUntil[productionPoint] or 0) then
            local fillTypeIndex = nextProduct(productionPoint)
            if fillTypeIndex ~= nil then
                PalletDepotAutoSpawn.busy[productionPoint] = true
                local queued = PalletDepotSpawn.spawn(productionPoint, fillTypeIndex, PalletDepotAutoSpawn.SIZE, farmId,
                    PalletDepotAutoSpawn.GROUP,
                    true, nil, function(code, spawned)
                        PalletDepotAutoSpawn.busy[productionPoint] = nil
                        if spawned > 0 then
                            local started = PalletDepotAutoSpawn.started[productionPoint] or {}
                            PalletDepotAutoSpawn.started[productionPoint] = started
                            started[fillTypeIndex] = true
                        else
                            -- lanes full or pallet limit: wait for a truck to take the pallets away
                            PalletDepotAutoSpawn.waitUntil[productionPoint] = (g_currentMission.time or 0) + PalletDepotAutoSpawn.RETRY_DELAY
                        end
                    end)
                if not queued then
                    PalletDepotAutoSpawn.busy[productionPoint] = nil
                    PalletDepotAutoSpawn.waitUntil[productionPoint] = now + PalletDepotAutoSpawn.RETRY_DELAY
                end
            end
        end
    end
end

function PalletDepotAutoSpawn:update(dt)
    if g_server == nil or g_currentMission == nil then
        return
    end
    PalletDepotAutoSpawn.timer = PalletDepotAutoSpawn.timer + dt
    if PalletDepotAutoSpawn.timer >= PalletDepotAutoSpawn.CHECK_INTERVAL then
        PalletDepotAutoSpawn.timer = 0
        PalletDepotAutoSpawn.check()
    end
end

addModEventListener(PalletDepotAutoSpawn)

-- --- join synchronisation -------------------------------------------------------------------------------

function PalletDepotAutoSpawn.writeStream(productionPoint, streamId, connection)
    if connection:getIsServer() then
        return
    end
    local ticks = PalletDepotAutoSpawn.data[productionPoint] or {}
    local count = 0
    for _ in pairs(ticks) do
        count = count + 1
    end
    streamWriteUInt16(streamId, count)
    for fillTypeIndex in pairs(ticks) do
        streamWriteUIntN(streamId, fillTypeIndex, FillTypeManager.SEND_NUM_BITS)
    end
end

function PalletDepotAutoSpawn.readStream(productionPoint, streamId, connection)
    if not connection:getIsServer() then
        return
    end
    for _ = 1, streamReadUInt16(streamId) do
        store(productionPoint, streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS), true)
    end
end

ProductionPoint.writeStream = Utils.appendedFunction(ProductionPoint.writeStream, PalletDepotAutoSpawn.writeStream)
ProductionPoint.readStream = Utils.appendedFunction(ProductionPoint.readStream, PalletDepotAutoSpawn.readStream)
if ProductionPoint.delete ~= nil then
    ProductionPoint.delete = Utils.prependedFunction(ProductionPoint.delete, function(productionPoint)
        PalletDepotAutoSpawn.data[productionPoint] = nil
        PalletDepotAutoSpawn.busy[productionPoint] = nil
        PalletDepotAutoSpawn.waitUntil[productionPoint] = nil
        PalletDepotAutoSpawn.started[productionPoint] = nil
    end)
end

-- --- savegame (server) ---------------------------------------------------------------------------------

local function getFilename()
    local dir = g_currentMission ~= nil and g_currentMission.missionInfo ~= nil and g_currentMission.missionInfo.savegameDirectory or nil
    return dir ~= nil and (dir .. "/" .. PalletDepotAutoSpawn.FILENAME) or nil
end

local function getKey(productionPoint)
    local placeable = productionPoint.owningPlaceable
    return placeable ~= nil and placeable.getUniqueId ~= nil and placeable:getUniqueId() or nil
end

function PalletDepotAutoSpawn.save()
    local filename = getFilename()
    if filename == nil or g_server == nil then
        return
    end
    local xmlId = createXMLFile("palletDepotAutoSpawn", filename, "palletDepotAutoSpawn")
    local i = 0
    for productionPoint, ticks in pairs(PalletDepotAutoSpawn.data) do
        local placeableKey = getKey(productionPoint)
        if placeableKey ~= nil and next(ticks) ~= nil then
            local key = string.format("palletDepotAutoSpawn.production(%d)", i)
            setXMLString(xmlId, key .. "#placeable", placeableKey)
            local j = 0
            for fillTypeIndex in pairs(ticks) do
                local name = g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex)
                if name ~= nil then
                    setXMLString(xmlId, string.format("%s.product(%d)#fillType", key, j), name)
                    j = j + 1
                end
            end
            i = i + 1
        end
    end
    saveXMLFile(xmlId)
    delete(xmlId)
end

function PalletDepotAutoSpawn.load()
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
    local xmlId = loadXMLFile("palletDepotAutoSpawn", filename)
    local i = 0
    while hasXMLProperty(xmlId, string.format("palletDepotAutoSpawn.production(%d)", i)) do
        local key = string.format("palletDepotAutoSpawn.production(%d)", i)
        local productionPoint = byKey[getXMLString(xmlId, key .. "#placeable") or ""]
        local j = 0
        while productionPoint ~= nil and hasXMLProperty(xmlId, string.format("%s.product(%d)", key, j)) do
            local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(
                getXMLString(xmlId, string.format("%s.product(%d)#fillType", key, j)) or "")
            if fillTypeIndex ~= nil and PalletDepotAutoSpawn.canTick(productionPoint)
                and productionPoint.outputFillTypeIds ~= nil and productionPoint.outputFillTypeIds[fillTypeIndex] then
                store(productionPoint, fillTypeIndex, true)
            end
            j = j + 1
        end
        i = i + 1
    end
    delete(xmlId)
end

FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, PalletDepotAutoSpawn.save)
-- not at loadMission00Finished: the buildings of the savegame are still loading then
Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission, PalletDepotAutoSpawn.load)
