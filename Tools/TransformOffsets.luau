local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptEditorService = game:GetService("ScriptEditorService")

local ResourceOffets = require(ReplicatedStorage.Shared.Common.ResourceOffsets)

local RNG = Random.new()

local builder: { string } = {
	"return {",
}

local s = os.clock()
for index, offset in ResourceOffets do
	builder[index + 1] = `\tCFrame.new({CFrame.lookAlong(offset, RNG:NextUnitVector())}),`
end
print(os.clock() - s)
table.insert(builder, "}")
task.wait(1)

local s = os.clock()
local src = table.concat(builder, "\n")
print(os.clock() - s)
task.wait(1)
local s = os.clock()
ScriptEditorService:UpdateSourceAsync(workspace.Camera.NewOffsets, function()
	return table.concat(builder, "\n")
end)
print(os.clock() - s)
