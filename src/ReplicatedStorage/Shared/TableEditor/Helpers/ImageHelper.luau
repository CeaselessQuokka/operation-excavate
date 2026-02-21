--!strict
--[[
	Helper functions for creating icons, images, and sprite sheet operations.
	Supports both the custom ICON_SHEET and Material Design Icons from ImageColor3ableSpriteSheets.
]]

--- Imports ---
local Constants = require(script.Parent.Parent.Constants)

--- Variables ---
local ICON_SHEET = Constants.ICON_SHEET

--[[
	Icon offsets within the ICON_SHEET sprite sheet.
	Each icon is 16x16 pixels.
]]
local ICON_OFFSETS = {
	-- Navigation & Actions
	Chevron = Vector2.new(16, 0), -- Arrow/chevron for expansion
	Close = Vector2.new(32, 0), -- X icon for close/delete
	Resize = Vector2.new(64, 0), -- Resize grip
	Focus = Vector2.new(112, 0), -- External link / focus
	Menu = Vector2.new(128, 0), -- Hamburger menu
	Freeze = Vector2.new(144, 0), -- Snowflake for freeze
	Desync = Vector2.new(0, 16), -- Warning/desync indicator
}

--[[
	Material Design Icons from sprite sheets.
	These are 96x96 icons that can be ImageColor3'd.
	Format: { Image = assetId, ImageRectOffset = Vector2, ImageRectSize = Vector2 }
]]
local SHEET_11 = "rbxassetid://8445470189"
local SHEET_12 = "rbxassetid://8445470392"
local SHEET_13 = "rbxassetid://8445470559"
local SHEET_14 = "rbxassetid://8445470826"
local SHEET_15 = "rbxassetid://8445470984"
local SHEET_16 = "rbxassetid://8445471173"
local SHEET_17 = "rbxassetid://8445471332"
local SHEET_18 = "rbxassetid://8445471499"
local SHEET_19 = "rbxassetid://8445471713"
local SHEET_20 = "rbxassetid://8445472085"

local MATERIAL_ICONS = {
	-- Lock (for frozen value state)
	Lock = {
		Image = SHEET_20,
		ImageRectOffset = Vector2.new(4, 104),
		ImageRectSize = Vector2.one * 96,
	},
	-- Lock open (for unfrozen value state)
	LockOpen = {
		Image = SHEET_20,
		ImageRectOffset = Vector2.new(104, 604),
		ImageRectSize = Vector2.one * 96,
	},
	-- Link/chain icon
	Link = {
		Image = SHEET_12,
		ImageRectOffset = Vector2.new(104, 404),
		ImageRectSize = Vector2.one * 96,
	},
	-- Play arrow (for live/unfrozen state)
	PlayArrow = {
		Image = SHEET_17,
		ImageRectOffset = Vector2.one * 604,
		ImageRectSize = Vector2.one * 96,
	},
	-- Pause (for frozen state)
	Pause = {
		Image = SHEET_17,
		ImageRectOffset = Vector2.new(904, 404),
		ImageRectSize = Vector2.one * 96,
	},
	-- Settings gear
	Settings = {
		Image = SHEET_17,
		ImageRectOffset = Vector2.new(604, 404),
		ImageRectSize = Vector2.one * 96,
	},
	-- Tune/sliders (alternative settings icon)
	Tune = {
		Image = SHEET_11,
		ImageRectOffset = Vector2.new(904, 304),
		ImageRectSize = Vector2.one * 96,
	},
	-- Expand less (chevron up)
	ExpandLess = {
		Image = SHEET_13,
		ImageRectOffset = Vector2.new(304, 604),
		ImageRectSize = Vector2.one * 96,
	},
	-- Expand more (chevron down)
	ExpandMore = {
		Image = SHEET_13,
		ImageRectOffset = Vector2.new(4, 704),
		ImageRectSize = Vector2.one * 96,
	},
	-- Close X
	Close = {
		Image = SHEET_15,
		ImageRectOffset = Vector2.one * 304,
		ImageRectSize = Vector2.one * 96,
	},
	-- Fullscreen expand
	Fullscreen = {
		Image = SHEET_14,
		ImageRectOffset = Vector2.new(404, 604),
		ImageRectSize = Vector2.one * 96,
	},
	-- Fullscreen exit/collapse
	FullscreenExit = {
		Image = SHEET_14,
		ImageRectOffset = Vector2.new(704, 604),
		ImageRectSize = Vector2.one * 96,
	},
	-- Remove/minus
	Remove = {
		Image = SHEET_18,
		ImageRectOffset = Vector2.new(104, 904),
		ImageRectSize = Vector2.one * 96,
	},
	-- More vertical dots
	MoreVert = {
		Image = SHEET_19,
		ImageRectOffset = Vector2.new(604, 404),
		ImageRectSize = Vector2.one * 96,
	},
	-- Search
	Search = {
		Image = SHEET_17,
		ImageRectOffset = Vector2.new(204, 104),
		ImageRectSize = Vector2.one * 96,
	},
	-- Filter list
	FilterList = {
		Image = SHEET_14,
		ImageRectOffset = Vector2.new(304, 804),
		ImageRectSize = Vector2.one * 96,
	},
	-- Bug report (for debug)
	BugReport = {
		Image = SHEET_16,
		ImageRectOffset = Vector2.new(804, 704),
		ImageRectSize = Vector2.one * 96,
	},
	-- Drag handle
	DragHandle = {
		Image = SHEET_13,
		ImageRectOffset = Vector2.new(4, 504),
		ImageRectSize = Vector2.one * 96,
	},
}

