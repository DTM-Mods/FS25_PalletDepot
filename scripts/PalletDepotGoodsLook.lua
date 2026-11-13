-- Native cargo, with its original geometry/UVs/materials, on the depot's existing rigid body.
-- Clone whole I3D graphs: lettuce crates share skinned geometry with the other crates.
PalletDepotGoodsLook = {DECK = 0.144, LAYER_TOLERANCE = 0.03}

function PalletDepotGoodsLook.getSourceFile(fillTypeIndex)
    local production = PalletDepotPallets.findProductionPallet(fillTypeIndex)
    if production ~= nil then return production end
    local desc = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    local filename = desc ~= nil and desc.palletFilename or nil
    if filename ~= nil and filename ~= "" and not PalletDepotPallets.isOwnPallet(filename) then return filename end
    return PalletDepotPallets.findStorePallet(fillTypeIndex)
end

local function release(request)
    if request.id ~= nil and not request.released then
        g_i3DManager:releaseSharedI3DFile(request.id)
        request.released = true
    end
end

function PalletDepotGoodsLook.clear(vehicle)
    local request = vehicle.palletDepotGoodsRequest
    vehicle.palletDepotGoodsRequest = nil
    for _, node in ipairs(vehicle.palletDepotGoodsNodes or {}) do delete(node) end
    vehicle.palletDepotGoodsNodes, vehicle.palletDepotGoodsWhole, vehicle.palletDepotGoodsFillType = nil, nil, nil
    if request ~= nil then request.discarded = true release(request) end
end

-- Imported nodes must never become extra collisions or bodies, including during autoload measurement.
local function visualsOnly(node)
    if getHasClassId(node, ClassIds.SHAPE) then
        if getIsCompoundChild(node) then setIsCompoundChild(node, false) end
        setRigidBodyType(node, RigidBodyType.NONE)
        setCollisionFilter(node, 0, 0)
    end
    for i = 0, getNumOfChildren(node) - 1 do visualsOnly(getChildAt(node, i)) end
end

