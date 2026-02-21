--!strict
--[[
	Helper functions for UI creation, styling, and layout.
	
	UI Improvements implemented:
	- Title bar uses UIListLayout + UIFlexItem for proper centering and spacing
	- ClipsDescendants enabled on main frame and components to prevent bleed-through
	- Text truncation with focus/unfocus handling for inputs
	- Improved collapse behavior with proper sizing
	- Settings menu with collapsible sections and ScrollingFrame
	- Minimized state has proper draggable area around button
	- All elements properly clip and don't overflow
	- Footer uses flex layout for proper responsive resizing
]]

--- Imports ---
local Constants = require(script.Parent.Parent.Constants)
local ImageHelper = require(script.Parent.ImageHelper)
local Types = require(script.Parent.Parent.Types)

--- Types ---
type ViewerOptionsInternal = Types.ViewerOptionsInternal

--- Variables ---
local COLORS = Constants.COLORS
local SIZES = Constants.SIZES
local TRANSPARENCY = Constants.TRANSPARENCY

--- Functions ---

-- UI Primitives

--[[
	Creates a UICorner with the specified radius.
]]
local function CreateCorner(radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	return corner
end

--[[
	Creates a UIStroke with the specified properties.
]]
local function CreateStroke(color: Color3, thickness: number, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	return stroke
end

--[[
	Creates a UIPadding with uniform or individual padding values.
]]
local function CreatePadding(left: number?, right: number?, top: number?, bottom: number?): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, left or 0)
	padding.PaddingRight = UDim.new(0, right or 0)
	padding.PaddingTop = UDim.new(0, top or 0)
	padding.PaddingBottom = UDim.new(0, bottom or 0)
	return padding
end

--[[
	Creates a UIListLayout with common settings.
]]
local function CreateListLayout(
	direction: Enum.FillDirection?,
	horizontalAlign: Enum.HorizontalAlignment?,
	verticalAlign: Enum.VerticalAlignment?,
	padding: number?
): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.HorizontalAlignment = horizontalAlign or Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = verticalAlign or Enum.VerticalAlignment.Top
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	if padding then
		layout.Padding = UDim.new(0, padding)
	end
	return layout
end

--[[
	Creates a UISizeConstraint with min/max bounds.
]]
local function CreateSizeConstraint(minSize: Vector2?, maxSize: Vector2?): UISizeConstraint
	local constraint = Instance.new("UISizeConstraint")
	if minSize then
		constraint.MinSize = minSize
	end
	if maxSize then
		constraint.MaxSize = maxSize
	end
	return constraint
end

--[[
	Creates a UIFlexItem for flex layout control.
]]
local function CreateFlexItem(flexMode: Enum.UIFlexMode?, growRatio: number?, shrinkRatio: number?): UIFlexItem
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = flexMode or Enum.UIFlexMode.Fill
	if growRatio then
		flex.GrowRatio = growRatio
	end
	if shrinkRatio then
		flex.ShrinkRatio = shrinkRatio
	end
	return flex
end

-- Text Truncation Handling

--[[
	Sets up automatic text truncation toggling for TextBoxes.
	Disables truncation on focus, re-enables on unfocus.
]]
local function SetupTruncationToggle(textBox: TextBox, truncateType: Enum.TextTruncate?)
	local normalTruncate = truncateType or Enum.TextTruncate.AtEnd

	textBox.TextTruncate = normalTruncate

	textBox.Focused:Connect(function()
		textBox.TextTruncate = Enum.TextTruncate.None
	end)

	textBox.FocusLost:Connect(function()
		textBox.TextTruncate = normalTruncate
	end)
end

-- ScrollingFrame Canvas Size Helper

--[[
	Connects a UIListLayout to automatically update a ScrollingFrame's canvas size.
	Returns the connection for cleanup.
]]
local function SetupAutoCanvasSize(scrollFrame: ScrollingFrame, listLayout: UIListLayout): RBXScriptConnection
	local function UpdateCanvasSize()
		local contentSize = listLayout.AbsoluteContentSize
		scrollFrame.CanvasSize = UDim2.fromOffset(0, contentSize.Y)
	end

	-- Initial update
	UpdateCanvasSize()

	-- Connect to changes
	return listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateCanvasSize)
