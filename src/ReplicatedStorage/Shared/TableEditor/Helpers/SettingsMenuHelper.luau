--!strict
--[[
	Helper module for creating settings menu UI components.
]]

--- Imports ---
local ColorPickerHelper = require(script.Parent.ColorPickerHelper)

--- Types ---
type Container = Frame | ScrollingFrame

--- Settings Menu Helper ---
local SettingsMenuHelper = {}

-- Create a toggle (checkbox-style) control
function SettingsMenuHelper.CreateToggle(
	container: Container,
	name: string,
	label: string,
	defaultValue: boolean,
	fontFace: Font,
	callback: (value: boolean) -> (),
	layoutOrder: number?
): Frame
	local toggleFrame = Instance.new("Frame")
	toggleFrame.Name = name .. "Toggle"
	toggleFrame.BackgroundTransparency = 1
	toggleFrame.Size = UDim2.new(1, 0, 0, 24)
	toggleFrame.LayoutOrder = layoutOrder or 0
	toggleFrame.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = toggleFrame

	local checkbox = Instance.new("TextButton")
	checkbox.Name = "Checkbox"
	checkbox.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	checkbox.BorderSizePixel = 0
	checkbox.Size = UDim2.new(0, 18, 0, 18)
	checkbox.Text = defaultValue and "✓" or ""
	checkbox.TextColor3 = Color3.fromRGB(255, 255, 255)
	checkbox.TextSize = 14
	checkbox.FontFace = fontFace
	checkbox.Parent = toggleFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = checkbox

	local labelText = Instance.new("TextLabel")
	labelText.Name = "Label"
	labelText.BackgroundTransparency = 1
	labelText.Size = UDim2.new(1, -26, 1, 0)
	labelText.Text = label
	labelText.TextColor3 = Color3.fromRGB(220, 220, 220)
	labelText.TextSize = 14
	labelText.FontFace = fontFace
	labelText.TextXAlignment = Enum.TextXAlignment.Left
	labelText.Parent = toggleFrame

	local isChecked = defaultValue
	checkbox.Activated:Connect(function()
		isChecked = not isChecked
		checkbox.Text = isChecked and "✓" or ""
		callback(isChecked)
	end)

	return toggleFrame
end

