-- Engine interfaces and XML/node fixtures for real FillUnit/Pallet/AnimatedVehicle tests.
AnimatedVehicle = {}
AnimationValueFloat = {TANGENT_TYPE_LINEAR = 0, TANGENT_TYPE_SPLINE = 1, TANGENT_TYPE_STEP = 2}
SpecializationUtil = {}
unpack = table.unpack
math.sign = function(v) return v > 0 and 1 or (v < 0 and -1 or 0) end
math.clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
table.hasElement = function(t, v) for _, item in ipairs(t) do if item == v then return true end end return false end
table.addElement = function(t, v) table.insert(t, v) end
table.removeElement = function(t, v) for i, item in ipairs(t) do if item == v then table.remove(t, i) return end end end
VehicleStateChange = {FILLTYPE_CHANGE = 1}
FillUnit.updateUnloadActionDisplay = function() end -- engine function absent from the debugger source
g_currentMission.accessHandler = {canFarmAccess = function() return true end}
g_guidedTourManager = {getIsTourRunning = function() return false end}
g_currentMission.missionInfo = {trailerFillLimit = false}
g_soundManager = {playSample = function() end}

NODE_SCALE, NODE_VISIBLE, NODE_MATERIAL, MATERIAL_TEXTURE = {}, {}, {}, {}
function setScale(node, x, y, z) NODE_SCALE[node] = {x, y, z} end
function getScale(node) return unpack(NODE_SCALE[node] or {1, 1, 1}) end
function setVisibility(node, active) NODE_VISIBLE[node] = active end
function getMaterial(node) return NODE_MATERIAL[node] or 1 end
local materialId = 1
function setMaterialDiffuseMapFromFile(original, texture)
    materialId = materialId + 1
    MATERIAL_TEXTURE[materialId] = texture
    return materialId
end
function setMaterial(node, material) NODE_MATERIAL[node] = material end
streamWriteFloat32, streamReadFloat32 = streamWriteInt32, streamReadInt32
streamWriteUIntN, streamReadUIntN = streamWriteInt32, streamReadInt32
g_fillTypeManager.getFillTypeByIndex = function(_, index)
    return {hudOverlayFilename = '/products/product' .. index .. '.dds'}
end
g_fillTypeManager.getFillTypeIndexByName = function(_, name)
    for index, title in pairs(FILLTYPE_NAMES) do if title == name then return index end end
end

function stackSaveXML()
    local xml = newSaveXML()
    function xml:setValue(key, value) self.handle.values[key] = value end
    function xml:getValue(key, default) local v = self.handle.values[key] if v == nil then return default end return v end
    function xml:hasProperty(key)
        for name in pairs(self.handle.values) do if name:sub(1, #key) == key then return true end end
        return false
    end
    return xml
end

local nextNode = 10000
function layeredPallet(size, server)
    local model = PALLET_MODELS[size]
    nextNode = nextNode + 100
    local collision = nextNode
    local objects = {}
    for i = 1, model.layers do
        objects[i] = {node = nextNode + i, isActive = false}
        NODE_VISIBLE[nextNode + i] = false
    end
    local unit = {capacity = size, fillLevel = 0, fillType = 5, lastValidFillType = 5,
        supportedFillTypes = {[5] = true, [6] = true}, supportedToolTypes = {[0] = true},
        ignoreFillLimit = true, autoAimTarget = {}, needsSaving = true,
        synchronizeFillLevel = true, fillLevelSent = 0, synchronizationNumBits = 16,
        fillEffects = {}, animationNodes = {}, alarmTriggers = {},
        fillLevelAnimations = {{name = 'fillAnimation', resetOnEmpty = true, updateWhileFilled = true}}}
    local v = {configFileName = '/mods/FS25_PalletDepot/vehicles/depotPallet' .. size .. '.xml',
        isServer = server ~= false, isClient = false, i3dMappings = {contentCollision = collision},
        size = {width = 1.2, length = 0.8, height = model.height},
        spec_pallet = {fillUnitIndex = 1, contents = {{fillUnitIndex = 1, objects = objects}}, samples = {}, nodes = {}, textures = {}},
        spec_fillUnit = {fillUnits = {unit}, fillEffects = {}, animationNodes = {}, activeFillEffects = {},
            activeFillAnimations = {}, allowFoldingWhileFilled = true, fillTypeChangeThreshold = 0.01,
            fillTrigger = {isFilling = false}},
        eventListeners = {onFillUnitFillLevelChanged = {Pallet}, onChangedFillType = {}, onPlayAnimation = {},
            onStopAnimation = {}, onStartAnimation = {}, onFinishAnimation = {}, onAnimationPartChanged = {}, onUpdateAnimation = {}},
        vehicleLoadingData = {getCustomParameter = function() return true end}}
    v.spec_pallet.contents[1].numObjects = #objects
    v.rootVehicle = v
    function v:getOwnerFarmId() return 1 end
    function v:raiseDirtyFlags() end
    function v:raiseActive() end
    function v:raiseStateChange() end
    for _, name in ipairs({'getFillUnitFillLevelPercentage', 'addFillUnitFillLevel', 'getFillUnitFillType',
        'getFillUnitSupportsToolTypeAndFillType', 'getFillUnitSupportsToolType', 'getFillUnitSupportsFillType',
        'getFillUnitAllowsFillType', 'getFillTypeChangeThreshold', 'updateFillUnitAutoAimTarget', 'updateAlarmTriggers',
        'setFillUnitLastValidFillType', 'setFillUnitIsFilling'}) do v[name] = FillUnit[name] end
    v.setPalletTensionBeltNodesDirty = Pallet.setPalletTensionBeltNodesDirty
    local animation = {name = 'fillAnimation', currentTime = 0, currentSpeed = 1, duration = 1000,
        parts = {}, partsReverse = {}, currentPartIndex = 1, samples = {}}
    local part = {startTime = 0, duration = 1000, direction = 0, animationValues = {}}
    local value = setmetatable({animation = animation, part = part, initialUpdate = true, tangentType = 0,
        startValue = {1, model.minScale, 1}, endValue = {1, 1, 1},
        oldCurValues = {}, oldSpeed = {}, curStartValue = {}, curRealValue = {},
        get = function() return getScale(collision) end,
        set = function(_, x, y, z) setScale(collision, x, y, z) end}, {__index = AnimationValueFloat})
    part.animationValues[1] = value
    animation.parts[1], animation.partsReverse[1] = part, part
    v.spec_animatedVehicle = {animations = {fillAnimation = animation}, activeAnimations = {}, numActiveAnimations = 0}
    for _, name in ipairs({'getAnimationExists', 'getAnimationTime', 'setAnimationTime', 'setRealAnimationTime',
        'resetAnimationValues', 'resetAnimationPartValues', 'setAnimationStopTime', 'playAnimation',
        'stopAnimation', 'getIsAnimationPlaying', 'updateAnimationPart'}) do v[name] = AnimatedVehicle[name] end
    return v, unit, objects
end
