--!strict
local assets = (workspace :: any).Resources:QueryDescendants("Model") :: { Model }
table.sort(assets, function(a, b)
	return (a:GetAttribute("ResourceTypeId") :: number) < (b:GetAttribute("ResourceTypeId") :: number)
end)

local rows = math.floor(math.sqrt(#assets))
local z = 0
for index, asset in assets do
	print(asset, ((index - 1) % rows), z)
	asset:PivotTo(CFrame.new(((index - 1) % rows) * 24, 16500, z * 24))
	if index % rows == 0 then
		z += 1
	end
end
