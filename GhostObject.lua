local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Helper Module
local Validator = require(ReplicatedStorage.Shared.PlacementValidator)

local GhostObject = {}
GhostObject.__index = GhostObject

-- CONSTANTS
local GRID_SIZE = 4
local TWEEN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local GHOST_TRANSPARENCY = 0.5

--------------------------------------------------------------------------------
-- HELPER: CALCULATE FOOTPRINT (Consolidated Logic)
--------------------------------------------------------------------------------
local function getFootprint(sizeData, rotation)
	local sizeX = sizeData.x
	local sizeZ = sizeData.y -- Default for Table/Vector2

	-- If Vector3, use Z for depth
	if typeof(sizeData) == "Vector3" then
		sizeX = sizeData.X
		sizeZ = sizeData.Z
	end

	-- Handle Rotation (Swap X/Z if 90 or 270 degrees)
	local rot = rotation or 0
	if math.abs(rot - 90) < 0.1 or math.abs(rot - 270) < 0.1 then
		sizeX, sizeZ = sizeZ, sizeX
	end

	return sizeX, sizeZ
end
--------------------------------------------------------------------------------

function GhostObject.new(template)
	local self = setmetatable({}, GhostObject)

	self.Template = template
	self.Rotation = 0
	self.CurrentGridPos = Vector3.new(0, 0, 0)
	self.IsValidPosition = false

	-- 1. Clone the Visual Model
	if template.Model then
		self.Model = template.Model:Clone()
		self.Model.Name = "Ghost_" .. template.Name

		-- Ensure PrimaryPart exists
		if not self.Model.PrimaryPart then
			self.Model.PrimaryPart = self.Model:FindFirstChild("Base") or self.Model:GetChildren()[1]
		end

		local primary = self.Model.PrimaryPart

		-- 2. SETUP GHOST VISUALS & WELDS
		for _, part in pairs(self.Model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CastShadow = false

				if part == primary then
					part.Transparency = 1 -- Hide PrimaryPart
					part.Anchored = true
				else
					part.Transparency = GHOST_TRANSPARENCY
					part.Material = Enum.Material.ForceField
					part.Anchored = false

					local weld = Instance.new("WeldConstraint")
					weld.Part0 = part
					weld.Part1 = primary
					weld.Parent = part
				end
			end
		end

		self.Model.Parent = workspace
	else
		warn("GhostObject: Template missing Model reference!")
	end

	return self
end

--------------------------------------------------------------------------------
-- CORE METHODS
--------------------------------------------------------------------------------

function GhostObject:Rotate()
	self.Rotation = (self.Rotation + 90) % 360
end

function GhostObject:Destroy()
	if self.activeTween then
		self.activeTween:Cancel()
	end
	if self.Model then
		self.Model:Destroy()
	end
	self.Model = nil
	self.Template = nil
end

function GhostObject:GetPlacementData()
	return {
		Position = {
			x = self.CurrentGridPos.X,
			y = self.CurrentGridPos.Y,
			z = self.CurrentGridPos.Z,
		},
		Rotation = self.Rotation,
	}
end

--------------------------------------------------------------------------------
-- LOGIC & MATH
--------------------------------------------------------------------------------

function GhostObject:IsValid(PlotObjSpace)
	if not PlotObjSpace then
		return true
	end

	local posData = {
		x = self.CurrentGridPos.X,
		y = self.CurrentGridPos.Y,
		z = self.CurrentGridPos.Z,
	}

	return Validator.isValid(PlotObjSpace, posData, self.Template.Size, self.Rotation, nil)
end

function GhostObject:UpdateVisuals(isValid)
	self.IsValidPosition = isValid
	local color = isValid and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)

	if self.Model then
		for _, instance in ipairs(self.Model:GetDescendants()) do
			if instance:IsA("BasePart") then
				instance.Color = color
			elseif instance:IsA("Texture") or instance:IsA("Decal") then
				instance.Color3 = color
			end
		end
	end
end

