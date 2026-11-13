-- Engine stand-ins for tests that run the GAME'S OWN Lua (loaded from gameSource.zip, see run_tests.py).
-- Only what the C++ engine provides lives here (physics mass, i3d loading, placement, streams, XML handles,
-- constants defined outside the Lua source). No game logic: every Vehicle / FillUnit / PalletSpawner function that
-- decides a pallet's weight or how it is spawned comes from the game's Lua.

Pallet = {}
Logging = {info = function() end, warning = function() end, devError = function(...) error(string.format(...)) end}
g_modManager = {getModByName = function() return {version = "test"} end}

-- result codes and enums the Lua source uses but does not define
PalletSpawner.RESULT_SUCCESS, PalletSpawner.RESULT_NO_SPACE = 0, 1
PalletSpawner.PALLET_LIMITED_REACHED, PalletSpawner.NO_PALLET_FOR_FILLTYPE = 2, 3
PalletSpawner.RESULT_ERROR_LOADING_PALLET = 4
VehicleLoadingState = {OK = 1, ERROR = 2}
VehiclePropertyState = {OWNED = 1}
SlotSystem = {LIMITED_OBJECT_PALLET = 1}

-- physics: the mass of each node (tonnes), as getMass / setMass see it
physicsMass = {}
function getMass(node) return physicsMass[node] end
function setMass(node, mass) physicsMass[node] = mass end
function getTerrainHeightAtWorldPos() return 0 end
g_terrainNode = 1

-- fill types: massPerLiter as FillTypeDesc.lua stores it (xml kg per litre * 0.001 = tonnes)
FILLTYPE_KG_PER_LITER = {}
g_fillTypeManager.getFillTypeByIndex = function(_, index)
    return {massPerLiter = (FILLTYPE_KG_PER_LITER[index] or 1) * 0.001}
end

-- pallet xml files: what Vehicle:loadFinished reads from them
PALLET_XML = {}

local nextNode = 100
-- Vehicle:loadFinished in the order the game runs it (Vehicle.lua): components and #maxMass (line 823) first,
-- then the specializations' onLoad with the savegame (line 1063). The vehicle's functions are the game's.
function loadPalletVehicle(filename, farmId, savegame, isServer)
    local xml = assert(PALLET_XML[filename], "no xml for " .. tostring(filename))
    nextNode = nextNode + 1
    physicsMass[nextNode] = xml.componentMassKg / 1000
    local v = {
        configFileName = filename, isServer = isServer ~= false, isPallet = true, ownerFarmId = farmId,
        components = {{node = nextNode, isDynamic = true, lastMass = 0}},
        maxComponentMass = (xml.maxMassKg or math.huge) / 1000,
        spec_pallet = {fillUnitIndex = 1},
        spec_fillUnit = {fillUnits = {{capacity = xml.capacity, fillLevel = 0, fillType = FillType.UNKNOWN,
                                       updateMass = true, fillMassNode = nextNode}}},
        isMassDirty = false, finishedFirstUpdate = true, deleted = false,
    }
    -- functions as SpecializationUtil binds them: FillUnit overwrites getAdditionalComponentMass (superFunc)
    v.updateMass = Vehicle.updateMass
    v.setMassDirty = Vehicle.setMassDirty
    v.getTotalMass = Vehicle.getTotalMass
    v.getComponentMass = Vehicle.getComponentMass
    v.getAdditionalComponentMass = function(self, component)
        return FillUnit.getAdditionalComponentMass(self, Vehicle.getAdditionalComponentMass, component)
    end
    v.getFillUnitCapacity = FillUnit.getFillUnitCapacity
    v.emptyAllFillUnits = FillUnit.emptyAllFillUnits
    v.getFillUnits = function(self) return self.spec_fillUnit.fillUnits end
    v.getFillUnitFillType = function(self, i) return self.spec_fillUnit.fillUnits[i].fillType end
    v.getFillUnitFillLevel = function(self, i) return self.spec_fillUnit.fillUnits[i].fillLevel end
    v.getOwnerFarmId = function(self) return self.ownerFarmId end
    -- the level change of FillUnit:addFillUnitFillLevel (within 0..capacity, sets the fill type, and as the
    -- game does for a fill unit with updateMass: setMassDirty)
    v.addFillUnitFillLevel = function(self, farmId, i, delta, fillType)
        local unit = self.spec_fillUnit.fillUnits[i]
        local old = unit.fillLevel
        unit.fillLevel = math.max(0, math.min(unit.capacity, old + delta))
        unit.fillType = unit.fillLevel > 0 and fillType or FillType.UNKNOWN
        if unit.updateMass then
            self:setMassDirty()
        end
        return unit.fillLevel - old
    end
    v.delete = function(self) self.deleted = true end
    -- Vehicle:update: "if self.finishedFirstUpdate and self.isMassDirty then self.isMassDirty = false
    -- self:updateMass() end"
    v.update = function(self)
        if self.finishedFirstUpdate and self.isMassDirty then
            self.isMassDirty = false
            self:updateMass()
        end
    end
    v.massKg = function(self) return self:getTotalMass() * 1000 end
    v.physicsKg = function(self) return physicsMass[self.components[1].node] * 1000 end
    FillUnit.onLoad(v, savegame)
    v:updateMass()
    return v