end

-- Header Creation (with flex layout for proper spacing)

--[[
	Creates the header frame with flex-based layout for proper title centering.
	Uses UIListLayout with UIFlexItem for responsive positioning.
	ClipsDescendants is enabled to prevent bleed-through during minimize/collapse.
]]
local function CreateHeader(options: ViewerOptionsInternal): Frame
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, SIZES.HeaderHeight)
	header.BackgroundColor3 = COLORS.HeaderBackground
	header.BackgroundTransparency = TRANSPARENCY.HeaderBackground
	header.BorderSizePixel = 0
	header.ClipsDescendants = true -- Prevent bleed-through on minimize

	local headerCorner = CreateCorner(SIZES.CornerRadius)
	headerCorner.Parent = header

	-- Corner fix (to make bottom corners square)
	local headerFix = Instance.new("Frame")
	headerFix.Name = "CornerFix"
	headerFix.Size = UDim2.new(1, 0, 0, SIZES.CornerRadius)
	headerFix.Position = UDim2.new(0, 0, 1, -SIZES.CornerRadius)
	headerFix.BackgroundColor3 = COLORS.HeaderBackground
	headerFix.BackgroundTransparency = TRANSPARENCY.HeaderBackground
	headerFix.BorderSizePixel = 0
	headerFix.Parent = header

	-- Content container for flex layout
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -8, 1, 0)
	content.Position = UDim2.fromOffset(4, 0)
	content.BackgroundTransparency = 1
	content.Parent = header

	-- Flex layout for header content (horizontal)
	local contentLayout = Instance.new("UIListLayout")
	contentLayout.Name = "Layout"
	contentLayout.FillDirection = Enum.FillDirection.Horizontal
	contentLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, 4)
	contentLayout.Parent = content

	-- Left Section (Badge + Desync + Freeze indicators) - auto-width based on visible content
	local leftSection = Instance.new("Frame")
	leftSection.Name = "LeftSection"
	leftSection.Size = UDim2.fromOffset(0, SIZES.HeaderHeight - 4)
	leftSection.AutomaticSize = Enum.AutomaticSize.X
	leftSection.BackgroundTransparency = 1
	leftSection.LayoutOrder = 1
	leftSection.Parent = content

	local leftLayout = Instance.new("UIListLayout")
	leftLayout.FillDirection = Enum.FillDirection.Horizontal
	leftLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
	leftLayout.Padding = UDim.new(0, 4)
	leftLayout.Parent = leftSection

	-- Badge Label (link group indicator)
	local badgeLabel = Instance.new("TextLabel")
	badgeLabel.Name = "BadgeLabel"
	badgeLabel.Size = UDim2.fromOffset(18, 18)
	badgeLabel.BackgroundColor3 = COLORS.BadgeBackground
	badgeLabel.TextColor3 = COLORS.BadgeSynced
	badgeLabel.TextSize = 11
	badgeLabel.FontFace = options.KeyFontFace
	badgeLabel.Text = "1"
	badgeLabel.Visible = false
	badgeLabel.LayoutOrder = 1
	badgeLabel.Parent = leftSection

	local badgeCorner = CreateCorner(9)
	badgeCorner.Parent = badgeLabel

	-- Desync Icon
	local desyncIcon =
		ImageHelper.CreateIcon(ImageHelper.ICON_OFFSETS.Desync, UDim2.fromOffset(14, 14), COLORS.DesyncIcon)
	desyncIcon.Name = "DesyncIcon"
	desyncIcon.AnchorPoint = Vector2.zero
	desyncIcon.Position = UDim2.new()
	desyncIcon.Visible = false
	desyncIcon.LayoutOrder = 2
	desyncIcon.Parent = leftSection

	-- Freeze Indicator
	local freezeIcon =
		ImageHelper.CreateIcon(ImageHelper.ICON_OFFSETS.Freeze, UDim2.fromOffset(14, 14), COLORS.FreezeActive)
	freezeIcon.Name = "FreezeIndicator"
	freezeIcon.AnchorPoint = Vector2.zero
	freezeIcon.Position = UDim2.new()
	freezeIcon.Visible = false
	freezeIcon.LayoutOrder = 3
	freezeIcon.Parent = leftSection

	-- Title Section (flexible, takes remaining space)
	local titleSection = Instance.new("Frame")
	titleSection.Name = "TitleSection"
	titleSection.Size = UDim2.new(1, 0, 1, 0)
	titleSection.BackgroundTransparency = 1
	titleSection.LayoutOrder = 2
	titleSection.ClipsDescendants = true
	titleSection.Parent = content

	local titleFlex = CreateFlexItem(Enum.UIFlexMode.Fill, 1, 1)
	titleFlex.Parent = titleSection

	-- Header Label (title)
	local headerLabel = Instance.new("TextLabel")
	headerLabel.Name = "HeaderLabel"
	headerLabel.Size = UDim2.fromScale(1, 1)
	headerLabel.BackgroundTransparency = 1
	headerLabel.TextColor3 = COLORS.HeaderText
	headerLabel.TextScaled = true
	headerLabel.FontFace = Constants.DEFAULT_HEADER_FONT
	headerLabel.Text = `{if options.AppendWrenchEmoji then "🔧 " else ""}{options.Title}`
	headerLabel.TextXAlignment = Enum.TextXAlignment.Left
	headerLabel.TextTruncate = Enum.TextTruncate.AtEnd
	headerLabel.Parent = titleSection

	local headerTextConstraint = Instance.new("UITextSizeConstraint")
	headerTextConstraint.MaxTextSize = 14
	headerTextConstraint.MinTextSize = 8
	headerTextConstraint.Parent = headerLabel

	-- Right Section (buttons) - auto-width based on content
	local rightSection = Instance.new("Frame")
	rightSection.Name = "RightSection"
	rightSection.Size = UDim2.fromOffset(0, SIZES.HeaderHeight - 4)
	rightSection.AutomaticSize = Enum.AutomaticSize.X
	rightSection.BackgroundTransparency = 1
	rightSection.LayoutOrder = 3
	rightSection.Parent = content

	local rightLayout = Instance.new("UIListLayout")
	rightLayout.FillDirection = Enum.FillDirection.Horizontal
	rightLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rightLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.Padding = UDim.new(0, 2)
	rightLayout.Parent = rightSection

	-- Link Button (Material Icon)
	local linkButton =
		ImageHelper.CreateMaterialIconButton("LinkButton", "Link", UDim2.fromOffset(24, 24), COLORS.LinkInactive)
	if linkButton then
		linkButton.LayoutOrder = 1
		linkButton.Parent = rightSection
	end

	-- Freeze Button (Material Icon - Pause to indicate "click to freeze" when live)
	local freezeButton =
		ImageHelper.CreateMaterialIconButton("FreezeButton", "Pause", UDim2.fromOffset(24, 24), COLORS.FreezeActive)
	if freezeButton then
		freezeButton.LayoutOrder = 2
		freezeButton.Parent = rightSection
	end

	-- Collapse Button (Material Icon - ExpandLess for expanded state)
	local collapseButton = ImageHelper.CreateMaterialIconButton(
		"CollapseButton",
		"ExpandLess",
		UDim2.fromOffset(24, 24),
		COLORS.IconDefault
	)
	if collapseButton then
		collapseButton.LayoutOrder = 3
		collapseButton.Parent = rightSection
	end

	-- Minimize Button (Material Icon - Remove/minus)
	local minimizeButton =
		ImageHelper.CreateMaterialIconButton("MinimizeButton", "Remove", UDim2.fromOffset(24, 24), COLORS.IconDefault)
	if minimizeButton then
		minimizeButton.LayoutOrder = 4
		minimizeButton.Parent = rightSection
	end

	-- Close Button (Material Icon)
	local closeButton =
		ImageHelper.CreateMaterialIconButton("CloseButton", "Close", UDim2.fromOffset(24, 24), COLORS.CloseButton)
	if closeButton then
		closeButton.LayoutOrder = 5
		closeButton.Parent = rightSection
	end

	return header