--- Functions ---

--[[
	Creates an ImageLabel configured to display an icon from the sprite sheet.
	
	@param iconOffset The Vector2 offset of the icon in the sprite sheet
	@param size The UDim2 size of the icon (default 16x16)
	@param color Optional Color3 to tint the icon
	@return The configured ImageLabel
]]
local function CreateIcon(iconOffset: Vector2, size: UDim2?, color: Color3?): ImageLabel
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = ICON_SHEET
	icon.ImageRectSize = Vector2.new(16, 16)
	icon.ImageRectOffset = iconOffset
	icon.Size = size or UDim2.fromOffset(16, 16)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ScaleType = Enum.ScaleType.Fit
	if color then
		icon.ImageColor3 = color
	end
	return icon
end

--[[
	Creates an ImageButton with an icon from the sprite sheet.
	Includes hover effect for transparency.
	
	@param name The name for the button instance
	@param iconOffset The Vector2 offset of the icon in the sprite sheet
	@param position The UDim2 position of the button
	@param color Optional Color3 to tint the icon
	@return The configured ImageButton
]]
local function CreateIconButton(name: string, iconOffset: Vector2, position: UDim2, color: Color3?): ImageButton
	local button = Instance.new("ImageButton")
	button.Name = name
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromOffset(24, 24)
	button.Position = position
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.AutoButtonColor = false

	local icon = CreateIcon(iconOffset, UDim2.fromOffset(14, 14), color)
	icon.Parent = button

	button.MouseEnter:Connect(function()
		icon.ImageTransparency = 0.3
	end)
	button.MouseLeave:Connect(function()
		icon.ImageTransparency = 0
	end)

	return button
end

--[[
	Sets the icon for an existing ImageLabel or ImageButton's Icon child.
	
	@param parent The parent instance containing the Icon child
	@param iconOffset The new Vector2 offset for the icon
	@param color Optional new Color3 to tint the icon
]]
local function SetIcon(parent: Instance, iconOffset: Vector2, color: Color3?)
	local icon = parent:FindFirstChild("Icon") :: ImageLabel?
	if icon then
		icon.ImageRectOffset = iconOffset
		if color then
			icon.ImageColor3 = color
		end
	end
end

--[[
	Creates an ImageLabel with a custom image (not from sprite sheet).
	
	@param image The rbxassetid string for the image
	@param size The UDim2 size of the image
	@param color Optional Color3 to tint the image
	@return The configured ImageLabel
]]
local function CreateImage(image: string, size: UDim2, color: Color3?): ImageLabel
	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Name = "Image"
	imageLabel.BackgroundTransparency = 1
	imageLabel.Image = image
	imageLabel.Size = size
	imageLabel.ScaleType = Enum.ScaleType.Fit
	if color then
		imageLabel.ImageColor3 = color
	end
	return imageLabel
