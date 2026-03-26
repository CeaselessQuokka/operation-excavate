--!strict
local assets = (workspace :: any).Resources:QueryDescendants("Model") :: { Model }
for _, asset in assets do
	local parts = asset:QueryDescendants("BasePart")
	if parts[2] then
		local root = parts[1]
		for index = 2, #parts do
			local part = parts[index]
			local weld = Instance.new("WeldConstraint")
			weld.Name = `{root} -> {part}`
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
		end
	end
end