end

--[[
	Finds a child in the header by name, checking both old and new flex structure.
	Provides backward compatibility for code expecting direct header children.
]]
local function FindHeaderChild(header: Frame, name: string): Instance?
	-- First check if it's a direct child (backward compat)
	local direct = header:FindFirstChild(name)
	if direct then
		return direct
	end

	-- Check the new flex structure
	local content = header:FindFirstChild("Content")
	if not content then
		return nil
	end

	-- Check left section
	local leftSection = content:FindFirstChild("LeftSection")
	if leftSection then
		local child = leftSection:FindFirstChild(name)
		if child then
			return child
		end
	end

	-- Check title section
	local titleSection = content:FindFirstChild("TitleSection")
	if titleSection then
		local child = titleSection:FindFirstChild(name)
		if child then
			return child
		end
	end

	-- Check right section
	local rightSection = content:FindFirstChild("RightSection")
	if rightSection then
		local child = rightSection:FindFirstChild(name)
		if child then
			return child
		end
	end

	return nil
end

-- Footer Creation

--[[
	Creates the footer frame with filter inputs and controls.
	Uses flex layout for proper responsive sizing.
	ClipsDescendants prevents text overflow.
]]
local function CreateFooter(options: ViewerOptionsInternal): Frame
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.Size = UDim2.new(1, 0, 0, SIZES.FooterHeight)
	footer.Position = UDim2.new(0, 0, 1, -SIZES.FooterHeight)
	footer.BackgroundColor3 = COLORS.FooterBackground
	footer.BackgroundTransparency = TRANSPARENCY.FooterBackground
	footer.BorderSizePixel = 0
	footer.ClipsDescendants = true -- Prevent text overflow

	local footerCorner = CreateCorner(SIZES.CornerRadius)
	footerCorner.Parent = footer

	-- Corner fix (for square top corners)
	local footerFix = Instance.new("Frame")
	footerFix.Name = "CornerFix"
	footerFix.Size = UDim2.new(1, 0, 0, SIZES.CornerRadius)
	footerFix.Position = UDim2.new()
	footerFix.BackgroundColor3 = COLORS.FooterBackground
	footerFix.BackgroundTransparency = TRANSPARENCY.FooterBackground
	footerFix.BorderSizePixel = 0
	footerFix.Parent = footer

	-- Footer content container with flex layout (leave space for resize button on right)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -28, 0, 20) -- Extra padding on right for resize button
	content.Position = UDim2.fromOffset(4, 4)
	content.BackgroundTransparency = 1
	content.Parent = footer

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.FillDirection = Enum.FillDirection.Horizontal
	contentLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, 4)
	contentLayout.Parent = content

	-- Filter Mode Button (fixed width)
	local filterModeButton = Instance.new("TextButton")
	filterModeButton.Name = "FilterModeButton"
	filterModeButton.Size = UDim2.fromOffset(22, 18)
	filterModeButton.BackgroundColor3 = COLORS.ButtonBackground
	filterModeButton.TextColor3 = COLORS.FilterText
	filterModeButton.Text = "K"
	filterModeButton.TextSize = 11
	filterModeButton.FontFace = Constants.DEFAULT_BOLD_FONT
	filterModeButton.AutoButtonColor = true
	filterModeButton.LayoutOrder = 1
	filterModeButton.Parent = content

	local filterModeCorner = CreateCorner(4)
	filterModeCorner.Parent = filterModeButton

	-- Field Filter Container (flexible, grows)
	local filterContainer = Instance.new("Frame")
	filterContainer.Name = "FilterContainer"
	filterContainer.Size = UDim2.fromOffset(80, 18)
	filterContainer.BackgroundTransparency = 1
	filterContainer.LayoutOrder = 2
	filterContainer.ClipsDescendants = true
	filterContainer.Parent = content

	local filterFlex = CreateFlexItem(Enum.UIFlexMode.Fill, 1, 1)
	filterFlex.Parent = filterContainer

	local fieldFilter = Instance.new("TextBox")
	fieldFilter.Name = "FieldFilter"
	fieldFilter.Size = UDim2.fromScale(1, 1)
	fieldFilter.BackgroundColor3 = COLORS.InputBackground
	fieldFilter.BackgroundTransparency = TRANSPARENCY.InputBackground
	fieldFilter.TextColor3 = COLORS.FilterText
	fieldFilter.PlaceholderText = "🔍 Filter keys..."
	fieldFilter.PlaceholderColor3 = COLORS.PlaceholderText
	fieldFilter.TextSize = 12
	fieldFilter.FontFace = options.KeyFontFace
	fieldFilter.ClearTextOnFocus = false
	fieldFilter.TextXAlignment = Enum.TextXAlignment.Left
	fieldFilter.TextTruncate = Enum.TextTruncate.AtEnd
	fieldFilter.Text = ""
	fieldFilter.Parent = filterContainer

	local filterCorner = CreateCorner(4)
	filterCorner.Parent = fieldFilter

	local filterPadding = CreatePadding(6, 6)
	filterPadding.Parent = fieldFilter

	-- Setup truncation toggle for better UX
	SetupTruncationToggle(fieldFilter)

	-- Exclusions Container (flexible, grows but less than filter)
	local exclusionsContainer = Instance.new("Frame")
	exclusionsContainer.Name = "ExclusionsContainer"
	exclusionsContainer.Size = UDim2.fromOffset(60, 18)
	exclusionsContainer.BackgroundTransparency = 1
	exclusionsContainer.LayoutOrder = 3
	exclusionsContainer.ClipsDescendants = true
	exclusionsContainer.Parent = content

	local exclusionsFlex = CreateFlexItem(Enum.UIFlexMode.Fill, 0.7, 1)
	exclusionsFlex.Parent = exclusionsContainer

	local exclusions = Instance.new("TextBox")
	exclusions.Name = "Exclusions"
	exclusions.Size = UDim2.fromScale(1, 1)
	exclusions.BackgroundColor3 = COLORS.InputBackground
	exclusions.BackgroundTransparency = TRANSPARENCY.InputBackground
	exclusions.TextColor3 = COLORS.ExclusionText
	exclusions.PlaceholderText = "🚫 Exclude types..."
	exclusions.PlaceholderColor3 = COLORS.PlaceholderText
	exclusions.TextSize = 12
	exclusions.FontFace = options.KeyFontFace
	exclusions.ClearTextOnFocus = false
	exclusions.TextXAlignment = Enum.TextXAlignment.Left
	exclusions.Text = ""
	exclusions.TextTruncate = Enum.TextTruncate.AtEnd
	exclusions.Parent = exclusionsContainer

	local exclusionCorner = CreateCorner(4)
	exclusionCorner.Parent = exclusions

	local exclusionPadding = CreatePadding(6, 6)
	exclusionPadding.Parent = exclusions

	-- Setup truncation toggle for better UX
	SetupTruncationToggle(exclusions)

	-- Match Count Container (auto-width based on content, shrinks when empty)
	local matchCountContainer = Instance.new("Frame")
	matchCountContainer.Name = "MatchCountContainer"
	matchCountContainer.Size = UDim2.fromOffset(0, 18)
	matchCountContainer.AutomaticSize = Enum.AutomaticSize.X
	matchCountContainer.BackgroundTransparency = 1
	matchCountContainer.LayoutOrder = 4
	matchCountContainer.ClipsDescendants = true
	matchCountContainer.Parent = content

	-- Match Count Label (inside container for proper flex behavior)
	local matchCountLabel = Instance.new("TextLabel")
	matchCountLabel.Name = "MatchCountLabel"
	matchCountLabel.Size = UDim2.fromOffset(0, 18)
	matchCountLabel.AutomaticSize = Enum.AutomaticSize.X
	matchCountLabel.BackgroundTransparency = 1
	matchCountLabel.TextColor3 = COLORS.SubLabelText
	matchCountLabel.Text = ""
	matchCountLabel.TextSize = 11
	matchCountLabel.FontFace = options.KeyFontFace
	matchCountLabel.TextXAlignment = Enum.TextXAlignment.Right
	matchCountLabel.Parent = matchCountContainer

	-- Hamburger Menu Button (part of flex layout)
	local hamburgerContainer = Instance.new("Frame")
	hamburgerContainer.Name = "HamburgerContainer"
	hamburgerContainer.Size = UDim2.fromOffset(22, 20)
	hamburgerContainer.BackgroundTransparency = 1
	hamburgerContainer.LayoutOrder = 5
	hamburgerContainer.Parent = content

	local hamburgerButton =
		ImageHelper.CreateIconButton("HamburgerButton", ImageHelper.ICON_OFFSETS.Menu, UDim2.fromScale(0.5, 0.5))
	hamburgerButton.Size = UDim2.fromOffset(20, 20)
	hamburgerButton.AnchorPoint = Vector2.new(0.5, 0.5)
	hamburgerButton.Parent = hamburgerContainer

	-- Resize Button (stays absolute positioned in corner)
	local resizeButton = Instance.new("ImageButton")
	resizeButton.Name = "ResizeButton"
	resizeButton.Size = UDim2.fromOffset(16, 16)
	resizeButton.Position = UDim2.new(1, -4, 1, -4)
	resizeButton.AnchorPoint = Vector2.new(1, 1)
	resizeButton.BackgroundTransparency = 1
	resizeButton.AutoButtonColor = false
	resizeButton.Parent = footer

	local resizeIcon =
		ImageHelper.CreateIcon(ImageHelper.ICON_OFFSETS.Resize, UDim2.fromOffset(12, 12), COLORS.IconResize)
	resizeIcon.Parent = resizeButton

	return footer
