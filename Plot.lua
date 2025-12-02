local Plot = {}
Plot.__index = Plot

local PlotTable = {}

-- TESTING --

local RESET_PLOT = false

-------------

-- SERVICES & MODULES
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Validator = require(ReplicatedStorage.Shared.PlacementValidator)

local Conveyor = require(ServerScriptService.Server.TycoonObjects.Conveyor)
local Spawner = require(ServerScriptService.Server.TycoonObjects.Spawner)
local Model = require(ServerScriptService.Server.TycoonObjects.Model)
local Collector = require(ServerScriptService.Server.TycoonObjects.Collector)

-- plot part cleanup settings
local CLEANUP_TAG = "TycoonDrop"
local MAX_STUCK_TIME = 5
local MIN_VELOCITY = 0.5
local PARTS_PER_FRAME = 30

local function StartGlobalCleanupLoop()
	local activeDrops = {}

	local function onDropAdded(drop)
		table.insert(activeDrops, drop)
	end

	local function onDropRemoved(drop)
		local index = table.find(activeDrops, drop)
		if index then
			table.remove(activeDrops, index)
		end
	end

	for _, drop in pairs(CollectionService:GetTagged(CLEANUP_TAG)) do
		onDropAdded(drop)
	end
	CollectionService:GetInstanceAddedSignal(CLEANUP_TAG):Connect(onDropAdded)
	CollectionService:GetInstanceRemovedSignal(CLEANUP_TAG):Connect(onDropRemoved)

	local currentIndex = 1

	RunService.Heartbeat:Connect(function()
		if #activeDrops == 0 then
			return
		end
		local processedCount = 0

		while processedCount < PARTS_PER_FRAME do
			processedCount += 1
			if currentIndex > #activeDrops then
				currentIndex = 1
			end
			local drop = activeDrops[currentIndex]
			if drop and drop.Parent and not drop:GetAttribute("IsFading") then
				local currentTime = workspace:GetServerTimeNow()
				if drop.AssemblyLinearVelocity.Magnitude > MIN_VELOCITY then
					drop:SetAttribute("LastMoved", currentTime)
				else
					local lastMoved = drop:GetAttribute("LastMoved") or currentTime

					if (currentTime - lastMoved) > MAX_STUCK_TIME then
						drop:SetAttribute("IsFading", true)
						if #activeDrops > 500 then
							drop:Destroy()
						else
							local tween = TweenService:Create(drop, TweenInfo.new(1), { Transparency = 1 })
							tween:Play()
							task.delay(1, function()
								if drop.Parent then
									drop:Destroy()
								end
							end)
						end
					end
				end
			end
			currentIndex += 1
		end
	end)
end

function Plot:Serialize()
	local saveData = {}

	-- Copy simple values
	saveData.number = self.number
	saveData.objSpace = self.objSpace or {}
	saveData.nextObjId = self.nextObjId

	-- Serialize the objects
	saveData.objects = {}
	for _, obj in ipairs(self.objects) do
		-- Assuming your objects (Conveyor, etc.) have a :Clean() or similar method
		-- that returns their saveable data structure.
		if obj.Clean then
			table.insert(saveData.objects, obj:Clean())
		else
			warn("Object missing Clean method:", obj)
		end
	end

	return saveData
end

function Plot.new(plotModel)
	local self = setmetatable({}, Plot)

	self.model = plotModel
	self.number = plotModel.Name

	if plotModel:FindFirstChild("Base") then
		self.BaseCFrame = plotModel.Base.CFrame
	else
		warn("Plot " .. self.number .. " has no Base!")
		self.BaseCFrame = CFrame.new(0, 0, 0)
	end

	self.isOccupied = false
	self.owner = nil

	self.objects = {}
	self.objSpace = {}

	table.insert(PlotTable, self)
	return self
end

function Plot.init()
	StartGlobalCleanupLoop()

	local plotsFolder = workspace:WaitForChild("Plots")

	for i, plot in pairs(plotsFolder:GetChildren()) do
		Plot.new(plot)
	end
	print("Plot System Initialized: Found " .. #PlotTable .. " plots.")
end

function Plot.ClaimFirstAvailablePlot(Player: Player, data)
	for i, plot in pairs(PlotTable) do
		if not plot.isOccupied then
			plot.isOccupied = true
			plot.owner = Player.Name

			plot.nextObjId = data.Plot.nextObjId or 1
			plot.objSpace = data.objSpace or {}

			for i, v in pairs(data.Plot.objects) do
				local savedId = v.id
				if savedId == 0 then
					savedId = nil
				end
				plot:placeObject(v, plot, savedId)
			end

			return plot
		end
	end
end

function Plot.getPlotFromPlayer(Player: Player)
	for i, plot in pairs(PlotTable) do
		if plot.owner == Player.Name then
			return plot
		end
	end
	return nil
end

function Plot:SyncObjectSpace(object)
	local id = object.id or self.nextObjId

	Validator.updateGrid(self.objSpace, object.Position, object.Size, object.Rotation, id)
end

function Plot:UnsyncObjectSpace(object)
	Validator.updateGrid(
		self.objSpace,
		object.Position,
		object.Size,
		object.Rotation,
		nil -- Passing nil removes the ID
	)
end

function Plot:Free()
	self.owner = nil

	for i, v in pairs(self.model.Objects:GetChildren()) do
		v:Destroy()
	end

	self.objects = {}

	self.nextObjId = 1

	self.isOccupied = false
	self.objSpace = {}
end

function Plot:checkValidPlacement(object)
	if not object or not object.Position then
		return false
	end

	return Validator.isValid(self.objSpace, object.Position, object.Size, object.Rotation, object.id)
end

function Plot:placeObject(Data, plot, i)
	if RESET_PLOT then -- DESTROY ENTIRE PLOT IF TRUE -- FOR TESTING
		warn("PLOT RESET WAS ACTIVATED.")
		self.nextObjId = 0
		return
	end

	local objectId = i
	if not objectId then
		self.nextObjId = self.nextObjId + 1
		objectId = self.nextObjId
	end

	local object
	local Type = Data.Type

	if Type == "Conveyor" then
		object = Conveyor.new(Data, self, objectId)
	elseif Type == "Spawner" then
		object = Spawner.new(Data, self, objectId)
	elseif Type == "Model" then
		object = Model.new(Data, self, objectId)
	elseif Type == "Collector" then
		object = Collector.new(Data, self, objectId)
	end

	if not self:checkValidPlacement(object) then
		if not i then
			self.nextObjId = self.nextObjId - 1
		end
		return false
	end

	self:SyncObjectSpace(object)

	table.insert(self.objects, object)
	object:Init(self)

	return object
end

return Plot
