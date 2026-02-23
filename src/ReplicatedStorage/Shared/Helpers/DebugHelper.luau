--[[
	A fairly versatile debug library that will help draw and render debug information.
--]]

--!strict
--- Services ---
local Workspace = game:GetService("Workspace")

--- Types ---
export type function Partial(t)
	if not t:is("table") then
		error("Can only call Partial on tables")
	end

	local newTable = types.newtable()
	for key, value in t:properties() do
		newTable:setproperty(key, types.optional(value.read))
	end
	return types.optional(newTable)
end

export type TableLike = { [any]: any }
export type Size = number | Vector3

export type Options = { Reuse: Instance? }
export type ColorOptions = {
	Color: Color3 | BrickColor,
}

--- Variables ---
local DEFAULT_COLOR_OPTIONS: ColorOptions = {
	Color = Color3.new(1, 0, 0),
}

--- Functions ---
local Cleaner = function()
	return setmetatable({ _items = {} }, {
		__call = function(self, item: any)
			if item ~= nil then
				table.insert(self._items, item)
			else
				for _, item in self._items :: any do
					if not pcall(function()
						item:Destroy()
					end) then
						if not pcall(function()
							item:Disconnect()
						end) then
							warn("Failed to clean up item:", item)
						end
					end
				end
				table.clear(self._items)
			end
			return item
		end,
	})
end

local function DeepClone<T>(tbl: T): T
	if typeof(tbl) ~= "table" then
		return tbl
	end

	local clone = {}
	for key, value in tbl :: any do
		if typeof(value) == "table" then
			clone[key] = DeepClone(value)
		else
			clone[key] = value
		end
	end
	return clone
end

-- The "withTemplate" parameter must contain the whole options structure.
-- The "partial" parameter does not require this behavior. It can be, all, partial, or non-existent.
--- Note: options is a deep clone of "withTemplate" with "partial" values applied overtop.
local function ReconcileOptions<P, T>(partial: P?, withTemplate: T): T
	local options = DeepClone(withTemplate)
	if partial == nil then
		return options
	end

	local function ApplyReconciliation(partialTable: TableLike, optionsTable: TableLike)
		for key, value in partialTable do
			if typeof(value) == "table" and typeof(optionsTable[key]) == "table" then
				ApplyReconciliation(value, optionsTable[key])
			else
				optionsTable[key] = value
			end
		end
	end
	ApplyReconciliation(partial, options)
	return options
end

local function ResolveSize(size: Size): Vector3
	return if typeof(size) == "number" then Vector3.new(size, size, size) else size
end

--- Debug Helper ---
local DebugHelper = {}

function DebugHelper.Box(cframe: CFrame, size: Size, options: Options & Partial<ColorOptions>): BasePart
	local boxOptions = ReconcileOptions(options, DEFAULT_COLOR_OPTIONS) :: Options & ColorOptions
	local centerPart: BasePart = boxOptions.Reuse :: BasePart
	if not centerPart then
		centerPart = Instance.new("Part")
		centerPart.Anchored = true
		centerPart.CanCollide = false
		centerPart.CanTouch = false
		centerPart.CanQuery = false
		centerPart.CastShadow = false
		centerPart.Transparency = 0.5
		centerPart.Size = Vector3.one
		local blockMesh = Instance.new("BlockMesh")
		blockMesh.Name = "DebugBlockMesh"
		blockMesh.Parent = centerPart
		centerPart.Parent = Workspace.Terrain
	end
	centerPart.CFrame = cframe
	DebugHelper.ApplyPartOptions(centerPart, boxOptions);
	(centerPart :: any).DebugBlockMesh.Scale = ResolveSize(size)
	return centerPart
end

function DebugHelper.ApplyPartOptions(part: BasePart, options: Options & ColorOptions)
	do -- Apply color options.
		local partColor: (Color3 | BrickColor)? = options.Color
		if partColor then
			if typeof(partColor) == "BrickColor" then
				part.BrickColor = partColor
			else
				part.Color = partColor
			end
		end
	end
end

