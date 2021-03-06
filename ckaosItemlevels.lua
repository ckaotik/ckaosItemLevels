local addonName, addon, _ = ...

local LibItemLocations = LibStub('LibItemLocations')

-- GLOBALS: _G, GameTooltip
-- GLOBALS: IsAddOnLoaded, GetItemInfo, GetContainerItemLink, GetInventoryItemLink, GetAverageItemLevel, GetVoidItemInfo
-- GLOBALS: hooksecurefunc, type, pairs, select, unpack, math, table

addon = CreateFrame('Frame')
addon:SetScript('OnEvent', function(self, event, ...)
	if self[event] then self[event](self, event, ...) end
end)

-- TODO this is a cutoff value to avoid low level item level clutter.
addon.minItemLevel = select(2, GetAverageItemLevel()) - 100

-- TODO: use different color scale
local buttons, colors = {}, { -- 0.55,0.55,0.55 -- gray
	{1 ,0, 0}, 			-- red 			-- worst item
	{1, 0.7, 0}, 		-- orange
	{1, 1, 0}, 			-- yellow
	{0, 1, 0}, 			-- green
	{0, 1, 1}, 			-- lightblue
	{0.2, 0.2, 1}, 		-- blue 		-- base color
	{0, 0.5, 1},		-- darkblue
	{0.7, 0, 1},		-- purple
	{1, 0, 1}, 			-- pink
	{0.9, 0.8, 0.5}, 	-- heirloom
	{1, 1, 1}, 			-- white 		-- best item
}

