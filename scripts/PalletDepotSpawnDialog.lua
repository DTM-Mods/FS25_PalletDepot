-- Logistics Hub: the Spawn goods window (opened from the productions window), our own.
--
-- Five lines: product in stock, pallet, partial pallet (full pallets only, or the last pallet takes the rest), farm
-- that gets the pallets, number of pallets. Up / down chooses a line, left / right or Enter / Backspace change it,
-- X / C take 10 pallets off / add 10, E all pallets, Space spawns, Esc cancels. The last spawn of each building is
-- chosen again next time (while the game runs). Warnings before spawning: the pallet limit, pallets still standing
-- at the pickup lanes. Left: a preview of the product and the pallet;
-- bottom: what you get.
-- Spawning itself is done by the server (scripts/PalletDepotSpawn.lua).

PalletDepotSpawnDialog = {}
local PalletDepotSpawnDialog_mt = Class(PalletDepotSpawnDialog, MessageDialog)

PalletDepotSpawnDialog.GUI_NAME = "PalletDepotSpawnDialog"
PalletDepotSpawnDialog.AXIS_REPEAT_MS = 180

local ROW = {PRODUCT = 1, PALLET = 2, PARTIAL = 3, FARM = 4, COUNT = 5}
local NUM_ROWS = 5
local NUM_SEGMENTS = 20         -- the number of pallets is drawn as one block per pallet up to this many

local COLOR = {
    full = {0.18, 0.55, 0.24, 1}, partial = {0.42, 0.86, 0.47, 1}, free = {0.25, 0.27, 0.26, 1},
}

PalletDepotSpawnDialog.lastFullOnly = false        -- the last choice, kept while the game runs
PalletDepotSpawnDialog.memory = {}                  -- productionPoint -> the last spawn {fillType, size, count, farmId}

local KEYS = {
    {action = "MENU_ACCEPT", handler = "onClickNext"},
    {action = "MENU_CANCEL", handler = "onClickPrevious"},
    {action = "MENU_EXTRA_1", handler = "onClickMinus10"},
    {action = "MENU_EXTRA_2", handler = "onClickPlus10"},
    {action = "MENU_ACTIVATE", handler = "onClickSpawn"},
    {action = "MENU_PAGE_NEXT", handler = "onClickAll"},
}

local function text(key)
    return g_i18n:getText(key)
end

local function liters(value)
    return g_i18n:formatNumber(math.floor(value), 0)
end

function PalletDepotSpawnDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or PalletDepotSpawnDialog_mt)
    self.products = {}
    self.farms = {}
    self.productIndex, self.palletIndex, self.farmIndex, self.count = 1, 1, 1, 1
    self.selected = ROW.PRODUCT
    self.fullOnly = PalletDepotSpawnDialog.lastFullOnly
    self.lastAxisTime = 0
    return self
end

-- productionPoint: the building; fillTypeIndex: product to preselect (optional); onDone(): called after spawning
function PalletDepotSpawnDialog.show(productionPoint, fillTypeIndex, onDone)
    local dialog = PalletDepotSpawnDialog.new()
    dialog.productionPoint = productionPoint
    dialog.onDone = onDone
    dialog.products = PalletDepotSpawn.getProducts(productionPoint)
    -- the product selected in the productions window, else the one spawned last here
    local memory = PalletDepotSpawnDialog.memory[productionPoint]
    fillTypeIndex = fillTypeIndex or (memory ~= nil and memory.fillType or nil)
    for i, product in ipairs(dialog.products) do
        if product.fillType == fillTypeIndex then
            dialog.productIndex = i
        end
    end

    local ownFarmId = g_currentMission:getFarmId()
    for _, farm in ipairs(g_farmManager:getFarms() or {}) do
        if farm.farmId ~= FarmManager.SPECTATOR_FARM_ID then
            table.insert(dialog.farms, farm)
        end
    end
    table.sort(dialog.farms, function(a, b)
        return a.farmId < b.farmId
    end)
    local farmId = memory ~= nil and memory.farmId or ownFarmId
    for i, farm in ipairs(dialog.farms) do
        if farm.farmId == farmId then
            dialog.farmIndex = i
        end
    end
    -- the last pallet and amount for the same product, else the building's pallet setting
    local product = dialog:getProduct()
    local same = memory ~= nil and product ~= nil and memory.fillType == product.fillType
    dialog.count = same and memory.count or 1
    dialog:choosePallet(same and memory.size or PalletDepotPallets.get(productionPoint))
    dialog:countLanePallets()

    g_gui:loadGui(PalletDepot.modDirectory .. "gui/PalletDepotSpawn.xml", PalletDepotSpawnDialog.GUI_NAME, dialog)
    g_gui:showDialog(PalletDepotSpawnDialog.GUI_NAME)
