--!strict
--[[
	ColorPickerHelper - A comprehensive, modular color picker

	Features:
	- HSV color wheel with saturation/value square
	- RGB sliders (0-255)
	- HSV sliders (H: 0-360, S/V: 0-100)
	- HEX input (#RRGGBB or RRGGBB)
	- Alpha/transparency slider (optional)
	- Color preview (old vs new)
	- Preset colors / recent colors
	- Copy/paste hex values
	- Theme-aware (light/dark mode support)
	- Works in plugins and LocalScripts

	Usage:
		local ColorPickerHelper = require(path.to.ColorPickerHelper)
		
		-- Create a color picker
		local picker = ColorPickerHelper.new({
			Parent = someFrame,
			InitialColor = Color3.fromRGB(255, 0, 0),
			ShowAlpha = true,
			OnColorChanged = function(color: Color3, alpha: number)
				print("Color changed:", color, alpha)
			end,
			OnConfirm = function(color: Color3, alpha: number)
				print("Confirmed:", color, alpha)
			end,
			OnCancel = function()
				print("Cancelled")
			end,
		})
		
		-- Update color programmatically
		picker:SetColor(Color3.fromRGB(0, 255, 0))
		picker:SetAlpha(0.5)
		
		-- Get current color
		local color, alpha = picker:GetColor()
		
		-- Destroy when done
		picker:Destroy()
]]

--- Services ---
local UserInputService = game:GetService("UserInputService")

--- Types ---
export type ColorPickerOptions = {
	Parent: GuiObject?,
	InitialColor: Color3?,
	InitialAlpha: number?,
	ShowAlpha: boolean?,
	ShowPresets: boolean?,
	ShowHexInput: boolean?,
	ShowRGBSliders: boolean?,
	ShowHSVSliders: boolean?,
	Title: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Theme: "Light" | "Dark" | "Auto"?,
	OnColorChanged: ((color: Color3, alpha: number) -> ())?,
	OnConfirm: ((color: Color3, alpha: number) -> ())?,
	OnCancel: (() -> ())?,
}

export type ColorPicker = {
	-- Properties
	Options: ColorPickerOptions,

	-- Internal state (private)
	_ui: Frame,
	_theme: { [string]: Color3 },
	_currentColor: Color3,
	_originalColor: Color3,
	_currentAlpha: number,
	_originalAlpha: number,
	_currentHue: number,
	_currentSaturation: number,
	_currentValue: number,
	_connections: { RBXScriptConnection },

	-- UI element references (private)
	_svPicker: Frame?,
	_svCursor: Frame?,
	_hueSlider: Frame?,
	_hueCursor: Frame?,
	_alphaSlider: Frame?,
	_alphaCursor: Frame?,
	_alphaOverlay: Frame?,
	_alphaInput: TextBox?,
	_previewNew: Frame?,
	_previewOld: Frame?,
	_previewNewAlpha: Frame?,
	_hexInput: TextBox?,
	_rgbInputs: { R: TextBox?, G: TextBox?, B: TextBox? },
	_hsvInputs: { H: TextBox?, S: TextBox?, V: TextBox? },
	_rgbSliders: { R: Frame?, G: Frame?, B: Frame? },
	_hsvSliders: { H: Frame?, S: Frame?, V: Frame? },
	_lastColorChangeTime: number,

	-- Methods
	SetColor: (self: ColorPicker, color: Color3) -> (),
	SetAlpha: (self: ColorPicker, alpha: number) -> (),
	GetColor: (self: ColorPicker) -> (Color3, number),
	SetHex: (self: ColorPicker, hex: string) -> boolean,
	GetHex: (self: ColorPicker) -> string,
	SetRGB: (self: ColorPicker, r: number, g: number, b: number) -> (),
	GetRGB: (self: ColorPicker) -> (number, number, number),
	SetHSV: (self: ColorPicker, h: number, s: number, v: number) -> (),
	GetHSV: (self: ColorPicker) -> (number, number, number),
	Show: (self: ColorPicker) -> (),
	Hide: (self: ColorPicker) -> (),
	IsVisible: (self: ColorPicker) -> boolean,
	GetUI: (self: ColorPicker) -> Frame,
	SetOriginalColor: (self: ColorPicker, color: Color3, alpha: number?) -> (),
	Reset: (self: ColorPicker) -> (),
	Destroy: (self: ColorPicker) -> (),
}

--- Variables ---
local DEFAULT_SIZE = UDim2.fromOffset(320, 400)
local CORNER_RADIUS = UDim.new(0, 6)
local PADDING = 8
local SLIDER_HEIGHT = 20
local INPUT_HEIGHT = 24
local BUTTON_HEIGHT = 28
local COLOR_WHEEL_SIZE = 180
local HUE_BAR_WIDTH = 20
local PREVIEW_HEIGHT = 40
local COLOR_CHANGE_DEBOUNCE = 0.016 -- ~60fps, prevents excessive callback firing

-- Default preset colors (Material Design palette) with names
local PRESET_COLORS = {
	{ color = Color3.fromRGB(244, 67, 54), name = "Red" },
	{ color = Color3.fromRGB(233, 30, 99), name = "Pink" },
	{ color = Color3.fromRGB(156, 39, 176), name = "Purple" },
	{ color = Color3.fromRGB(103, 58, 183), name = "Deep Purple" },
	{ color = Color3.fromRGB(63, 81, 181), name = "Indigo" },
	{ color = Color3.fromRGB(33, 150, 243), name = "Blue" },
	{ color = Color3.fromRGB(3, 169, 244), name = "Light Blue" },
	{ color = Color3.fromRGB(0, 188, 212), name = "Cyan" },
	{ color = Color3.fromRGB(0, 150, 136), name = "Teal" },
	{ color = Color3.fromRGB(76, 175, 80), name = "Green" },
	{ color = Color3.fromRGB(139, 195, 74), name = "Light Green" },
	{ color = Color3.fromRGB(205, 220, 57), name = "Lime" },
	{ color = Color3.fromRGB(255, 235, 59), name = "Yellow" },
	{ color = Color3.fromRGB(255, 193, 7), name = "Amber" },
	{ color = Color3.fromRGB(255, 152, 0), name = "Orange" },
	{ color = Color3.fromRGB(255, 87, 34), name = "Deep Orange" },
	{ color = Color3.fromRGB(121, 85, 72), name = "Brown" },
	{ color = Color3.fromRGB(158, 158, 158), name = "Grey" },
	{ color = Color3.fromRGB(96, 125, 139), name = "Blue Grey" },
	{ color = Color3.fromRGB(0, 0, 0), name = "Black" },
	{ color = Color3.fromRGB(255, 255, 255), name = "White" },
}

local THEMES = {
	Dark = {
		Background = Color3.fromRGB(40, 40, 40),
		Surface = Color3.fromRGB(50, 50, 50),
		Border = Color3.fromRGB(70, 70, 70),
		Text = Color3.fromRGB(230, 230, 230),
		TextSecondary = Color3.fromRGB(160, 160, 160),
		InputBackground = Color3.fromRGB(35, 35, 35),
		ButtonBackground = Color3.fromRGB(60, 60, 60),
		ButtonHover = Color3.fromRGB(80, 80, 80),
		Accent = Color3.fromRGB(0, 122, 255),
	},
	Light = {
		Background = Color3.fromRGB(245, 245, 245),
		Surface = Color3.fromRGB(255, 255, 255),
		Border = Color3.fromRGB(200, 200, 200),
		Text = Color3.fromRGB(30, 30, 30),
		TextSecondary = Color3.fromRGB(100, 100, 100),
		InputBackground = Color3.fromRGB(240, 240, 240),
		ButtonBackground = Color3.fromRGB(230, 230, 230),
		ButtonHover = Color3.fromRGB(210, 210, 210),
		Accent = Color3.fromRGB(0, 122, 255),
	},
}

--- Color Picker Helper ---
local ColorPickerHelper = {}
ColorPickerHelper.__index = ColorPickerHelper

--- Functions ---

--[[
	Clamps a number between min and max
]]
local function clamp(value: number, min: number, max: number): number
	return math.max(min, math.min(max, value))
end

--[[
	Converts RGB (0-255) to Color3
]]
local function rgbToColor3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(clamp(r, 0, 255), clamp(g, 0, 255), clamp(b, 0, 255))
end

--[[
	Converts Color3 to RGB (0-255)
]]
local function color3ToRGB(color: Color3): (number, number, number)
	return math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255)
end

--[[
	Converts HSV (H: 0-360, S: 0-100, V: 0-100) to Color3
]]
local function hsvToColor3(h: number, s: number, v: number): Color3
	return Color3.fromHSV(clamp(h, 0, 360) / 360, clamp(s, 0, 100) / 100, clamp(v, 0, 100) / 100)
end

--[[
	Converts Color3 to HSV (H: 0-360, S: 0-100, V: 0-100)
	Note: When S or V is 0, hue is undefined. Caller should preserve previous hue.
]]
local function color3ToHSV(color: Color3): (number, number, number)
	local h, s, v = color:ToHSV()
	return math.round(h * 360), math.round(s * 100), math.round(v * 100)