end

--[[
Finds a child in the footer by name, checking both old and new flex structure.
Provides backward compatibility for code expecting direct footer children.
]]
local function FindFooterChild(footer: Frame, name: string): Instance?
	-- First check if its a direct child (backward compat)
	local direct = footer:FindFirstChild(name)
	if direct then
		return direct
	end

	-- Check the new flex structure
	local content = footer:FindFirstChild("Content")
	if not content then
		return nil
	end

	-- Check direct children of content first
	local directInContent = content:FindFirstChild(name)
	if directInContent then
		return directInContent
	end

	-- Check all containers in content
	for _, container in content:GetChildren() do
		if container:IsA("Frame") then
			local child = container:FindFirstChild(name)
			if child then
				return child
			end
		end
	end

	return nil
end

-- Viewer Area Creation

--[[
	Creates the main viewer/content area with scrolling frame.
]]
local function CreateViewerArea(options: ViewerOptionsInternal): Frame
	local viewer = Instance.new("Frame")
	viewer.Name = "Viewer"
	viewer.Size = UDim2.new(1, 0, 1, -(SIZES.HeaderHeight + SIZES.FooterHeight))
	viewer.Position = UDim2.fromOffset(0, SIZES.HeaderHeight)
	viewer.BackgroundTransparency = 1
	viewer.BorderSizePixel = 0
	viewer.ClipsDescendants = true

	local scrollingFrame = Instance.new("ScrollingFrame")
	scrollingFrame.Name = "Table"
	scrollingFrame.Size = UDim2.fromScale(1, 1)
	scrollingFrame.CanvasSize = UDim2.new()
	scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollingFrame.ScrollBarThickness = 4
	scrollingFrame.ScrollBarImageColor3 = COLORS.ScrollBar
	scrollingFrame.BackgroundTransparency = 1
	scrollingFrame.BorderSizePixel = 0
	scrollingFrame.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	scrollingFrame.TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
	scrollingFrame.BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
	scrollingFrame.MidImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
	scrollingFrame.Parent = viewer

	local listLayout = Instance.new("UIListLayout")
	listLayout.Name = "ListLayout"
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 1)
	listLayout.Parent = scrollingFrame

	local padding = CreatePadding(4, 8, 4, 4)
	padding.Name = "UIPadding"
	padding.Parent = scrollingFrame

	return viewer
