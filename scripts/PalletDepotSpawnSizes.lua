-- Pallet Depot: in a depot, Production Storage Control's spawn dialog offers every product's own pallet (its model
-- and textures, nothing copied: we point at its file) in 1,000 L and 5,000 L, and nothing else, whatever size the
-- depot's Settings page has. Only a product without a pallet of its own gets our plain pallet.
--
-- PSC (Braeven, FS25_ProductionStorageControl) is not changed: we wrap two of its functions from outside.
--  * ProductionStorageDialog.show: for a depot, replace every package PSC lists for a product with our two,
--    1,000 L and 5,000 L.
--  * ProductionPoint:ReceiveSpawnEvent (server): PSC takes a type 6 pallet's file from the spawner's single slot; for a
--    depot we point it at the product's own pallet file and mark the picked liters (palletDepotCapacity), which
--    PalletDepotPalletMass sets on the pallet when it spawns.
-- The pallets still spawn through the depot's spawner, so PalletDepotPalletMass caps them (weight only).
-- PSC loads after us (mods load alphabetically), so the wraps are installed when the mission has loaded.

PalletDepotSpawnSizes = {}
PalletDepotSpawnSizes.TYPE_SPAWNER_PALLET = 6       -- PSC's package type "pallet from the production's spawner"

local function plainPalletFile(capacity)
    local file = PalletDepotPallets.FILES[capacity]
    return file ~= nil and PalletDepot.modDirectory .. file or nil
end

-- the file to spawn for `capacity` liters of a product: its own pallet, else our plain one
local function palletFile(productionPoint, fillTypeIndex, capacity)
    return PalletDepotPallets.getProductPalletFile(productionPoint, fillTypeIndex) or plainPalletFile(capacity)
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

-- the dialog's product list for a depot: only our two sizes, every other pallet choice is removed
function PalletDepotSpawnSizes.addPackages(options, productionPoint)
    for _, option in ipairs(options or {}) do
        if option.openmenu == nil and option.fillTypeIndex ~= nil and option.fillTypeIndex > 0 and option.packages ~= nil then
            local packages = {}
            for _, capacity in ipairs({1000, 5000}) do
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
        item.size = StoreItemUtil.getSizeValues(filename, "vehicle", 0, {})
        item.capacity = capacity
        if PalletDepotPallets.getProductPalletFile(productionPoint, fillTypeIndex) ~= nil then
            item.palletDepotCapacity = capacity      -- the product's own pallet, holding the picked liters
        end
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
