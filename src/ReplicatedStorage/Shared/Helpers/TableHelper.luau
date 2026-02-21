--!strict
--- Types ---
export type TableLike = { [any]: any }

--- Table Helper ---
local TableHelper = {}

function TableHelper.ArrayToSet<T>(array: { T }): { [T]: boolean }
	local set: { [T]: boolean } = {}
	for _, key in array do
		set[key] = true
	end
	return set
end

function TableHelper.SetToArray<T>(set: { [T]: boolean }): { T }
	local array = {}
	for value in set do
		table.insert(array, value)
	end
	return array
end

function TableHelper.DeepClone<T>(tbl: T): T
	if typeof(tbl) ~= "table" then
		return tbl
	end

	local clone = {}
	for key, value in tbl do
		if typeof(value) == "table" then
			clone[key] = TableHelper.DeepClone(value)
		else
			clone[key] = value
		end
	end
	return (clone :: any) :: T
end

-- The "withTemplate" parameter must contain the whole options structure.
-- The "partial" parameter does not require this behavior. It can be, all, partial, or non-existent.
--- Note: options is a deep clone of "withTemplate" with "partial" values applied overtop.
function TableHelper.ReconcileOptions<P, T>(partial: P?, withTemplate: T): T
	local options = (TableHelper.DeepClone(withTemplate) :: any) :: T
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

function TableHelper.DeepMerge<T, U>(base: T, override: U): T & U
	if typeof(base) ~= "table" or typeof(override) ~= "table" then
		return override :: any
	end

	for key, value in override do
		if typeof(value) == "table" and typeof(base[key]) == "table" then
			base[key] = TableHelper.DeepMerge(base[key], value)
		else
			base[key] = value
		end
	end
	return base
end

return table.freeze(TableHelper)
