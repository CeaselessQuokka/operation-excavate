--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

--- Imports ---
local TableEditor = require(ReplicatedStorage.Shared.TableEditor)

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)
local LoadingHelper = require(ReplicatedStorage.Shared.Helpers.LoadingHelper)
local Remote = require(ReplicatedStorage.Shared.Common.Classes.Remote)

--- Client Initialization ---
LoadingHelper.LoadModules(script.Controllers)
LoadingHelper.LoadModules(script.Systems)
LoadingHelper.LoadModules(ReplicatedStorage.Shared.Systems, true)

-- Register custom reset action.
local onResetRequestedRemote = Remote.Event("OnResetRequested") :: Remote.ClientApi<()>
local resetBindable = Instance.new("BindableEvent")
resetBindable.Event:Connect(function()
	local humanoid = CharacterHelper.GetHumanoid(Players.LocalPlayer)
	if humanoid then
		humanoid.EvaluateStateMachine = true
	end
	onResetRequestedRemote:Fire()
end)
while true do
	if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", resetBindable) then
		break
	end
	task.wait(1)
end

-- Jecs world viewer.
while true do
	TableEditor.View("[Client] Jecs World", { World = JecsCommon.World })
	task.wait(2.5)
end