end

--[[
	Creates an ImageLabel from a Material Design Icon definition.
	These icons are 96x96 in the sprite sheet and can be tinted with ImageColor3.
	
	@param iconName The name of the icon in MATERIAL_ICONS
	@param size The UDim2 size for the icon (default 16x16)
	@param color Optional Color3 to tint the icon (default white)
	@return The configured ImageLabel, or nil if icon not found
]]
local function CreateMaterialIcon(iconName: string, size: UDim2?, color: Color3?): ImageLabel?
	local iconDef = MATERIAL_ICONS[iconName]
	if not iconDef then
		warn(`[ImageHelper] Material icon not found: {iconName}`)
		return nil
	end

	local icon = Instance.new("ImageLabel")
	icon.Name = "MaterialIcon"
	icon.BackgroundTransparency = 1
	icon.Image = iconDef.Image
	icon.ImageRectOffset = iconDef.ImageRectOffset
	icon.ImageRectSize = iconDef.ImageRectSize
	icon.Size = size or UDim2.fromOffset(16, 16)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ImageColor3 = color or Color3.new(1, 1, 1)

	return icon
end

--[[
	Creates an ImageButton with a Material Design Icon.
	Includes hover effect for transparency.
	
	@param name The name for the button instance
	@param iconName The name of the icon in MATERIAL_ICONS
	@param size The UDim2 size for the button (default 24x24)
	@param color Optional Color3 to tint the icon
	@return The configured ImageButton, or nil if icon not found
]]
local function CreateMaterialIconButton(name: string, iconName: string, size: UDim2?, color: Color3?): ImageButton?
	local iconDef = MATERIAL_ICONS[iconName]
	if not iconDef then
		warn(`[ImageHelper] Material icon not found: {iconName}`)
		return nil
	end

	local buttonSize = size or UDim2.fromOffset(24, 24)
	local button = Instance.new("ImageButton")
	button.Name = name
	button.BackgroundTransparency = 1
	button.Size = buttonSize
	button.AutoButtonColor = false

	-- Icon is slightly smaller than button for padding effect
	local iconSize = UDim2.fromOffset(buttonSize.X.Offset - 6, buttonSize.Y.Offset - 6)
	local icon = CreateMaterialIcon(iconName, iconSize, color)
	if icon then
		icon.Parent = button

		button.MouseEnter:Connect(function()
			icon.ImageTransparency = 0.3
		end)
		button.MouseLeave:Connect(function()
			icon.ImageTransparency = 0
		end)
	end

	return button
end

--[[
	Sets a Material Design Icon on an existing button's MaterialIcon child.
	
	@param parent The parent instance containing the MaterialIcon child
	@param iconName The name of the new icon in MATERIAL_ICONS
	@param color Optional new Color3 to tint the icon
]]
local function SetMaterialIcon(parent: Instance, iconName: string, color: Color3?)
	local iconDef = MATERIAL_ICONS[iconName]
	if not iconDef then
		warn(`[ImageHelper] Material icon not found: {iconName}`)
		return
	end

	local icon = parent:FindFirstChild("MaterialIcon") :: ImageLabel?
	if icon then
		icon.Image = iconDef.Image
		icon.ImageRectOffset = iconDef.ImageRectOffset
		icon.ImageRectSize = iconDef.ImageRectSize
		if color then
			icon.ImageColor3 = color
		end
	end
end

--- Image Helper ---
local ImageHelper = {
	-- Constants
	ICON_SHEET = ICON_SHEET,
	ICON_OFFSETS = ICON_OFFSETS,
	MATERIAL_ICONS = MATERIAL_ICONS,

	-- Functions (legacy sprite sheet)
	CreateIcon = CreateIcon,
	CreateIconButton = CreateIconButton,
	SetIcon = SetIcon,
	CreateImage = CreateImage,

	-- Functions (Material Design Icons)
	CreateMaterialIcon = CreateMaterialIcon,
	CreateMaterialIconButton = CreateMaterialIconButton,
	SetMaterialIcon = SetMaterialIcon,
}

return table.freeze(ImageHelper)
