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

-- Names of the nodes that act as skin bones in an I3D (e.g. boardsStack2..8 posing one skinned mesh).
-- Hiding a bone hides nothing, so pallets whose layers are bones must be drawn whole. Cached per file;
-- a binary/unreadable I3D gives an empty set (old per-layer behaviour).
PalletDepotGoodsLook.boneCache = {}
function PalletDepotGoodsLook.getBoneNames(i3d)
    local cached = PalletDepotGoodsLook.boneCache[i3d]
    if cached ~= nil then return cached end
    local names, idToName, boneIds = {}, {}, {}
    local xmlId = loadXMLFile("palletDepotI3dBones", i3d)
    if xmlId ~= nil and xmlId ~= 0 then
        local function walk(key)
            for _, tag in ipairs({"Shape", "TransformGroup"}) do
                local i = 0
                while true do
                    local childKey = string.format("%s.%s(%d)", key, tag, i)
                    if not hasXMLProperty(xmlId, childKey) then break end
                    local nodeId = getXMLString(xmlId, childKey .. "#nodeId")
                    local name = getXMLString(xmlId, childKey .. "#name")
                    if nodeId ~= nil and name ~= nil then idToName[nodeId] = name end
                    local skin = getXMLString(xmlId, childKey .. "#skinBindNodeIds")
                    if skin ~= nil then
                        for id in skin:gmatch("%S+") do boneIds[id] = true end
                    end
                    walk(childKey)
                    i = i + 1
                end
            end
        end
        walk("i3D.Scene")
        delete(xmlId)
    end
    for id in pairs(boneIds) do
        if idToName[id] ~= nil then names[idToName[id]] = true end
    end
    PalletDepotGoodsLook.boneCache[i3d] = names
    return names
end

local function layersAreBones(objects, boneNames)
    for _, object in ipairs(objects) do
        if boneNames[getName(object.node)] then return true end
    end
    return false
end

local function holders(vehicle)
    for _, content in ipairs(vehicle.spec_pallet.contents or {}) do
        if content.fillUnitIndex == (vehicle.spec_pallet.fillUnitIndex or 1) then return content.objects end
    end
    return {}
end

-- Single-weight skinning does not support scaled joints (even uniform scale changes the rotation).
-- Fit the native plank vertices in the shader instead; the complete skeleton stays at unit scale.
function PalletDepotGoodsLook.fitPlankStack(cargo, request, targetHeight)
    if not request.i3d:match("/boardsStackPallet/boardsStackPallet%.i3d$") then return nil end
    local function find(node)
        if getName(node) == "boardsStack1" then return node end
        for i = 0, getNumOfChildren(node) - 1 do
            local found = find(getChildAt(node, i))
            if found ~= nil then return found end
        end
    end
    local shape = find(cargo)
    if shape == nil then return nil end
    -- Native boardsStackPallet bounds measured offline in GIANTS Editor (1,984 vertices).
    -- getShapeVertexPositions is editor-only: calling it in game aborts cargo fitting.
    -- These values apply only to the specific base-game model checked above.
    local lo = {-0.6065325737, 0.1446710825, -0.4158901572}
    local hi = {0.6073279977, 0.6446714997, 0.4158901572}
    local template, sharedId = g_i3DManager:loadSharedI3DFile(
        PalletDepot.modDirectory .. "vehicles/plankCargoMaterial.i3d", false, false)
    if template == 0 then
        if sharedId ~= nil then g_i3DManager:releaseSharedI3DFile(sharedId) end
        Logging.warning("[PalletDepot] Could not load plank cargo material")
        return nil
    end
    setMaterial(shape, getMaterial(getChildAt(template, 0), 0), 0)
    delete(template)
    if sharedId ~= nil then g_i3DManager:releaseSharedI3DFile(sharedId) end
    return {shape = shape, sx = request.vehicle.size.width / (hi[1] - lo[1]),
        sy = targetHeight / (hi[2] - lo[2]), sz = request.vehicle.size.length / (hi[3] - lo[3]),
        baseY = lo[2], centerX = (lo[1] + hi[1]) / 2, centerZ = (lo[3] + hi[3]) / 2,
        radius = select(4, getShapeBoundingSphere(shape))}