end

-- Tooltip Creation

--[[
	Creates a tooltip frame.
]]
local function CreateTooltip(options: ViewerOptionsInternal): Frame
	local tooltip = Instance.new("Frame")
	tooltip.Name = "Tooltip"
	tooltip.Size = UDim2.fromOffset(200, 24)
	tooltip.AutomaticSize = Enum.AutomaticSize.XY
	tooltip.BackgroundColor3 = COLORS.TooltipBackground
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.ZIndex = 100

	local tooltipCorner = CreateCorner(SIZES.TooltipCornerRadius)
	tooltipCorner.Parent = tooltip

	local tooltipStroke = CreateStroke(COLORS.TooltipBorder, SIZES.TooltipStrokeThickness)
	tooltipStroke.Parent = tooltip

	local tooltipLabel = Instance.new("TextLabel")
	tooltipLabel.Name = "Label"
	tooltipLabel.Size = UDim2.new()
	tooltipLabel.AutomaticSize = Enum.AutomaticSize.XY
	tooltipLabel.BackgroundTransparency = 1
	tooltipLabel.TextColor3 = COLORS.IconDefault
	tooltipLabel.TextSize = 12
	tooltipLabel.FontFace = options.ValueFontFace
	tooltipLabel.TextXAlignment = Enum.TextXAlignment.Left
	tooltipLabel.TextWrapped = true
	tooltipLabel.Parent = tooltip

	local tooltipPadding = CreatePadding(6, 6, 4, 4)
	tooltipPadding.Parent = tooltip

	local tooltipSizeConstraint = CreateSizeConstraint(nil, Vector2.new(SIZES.TooltipMaxWidth, SIZES.TooltipMaxHeight))
	tooltipSizeConstraint.Parent = tooltip

	return tooltip
