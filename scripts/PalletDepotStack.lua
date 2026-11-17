-- Whole carton layers and the matching built-in animated collision, on our own pallets only.
-- Autoload uses our known box dimensions instead of caching an unreliable first raycast measurement.
PalletDepotStack = {}
PalletDepotStack.MIN_SCALE = 0.001       -- matches tools/pallet_layout.py and vehicle fillAnimation

function PalletDepotStack.update(vehicle, fillUnitIndex)
    if not PalletDepotPallets.isOwnPallet(vehicle.configFileName) then return end
    local spec = vehicle.spec_pallet
    local fillSpec = vehicle.spec_fillUnit
    if spec == nil or spec.contents == nil or fillSpec == nil then return end
    fillUnitIndex = fillUnitIndex or spec.fillUnitIndex or 1
    local unit = fillSpec.fillUnits[fillUnitIndex]
    if unit == nil or unit.capacity <= 0 then return end
    local fraction = math.max(0, math.min(1, unit.fillLevel / unit.capacity))
    local layerCount, shown = 0, 0
    for _, content in ipairs(spec.contents) do
        if content.fillUnitIndex == fillUnitIndex then
            layerCount = #content.objects
            shown = fraction > 0 and math.max(1, math.ceil(fraction * layerCount - 0.000001)) or 0
            for index, object in ipairs(content.objects) do
                local active = index <= shown
                if object.isActive ~= active then
                    object.isActive = active
                    setVisibility(object.node, active)
                    vehicle:setPalletTensionBeltNodesDirty()
                end
            end
        end
    end
    if layerCount == 0 then return end
    local scale = math.max(PalletDepotStack.MIN_SCALE, shown / layerCount)
    local time = (scale - PalletDepotStack.MIN_SCALE) / (1 - PalletDepotStack.MIN_SCALE)
    if vehicle.getAnimationExists ~= nil and vehicle:getAnimationExists("fillAnimation") then
        -- stopAnimation's true flag avoids network events: each peer derives this from synced litres.
        vehicle:stopAnimation("fillAnimation", true)
        -- The I3D starts at full scale, while a newly loaded animation starts at time zero.
        -- Prime time one before moving down to any partial/empty state.
        if not vehicle.palletDepotCollisionInitialized then
            vehicle:setAnimationTime("fillAnimation", 1, true, false)
        end
        vehicle:setAnimationTime("fillAnimation", time, true, false)
        vehicle:setAnimationStopTime("fillAnimation", time)
        vehicle.palletDepotCollisionInitialized = true
    end
    vehicle.palletDepotShownLayers = shown
end

-- Correct the game's floor() visibility rule (including its first-object-at-zero behaviour).
Pallet.onFillUnitFillLevelChanged = Utils.appendedFunction(Pallet.onFillUnitFillLevelChanged,
    function(vehicle, index) PalletDepotStack.update(vehicle, index) end)

-- FillUnit schedules its linear animation AFTER the pallet event. Correct it after the entire call.
FillUnit.addFillUnitFillLevel = Utils.overwrittenFunction(FillUnit.addFillUnitFillLevel,
    function(vehicle, superFunc, farmId, index, ...)
        local delta = superFunc(vehicle, farmId, index, ...)
        if not vehicle.isDeleted then PalletDepotStack.update(vehicle, index) end
        return delta
    end)

-- Save loading explicitly advances animations after filling; reapply the layer stop after that too.
FillUnit.onPostLoad = Utils.appendedFunction(FillUnit.onPostLoad,
    function(vehicle) PalletDepotStack.update(vehicle) end)
Pallet.onPostLoad = Utils.appendedFunction(Pallet.onPostLoad,
    function(vehicle) PalletDepotStack.update(vehicle) end)

function PalletDepotStack.getAutoloadType(vehicle, measured)
    if measured == nil or not PalletDepotPallets.isOwnPallet(vehicle.configFileName) then return measured end
    local size = vehicle.size
    -- FS25 mapping values are records; engine transform functions require the record's nodeId.
    local mapping = vehicle.i3dMappings ~= nil and vehicle.i3dMappings.contentCollision or nil
    local collision = mapping ~= nil and mapping.nodeId or nil
    if size == nil or collision == nil or collision == 0 then return measured end
    local _, deck = getTranslation(collision)
    local _, scaleY = getScale(collision)
    -- Copy: UAL shares its cached full-pallet type between every product on the same model.
    local corrected = {}
    for key, value in pairs(measured) do corrected[key] = value end
    corrected.sizeX, corrected.sizeZ = size.width, size.length
    corrected.sizeY = deck + (size.height - deck) * scaleY
    corrected.width = math.min(corrected.sizeX, corrected.sizeZ)
    corrected.length = math.max(corrected.sizeX, corrected.sizeZ)
    -- Our model's origin is centered on the pallet's bottom, including its runners.
    corrected.offset = {x = 0, y = 0, z = 0}
    return corrected
end

function PalletDepotStack.installAutoload()
    if PalletDepotStack.autoloadInstalled then return end
    local mod = _G["FS25_UniversalAutoload"]
    local autoload = mod ~= nil and mod.UniversalAutoload or nil
    if autoload == nil or autoload.getContainerType == nil then return end
    autoload.getContainerType = Utils.overwrittenFunction(autoload.getContainerType,
        function(vehicle, superFunc, ...)
            local measured = superFunc(vehicle, ...)
            if vehicle == nil then return measured end
            return PalletDepotStack.getAutoloadType(vehicle, measured)
        end)
    PalletDepotStack.autoloadInstalled = true
end

-- Both mods have finished loading by this point; UAL remains optional.
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished,
    PalletDepotStack.installAutoload)
