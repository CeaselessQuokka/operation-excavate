--!strict
local EncodingService = game:GetService("EncodingService")
--- Services ---

--- Imports ---

--- Types ---
export type MaterialMatrix = { { { Enum.Material } } } & { Size: Vector3 }
export type OccupancyMatrix = { { { number } } } & { Size: Vector3 }

--- Variables ---
local MATERIAL_LOOKUP = {
	WoodPlanks = 1,
	Basalt = 2,
	Slate = 3,
	CrackedLava = 4,
	Concrete = 5,
	Limestone = 6,
	Brick = 7,
	Cobblestone = 8,
	Rock = 9,
	Sandstone = 10,
	Grass = 11,
	LeafyGrass = 12,
	Sand = 13,
	Snow = 14,
	Mud = 15,
	Ground = 16,
	Asphalt = 17,
	Salt = 18,
	Ice = 19,
	Glacier = 20,
	Air = 21,
	Water = 22,
}

--- Functions ---

--- Terrain Serialization Helper ---
local TerrainSerializationHelper = {}

function TerrainSerializationHelper.SerializeMaterials(matrix: MaterialMatrix): buffer
	local serialSize = 100_000
	local serial = buffer.create(serialSize)
	local cursor = 0

	-- Serialize dimensions.
	buffer.writeu16(serial, cursor, matrix.Size.X)
	cursor += 2
	buffer.writeu16(serial, cursor, matrix.Size.Y)
	cursor += 2
	buffer.writeu16(serial, cursor, matrix.Size.Z)
	cursor += 2

	-- Serialize material data.
	for x = 1, matrix.Size.X do
		for y = 1, matrix.Size.Y do
			for z = 1, matrix.Size.Z do
				if cursor >= serialSize then
					print("Extending serial size")
					serialSize += 100_000
					local newSerial = buffer.create(serialSize)
					buffer.copy(newSerial, 0, serial)
					serial = newSerial
				end
				buffer.writeu8(serial, cursor, MATERIAL_LOOKUP[(matrix :: any)[x][y][z]])
				cursor += 1
			end
		end
	end

	-- Truncate serial.
	if cursor < serialSize then
		local newSerial = buffer.create(cursor)
		buffer.copy(newSerial, 0, serial)
		serial = newSerial
	end

	-- Compress serial.
	for level = 1, 22 do
		local start = os.clock()
		local compressed = EncodingService:CompressBuffer(serial, Enum.CompressionAlgorithm.Zstd, level)
		local finish = os.clock() - start
		local compressionRatio = buffer.len(serial) / buffer.len(compressed)
		print(
			`Compression level {level}: {("%.3f"):format(compressionRatio)}x compression, took {("%.6f"):format(finish)} seconds`
		)
	end
	-- return EncodingService:CompressBuffer(serial, Enum.CompressionAlgorithm.Zstd, 22)
end

return table.freeze(TerrainSerializationHelper)