-- Create a button control
function SettingsMenuHelper.CreateButton(
	container: Container,
	name: string,
	label: string,
	fontFace: Font,
	callback: () -> ()
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name .. "Button"
	button.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
	button.BorderSizePixel = 0
	button.Size = UDim2.new(1, 0, 0, 28)
	button.Text = label
	button.TextColor3 = Color3.fromRGB(220, 220, 220)
	button.TextSize = 14
	button.FontFace = fontFace
	button.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = button

	button.Activated:Connect(callback)

	return button
end

-- Create a number input control
function SettingsMenuHelper.CreateNumberInput(
	container: Container,
	name: string,
	label: string,
	defaultValue: number,
	fontFace: Font,
	callback: (value: number) -> (),
	min: number?,
	max: number?
): Frame
	local inputFrame = Instance.new("Frame")
	inputFrame.Name = name .. "Input"
	inputFrame.BackgroundTransparency = 1
	inputFrame.Size = UDim2.new(1, 0, 0, 24)
	inputFrame.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = inputFrame

	local labelText = Instance.new("TextLabel")
	labelText.Name = "Label"
	labelText.BackgroundTransparency = 1
	labelText.Size = UDim2.new(0.6, 0, 1, 0)
	labelText.Text = label
	labelText.TextColor3 = Color3.fromRGB(220, 220, 220)
	labelText.TextSize = 14
	labelText.FontFace = fontFace
	labelText.TextXAlignment = Enum.TextXAlignment.Left
	labelText.Parent = inputFrame

	local textBox = Instance.new("TextBox")
	textBox.Name = "Value"
	textBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	textBox.BorderSizePixel = 0
	textBox.Size = UDim2.new(0.4, -8, 0, 20)
	textBox.Text = tostring(defaultValue)
	textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	textBox.TextSize = 14
	textBox.FontFace = fontFace
	textBox.ClearTextOnFocus = false
	textBox.Parent = inputFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = textBox

	textBox.FocusLost:Connect(function()
		local num = tonumber(textBox.Text)
		if num then
			if min and num < min then
				num = min
			end
			if max and num > max then
				num = max
			end
			textBox.Text = tostring(num)
			callback(num)
		else
			textBox.Text = tostring(defaultValue)
		end
	end)

	return inputFrame
end

-- Create a collapsible section header (returns content frame for adding children)
function SettingsMenuHelper.CreateCollapsibleSection(
	container: Container,
	name: string,
	label: string,
	defaultExpanded: boolean,
	fontFace: Font,
	layoutOrder: number?
): Frame
	local isExpanded = defaultExpanded

	local sectionFrame = Instance.new("Frame")
	sectionFrame.Name = name .. "Section"
	sectionFrame.BackgroundTransparency = 1
	sectionFrame.Size = UDim2.new(1, 0, 0, 0)
	sectionFrame.AutomaticSize = Enum.AutomaticSize.Y
	sectionFrame.LayoutOrder = layoutOrder or 0
	sectionFrame.Parent = container

	local sectionLayout = Instance.new("UIListLayout")
	sectionLayout.FillDirection = Enum.FillDirection.Vertical
	sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sectionLayout.Padding = UDim.new(0, 4)
	sectionLayout.Parent = sectionFrame

	local headerButton = Instance.new("TextButton")
	headerButton.Name = "Header"
	headerButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	headerButton.BorderSizePixel = 0
	headerButton.Size = UDim2.new(1, 0, 0, 26)
	headerButton.Text = (isExpanded and "▼ " or "▶ ") .. label
	headerButton.TextColor3 = Color3.fromRGB(200, 200, 200)
	headerButton.TextSize = 14
	headerButton.FontFace = fontFace
	headerButton.TextXAlignment = Enum.TextXAlignment.Left
	headerButton.LayoutOrder = 1
	headerButton.Parent = sectionFrame

	local headerPadding = Instance.new("UIPadding")
	headerPadding.PaddingLeft = UDim.new(0, 6)
	headerPadding.Parent = headerButton

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 4)
	headerCorner.Parent = headerButton

	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "Content"
	contentFrame.BackgroundTransparency = 1
	contentFrame.Size = UDim2.new(1, 0, 0, 0)
	contentFrame.AutomaticSize = Enum.AutomaticSize.Y
	contentFrame.Visible = isExpanded
	contentFrame.LayoutOrder = 2
	contentFrame.Parent = sectionFrame

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.FillDirection = Enum.FillDirection.Vertical
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, 4)
	contentLayout.Parent = contentFrame

	local contentPadding = Instance.new("UIPadding")
	contentPadding.PaddingLeft = UDim.new(0, 12)
	contentPadding.Parent = contentFrame

	headerButton.Activated:Connect(function()
		isExpanded = not isExpanded
		headerButton.Text = (isExpanded and "▼ " or "▶ ") .. label
		contentFrame.Visible = isExpanded
	end)

	return contentFrame
end

-- Create a separator line
function SettingsMenuHelper.CreateSeparator(container: Container, layoutOrder: number?): Frame
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	separator.BorderSizePixel = 0
	separator.Size = UDim2.new(1, 0, 0, 1)
	separator.LayoutOrder = layoutOrder or 0
	separator.Parent = container

	return separator
end

