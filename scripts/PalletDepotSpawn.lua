-- Logistics Hub: spawn goods from a production's storage onto pallets at its pickup lanes (our own code; the window
-- is scripts/PalletDepotSpawnDialog.lua).
--
-- The player picks a product in stock, a pallet (the production's own pallet of that product, or our 1,000 L or
-- 5,000 L version of it), the farm that gets the pallets, how many, and whether a last part-filled pallet takes the
-- rest or only full pallets come out. The server checks the request, spawns the pallets one after another through the
-- building's own pallet spawner (PalletSpawner, base game) and moves the litres from the storage onto each pallet. Problems (no free space, pallet limit) and the
-- result are reported to the player who asked.

PalletDepotSpawn = {}
PalletDepotSpawn.MAX_PALLETS = 100      -- per request

PalletDepotSpawn.RESULT_DONE = 0
PalletDepotSpawn.RESULT_NO_SPACE = 1
PalletDepotSpawn.RESULT_LIMIT = 2
PalletDepotSpawn.RESULT_ERROR = 3

local function text(key)
    return g_i18n:getText(key)
end

-- --- what can be spawned (server and clients) ------------------------------------------------------------

-- every pallet that product can go on in this production: {size = 0 | 1000 | 5000, capacity = liters}; 0 is the
-- product's pallet in its normal size, 1000 / 5000 the same pallet holding that much (our plain pallet if it has none)
function PalletDepotSpawn.getPallets(productionPoint, fillTypeIndex)
    local pallets = {}
    if productionPoint.palletSpawner == nil then
        return pallets
    end
    local game = PalletDepotPallets.getGamePallets(productionPoint)[fillTypeIndex]
    if game ~= nil and (game.capacity or 0) > 0 then
        table.insert(pallets, {size = 0, capacity = game.capacity})
    end
    -- our pallets take any product; outside the hubs only products that come on pallets anyway, as on the
    -- Settings page
    if game ~= nil or PalletDepot.isDepot(productionPoint) then
        for _, size in ipairs(PalletDepotPallets.SIZES) do
            if size > 0 then
                table.insert(pallets, {size = size, capacity = size})
            end
        end
    end
    return pallets
end

-- the products in stock that can go on a pallet, sorted by name: {fillType, title, liters, pallets}
function PalletDepotSpawn.getProducts(productionPoint)
    local products = {}
    local storage = productionPoint.storage
    if storage == nil or storage.fillLevels == nil or productionPoint.palletSpawner == nil then
        return products
    end
    for fillTypeIndex in pairs(productionPoint.outputFillTypeIds or {}) do
        local liters = storage:getFillLevel(fillTypeIndex)
        if liters >= 1 then
            local pallets = PalletDepotSpawn.getPallets(productionPoint, fillTypeIndex)
            if #pallets > 0 then
                table.insert(products, {fillType = fillTypeIndex, liters = liters, pallets = pallets,
                    title = g_fillTypeManager:getFillTypeTitleByIndex(fillTypeIndex) or "?"})
            end
        end
    end
    table.sort(products, function(a, b)
        return a.title < b.title
    end)
    return products
end

-- fullOnly: only pallets that can be filled completely; else the last one takes the rest
function PalletDepotSpawn.getMaxPallets(liters, capacity, fullOnly)
    if capacity == nil or capacity <= 0 then
        return 0
    end
    local pallets = math.floor(liters) / capacity
    pallets = fullOnly and math.floor(pallets) or math.ceil(pallets)
    return math.min(pallets, PalletDepotSpawn.MAX_PALLETS)
end

-- --- request (client or server) ---------------------------------------------------------------------------

function PalletDepotSpawn.request(productionPoint, fillTypeIndex, size, farmId, count, fullOnly)
    if g_server ~= nil then
        PalletDepotSpawn.spawn(productionPoint, fillTypeIndex, size, farmId, count, fullOnly, nil)
    else
        g_client:getServerConnection():sendEvent(PalletDepotSpawnEvent.new(productionPoint, fillTypeIndex, size, farmId,
            count, fullOnly))
    end
end

-- --- spawning (server) ------------------------------------------------------------------------------------