end

-- Other skinned cargo (barrels, crates, bags, ...): its bones carry positions and turns, and rigid parts
-- (fruit, leaves, straps) hang off them. Scaling any bone or ancestor skews the skin, so the skeleton stays at
-- unit scale; skinned meshes are scaled in the cargo's frame before skinning (shaders/skinnedCargoFit.xml) and
-- the rigid parts move under one scaled node, keeping their pose and visibility.
PalletDepotGoodsLook.fitMaterials = {}
local function fitMaterial(original)
    local diffuse = getMaterialDiffuseMapFilename(original) or ""
    local normal = getMaterialNormalMapFilename(original) or ""
    local gloss = getMaterialGlossMapFilename(original) or ""
    local key = diffuse .. "|" .. normal .. "|" .. gloss
    local cached = PalletDepotGoodsLook.fitMaterials[key]
    if cached ~= nil then return cached end
    if PalletDepotGoodsLook.fitCarrier == nil then
        local template = g_i3DManager:loadSharedI3DFile(
            PalletDepot.modDirectory .. "vehicles/skinnedCargoMaterial.i3d", false, false)
        if template == nil or template == 0 then
            Logging.warning("[PalletDepot] Could not load skinned cargo material")
            PalletDepotGoodsLook.fitCarrier = false
        else
            -- kept for the session: the template owns the carrier material
            PalletDepotGoodsLook.fitCarrier = getMaterial(getChildAt(template, 0), 0)
            PalletDepotGoodsLook.fitTemplate = template
        end
    end
    if not PalletDepotGoodsLook.fitCarrier then return nil end
    local material = PalletDepotGoodsLook.fitCarrier
    if diffuse ~= "" then material = setMaterialDiffuseMapFromFile(material, diffuse, true, true, false) end
    if normal ~= "" then material = setMaterialNormalMapFromFile(material, normal, true, false, false) end
    if gloss ~= "" then material = setMaterialGlossMapFromFile(material, gloss, true, true, false) end
    PalletDepotGoodsLook.fitMaterials[key] = material
    return material
end

local function frameOf(node, cargo)
    return {t = {localToLocal(node, cargo, 0, 0, 0)},
        c = {{localDirectionToLocal(node, cargo, 1, 0, 0)}, {localDirectionToLocal(node, cargo, 0, 1, 0)},
             {localDirectionToLocal(node, cargo, 0, 0, 1)}}}
end

local function fitShape(cargo, shape, materials, inPlace)
    for m, material in pairs(materials) do setMaterial(shape, material, m) end
    local entry = frameOf(shape, cargo)
    entry.shape, entry.inPlace = shape, inPlace
    return entry
end

-- Native skinned cargo is one piece modelled at the mesh origin; its bones place the copies (measured on all
-- 17 base-game models). Each piece is scaled in its own space by the shader and each bone is moved (never
-- scaled) to its fitted spot. Visible non-skinned shapes that hold bones are scaled in place by the shader.
-- Left on the old path at the user's request (goat milk never comes out of a depot).
PalletDepotGoodsLook.SKIN_FIT_SKIP = {"/goatMilkCanPallet/goatMilkCanPallet.i3d"}

