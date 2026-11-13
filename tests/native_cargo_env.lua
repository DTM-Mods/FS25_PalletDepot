-- Engine stand-ins for native I3D loading, graph cloning, mappings and materials.
-- Pallet/FillUnit/AnimatedVehicle behaviour is loaded from the real game's source by stack_test.lua.
ClassIds, RigidBodyType = {SHAPE = 1}, {NONE = 0}
Logging = {warning = function() end}
NATIVE_NODES, NATIVE_LOADS, NATIVE_RELEASES = {}, {}, {}
local nextNode, nextRequest = 1000000, 0
local function node(parent, shape, y)
    nextNode = nextNode + 1
    local id = nextNode
    NATIVE_NODES[id] = {parent = parent or 0, children = {}, shape = shape,
        translation = {0, y or 0, 0}, sphere = {0, 0.11, 0, 0.3}, material = 300,
        body = shape and 1 or 0, compound = shape, filter = 65540}
    if parent then table.insert(NATIVE_NODES[parent].children, id) end
    return id
end
function getHasClassId(n) return NATIVE_NODES[n].shape end
function getNumOfChildren(n) return #NATIVE_NODES[n].children end
function getChildAt(n, i) return NATIVE_NODES[n].children[i + 1] end
function getParent(n) return NATIVE_NODES[n].parent end
function getShapeBoundingSphere(n) return unpack(NATIVE_NODES[n].sphere) end
function getIsCompoundChild(n) return NATIVE_NODES[n].compound end
function setIsCompoundChild(n, v) NATIVE_NODES[n].compound = v end
function setRigidBodyType(n, v) NATIVE_NODES[n].body = v end
function setCollisionFilter(n, group) NATIVE_NODES[n].filter = group end
function setTranslation(n, x, y, z) NATIVE_NODES[n].translation = {x, y, z} end
function localToLocal(n, root, x, y, z)
    while n ~= root do
        local p = NATIVE_NODES[n]
        x, y, z = x + p.translation[1], y + p.translation[2], z + p.translation[3]
        n = p.parent
    end
    return x, y, z
end
function link(parent, child)
    NATIVE_NODES[child].parent = parent
    if NATIVE_NODES[parent] then table.insert(NATIVE_NODES[parent].children, child) end
end
function delete(n)
    if not NATIVE_NODES[n] then return end
    for _, child in ipairs(NATIVE_NODES[n].children) do delete(child) end
    NATIVE_NODES[n].deleted = true
end
function clone(root, underParent, callOnCreate, physics)
    assertEqual(physics, false, 'clones must not enter physics')
    local remap = {}
    local function copy(old, parent)
        local src = NATIVE_NODES[old]
        local out = node(parent, src.shape)
        remap[old] = out
        for key, value in pairs(src) do
            if key ~= 'children' and key ~= 'parent' then
                if type(value) == 'table' then
                    local t = {} for k, v in pairs(value) do t[k] = v end
                    NATIVE_NODES[out][key] = t
                else NATIVE_NODES[out][key] = value end
            end
        end
        for _, child in ipairs(src.children) do copy(child, out) end
        return out
    end
    local out = copy(root)
    for old, new in pairs(remap) do
        local skin = NATIVE_NODES[old].skin
        if skin then
            for i, bone in ipairs(skin) do
                assert(remap[bone], 'whole graph must contain all skin joints')
                NATIVE_NODES[new].skin[i] = remap[bone]
            end
        end
    end
    return out
end
Utils.getModNameAndBaseDirectory = function() return nil, '/products/' end
Utils.getFilename = function(filename, baseDirectory)
    if filename == nil then return nil end
    if filename:sub(1, 1) == '/' or filename:match('^%a:/') then return filename end
    if filename:sub(1, 6) == '$data/' then return '/game/data/' .. filename:sub(7) end
    return baseDirectory .. filename
end
NATIVE_RAW_FILENAME_BY_TYPE = {}
g_fillTypeManager.getFillTypeByIndex = function(_, index)
    return {palletFilename = '/products/product' .. index .. '.xml'}
end
I3DUtil = {loadI3DMapping = function(xml, _, components, mappings)
    local root = components[1].node
    local content = getChildAt(root, 1)
    for i, obj in ipairs(NATIVE_NODES[content].children) do
        mappings['box' .. i] = obj
        mappings['tension' .. i] = getChildAt(obj, 0)
    end
end}
local originalLoad = XMLFile.loadIfExists
XMLFile.loadIfExists = function(_, filename)
    local ft = tonumber(filename:match('/products/product(%d+)%.xml$'))
    if not ft then return originalLoad and originalLoad(nil, filename) end
    local count = ft == 7 and 0 or 12
    local xml = {}
    function xml:delete() end
    function xml:iterator(key)
        local values = {}
        if key == 'vehicle.pallet.content' and count > 0 then values = {'content'} end
        if key == 'content.object' then for i = 1, count do values[i] = 'object' .. i end end
        local i = 0
        return function() i = i + 1 if values[i] then return i, values[i] end end
    end
    function xml:getValue(key, default, components, mappings)
        if key == 'vehicle.base.filename' then
            return NATIVE_RAW_FILENAME_BY_TYPE[ft] or '/products/product' .. ft .. '.i3d'
        end
        if key == 'vehicle.base.size#width' then return 1.3 end
        if key == 'vehicle.base.size#length' then return 0.9 end
        if key == 'vehicle.base.size#height' then return 0.804 end
        local i = key:match('^object(%d+)#node$')
        if i then return mappings['box' .. i] end
        i = key:match('^object(%d+)#tensionBeltNode$')
        if i then return mappings['tension' .. i] end
        return default
    end
    return xml
end
function finishNativeLoad(id, failed)
    local load = NATIVE_LOADS[id]
    if failed then load.callback(load.target, 0, 'missing') return end
    local scene = node()
    local root = node(scene, true)
    node(root, true) -- the original dynamicMountTrigger
    local content = node(root)
    local ft = load.target.fillType
    if ft ~= 7 then
        local bones = {}
        for i = 1, 12 do
            local obj = node(content, i == 1, 0.144 + math.floor((i - 1) / 4) * 0.22)
            NATIVE_NODES[obj].material = 300 + ft
            node(obj, true) -- tension mesh has a per-crate sphere
            bones[i] = obj
        end
        NATIVE_NODES[bones[1]].skin = bones
    else node(content, true) end
    load.callback(load.target, scene)
end
g_i3DManager = {
    loadSharedI3DFileAsync = function(_, filename, callOnCreate, physics, callback, target)
        assert(filename:sub(1, 1) == '/' or filename:match('^%a:/'),
            'native loader received an unresolved model path: ' .. filename)
        assertEqual(callOnCreate, false, 'native visual load must not execute onCreate')
        assertEqual(physics, false, 'native visual load must not add physics')
        nextRequest = nextRequest + 1
        NATIVE_LOADS[nextRequest] = {filename = filename, callback = callback, target = target}
        if not NATIVE_DEFER_LOAD then finishNativeLoad(nextRequest) end
        return nextRequest
    end,
    releaseSharedI3DFile = function(_, id) NATIVE_RELEASES[id] = (NATIVE_RELEASES[id] or 0) + 1 end
}
