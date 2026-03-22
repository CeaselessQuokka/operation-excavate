--!strict
--- Services ---
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

--- Imports ---
-- local Jabby = require(ReplicatedStorage.Packages.Jabby)

local TableEditor = require(ReplicatedStorage.Shared.TableEditor) -- Keep for debugging purposes; needed to hook up client connections.

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

-- Setup Jabby.
-- local client = Jabby.obtain_client()
-- local function create_widget(_, state: Enum.UserInputState)
-- 	if state == Enum.UserInputState.Begin then
-- 		client.spawn_app(client.apps.home, nil)
-- 	end
-- end
-- ContextActionService:BindAction("JecsDebugger", create_widget, false, Enum.KeyCode.F4)

-- Jabby.register({
-- 	applet = Jabby.applets.world,
-- 	name = "Client",
-- 	configuration = {
-- 		world = JecsCommon.World,
-- 	},
-- })