end

--[[
	Converts Color3 to HSV, preserving the given hue when saturation or value is 0
	This prevents hue from jumping to 0 when selecting black/white/grey colors
]]
local function color3ToHSVPreserveHue(color: Color3, preserveHue: number): (number, number, number)
	local h, s, v = color:ToHSV()
	local hDegrees = math.round(h * 360)
	local sPercent = math.round(s * 100)
	local vPercent = math.round(v * 100)

	-- Preserve hue when saturation or value is 0 (hue is undefined in these cases)
	if sPercent == 0 or vPercent == 0 then
		hDegrees = preserveHue
	end

	return hDegrees, sPercent, vPercent
end

--[[
	Converts hex string to Color3
	Accepts: #RRGGBB, RRGGBB, #RGB, RGB
]]
local function hexToColor3(hex: string): Color3?
	hex = hex:gsub("#", ""):upper()

	-- Handle shorthand (#RGB -> #RRGGBB)
	if #hex == 3 then
		hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
	end

	if #hex ~= 6 then
		return nil
	end

	local r = tonumber(hex:sub(1, 2), 16)
	local g = tonumber(hex:sub(3, 4), 16)
	local b = tonumber(hex:sub(5, 6), 16)

	if not r or not g or not b then
		return nil
	end

	return Color3.fromRGB(r, g, b)
end

--[[
	Converts Color3 to hex string (#RRGGBB)
]]
local function color3ToHex(color: Color3): string
	local r, g, b = color3ToRGB(color)
	return string.format("#%02X%02X%02X", r, g, b)
end

--[[
	Detects if we're in a dark theme environment
]]
local function detectTheme(): "Light" | "Dark"
	-- Try to detect Studio theme
	local success, result = pcall(function(): "Light" | "Dark"
		local studioSettings = settings()
		local studio = studioSettings:GetService("Studio") :: any
		local theme = studio.Theme
		if theme.Name:lower():find("dark") then
			return "Dark"
		end
		return "Light"
	end)

	if success and result then
		return result :: "Light" | "Dark"
	end

	-- Default to dark for in-game
	return "Dark"
end

--[[
	Gets theme colors based on theme name
]]
local function getThemeColors(theme: "Light" | "Dark" | "Auto"): typeof(THEMES.Dark)
	if theme == "Auto" then
		theme = detectTheme()
	end
	return THEMES[theme] or THEMES.Dark
end

--[[
	Creates a frame with common styling (available for future use)
]]
local function _createStyledFrame(name: string, theme: typeof(THEMES.Dark)): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = theme.Surface
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = CORNER_RADIUS
	corner.Parent = frame

	return frame
end

--[[
	Creates a text label with common styling
]]
local function createStyledLabel(name: string, text: string, theme: typeof(THEMES.Dark)): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = text
	label.TextColor3 = theme.Text
	label.TextSize = 12
	label.Font = Enum.Font.SourceSans
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	return label
end

--[[
	Creates a text input with common styling
]]
local function createStyledInput(name: string, placeholder: string, theme: typeof(THEMES.Dark)): TextBox
	local input = Instance.new("TextBox")
	input.Name = name
	input.PlaceholderText = placeholder
	input.PlaceholderColor3 = theme.TextSecondary
	input.TextColor3 = theme.Text
	input.BackgroundColor3 = theme.InputBackground
	input.BorderSizePixel = 0
	input.TextSize = 12
	input.Font = Enum.Font.SourceSansSemibold
	input.ClearTextOnFocus = false
	input.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = input

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.Parent = input

	return input
end

--[[
	Creates a button with common styling
]]
local function createStyledButton(name: string, text: string, theme: typeof(THEMES.Dark)): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.TextColor3 = theme.Text
	button.BackgroundColor3 = theme.ButtonBackground
	button.BorderSizePixel = 0
	button.TextSize = 12
	button.Font = Enum.Font.SourceSansSemibold
	button.AutoButtonColor = false
	button.Size = UDim2.new(0, 80, 0, BUTTON_HEIGHT)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = button

	-- Hover effect
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = theme.ButtonHover
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = theme.ButtonBackground
	end)

	return button
end

-- Forward declarations (functions defined later but called by createMainContainer)
local createSVPicker: (self: ColorPicker, parent: GuiObject) -> Frame
local createColorPreview: (self: ColorPicker, parent: GuiObject) -> Frame
local createHexInput: (self: ColorPicker, parent: GuiObject) -> Frame
local createRGBSliders: (self: ColorPicker, parent: GuiObject) -> Frame
local createHSVSliders: (self: ColorPicker, parent: GuiObject) -> Frame
local createAlphaSlider: (self: ColorPicker, parent: GuiObject) -> Frame
local createPresetColors: (self: ColorPicker, parent: GuiObject) -> Frame
local createActionButtons: (self: ColorPicker, parent: GuiObject) -> Frame

-- Forward declarations for update functions (called from UI event handlers)
local updateAllUI: (self: ColorPicker) -> ()
local fireColorChanged: (self: ColorPicker) -> ()

--[[
	Creates the main container frame
]]
local function createMainContainer(self: ColorPicker): Frame
	local theme = self._theme
	local options = self.Options

	-- Main frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "ColorPicker"
	mainFrame.Size = options.Size or DEFAULT_SIZE
	mainFrame.Position = options.Position or UDim2.fromScale(0.5, 0.5)
	mainFrame.AnchorPoint = options.AnchorPoint or Vector2.new(0.5, 0.5)
	mainFrame.BackgroundColor3 = theme.Background
	mainFrame.BorderSizePixel = 0
	mainFrame.ClipsDescendants = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = CORNER_RADIUS
	corner.Parent = mainFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = theme.Border
	stroke.Thickness = 1
	stroke.Parent = mainFrame

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 28)
	titleBar.BackgroundColor3 = theme.Surface
	titleBar.BorderSizePixel = 0
	titleBar.Parent = mainFrame

	local titleCorner = Instance.new("UICorner")
	titleCorner.CornerRadius = CORNER_RADIUS
	titleCorner.Parent = titleBar

	-- Fix bottom corners of title bar
	local titleFix = Instance.new("Frame")
	titleFix.Name = "CornerFix"
	titleFix.Size = UDim2.new(1, 0, 0, 8)
	titleFix.Position = UDim2.new(0, 0, 1, -8)
	titleFix.BackgroundColor3 = theme.Surface
	titleFix.BorderSizePixel = 0
	titleFix.Parent = titleBar

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -60, 1, 0)
	titleLabel.Position = UDim2.new(0, PADDING, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = options.Title or "Color Picker"
	titleLabel.TextColor3 = theme.Text
	titleLabel.TextSize = 13
	titleLabel.Font = Enum.Font.SourceSansSemibold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = titleBar

	-- Make window draggable via title bar
	-- UIDragDetector must be on the frame we want to move (mainFrame)
	-- but we use a drag area (titleBar) to restrict where dragging can start
	local dragDetector = Instance.new("UIDragDetector")
	dragDetector.DragStyle = Enum.UIDragDetectorDragStyle.TranslatePlane
	dragDetector.ResponseStyle = Enum.UIDragDetectorResponseStyle.Scale
	dragDetector.Parent = mainFrame

	-- Create an invisible drag area over the title bar
	local dragArea = Instance.new("Frame")
	dragArea.Name = "DragArea"
	dragArea.Size = UDim2.new(1, -30, 1, 0) -- Leave space for close button
	dragArea.BackgroundTransparency = 1
	dragArea.Parent = titleBar

	-- Only allow dragging from the title bar area
	dragDetector.BoundingUI = dragArea

	-- Close button
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0, 24, 0, 24)
	closeButton.Position = UDim2.new(1, -26, 0, 2)
	closeButton.BackgroundTransparency = 1
	closeButton.Text = "✕"
	closeButton.TextColor3 = theme.TextSecondary
	closeButton.TextSize = 14
	closeButton.Font = Enum.Font.SourceSansBold
	closeButton.Parent = titleBar

	closeButton.MouseEnter:Connect(function()
		closeButton.TextColor3 = theme.Text
	end)
	closeButton.MouseLeave:Connect(function()
		closeButton.TextColor3 = theme.TextSecondary
	end)
	closeButton.Activated:Connect(function()
		if options.OnCancel then
			options.OnCancel()
		end
		self:Hide()
	end)

	-- Escape key to cancel
	table.insert(
		self._connections,
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape and mainFrame.Visible then
				-- Revert to original color
				self._currentColor = self._originalColor
				self._currentAlpha = self._originalAlpha
				local h, s, v = color3ToHSV(self._originalColor)
				self._currentHue = h
				self._currentSaturation = s
				self._currentValue = v

				if options.OnCancel then
					options.OnCancel()
				end
				self:Hide()
			end
		end)
	)

	-- Content container
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -PADDING * 2, 1, -28 - PADDING * 2)
	content.Position = UDim2.new(0, PADDING, 0, 28 + PADDING)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 4
	content.ScrollBarImageColor3 = theme.Border
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.Parent = mainFrame

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, PADDING)
	contentLayout.Parent = content

	-- Create all sections
	createSVPicker(self, content)
	createColorPreview(self, content)
	createHexInput(self, content)

	if options.ShowRGBSliders ~= false then
		createRGBSliders(self, content)
	end

	if options.ShowHSVSliders then
		createHSVSliders(self, content)
	end

	if options.ShowAlpha then
		createAlphaSlider(self, content)
	end

	if options.ShowPresets ~= false then
		createPresetColors(self, content)
	end

	createActionButtons(self, content)

	-- Parent the frame
	if options.Parent then
		mainFrame.Parent = options.Parent
	end

	return mainFrame
