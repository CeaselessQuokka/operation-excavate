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

export type Options = { [any]: any }
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
	return (clone :: any) :: T
end

-- The "withTemplate" parameter must contain the whole options structure.
-- The "partial" parameter does not require this behavior. It can be, all, partial, or non-existent.
--- Note: options is a deep clone of "withTemplate" with "partial" values applied overtop.
local function ReconcileOptions<P, T>(partial: P?, withTemplate: T): T
	local options = (DeepClone(withTemplate) :: any) :: T
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
	ApplyReconciliation((partial :: any) :: TableLike, (options :: any) :: TableLike)
	return options
end

local function ResolveSize(size: Size): Vector3
	if typeof(size) == "number" then
		return Vector3.new(size, size, size)
	else
		return size
	end
end

--- Debug Helper ---
local DebugHelper = {}

function DebugHelper.Box(cframe: CFrame, size: Size, options: Partial<ColorOptions>): BasePart
	local boxOptions = ReconcileOptions(options, DEFAULT_COLOR_OPTIONS)
	local centerPart = Instance.new("Part")
	centerPart.Anchored = true
	centerPart.CanCollide = false
	centerPart.CanTouch = false
	centerPart.CanQuery = false
	centerPart.CastShadow = false
	centerPart.Transparency = 0.5
	centerPart.Size = Vector3.one
	centerPart.CFrame = cframe
	local blockMesh = Instance.new("BlockMesh")
	blockMesh.Scale = ResolveSize(size)
	blockMesh.Parent = centerPart
	DebugHelper.ApplyPartOptions(centerPart, boxOptions :: Options)
	centerPart.Parent = Workspace.Terrain
	return centerPart
end

function DebugHelper.ApplyPartOptions(part: BasePart, options: Options)
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

return table.freeze(DebugHelper)