-- Create a section label (non-interactive text)
function SettingsMenuHelper.CreateSectionLabel(
	container: Container,
	name: string,
	text: string,
	fontFace: Font,
	layoutOrder: number?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name .. "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 20)
	label.Text = text
	label.TextColor3 = Color3.fromRGB(180, 180, 180)
	label.TextSize = 12
	label.FontFace = fontFace
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = layoutOrder or 0
	label.Parent = container

	return label
end

-- Create a cycle button (clicks through options)
function SettingsMenuHelper.CreateCycleButton(
	container: Container,
	name: string,
	label: string,
	options: { string },
	defaultIndex: number,
	fontFace: Font,
	callback: (index: number, value: string) -> ()
): Frame
	local cycleFrame = Instance.new("Frame")
	cycleFrame.Name = name .. "Cycle"
	cycleFrame.BackgroundTransparency = 1
	cycleFrame.Size = UDim2.new(1, 0, 0, 24)
	cycleFrame.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = cycleFrame

	local labelText = Instance.new("TextLabel")
	labelText.Name = "Label"
	labelText.BackgroundTransparency = 1
	labelText.Size = UDim2.new(0.5, 0, 1, 0)
	labelText.Text = label
	labelText.TextColor3 = Color3.fromRGB(220, 220, 220)
	labelText.TextSize = 14
	labelText.FontFace = fontFace
	labelText.TextXAlignment = Enum.TextXAlignment.Left
	labelText.Parent = cycleFrame

	local cycleButton = Instance.new("TextButton")
	cycleButton.Name = "CycleButton"
	cycleButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	cycleButton.BorderSizePixel = 0
	cycleButton.Size = UDim2.new(0.5, -8, 0, 20)
	cycleButton.Text = options[defaultIndex] or options[1]
	cycleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	cycleButton.TextSize = 12
	cycleButton.FontFace = fontFace
	cycleButton.TextTruncate = Enum.TextTruncate.AtEnd
	cycleButton.Parent = cycleFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = cycleButton

	local currentIndex = defaultIndex
	cycleButton.Activated:Connect(function()
		currentIndex = currentIndex % #options + 1
		cycleButton.Text = options[currentIndex]
		callback(currentIndex, options[currentIndex])
	end)

	return cycleFrame
end

-- Create a color picker control (color swatch button that opens picker)
function SettingsMenuHelper.CreateColorPicker(
	container: Container,
	name: string,
	label: string,
	defaultValue: Color3,
	fontFace: Font,
	callback: (value: Color3) -> (),
	pickerParent: GuiObject?
): Frame
	local colorFrame = Instance.new("Frame")
	colorFrame.Name = name .. "ColorPicker"
	colorFrame.BackgroundTransparency = 1
	colorFrame.Size = UDim2.new(1, 0, 0, 24)
	colorFrame.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = colorFrame

	local labelText = Instance.new("TextLabel")
	labelText.Name = "Label"
	labelText.BackgroundTransparency = 1
	labelText.Size = UDim2.new(0.6, 0, 1, 0)
	labelText.Text = label
	labelText.TextColor3 = Color3.fromRGB(220, 220, 220)
	labelText.TextSize = 14
	labelText.FontFace = fontFace
	labelText.TextXAlignment = Enum.TextXAlignment.Left
	labelText.Parent = colorFrame

	-- Color swatch button
	local swatchButton = Instance.new("TextButton")
	swatchButton.Name = "Swatch"
	swatchButton.BackgroundColor3 = defaultValue
	swatchButton.BorderSizePixel = 0
	swatchButton.Size = UDim2.new(0.4, -8, 0, 20)
	swatchButton.Text = ""
	swatchButton.AutoButtonColor = false
	swatchButton.Parent = colorFrame

	local swatchCorner = Instance.new("UICorner")
	swatchCorner.CornerRadius = UDim.new(0, 4)
	swatchCorner.Parent = swatchButton

	local swatchStroke = Instance.new("UIStroke")
	swatchStroke.Color = Color3.fromRGB(80, 80, 80)
	swatchStroke.Thickness = 1
	swatchStroke.Parent = swatchButton

	-- Hover effect
	swatchButton.MouseEnter:Connect(function()
		swatchStroke.Color = Color3.fromRGB(120, 120, 120)
	end)
	swatchButton.MouseLeave:Connect(function()
		swatchStroke.Color = Color3.fromRGB(80, 80, 80)
	end)

	-- Active picker reference for cleanup
	local activePicker: ColorPickerHelper.ColorPicker? = nil

	swatchButton.Activated:Connect(function()
		-- Close existing picker if open
		if activePicker then
			activePicker:Destroy()
			activePicker = nil
			return
		end

		-- Determine parent for picker
		local parent = pickerParent
		if not parent then
			-- Try to find a ScreenGui or suitable parent
			local current: Instance? = container
			while current do
				if current:IsA("ScreenGui") or current:IsA("SurfaceGui") or current:IsA("BillboardGui") then
					parent = current :: GuiObject
					break
				end
				current = current.Parent
			end
		end

		if not parent then
			return
		end

		-- Create color picker
		activePicker = ColorPickerHelper.new({
			Parent = parent,
			InitialColor = swatchButton.BackgroundColor3,
			Title = label,
			Size = UDim2.fromOffset(280, 380),
			Position = UDim2.fromScale(0.5, 0.5),
			ShowAlpha = false,
			ShowPresets = true,
			ShowHSVSliders = false,
			Theme = "Dark",
			OnColorChanged = function(color: Color3, _alpha: number)
				swatchButton.BackgroundColor3 = color
			end,
			OnConfirm = function(color: Color3, _alpha: number)
				swatchButton.BackgroundColor3 = color
				callback(color)
				if activePicker then
					activePicker:Destroy()
					activePicker = nil
				end
			end,
			OnCancel = function()
				swatchButton.BackgroundColor3 = defaultValue
				if activePicker then
					activePicker:Destroy()
					activePicker = nil
				end
			end,
		})
	end)

	return colorFrame
end

return table.freeze(SettingsMenuHelper)