-- connection: the player who asked (nil: the host / single player)
function PalletDepotSpawn.spawn(productionPoint, fillTypeIndex, size, farmId, count, fullOnly, connection)
    local spawner = productionPoint.palletSpawner
    local storage = productionPoint.storage
    if spawner == nil or storage == nil or productionPoint.outputFillTypeIds == nil
        or not productionPoint.outputFillTypeIds[fillTypeIndex] then
        return
    end
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil or farmId == FarmManager.SPECTATOR_FARM_ID then
        return
    end

    -- the chosen pallet must be one this product can go on here
    local capacity
    for _, option in ipairs(PalletDepotSpawn.getPallets(productionPoint, fillTypeIndex)) do
        if option.size == size then
            capacity = option.capacity
        end
    end
    local pallet = nil
    if capacity ~= nil then
        -- 1,000 / 5,000 L: the product's own pallet with that capacity (PalletDepotPalletMass sets it when it spawns)
        pallet = size > 0 and PalletDepotPallets.getSizedPallet(productionPoint, fillTypeIndex, size)
            or PalletDepotPallets.getGamePallets(productionPoint)[fillTypeIndex]
    end
    if pallet == nil then
        return
    end
    count = math.min(count, PalletDepotSpawn.getMaxPallets(storage:getFillLevel(fillTypeIndex), capacity, fullOnly))
    if count < 1 then
        return
    end

    local job = {productionPoint = productionPoint, fillType = fillTypeIndex, farmId = farmId, connection = connection,
                 fullOnly = fullOnly == true, pending = count, spawned = 0, liters = 0, problem = nil}
    -- the spawner takes the pallet from its table when the request is queued; for this request it is the chosen one
    local map = spawner.fillTypeIdToPallet
    local before = map[fillTypeIndex]
    map[fillTypeIndex] = pallet
    for _ = 1, count do
        spawner:spawnPallet(farmId, fillTypeIndex, PalletDepotSpawn.onPalletSpawned, job)
    end
    map[fillTypeIndex] = before
end

function PalletDepotSpawn.onPalletSpawned(job, vehicle, result, fillTypeIndex)
    job.pending = job.pending - 1
    local productionPoint = job.productionPoint
    local storage = productionPoint.storage
    if vehicle ~= nil then
        local liters = storage ~= nil and storage:getFillLevel(fillTypeIndex) or 0
        local fillUnitIndex = vehicle.spec_pallet ~= nil and vehicle.spec_pallet.fillUnitIndex or 1
        if result == PalletSpawner.RESULT_SUCCESS then
            vehicle:emptyAllFillUnits(true)
        end
        local delta = 0
        local capacity = vehicle:getFillUnitCapacity(fillUnitIndex)
        -- full pallets only: a pallet the stock cannot fill any more stays empty and is removed below
        if liters >= 1 and not (job.fullOnly and liters < capacity) then
            local amount = math.min(liters, capacity)
            delta = vehicle:addFillUnitFillLevel(job.farmId, fillUnitIndex, amount, fillTypeIndex, ToolType.UNDEFINED)
        end
        if delta > 0 then
            storage:setFillLevel(liters - delta, fillTypeIndex)
            job.spawned = job.spawned + 1
            job.liters = job.liters + delta
        elseif result == PalletSpawner.RESULT_SUCCESS then
            vehicle:delete()        -- not enough stock left for it meanwhile: no empty pallet left behind
        end
    elseif result == PalletSpawner.RESULT_NO_SPACE then
        job.problem = job.problem or PalletDepotSpawn.RESULT_NO_SPACE
    elseif result == PalletSpawner.PALLET_LIMITED_REACHED then
        job.problem = job.problem or PalletDepotSpawn.RESULT_LIMIT
    else
        job.problem = job.problem or PalletDepotSpawn.RESULT_ERROR
    end

    if job.pending <= 0 then
        local code = job.problem or PalletDepotSpawn.RESULT_DONE
        if job.connection ~= nil then
            job.connection:sendEvent(PalletDepotSpawnResultEvent.new(productionPoint, fillTypeIndex, code, job.spawned, job.liters))
        else
            PalletDepotSpawn.showResult(productionPoint, fillTypeIndex, code, job.spawned, job.liters)
        end
    end
end

-- --- result (the player who asked) ------------------------------------------------------------------------