local baseColorIndex, stepSize = math.ceil(#colors/2), 8
local function GetItemLevelColor(itemLevel)
	local total, equipped = GetAverageItemLevel()
	local levelDiff = math.floor((itemLevel - equipped)/stepSize)
	local color     = colors[baseColorIndex + levelDiff]
		or (levelDiff < 0 and colors[1])
		or (levelDiff > 0 and colors[#colors])
	return unpack(color or colors[baseColorIndex])
end

local getItemLink = {
	[PaperDollItemSlotButton_OnEnter]  = function(self)
		return GetInventoryItemLink('player', self:GetID())
	end,
	[ContainerFrameItemButton_OnEnter] = function(self)
		return GetContainerItemLink(self:GetParent():GetID(), self:GetID())
	end,
	[BankFrameItemButton_OnEnter] = function(self)
		return GetInventoryItemLink('player', self:GetInventorySlot())
	end,
}

local function HideButtonLevel(self)
	local button = (self.icon or self.Icon) and self or self:GetParent()
	if button and button.itemLevel then
		button.itemLevel:SetText('')
	end
end

local function UpdateButtonLevel(self, texture)
	if addon.minItemLevel < 0 then
		addon.minItemLevel = select(2, GetAverageItemLevel()) - 100
	end

	local button = (self.icon or self.Icon) and self or self:GetParent()
	if not button then return end
	if not texture or texture == '' or button.noItemLevel then
		HideButtonLevel(button)
		return
	end

	if not button.itemLevel then
		local iLevel = button:CreateFontString(nil, 'OVERLAY', 'NumberFontNormalSmall')
		      iLevel:SetPoint('TOPLEFT', -2, 1)
		button.itemLevel = iLevel
	end
	button.itemLevel:SetText('')

	local itemLink = button.link or button.hyperLink or button.hyperlink or button.itemlink or button.itemLink
		or (button.item and type(button.item) == 'string' and button.item)
		or (button.hasItem and type(button.hasItem) == 'string' and button.hasItem)
	if not itemLink and button.GetItem then
		itemLink = button:GetItem()
	elseif not itemLink then
		local func = button.UpdateTooltip or button:GetScript('OnEnter')
		if func and getItemLink[func] then
			itemLink = getItemLink[func](button)
		elseif button.UpdateTooltip and not GameTooltip:IsShown() then
			-- tooltip scan as last resort
			button:UpdateTooltip()
			_, itemLink = GameTooltip:GetItem()
			GameTooltip:Hide()
		end
	end

	-- We tried really hard, but there's just no link :(
	if not itemLink then return end

	local inventoryType = C_Item.GetItemInventoryTypeByID(itemLink)
	if inventoryType == Enum.InventoryType.IndexBagType or inventoryType == Enum.InventoryType.IndexNonEquipType then
		return
	end

	local quality = C_Item.GetItemQualityByID(itemLink)
	if quality == Enum.ItemQuality.Artifact and (inventoryType == Enum.InventoryType.IndexWeaponoffhandType or inventoryType == Enum.InventoryType.IndexShieldType) then
		-- Artifact offhand shares main hand's item level. Don't display separately.
		return
	end

	local itemLevel = GetDetailedItemLevelInfo(itemLink)
	if not itemLevel or itemLevel <= addon.minItemLevel then return end
	button.itemLevel:SetText(itemLevel)
	button.itemLevel:SetTextColor(GetItemLevelColor(itemLevel))
end

local function AddButton(button)
	local icon = button and (button.icon or button.Icon)
	if not button or not icon then return end
	if button.SetTexture then hooksecurefunc(button, 'SetTexture', UpdateButtonLevel) end
	if icon.SetTexture   then hooksecurefunc(icon,   'SetTexture', UpdateButtonLevel) end
	hooksecurefunc(button, 'Hide', HideButtonLevel)
	hooksecurefunc(icon,   'Hide', HideButtonLevel)
	table.insert(buttons, button)
end

local function Update()
	for _, button in pairs(buttons) do
		UpdateButtonLevel(button, true)
	end
end
addon.PLAYER_AVG_ITEM_LEVEL_UPDATE = Update
addon.PLAYER_AVG_ITEM_LEVEL_READY = Update

-- --------------------------------------------------------
--  LoadWith
-- --------------------------------------------------------
local loadWith = {}
function addon:LoadWith(otherAddon, handler)
	if IsAddOnLoaded(otherAddon) then
		-- addon is available, directly run handler code
		return handler(self, nil, otherAddon)
	else
		if loadWith[otherAddon] then
			for _, callback in pairs(loadWith[otherAddon]) do
				if callback == handler then
					return
				end
			end
		end
		-- handler is not yet registered
		if not loadWith[otherAddon] then loadWith[otherAddon] = {} end
		tinsert(loadWith[otherAddon], handler)
		self:RegisterEvent('ADDON_LOADED')
	end
end
function addon:ADDON_LOADED(event, arg1)
	if loadWith[arg1] then
		for key, callback in pairs(loadWith[arg1]) do
			if callback(self, event, arg1) then
				-- handler succeeded, remove from task list
				loadWith[arg1][key] = nil
			end
		end
	end
	if not next(loadWith) then
		self:UnregisterEvent('ADDON_LOADED')
	end
end
addon:RegisterEvent('ADDON_LOADED')

-- --------------------------------------------------------

local function InitVoidStorage(self)
	AddButton(_G.VoidStorageStorageButton1)
	getItemLink[_G.VoidStorageItemButton_OnEnter] = function(self)
		if not self.hasItem then return end
		local itemID = GetVoidItemInfo(_G.VoidStorageFrame.page, self.slot)
		local itemLink = itemID and select(2, GetItemInfo(itemID))
		return itemLink or itemID
	end
	hooksecurefunc('VoidStorageFrame_Update', Update)
	return true
end

local function InitInspect()
	getItemLink[_G.InspectPaperDollItemSlotButton_OnEnter] = function(self)
		if not self.hasItem or not InspectFrame.unit then return end
		return GetInventoryItemLink(InspectFrame.unit, self:GetID())
	end
	local buttons = { InspectPaperDollItemsFrame:GetChildren() }
	for _, button in pairs(buttons) do
		button.UpdateTooltip = _G.InspectPaperDollItemSlotButton_OnEnter
		AddButton(button)
	end
end

local function Initialize(self)
	hooksecurefunc('SetItemButtonTexture', UpdateButtonLevel)
	hooksecurefunc('BankFrameItemButton_Update', function(self) UpdateButtonLevel(self, true) end)
	hooksecurefunc('EquipmentFlyout_DisplayButton', function(self, itemSlot)
		if type(self.location) == 'number' and self.location < EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION then
			_, _, self.itemLink = LibItemLocations:GetLocationItemInfo(self.location)
			UpdateButtonLevel(self, true)
		else
			HideButtonLevel(self)
		end
	end)

	hooksecurefunc('CreateFrame', function(frameType, name, parent, templates, id)
		if frameType:lower() == 'button' and templates and templates:lower():find('itembutton') then
			if not name then return end
			if parent and type(parent) == 'table' then
				name = name:gsub('$parent', parent:GetName() or '')
			end
			AddButton(_G[name])
		end
	end)

	self:LoadWith('Blizzard_VoidStorageUI', InitVoidStorage)
	self:LoadWith('Blizzard_InspectUI', InitInspect)

	self:RegisterEvent('PLAYER_AVG_ITEM_LEVEL_UPDATE')
	-- @todo Does this event still exist?
	-- self:RegisterEvent('PLAYER_AVG_ITEM_LEVEL_READY')

	return true
end
addon:LoadWith(addonName, Initialize)
