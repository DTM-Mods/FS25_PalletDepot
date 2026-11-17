-- Engine primitives for running the installed Universal Autoload packing code unchanged.
Pallet = {}
Wheels = {}
UniversalAutoload = {DELTA = 0.005, objectSpacing = 0, LOADING_TYPES = {},
    ALL = 'ALL', MATERIALS = {'ALL', 'CHEESE'}, CONTAINERS = {'ALL', 'EURO_PALLET'},
    debugPrint = function() end, isShippingContainer = function() return false end,
    updateActionEventText = function() end}
_G.FS25_UniversalAutoload = {UniversalAutoload = UniversalAutoload}
local nextNode = 50000
AUTOLOAD_NODES = {}
function createTransformGroup()
    nextNode = nextNode + 1
    AUTOLOAD_NODES[nextNode] = {translation = {0, 0, 0}, scale = {1, 1, 1}}
    return nextNode
end
local function engineNode(node)
    assert(type(node) == 'number', 'Engine expects a numeric node ID, got ' .. type(node))
    assert(AUTOLOAD_NODES[node], 'Unknown engine node ' .. tostring(node))
    return AUTOLOAD_NODES[node]
end
function entityExists(node) return type(node) == 'number' and AUTOLOAD_NODES[node] ~= nil end
function getScale(node) return table.unpack(engineNode(node).scale) end
function getTranslation(node) return table.unpack(engineNode(node).translation) end
function getWorldTranslation(node) return getTranslation(node) end
function localToWorld(node, x, y, z)
    local px, py, pz = getTranslation(node)
    return px + x, py + y, pz + z
end
function setTranslation(node, x, y, z) AUTOLOAD_NODES[node].translation = {x, y, z} end
function setRotation(node, x, y, z) AUTOLOAD_NODES[node].rotation = {x, y, z} end
function link(parent, child) AUTOLOAD_NODES[child].parent = parent end
function deepCopy(value)
    if type(value) ~= 'table' then return value end
    local copy = {} for key, item in pairs(value) do copy[key] = deepCopy(item) end return copy
end