function GhostObject:_setCFrame(Plot)
	local plotBase = Plot.model.Base
	local plotSize = plotBase.Size

	-- 1. Origin at Corner of Plot Base
	local cornerCFrame = plotBase.CFrame * CFrame.new(-plotSize.X / 2, plotSize.Y / 2, -plotSize.Z / 2)

	-- 2. Basic Grid Centering
	local halfGrid = GRID_SIZE / 2

	-- [[ FIX ]]
	-- We removed the manual shiftX/shiftZ logic here.
	-- We now rely on CurrentGridPos being correct (calculated in Update).
	local offsetX = (self.CurrentGridPos.X * GRID_SIZE) + halfGrid
	local offsetZ = (self.CurrentGridPos.Z * GRID_SIZE) + halfGrid

	-- 3. Vertical Offset
	local offsetY = 0
	if self.Model.PrimaryPart then
		offsetY = self.Model.PrimaryPart.Size.Y / 2
	end

	-- 4. Target CFrame
	local targetCFrame = cornerCFrame
		* CFrame.new(offsetX, offsetY, offsetZ)
		* CFrame.Angles(0, math.rad(self.Rotation), 0)

	-- 5. Tween
	if self.activeTween then
		self.activeTween:Cancel()
	end
	self.activeTween = TweenService:Create(self.Model.PrimaryPart, TWEEN_INFO, { CFrame = targetCFrame })
	self.activeTween:Play()
end

function GhostObject:Update(mouseHitPosition, Plot, clientObjSpace)
	if not Plot or not self.Model or not self.Template or not mouseHitPosition then
		return
	end

	local plotBase = Plot.model.Base
	local plotSize = plotBase.Size

	-- 1. Convert to Plot-Local Space
	local relativePos = plotBase.CFrame:PointToObjectSpace(mouseHitPosition)
	local cornerRelativeX = relativePos.X + (plotSize.X / 2)
	local cornerRelativeZ = relativePos.Z + (plotSize.Z / 2)

	-- 2. Snap to Grid
	local gridX = math.clamp(math.floor((cornerRelativeX / GRID_SIZE) + 0.0001), 0, 9999)
	local gridZ = math.clamp(math.floor((cornerRelativeZ / GRID_SIZE) + 0.0001), 0, 9999)

	-- 3. Calculate Footprint & Shift
	local rSizeX, rSizeZ = getFootprint(self.Template.Size, self.Rotation)

	-- [[ NEW: LOGICAL SHIFT ]]
	-- We apply the shift to the GRID COORDINATES, not the CFrame.
	local shiftX, shiftZ = 0, 0
	local rot = math.floor(self.Rotation + 0.5)

	if rot == 90 then
		shiftZ = rSizeZ - 1
	elseif rot == 180 then
		shiftX = rSizeX - 1
		shiftZ = rSizeZ - 1
	elseif rot == 270 then
		shiftX = rSizeX - 1
	end

	-- 4. Clamp within Bounds
	-- We adjust the bounds based on the shift.
	-- If we are shifting +1, we can't be at the very end of the plot, or we'd go over.
	local maxGridX = (plotSize.X / GRID_SIZE) - rSizeX
	local maxGridZ = (plotSize.Z / GRID_SIZE) - rSizeZ

	-- Note: The logic below allows gridX to be 0, then adds the shift.
	-- This means if mouse is at 0, and shift is 1, final pos is 1. (Correct!)

	local clampedX = math.clamp(gridX, 0, maxGridX)
	local clampedZ = math.clamp(gridZ, 0, maxGridZ)

	-- 5. Apply Shift to Final Position
	local finalX = clampedX + shiftX
	local finalZ = clampedZ + shiftZ

	local newPos = Vector3.new(math.round(finalX), 0, math.round(finalZ))

	if newPos ~= self.CurrentGridPos or self._lastRotation ~= self.Rotation then
		self.CurrentGridPos = newPos
		self._lastRotation = self.Rotation

		self:_setCFrame(Plot)

		-- Pass the plotSize to the validtor now if you added bounds checking
		local valid = self:IsValid(clientObjSpace)
		self:UpdateVisuals(valid)
	end
end

return GhostObject