end

-- VehicleLoadingData: loads the i3d/xml and calls back like the engine (PalletSpawner passes spawnEmpty)
VehicleLoadingData = {}
function VehicleLoadingData.new()
    local data = {}
    function data:setFilename(f) self.filename = f end
    function data:setPosition() end
    function data:setRotation() end
    function data:setPropertyState() end
    function data:setOwnerFarmId(id) self.farmId = id end
    function data:setCustomParameter() end
    function data:load(callback, target)
        local vehicle = loadPalletVehicle(self.filename, self.farmId, nil, true)
        table.insert(LOADED_VEHICLES, vehicle)
        callback(target, {vehicle}, VehicleLoadingState.OK)
    end
    return data
end
LOADED_VEHICLES = {}

-- the mission: slots, updateables (run by runUpdates), placement always finds room
UPDATEABLES = {}
g_currentMission.slotSystem = {getCanAddLimitedObjects = function() return true end}
g_currentMission.addUpdateable = function(_, object) UPDATEABLES[object] = true end
g_currentMission.removeUpdateable = function(_, object) UPDATEABLES[object] = nil end
g_currentMission.placementManager = {getPlaceAsync = function(_, places, size, callback, target)
    callback(target, {x = 0, y = 0, z = 0, xRot = 0, yRot = 0, zRot = 0})
end}
function runUpdates()
    for _ = 1, 50 do
        for object in pairs(UPDATEABLES) do
            object:update(16)
        end
    end
    for _, vehicle in ipairs(LOADED_VEHICLES) do
        vehicle:update(16)
    end
end

-- a pallet spawner object of the game's class (its functions are the game's)
function newGameSpawner(fillTypeIdToPallet)
    return setmetatable({fillTypeIdToPallet = fillTypeIdToPallet, spawnQueue = {}, spawnPlaces = {{}},
                         fillTypeToSpawnPlaces = {}, spawnOffsetY = 0}, {__index = PalletSpawner})
end

-- network streams (engine): one shared queue
STREAM = {}
-- engine signatures: streamWriteX(streamId, value) returns value; streamReadX(streamId)
local function push(_, v) table.insert(STREAM, v) return v end
local function pop(_) return table.remove(STREAM, 1) end
streamWriteBool, streamReadBool = push, pop
streamWriteUInt16, streamReadUInt16 = push, pop
streamWriteInt32, streamReadInt32 = push, pop
NetworkUtil = {writeNodeObject = push, readNodeObject = pop}

-- savegame XML handles (engine): key -> value
function newSaveXML() return {handle = {values = {}}} end
function setXMLInt(handle, key, value) handle.values[key] = value end
function getXMLInt(handle, key) return handle.values[key] end