function PalletDepotGoodsLook.prepareSkinFit(cargo, i3d)
    for _, suffix in ipairs(PalletDepotGoodsLook.SKIN_FIT_SKIP) do
        if i3d ~= nil and i3d:sub(-#suffix) == suffix then return nil end
    end
    local skins, keep = {}, {}
    local function collect(node)
        if getHasClassId(node, ClassIds.SHAPE) and getShapeIsSkinned(node) then table.insert(skins, node) end
        for i = 0, getNumOfChildren(node) - 1 do collect(getChildAt(node, i)) end
    end
    collect(cargo)
    if #skins == 0 then return nil end
    local function mark(node)
        while node ~= 0 and node ~= cargo and not keep[node] do keep[node] = true node = getParent(node) end
    end
    local bones, isBone = {}, {}
    for _, skin in ipairs(skins) do
        mark(skin)
        for b = 0, getNumOfShapeBones(skin) - 1 do
            local bone = getShapeBone(skin, b)
            mark(bone)
            if not isBone[bone] then isBone[bone] = true table.insert(bones, bone) end
        end
    end
    local function materialsOf(shape, needMaps)
        local list = {}
        for m = 0, getNumOfMaterials(shape) - 1 do
            local original = getMaterial(shape, m)
            if needMaps and (getMaterialDiffuseMapFilename(original) or "") == "" then return nil end
            local material = fitMaterial(original)
            if material == nil then return false end
            list[m] = material
        end
        return list
    end
    local skinMaterials, holders = {}, {}
    for _, skin in ipairs(skins) do
        skinMaterials[skin] = materialsOf(skin, false)
        if not skinMaterials[skin] then return nil end
    end
    for node in pairs(keep) do
        if getHasClassId(node, ClassIds.SHAPE) and not getShapeIsSkinned(node) then
            local list = materialsOf(node, true)
            if list == false then return nil end
            if list ~= nil then holders[node] = list end
        end
    end
    local function hidden(node)
        node = getParent(node)
        while node ~= 0 and node ~= cargo do
            if not getVisibility(node) then return true end
            node = getParent(node)
        end
        return false
    end
    local moving = {}
    local function findMoving(node)
        for i = 0, getNumOfChildren(node) - 1 do
            local child = getChildAt(node, i)
            if keep[child] then findMoving(child) else table.insert(moving, child) end
        end
    end
    findMoving(cargo)
    local rigid = createTransformGroup("palletDepotRigidCargo")
    link(cargo, rigid)
    for _, node in ipairs(moving) do
        local x, y, z = localToLocal(node, cargo, 0, 0, 0)
        local dx, dy, dz = localDirectionToLocal(node, cargo, 0, 0, 1)
        local ux, uy, uz = localDirectionToLocal(node, cargo, 0, 1, 0)
        local hide = hidden(node)
        link(rigid, node)
        setTranslation(node, x, y, z)
        setDirection(node, dx, dy, dz, ux, uy, uz)
        if hide then setVisibility(node, false) end
    end
    local fit = {rigid = rigid, cargo = cargo, shapes = {}, bones = {}}
    -- parents before children, so each bone is placed from its parent's already fitted pose
    local function depth(node) local d = 0 while node ~= cargo and node ~= 0 do d = d + 1 node = getParent(node) end return d end
    table.sort(bones, function(l, r) return depth(l) < depth(r) end)
    for _, bone in ipairs(bones) do table.insert(fit.bones, {node = bone, p = {localToLocal(bone, cargo, 0, 0, 0)}}) end
    for _, skin in ipairs(skins) do table.insert(fit.shapes, fitShape(cargo, skin, skinMaterials[skin], false)) end
    for node, list in pairs(holders) do table.insert(fit.shapes, fitShape(cargo, node, list, true)) end
    return fit
end

-- Cargo frame: p -> (sx * x, dy + sy * y, sz * z), the fit the cargo root's scale gave before.
-- c[j] = shape axis j in the cargo frame; shape-space vector of a cargo vector v = (c[1].v, c[2].v, c[3].v).
function PalletDepotGoodsLook.applySkinFit(fit, sx, sy, sz, dy, centerY, radius)
    setScale(fit.rigid, sx, sy, sz)
    setTranslation(fit.rigid, 0, dy, 0)
    for _, bone in ipairs(fit.bones) do
        local p = bone.p
        setTranslation(bone.node, localToLocal(fit.cargo, getParent(bone.node), sx * p[1], dy + sy * p[2], sz * p[3]))
    end
    for _, e in ipairs(fit.shapes) do
        local c = e.c
        local t = e.inPlace and e.t or {localToLocal(e.shape, fit.cargo, 0, 0, 0)}
        local function back(v)
            return c[1][1] * v[1] + c[1][2] * v[2] + c[1][3] * v[3],
                c[2][1] * v[1] + c[2][2] * v[2] + c[2][3] * v[3],
                c[3][1] * v[1] + c[3][2] * v[2] + c[3][3] * v[3]
        end
        local ox, oy, oz = 0, 0, 0
        if e.inPlace then ox, oy, oz = back({(sx - 1) * t[1], dy + (sy - 1) * t[2], (sz - 1) * t[3]}) end
        setShaderParameter(e.shape, "cargoScale", sx, sy, sz, 0, false)
        setShaderParameter(e.shape, "cargoOffset", ox, oy, oz, 0, false)
        setShaderParameter(e.shape, "cargoRow0", c[1][1], c[2][1], c[3][1], 0, false)
        setShaderParameter(e.shape, "cargoRow1", c[1][2], c[2][2], c[3][2], 0, false)
        setShaderParameter(e.shape, "cargoRow2", c[1][3], c[2][3], c[3][3], 0, false)
        local bx, by, bz = back({-t[1], centerY - t[2], -t[3]})
        setShapeBoundingSphere(e.shape, bx, by, bz, radius)
    end
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
    if layersAreBones(objects, PalletDepotGoodsLook.getBoneNames(request.i3d)) then
        center = nil                                 -- one skinned mesh: draw it whole (below)
    end
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
            local dy = deck + (index - 1) * pitch - (center - sourcePitch / 2) * sy
            local fit = PalletDepotGoodsLook.prepareSkinFit(cargo, request.i3d)
            if fit ~= nil then
                PalletDepotGoodsLook.applySkinFit(fit, sx, sy, sz, dy, deck + (index - 0.5) * pitch, 1.5)
            else
                setScale(cargo, sx, sy, sz)
                setTranslation(cargo, 0, dy, 0)
            end
            table.insert(vehicle.palletDepotGoodsNodes, cargo)
        end
    else
        -- Indivisible cargo (churns, tanks, etc.) keeps its complete native assembly, fitted to the envelope.
        local cargo = clone(scene, false, false, false)
        visualsOnly(cargo)
        sourceObjects(xml, cargo)
        link(layers[1].node, cargo)
        local sy = targetHeight / math.max(0.01, request.height - deck)
        local whole = PalletDepotGoodsLook.fitPlankStack(cargo, request, targetHeight)
        if whole == nil then
            whole = {sx = sx, sy = sy, sz = sz, fit = PalletDepotGoodsLook.prepareSkinFit(cargo, request.i3d)}
        end
        whole.node = cargo
        vehicle.palletDepotGoodsWhole = whole
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
            if whole.shape ~= nil then
                setShaderParameter(whole.shape, "cargoScale", whole.sx, sy, whole.sz, 0, false)
                -- Shader displacement must also be included in the render/culling bounds.
                setShapeBoundingSphere(whole.shape, whole.centerX * whole.sx,
                    whole.baseY * sy, whole.centerZ * whole.sz,
                    whole.radius * math.max(whole.sx, sy, whole.sz))
                setTranslation(whole.node, -whole.centerX * whole.sx,
                    PalletDepotGoodsLook.DECK - whole.baseY * sy, -whole.centerZ * whole.sz)
            elseif whole.fit ~= nil then
                PalletDepotGoodsLook.applySkinFit(whole.fit, whole.sx, sy, whole.sz,
                    PalletDepotGoodsLook.DECK * (1 - sy), vehicle.size.height / 2, 1.5)
            else
                setScale(whole.node, whole.sx, sy, whole.sz)
                setTranslation(whole.node, 0, PalletDepotGoodsLook.DECK * (1 - sy), 0)
            end
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