end

--[[
	Creates the saturation/value picker with hue bar
]]
createSVPicker = function(self: ColorPicker, parent: GuiObject): Frame
	local _theme = self._theme -- Stored for potential future theming

	-- Container for SV square + Hue bar
	local container = Instance.new("Frame")
	container.Name = "SVPickerContainer"
	container.Size = UDim2.new(1, 0, 0, COLOR_WHEEL_SIZE)
	container.BackgroundTransparency = 1
	container.LayoutOrder = 1
	container.Parent = parent

	-- Saturation/Value square
	local svSquare = Instance.new("Frame")
	svSquare.Name = "SVSquare"
	svSquare.Size = UDim2.new(1, -HUE_BAR_WIDTH - PADDING, 0, COLOR_WHEEL_SIZE)
	svSquare.Position = UDim2.new(0, 0, 0, 0)
	svSquare.BackgroundColor3 = Color3.fromHSV(self._currentHue / 360, 1, 1)
	svSquare.BorderSizePixel = 0
	svSquare.Parent = container

	local svCorner = Instance.new("UICorner")
	svCorner.CornerRadius = UDim.new(0, 4)
	svCorner.Parent = svSquare

	-- White gradient (saturation)
	local satGradient = Instance.new("UIGradient")
	satGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
	satGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	satGradient.Rotation = 0
	satGradient.Parent = svSquare

	-- Black gradient overlay (value) - using a separate frame
	local valueOverlay = Instance.new("Frame")
	valueOverlay.Name = "ValueOverlay"
	valueOverlay.Size = UDim2.new(1, 0, 1, 0)
	valueOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	valueOverlay.BorderSizePixel = 0
	valueOverlay.ZIndex = 2
	valueOverlay.Parent = svSquare

	local valueCorner = Instance.new("UICorner")
	valueCorner.CornerRadius = UDim.new(0, 4)
	valueCorner.Parent = valueOverlay

	local valueGradient = Instance.new("UIGradient")
	valueGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	valueGradient.Rotation = 90
	valueGradient.Parent = valueOverlay

	-- SV cursor
	local svCursor = Instance.new("Frame")
	svCursor.Name = "Cursor"
	svCursor.Size = UDim2.new(0, 16, 0, 16)
	svCursor.AnchorPoint = Vector2.new(0.5, 0.5)
	svCursor.BackgroundTransparency = 1
	svCursor.ZIndex = 3
	svCursor.Parent = svSquare

	local cursorOuter = Instance.new("Frame")
	cursorOuter.Size = UDim2.new(1, 0, 1, 0)
	cursorOuter.BackgroundTransparency = 1
	cursorOuter.Parent = svCursor

	local cursorOuterCorner = Instance.new("UICorner")
	cursorOuterCorner.CornerRadius = UDim.new(1, 0)
	cursorOuterCorner.Parent = cursorOuter

	local cursorOuterStroke = Instance.new("UIStroke")
	cursorOuterStroke.Color = Color3.new(1, 1, 1)
	cursorOuterStroke.Thickness = 2
	cursorOuterStroke.Parent = cursorOuter

	local cursorInner = Instance.new("Frame")
	cursorInner.Size = UDim2.new(1, -4, 1, -4)
	cursorInner.Position = UDim2.new(0, 2, 0, 2)
	cursorInner.BackgroundTransparency = 1
	cursorInner.Parent = svCursor

	local cursorInnerCorner = Instance.new("UICorner")
	cursorInnerCorner.CornerRadius = UDim.new(1, 0)
	cursorInnerCorner.Parent = cursorInner

	local cursorInnerStroke = Instance.new("UIStroke")
	cursorInnerStroke.Color = Color3.new(0, 0, 0)
	cursorInnerStroke.Thickness = 1
	cursorInnerStroke.Parent = cursorInner

	self._svPicker = svSquare
	self._svCursor = svCursor

	-- Hue bar
	local hueBar = Instance.new("Frame")
	hueBar.Name = "HueBar"
	hueBar.Size = UDim2.new(0, HUE_BAR_WIDTH, 0, COLOR_WHEEL_SIZE)
	hueBar.Position = UDim2.new(1, -HUE_BAR_WIDTH, 0, 0)
	hueBar.BackgroundColor3 = Color3.new(1, 1, 1)
	hueBar.BorderSizePixel = 0
	hueBar.Parent = container

	local hueCorner = Instance.new("UICorner")
	hueCorner.CornerRadius = UDim.new(0, 4)
	hueCorner.Parent = hueBar

	-- Hue gradient
	local hueGradient = Instance.new("UIGradient")
	hueGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
		ColorSequenceKeypoint.new(0.167, Color3.fromHSV(0.167, 1, 1)),
		ColorSequenceKeypoint.new(0.333, Color3.fromHSV(0.333, 1, 1)),
		ColorSequenceKeypoint.new(0.5, Color3.fromHSV(0.5, 1, 1)),
		ColorSequenceKeypoint.new(0.667, Color3.fromHSV(0.667, 1, 1)),
		ColorSequenceKeypoint.new(0.833, Color3.fromHSV(0.833, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1)),
	})
	hueGradient.Rotation = 90
	hueGradient.Parent = hueBar

	-- Hue cursor
	local hueCursor = Instance.new("Frame")
	hueCursor.Name = "Cursor"
	hueCursor.Size = UDim2.new(1, 4, 0, 8)
	hueCursor.AnchorPoint = Vector2.new(0.5, 0.5)
	hueCursor.Position = UDim2.new(0.5, 0, 0, 0)
	hueCursor.BackgroundTransparency = 1
	hueCursor.ZIndex = 2
	hueCursor.Parent = hueBar

	local hueCursorCorner = Instance.new("UICorner")
	hueCursorCorner.CornerRadius = UDim.new(0, 2)
	hueCursorCorner.Parent = hueCursor

	local hueCursorStroke = Instance.new("UIStroke")
	hueCursorStroke.Color = Color3.new(1, 1, 1)
	hueCursorStroke.Thickness = 2
	hueCursorStroke.Parent = hueCursor

	self._hueSlider = hueBar
	self._hueCursor = hueCursor

	-- Input handling for SV picker
	local isDraggingSV = false

	local function updateSVFromPosition(inputPos: Vector3)
		local absPos = svSquare.AbsolutePosition
		local absSize = svSquare.AbsoluteSize

		local relX = clamp((inputPos.X - absPos.X) / absSize.X, 0, 1)
		local relY = clamp((inputPos.Y - absPos.Y) / absSize.Y, 0, 1)

		self._currentSaturation = relX * 100
		self._currentValue = (1 - relY) * 100
		self._currentColor = hsvToColor3(self._currentHue, self._currentSaturation, self._currentValue)

		updateAllUI(self)
		fireColorChanged(self)
	end

	svSquare.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			isDraggingSV = true
			updateSVFromPosition(input.Position)
		end
	end)

	valueOverlay.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			isDraggingSV = true
			updateSVFromPosition(input.Position)
		end
	end)

	table.insert(
		self._connections,
		UserInputService.InputChanged:Connect(function(input)
			if
				isDraggingSV
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				updateSVFromPosition(input.Position)
			end
		end)
	)

	table.insert(
		self._connections,
		UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				isDraggingSV = false
			end
		end)
	)

	-- Input handling for Hue bar
	local isDraggingHue = false

	local function updateHueFromPosition(inputPos: Vector3)
		local absPos = hueBar.AbsolutePosition
		local absSize = hueBar.AbsoluteSize

		local relY = clamp((inputPos.Y - absPos.Y) / absSize.Y, 0, 1)

		self._currentHue = relY * 360
		self._currentColor = hsvToColor3(self._currentHue, self._currentSaturation, self._currentValue)

		updateAllUI(self)
		fireColorChanged(self)
	end

	hueBar.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			isDraggingHue = true
			updateHueFromPosition(input.Position)
		end
	end)

	table.insert(
		self._connections,
		UserInputService.InputChanged:Connect(function(input)
			if
				isDraggingHue
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				updateHueFromPosition(input.Position)
			end
		end)
	)

	table.insert(
		self._connections,
		UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				isDraggingHue = false
			end
		end)
	)

	return container
end

--[[
	Creates the hue slider bar (standalone - used when not in SV picker)
	Prefixed with _ as currently integrated into createSVPicker
]]
local function _createHueSlider(_self: ColorPicker, _parent: GuiObject): Frame
	-- Hue is already integrated into createSVPicker
	-- This is a placeholder for potential standalone use
	return Instance.new("Frame")
