-- Depot pallets keep their litres and a 400 kg total mass limit.
-- Newly spawned sized pallets use our own models. Legacy product-model pallets retain their
-- original visual-capacity behaviour; our layered models use PalletDepotStack instead.
-- Capacity and weight markers are saved and sent before the game's fill-level join data.

PalletDepotPalletMass = {}
PalletDepotPalletMass.MAX_MASS = 400            -- kg, like the NF Marsch goat milk pallet
PalletDepotPalletMass.ATTR = "#palletDepotMaxMass"
PalletDepotPalletMass.ATTR_CAPACITY = "#palletDepotCapacity"

-- The cap is on weight only, never on litres: with the game's trailer fill limit on, FillUnit stops filling once
-- maxComponentMass is reached (FillUnit.lua getFillUnitFreeCapacity / addFillUnitFillLevel) unless the fill unit has
-- ignoreFillLimit. Vehicle:updateMass still clamps the weight.
function PalletDepotPalletMass.ignoreFillLimit(vehicle)
    local spec = vehicle.spec_fillUnit
    if spec ~= nil and spec.fillUnits ~= nil then
        for _, fillUnit in ipairs(spec.fillUnits) do
            fillUnit.ignoreFillLimit = true
        end
    end
end

local function apply(vehicle, kg)
    if vehicle == nil or kg == nil or kg <= 0 then
        return
    end
    vehicle.palletDepotMaxMass = kg
    vehicle.maxComponentMass = kg / 1000         -- the game works in tonnes
    PalletDepotPalletMass.ignoreFillLimit(vehicle)
end
PalletDepotPalletMass.apply = apply

-- the pallet's fill unit takes `liters`; nothing else of the pallet changes
local function applyCapacity(vehicle, liters)
    if vehicle == nil or liters == nil or liters <= 0 then
        return
    end
    local spec = vehicle.spec_fillUnit
    local index = vehicle.spec_pallet ~= nil and vehicle.spec_pallet.fillUnitIndex or 1
    local fillUnit = spec ~= nil and spec.fillUnits ~= nil and spec.fillUnits[index] or nil
    if fillUnit == nil then
        return
    end
    if vehicle.palletDepotVisualCapacity == nil then
        vehicle.palletDepotVisualCapacity = fillUnit.capacity    -- the pallet's own size, from its xml
    end
    vehicle.palletDepotCapacity = liters
    fillUnit.capacity = liters
    fillUnit.capacityToDisplay = nil
end
PalletDepotPalletMass.applyCapacity = applyCapacity

-- The goods on the pallet follow the fill level against the pallet's OWN size, not the new capacity: 1,000 L on a
-- pallet built for 5,000 L shows a fifth of the goods, and more than its own size shows it full. The game counts the
-- visible goods from getFillUnitFillLevelPercentage (Pallet.lua onFillUnitFillLevelChanged), so for that call only
-- the fill unit has its own size back.
Pallet.onFillUnitFillLevelChanged = Utils.overwrittenFunction(Pallet.onFillUnitFillLevelChanged,
    function(vehicle, superFunc, fillUnitIndex, ...)
        local visual = vehicle.palletDepotVisualCapacity
        local spec = vehicle.spec_fillUnit
        local fillUnit = spec ~= nil and spec.fillUnits ~= nil and spec.fillUnits[fillUnitIndex] or nil
        if PalletDepotPallets.isOwnPallet(vehicle.configFileName)
            or visual == nil or vehicle.palletDepotCapacity == nil or fillUnit == nil or visual <= 0 or visual == math.huge then
            return superFunc(vehicle, fillUnitIndex, ...)
        end
        local capacity = fillUnit.capacity
        fillUnit.capacity = visual          -- over 100 % just shows every object (the game loops over what it has)
        local ok, result = pcall(superFunc, vehicle, fillUnitIndex, ...)
        fillUnit.capacity = capacity
        if not ok then
            error(result)
        end
        return result
    end)

local function isDepotSpawner(spawner)
    for _, depot in ipairs(PalletDepot.getDepots()) do
        if depot.palletSpawner == spawner then
            return true
        end
    end
    return false
end

-- --- spawning (server) ----------------------------------------------------------------------------------

-- prepended: runs before the spawner's callback fills the new (empty) pallet
PalletSpawner.onFinishLoadingPallet = Utils.prependedFunction(PalletSpawner.onFinishLoadingPallet,
    function(spawner, vehicles, vehicleLoadState)
        if g_server == nil or vehicles == nil or vehicles[1] == nil then
            return
        end
        local pallet = vehicles[1]
        local entry = spawner.currentObjectToSpawn ~= nil and spawner.currentObjectToSpawn.pallet or nil
        local liters = entry ~= nil and entry.palletDepotCapacity or 0
        -- capped: everything a depot spawns, and every pallet of our sizes, from ANY production (1.3.0.5: those
        -- outside the depots were left uncapped, a 5,000 L butter pallet weighed 775 kg)
        local kg = (isDepotSpawner(spawner) or liters > 0) and PalletDepotPalletMass.MAX_MASS or 0
        if liters <= 0 and kg <= 0 then
            return
        end
        applyCapacity(pallet, liters)
        apply(pallet, kg)
        g_server:broadcastEvent(PalletDepotPalletMassEvent.new(pallet, kg, liters))
        local mod = g_modManager ~= nil and g_modManager:getModByName(PalletDepot.modName) or nil
        Logging.info("[PalletDepot] %s: pallet %s capped at %d kg%s", mod ~= nil and mod.version or "?",
            tostring(pallet.configFileName), kg, liters > 0 and string.format(", %d L", liters) or "")
    end)