end

function PalletDepotSpawnDialog:onGuiSetupFinished()
    PalletDepotSpawnDialog:superClass().onGuiSetupFinished(self)
    self.rowList:setDataSource(self)
    self.rowList:setDelegate(self)
end

function PalletDepotSpawnDialog:onOpen()
    PalletDepotSpawnDialog:superClass().onOpen(self)
    local productionPoint = self.productionPoint
    self.titleText:setText(productionPoint.getName ~= nil and productionPoint:getName() or "")
    self.subtitleText:setText(text(#self.products > 0 and "pdo_spawnHint" or "pdo_spawnNothing"))
    self.titleIcon:setImageFilename(PalletDepot.modDirectory .. "icon_palletDepot_clear.dds")
    self:refresh()
end

function PalletDepotSpawnDialog:onClickOk()
    return false
end

function PalletDepotSpawnDialog:onClickBack()
    self:close()
end

-- --- the choice ------------------------------------------------------------------------------------------

function PalletDepotSpawnDialog:getProduct()
    return self.products[self.productIndex]
end

function PalletDepotSpawnDialog:getPallet()
    local product = self:getProduct()
    return product ~= nil and product.pallets[self.palletIndex] or nil
end

function PalletDepotSpawnDialog:getMaxCount()
    local product, pallet = self:getProduct(), self:getPallet()
    if product == nil or pallet == nil then
        return 0
    end
    return PalletDepotSpawn.getMaxPallets(product.liters, pallet.capacity, self.fullOnly)
end

-- litres the chosen pallets take out of stock
function PalletDepotSpawnDialog:getAmount()
    local product, pallet = self:getProduct(), self:getPallet()
    if product == nil or pallet == nil or self:getMaxCount() < 1 then
        return 0
    end
    return math.min(self.count * pallet.capacity, math.floor(product.liters))
end

-- after the product changed: the pallet of that size if the product has it, else its first pallet
function PalletDepotSpawnDialog:choosePallet(size)
    local product = self:getProduct()
    self.palletIndex = 1
    if product ~= nil then
        for i, pallet in ipairs(product.pallets) do
            if pallet.size == size then
                self.palletIndex = i
            end
        end
    end
    self:clampCount()
end

function PalletDepotSpawnDialog:clampCount()
    self.count = math.max(math.min(self.count, self:getMaxCount()), 1)
end

local function step(index, delta, count)
    if count < 1 then
        return 1
    end
    return (index - 1 + delta) % count + 1
end

-- delta: +1 / -1 for the selected line; on the number of pallets any amount
function PalletDepotSpawnDialog:change(delta)
    if #self.products == 0 then
        return
    end
    if self.selected == ROW.PRODUCT then
        local pallet = self:getPallet()
        self.productIndex = step(self.productIndex, delta, #self.products)
        self:choosePallet(pallet ~= nil and pallet.size or 0)
    elseif self.selected == ROW.PALLET then
        self.palletIndex = step(self.palletIndex, delta, #self:getProduct().pallets)
        self:clampCount()
    elseif self.selected == ROW.PARTIAL then
        self.fullOnly = not self.fullOnly
        PalletDepotSpawnDialog.lastFullOnly = self.fullOnly
        self:clampCount()
    elseif self.selected == ROW.FARM then
        self.farmIndex = step(self.farmIndex, delta, #self.farms)
    else
        self:changeCount(delta)
        return
    end
    self:refresh()
end

function PalletDepotSpawnDialog:changeCount(delta)
    local max = self:getMaxCount()
    if math.abs(delta) == 1 and max > 0 then
        self.count = step(self.count, delta, max)       -- +1 / -1 wrap around
    else
        self.count = math.max(math.min(self.count + delta, max), 1)
    end
    self:refresh()
end

-- --- the list --------------------------------------------------------------------------------------------

function PalletDepotSpawnDialog:getNumberOfItemsInSection(list, section)
    return #self.products > 0 and NUM_ROWS or 0
end

local function icon(name)
    return PalletDepot.modDirectory .. "textures/" .. name .. ".dds"
end

local function fillTypeIcon(fillTypeIndex)
    local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    return fillType ~= nil and fillType.hudOverlayFilename or nil
end

local function setImage(element, filename, color)
    element:setVisible(filename ~= nil)
    if filename ~= nil then
        element:setImageFilename(filename)
        element:setImageColor(nil, unpack(color or {1, 1, 1, 1}))
    end
end

-- What the pallet looks like: its shop picture (the product's own pallet), else nil and the product's icon, which the
-- window puts on an empty wooden pallet (textures/ui_palletBase.dds) so the picture shows what is on it. A blank
-- shop picture (store_empty, e.g. the Fed packs' pallets) counts as none.
function PalletDepotSpawnDialog:getPalletLook()
    local product, pallet = self:getProduct(), self:getPallet()
    local filename
    if product ~= nil and pallet ~= nil then
        if pallet.size == 0 then
            local entry = PalletDepotPallets.getGamePallets(self.productionPoint)[product.fillType]
            filename = entry ~= nil and entry.filename or nil
        else
            filename = PalletDepotPallets.getProductPalletFile(self.productionPoint, product.fillType)
        end
    end
    local item = filename ~= nil and g_storeManager ~= nil and g_storeManager:getItemByXMLFilename(filename) or nil
    local image = item ~= nil and item.imageFilename or nil
    if image ~= nil and image ~= "" and string.find(string.lower(image), "store_empty", 1, true) == nil then
        return image, nil
    end
    return nil, product ~= nil and fillTypeIcon(product.fillType) or nil
end

-- shows a pallet in picture / base / goods: the shop picture, or the product's icon on the empty pallet
function PalletDepotSpawnDialog:showPallet(picture, base, goods)
    local image, goodsIcon = self:getPalletLook()
    setImage(picture, image)
    setImage(base, image == nil and goodsIcon ~= nil and icon("ui_palletBase") or nil)
    setImage(goods, image == nil and goodsIcon or nil)
end

function PalletDepotSpawnDialog:getPalletName()
    local pallet = self:getPallet()
    if pallet == nil then
        return ""
    end
    return string.format(text(pallet.size > 0 and "pdo_spawnPalletOwn" or "pdo_spawnPalletGame"), liters(pallet.capacity))
end

-- the farm's colour and, in multiplayer, its icon (the game's farm icons, one per farm colour)
local function farmLook(farm)
    if farm == nil or Farm == nil then
        return nil, nil
    end
    local isMultiplayer = g_currentMission.missionDynamicInfo ~= nil and g_currentMission.missionDynamicInfo.isMultiplayer
    if not isMultiplayer then
        return Farm.COLOR_SINGLEPLAYER, nil
    end
    local color = Farm.COLORS ~= nil and Farm.COLORS[farm.color] or nil
    local slice = Farm.ICON_SLICE_IDS ~= nil and Farm.ICON_SLICE_IDS[farm.color] or nil
    return color, slice
end

function PalletDepotSpawnDialog:populateCellForItemInSection(list, section, index, row)
    local product, pallet = self:getProduct(), self:getPallet()
    local image, color, caption, value, detail = nil, nil, "", "", ""
    local farmSlice, valueColor, palletRow = nil, nil, false
    local showBar = false
    if index == ROW.PRODUCT then
        image = fillTypeIcon(product.fillType)
        caption = text("pdo_spawnProduct")
        value = product.title
        detail = string.format(text("pdo_spawnInStock"), liters(product.liters))
    elseif index == ROW.PALLET then
        palletRow = true
        caption = text("pdo_spawnPallet")
        value = self:getPalletName()
        detail = string.format(text("pdo_spawnPerPallet"), liters(pallet.capacity))
    elseif index == ROW.PARTIAL then
        local rest = math.floor(product.liters) % pallet.capacity
        image = icon(self.fullOnly and "ui_pallet" or "ui_partial")
        caption = text("pdo_spawnPartial")
        value = text(self.fullOnly and "pdo_spawnFullOnly" or "pdo_spawnWithRest")
        if rest >= 1 then
            detail = string.format(text(self.fullOnly and "pdo_spawnRestLeft" or "pdo_spawnRestLast"), liters(rest))
        end
    elseif index == ROW.FARM then
        local farm = self.farms[self.farmIndex]
        local farmColor
        farmColor, farmSlice = farmLook(farm)
        if farmSlice == nil then
            image = icon("ui_farm")
            color = farmColor
        end
        valueColor = farmColor
        caption = text("pdo_spawnFarm")
        value = farm ~= nil and farm.name or "?"
        detail = farm ~= nil and farm.farmId == g_currentMission:getFarmId() and text("pdo_spawnYourFarm") or ""
    else
        local max = self:getMaxCount()
        palletRow = true
        caption = text("pdo_spawnCount")
        if max < 1 then
            value = text("pdo_spawnNotEnough")
        else
            value = string.format(text("pdo_spawnCountValue"), self.count, max)
            detail = liters(self:getAmount()) .. " L"
        end
        showBar = max > NUM_SEGMENTS
        local bg, fill = row:getAttribute("barBg"), row:getAttribute("barFill")
        fill:setSize(bg.size[1] * (max > 0 and self.count / max or 0), nil)
        self:drawSegments(row, (max < 1 or showBar) and 0 or max)
    end
    if index ~= ROW.COUNT then
        self:drawSegments(row, 0)
    end

    local selected = index == self.selected
    if palletRow then
        self:showPallet(row:getAttribute("icon"), row:getAttribute("iconBase"), row:getAttribute("iconGoods"))
    else
        setImage(row:getAttribute("icon"), image, color ~= nil and {color[1], color[2], color[3], 1} or nil)
        setImage(row:getAttribute("iconBase"), nil)
        setImage(row:getAttribute("iconGoods"), nil)
    end
    row:getAttribute("stripe"):setVisible(selected)
    row:getAttribute("caption"):setText(caption)
    local farmIcon = row:getAttribute("farmIcon")
    farmIcon:setVisible(farmSlice ~= nil)
    if farmSlice ~= nil then
        farmIcon:setImageSlice(nil, farmSlice)
    end
    local valueElement = row:getAttribute("value")
    valueElement:setText(value)
    local c = valueColor or {0.92, 0.94, 0.92, 1}
    valueElement:setTextColor(c[1], c[2], c[3], 1)
    row:getAttribute("detail"):setText(detail)
    row:getAttribute("barBg"):setVisible(showBar)
    row:getAttribute("barFill"):setVisible(showBar)
end

-- --- warnings --------------------------------------------------------------------------------------------

-- pallets standing at the pickup lanes now (the spawner places new ones around them, or reports no space)
function PalletDepotSpawnDialog:countLanePallets()
    self.lanePallets = {}
    local spawner = self.productionPoint.palletSpawner
    if spawner == nil or overlapBox == nil or CollisionFlag == nil then
        return
    end
    local places, seen = {}, {}
    local function add(list)
        for _, place in ipairs(list or {}) do
            if not seen[place] then
                seen[place] = true
                table.insert(places, place)
            end
        end
    end
    add(spawner.spawnPlaces)
    for _, list in pairs(spawner.fillTypeToSpawnPlaces or {}) do
        add(list)
    end
    for _, place in ipairs(places) do
        if place.startX ~= nil and place.width ~= nil then
            local x = place.startX + place.width / 2 * place.dirX
            local y = place.startY + place.width / 2 * place.dirY
            local z = place.startZ + place.width / 2 * place.dirZ
            overlapBox(x, y, z, place.rotX, place.rotY, place.rotZ, place.width / 2, 1, 1, "onLaneObject", self,
                CollisionFlag.VEHICLE + CollisionFlag.DYNAMIC_OBJECT, true, true, false, true)
        end
    end
end

function PalletDepotSpawnDialog:onLaneObject(node)
    local object = g_currentMission.nodeToObject ~= nil and g_currentMission.nodeToObject[node] or nil
    if object ~= nil and object.isPallet then
        self.lanePallets[object] = true
    end
end

-- how many of `count` pallets the game's pallet limit still allows
local function palletsAllowed(count)
    local slots = g_currentMission.slotSystem
    if slots == nil or slots.getCanAddLimitedObjects == nil or SlotSystem == nil or SlotSystem.LIMITED_OBJECT_PALLET == nil then
        return count
    end
    for n = count, 1, -1 do
        if slots:getCanAddLimitedObjects(SlotSystem.LIMITED_OBJECT_PALLET, n) then
            return n
        end
    end
    return 0
end

function PalletDepotSpawnDialog:getWarning()
    local allowed = palletsAllowed(self.count)
    if allowed < self.count then
        return string.format(text("pdo_spawnWarnLimit"), allowed)
    end
    local standing = 0
    for _ in pairs(self.lanePallets or {}) do
        standing = standing + 1
    end
    if standing > 0 then
        return string.format(text("pdo_spawnWarnLanes"), standing)
    end
    return nil
end

function PalletDepotSpawnDialog:setSummary(main, info)
    local warning = main ~= nil and self:getProduct() ~= nil and self:getMaxCount() > 0 and self:getWarning() or nil
    self.summaryText:setVisible(warning == nil)
    self.summaryTextTop:setVisible(warning ~= nil)
    self.summaryWarning:setVisible(warning ~= nil)
    self.summaryText:setText(main or "")
    self.summaryTextTop:setText(main or "")
    self.summaryWarning:setText(warning or "")
    self.summaryInfo:setText(info or "")
end

-- the preview on the left and the line at the bottom
function PalletDepotSpawnDialog:updatePreview()
    local product, pallet, farm = self:getProduct(), self:getPallet(), self.farms[self.farmIndex]
    if product == nil or pallet == nil then
        setImage(self.heroProductIcon, nil)
        setImage(self.heroPalletImage, nil)
        setImage(self.heroPalletBase, nil)
        setImage(self.heroPalletGoods, nil)
        self.heroProductName:setText("")
        self.heroProductInfo:setText("")
        self.heroPalletName:setText("")
        self.heroStockBg:setVisible(false)
        self.heroStockFill:setVisible(false)
        self:setSummary(text("pdo_spawnNothing"), "")
        return
    end
    setImage(self.heroProductIcon, fillTypeIcon(product.fillType))
    self.heroProductName:setText(product.title)
    self.heroProductInfo:setText(string.format(text("pdo_spawnInStock"), liters(product.liters)))
    self:showPallet(self.heroPalletImage, self.heroPalletBase, self.heroPalletGoods)
    self:showPallet(self.summaryIcon, self.summaryBase, self.summaryGoods)
    self.heroPalletName:setText(self:getPalletName())

    local amount = self:getAmount()
    -- stock bar: the part that goes out
    self.heroStockBg:setVisible(true)
    self.heroStockFill:setVisible(amount > 0)
    self.heroStockFill:setSize(self.heroStockBg.size[1] * math.min(amount / math.max(product.liters, 1), 1), nil)

    if self:getMaxCount() < 1 then
        self:setSummary(text("pdo_spawnNotEnough"), string.format(text("pdo_spawnInStock"), liters(product.liters)))
        return
    end
    local rest = product.liters - amount
    local farmName = farm ~= nil and farm.name or "?"
    local summary
    if self.count == 1 then
        summary = string.format(text("pdo_spawnSummaryOne"), liters(amount), product.title, farmName)
    else
        summary = string.format(text("pdo_spawnSummary"), self.count, liters(amount), product.title, farmName)
    end
    self:setSummary(summary,
        rest >= 1 and string.format(text("pdo_spawnRest"), liters(rest)) or text("pdo_spawnAllOut"))
end

-- one block per pallet: chosen full pallets green, a chosen part-filled pallet light, the others grey
function PalletDepotSpawnDialog:drawSegments(row, max)
    local bg = row:getAttribute("barBg")
    local gap = bg.size[1] * 0.008
    local width = max > 0 and (bg.size[1] - gap * (max - 1)) / max or 0
    local product, pallet = self:getProduct(), self:getPallet()
    for i = 1, NUM_SEGMENTS do
        local segment = row:getAttribute("seg" .. i)
        if segment ~= nil then
            segment:setVisible(i <= max)
            if i <= max then
                segment:setPosition(bg.position[1] + (i - 1) * (width + gap), nil)
                local color, share = COLOR.free, 1
                if i <= self.count then
                    color = COLOR.full
                    -- the part-filled pallet: as long as it is full, lighter
                    if pallet ~= nil and product ~= nil and i * pallet.capacity > product.liters then
                        color = COLOR.partial
                        share = math.max((product.liters - (i - 1) * pallet.capacity) / pallet.capacity, 0.12)
                    end
                end
                segment:setSize(width * share, nil)
                segment:setImageColor(nil, unpack(color))
            end
        end
    end
end

function PalletDepotSpawnDialog:onListSelectionChanged(list, section, index)
    if index ~= self.selected then
        self.selected = index
        self.rowList:reloadData()
        self.rowList:setSelectedItem(1, self.selected, true)
    end
end

function PalletDepotSpawnDialog:refresh()
    self.rowList:reloadData()
    if #self.products > 0 then
        self.rowList:setSelectedItem(1, self.selected, true)
    end
    self:updatePreview()
    self:updateButtons()
end

function PalletDepotSpawnDialog:updateButtons()
    local canSpawn = #self.products > 0 and self:getMaxCount() > 0
    self.nextButton:setVisible(canSpawn)
    self.nextButton:setInputAction(InputAction.MENU_ACCEPT)
    self.previousButton:setVisible(canSpawn)
    self.previousButton:setInputAction(InputAction.MENU_CANCEL)
    self.minusButton:setVisible(canSpawn)
    self.minusButton:setInputAction(InputAction.MENU_EXTRA_1)
    self.plusButton:setVisible(canSpawn)
    self.plusButton:setInputAction(InputAction.MENU_EXTRA_2)
    self.allButton:setVisible(canSpawn)
    self.allButton:setInputAction(InputAction.MENU_PAGE_NEXT)
    self.spawnButton:setVisible(canSpawn)
    self.spawnButton:setInputAction(InputAction.MENU_ACTIVATE)
    local box = self.buttonBox
    if box ~= nil and box.updateLayoutCells ~= nil and box.applyCellPositions ~= nil then
        box:updateLayoutCells()
        box:applyCellPositions(0, 0)
    end
end

-- --- actions ---------------------------------------------------------------------------------------------

function PalletDepotSpawnDialog:onClickNext()
    self:change(1)
end

function PalletDepotSpawnDialog:onClickPrevious()
    self:change(-1)
end

function PalletDepotSpawnDialog:onClickMinus10()
    self:changeCount(-10)
end

function PalletDepotSpawnDialog:onClickPlus10()
    self:changeCount(10)
end

-- every pallet of the selected product
function PalletDepotSpawnDialog:onClickAll()
    local max = self:getMaxCount()
    if max > 0 then
        self.count = max
        self.selected = ROW.COUNT
        self:refresh()
    end
end

function PalletDepotSpawnDialog:onClickSpawn()
    local product, pallet, farm = self:getProduct(), self:getPallet(), self.farms[self.farmIndex]
    if product == nil or pallet == nil or farm == nil or self:getMaxCount() < 1 then
        return
    end
    PalletDepotSpawnDialog.memory[self.productionPoint] = {fillType = product.fillType, size = pallet.size,
        count = self.count, farmId = farm.farmId}
    PalletDepotSpawn.request(self.productionPoint, product.fillType, pallet.size, farm.farmId, self.count, self.fullOnly)
    local onDone = self.onDone
    self:close()
    if onDone ~= nil then
        onDone()
    end
end

function PalletDepotSpawnDialog:inputEvent(action, value, eventUsed)
    if not eventUsed and value ~= 0 then
        for _, key in ipairs(KEYS) do
            if action == InputAction[key.action] then
                if self[key.handler] ~= nil then
                    self[key.handler](self)
                end
                return true
            end
        end
        -- left / right (keys, stick, d-pad) changes the selected line; held down it repeats
        if InputAction.MENU_AXIS_LEFT_RIGHT ~= nil and action == InputAction.MENU_AXIS_LEFT_RIGHT and math.abs(value) > 0.5 then
            if g_time - self.lastAxisTime >= PalletDepotSpawnDialog.AXIS_REPEAT_MS then
                self.lastAxisTime = g_time
                self:change(value > 0 and 1 or -1)
            end
            return true
        end
    end
    return PalletDepotSpawnDialog:superClass().inputEvent(self, action, value, eventUsed)
end