end

--[[
	Creates the alpha/transparency slider
]]
createAlphaSlider = function(self: ColorPicker, parent: GuiObject): Frame
	local theme = self._theme

	local container = Instance.new("Frame")
	container.Name = "AlphaSliderContainer"
	container.Size = UDim2.new(1, 0, 0, SLIDER_HEIGHT + 16)
	container.BackgroundTransparency = 1
	container.LayoutOrder = 5
	container.Parent = parent

	local label = createStyledLabel("Label", "Alpha", theme)
	label.Size = UDim2.new(0, 50, 0, 16)
	label.Parent = container

	-- Alpha slider with checkerboard background
	local sliderBg = Instance.new("Frame")
	sliderBg.Name = "SliderBackground"
	sliderBg.Size = UDim2.new(1, -60, 0, SLIDER_HEIGHT)
	sliderBg.Position = UDim2.new(0, 0, 0, 16)
	sliderBg.BackgroundColor3 = Color3.new(1, 1, 1)
	sliderBg.BorderSizePixel = 0
	sliderBg.ClipsDescendants = true
	sliderBg.Parent = container

	local sliderCorner = Instance.new("UICorner")
	sliderCorner.CornerRadius = UDim.new(0, 4)
	sliderCorner.Parent = sliderBg

	-- Checkerboard pattern for transparency preview
	local checkerboard = Instance.new("Frame")
	checkerboard.Name = "Checkerboard"
	checkerboard.Size = UDim2.new(1, 0, 1, 0)
	checkerboard.BackgroundColor3 = Color3.new(0.8, 0.8, 0.8)
	checkerboard.BorderSizePixel = 0
	checkerboard.Parent = sliderBg

	-- Create checkerboard pattern using UIGradient
	local checkerGradient = Instance.new("UIGradient")
	checkerGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.5, Color3.new(0.7, 0.7, 0.7)),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
	checkerGradient.Parent = checkerboard

	-- Alpha color overlay
	local alphaOverlay = Instance.new("Frame")
	alphaOverlay.Name = "AlphaOverlay"
	alphaOverlay.Size = UDim2.new(1, 0, 1, 0)
	alphaOverlay.BackgroundColor3 = self._currentColor
	alphaOverlay.BorderSizePixel = 0
	alphaOverlay.ZIndex = 2
	alphaOverlay.Parent = sliderBg

	local alphaGradient = Instance.new("UIGradient")
	alphaGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	alphaGradient.Parent = alphaOverlay

	-- Alpha cursor
	local alphaCursor = Instance.new("Frame")
	alphaCursor.Name = "Cursor"
	alphaCursor.Size = UDim2.new(0, 8, 1, 4)
	alphaCursor.AnchorPoint = Vector2.new(0.5, 0.5)
	alphaCursor.Position = UDim2.new(self._currentAlpha, 0, 0.5, 0)
	alphaCursor.BackgroundTransparency = 1
	alphaCursor.ZIndex = 3
	alphaCursor.Parent = sliderBg

	local alphaCursorCorner = Instance.new("UICorner")
	alphaCursorCorner.CornerRadius = UDim.new(0, 2)
	alphaCursorCorner.Parent = alphaCursor

	local alphaCursorStroke = Instance.new("UIStroke")
	alphaCursorStroke.Color = Color3.new(1, 1, 1)
	alphaCursorStroke.Thickness = 2
	alphaCursorStroke.Parent = alphaCursor

	-- Alpha value input
	local alphaInput = createStyledInput("AlphaInput", "100", theme)
	alphaInput.Size = UDim2.new(0, 50, 0, SLIDER_HEIGHT)
	alphaInput.Position = UDim2.new(1, -50, 0, 16)
	alphaInput.Text = tostring(math.round(self._currentAlpha * 100))
	alphaInput.Parent = container

	self._alphaSlider = sliderBg
	self._alphaCursor = alphaCursor
	self._alphaOverlay = alphaOverlay
	self._alphaInput = alphaInput

	-- Input handling
	local isDragging = false

	local function updateAlphaFromPosition(inputPos: Vector3)
		local absPos = sliderBg.AbsolutePosition
		local absSize = sliderBg.AbsoluteSize

		local relX = clamp((inputPos.X - absPos.X) / absSize.X, 0, 1)
		self._currentAlpha = relX

		updateAllUI(self)
		fireColorChanged(self)
	end

	sliderBg.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			isDragging = true
			updateAlphaFromPosition(input.Position)
		end
	end)

	table.insert(
		self._connections,
		UserInputService.InputChanged:Connect(function(input)
			if
				isDragging
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				updateAlphaFromPosition(input.Position)
			end
		end)
	)

	table.insert(
		self._connections,
		UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				isDragging = false
			end
		end)
	)

	alphaInput.FocusLost:Connect(function()
		local value = tonumber(alphaInput.Text)
		if value then
			self._currentAlpha = clamp(value / 100, 0, 1)
			updateAllUI(self)
			fireColorChanged(self)
		else
			alphaInput.Text = tostring(math.round(self._currentAlpha * 100))
		end
	end)

	return container
end

--[[
	Creates the color preview section (old vs new)
]]
createColorPreview = function(self: ColorPicker, parent: GuiObject): Frame
	local theme = self._theme

	local container = Instance.new("Frame")
	container.Name = "ColorPreview"
	container.Size = UDim2.new(1, 0, 0, PREVIEW_HEIGHT)
	container.BackgroundTransparency = 1
	container.LayoutOrder = 2
	container.Parent = parent

	-- Container for the two preview squares
	local previewFrame = Instance.new("Frame")
	previewFrame.Name = "PreviewFrame"
	previewFrame.Size = UDim2.new(1, 0, 1, 0)
	previewFrame.BackgroundColor3 = theme.Surface
	previewFrame.BorderSizePixel = 0
	previewFrame.ClipsDescendants = true
	previewFrame.Parent = container

	local previewCorner = Instance.new("UICorner")
	previewCorner.CornerRadius = UDim.new(0, 4)
	previewCorner.Parent = previewFrame

	local previewStroke = Instance.new("UIStroke")
	previewStroke.Color = theme.Border
	previewStroke.Thickness = 1
	previewStroke.Parent = previewFrame

	-- Old color (left half) - with checkerboard for alpha visibility
	local oldColorBg = Instance.new("Frame")
	oldColorBg.Name = "OldColorBg"
	oldColorBg.Size = UDim2.new(0.5, 0, 1, 0)
	oldColorBg.Position = UDim2.new(0, 0, 0, 0)
	oldColorBg.BackgroundColor3 = Color3.new(0.8, 0.8, 0.8)
	oldColorBg.BorderSizePixel = 0
	oldColorBg.ClipsDescendants = true
	oldColorBg.Parent = previewFrame

	-- Checkerboard pattern for old color
	local oldCheckerGradient = Instance.new("UIGradient")
	oldCheckerGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.25, Color3.new(0.7, 0.7, 0.7)),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.75, Color3.new(0.7, 0.7, 0.7)),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
	oldCheckerGradient.Parent = oldColorBg

	local oldColor = Instance.new("Frame")
	oldColor.Name = "OldColor"
	oldColor.Size = UDim2.new(1, 0, 1, 0)
	oldColor.BackgroundColor3 = self._originalColor
	oldColor.BackgroundTransparency = 1 - self._originalAlpha
	oldColor.BorderSizePixel = 0
	oldColor.Parent = oldColorBg

	local oldLabel = Instance.new("TextLabel")
	oldLabel.Name = "Label"
	oldLabel.Size = UDim2.new(1, 0, 0, 14)
	oldLabel.Position = UDim2.new(0, 0, 1, -16)
	oldLabel.BackgroundTransparency = 1
	oldLabel.Text = "Original"
	oldLabel.TextColor3 = Color3.new(1, 1, 1)
	oldLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	oldLabel.TextStrokeTransparency = 0.5
	oldLabel.TextSize = 10
	oldLabel.Font = Enum.Font.SourceSans
	oldLabel.ZIndex = 2
	oldLabel.Parent = oldColorBg

	-- New color (right half) - with checkerboard for alpha visibility
	local newColorBg = Instance.new("Frame")
	newColorBg.Name = "NewColorBg"
	newColorBg.Size = UDim2.new(0.5, 0, 1, 0)
	newColorBg.Position = UDim2.new(0.5, 0, 0, 0)
	newColorBg.BackgroundColor3 = Color3.new(0.8, 0.8, 0.8)
	newColorBg.BorderSizePixel = 0
	newColorBg.ClipsDescendants = true
	newColorBg.Parent = previewFrame

	-- Checkerboard pattern for new color
	local newCheckerGradient = Instance.new("UIGradient")
	newCheckerGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.25, Color3.new(0.7, 0.7, 0.7)),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.75, Color3.new(0.7, 0.7, 0.7)),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
	newCheckerGradient.Parent = newColorBg

	local newColor = Instance.new("Frame")
	newColor.Name = "NewColor"
	newColor.Size = UDim2.new(1, 0, 1, 0)
	newColor.BackgroundColor3 = self._currentColor
	newColor.BackgroundTransparency = 1 - self._currentAlpha
	newColor.BorderSizePixel = 0
	newColor.Parent = newColorBg

	local newLabel = Instance.new("TextLabel")
	newLabel.Name = "Label"
	newLabel.Size = UDim2.new(1, 0, 0, 14)
	newLabel.Position = UDim2.new(0, 0, 1, -16)
	newLabel.BackgroundTransparency = 1
	newLabel.Text = "New"
	newLabel.TextColor3 = Color3.new(1, 1, 1)
	newLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	newLabel.TextStrokeTransparency = 0.5
	newLabel.TextSize = 10
	newLabel.Font = Enum.Font.SourceSans
	newLabel.ZIndex = 2
	newLabel.Parent = newColorBg

	-- Click on old color to revert
	local oldButton = Instance.new("TextButton")
	oldButton.Size = UDim2.new(1, 0, 1, 0)
	oldButton.BackgroundTransparency = 1
	oldButton.Text = ""
	oldButton.ZIndex = 3
	oldButton.Parent = oldColorBg

	oldButton.Activated:Connect(function()
		self:SetColor(self._originalColor)
		self._currentAlpha = self._originalAlpha
		updateAllUI(self)
		fireColorChanged(self)
	end)

	self._previewOld = oldColor
	self._previewNew = newColor

	return container