-- The cap must hold whatever resets maxComponentMass later: every mass update puts ours back first.
Vehicle.updateMass = Utils.prependedFunction(Vehicle.updateMass, function(vehicle)
    local kg = vehicle.palletDepotMaxMass
    if kg ~= nil and kg > 0 then
        vehicle.maxComponentMass = kg / 1000
    end
end)

-- --- event: the server tells the clients ---------------------------------------------------------------

PalletDepotPalletMassEvent = {}
local PalletDepotPalletMassEvent_mt = Class(PalletDepotPalletMassEvent, Event)
InitEventClass(PalletDepotPalletMassEvent, "PalletDepotPalletMassEvent")

function PalletDepotPalletMassEvent.emptyNew()
    return Event.new(PalletDepotPalletMassEvent_mt)
end

function PalletDepotPalletMassEvent.new(vehicle, kg, liters)
    local self = PalletDepotPalletMassEvent.emptyNew()
    self.vehicle = vehicle
    self.kg = kg or 0
    self.liters = liters or 0
    return self
end

function PalletDepotPalletMassEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.kg = streamReadUInt16(streamId)
    self.liters = streamReadInt32(streamId)
    applyCapacity(self.vehicle, self.liters)
    apply(self.vehicle, self.kg)
end

function PalletDepotPalletMassEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteUInt16(streamId, self.kg)
    streamWriteInt32(streamId, self.liters)
end

-- --- join synchronisation (every vehicle writes one flag, so both sides stay in step) ------------------

Vehicle.writeStream = Utils.appendedFunction(Vehicle.writeStream, function(vehicle, streamId, connection)
    if streamWriteBool(streamId, vehicle.palletDepotMaxMass ~= nil) then
        streamWriteUInt16(streamId, vehicle.palletDepotMaxMass)
    end
end)

Vehicle.readStream = Utils.appendedFunction(Vehicle.readStream, function(vehicle, streamId, connection)
    if streamReadBool(streamId) then
        apply(vehicle, streamReadUInt16(streamId))
    end
end)

-- The capacity goes in FillUnit's own join data, before its fill levels: the client adds the fill level against its
-- capacity (FillUnit:onReadStream), so it must have the new capacity first. Same conditions as the game's code.
FillUnit.onWriteStream = Utils.prependedFunction(FillUnit.onWriteStream, function(vehicle, streamId, connection)
    if not connection:getIsServer() then
        if streamWriteBool(streamId, vehicle.palletDepotCapacity ~= nil) then
            streamWriteInt32(streamId, vehicle.palletDepotCapacity)
        end
    end
end)

FillUnit.onReadStream = Utils.prependedFunction(FillUnit.onReadStream, function(vehicle, streamId, connection)
    if connection:getIsServer() then
        if streamReadBool(streamId) then
            applyCapacity(vehicle, streamReadInt32(streamId))
        end
    end
end)

-- --- savegame -------------------------------------------------------------------------------------------

Vehicle.saveToXMLFile = Utils.appendedFunction(Vehicle.saveToXMLFile, function(vehicle, xmlFile, key)
    if xmlFile == nil or xmlFile.handle == nil then
        return
    end
    if vehicle.palletDepotMaxMass ~= nil then
        setXMLInt(xmlFile.handle, key .. PalletDepotPalletMass.ATTR, vehicle.palletDepotMaxMass)
    end
    if vehicle.palletDepotCapacity ~= nil then
        setXMLInt(xmlFile.handle, key .. PalletDepotPalletMass.ATTR_CAPACITY, vehicle.palletDepotCapacity)
    end
end)

-- FillUnit.onLoad runs after Vehicle:load has read <components maxMass> and before FillUnit.onPostLoad puts the
-- saved fill level back, so the capacity is there before the litres are
FillUnit.onLoad = Utils.appendedFunction(FillUnit.onLoad, function(vehicle, savegame)
    if savegame == nil or savegame.xmlFile == nil or savegame.xmlFile.handle == nil then
        return
    end
    local liters = getXMLInt(savegame.xmlFile.handle, savegame.key .. PalletDepotPalletMass.ATTR_CAPACITY)
    if liters ~= nil then
        applyCapacity(vehicle, liters)
    end
    local kg = getXMLInt(savegame.xmlFile.handle, savegame.key .. PalletDepotPalletMass.ATTR)
    if kg ~= nil or liters ~= nil then      -- liters alone: a pallet of our sizes saved before 1.3.0.5, uncapped
        apply(vehicle, PalletDepotPalletMass.MAX_MASS)      -- today's cap, also for pallets saved under an older one
    end
end)
