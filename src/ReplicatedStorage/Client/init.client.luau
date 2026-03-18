--!strict
--- Services ---
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterGui = game:GetService("StarterGui")

--- Imports ---
local Jabby = require(ReplicatedStorage.Packages.Jabby)
local Knit = require(ReplicatedStorage.Packages.Knit)

local PlayerService: typeof(require(ServerScriptService.Server.Services.PlayerService).Client)

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local LoadingHelper = require(ReplicatedStorage.Shared.Helpers.LoadingHelper)

local TableEditor = require(ReplicatedStorage.Shared.TableEditor) -- Keep so the client connections can be made

--- Client Initialization ---
-- Load Knit controllers.
LoadingHelper.LoadModules(script.Controllers)
LoadingHelper.LoadModules(script.Systems)
LoadingHelper.LoadModules(ReplicatedStorage.Shared.Systems, true)
Knit.Start({ ServicePromises = false }):expect()

-- Load client and shared components.
LoadingHelper.LoadModules(script.Components)
LoadingHelper.LoadModules(ReplicatedStorage.Shared.Components)

-- Setup Jabby.
local client = Jabby.obtain_client()
local function create_widget(_, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin then
		return
	end
	client.spawn_app(client.apps.home, nil)
end
ContextActionService:BindAction("Open Jabby Home", create_widget, false, Enum.KeyCode.F4)

-- Register custom reset action.
PlayerService = Knit.GetService("PlayerService")
local resetBindable = Instance.new("BindableEvent")
resetBindable.Event:Connect(function()
	local humanoid = CharacterHelper.GetHumanoid(Players.LocalPlayer)
	if humanoid then
		humanoid.EvaluateStateMachine = true
	end
	PlayerService.OnResetRequested:Fire()
end)
while true do
	if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", resetBindable) then
		break
	end
	task.wait(1)
end
