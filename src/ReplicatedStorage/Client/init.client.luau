--!strict
--- Services ---
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

--- Imports ---
local Knit = require(ReplicatedStorage.Packages.Knit)

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)
local LoadingHelper = require(ReplicatedStorage.Shared.Helpers.LoadingHelper)
local Remote = require(ReplicatedStorage.Shared.Common.Classes.Remote)

-- Keep so the client connections can be made.
local TableEditor = require(ReplicatedStorage.Shared.TableEditor)

--- Client Initialization ---
-- Load Knit controllers.
LoadingHelper.LoadModules(script.Controllers)
LoadingHelper.LoadModules(script.Systems)
LoadingHelper.LoadModules(ReplicatedStorage.Shared.Systems, true)
Knit.Start({ ServicePromises = false }):expect()

-- Load client and shared components.
LoadingHelper.LoadModules(script.Components)
LoadingHelper.LoadModules(ReplicatedStorage.Shared.Components)

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
while true do
	TableEditor.View("[Client] Jecs World", { World = JecsCommon.World })
	task.wait(1)
end