end

--[[
	Creates the hex input field
]]
createHexInput = function(self: ColorPicker, parent: GuiObject): Frame
	local theme = self._theme

	local container = Instance.new("Frame")
	container.Name = "HexInputContainer"
	container.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT + 16)
	container.BackgroundTransparency = 1
	container.LayoutOrder = 3
	container.Parent = parent

	local label = createStyledLabel("Label", "Hex", theme)
	label.Size = UDim2.new(0, 30, 0, 16)
	label.Parent = container

	local hexInput = createStyledInput("HexInput", "#FF0000", theme)
	hexInput.Size = UDim2.new(1, -80, 0, INPUT_HEIGHT)
	hexInput.Position = UDim2.new(0, 35, 0, 16)
	hexInput.Text = color3ToHex(self._currentColor)
	hexInput.Parent = container

	-- Copy button
	local copyButton = createStyledButton("CopyButton", "📋", theme)
	copyButton.Size = UDim2.new(0, INPUT_HEIGHT, 0, INPUT_HEIGHT)
	copyButton.Position = UDim2.new(1, -INPUT_HEIGHT, 0, 16)
	copyButton.TextSize = 14
	copyButton.Parent = container

	self._hexInput = hexInput

	-- Store original background for reset
	local originalBg = hexInput.BackgroundColor3

	local function validateAndApplyHex()
		local color = hexToColor3(hexInput.Text)
		if color then
			hexInput.BackgroundColor3 = originalBg
			self:SetColor(color)
			return true
		else
			-- Flash red briefly to indicate invalid input
			hexInput.BackgroundColor3 = Color3.fromRGB(100, 40, 40)
			task.delay(0.3, function()
				if hexInput and hexInput.Parent then
					hexInput.BackgroundColor3 = originalBg
					hexInput.Text = color3ToHex(self._currentColor)
				end
			end)
			return false
		end
	end

	hexInput.FocusLost:Connect(function(_enterPressed)
		validateAndApplyHex()
	end)

	copyButton.Activated:Connect(function()
		-- Focus the hex input and select all text so user can Ctrl+C
		hexInput.Text = color3ToHex(self._currentColor)
		hexInput:CaptureFocus()

		-- Select all text (cursor at end, selection from start)
		hexInput.CursorPosition = #hexInput.Text + 1
		hexInput.SelectionStart = 1

		-- Visual feedback on button
		local originalText = copyButton.Text
		copyButton.Text = "..."
		task.delay(0.5, function()
			if copyButton and copyButton.Parent then
				copyButton.Text = originalText
			end
		end)
	end)

	return container
end

--[[
	Creates RGB sliders section
]]
createRGBSliders = function(self: ColorPicker, parent: GuiObject): Frame
	local theme = self._theme

	local container = Instance.new("Frame")
	container.Name = "RGBSlidersContainer"
	container.Size = UDim2.new(1, 0, 0, (SLIDER_HEIGHT + 8) * 3 + 16)
	container.BackgroundTransparency = 1
	container.LayoutOrder = 4
	container.Parent = parent

	local label = createStyledLabel("Label", "RGB", theme)
	label.Size = UDim2.new(1, 0, 0, 16)
	label.Font = Enum.Font.SourceSansSemibold
	label.Parent = container

	local r, g, b = color3ToRGB(self._currentColor)
	local sliderData = {
		{ name = "R", color = Color3.fromRGB(255, 100, 100), value = r },
		{ name = "G", color = Color3.fromRGB(100, 255, 100), value = g },
		{ name = "B", color = Color3.fromRGB(100, 100, 255), value = b },
	}

	self._rgbSliders = {}
	self._rgbInputs = {}

	for i, data in sliderData do
		local yOffset = 16 + (i - 1) * (SLIDER_HEIGHT + 8)

		-- Label
		local sliderLabel = createStyledLabel(data.name .. "Label", data.name, theme)
		sliderLabel.Size = UDim2.new(0, 16, 0, SLIDER_HEIGHT)
		sliderLabel.Position = UDim2.new(0, 0, 0, yOffset)
		sliderLabel.TextXAlignment = Enum.TextXAlignment.Center
		sliderLabel.TextColor3 = data.color
		sliderLabel.Parent = container

		-- Slider background
		local sliderBg = Instance.new("Frame")
		sliderBg.Name = data.name .. "Slider"
		sliderBg.Size = UDim2.new(1, -70, 0, SLIDER_HEIGHT)
		sliderBg.Position = UDim2.new(0, 20, 0, yOffset)
		sliderBg.BackgroundColor3 = theme.InputBackground
		sliderBg.BorderSizePixel = 0
		sliderBg.Parent = container

		local sliderCorner = Instance.new("UICorner")
		sliderCorner.CornerRadius = UDim.new(0, 4)
		sliderCorner.Parent = sliderBg

		-- Slider fill
		local sliderFill = Instance.new("Frame")
		sliderFill.Name = "Fill"
		sliderFill.Size = UDim2.new(data.value / 255, 0, 1, 0)
		sliderFill.BackgroundColor3 = data.color
		sliderFill.BorderSizePixel = 0
		sliderFill.Parent = sliderBg

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 4)
		fillCorner.Parent = sliderFill

		-- Slider cursor
		local cursor = Instance.new("Frame")
		cursor.Name = "Cursor"
		cursor.Size = UDim2.new(0, 4, 1, 4)
		cursor.AnchorPoint = Vector2.new(0.5, 0.5)
		cursor.Position = UDim2.new(data.value / 255, 0, 0.5, 0)
		cursor.BackgroundColor3 = Color3.new(1, 1, 1)
		cursor.BorderSizePixel = 0
		cursor.ZIndex = 2
		cursor.Parent = sliderBg

		local cursorCorner = Instance.new("UICorner")
		cursorCorner.CornerRadius = UDim.new(0, 2)
		cursorCorner.Parent = cursor

		-- Value input
		local valueInput = createStyledInput(data.name .. "Input", "255", theme)
		valueInput.Size = UDim2.new(0, 45, 0, SLIDER_HEIGHT)
		valueInput.Position = UDim2.new(1, -45, 0, yOffset)
		valueInput.Text = tostring(data.value)
		valueInput.Parent = container

		self._rgbSliders[data.name] = sliderBg
		self._rgbInputs[data.name] = valueInput

		-- Input handling
		local isDragging = false

		local function updateFromPosition(inputPos: Vector3)
			local absPos = sliderBg.AbsolutePosition
			local absSize = sliderBg.AbsoluteSize

			local relX = clamp((inputPos.X - absPos.X) / absSize.X, 0, 1)
			local value = math.round(relX * 255)

			local cr, cg, cb = color3ToRGB(self._currentColor)
			if data.name == "R" then
				cr = value
			elseif data.name == "G" then
				cg = value
			else
				cb = value
			end

			self:SetRGB(cr, cg, cb)
		end

		sliderBg.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				isDragging = true
				updateFromPosition(input.Position)
			end
		end)

		table.insert(
			self._connections,
			UserInputService.InputChanged:Connect(function(input)
				if
					isDragging
					and (
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					)
				then
					updateFromPosition(input.Position)
				end
			end)
		)

		table.insert(
			self._connections,
			UserInputService.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					isDragging = false
				end
			end)
		)

		valueInput.FocusLost:Connect(function()
			local value = tonumber(valueInput.Text)
			if value then
				value = clamp(math.round(value), 0, 255)
				local cr, cg, cb = color3ToRGB(self._currentColor)
				if data.name == "R" then
					cr = value
				elseif data.name == "G" then
					cg = value
				else
					cb = value
				end
				self:SetRGB(cr, cg, cb)
			else
				local cr, cg, cb = color3ToRGB(self._currentColor)
				if data.name == "R" then
					valueInput.Text = tostring(cr)
				elseif data.name == "G" then
					valueInput.Text = tostring(cg)
				else
					valueInput.Text = tostring(cb)
				end
			end
		end)
	end

	return container