function PalletDepotSpawn.showResult(productionPoint, fillTypeIndex, code, spawned, liters)
    local product = g_fillTypeManager:getFillTypeTitleByIndex(fillTypeIndex) or "?"
    local site = productionPoint.getName ~= nil and productionPoint:getName() or ""
    if spawned > 0 then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(text("pdo_spawnDone"), spawned, product, g_i18n:formatNumber(liters, 0), site))
    end
    if code == PalletDepotSpawn.RESULT_NO_SPACE then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(text("pdo_spawnNoSpace"), site, product))
    elseif code == PalletDepotSpawn.RESULT_LIMIT then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, text("pdo_spawnLimit"))
    elseif code == PalletDepotSpawn.RESULT_ERROR then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(text("pdo_spawnFailed"), product))
    end
end

-- --- events -----------------------------------------------------------------------------------------------

PalletDepotSpawnEvent = {}
local PalletDepotSpawnEvent_mt = Class(PalletDepotSpawnEvent, Event)
InitEventClass(PalletDepotSpawnEvent, "PalletDepotSpawnEvent")

function PalletDepotSpawnEvent.emptyNew()
    return Event.new(PalletDepotSpawnEvent_mt)
end

function PalletDepotSpawnEvent.new(productionPoint, fillTypeIndex, size, farmId, count, fullOnly)
    local self = PalletDepotSpawnEvent.emptyNew()
    self.fullOnly = fullOnly == true
    self.productionPoint = productionPoint
    self.fillTypeIndex = fillTypeIndex
    self.size = size
    self.farmId = farmId
    self.count = count
    return self
end

function PalletDepotSpawnEvent:readStream(streamId, connection)
    self.productionPoint = NetworkUtil.readNodeObject(streamId)
    self.fillTypeIndex = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
    self.size = streamReadUInt16(streamId)
    self.farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS)
    self.count = streamReadUInt8(streamId)
    self.fullOnly = streamReadBool(streamId)
    self:run(connection)
end

function PalletDepotSpawnEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.productionPoint)
    streamWriteUIntN(streamId, self.fillTypeIndex, FillTypeManager.SEND_NUM_BITS)
    streamWriteUInt16(streamId, self.size)
    streamWriteUIntN(streamId, self.farmId, FarmManager.FARM_ID_SEND_NUM_BITS)
    streamWriteUInt8(streamId, math.min(self.count, 255))
    streamWriteBool(streamId, self.fullOnly)
end

function PalletDepotSpawnEvent:run(connection)
    local productionPoint = self.productionPoint
    if productionPoint == nil or connection:getIsServer() then
        return
    end
    -- only players allowed to manage the owning farm's productions
    if not g_currentMission:getHasPlayerPermission("manageProductions", connection, productionPoint:getOwnerFarmId()) then
        return
    end
    PalletDepotSpawn.spawn(productionPoint, self.fillTypeIndex, self.size, self.farmId, self.count, self.fullOnly,
        connection)
end

PalletDepotSpawnResultEvent = {}
local PalletDepotSpawnResultEvent_mt = Class(PalletDepotSpawnResultEvent, Event)
InitEventClass(PalletDepotSpawnResultEvent, "PalletDepotSpawnResultEvent")

function PalletDepotSpawnResultEvent.emptyNew()
    return Event.new(PalletDepotSpawnResultEvent_mt)
end

function PalletDepotSpawnResultEvent.new(productionPoint, fillTypeIndex, code, spawned, liters)
    local self = PalletDepotSpawnResultEvent.emptyNew()
    self.productionPoint = productionPoint
    self.fillTypeIndex = fillTypeIndex
    self.code = code
    self.spawned = spawned
    self.liters = liters
    return self
end

function PalletDepotSpawnResultEvent:readStream(streamId, connection)
    self.productionPoint = NetworkUtil.readNodeObject(streamId)
    self.fillTypeIndex = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
    self.code = streamReadUInt8(streamId)
    self.spawned = streamReadUInt8(streamId)
    self.liters = streamReadInt32(streamId)
    self:run(connection)
end

function PalletDepotSpawnResultEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.productionPoint)
    streamWriteUIntN(streamId, self.fillTypeIndex, FillTypeManager.SEND_NUM_BITS)
    streamWriteUInt8(streamId, self.code)
    streamWriteUInt8(streamId, math.min(self.spawned, 255))
    streamWriteInt32(streamId, math.floor(self.liters + 0.5))
end

function PalletDepotSpawnResultEvent:run(connection)
    if self.productionPoint ~= nil and connection:getIsServer() then
        PalletDepotSpawn.showResult(self.productionPoint, self.fillTypeIndex, self.code, self.spawned, self.liters)
    end
end