end

--[[
	Destroys an entry GUI and its children recursively.
	Used for cleaning up table entry frames.
	
	@param entry The entry frame to destroy
]]
local function DestroyEntry(entry: Frame)
	local children = entry:FindFirstChild("Children") :: Frame?
	if children then
		for _, child in pairs(children:GetChildren()) do
			if child:IsA("Frame") and child.Name ~= "ListLayout" then
				DestroyEntry(child :: Frame)
			end
		end
	end
	entry:Destroy()
end

-- Ghost Row Creation

export type GhostRowConfig = {
	Parent: Frame,
	Indent: number?,
	KeyFontFace: Font,
	ValueFontFace: Font,
	PlaceholderText: string?,
}

export type GhostRowResult = {
	Row: Frame,
	KeyInput: TextBox,
	ValueInput: TextBox,
	AddButton: ImageButton,
}

--[[
	Creates a ghost row for adding new entries when Editable is true.
	This is used for both root-level and nested table entries.
	
	@param config GhostRowConfig with Parent, Indent, KeyFontFace, ValueFontFace
	@return GhostRowResult containing Row, KeyInput, ValueInput, AddButton
]]
local function CreateGhostRow(config: GhostRowConfig): GhostRowResult
	local indent = config.Indent or 0
	local placeholderText = config.PlaceholderText or "value"

	local ghostRow = Instance.new("Frame")
	ghostRow.Name = if indent == 0 then "RootGhostRow" else "GhostRow"
	ghostRow.Size = UDim2.new(1, -indent, 0, 22)
	ghostRow.Position = if indent > 0 then UDim2.fromOffset(indent, 0) else UDim2.new()
	ghostRow.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	ghostRow.BackgroundTransparency = 0.8
	ghostRow.BorderSizePixel = 0
	ghostRow.LayoutOrder = 999999999 -- Always at the bottom
	ghostRow.Parent = config.Parent

	local ghostCorner = CreateCorner(4)
	ghostCorner.Parent = ghostRow

	-- Key input
	local keyInput = Instance.new("TextBox")
	keyInput.Name = "KeyInput"
	keyInput.Size = UDim2.fromOffset(80, 18)
	keyInput.Position = UDim2.fromOffset(4, 2)
	keyInput.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
	keyInput.BackgroundTransparency = 0.5
	keyInput.TextColor3 = Color3.fromRGB(180, 180, 185)
	keyInput.PlaceholderText = "key"
	keyInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 105)
	keyInput.TextSize = 12
	keyInput.FontFace = config.KeyFontFace
	keyInput.Text = ""
	keyInput.ClearTextOnFocus = false
	keyInput.TextXAlignment = Enum.TextXAlignment.Left
	keyInput.Parent = ghostRow

	local keyInputCorner = CreateCorner(3)
	keyInputCorner.Parent = keyInput

	local keyInputPadding = CreatePadding(4, 4)
	keyInputPadding.Parent = keyInput

	-- Colon separator
	local colonLabel = Instance.new("TextLabel")
	colonLabel.Name = "Colon"
	colonLabel.Size = UDim2.fromOffset(12, 18)
	colonLabel.Position = UDim2.fromOffset(86, 2)
	colonLabel.BackgroundTransparency = 1
	colonLabel.TextColor3 = Color3.fromRGB(150, 150, 155)
	colonLabel.TextSize = 12
	colonLabel.FontFace = config.ValueFontFace
	colonLabel.Text = ":"
	colonLabel.Parent = ghostRow

	-- Value input
	local valueInput = Instance.new("TextBox")
	valueInput.Name = "ValueInput"
	valueInput.Size = UDim2.new(1, -146, 0, 18)
	valueInput.Position = UDim2.fromOffset(100, 2)
	valueInput.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
	valueInput.BackgroundTransparency = 0.5
	valueInput.TextColor3 = Color3.fromRGB(180, 180, 185)
	valueInput.PlaceholderText = placeholderText
	valueInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 105)
	valueInput.TextSize = 12
	valueInput.FontFace = config.ValueFontFace
	valueInput.Text = ""
	valueInput.ClearTextOnFocus = false
	valueInput.TextXAlignment = Enum.TextXAlignment.Left
	valueInput.Parent = ghostRow

	local valueInputCorner = CreateCorner(3)
	valueInputCorner.Parent = valueInput

	local valueInputPadding = CreatePadding(4, 4)
	valueInputPadding.Parent = valueInput

	-- Add button
	local addBtn = Instance.new("ImageButton")
	addBtn.Name = "AddButton"
	addBtn.Size = UDim2.fromOffset(18, 18)
	addBtn.Position = UDim2.new(1, -22, 0, 2)
	addBtn.AnchorPoint = Vector2.new(1, 0)
	addBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
	addBtn.BackgroundTransparency = 0.3
	addBtn.AutoButtonColor = false
	addBtn.Parent = ghostRow

	local addBtnCorner = CreateCorner(3)
	addBtnCorner.Parent = addBtn

	-- Use text plus instead of icon
	local addLabel = Instance.new("TextLabel")
	addLabel.Name = "PlusLabel"
	addLabel.Size = UDim2.fromScale(1, 1)
	addLabel.BackgroundTransparency = 1
	addLabel.Text = "+"
	addLabel.TextColor3 = Color3.fromRGB(150, 255, 150)
	addLabel.TextSize = 16
	addLabel.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold)
	addLabel.Parent = addBtn

	-- Hover effects (connected directly since no cleanup needed - destroyed with parent)
	ghostRow.MouseEnter:Connect(function()
		ghostRow.BackgroundTransparency = 0.6
	end)

	ghostRow.MouseLeave:Connect(function()
		ghostRow.BackgroundTransparency = 0.8
	end)

	addBtn.MouseEnter:Connect(function()
		addBtn.BackgroundTransparency = 0.1
	end)

	addBtn.MouseLeave:Connect(function()
		addBtn.BackgroundTransparency = 0.3
	end)

	return {
		Row = ghostRow,
		KeyInput = keyInput,
		ValueInput = valueInput,
		AddButton = addBtn,
	}
end

--- UI Helper ---
local UiHelper = {
	-- Primitives
	CreateCorner = CreateCorner,
	CreateStroke = CreateStroke,
	CreatePadding = CreatePadding,
	CreateListLayout = CreateListLayout,
	CreateSizeConstraint = CreateSizeConstraint,
	CreateFlexItem = CreateFlexItem,

	-- Helpers
	SetupTruncationToggle = SetupTruncationToggle,
	SetupAutoCanvasSize = SetupAutoCanvasSize,
	DestroyEntry = DestroyEntry,
	FindHeaderChild = FindHeaderChild,
	FindFooterChild = FindFooterChild,

	-- UI Components
	CreateHeader = CreateHeader,
	CreateFooter = CreateFooter,
	CreateViewerArea = CreateViewerArea,
	CreateTooltip = CreateTooltip,
	CreateGhostRow = CreateGhostRow,
}

return table.freeze(UiHelper)