end

--[[
	Creates HSV sliders section
]]
createHSVSliders = function(self: ColorPicker, parent: GuiObject): Frame
	local theme = self._theme

	local container = Instance.new("Frame")
	container.Name = "HSVSlidersContainer"
	container.Size = UDim2.new(1, 0, 0, (SLIDER_HEIGHT + 8) * 3 + 16)
	container.BackgroundTransparency = 1
	container.LayoutOrder = 4.5
	container.Parent = parent

	local label = createStyledLabel("Label", "HSV", theme)
	label.Size = UDim2.new(1, 0, 0, 16)
	label.Font = Enum.Font.SourceSansSemibold
	label.Parent = container

	local h, s, v = self._currentHue, self._currentSaturation, self._currentValue
	local sliderData = {
		{ name = "H", label = "H", max = 360, value = h, suffix = "°" },
		{ name = "S", label = "S", max = 100, value = s, suffix = "%" },
		{ name = "V", label = "V", max = 100, value = v, suffix = "%" },
	}

	self._hsvSliders = {}
	self._hsvInputs = {}

	for i, data in sliderData do
		local yOffset = 16 + (i - 1) * (SLIDER_HEIGHT + 8)

		-- Label
		local sliderLabel = createStyledLabel(data.name .. "Label", data.label, theme)
		sliderLabel.Size = UDim2.new(0, 16, 0, SLIDER_HEIGHT)
		sliderLabel.Position = UDim2.new(0, 0, 0, yOffset)
		sliderLabel.TextXAlignment = Enum.TextXAlignment.Center
		sliderLabel.Parent = container

		-- Slider background
		local sliderBg = Instance.new("Frame")
		sliderBg.Name = data.name .. "Slider"
		sliderBg.Size = UDim2.new(1, -70, 0, SLIDER_HEIGHT)
		sliderBg.Position = UDim2.new(0, 20, 0, yOffset)
		sliderBg.BackgroundColor3 = theme.InputBackground
		sliderBg.BorderSizePixel = 0
		sliderBg.Parent = container

		local sliderCorner = Instance.new("UICorner")
		sliderCorner.CornerRadius = UDim.new(0, 4)
		sliderCorner.Parent = sliderBg

		-- Special gradient for Hue slider
		if data.name == "H" then
			local hueGradient = Instance.new("UIGradient")
			hueGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
				ColorSequenceKeypoint.new(0.167, Color3.fromHSV(0.167, 1, 1)),
				ColorSequenceKeypoint.new(0.333, Color3.fromHSV(0.333, 1, 1)),
				ColorSequenceKeypoint.new(0.5, Color3.fromHSV(0.5, 1, 1)),
				ColorSequenceKeypoint.new(0.667, Color3.fromHSV(0.667, 1, 1)),
				ColorSequenceKeypoint.new(0.833, Color3.fromHSV(0.833, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1)),
			})
			hueGradient.Parent = sliderBg
		else
			-- Slider fill for S and V
			local sliderFill = Instance.new("Frame")
			sliderFill.Name = "Fill"
			sliderFill.Size = UDim2.new(data.value / data.max, 0, 1, 0)
			sliderFill.BackgroundColor3 = theme.Accent
			sliderFill.BorderSizePixel = 0
			sliderFill.Parent = sliderBg

			local fillCorner = Instance.new("UICorner")
			fillCorner.CornerRadius = UDim.new(0, 4)
			fillCorner.Parent = sliderFill
		end

		-- Slider cursor
		local cursor = Instance.new("Frame")
		cursor.Name = "Cursor"
		cursor.Size = UDim2.new(0, 4, 1, 4)
		cursor.AnchorPoint = Vector2.new(0.5, 0.5)
		cursor.Position = UDim2.new(data.value / data.max, 0, 0.5, 0)
		cursor.BackgroundColor3 = Color3.new(1, 1, 1)
		cursor.BorderSizePixel = 0
		cursor.ZIndex = 2
		cursor.Parent = sliderBg

		local cursorCorner = Instance.new("UICorner")
		cursorCorner.CornerRadius = UDim.new(0, 2)
		cursorCorner.Parent = cursor

		local cursorStroke = Instance.new("UIStroke")
		cursorStroke.Color = Color3.new(0, 0, 0)
		cursorStroke.Thickness = 1
		cursorStroke.Parent = cursor

		-- Value input
		local valueInput = createStyledInput(data.name .. "Input", tostring(data.max), theme)
		valueInput.Size = UDim2.new(0, 45, 0, SLIDER_HEIGHT)
		valueInput.Position = UDim2.new(1, -45, 0, yOffset)
		valueInput.Text = tostring(math.round(data.value))
		valueInput.Parent = container

		self._hsvSliders[data.name] = sliderBg
		self._hsvInputs[data.name] = valueInput

		-- Input handling
		local isDragging = false

		local function updateFromPosition(inputPos: Vector3)
			local absPos = sliderBg.AbsolutePosition
			local absSize = sliderBg.AbsoluteSize

			local relX = clamp((inputPos.X - absPos.X) / absSize.X, 0, 1)
			local value = math.round(relX * data.max)

			if data.name == "H" then
				self._currentHue = value
			elseif data.name == "S" then
				self._currentSaturation = value
			else
				self._currentValue = value
			end

			self._currentColor = hsvToColor3(self._currentHue, self._currentSaturation, self._currentValue)
			updateAllUI(self)
			fireColorChanged(self)
		end

		sliderBg.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				isDragging = true
				updateFromPosition(input.Position)
			end
		end)

		table.insert(
			self._connections,
			UserInputService.InputChanged:Connect(function(input)
				if
					isDragging
					and (
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					)
				then
					updateFromPosition(input.Position)
				end
			end)
		)

		table.insert(
			self._connections,
			UserInputService.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					isDragging = false
				end
			end)
		)

		valueInput.FocusLost:Connect(function()
			local value = tonumber(valueInput.Text)
			if value then
				value = clamp(math.round(value), 0, data.max)
				if data.name == "H" then
					self._currentHue = value
				elseif data.name == "S" then
					self._currentSaturation = value
				else
					self._currentValue = value
				end
				self._currentColor = hsvToColor3(self._currentHue, self._currentSaturation, self._currentValue)
				updateAllUI(self)
				fireColorChanged(self)
			else
				if data.name == "H" then
					valueInput.Text = tostring(math.round(self._currentHue))
				elseif data.name == "S" then
					valueInput.Text = tostring(math.round(self._currentSaturation))
				else
					valueInput.Text = tostring(math.round(self._currentValue))
				end
			end
		end)
	end

	return container
end

--[[
	Creates preset colors grid
]]
createPresetColors = function(self: ColorPicker, parent: GuiObject): Frame
	local theme = self._theme

	local container = Instance.new("Frame")
	container.Name = "PresetColors"
	container.Size = UDim2.new(1, 0, 0, 16) -- Base height, will grow with AutomaticSize
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.LayoutOrder = 6
	container.Parent = parent

	local label = createStyledLabel("Label", "Presets", theme)
	label.Size = UDim2.new(1, 0, 0, 16)
	label.Font = Enum.Font.SourceSansSemibold
	label.Parent = container

	-- Tooltip label (shared, moves to hovered preset)
	local tooltip = Instance.new("TextLabel")
	tooltip.Name = "Tooltip"
	tooltip.Size = UDim2.new(0, 100, 0, 20)
	tooltip.BackgroundColor3 = theme.Surface
	tooltip.TextColor3 = theme.Text
	tooltip.TextSize = 10
	tooltip.Font = Enum.Font.SourceSans
	tooltip.Visible = false
	tooltip.ZIndex = 100
	tooltip.Parent = container

	local tooltipCorner = Instance.new("UICorner")
	tooltipCorner.CornerRadius = UDim.new(0, 4)
	tooltipCorner.Parent = tooltip

	local tooltipStroke = Instance.new("UIStroke")
	tooltipStroke.Color = theme.Border
	tooltipStroke.Thickness = 1
	tooltipStroke.Parent = tooltip

	-- Grid container
	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.Size = UDim2.new(1, 0, 0, 0) -- Height determined by AutomaticSize
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.Position = UDim2.new(0, 0, 0, 16)
	grid.BackgroundTransparency = 1
	grid.Parent = container

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 24, 0, 24)
	gridLayout.CellPadding = UDim2.new(0, 4, 0, 4)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	-- Create preset color buttons
	for i, presetData in PRESET_COLORS do
		local color = presetData.color
		local colorName = presetData.name
		local hexValue = color3ToHex(color)

		local presetButton = Instance.new("TextButton")
		presetButton.Name = "Preset" .. i
		presetButton.LayoutOrder = i
		presetButton.BackgroundColor3 = color
		presetButton.BorderSizePixel = 0
		presetButton.Text = ""
		presetButton.AutoButtonColor = false
		presetButton.Parent = grid

		local presetCorner = Instance.new("UICorner")
		presetCorner.CornerRadius = UDim.new(0, 4)
		presetCorner.Parent = presetButton

		local presetStroke = Instance.new("UIStroke")
		presetStroke.Color = theme.Border
		presetStroke.Thickness = 1
		presetStroke.Transparency = 0.5
		presetStroke.Parent = presetButton

		presetButton.MouseEnter:Connect(function()
			presetStroke.Transparency = 0
			presetStroke.Color = theme.Accent

			-- Show tooltip
			tooltip.Text = colorName .. " " .. hexValue
			tooltip.Size = UDim2.new(0, tooltip.TextBounds.X + 12, 0, 20)
			-- Position tooltip above the button
			local buttonPos = presetButton.AbsolutePosition
			local containerPos = container.AbsolutePosition
			tooltip.Position = UDim2.new(0, buttonPos.X - containerPos.X, 0, buttonPos.Y - containerPos.Y - 22)
			tooltip.Visible = true
		end)

		presetButton.MouseLeave:Connect(function()
			presetStroke.Transparency = 0.5
			presetStroke.Color = theme.Border
			tooltip.Visible = false
		end)

		presetButton.Activated:Connect(function()
			self:SetColor(color)
		end)
	end

	return container
