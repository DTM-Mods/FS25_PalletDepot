-- Production Storage Control compatibility: depot packages use our own layered models.
-- Only depot choices and their queued entries are changed; PSC's source is untouched.
-- Each queued entry carries capacity and palletDepotCapacity for the mass/save/sync hooks.

PalletDepotSpawnSizes = {}
PalletDepotSpawnSizes.TYPE_SPAWNER_PALLET = 6       -- PSC's package type "pallet from the production's spawner"

local function plainPalletFile(capacity)
    local file = PalletDepotPallets.FILES[capacity]
    return file ~= nil and PalletDepot.modDirectory .. file or nil
end

-- A depot size always uses our model; the queued fill type supplies its product.
local function palletFile(productionPoint, fillTypeIndex, capacity)
    return plainPalletFile(capacity)
end

local function packageFor(productionPoint, fillTypeIndex, capacity, fillLevel, unitShort)
    local filename = palletFile(productionPoint, fillTypeIndex, capacity)
    local size = StoreItemUtil.getSizeValues(filename, "vehicle", 0, {})
    local max = math.floor(fillLevel / capacity)
    if fillLevel - max * capacity >= 1 then
        max = max + 1                                -- the last pallet takes the rest, as PSC does
    end
    return {
        capacity = capacity,
        max = max,
        title = g_i18n:getText("typeDesc_pallet") .. " (" .. capacity .. " " .. (unitShort or "l") .. ")",
        modIcon = PalletDepot.modDirectory .. "icon_palletDepot_clear.dds",    -- the mod icon without its background
        width = size.width,
        height = size.height,
        length = size.length,
        type = PalletDepotSpawnSizes.TYPE_SPAWNER_PALLET,
        palletDepotOwn = true,
    }
end

-- the dialog's product list for a depot: only our sizes, every other pallet choice is removed
function PalletDepotSpawnSizes.addPackages(options, productionPoint)
    for _, option in ipairs(options or {}) do
        if option.openmenu == nil and option.fillTypeIndex ~= nil and option.fillTypeIndex > 0 and option.packages ~= nil then
            local packages = {}
            for _, capacity in ipairs({1000, 2500, 5000}) do
                table.insert(packages, packageFor(productionPoint, option.fillTypeIndex, capacity, option.fillLevel or 0, option.unitShort))
            end
            option.packages = packages
        end
    end
end

-- server: a depot's type 6 spawn uses our pallet of the picked size
function PalletDepotSpawnSizes.fixSpawn(productionPoint, fillTypeIndex, capacity, type)
    if type ~= PalletDepotSpawnSizes.TYPE_SPAWNER_PALLET or not PalletDepot.isDepot(productionPoint) then
        return
    end
    if PalletDepotPallets.FILES[capacity] == nil then
        return
    end
    local filename = palletFile(productionPoint, fillTypeIndex, capacity)
    local spawner = productionPoint.palletSpawner
    local item = spawner ~= nil and spawner.pendingItem ~= nil and spawner.pendingItem[fillTypeIndex] or nil
    if filename ~= nil and item ~= nil then
        item.filename = filename                     -- the queued spawns point at this same item
        item.size = PalletDepotPallets.getSizeFor(filename, capacity)
        item.capacity = capacity
        item.palletDepotCapacity = capacity
    end
end

function PalletDepotSpawnSizes.install()
    if PalletDepotSpawnSizes.installed then
        return
    end
    local psc = _G["FS25_ProductionStorageControl"]
    local dialog = psc ~= nil and psc.ProductionStorageDialog or nil
    if dialog == nil or dialog.show == nil or ProductionPoint.ReceiveSpawnEvent == nil then
        return                                       -- PSC not loaded: nothing to do
    end
    PalletDepotSpawnSizes.installed = true

    dialog.show = Utils.overwrittenFunction(dialog.show,
        function(farmList, superFunc, target, title, options, productionPoint)
            if PalletDepot.isDepot(productionPoint) then
                PalletDepotSpawnSizes.addPackages(options, productionPoint)
            end
            return superFunc(farmList, target, title, options, productionPoint)
        end)

    ProductionPoint.ReceiveSpawnEvent = Utils.appendedFunction(ProductionPoint.ReceiveSpawnEvent,
        function(productionPoint, ownerFarmId, fillTypeIndex, pendingLiters, width, height, length, capacity, type)
            PalletDepotSpawnSizes.fixSpawn(productionPoint, fillTypeIndex, capacity, type)
        end)
end

-- after every mod's scripts have run (PSC included)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, PalletDepotSpawnSizes.install)
