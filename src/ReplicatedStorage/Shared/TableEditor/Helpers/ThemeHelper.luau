--!strict
--[[
	Helper functions for applying Studio themes to UI elements.
	Note: Contains Studio-specific code. Remove if not needed.
]]

--- Imports ---
local AttributeHelper = require(script.Parent.AttributeHelper)

--- Variables ---
local STUDIO = settings().Studio

local STYLE_ENUM_ITEMS: { [string]: boolean } = {}
for _, item in pairs(Enum.StudioStyleGuideColor:GetEnumItems()) do
	STYLE_ENUM_ITEMS[item.Name] = true
end
table.freeze(STYLE_ENUM_ITEMS)

--- Theme Helper ---
local ThemeHelper = {
	OnThemeChanged = STUDIO.ThemeChanged,
}

function ThemeHelper.GetCurrentTheme(): StudioTheme
	return STUDIO.Theme :: StudioTheme
end

function ThemeHelper.GetColor(styleItem: Enum.StudioStyleGuideColor, modifier: Enum.StudioStyleGuideModifier?): Color3
	return ThemeHelper.GetCurrentTheme():GetColor(styleItem, modifier)
end

function ThemeHelper.ApplyTheme(root: Instance, theme: StudioTheme)
	local descendants = { root, table.unpack(root:GetDescendants()) }
	for _, instance in pairs(descendants) do
		for _, tag in pairs(instance:GetTags()) do
			if not STYLE_ENUM_ITEMS[tag] then
				continue
			end

			local propertiesToApplyTo: { string } = AttributeHelper.GetAsArray(instance, tag)
			if not propertiesToApplyTo[1] then
				warn(`No properties to apply to for "{tag}" on {instance:GetFullName()}`, instance)
				continue
			end

			for _, property in pairs(propertiesToApplyTo) do
				local success = pcall(function()
					local colorEnum = Enum.StudioStyleGuideColor:FromName(tag)
					assert(colorEnum, `Could not find Enum.StudioStyleGuideColor with name "{tag}"`)

					local descendant = instance :: any
					descendant[property] = theme:GetColor(colorEnum)
				end)
				if not success then
					warn(`Could not apply color of "{property}" to {instance:GetFullName()}`, instance)
				end
			end
		end
	end
end

function ThemeHelper.ApplyCurrentTheme(root: Instance)
	ThemeHelper.ApplyTheme(root, ThemeHelper.GetCurrentTheme())
end

return table.freeze(ThemeHelper)
