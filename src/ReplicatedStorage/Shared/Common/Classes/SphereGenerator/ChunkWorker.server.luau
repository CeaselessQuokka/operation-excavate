--[[
	Parallel chunk generation worker for Actor-based multithreading.
	Runs inside Actor instances created by ParallelChunkScheduler.
	Does nothing when not parented under an Actor (safe as a template in ReplicatedStorage).

	Each Actor has an isolated Luau VM, so workers create their own PlanetGenerator
	instances via PlanetGenerator.new(). Construction runs serially (one worker at a time)
	to guarantee deterministic floating-point results identical to the main thread.
	Chunk generation runs in parallel via BindToMessageParallel.
]]

--!strict

local actor = script:GetActor()
if not actor then
	return
end

--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local PlanetGenerator = require(ReplicatedStorage.Shared.Common.Classes.SphereGenerator.PlanetGenerator)

--- Variables ---
local terrain = workspace.Terrain
local planet: PlanetGenerator.PlanetGenerator? = nil
local completionEvent: BindableEvent = actor:WaitForChild("ChunkCompleted") :: BindableEvent

--- Message Handlers ---

-- SetPlanet: creates a PlanetGenerator instance for this worker's VM.
-- Runs serially (BindToMessage) to guarantee deterministic floating-point results.
-- PlanetGenerator construction involves transcendental math (sin, cos, acos, atan2)
-- whose results can differ at the ULP level under parallel execution, causing the
-- derived grid dimensions to mismatch the main thread's and corrupting chunk mapping.
actor:BindToMessage("SetPlanet", function(masterSeed: number, chunkSize: number)
	planet = PlanetGenerator.new(masterSeed, chunkSize, true)
	actor:SetAttribute("Ready", true)
end)

-- GenerateChunk: runs voxel computation in parallel, then synchronizes for WriteVoxels.
actor:BindToMessageParallel("GenerateChunk", function(chunkIndex: number)
	local pg = planet :: PlanetGenerator.PlanetGenerator
	local chunkType, chunkSeed, hasContent, region = pg:_ComputeChunkData(chunkIndex)

	task.synchronize()

	if hasContent then
		terrain:WriteVoxels(region :: Region3, pg.Resolution, pg._reuseMats, pg._reuseOccs)
	end

	completionEvent:Fire(chunkIndex, chunkType, chunkSeed)
end)

-- Signal that all message handlers are bound and this worker is ready to receive messages.
actor:SetAttribute("Initialized", true)
