--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

--- Imports ---
local CameraHelper = require(ReplicatedStorage.Shared.Helpers.CameraHelper)
local Cleaner = require(ReplicatedStorage.Shared.Helpers.Cleaner)
local PlayerController = require(script.Parent.PlayerController)

--- Camera Controller ---
local CameraController = {
	CameraForward = Vector3.zAxis,
}

do -- Controller initialization.
	local cameraForward: Vector3 = Vector3.zAxis
	local cleaner = Cleaner.new()
	local function Cleanup()
		cleaner:Clean()
	end
	PlayerController.CharacterAdded(function(character)
		local MIN_ZOOM = 5
		local MAX_ZOOM = 2048
		local ZOOM_STEP = 10
		local SENSITIVITY = Vector2.new(1, 1) * math.rad(0.5)
		local MIN_PITCH = math.rad(-80)
		local MAX_PITCH = math.rad(80)
		local HEAD_OFFSET = Vector3.new(0, 1.5, 0) -- offset from HumanoidRootPart to head

		local camera = CameraHelper.GetCamera()
		local zoomLevel = 16
		local pitch = 0 -- vertical angle (radians), 0 = horizon
		local yawDelta = 0 -- accumulated mouse yaw since last frame
		local pitchDelta = 0 -- accumulated mouse pitch since last frame

		CameraHelper.SetScriptable()

		-- Accumulate mouse/touch delta for camera rotation.
		cleaner:Add(UserInputService.InputChanged:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end

			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
			then
				local delta = input.Delta
				yawDelta -= delta.X * SENSITIVITY.X
				pitchDelta -= delta.Y * SENSITIVITY.Y
			elseif input.UserInputType == Enum.UserInputType.Touch then
				local delta = input.Delta
				yawDelta -= delta.X * SENSITIVITY.X
				pitchDelta -= delta.Y * SENSITIVITY.Y
			end
		end))

		-- Zoom via scroll wheel.
		cleaner:Add(UserInputService.InputChanged:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				zoomLevel = math.clamp(zoomLevel - input.Position.Z * ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
			end
		end))

		-- Right-click hides cursor for look, like default camera.
		cleaner:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
			end
		end))
		cleaner:Add(UserInputService.InputEnded:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
		end))

		cleaner:Add(RunService.PreRender:Connect(function()
			if PlayerController.Character ~= character then
				return
			end

			local rootCF = character.HumanoidRootPart.CFrame
			local up = rootCF.Position.Unit -- surface normal on a sphere centered at origin
			local focusPoint = rootCF.Position + rootCF:VectorToWorldSpace(HEAD_OFFSET)

			-- Initialize camera forward from character look on first frame.
			if not cameraForward then
				local charLook = rootCF.LookVector
				local proj = charLook - up * charLook:Dot(up)
				if proj.Magnitude < 0.001 then
					proj = Vector3.xAxis:Cross(up)
					if proj.Magnitude < 0.001 then
						proj = Vector3.zAxis:Cross(up)
					end
				end
				cameraForward = proj.Unit
				CameraController.CameraForward = cameraForward
			else
				-- Re-project onto current tangent plane (up changes as we walk on the sphere).
				local proj = cameraForward - up * cameraForward:Dot(up)
				if proj.Magnitude < 0.001 then
					proj = Vector3.xAxis:Cross(up)
					if proj.Magnitude < 0.001 then
						proj = Vector3.zAxis:Cross(up)
					end
				end
				cameraForward = proj.Unit
				CameraController.CameraForward = cameraForward
			end

			-- Apply yaw delta: rotate cameraForward around the surface normal.
			if yawDelta ~= 0 then
				cameraForward = CFrame.fromAxisAngle(up, yawDelta):VectorToWorldSpace(cameraForward)
				CameraController.CameraForward = cameraForward
				yawDelta = 0
			end

			-- Apply pitch delta.
			if pitchDelta ~= 0 then
				pitch = math.clamp(pitch + pitchDelta, MIN_PITCH, MAX_PITCH)
				pitchDelta = 0
			end

			-- Build camera frame from the independent forward direction.
			local right = cameraForward:Cross(up).Unit
			local refFrame = CFrame.fromMatrix(focusPoint, right, up)

			-- Apply pitch (tilt up/down). Yaw is already baked into cameraForward.
			local rotated = refFrame * CFrame.Angles(pitch, 0, 0)

			-- Place camera behind the focus point along the rotated look direction.
			local cameraPos = focusPoint - rotated.LookVector * zoomLevel
			camera.CFrame = CFrame.lookAt(cameraPos, focusPoint, up)
			camera.Focus = CFrame.new(focusPoint)
		end))
	end)
	PlayerController.OnDied:Connect(Cleanup)
	PlayerController.Player.CharacterRemoving:Connect(Cleanup)
end

return CameraController