local function sourceObjects(xml, scene)
    local components = {}
    for i = 0, getNumOfChildren(scene) - 1 do components[i + 1] = {node = getChildAt(scene, i)} end
    local mappings = {}
    I3DUtil.loadI3DMapping(xml, "vehicle", components, mappings, #components)
    local objects = {}
    for _, key in xml:iterator("vehicle.pallet.content") do
        for _, objectKey in xml:iterator(key .. ".object") do
            local node = xml:getValue(objectKey .. "#node", nil, components, mappings)
            if node ~= nil and node ~= 0 then
                local measure = xml:getValue(objectKey .. "#tensionBeltNode", nil, components, mappings)
                if measure == nil or measure == 0 then measure = node end
                while not getHasClassId(measure, ClassIds.SHAPE) and getNumOfChildren(measure) > 0 do
                    measure = getChildAt(measure, 0)
                end
                local x, y, z = 0, 0, 0
                if getHasClassId(measure, ClassIds.SHAPE) then x, y, z = getShapeBoundingSphere(measure) end
                local _, centerY = localToLocal(measure, scene, x, y, z)
                table.insert(objects, {node = node, y = centerY})
            end
        end
    end
    local wood = xml:getValue("vehicle.pallet#node", nil, components, mappings)
    if wood ~= nil and wood ~= 0 then
        local ancestor = false
        for _, object in ipairs(objects) do
            local parent = object.node
            while parent ~= 0 and parent ~= scene do
                if parent == wood then ancestor = true break end
                parent = getParent(parent)
            end
        end
        if not ancestor and (#objects > 0 or getNumOfChildren(wood) == 0) then setVisibility(wood, false) end
    end
    return objects
end

-- Tension meshes locate individual crates even when the visible mesh contains many skinned crates.
function PalletDepotGoodsLook.measureRows(objects, height)
    local heights, rows = {}, {}
    for _, object in ipairs(objects) do table.insert(heights, object.y) end
    table.sort(heights)
    for _, y in ipairs(heights) do
        if #rows == 0 or y - rows[#rows] > PalletDepotGoodsLook.LAYER_TOLERANCE then table.insert(rows, y) end
    end
    local pitch = #rows > 1 and rows[2] - rows[1] or height - PalletDepotGoodsLook.DECK
    return rows[1], math.max(0.01, pitch)
end

local function holders(vehicle)
    for _, content in ipairs(vehicle.spec_pallet.contents or {}) do
        if content.fillUnitIndex == (vehicle.spec_pallet.fillUnitIndex or 1) then return content.objects end
    end
    return {}
end

function PalletDepotGoodsLook.onLoaded(request, scene, failedReason)
    local vehicle = request.vehicle
    if scene == 0 or vehicle.isDeleted or vehicle.isDeleting
        or request.discarded or vehicle.palletDepotGoodsRequest ~= request then
        if scene ~= 0 then delete(scene) end
        request.discarded = true
        release(request)
        if scene == 0 and not vehicle.isDeleted and not vehicle.isDeleting and not request.warned then
            Logging.warning("[PalletDepot] Could not load product geometry %s (%s)", request.i3d, tostring(failedReason))
            request.warned = true
        end
        return
    end
    local xml = XMLFile.loadIfExists("palletDepotNativeCargo", request.filename, Vehicle.xmlSchema)
    if xml == nil then delete(scene) request.discarded = true release(request) return end
    local objects, layers = sourceObjects(xml, scene), holders(vehicle)
    if #layers == 0 then xml:delete() delete(scene) request.discarded = true release(request) return end
    local deck = PalletDepotGoodsLook.DECK
    local targetHeight = vehicle.size.height - deck
    local pitch = targetHeight / #layers
    local sx, sz = vehicle.size.width / request.width, vehicle.size.length / request.length
    local center, sourcePitch = PalletDepotGoodsLook.measureRows(objects, request.height)
    vehicle.palletDepotGoodsNodes = {}
    if center ~= nil then
        for index, layer in ipairs(layers) do
            local cargo = clone(scene, false, false, false)
            visualsOnly(cargo)
            for _, object in ipairs(sourceObjects(xml, cargo)) do
                setVisibility(object.node, math.abs(object.y - center) <= PalletDepotGoodsLook.LAYER_TOLERANCE)
            end
            link(layer.node, cargo)
            local sy = pitch / sourcePitch
            setScale(cargo, sx, sy, sz)
            setTranslation(cargo, 0, deck + (index - 1) * pitch - (center - sourcePitch / 2) * sy, 0)
            table.insert(vehicle.palletDepotGoodsNodes, cargo)
        end
    else
        -- Indivisible cargo (churns, tanks, etc.) keeps its complete native assembly, fitted to the envelope.
        local cargo = clone(scene, false, false, false)
        visualsOnly(cargo)
        sourceObjects(xml, cargo)
        link(layers[1].node, cargo)
        local sy = targetHeight / math.max(0.01, request.height - deck)
        vehicle.palletDepotGoodsWhole = {node = cargo, sx = sx, sy = sy, sz = sz}
        setScale(cargo, sx, sy, sz)
        setTranslation(cargo, 0, deck - deck * sy, 0)
        table.insert(vehicle.palletDepotGoodsNodes, cargo)
    end
    xml:delete()
    delete(scene)
    vehicle.palletDepotGoodsFillType = request.fillType
    PalletDepotGoodsLook.update(vehicle, request.fillType)
end

function PalletDepotGoodsLook.update(vehicle, fillTypeIndex)
    if not PalletDepotPallets.isOwnPallet(vehicle.configFileName) or vehicle.isDeleted or vehicle.isDeleting then return end
    local spec = vehicle.spec_pallet
    if spec == nil or spec.contents == nil then return end
    fillTypeIndex = fillTypeIndex or vehicle:getFillUnitFillType(spec.fillUnitIndex or 1)
    if fillTypeIndex == nil or fillTypeIndex == FillType.UNKNOWN then return end
    if vehicle.palletDepotGoodsFillType == fillTypeIndex then
        local whole = vehicle.palletDepotGoodsWhole
        if whole ~= nil then
            local layers = holders(vehicle)
            local fraction = (vehicle.palletDepotShownLayers or #layers) / math.max(1, #layers)
            local sy = whole.sy * math.max(0.001, fraction)
            setScale(whole.node, whole.sx, sy, whole.sz)
            setTranslation(whole.node, 0, PalletDepotGoodsLook.DECK * (1 - sy), 0)
        end
        return
    end
    local current = vehicle.palletDepotGoodsRequest
    if current ~= nil and current.fillType == fillTypeIndex then return end
    PalletDepotGoodsLook.clear(vehicle)
    local filename = PalletDepotGoodsLook.getSourceFile(fillTypeIndex)
    if filename == nil then
        Logging.warning("[PalletDepot] No original pallet for fill type %s; no substitute cartons will be drawn", tostring(fillTypeIndex))
        vehicle.palletDepotGoodsRequest = {fillType = fillTypeIndex}
        return
    end
    local xml = XMLFile.loadIfExists("palletDepotNativeCargo", filename, Vehicle.xmlSchema)
    if xml == nil then return end
    local _, baseDirectory = Utils.getModNameAndBaseDirectory(filename)
    local request = {vehicle = vehicle, filename = filename, fillType = fillTypeIndex,
        -- Vehicle.lua registers this field as STRING, so XMLFile does not resolve its path.
        -- Use the same explicit resolver as Vehicle:load, including mod roots and $data macros.
        i3d = Utils.getFilename(xml:getValue("vehicle.base.filename"), baseDirectory),
        width = math.max(0.1, xml:getValue("vehicle.base.size#width", 1.3)),
        length = math.max(0.1, xml:getValue("vehicle.base.size#length", 0.9)),
        height = math.max(0.154, xml:getValue("vehicle.base.size#height", 1.3))}
    xml:delete()
    if request.i3d == nil then return end
    vehicle.palletDepotGoodsRequest = request
    request.id = g_i3DManager:loadSharedI3DFileAsync(request.i3d, false, false, PalletDepotGoodsLook.onLoaded, request)
    if request.discarded then release(request) end
end

Pallet.onFillUnitFillLevelChanged = Utils.appendedFunction(Pallet.onFillUnitFillLevelChanged,
    function(vehicle) PalletDepotGoodsLook.update(vehicle) end)
Pallet.onPostLoad = Utils.appendedFunction(Pallet.onPostLoad,
    function(vehicle) PalletDepotGoodsLook.update(vehicle) end)
Pallet.onDelete = Utils.prependedFunction(Pallet.onDelete,
    function(vehicle) PalletDepotGoodsLook.clear(vehicle) end)
