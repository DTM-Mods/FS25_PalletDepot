-- Stand-ins for the parts of the FS25 engine the tested scripts touch, plus helpers to build test objects.
-- Loaded by tests/run_tests.py into a fresh Lua runtime before the mod's scripts and one test file.

g_currentModName = "FS25_PalletDepot"
g_currentModDirectory = "/mods/FS25_PalletDepot/"

function Class(class, super)
    return {__index = class}
end
Event = {new = function(mt) return setmetatable({}, mt) end}
function InitEventClass() end
Utils = {
    appendedFunction = function(old, new) return function(...) if old then old(...) end new(...) end end,
    prependedFunction = function(old, new) return function(...) new(...) if old then old(...) end end end,
    overwrittenFunction = function(old, new) return function(self, ...) return new(self, old, ...) end end,
    getNoNil = function(value, default) if value == nil then return default end return value end,
}

FillType = {UNKNOWN = 0}
FillUnit = {}
ProductionPoint = {OUTPUT_MODE = {KEEP = 0, DIRECT_SELL = 1, AUTO_DELIVER = 2}, updateProduction = function() end}
FSBaseMission = {INGAME_NOTIFICATION_OK = 1, INGAME_NOTIFICATION_CRITICAL = 2}
Mission00 = {}
FarmManager = {SPECTATOR_FARM_ID = 0}
FillTypeManager = {SEND_NUM_BITS = 10}
ToolType = {UNDEFINED = 0}
PalletSpawner = {RESULT_SUCCESS = 0, RESULT_NO_SPACE = 1, PALLET_LIMITED_REACHED = 2}
StoreItemUtil = {getSizeValues = function() return {width = 1.2, length = 1, height = 1.5} end}
XMLFile = {load = function() return nil end}
Vehicle = {}

notifications = {}
g_i18n = {getText = function(_, key) return key end, formatNumber = function(_, v) return tostring(v) end}
FILLTYPE_NAMES = {[5] = "CARROTBAG", [6] = "CHEESE", [7] = "FLOUR"}
g_fillTypeManager = {
    indexToFillType = {},
    getFillTypeTitleByIndex = function(_, i) return "FT" .. i end,
    getFillTypeByIndex = function(_, i) return {} end,
    getFillTypeNameByIndex = function(_, i) return FILLTYPE_NAMES[i] end,
}
g_farmManager = {getFarmById = function(_, id) if id == 1 or id == 2 then return {farmId = id} end end}
g_currentMission = {addIngameNotification = function(_, kind, text) table.insert(notifications, text) end}
g_server = {broadcastEvent = function() end}

-- --- test helpers --------------------------------------------------------------------------------------

function assertEqual(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
    end
end

-- a spawned pallet vehicle
function newPalletVehicle(entry, farmId)
    local v = {fill = 0, cap = entry.capacity, file = entry.filename, sized = entry.palletDepotCapacity,
               farm = farmId, deleted = false, spec_pallet = {fillUnitIndex = 1}}
    function v:emptyAllFillUnits() self.fill = 0 end
    function v:getFillUnitCapacity() return self.cap end
    function v:addFillUnitFillLevel(farm, fillUnit, amount)
        local delta = math.min(amount, self.cap - self.fill)
        self.fill = self.fill + delta
        return delta
    end
    function v:delete() self.deleted = true end
    return v
end

-- a pallet spawner like the game's: requests queue up, run() spawns them (space: how many fit)
function newSpawner(gamePallets)
    local spawner = {fillTypeIdToPallet = gamePallets, queue = {}, space = 99, spawned = {}}
    function spawner:loadPalletFromFilename(filename)
        local pallet = {filename = filename, capacity = tonumber(filename:match("(%d+)%.xml"))}
        for fillType = 1, 10 do
            self.fillTypeIdToPallet[fillType] = pallet      -- as the game does: every fill type it supports
        end
        return pallet
    end
    function spawner:spawnPallet(farmId, fillType, callback, target)
        table.insert(self.queue, {pallet = self.fillTypeIdToPallet[fillType], fillType = fillType, callback = callback,
                                  target = target, farmId = farmId})
    end
    function spawner:run()
        for _, request in ipairs(self.queue) do
            if self.space > 0 then
                self.space = self.space - 1
                local vehicle = newPalletVehicle(request.pallet, request.farmId)
                table.insert(self.spawned, vehicle)
                request.callback(request.target, vehicle, PalletSpawner.RESULT_SUCCESS, request.fillType)
            else
                request.callback(request.target, nil, PalletSpawner.RESULT_NO_SPACE, request.fillType)
            end
        end
        self.queue = {}
    end
    return spawner
end

function newStorage(levels)
    local storage = {fillLevels = levels}
    function storage:getFillLevel(fillType) return self.fillLevels[fillType] or 0 end
    function storage:setFillLevel(value, fillType) self.fillLevels[fillType] = value end
    return storage
end

-- a production point; isHub: one of our buildings. Outputs 5 (carrot bags, game pallet of 1,000 L), 6 (cheese, no
-- pallet of its own) and 7 (flour, game pallet of 1,000 L).
function newProductionPoint(isHub, levels)
    local gamePallet = {filename = "/data/carrotPallet.xml", capacity = 1000}
    local flourPallet = {filename = "/data/flourPallet.xml", capacity = 1000}
    local pp = {
        palletSpawner = newSpawner({[5] = gamePallet, [7] = flourPallet}),
        storage = newStorage(levels or {[5] = 30987, [6] = 400, [7] = 2000}),
        outputFillTypeIds = {[5] = true, [6] = true, [7] = true},
        outputFillTypeIdsToPallets = {[5] = gamePallet, [7] = flourPallet},
        owningPlaceable = {customEnvironment = isHub and "FS25_PalletDepot" or "FS25_SomeFactory"},
        gamePallet = gamePallet,
    }
    function pp:getName() return isHub and "Hub" or "Factory" end
    function pp:getOwnerFarmId() return 1 end
    return pp
end