end

--[[
	Creates confirm/cancel buttons
]]
createActionButtons = function(self: ColorPicker, parent: GuiObject): Frame
	local theme = self._theme
	local options = self.Options

	local container = Instance.new("Frame")
	container.Name = "ActionButtons"
	container.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT + 8)
	container.BackgroundTransparency = 1
	container.LayoutOrder = 10
	container.Parent = parent

	-- Button container for horizontal layout
	local buttonContainer = Instance.new("Frame")
	buttonContainer.Name = "ButtonContainer"
	buttonContainer.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
	buttonContainer.Position = UDim2.new(0, 0, 0, 8)
	buttonContainer.BackgroundTransparency = 1
	buttonContainer.Parent = container

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	buttonLayout.Padding = UDim.new(0, PADDING)
	buttonLayout.Parent = buttonContainer

	-- Cancel button
	local cancelButton = createStyledButton("CancelButton", "Cancel", theme)
	cancelButton.LayoutOrder = 1
	cancelButton.Parent = buttonContainer

	cancelButton.Activated:Connect(function()
		-- Revert to original color
		self._currentColor = self._originalColor
		self._currentAlpha = self._originalAlpha
		local h, s, v = color3ToHSV(self._originalColor)
		self._currentHue = h
		self._currentSaturation = s
		self._currentValue = v

		if options.OnCancel then
			options.OnCancel()
		end
		self:Hide()
	end)

	-- Confirm button
	local confirmButton = createStyledButton("ConfirmButton", "OK", theme)
	confirmButton.LayoutOrder = 2
	confirmButton.BackgroundColor3 = theme.Accent
	confirmButton.Parent = buttonContainer

	confirmButton.MouseEnter:Connect(function()
		confirmButton.BackgroundColor3 = Color3.new(
			math.min(1, theme.Accent.R + 0.1),
			math.min(1, theme.Accent.G + 0.1),
			math.min(1, theme.Accent.B + 0.1)
		)
	end)
	confirmButton.MouseLeave:Connect(function()
		confirmButton.BackgroundColor3 = theme.Accent
	end)

	confirmButton.Activated:Connect(function()
		-- Update original to current (for next time)
		self._originalColor = self._currentColor
		self._originalAlpha = self._currentAlpha

		if options.OnConfirm then
			options.OnConfirm(self._currentColor, self._currentAlpha)
		end
		self:Hide()
	end)

	return container
end

--[[
	Updates all UI elements to reflect current color
]]
updateAllUI = function(self: ColorPicker)
	local color = self._currentColor
	local h, s, v = self._currentHue, self._currentSaturation, self._currentValue
	local r, g, b = color3ToRGB(color)

	-- Update SV picker
	if self._svPicker then
		self._svPicker.BackgroundColor3 = Color3.fromHSV(h / 360, 1, 1)
	end

	if self._svCursor then
		self._svCursor.Position = UDim2.new(s / 100, 0, 1 - v / 100, 0)
	end

	-- Update Hue cursor
	if self._hueCursor then
		self._hueCursor.Position = UDim2.new(0.5, 0, h / 360, 0)
	end

	-- Update Alpha slider
	if self._alphaSlider and self._alphaCursor then
		self._alphaCursor.Position = UDim2.new(self._currentAlpha, 0, 0.5, 0)
	end

	if self._alphaOverlay then
		self._alphaOverlay.BackgroundColor3 = color
	end

	if self._alphaInput then
		self._alphaInput.Text = tostring(math.round(self._currentAlpha * 100))
	end

	-- Update color preview
	if self._previewNew then
		self._previewNew.BackgroundColor3 = color
		self._previewNew.BackgroundTransparency = 1 - self._currentAlpha
	end

	-- Update hex input
	if self._hexInput then
		self._hexInput.Text = color3ToHex(color)
	end

	-- Update RGB sliders and inputs
	if self._rgbSliders and self._rgbInputs then
		local rgbValues: { [string]: number } = { R = r, G = g, B = b }
		for channel, value in rgbValues do
			local slider = self._rgbSliders[channel]
			local input = self._rgbInputs[channel]

			if slider then
				local fill = slider:FindFirstChild("Fill") :: Frame?
				local cursor = slider:FindFirstChild("Cursor") :: Frame?
				if fill then
					fill.Size = UDim2.new(value / 255, 0, 1, 0)
				end
				if cursor then
					cursor.Position = UDim2.new(value / 255, 0, 0.5, 0)
				end
			end

			if input then
				input.Text = tostring(value)
			end
		end
	end

	-- Update HSV sliders and inputs
	if self._hsvSliders and self._hsvInputs then
		local hsvValues: { [string]: { value: number, max: number } } = {
			H = { value = h, max = 360 },
			S = { value = s, max = 100 },
			V = { value = v, max = 100 },
		}
		for channel, data in hsvValues do
			local slider = self._hsvSliders[channel]
			local input = self._hsvInputs[channel]

			if slider then
				local fill = slider:FindFirstChild("Fill") :: Frame?
				local cursor = slider:FindFirstChild("Cursor") :: Frame?
				if fill then
					fill.Size = UDim2.new(data.value / data.max, 0, 1, 0)
				end
				if cursor then
					cursor.Position = UDim2.new(data.value / data.max, 0, 0.5, 0)
				end
			end

			if input then
				input.Text = tostring(math.round(data.value))
			end
		end
	end
end

--[[
	Fires the OnColorChanged callback if present (with debouncing)
]]
fireColorChanged = function(self: ColorPicker)
	if self.Options.OnColorChanged then
		local now = tick()
		if now - (self._lastColorChangeTime or 0) >= COLOR_CHANGE_DEBOUNCE then
			self._lastColorChangeTime = now
			self.Options.OnColorChanged(self._currentColor, self._currentAlpha)
		end
	end
end

--[[
	Creates a new ColorPicker instance
]]
function ColorPickerHelper.new(options: ColorPickerOptions?): ColorPicker
	local self = setmetatable({}, ColorPickerHelper) :: any

	-- Merge options with defaults
	self.Options = {
		Parent = nil,
		InitialColor = Color3.fromRGB(255, 0, 0),
		InitialAlpha = 1,
		ShowAlpha = false,
		ShowPresets = true,
		ShowHexInput = true,
		ShowRGBSliders = true,
		ShowHSVSliders = false,
		Title = "Color Picker",
		Size = DEFAULT_SIZE,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Theme = "Auto",
		OnColorChanged = nil,
		OnConfirm = nil,
		OnCancel = nil,
	}

	if options then
		for key, value in options do
			(self.Options :: any)[key] = value
		end
	end

	-- Internal state
	self._currentColor = self.Options.InitialColor
	self._originalColor = self.Options.InitialColor
	self._currentAlpha = self.Options.InitialAlpha
	self._originalAlpha = self.Options.InitialAlpha
	self._currentHue = 0
	self._currentSaturation = 100
	self._currentValue = 100
	self._connections = {} :: { RBXScriptConnection }
	self._theme = getThemeColors(self.Options.Theme or "Auto")
	self._lastColorChangeTime = 0

	-- Initialize HSV from initial color
	local h, s, v = color3ToHSV(self._currentColor)
	self._currentHue = h
	self._currentSaturation = s
	self._currentValue = v

	-- UI element references (set during creation)
	self._svPicker = nil :: Frame?
	self._svCursor = nil :: Frame?
	self._hueSlider = nil :: Frame?
	self._hueCursor = nil :: Frame?
	self._alphaSlider = nil :: Frame?
	self._alphaCursor = nil :: Frame?
	self._alphaOverlay = nil :: Frame?
	self._alphaInput = nil :: TextBox?
	self._previewNew = nil :: Frame?
	self._previewOld = nil :: Frame?
	self._previewNewAlpha = nil :: Frame?
	self._hexInput = nil :: TextBox?
	self._rgbInputs = {} :: { R: TextBox?, G: TextBox?, B: TextBox? }
	self._hsvInputs = {} :: { H: TextBox?, S: TextBox?, V: TextBox? }
	self._rgbSliders = {} :: { R: Frame?, G: Frame?, B: Frame? }
	self._hsvSliders = {} :: { H: Frame?, S: Frame?, V: Frame? }

	-- Create UI (this will populate the references above)
	self._ui = createMainContainer(self)

	-- Initial UI update
	updateAllUI(self)

	return self :: any