do -- Colorscheme logic.
	local COLOR_SCHEMES: { { Color3 } } = table.freeze({
		table.freeze({
			Color3.fromRGB(230, 25, 25), -- Red
			Color3.fromRGB(25, 80, 230), -- Blue
			Color3.fromRGB(25, 200, 25), -- Green
			Color3.fromRGB(240, 220, 0), -- Yellow
			Color3.fromRGB(220, 0, 220), -- Magenta
		}),
		table.freeze({
			Color3.fromRGB(255, 182, 193), -- Pink
			Color3.fromRGB(137, 207, 240), -- Baby Blue
			Color3.fromRGB(152, 251, 152), -- Pale Green
			Color3.fromRGB(255, 253, 150), -- Pale Yellow
			Color3.fromRGB(200, 162, 200), -- Plum
		}),
		table.freeze({
			Color3.fromRGB(255, 0, 230), -- Hot Pink
			Color3.fromRGB(0, 255, 255), -- Cyan
			Color3.fromRGB(57, 255, 20), -- Neon Green
			Color3.fromRGB(255, 95, 0), -- Neon Orange
			Color3.fromRGB(155, 0, 255), -- Neon Purple
		}),
		table.freeze({
			Color3.fromRGB(185, 83, 27), -- Terracotta
			Color3.fromRGB(110, 120, 0), -- Olive
			Color3.fromRGB(80, 45, 20), -- Chocolate
			Color3.fromRGB(210, 185, 130), -- Sand
			Color3.fromRGB(100, 145, 75), -- Sage
		}),
		table.freeze({
			Color3.fromRGB(0, 30, 120), -- Deep Navy
			Color3.fromRGB(0, 150, 150), -- Teal
			Color3.fromRGB(50, 210, 210), -- Aqua
			Color3.fromRGB(110, 210, 170), -- Sea Foam
			Color3.fromRGB(255, 110, 74), -- Coral
		}),
		table.freeze({
			Color3.fromRGB(180, 0, 30), -- Deep Red
			Color3.fromRGB(255, 100, 0), -- Burnt Orange
			Color3.fromRGB(255, 200, 0), -- Gold
			Color3.fromRGB(255, 90, 120), -- Rose
			Color3.fromRGB(140, 30, 140), -- Plum
		}),
		table.freeze({
			Color3.fromRGB(224, 17, 95), -- Ruby
			Color3.fromRGB(0, 155, 72), -- Emerald
			Color3.fromRGB(15, 82, 186), -- Sapphire
			Color3.fromRGB(153, 102, 204), -- Amethyst
			Color3.fromRGB(255, 185, 15), -- Topaz
		}),
		table.freeze({
			Color3.fromRGB(255, 85, 160), -- Bubblegum
			Color3.fromRGB(64, 224, 208), -- Turquoise
			Color3.fromRGB(255, 240, 30), -- Lemon Drop
			Color3.fromRGB(80, 120, 255), -- Blueberry
			Color3.fromRGB(255, 150, 50), -- Tangerine
		}),
		table.freeze({
			Color3.fromRGB(1, 68, 33), -- Pine
			Color3.fromRGB(155, 170, 100), -- Moss
			Color3.fromRGB(120, 70, 30), -- Bark
			Color3.fromRGB(220, 175, 40), -- Goldenrod
			Color3.fromRGB(140, 30, 70), -- Berry
		}),
		table.freeze({
			Color3.fromRGB(200, 16, 16), -- Crimson
			Color3.fromRGB(230, 88, 25), -- Flame
			Color3.fromRGB(255, 155, 0), -- Bright Orange
			Color3.fromRGB(255, 225, 30), -- Solar Yellow
			Color3.fromRGB(255, 245, 180), -- Heat Glow
		}),
		table.freeze({
			Color3.fromRGB(70, 140, 210), -- Glacier
			Color3.fromRGB(170, 225, 250), -- Frost
			Color3.fromRGB(80, 180, 180), -- Arctic Teal
			Color3.fromRGB(165, 145, 210), -- Pale Lavender
			Color3.fromRGB(225, 238, 250), -- Snow
		}),
		table.freeze({
			Color3.fromRGB(252, 60, 100), -- Flamingo
			Color3.fromRGB(255, 170, 0), -- Mango
			Color3.fromRGB(0, 185, 80), -- Palm
			Color3.fromRGB(0, 145, 210), -- Lagoon
			Color3.fromRGB(190, 60, 190), -- Orchid
		}),
		table.freeze({
			Color3.fromRGB(200, 165, 0), -- Mustard
			Color3.fromRGB(160, 55, 10), -- Rust
			Color3.fromRGB(0, 110, 110), -- Retro Teal
			Color3.fromRGB(85, 110, 15), -- Avocado
			Color3.fromRGB(100, 10, 30), -- Maroon
		}),
		table.freeze({
			Color3.fromRGB(255, 200, 0), -- Crown Gold
			Color3.fromRGB(72, 0, 120), -- Royal Purple
			Color3.fromRGB(0, 30, 100), -- Royal Navy
			Color3.fromRGB(180, 12, 30), -- Crimson
			Color3.fromRGB(240, 230, 200), -- Ivory
		}),
		table.freeze({
			Color3.fromRGB(255, 0, 110), -- Cyber Pink
			Color3.fromRGB(0, 180, 255), -- Electric Blue
			Color3.fromRGB(170, 255, 0), -- Acid Green
			Color3.fromRGB(255, 60, 0), -- Digital Red
			Color3.fromRGB(100, 0, 200), -- Deep Violet
		}),
		table.freeze({
			Color3.fromRGB(240, 240, 240), -- White
			Color3.fromRGB(180, 180, 180), -- Light Gray
			Color3.fromRGB(120, 120, 120), -- Medium Gray
			Color3.fromRGB(60, 60, 60), -- Dark Gray
			Color3.fromRGB(20, 20, 20), -- Near Black
		}),
	})
	local N_SCHEMES = #COLOR_SCHEMES
	function DebugHelper.GetColorScheme(index: number?): { Color3 }
		return if index then COLOR_SCHEMES[((index - 1) % N_SCHEMES) + 1] else COLOR_SCHEMES[1]
	end
end

return table.freeze(DebugHelper)
