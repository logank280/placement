local PlacementValidator = {}

function PlacementValidator.getFootprint(sizeData, rotation)
	local sizeX = sizeData.x
	local sizeZ = sizeData.z
	local sizeY = 1

	local rot = rotation or 0

	-- Handle rotation swapping
	if math.abs(rot - 90) < 0.1 or math.abs(rot - 270) < 0.1 then
		sizeX, sizeZ = sizeZ, sizeX
	end

	return math.round(sizeX), math.round(sizeY), math.round(sizeZ)
end

-- [[ HELPER: Calculates the Bottom-Left corner based on rotation ]] --
local function getScanningOrigin(px, pz, sizeX, sizeZ, rotation)
	local rot = rotation or 0

	-- Based on your GhostObject logic:
	-- 90 deg: Extends Negative Z -> Shift Z back
	-- 180 deg: Extends Negative X & Z -> Shift X and Z back
	-- 270 deg: Extends Negative X -> Shift X back

	if math.abs(rot - 90) < 0.1 then
		pz = pz - sizeZ + 1
	elseif math.abs(rot - 180) < 0.1 then
		px = px - sizeX + 1
		pz = pz - sizeZ + 1
	elseif math.abs(rot - 270) < 0.1 then
		px = px - sizeX + 1
	end

	return px, pz
end

-- Assume you pass PLOT_SIZE (e.g., 100 tiles) to isValid
function PlacementValidator.isValid(objSpace, positionData, sizeData, rotation, ignoreId, plotSizeX, plotSizeZ)
	local px = positionData.x
	local py = positionData.y
	local pz = positionData.z

	local sizeX, sizeY, sizeZ = PlacementValidator.getFootprint(sizeData, rotation)
	px, pz = getScanningOrigin(px, pz, sizeX, sizeZ, rotation)

	local maxGridX = (plotSizeX or 100) - 1
	local maxGridZ = (plotSizeZ or 100) - 1

	for cx = px, px + sizeX - 1 do
		for cy = py, py + sizeY - 1 do
			for cz = pz, pz + sizeZ - 1 do
				--if cx < 0 or cx > maxGridX or cz < 0 or cz > maxGridZ then
				--	return false
				--end

				-- Check collision
				if objSpace[cx] and objSpace[cx][cy] and objSpace[cx][cy][cz] then
					local occupiedById = objSpace[cx][cy][cz]
					if occupiedById ~= ignoreId then
						return false
					end
				end
			end
		end
	end

	return true
end

function PlacementValidator.updateGrid(objSpace, positionData, sizeData, rotation, id)
	local px = positionData.x
	local py = positionData.y
	local pz = positionData.z

	local sizeX, sizeY, sizeZ = PlacementValidator.getFootprint(sizeData, rotation)

	-- [[ FIX: Shift Start Point ]]
	-- Must apply the same shift here so we save data to the correct tiles!
	px, pz = getScanningOrigin(px, pz, sizeX, sizeZ, rotation)

	for cx = px, px + sizeX - 1 do
		if not objSpace[cx] then
			objSpace[cx] = {}
		end
		for cy = py, py + sizeY - 1 do
			if not objSpace[cx][cy] then
				objSpace[cx][cy] = {}
			end
			for cz = pz, pz + sizeZ - 1 do
				objSpace[cx][cy][cz] = id
			end
		end
	end
end

return PlacementValidator