end

--[[
	Sets the current color
]]
function ColorPickerHelper:SetColor(color: Color3)
	self._currentColor = color
	-- Preserve hue when setting to a color where hue is undefined (black, white, grey)
	local h, s, v = color3ToHSVPreserveHue(color, self._currentHue)
	self._currentHue = h
	self._currentSaturation = s
	self._currentValue = v
	updateAllUI(self)
	fireColorChanged(self)
end

--[[
	Sets the current alpha/transparency
]]
function ColorPickerHelper:SetAlpha(alpha: number)
	self._currentAlpha = clamp(alpha, 0, 1)
	updateAllUI(self)
	fireColorChanged(self)
end

--[[
	Gets the current color and alpha
]]
function ColorPickerHelper:GetColor(): (Color3, number)
	return self._currentColor, self._currentAlpha
end

--[[
	Sets color from hex string
]]
function ColorPickerHelper:SetHex(hex: string): boolean
	local color = hexToColor3(hex)
	if color then
		self:SetColor(color)
		return true
	end
	return false
end

--[[
	Gets color as hex string
]]
function ColorPickerHelper:GetHex(): string
	return color3ToHex(self._currentColor)
end

--[[
	Sets color from RGB values (0-255)
]]
function ColorPickerHelper:SetRGB(r: number, g: number, b: number)
	self:SetColor(rgbToColor3(r, g, b))
end

--[[
	Gets color as RGB values (0-255)
]]
function ColorPickerHelper:GetRGB(): (number, number, number)
	return color3ToRGB(self._currentColor)
end

--[[
	Sets color from HSV values (H: 0-360, S: 0-100, V: 0-100)
]]
function ColorPickerHelper:SetHSV(h: number, s: number, v: number)
	self._currentHue = clamp(h, 0, 360)
	self._currentSaturation = clamp(s, 0, 100)
	self._currentValue = clamp(v, 0, 100)
	self._currentColor = hsvToColor3(self._currentHue, self._currentSaturation, self._currentValue)
	updateAllUI(self)
	fireColorChanged(self)
end

--[[
	Gets color as HSV values (H: 0-360, S: 0-100, V: 0-100)
]]
function ColorPickerHelper:GetHSV(): (number, number, number)
	return self._currentHue, self._currentSaturation, self._currentValue
end

--[[
	Shows the color picker
]]
function ColorPickerHelper:Show()
	if self._ui then
		self._ui.Visible = true
	end
end

--[[
	Hides the color picker
]]
function ColorPickerHelper:Hide()
	if self._ui then
		self._ui.Visible = false
	end
end

--[[
	Returns whether the color picker is visible
]]
function ColorPickerHelper:IsVisible(): boolean
	return self._ui and self._ui.Visible or false
end

--[[
	Gets the UI frame
]]
function ColorPickerHelper:GetUI(): Frame
	return self._ui
end

--[[
	Destroys the color picker and cleans up
]]
function ColorPickerHelper:Destroy()
	-- Disconnect all connections
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._connections = {}

	-- Destroy UI
	if self._ui then
		self._ui:Destroy()
		self._ui = nil :: any
	end
end

--[[
	Utility: Convert hex to Color3
]]
function ColorPickerHelper.HexToColor3(hex: string): Color3?
	return hexToColor3(hex)
end

--[[
	Utility: Convert Color3 to hex
]]
function ColorPickerHelper.Color3ToHex(color: Color3): string
	return color3ToHex(color)
end

--[[
	Utility: Convert RGB to Color3
]]
function ColorPickerHelper.RGBToColor3(r: number, g: number, b: number): Color3
	return rgbToColor3(r, g, b)
end

--[[
	Utility: Convert Color3 to RGB
]]
function ColorPickerHelper.Color3ToRGB(color: Color3): (number, number, number)
	return color3ToRGB(color)
end

--[[
	Utility: Convert HSV to Color3
]]
function ColorPickerHelper.HSVToColor3(h: number, s: number, v: number): Color3
	return hsvToColor3(h, s, v)
end

--[[
	Utility: Convert Color3 to HSV
]]
function ColorPickerHelper.Color3ToHSV(color: Color3): (number, number, number)
	return color3ToHSV(color)
end

--[[
	Utility: Get a contrasting text color (black or white) for a given background color
	Uses relative luminance formula (WCAG 2.0)
]]
function ColorPickerHelper.GetContrastColor(backgroundColor: Color3): Color3
	-- Calculate relative luminance using sRGB formula
	local function linearize(channel: number): number
		if channel <= 0.03928 then
			return channel / 12.92
		end
		return ((channel + 0.055) / 1.055) ^ 2.4
	end

	local r = linearize(backgroundColor.R)
	local g = linearize(backgroundColor.G)
	local b = linearize(backgroundColor.B)

	-- Calculate luminance
	local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b

	-- Return black for light backgrounds, white for dark
	if luminance > 0.179 then
		return Color3.new(0, 0, 0)
	else
		return Color3.new(1, 1, 1)
	end
end

--[[
	Utility: Blend two colors together
]]
function ColorPickerHelper.BlendColors(color1: Color3, color2: Color3, ratio: number): Color3
	ratio = clamp(ratio, 0, 1)
	return Color3.new(
		color1.R + (color2.R - color1.R) * ratio,
		color1.G + (color2.G - color1.G) * ratio,
		color1.B + (color2.B - color1.B) * ratio
	)
end

--[[
	Utility: Lighten a color by a percentage (0-1)
]]
function ColorPickerHelper.Lighten(color: Color3, amount: number): Color3
	amount = clamp(amount, 0, 1)
	return Color3.new(
		color.R + (1 - color.R) * amount,
		color.G + (1 - color.G) * amount,
		color.B + (1 - color.B) * amount
	)
end

--[[
	Utility: Darken a color by a percentage (0-1)
]]
function ColorPickerHelper.Darken(color: Color3, amount: number): Color3
	amount = clamp(amount, 0, 1)
	return Color3.new(color.R * (1 - amount), color.G * (1 - amount), color.B * (1 - amount))
end

--[[
	Convenience method: Show a popup color picker
	Returns a Promise-like interface or uses callbacks
	
	Usage:
		ColorPickerHelper.Pick({
			InitialColor = Color3.new(1, 0, 0),
			Parent = screenGui,
			OnConfirm = function(color, alpha)
				print("Selected:", color)
			end,
		})
]]
function ColorPickerHelper.Pick(options: ColorPickerOptions): ColorPicker
	-- Track auto-created GUI locally (not in options)
	local autoCreatedGui: ScreenGui? = nil

	-- Ensure we have a parent
	if not options.Parent then
		local Players = game:GetService("Players")
		local player = Players.LocalPlayer
		if player then
			local playerGui = player:FindFirstChild("PlayerGui")
			if playerGui then
				local screenGui = Instance.new("ScreenGui")
				screenGui.Name = "ColorPickerGui"
				screenGui.ResetOnSpawn = false
				screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
				screenGui.DisplayOrder = 999
				screenGui.Parent = playerGui
				options.Parent = screenGui :: any -- Cast needed as Parent expects GuiObject

				-- Store reference so we can clean up
				autoCreatedGui = screenGui
			end
		end
	end

	local picker = ColorPickerHelper.new(options)

	-- Wrap callbacks to clean up auto-created gui
	local originalOnConfirm = options.OnConfirm
	local originalOnCancel = options.OnCancel

	if autoCreatedGui then
		local gui = autoCreatedGui

		picker.Options.OnConfirm = function(color: Color3, alpha: number)
			if originalOnConfirm then
				originalOnConfirm(color, alpha)
			end
			picker:Destroy()
			gui:Destroy()
		end

		picker.Options.OnCancel = function()
			if originalOnCancel then
				originalOnCancel()
			end
			picker:Destroy()
			gui:Destroy()
		end
	end

	picker:Show()
	return picker
end

--[[
	Sets the original/comparison color (shown on the left of preview)
]]
function ColorPickerHelper:SetOriginalColor(color: Color3, alpha: number?)
	self._originalColor = color
	self._originalAlpha = alpha or 1
	if self._previewOld then
		self._previewOld.BackgroundColor3 = color
		self._previewOld.BackgroundTransparency = 1 - self._originalAlpha
	end
end

--[[
	Resets the current color to the original
]]
function ColorPickerHelper:Reset()
	self._currentColor = self._originalColor
	self._currentAlpha = self._originalAlpha
	-- Use preserveHue to avoid hue jumping when resetting to black/white/grey
	local h, s, v = color3ToHSVPreserveHue(self._originalColor, self._currentHue)
	self._currentHue = h
	self._currentSaturation = s
	self._currentValue = v
	updateAllUI(self)
	fireColorChanged(self)
end

return table.freeze(ColorPickerHelper)
