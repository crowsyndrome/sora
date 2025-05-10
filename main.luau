--[[
	Sora - Lightweight and extensible Roblox utility
	https://github.com/crowsyndrome/sora
]]

if not game:IsLoaded() then
	game.Loaded:Wait()
end

if getgenv().SORA_LOADED then
	warn("Sora already loaded. Please unload first")
	return
end

getgenv().SORA_LOADED = true

local start = tick()
local Sora = {
	keys = {
		prefix = "Quote",
		teleport = "LeftAlt",
		boost = "C",
		extra_boost = "LeftControl",
	},
	customization = {
		accent = { 131, 195, 248 },
		notificationSound = "rbxassetid://89087762338808",
		bootSound = "rbxassetid://136242004757394",
		font = "rbxasset://fonts/families/SourceSansPro.json",
		notificationLength = 5,
	},
	features = {
		bootSoundEnabled = true,
		notificationSoundEnabled = true,
		notificationVolume = 0.4,
		notifyJoin = true,
		notifyLeave = true,
		notifyRejoin = true,
		clickTeleport = true,
		boost = true,
		boostSpeed = 125,
		boostExtraSpeed = 250,
		enhancedDisplays = false,
	},
}

local Services = setmetatable({}, {
	__index = function(self, serviceName)
		local service = cloneref(game:GetService(serviceName))

		rawset(self, serviceName, service)

		return service
	end,
})

local VoiceChatInternal = Services.VoiceChatInternal
local UserInputService = Services.UserInputService
local TeleportService = Services.TeleportService
local TweenService = Services.TweenService
local HttpService = Services.HttpService
local RunService = Services.RunService
local Players = Services.Players

local Player = Players.LocalPlayer
local currentCharacter, currentHumanoid, currentRoot

local sleep, delay, newThread
do
	sleep = task.wait
	delay = task.delay
	newThread = task.spawn
end

local insert, remove, concat, tFind, sort, clear
do
	insert = table.insert
	remove = table.remove
	concat = table.concat
	tFind = table.find
	sort = table.sort
	clear = table.clear
end

local format, match, find, split, lower
do
	format = string.format
	match = string.match
	find = string.find
	split = string.split
	lower = string.lower
end

local random, floor, round, clamp, max, rad
do
	random = math.random
	floor = math.floor
	round = math.round
	clamp = math.clamp
	max = math.max
	rad = math.rad
end

local newUDim2, newCFrame, newVector3, newVector2, newAngles
do
	newUDim2 = UDim2.new
	newCFrame = CFrame.new
	newVector3 = Vector3.new
	newVector2 = Vector2.new
	newAngles = CFrame.Angles
end

local queue_on_teleport = queue_on_teleport or function() end
local cloneref = cloneref or function(o)
	return o
end

local Profile = {}
Profile.__index = Profile
do
	local PROFILE_FOLDER = "sora"
	if not isfolder(PROFILE_FOLDER) then
		makefolder(PROFILE_FOLDER)
	end

	-- Deep-merge defaults into data
	local function deepMerge(defaults, data)
		for k, v in defaults do
			if type(v) == "table" then
				if type(data[k]) ~= "table" then
					data[k] = {}
				end

				deepMerge(v, data[k])
			else
				if data[k] == nil then
					data[k] = v
				end
			end
		end
	end

	-- Split a dot-separated key into parts
	local function splitKey(key)
		local parts = {}
		for part in string.gmatch(key, "([^.]+)") do
			insert(parts, part)
		end
		return parts
	end

	-- Get nested table and key
	local function getContainer(tbl, parts)
		local current = tbl
		for i = 1, #parts - 1 do
			local part = parts[i]
			if type(current[part]) ~= "table" then
				return nil, parts[#parts]
			end

			current = current[part]
		end

		return current, parts[#parts]
	end

	function Profile.new(name, defaults)
		local path = PROFILE_FOLDER .. "/" .. name .. ".json"
		local data = {}

		if isfile(path) then
			local raw = readfile(path)
			local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
			if ok and type(decoded) == "table" then
				data = decoded
			else
				warn(("Profile '%s': failed to decode JSON, re-initializing defaults"):format(name))
			end
		end

		deepMerge(defaults, data)

		if not isfile(path) then
			writefile(path, HttpService:JSONEncode(data))
		end

		local self = setmetatable({
			name = name,
			path = path,
			data = data,
			defaults = defaults,
		}, Profile)

		return self
	end

	function Profile:get(key)
		if type(key) == "string" and string.find(key, "%.") then
			local parts = splitKey(key)
			local tbl = self.data
			for _, part in parts do
				if type(tbl) ~= "table" then
					return nil
				end

				tbl = tbl[part]
			end

			return tbl
		else
			return self.data[key]
		end
	end

	function Profile:set(key, value)
		if type(key) == "string" and string.find(key, "%.") then
			local parts = splitKey(key)
			local container, lastKey = getContainer(self.data, parts)
			if not container then
				error(("Profile '%s': cannot set nested key '%s' - path invalid"):format(self.name, key))
			end
			container[lastKey] = value
		else
			self.data[key] = value
		end
		self:save()
	end

	function Profile:save()
		local ok, err = pcall(function()
			writefile(self.path, HttpService:JSONEncode(self.data))
		end)

		if not ok then
			error(("Profile '%s': failed to save: %s"):format(self.name, tostring(err)))
		end
	end

	function Profile:reload()
		if not isfile(self.path) then
			warn(("Profile '%s': file does not exist, skipping reload"):format(self.name))
			return
		end

		local raw = readfile(self.path)
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(decoded) == "table" then
			self.data = decoded
		else
			warn(("Profile '%s': failed to decode on reload, keeping current data"):format(self.name))
		end
	end

	function Profile:reset()
		self.data = {}
		deepMerge(self.defaults, self.data)
		self:save()
	end
end

local settings = Profile.new("settings", Sora)
local accentColor = Color3.fromRGB(unpack(settings:get("customization.accent")))

local function getSettingKeyCode(keycode)
	return Enum.KeyCode[settings:get("keys")[keycode]]
end

local function animate(object, speed, easingStyle, properties, easingDirection)
	local actualEasingDirection = Enum.EasingDirection[easingDirection] or Enum.EasingDirection.Out

	local info = TweenInfo.new(speed, Enum.EasingStyle[easingStyle], actualEasingDirection)

	local tween = TweenService:Create(object, info, properties)
	tween:Play()

	return tween
end

local colors = {
	red = Color3.fromRGB(255, 108, 108),
	green = Color3.fromRGB(127, 255, 127),
	blue = Color3.fromRGB(127, 127, 255),
	yellow = Color3.fromRGB(255, 255, 127),
	cyan = Color3.fromRGB(127, 255, 255),
	magenta = Color3.fromRGB(255, 127, 255),
	white = Color3.fromRGB(255, 255, 255),
	black = Color3.fromRGB(39, 39, 39),
}

local color = {}
do
	local function wrap(colorValue, text)
		local r = floor(colorValue.R * 255 + 0.5)
		local g = floor(colorValue.G * 255 + 0.5)
		local b = floor(colorValue.B * 255 + 0.5)

		return ('<font color="rgb(%d,%d,%d)">%s</font>'):format(r, g, b, text)
	end

	function color.italic(text)
		return "<i>" .. text .. "</i>"
	end

	for name, color3Value in colors do
		color[name] = function(text)
			return wrap(color3Value, text)
		end
	end
end

local function lightenRGB(color3, points)
	local r = color3.R * 255
	local g = color3.G * 255
	local b = color3.B * 255

	r = clamp(r + points, 0, 255)
	g = clamp(g + points, 0, 255)
	b = clamp(b + points, 0, 255)

	return Color3.fromRGB(r, g, b)
end

local function darkenRGB(color3, points)
	return lightenRGB(color3, -points)
end

local function create(className, name, properties)
	local instance = Instance.new(className)
	instance.Name = name

	for property, value in properties do
		instance[property] = value
	end

	return instance
end

local managedConnections = {}

local function addConnection(rbxSignal, callback)
	local connection = rbxSignal:Connect(callback)

	insert(managedConnections, connection)

	return connection
end

local function disconnectAllManagedConnections()
	for _, connection in managedConnections do
		if connection and connection.Connected then
			pcall(function()
				connection:Disconnect()
			end)
		end
	end

	managedConnections = {}
end

local function httpGetJson(url)
	local ok, raw = pcall(game.HttpGet, game, url)
	if not ok then
		return nil
	end

	local okDecode, data = pcall(HttpService.JSONDecode, HttpService, raw)
	return okDecode and data or nil
end

local function fetchServers()
	local servers = {}

	local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
	local body = httpGetJson(url)

	if typeof(body) == "table" and typeof(body.data) == "table" then
		for _, server in body.data do
			if type(server) == "table" and server.playing < server.maxPlayers then
				insert(servers, {
					id = server.id,
					ping = server.ping,
					players = server.playing,
					maxPlayers = server.maxPlayers,
				})
			end
		end
	end

	return servers
end

local function onCharacterAdded(character)
	currentCharacter = character or Player.CharacterAdded:Wait()
	currentHumanoid = currentCharacter:WaitForChild("Humanoid", 5)
	currentRoot = currentCharacter:WaitForChild("HumanoidRootPart", 5)
end

Player.CharacterAdded:Connect(onCharacterAdded)

onCharacterAdded(Player.Character)

-- MARK: Interface
local provider = get_hidden_gui or gethui
local hiddenParent = provider and provider() or cloneref(game:GetService("CoreGui"))

local holder = create("ScreenGui", Services.HttpService:GenerateGUID(), {
	Parent = hiddenParent,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local notifHolder = create("ScreenGui", Services.HttpService:GenerateGUID(), {
	Parent = hiddenParent,
	ZIndexBehavior = Enum.ZIndexBehavior.Global,
})

local fadeInTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local fadeOutTweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local shiftTweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local activeNotifications = {}

local NOTIFICATION_HEIGHT = 50
local NOTIFICATION_GAP = 5
local BASE_Y_OFFSET = -125
local START_Y_OFFSET_DELTA = -10

local function removeNotificationRecord(instanceToRemove)
	for i = #activeNotifications, 1, -1 do
		if activeNotifications[i].instance == instanceToRemove then
			remove(activeNotifications, i)
			break
		end
	end
end

local function notify(...)
	local args = { ... }
	local stringArgs = {}
	for i, v in args do
		stringArgs[i] = tostring(v)
	end
	local notificationText = concat(stringArgs, " ")

	local shiftAmount = NOTIFICATION_HEIGHT + NOTIFICATION_GAP
	for _, data in activeNotifications do
		local existingNotification = data.instance
		if existingNotification and existingNotification.Parent then
			local newTargetY = data.targetY - shiftAmount
			data.targetY = newTargetY
			animate(
				existingNotification,
				shiftTweenInfo.Time,
				shiftTweenInfo.EasingStyle.Name,
				{ Position = newUDim2(0.5, 0, 1, newTargetY) },
				shiftTweenInfo.EasingDirection.Name
			)
		end
	end

	local targetY = BASE_Y_OFFSET
	local startY = targetY - START_Y_OFFSET_DELTA
	local startPosition = newUDim2(0.5, 0, 1, startY)
	local endPosition = newUDim2(0.5, 0, 1, targetY)
	local finalImgTrans = 0.5

	if settings:get("features.notificationSoundEnabled") then
		local Sound = create("Sound", "Sound", {
			RollOffMode = Enum.RollOffMode.InverseTapered,
			SoundId = settings:get("customization.notificationSound"),
			Parent = Player.Character,
			Volume = settings:get("features.notificationVolume"),
		})

		Services.Debris:AddItem(Sound, 10)
		Sound:Play()
	end

	local notifTitle = create("TextLabel", "Title", {
		FontFace = Font.new(settings:get("customization.font")),
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeColor3 = Color3.new(0.141, 0.141, 0.141),
		Text = notificationText,
		BackgroundTransparency = 1,
		AnchorPoint = newVector2(0.5, 1),
		BorderSizePixel = 0,
		Position = startPosition,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextSize = 22,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		RichText = true,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = newUDim2(0, 0, 0, NOTIFICATION_HEIGHT),
	})

	notifTitle.Parent = notifHolder
	notifTitle.ZIndex = #activeNotifications + 1

	local imageLabel = create("ImageLabel", "ImageLabel", {
		Image = "rbxassetid://8992230903",
		ImageColor3 = Color3.new(),
		ImageTransparency = 1,
		BackgroundTransparency = 1,
		AnchorPoint = newVector2(0.5, 0),
		Position = newUDim2(1, 0, 4, -200),
		Size = newUDim2(2, 0, 0, 80),
		ZIndex = -1,
		BorderSizePixel = 0,
	})

	imageLabel.Parent = notifTitle

	insert(activeNotifications, { instance = notifTitle, targetY = targetY })

	animate(notifTitle, fadeInTweenInfo.Time, fadeInTweenInfo.EasingStyle.Name, {
		Position = endPosition,
		TextTransparency = 0,
		TextStrokeTransparency = 0,
	}, fadeInTweenInfo.EasingDirection.Name)

	animate(
		imageLabel,
		fadeInTweenInfo.Time,
		fadeInTweenInfo.EasingStyle.Name,
		{ ImageTransparency = finalImgTrans },
		fadeInTweenInfo.EasingDirection.Name
	)

	delay(settings:get("customization.notificationLength"), function()
		if notifTitle and notifTitle.Parent then
			local fadeOutTween = animate(notifTitle, fadeOutTweenInfo.Time, fadeOutTweenInfo.EasingStyle.Name, {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
				TextSize = 19,
			}, fadeOutTweenInfo.EasingDirection.Name)

			animate(
				imageLabel,
				fadeOutTweenInfo.Time,
				fadeOutTweenInfo.EasingStyle.Name,
				{ ImageTransparency = 1 },
				fadeOutTweenInfo.EasingDirection.Name
			)

			fadeOutTween.Completed:Wait()
			removeNotificationRecord(notifTitle)

			if notifTitle.Parent then
				notifTitle:Destroy()
			end
		else
			removeNotificationRecord(notifTitle)
		end
	end)
end

local orbiting = false
local EDGE_MARGIN = 8
local MIN_SIZE = newVector2(120, 80)

local SWAY_FACTOR = 0.2 -- How much sway per pixel/sec of mouse movement
local MAX_SWAY_ANGLE = 25 -- Maximum degrees of sway
local SWAY_RETURN_SPEED = 8 -- How quickly it returns to 0 rotation (higher is faster)

local function makeDraggable(guiObject)
	local screenGui = guiObject:FindFirstAncestorWhichIsA("ScreenGui")
	if not screenGui then
		warn("makeDraggable: guiObject is not a descendant of a ScreenGui!")
		return
	end

	local function toV2(input)
		return newVector2(input.Position.X, input.Position.Y)
	end

	local function topLeftToUDim(topLeft, size, anchor)
		local anchorPos = topLeft + size * anchor
		return UDim2.fromOffset(anchorPos.X, anchorPos.Y)
	end

	local function hitTestEdges(cursor)
		local guiPos = guiObject.AbsolutePosition
		local guiSize = guiObject.AbsoluteSize
		local rel = cursor - guiPos

		local hitL = rel.X <= EDGE_MARGIN
		local hitR = rel.X >= guiSize.X - EDGE_MARGIN
		local hitT = rel.Y <= EDGE_MARGIN
		local hitB = rel.Y >= guiSize.Y - EDGE_MARGIN

		if hitL or hitR or hitT or hitB then
			return { L = hitL, R = hitR, T = hitT, B = hitB }
		end
		return nil
	end

	local dragging = false
	local resizing = false
	local resizeEdges = nil
	local startCursor = Vector2.zero
	local startTopLeft = Vector2.zero
	local startSize = Vector2.zero

	local lastMouseX = 0
	local targetSwayAngle = 0
	local currentSwayAngle = 0

	guiObject.InputBegan:Connect(function(input)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		local cursor = toV2(input)
		local edgesHit = hitTestEdges(cursor)

		startCursor = cursor
		startTopLeft = guiObject.AbsolutePosition
		startSize = guiObject.AbsoluteSize

		if edgesHit then
			resizing = true
			resizeEdges = edgesHit
		else
			dragging = true
			lastMouseX = cursor.X
		end

		local inputChangedConnection
		inputChangedConnection = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
				resizing = false

				if inputChangedConnection then
					inputChangedConnection:Disconnect()
				end
			end
		end)
	end)

	addConnection(UserInputService.InputChanged, function(input)
		if
			input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		local cursor = toV2(input)

		if dragging then
			local totalDelta = cursor - startCursor
			local newTopLeft = startTopLeft + totalDelta

			local scr = screenGui.AbsoluteSize
			newTopLeft =
				newVector2(clamp(newTopLeft.X, 0, scr.X - startSize.X), clamp(newTopLeft.Y, 0, scr.Y - startSize.Y))

			if not orbiting then
				guiObject.Position = topLeftToUDim(newTopLeft, startSize, guiObject.AnchorPoint)
			end

			local mouseDeltaX = cursor.X - lastMouseX
			targetSwayAngle = mouseDeltaX * SWAY_FACTOR
			targetSwayAngle = clamp(targetSwayAngle, -MAX_SWAY_ANGLE, MAX_SWAY_ANGLE)
			lastMouseX = cursor.X
		elseif resizing then
			local delta = cursor - startCursor
			local newTL = startTopLeft
			local newSize = startSize

			if resizeEdges.L then
				newTL = newTL + newVector2(delta.X, 0)
				newSize = newSize - newVector2(delta.X, 0)
			elseif resizeEdges.R then
				newSize = newSize + newVector2(delta.X, 0)
			end

			if resizeEdges.T then
				newTL = newTL + newVector2(0, delta.Y)
				newSize = newSize - newVector2(0, delta.Y)
			elseif resizeEdges.B then
				newSize = newSize + newVector2(0, delta.Y)
			end

			local adj

			if newSize.X < MIN_SIZE.X then
				adj = MIN_SIZE.X - newSize.X
				newSize = newVector2(MIN_SIZE.X, newSize.Y)
				if resizeEdges.L then
					newTL = newTL - newVector2(adj, 0)
				end
			end
			if newSize.Y < MIN_SIZE.Y then
				adj = MIN_SIZE.Y - newSize.Y
				newSize = newVector2(newSize.X, MIN_SIZE.Y)
				if resizeEdges.T then
					newTL = newTL - newVector2(0, adj)
				end
			end

			local scr = screenGui.AbsoluteSize
			if scr.X < newSize.X then
				newSize = newVector2(scr.X, newSize.Y)
			end

			if scr.Y < newSize.Y then
				newSize = newVector2(newSize.X, scr.Y)
			end

			newTL = newVector2(clamp(newTL.X, 0, scr.X - newSize.X), clamp(newTL.Y, 0, scr.Y - newSize.Y))

			guiObject.Size = UDim2.fromOffset(newSize.X, newSize.Y)
			guiObject.Position = topLeftToUDim(newTL, newSize, guiObject.AnchorPoint)
		end
	end)

	addConnection(RunService.RenderStepped, function(deltaTime)
		local effectiveTargetAngle = 0
		if dragging then
			effectiveTargetAngle = targetSwayAngle
		end

		currentSwayAngle = currentSwayAngle + (effectiveTargetAngle - currentSwayAngle) * SWAY_RETURN_SPEED * deltaTime
		guiObject.Rotation = currentSwayAngle

		if not dragging and math.abs(currentSwayAngle) < 0.01 then
			currentSwayAngle = 0
			guiObject.Rotation = 0
			targetSwayAngle = 0
		end
	end)
end

-- MARK: UI Library
local Window = {}
Window.__index = Window

local Section = {}
Section.__index = Section

local easingStyle = "Quart"
local easingTime = 0.25

function Window.new(config)
	local self = setmetatable({}, Window)
	self.config = config
	self.tabs = {}
	self.tabFrames = {}
	self.selected = nil

	local library = create("CanvasGroup", "Library", {
		BackgroundColor3 = Color3.fromRGB(18, 18, 20),
		Position = newUDim2(easingTime, 0, easingTime, 0),
		Size = config.size,
		GroupTransparency = 1,
		AnchorPoint = newVector2(0.5, 0.5),
		Parent = holder,
	})

	local Scale = create("UIScale", "UIScale", {
		Scale = 0.75,
		Parent = library,
	})

	makeDraggable(library)

	create("UIPadding", "UIPadding", {
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 6),
		Parent = library,
	})

	local background = create("Frame", "Background", {
		AnchorPoint = newVector2(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(18, 18, 20),
		Position = newUDim2(0.5, 0, 0.5, 0),
		Size = newUDim2(1, 6, 1, 6),
		ZIndex = 0,
		Parent = library,
	})

	create("UIStroke", "UIStroke", {
		Color = Color3.fromRGB(54, 54, 56),
		Thickness = 1.3,
		Parent = background,
	})

	create("UICorner", "UICorner", {
		CornerRadius = UDim.new(0, 7),
		Parent = background,
	})

	create("UICorner", "UICorner", {
		CornerRadius = UDim.new(0, 9),
		Parent = library,
	})

	local content = create("Frame", "Content", {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Size = newUDim2(0, 0, 1, 0),

		Parent = library,
	})

	self.content = content

	local topbar = create("Frame", "Topbar", {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Parent = content,
	})

	create("UIListLayout", "UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = topbar,
	})

	local titleRow = create("Frame", "Title", {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Parent = topbar,
	})
	do
		create("UIListLayout", "UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Parent = titleRow,
		})
		create("TextLabel", "Title", {
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			FontFace = Font.new(settings:get("customization.font"), Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
			Position = newUDim2(0.336106, 0, 0.20776, 0),
			RichText = true,
			Text = config.name,
			TextColor3 = accentColor,
			TextSize = 20,
			TextStrokeTransparency = 0,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = titleRow,
		})

		create("UIPadding", "UIPadding", {
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 10),
			Parent = titleRow,
		})

		if config.icon then
			create("ImageLabel", "Icon", {
				BackgroundTransparency = 1,
				Image = config.icon,
				ImageColor3 = accentColor,
				LayoutOrder = -1,
				Size = newUDim2(0, 20, 0, 20),
				Parent = titleRow,
			})
		end
	end

	local navbar = create("Frame", "Navbar", {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = topbar,
	})
	self.navbar = navbar
	do
		create("UIListLayout", "UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 15),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = navbar,
		})

		create("UIPadding", "UIPadding", {
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 8),
			Parent = navbar,
		})
	end

	create("Frame", "Seperator", {
		BackgroundColor3 = Color3.fromRGB(38, 38, 40),
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Size = newUDim2(1, 0, 0, 1),
		Parent = topbar,
	})

	local exitButton = create("ImageButton", "ImageButton", {
		AnchorPoint = newVector2(1, 0),
		BackgroundTransparency = 1,
		Image = "rbxassetid://123981975891685",
		Position = newUDim2(1, -10, 0, 11),
		Size = newUDim2(0, 16, 0, 16),
		Parent = library,
	})

	local originalColor = exitButton.ImageColor3
	addConnection(exitButton.MouseEnter, function()
		animate(exitButton, easingTime, easingStyle, { ImageColor3 = darkenRGB(originalColor, 100) }, "Out")
	end)

	addConnection(exitButton.MouseLeave, function()
		animate(exitButton, easingTime, easingStyle, { ImageColor3 = originalColor }, "Out")
	end)

	addConnection(exitButton.MouseButton1Down, function()
		animate(exitButton, easingTime, easingStyle, { ImageColor3 = darkenRGB(originalColor, 150) }, "Out")
		animate(library, easingTime, easingStyle, { GroupTransparency = 1 }, "In")
		sleep()
		animate(Scale, easingTime, easingStyle, { Scale = 0.5 }, "In")
		sleep(0.25)
		library:Destroy()
	end)

	addConnection(exitButton.MouseButton1Up, function()
		animate(exitButton, easingTime, easingStyle, { ImageColor3 = originalColor }, "Out")
	end)

	create("ImageLabel", "Drop Shadow", {
		BackgroundTransparency = 1,
		Image = "rbxassetid://186491278",
		ImageTransparency = 0.45,
		Position = newUDim2(-0.15, 0, -0.15, 0),
		Size = newUDim2(1.3, 0, 1.4, 0),
		ZIndex = -5,
		Parent = library,
	})

	create("UICorner", "UICorner", {
		CornerRadius = UDim.new(0, 4),
		Parent = library,
	})

	animate(library, easingTime, easingStyle, { GroupTransparency = 0 }, "Out")
	animate(Scale, easingTime, easingStyle, { Scale = 1 }, "Out")
	return self
end

local function setBase(btn, col)
	btn:SetAttribute("BaseColor", col)
end

local function getBase(btn)
	return btn:GetAttribute("BaseColor") or btn.TextColor3
end

function Window.addTab(self, name)
	local tab = create("Frame", "Title", {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Parent = self.navbar,
	})

	create("UIListLayout", "TitleListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tab,
	})

	local title = create("TextButton", "Title", {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		FontFace = Font.new(settings:get("customization.font")),
		Position = newUDim2(0.336106, 0, 0.20776, 0),
		RichText = true,
		Text = name,
		TextColor3 = Color3.fromRGB(182, 182, 182),
		TextSize = 18,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = tab,
	})
	setBase(title, title.TextColor3)

	local scroll = create("CanvasGroup", "Scroll", {
		BackgroundTransparency = 1,
		Size = newUDim2(1, -2, 1, -76),
		GroupTransparency = 1,
		Position = newUDim2(0, 0, 0, 78),
		Parent = self.content,
	})
	self.scroll = scroll

	create("Frame", "Frame", {
		AnchorPoint = newVector2(0, 1),
		BackgroundColor3 = Color3.fromRGB(18, 18, 20),
		Position = newUDim2(0, 0, 1, -2),
		Size = newUDim2(1, 0, 0, 10),
		ZIndex = 6,
		Parent = scroll,
	})

	create("UIGradient", "UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = scroll.Frame,
	})

	create("UICorner", "UICorner", {
		CornerRadius = UDim.new(0, 3),
		Parent = scroll.Frame,
	})

	local frame = create("ScrollingFrame", "Frame", {
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		CanvasSize = newUDim2(),
		Position = newUDim2(0, 1, 0, 0),
		ScrollBarThickness = 0,
		Selectable = false,
		Size = newUDim2(1, 0, 1, -5),
		Parent = scroll,
		Visible = false,
		Name = name,
	})

	create("UIListLayout", "UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = frame,
	})

	create("UIPadding", "UIPadding", {
		PaddingBottom = UDim.new(0, 5),
		PaddingLeft = UDim.new(0, 1),
		PaddingRight = UDim.new(0, 1),
		PaddingTop = UDim.new(0, 1),
		Parent = frame,
	})

	insert(self.tabFrames, frame)
	insert(self.tabs, tab)

	if #self.tabs == 1 then
		title.TextColor3 = accentColor
		title.FontFace = Font.new(settings:get("customization.font"), Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
		frame.Visible = true
		self.selectedFrame = frame
		scroll.GroupTransparency = 0
		setBase(title, accentColor)
	end

	addConnection(title.MouseEnter, function()
		animate(title, 0.1, easingStyle, { TextColor3 = lightenRGB(getBase(title), 15) }, "Out")
	end)

	addConnection(title.MouseLeave, function()
		animate(title, 0.1, easingStyle, { TextColor3 = getBase(title) }, "Out")
	end)

	addConnection(title.MouseButton1Down, function()
		animate(title, 0.1, easingStyle, { TextColor3 = darkenRGB(getBase(title), 25) }, "Out")
	end)

	addConnection(title.MouseButton1Click, function()
		if self.selectedFrame == frame then
			return
		end

		local fromIdx = tFind(self.tabFrames, self.selectedFrame)
		local toIdx = tFind(self.tabFrames, frame)
		local dir = (toIdx > fromIdx) and 1 or -1

		local oldFrame = self.selectedFrame
		self.selectedFrame = frame
		frame.Visible = true

		for _, t in self.tabs do
			local btn = t.Title
			local neutral = Color3.fromRGB(182, 182, 182)
			animate(btn, 0.25, easingStyle, { TextColor3 = neutral }, "Out")
			btn.FontFace = Font.new(settings:get("customization.font"))
			setBase(btn, neutral)
		end

		animate(title, 0.25, easingStyle, { TextColor3 = accentColor }, "Out")
		title.FontFace = Font.new(settings:get("customization.font"), Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
		setBase(title, accentColor)

		if oldFrame then
			animate(oldFrame, 0.4, easingStyle, { Position = newUDim2(-dir, dir * 5, 0, 0) }, "Out")
			animate(oldFrame.Parent, 0.25, easingStyle, { GroupTransparency = 1 }, "Out")
		end

		frame.Position = newUDim2(dir, dir, 0, 0)
		animate(frame, 0.4, easingStyle, { Position = newUDim2(0, 1, 0, 0) }, "Out")
		animate(frame.Parent, 0.25, easingStyle, { GroupTransparency = 0 }, "Out")
	end)

	return setmetatable({ container = frame }, Section)
end

function Section.addSection(self, sectionName)
	local section = create("Frame", "Section", {
		AnchorPoint = newVector2(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(23, 23, 26),
		Position = newUDim2(1, 0, 0, 0),
		Size = newUDim2(1, -8, 0, 0),
		ZIndex = -1,
		Parent = self.container,
	})

	create("UIStroke", "UIStroke", {
		Color = Color3.fromRGB(36, 36, 40),
		Parent = section,
	})

	create("UIListLayout", "UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = section,
	})

	create("UIPadding", "UIPadding", {
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
		PaddingLeft = UDim.new(0, 5),
		PaddingRight = UDim.new(0, 5),
		Parent = section,
	})

	local title = create("Frame", "Title", {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		LayoutOrder = -1,
		Parent = section,
	})

	create("UIListLayout", "UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = title,
	})

	if sectionName then
		create("TextLabel", "Title", {
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			FontFace = Font.new(settings:get("customization.font"), Enum.FontWeight.SemiBold),
			Position = newUDim2(0.336106, 0, 0.20776, 0),
			RichText = true,
			Text = sectionName,
			TextColor3 = Color3.fromRGB(253, 253, 255),
			TextSize = 19,
			TextStrokeTransparency = 0,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = title,
		})
	end

	create("UIPadding", "UIPadding", {
		PaddingLeft = UDim.new(0, 3),
		Parent = title,
	})

	create("UICorner", "UICorner", {
		CornerRadius = UDim.new(0, 2),
		Parent = section,
	})

	return setmetatable({ container = section }, Section)
end

function Section.addViewport(self, object, autoSpin)
	local viewport = create("ViewportFrame", "Viewport", {
		Size = newUDim2(1, 0, 0, 200),
		BackgroundColor3 = Color3.fromRGB(32, 32, 36),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = self.container,
	})

	create("Frame", "BottomBar", {
		LayoutOrder = 1,
		AnchorPoint = newVector2(0, 1),
		Position = newUDim2(0, 0, 1, 0),
		Size = newUDim2(1, 0, 0, 2),
		BorderSizePixel = 0,
		ZIndex = 2,
		BackgroundColor3 = accentColor,
		Parent = viewport,
	})

	create("UICorner", "ViewportCorner", {
		CornerRadius = UDim.new(0, 4),
		Parent = viewport,
	})

	object.Archivable = true
	local clone = object:Clone()
	clone.Parent = viewport

	local pivotCF, size
	if clone:IsA("Model") then
		pivotCF, size = clone:GetBoundingBox()
	elseif clone:IsA("BasePart") then
		pivotCF = clone.CFrame
		size = clone.Size
	else
		error(("Unsupported class for viewport: %s"):format(clone.ClassName))
	end

	local pivotPos = pivotCF.Position
	local maxDim = max(size.X, size.Y, size.Z)
	local dist = maxDim

	local camera = create("Camera", "ViewportCamera", {
		CameraType = Enum.CameraType.Scriptable,
		Parent = viewport,
	})

	viewport.CurrentCamera = camera

	local yaw = 0
	local pitch = 0
	local spin = 0

	local function updateCam()
		local rot = newAngles(0, spin, 0) * newAngles(0, yaw, 0) * newAngles(pitch, 0, 0)

		local camPos = pivotPos + rot:VectorToWorldSpace(newVector3(0, 0, dist))
		camera.CFrame = CFrame.lookAt(camPos, pivotPos, newVector3(0, 1, 0))
	end

	updateCam()

	local lastPos = Vector2.zero
	local sensitivity = 0.01

	if autoSpin then
		addConnection(RunService.RenderStepped, function(dt)
			if not orbiting then
				spin += rad(20) * dt
				updateCam()
			end
		end)
	end

	addConnection(viewport.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			orbiting = true
			lastPos = UserInputService:GetMouseLocation()
		end
	end)

	addConnection(UserInputService.InputChanged, function(input)
		if not orbiting or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end

		local pos = UserInputService:GetMouseLocation()
		local dx = pos.X - lastPos.X
		local dy = pos.Y - lastPos.Y
		lastPos = pos

		yaw -= dx * sensitivity
		pitch = clamp(pitch - dy * sensitivity, rad(-80), rad(80))
		updateCam()
	end)

	addConnection(viewport.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			orbiting = false
		end
	end)

	return viewport
end

function Section.addButton(self, buttonName, callback)
	local button = create("Frame", "Button", {
		BackgroundTransparency = 1,
		Size = newUDim2(1, 0, 0, 40),
		Parent = self.container,
	})

	create("UIListLayout", "UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = button,
	})

	create("UICorner", "UICorner", {
		CornerRadius = UDim.new(0, 4),
		Parent = button,
	})

	local title = create("TextLabel", "Title", {
		BackgroundColor3 = Color3.fromRGB(32, 32, 36),
		FontFace = Font.new(settings:get("customization.font")),
		Position = newUDim2(0.336106, 0, 0.20776, 0),
		RichText = true,
		Size = newUDim2(1, 0, 1, 0),
		Text = buttonName,
		TextColor3 = Color3.fromRGB(251, 251, 255),
		TextSize = 19,
		TextStrokeTransparency = 0,
		Parent = button,
	})

	create("UICorner", "UICorner1", {
		CornerRadius = UDim.new(0, 2),
		Parent = title,
	})

	create("UIPadding", "UIPaddingTitle", {
		Parent = title,
	})

	local textbutton = create("TextButton", "TextButton", {
		BackgroundTransparency = 1,
		FontFace = Font.new(settings:get("customization.font")),
		Size = newUDim2(1, 0, 1, 0),
		Text = "",
		TextColor3 = Color3.new(),
		TextSize = 14,
		Parent = title,
		ZIndex = 10,
	})

	local originalColor = title.BackgroundColor3
	local hovered = false
	addConnection(textbutton.MouseEnter, function()
		hovered = true
		animate(title, easingTime, easingStyle, { BackgroundColor3 = lightenRGB(originalColor, 8) }, "Out")
	end)

	addConnection(textbutton.MouseLeave, function()
		animate(title, easingTime, easingStyle, { BackgroundColor3 = originalColor }, "Out")
	end)

	addConnection(textbutton.MouseButton1Down, function()
		animate(title, easingTime, easingStyle, { BackgroundColor3 = lightenRGB(originalColor, 12) }, "Out")
	end)

	addConnection(textbutton.MouseButton1Up, function()
		if hovered then
			animate(title, easingTime, easingStyle, { BackgroundColor3 = lightenRGB(originalColor, 8) }, "Out")
			return
		end

		animate(title, easingTime, easingStyle, { BackgroundColor3 = originalColor }, "Out")
	end)

	addConnection(textbutton.MouseButton1Click, callback)

	create("UIStroke", "UIStroke", {
		Color = Color3.fromRGB(32, 32, 36),
		Parent = button,
	})
end

function Section.addToggle(self, buttonName, callback, defaultState)
	defaultState = defaultState or false

	local toggle = create("Frame", "Toggle", {
		BackgroundTransparency = 1,
		LayoutOrder = -1,
		Size = newUDim2(1, 0, 0, 15),
		Parent = self.container,
	})

	create("UIListLayout", "UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = toggle,
	})

	local title = create("TextLabel", "Title", {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		FontFace = Font.new(settings:get("customization.font")),
		Position = newUDim2(0.336106, 0, 0.20776, 0),
		RichText = true,
		Text = buttonName,
		TextColor3 = Color3.fromRGB(253, 253, 255),
		TextSize = 17,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = toggle,
	})

	local textbutton = create("TextButton", "TextButton", {
		BackgroundTransparency = 1,
		FontFace = Font.new(settings:get("customization.font")),
		Size = newUDim2(1, 0, 1, 0),
		Text = "",
		TextColor3 = Color3.new(),
		TextSize = 14,
		Parent = title,
	})

	create("UIPadding", "UIPadding", {
		PaddingBottom = UDim.new(0, 2),
		PaddingLeft = UDim.new(0, 3),
		Parent = toggle,
	})

	local outline = create("Frame", "ToggleOutline", {
		BackgroundTransparency = 1,
		LayoutOrder = -1,
		Size = newUDim2(0, 12, 0, 12),
		Parent = toggle,
	})

	local toggleinner = create("Frame", "ToggleInner", {
		AnchorPoint = newVector2(0.5, 0.5),
		BackgroundColor3 = accentColor,
		LayoutOrder = -1,
		Position = newUDim2(0.5, 0, 0.5, 0),
		Size = newUDim2(0, 8, 0, 8),
		Visible = true,
		Parent = outline,
	})

	if defaultState then
		toggleinner.Size = newUDim2(0, 8, 0, 8)
		toggleinner.BackgroundTransparency = 0
	else
		toggleinner.Size = newUDim2(0, 0, 0, 0)
		toggleinner.BackgroundTransparency = 1
	end

	create("UICorner", "InnerCorner", {
		CornerRadius = UDim.new(0, 2),
		Parent = toggleinner,
	})

	local uistroke = create("UIStroke", "OutlineStroke", {
		Color = defaultState and accentColor or Color3.fromRGB(73, 78, 89),
		Parent = outline,
	})

	create("UICorner", "OutlineCorner", {
		CornerRadius = UDim.new(0, 3),
		Parent = outline,
	})

	addConnection(textbutton.MouseButton1Click, function()
		defaultState = not defaultState

		if defaultState then
			callback(true)
			animate(
				toggleinner,
				easingTime / 1.5,
				easingStyle,
				{ Size = newUDim2(0, 8, 0, 8), BackgroundTransparency = 0 },
				"Out"
			)
			animate(uistroke, easingTime, easingStyle, { Color = accentColor }, "Out")
		else
			callback(false)
			animate(
				toggleinner,
				easingTime / 1.5,
				easingStyle,
				{ Size = newUDim2(0, 0, 0, 0), BackgroundTransparency = 1 },
				"Out"
			)
			animate(uistroke, easingTime, easingStyle, { Color = Color3.fromRGB(73, 78, 89) }, "Out")
		end
	end)
end

function Section.addEntry(self, titleText, desc, subtext)
	local entry = create("Frame", "Entry", {
		AnchorPoint = newVector2(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(23, 23, 26),
		Position = newUDim2(0.5, 0, 0.5, 0),
		Size = newUDim2(1, 0, 0, 0),
		Parent = self.container,
	})

	create("UIListLayout", "UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = entry,
	})

	create("UICorner", "UICorner", {
		CornerRadius = UDim.new(0, 4),
		Parent = entry,
	})

	local title = create("Frame", "Title", {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(32, 32, 36),
		Size = newUDim2(1, 0, 0, 0),
		Parent = entry,
	})

	create("TextLabel", "Title", {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		FontFace = Font.new(settings:get("customization.font"), Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
		RichText = true,
		Size = newUDim2(1, 0, 0, 0),
		Text = titleText,
		TextColor3 = Color3.fromRGB(251, 251, 255),
		TextSize = 20,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		Parent = title,
		Visible = titleText and true or false,
		LayoutOrder = -1,
	})

	create("UICorner", "UICorner", {
		CornerRadius = UDim.new(0, 4),
		Parent = title:FindFirstChild("Title"),
	})

	create("UICorner", "UICorner", {
		CornerRadius = UDim.new(0, 4),
		Parent = title,
	})

	create("TextLabel", "Description", {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		FontFace = Font.new(settings:get("customization.font")),
		RichText = true,
		Size = newUDim2(1, 0, 0, 0),
		Text = desc,
		TextColor3 = Color3.fromRGB(218, 218, 221),
		TextSize = 18,
		TextStrokeTransparency = 0,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		Parent = title,

		Visible = desc and true or false,
	})

	create("UICorner", "UICorner", {
		CornerRadius = UDim.new(0, 4),
		Parent = title:FindFirstChild("Description"),
	})

	create("UIListLayout", "UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = title,
	})

	create("UIPadding", "UIPadding", {
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 11),
		PaddingTop = UDim.new(0, 10),
		Parent = title,
	})

	create("TextLabel", "Subtext", {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		FontFace = Font.new("rbxassetid://16658246179"),
		RichText = true,
		Size = newUDim2(1, 0, 0, 0),
		Text = subtext,
		TextColor3 = Color3.fromRGB(167, 167, 170),
		TextSize = 14,
		TextStrokeTransparency = 0.8,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = subtext and true or false,
		ZIndex = 3,
		Parent = title,
	})

	create("UICorner", "UICorner", {
		CornerRadius = UDim.new(0, 4),
		Parent = title:FindFirstChild("Subtext"),
	})

	create("UIPadding", "UIPadding", {
		PaddingTop = UDim.new(0, 2),
		Parent = title:FindFirstChild("Subtext"),
	})
end

function Section.addTextbox(self, placeholder, event, callback)
	local textbox = create("Frame", "Textbox", {
		BackgroundColor3 = Color3.fromRGB(32, 32, 36),
		Size = newUDim2(1, 0, 0, 40),
		Parent = self.container,
	})

	local uistroke = create("UIStroke", "UIStroke", {
		Color = accentColor,
		Thickness = 0,
		Transparency = 1,
		Parent = textbox,
	})

	local textbox1 = create("TextBox", "Textbox", {
		Active = false,
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		CursorPosition = -1,
		FontFace = Font.new(settings:get("customization.font")),
		PlaceholderColor3 = Color3.fromRGB(180, 180, 180),
		PlaceholderText = tostring(placeholder),
		RichText = true,
		Selectable = false,
		Size = newUDim2(1, 0, 1, 0),
		Text = "",
		TextColor3 = Color3.fromRGB(251, 251, 255),
		TextSize = 19,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 1,
		Parent = textbox,
	})

	create("UIPadding", "UIPadding", {
		PaddingBottom = UDim.new(0, 7),
		PaddingLeft = UDim.new(0, 13),
		PaddingTop = UDim.new(0, 7),
		Parent = textbox1,
	})

	create("UICorner", "UICorner", {
		CornerRadius = UDim.new(0, 4),
		Parent = textbox1,
	})
	create("UICorner", "UICorner", {
		CornerRadius = UDim.new(0, 4),
		Parent = textbox,
	})

	local originalColor = textbox.BackgroundColor3
	local focused = false

	textbox1.Focused:Connect(function()
		focused = true
		animate(uistroke, easingTime, easingStyle, { Thickness = 1 }, "Out")
		animate(uistroke, easingTime, easingStyle, { Transparency = 0 }, "Out")
		animate(textbox, easingTime, easingStyle, { BackgroundColor3 = accentColor }, "Out")
		textbox.BackgroundTransparency = 0.85
	end)

	textbox1.MouseEnter:Connect(function()
		animate(textbox, easingTime, easingStyle, { BackgroundColor3 = lightenRGB(originalColor, 8) }, "Out")
	end)

	textbox1.MouseLeave:Connect(function()
		if not focused then
			animate(uistroke, easingTime, easingStyle, { Transparency = 1 }, "Out")
			animate(uistroke, easingTime, easingStyle, { Thickness = 0 }, "Out")
			animate(textbox, easingTime, easingStyle, { BackgroundColor3 = originalColor }, "Out")
			textbox.BackgroundTransparency = 0
		end
	end)

	textbox1.FocusLost:Connect(function()
		focused = false
		animate(uistroke, easingTime, easingStyle, { Transparency = 1 }, "Out")
		animate(uistroke, easingTime, easingStyle, { Thickness = 0 }, "Out")
		animate(textbox, easingTime, easingStyle, { BackgroundColor3 = originalColor }, "Out")
		animate(textbox, easingTime, easingStyle, { BackgroundTransparency = 0 }, "Out")
	end)

	if event == "FocusLost" then
		textbox1.FocusLost:Connect(function()
			callback(textbox1.Text)
		end)
	else
		textbox1:GetPropertyChangedSignal("Text"):Connect(function()
			callback(textbox1.Text)
		end)
	end
end

function Section.addDropdown(self, values, callback, defaultValue)
	local opened = false
	self.selected = nil

	local dropdown = create("Frame", "Dropdown", {
		BackgroundColor3 = Color3.fromRGB(32, 32, 36),
		Size = newUDim2(1, 0, 0, 40),
		Parent = self.container,
		ZIndex = 0,
	})

	local textbutton = create("TextButton", "TextButton", {
		BackgroundTransparency = 1,
		FontFace = Font.new(settings:get("customization.font")),
		Size = newUDim2(1, 0, 1, 0),
		Text = "",
		TextColor3 = Color3.new(),
		TextSize = 14,
		ZIndex = 10,
		Parent = dropdown,
	})

	local title = create("TextLabel", "Title", {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		FontFace = Font.new(settings:get("customization.font")),
		RichText = true,
		Size = newUDim2(1, 0, 1, 0),
		Text = defaultValue or values[1] or "",
		TextColor3 = Color3.fromRGB(251, 251, 255),
		TextSize = 19,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		Parent = dropdown,
	})

	create("UIPadding", "UIPadding", {
		PaddingBottom = UDim.new(0, 7),
		PaddingLeft = UDim.new(0, 13),
		PaddingTop = UDim.new(0, 7),
		Parent = title,
	})
	create("UICorner", "UICorner", {
		CornerRadius = UDim.new(0, 4),
		Parent = title,
	})

	local imagelabel = create("ImageLabel", "ImageLabel", {
		AnchorPoint = newVector2(1, 0.5),
		BackgroundTransparency = 1,
		Image = "rbxassetid://75898830403385",
		ImageColor3 = accentColor,
		LayoutOrder = -1,
		Position = newUDim2(1, -10, 0.5, 0),
		Size = newUDim2(0, 16, 0, 16),
		Parent = dropdown,
	})

	local originalPosition = newUDim2(0, 0, 0, 35)
	local targetPosition = newUDim2(0, 0, 0, 46)

	local options = create("CanvasGroup", "Options", {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Position = originalPosition,
		Size = newUDim2(0, 0, 0, 0),
		ZIndex = 9,
		GroupTransparency = 1,
		Visible = false,
		Parent = dropdown,
	})

	local holder = create("Frame", "Holder", {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(24, 24, 27),
		Size = newUDim2(1, 0, 1, 0),
		Visible = true,
		ZIndex = 9,
		Parent = options,
	})

	create("UIListLayout", "UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = holder,
	})

	create("UIStroke", "UIStroke", {
		Color = Color3.fromRGB(35, 35, 39),
		Parent = options,
	})
	create("UIPadding", "UIPadding", {
		PaddingBottom = UDim.new(0, 3),
		PaddingTop = UDim.new(0, 3),
		Parent = holder,
	})
	create("UICorner", "UICorner", {
		CornerRadius = UDim.new(0, 4),
		Parent = holder,
	})

	local function createOption(name, selected)
		local optionFrame = create("Frame", "Option", {
			BackgroundTransparency = 1,
			Size = newUDim2(1, 0, 0, 40),
			ZIndex = 12,
			Parent = holder,
		})

		local titleLabel = create("TextLabel", "Title", {
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = selected and accentColor or Color3.fromRGB(35, 35, 39),
			FontFace = Font.new(settings:get("customization.font")),
			Position = newUDim2(0, 0, 0, 0),
			RichText = true,
			Size = newUDim2(1, 0, 0, 40),
			Text = name,
			TextColor3 = selected and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(230, 230, 234),
			TextSize = 19,
			ZIndex = 15,
			Parent = optionFrame,
		})

		create("UIGradient", "Gradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(161, 161, 161)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(224, 224, 224)),
				ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
			}),
			Rotation = -90,
			Parent = titleLabel,
			Enabled = selected,
		})

		create("UIPadding", "UIPadding", {
			PaddingBottom = UDim.new(0, 7),
			PaddingTop = UDim.new(0, 7),
			Parent = titleLabel,
		})
		create("UICorner", "UICorner", {
			CornerRadius = UDim.new(0, 4),
			Parent = titleLabel,
		})
		create("UIPadding", "UIPadding", {
			PaddingLeft = UDim.new(0, 3),
			PaddingRight = UDim.new(0, 3),
			Parent = optionFrame,
		})
		create("UICorner", "UICorner", {
			CornerRadius = UDim.new(0, 4),
			Parent = optionFrame,
		})

		local button = create("TextButton", "TextButton", {
			BackgroundTransparency = 1,
			FontFace = Font.new(settings:get("customization.font")),
			Size = newUDim2(1, 0, 1, 0),
			Text = "",
			TextColor3 = Color3.new(),
			TextSize = 14,
			ZIndex = 15,
			Parent = optionFrame,
		})

		button.MouseButton1Click:Connect(function()
			for _, obj in holder:GetChildren() do
				if obj:IsA("Frame") then
					animate(
						obj.Title,
						easingTime,
						easingStyle,
						{ BackgroundColor3 = Color3.fromRGB(35, 35, 39) },
						"Out"
					)
					animate(obj.Title, easingTime, easingStyle, { TextColor3 = Color3.fromRGB(201, 201, 204) }, "Out")
					obj.Title.Gradient.Enabled = false
				end
			end

			animate(titleLabel, easingTime, easingStyle, { TextColor3 = Color3.fromRGB(0, 0, 0) }, "Out")
			animate(titleLabel, easingTime, easingStyle, { BackgroundColor3 = accentColor }, "Out")
			titleLabel.Gradient.Enabled = true
			title.Text = name
			self.selected = name
			callback(name)
		end)
	end

	if defaultValue then
		createOption(defaultValue, true)
		self.selected = defaultValue
	else
		createOption(values[1], true)
		self.selected = values[1]
	end
	for i = 2, #values do
		createOption(values[i], false)
	end

	create("UICorner", "UICorner", { CornerRadius = UDim.new(0, 4), Parent = options })
	create("UICorner", "UICorner", { CornerRadius = UDim.new(0, 4), Parent = dropdown })

	local originalColor = dropdown.BackgroundColor3
	addConnection(textbutton.MouseEnter, function()
		animate(dropdown, easingTime, easingStyle, { BackgroundColor3 = lightenRGB(originalColor, 8) }, "Out")
	end)
	addConnection(textbutton.MouseLeave, function()
		animate(dropdown, easingTime, easingStyle, { BackgroundColor3 = originalColor }, "Out")
	end)
	addConnection(textbutton.MouseButton1Down, function()
		animate(dropdown, easingTime, easingStyle, { BackgroundColor3 = lightenRGB(originalColor, 12) }, "Out")
	end)
	addConnection(textbutton.MouseButton1Up, function()
		animate(dropdown, easingTime, easingStyle, { BackgroundColor3 = originalColor }, "Out")
	end)

	textbutton.MouseButton1Click:Connect(function()
		opened = not opened
		if opened then
			options.Visible = true
			dropdown.ZIndex = 1
			self.container.ZIndex = self.container.ZIndex + 1
			animate(dropdown, easingTime, easingStyle, { BackgroundColor3 = lightenRGB(originalColor, 8) }, "Out")
			animate(options, easingTime, easingStyle, { GroupTransparency = 0 }, "Out")
			animate(options, easingTime, easingStyle, { Position = targetPosition }, "Out")
			animate(imagelabel, easingTime, easingStyle, { Rotation = 180 }, "Out")
		else
			animate(imagelabel, easingTime, easingStyle, { Rotation = 0 }, "Out")
			animate(options, easingTime, easingStyle, { Position = originalPosition }, "Out")
			animate(options, easingTime, easingStyle, { GroupTransparency = 1 }, "Out")
			sleep(0.15)
			options.Visible = false
			dropdown.ZIndex = 0
		end
	end)
end

function Section.addLabel(self, labelText)
	local Label = create("TextLabel", "Title", {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		FontFace = Font.new(settings:get("customization.font")),
		Position = newUDim2(0.336106, 0, 0.20776, 0),
		RichText = true,
		Text = tostring(labelText),
		TextColor3 = Color3.fromRGB(253, 253, 255),
		TextSize = 18,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self.container,
		ZIndex = -5,
	})

	create("UIPadding", "UIPadding", {
		PaddingLeft = UDim.new(0, 2),
		Parent = Label,
	})
end

-- MARK: Command Handler
local commandRegistry = {}
local aliasMap = {}
local typeValidators = {
	player = function(valueString, _)
		local lowerValue = lower(valueString)

		if lowerValue == "me" then
			return true, Player
		end

		local foundPlayers = {}

		for _, player in Players:GetPlayers() do
			local lowerName = lower(player.Name)
			local lowerDisplayName = lower(player.DisplayName)

			if find(lowerName, lowerValue, 1, true) == 1 or find(lowerDisplayName, lowerValue, 1, true) == 1 then
				insert(foundPlayers, player)
			end
		end

		if #foundPlayers >= 1 then
			return true, foundPlayers[1]
		else
			notify("Player '" .. valueString .. "' not found")
			return false
		end
	end,

	number = function(valueString, argName)
		local num = tonumber(valueString)
		if num ~= nil then
			return true, num
		else
			notify("Argument '" .. argName .. "' ('" .. valueString .. "') is not a valid number")
			return false
		end
	end,

	string = function(valueString, _)
		return true, valueString
	end,

	boolean = function(valueString, argName)
		local lowerVal = lower(valueString)
		if lowerVal == "true" or lowerVal == "yes" or lowerVal == "1" or lowerVal == "on" then
			return true, true
		elseif lowerVal == "false" or lowerVal == "no" or lowerVal == "0" or lowerVal == "off" then
			return true, false
		else
			notify("Argument '" .. argName .. "' ('" .. valueString .. "') is not a valid boolean (true/false)")
			return false
		end
	end,
}

local function parseArgument(valueString, argDefinition)
	local argType = argDefinition.type
	local argName = argDefinition.name or "unnamed"
	local isOptional = argDefinition.isOptional

	if valueString == nil then
		if isOptional then
			return true, nil
		else
			return false
		end
	end

	local validator = typeValidators[argType]
	if validator then
		return validator(valueString, argName)
	else
		notify("Unknown argument type defined: " .. tostring(argType) .. " for argument " .. argName)
		return false
	end
end

local function isNonEmptyString(value)
	return type(value) == "string" and #value > 0
end

local function validateAlias(alias)
	return type(alias) == "string" and #alias > 0
end

local function validateArgumentsDefinition(def)
	return type(def) == "table"
		and isNonEmptyString(def.name)
		and isNonEmptyString(def.type)
		and (def.isOptional == nil or type(def.isOptional) == "boolean")
end

function createCommand(aliases, argumentsDefinition, executeFunction, description)
	for _, validator in
		{
			{
				condition = function()
					return type(aliases) ~= "table" or #aliases == 0
				end,
				message = "Aliases must be a non-empty table",
			},
			{
				condition = function()
					return argumentsDefinition ~= nil and type(argumentsDefinition) ~= "table"
				end,
				message = "ArgumentsDefinition must be a table (or nil)",
			},
			{
				condition = function()
					return type(executeFunction) ~= "function"
				end,
				message = "ExecuteFunction must be a function",
			},
			{
				condition = function()
					return description ~= nil and type(description) ~= "string"
				end,
				message = "Description, if provided, must be a string",
			},
		}
	do
		if validator.condition() then
			return notify(validator.message)
		end
	end

	local primaryAlias = aliases[1]
	if primaryAlias == "" then
		return notify("Primary alias (first in list) cannot be empty")
	end

	if commandRegistry[primaryAlias] then
		return notify(("Command '%s' already exists"):format(primaryAlias))
	end

	local validatedArgsDef = {}
	if argumentsDefinition then
		for idx, argDef in argumentsDefinition do
			if not validateArgumentsDefinition(argDef) then
				return notify("Invalid argument definition at index " .. idx)
			end

			insert(validatedArgsDef, {
				name = argDef.name,
				type = argDef.type,
				isOptional = argDef.isOptional == true,
			})
		end
	end

	for _, alias in aliases do
		if not validateAlias(alias) then
			return notify("All aliases must be non-empty strings")
		end
		if aliasMap[alias] then
			return notify("Alias '" .. alias .. "' is already registered to command '" .. aliasMap[alias] .. "'")
		end
	end

	local commandData = {
		PrimaryAlias = primaryAlias,
		Aliases = aliases,
		ArgumentsDefinition = validatedArgsDef,
		ExecuteFunction = executeFunction,
		Description = description or "",
	}
	commandRegistry[primaryAlias] = commandData

	for _, alias in aliases do
		aliasMap[alias] = primaryAlias
	end

	return true
end

function executeCommand(commandString)
	if not commandString or type(commandString) ~= "string" or #commandString == 0 then
		return false
	end

	commandString = match(commandString, "^%s*(.-)%s*$")
	local parts = split(commandString, " ")
	if #parts == 0 then
		return false
	end

	local commandAlias = parts[1]
	local primaryAlias = aliasMap[commandAlias]

	if not primaryAlias then
		notify("Unknown command: " .. color.red(commandAlias) .. "")
		return false
	end

	local commandData = commandRegistry[primaryAlias]
	local argsDefinition = commandData.ArgumentsDefinition or {}

	local inputArgStrings = {}
	for i = 2, #parts do
		insert(inputArgStrings, parts[i])
	end

	if #inputArgStrings < #argsDefinition then
		for i = #inputArgStrings + 1, #argsDefinition do
			local argDef = argsDefinition[i]
			if not argDef.isOptional then
				local missingArgName = argDef.name
				notify("Missing argument: " .. color.red(missingArgName))
				return false
			end
		end
	elseif #inputArgStrings > #argsDefinition then
		notify(
			"Too many arguments provided for command "
				.. color.red(primaryAlias)
				.. ". Expected "
				.. color.cyan(#argsDefinition)
				.. ", got "
				.. color.yellow(#inputArgStrings)
				.. ""
		)
		return false
	end

	local parsedArgs = {}
	for i, argDef in argsDefinition do
		local success, resultOrError = parseArgument(inputArgStrings[i], argDef)
		if not success then
			return false
		end

		parsedArgs[argDef.name] = resultOrError
	end

	local ok, ret = xpcall(function()
		return commandData.ExecuteFunction(parsedArgs)
	end, debug.traceback)

	if not ok then
		notify(("Error executing '%s':\n%s"):format(primaryAlias, ret))
		warn(("Error executing '%s':\n%s"):format(primaryAlias, ret))
		return false
	end

	return true
end

local spoofedProperties = {}
function spoofProperty(instance, propertyName)
	local originalValue = instance[propertyName]

	if not spoofedProperties[instance] then
		spoofedProperties[instance] = {}
	end

	spoofedProperties[instance][propertyName] = originalValue

	local mt = getrawmetatable(game)
	local oldindex = mt.__index
	setreadonly(mt, false)

	mt.__index = function(indexed, property)
		if spoofedProperties[indexed] and spoofedProperties[indexed][property] then
			return spoofedProperties[indexed][property]
		end
		return oldindex(indexed, property)
	end

	setreadonly(mt, true)
end

-- MARK: Command Bar
local initialPosition = newUDim2(0.5, 0, 0, 100)
local openedPosition = newUDim2(0.5, 0, 0, 150)
local BuilderMono = Font.new("rbxassetid://16658246179")

local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local activeTweens = {}
local suggestionSpecs = {
	open = {
		{ key = "frame", props = { BackgroundTransparency = 0.15 } },
		{ key = "title", props = { TextTransparency = 0 } },
		{ key = "aliases", props = { TextTransparency = 0 } },
		{ key = "description", props = { TextTransparency = 0 } },
	},
	close = {
		{ key = "description", props = { TextTransparency = 1 } },
		{ key = "aliases", props = { TextTransparency = 1 } },
		{ key = "title", props = { TextTransparency = 1 } },
		{ key = "frame", props = { BackgroundTransparency = 1 } },
	},
}

local function cancelSuggestionTweens()
	for _, tw in activeTweens do
		if tw.PlaybackState ~= Enum.PlaybackState.Completed then
			tw:Cancel()
		end
	end
	activeTweens = {}
end

local runner = create("Frame", "Runner", {
	AnchorPoint = newVector2(0.5, 0),
	BackgroundColor3 = Color3.fromRGB(16, 16, 16),
	BackgroundTransparency = 1,
	Position = initialPosition,
	Size = newUDim2(0, 500, 0, 60),
	AutomaticSize = Enum.AutomaticSize.X,
	Parent = holder,
})

create("UIPadding", "Padding", {
	PaddingTop = UDim.new(0, 6),
	PaddingBottom = UDim.new(0, 5),
	PaddingLeft = UDim.new(0, 21),
	PaddingRight = UDim.new(0, 20),
	Parent = runner,
})

create("UICorner", "Corner", { CornerRadius = UDim.new(0, 8), Parent = runner })

create("TextLabel", "Title", {
	LayoutOrder = -1,
	FontFace = Font.new("rbxassetid://16658246179"),
	TextColor3 = accentColor,
	Text = format("[sora@%s]", tostring(Player.Name:lower())),
	BackgroundTransparency = 1,
	TextTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 18,
	AutomaticSize = Enum.AutomaticSize.X,
	Parent = runner,
})

local input = create("TextBox", "Input", {
	LayoutOrder = 3,
	FontFace = BuilderMono,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "",
	PlaceholderText = "",
	PlaceholderColor3 = Color3.new(0.905882, 0.901960, 0.952941),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 3,
	TextSize = 17,
	AutomaticSize = Enum.AutomaticSize.X,
	Size = newUDim2(0, 0, 1, 0),
	ClearTextOnFocus = false,
	Parent = runner,
})

create("UIPadding", "InputPad", { PaddingLeft = UDim.new(0, 5), Parent = input })

local prediction = create("TextLabel", "Prediction", {
	FontFace = BuilderMono,
	TextColor3 = Color3.new(0.639, 0.639, 0.639),
	BackgroundTransparency = 1,
	Text = "",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 17,
	Size = newUDim2(1, 0, 1, 0),
	ZIndex = 1,
	Parent = input,
})

create("ImageLabel", "Chevron", {
	ImageColor3 = accentColor,
	Image = "rbxassetid://100258505567305",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = newUDim2(0, 20, 0, 20),
	ImageTransparency = 1,
	LayoutOrder = 1,
	Parent = runner,
})

create("UIListLayout", "Layout", {
	VerticalAlignment = Enum.VerticalAlignment.Center,
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 5),
	Parent = runner,
})

local suggestion = create("Frame", "Suggestion", {
	Parent = holder,
	AnchorPoint = newVector2(0, 1),
	BackgroundColor3 = Color3.new(0.150, 0.150, 0.153),
	BackgroundTransparency = 0.15,
	Position = UDim2.fromOffset(0, 0),
	ZIndex = input.ZIndex + 1,
	AutomaticSize = Enum.AutomaticSize.XY,
	Visible = false,
})
create("UIPadding", "SugPadding", {
	PaddingTop = UDim.new(0, 15),
	PaddingLeft = UDim.new(0, 15),
	PaddingRight = UDim.new(0, 15),
	PaddingBottom = UDim.new(0, 15),
	Parent = suggestion,
})

create("UICorner", "SugCorner", { Parent = suggestion })

create(
	"UIListLayout",
	"SugLayout",
	{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5), Parent = suggestion }
)

local sugTitle = create("TextLabel", "SuggestionTitle", {
	LayoutOrder = -1,
	FontFace = Font.new("rbxassetid://16658221428", Enum.FontWeight.Bold),
	Text = "",
	RichText = true,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 1,
	TextSize = 20,
	AutomaticSize = Enum.AutomaticSize.X,
	TextTransparency = 1,
	Parent = suggestion,
	ZIndex = 5,
	Size = newUDim2(0, 0, 0, 15),
})

local sugAliases = create("TextLabel", "SuggestionAliases", {
	Text = "",
	RichText = false,
	FontFace = Font.new("rbxassetid://16658221428", Enum.FontWeight.SemiBold),
	TextColor3 = Color3.fromRGB(230, 230, 230),
	TextWrapped = true,
	TextSize = 17,
	BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.X,
	TextTransparency = 1,
	Parent = suggestion,
	ZIndex = 5,
	Size = newUDim2(0, 0, 0, 15),
})

local sugDesc = create("TextLabel", "SuggestionDescription", {
	LayoutOrder = 2,
	FontFace = Font.new("rbxassetid://16658221428"),
	Text = "",
	TextWrapped = true,
	TextSize = 16,
	TextColor3 = Color3.fromRGB(190, 190, 190),
	AutomaticSize = Enum.AutomaticSize.X,
	TextTransparency = 1,
	Parent = suggestion,
	BackgroundTransparency = 1,
	ZIndex = 5,
	Size = newUDim2(0, 0, 0, 15),
})

local function repositionSuggestion()
	if not suggestion.Visible then
		return
	end

	local w = input.TextBounds.X
	local yOff = suggestion.Position.Y.Offset

	local tw = TweenService:Create(
		suggestion,
		tweenInfo,
		{ Position = UDim2.fromOffset(round(input.AbsolutePosition.X + w + 3), yOff) }
	)

	insert(activeTweens, tw)
	tw:Play()
end

local function getSuggestionElements()
	return {
		frame = suggestion,
		title = sugTitle,
		aliases = sugAliases,
		description = sugDesc,
	}
end

local function playSuggestionSequence(specs, delay, onLast)
	local elems = getSuggestionElements()
	for i, spec in specs do
		local obj = elems[spec.key]
		if obj then
			local tw = TweenService:Create(obj, tweenInfo, spec.props)
			insert(activeTweens, tw)
			tw:Play()
			if i == #specs and onLast then
				tw.Completed:Connect(onLast)
			end

			if delay and i < #specs then
				sleep(delay)
			end
		end
	end
end

local OFFSET = 10

local function openSuggestion()
	cancelSuggestionTweens()

	-- figure out the final position above the caret:
	local w = input.TextBounds.X
	local gx, gy = input.AbsolutePosition.X, input.AbsolutePosition.Y
	local finalPos = UDim2.fromOffset(gx + w, gy - 15)

	-- start hidden & 10px above where we want it
	sugTitle.TextTransparency = 1
	sugAliases.TextTransparency = 1
	sugDesc.TextTransparency = 1
	suggestion.BackgroundTransparency = 1
	suggestion.Position = UDim2.fromOffset(finalPos.X.Offset, finalPos.Y.Offset - OFFSET)
	suggestion.Visible = true

	playSuggestionSequence(suggestionSpecs.open, 0.04)

	local posTween = TweenService:Create(suggestion, tweenInfo, { Position = finalPos })
	insert(activeTweens, posTween)
	posTween:Play()
end

local function closeSuggestion()
	cancelSuggestionTweens()

	local currentPos = suggestion.Position
	local upPos = UDim2.fromOffset(currentPos.X.Offset, currentPos.Y.Offset - OFFSET)

	playSuggestionSequence(suggestionSpecs.close, 0.04)

	local posTween = TweenService:Create(suggestion, tweenInfo, { Position = upPos })
	insert(activeTweens, posTween)
	posTween.Completed:Connect(function()
		suggestion.Visible = false

		suggestion.Position = currentPos
	end)

	posTween:Play()
end

local function updatePrediction(txt)
	prediction.Text = ""

	local parts = {}
	for word in txt:gmatch("%S+") do
		insert(parts, word)
	end

	if #parts == 0 then
		if suggestion.Visible then
			closeSuggestion()
		end
		return
	end

	local cmdInput = parts[1]
	local bestAlias
	local bestLen = math.huge

	for alias in aliasMap do
		if alias:sub(1, #cmdInput) == cmdInput and #alias < bestLen then
			bestAlias, bestLen = alias, #alias
		end
	end

	if not bestAlias then
		if suggestion.Visible then
			closeSuggestion()
		end
		return
	end

	local primary = aliasMap[bestAlias]
	local data = commandRegistry[primary] or {}
	local argDefs = data.ArgumentsDefinition or {}

	if #parts == 1 then
		local remainder = bestAlias:sub(#cmdInput + 1)
		prediction.Text = string.rep(" ", #cmdInput) .. remainder .. " "

		local argNames = {}
		for _, arg in argDefs do
			insert(argNames, arg.name)
		end

		local smallSize = max(1, sugTitle.TextSize - 3)
		local argsText = (#argNames > 0)
				and format(' <font face="SourceSans" size="%d">(%s)</font>', smallSize, concat(argNames, ", "))
			or ""

		local prefix = bestAlias:sub(1, #cmdInput)
		local suffix = bestAlias:sub(#cmdInput + 1)
		local c = accentColor
		local hex = format("#%02X%02X%02X", floor(c.R * 255), floor(c.G * 255), floor(c.B * 255))

		sugTitle.RichText = true
		sugTitle.Text = format('<font color="%s">%s</font>%s%s', hex, prefix, suffix, argsText)

		local rawAliases = data.Aliases or { bestAlias }
		if #rawAliases > 1 then
			sugAliases.Visible = true
			sugAliases.RichText = true
			local aliPieces = {}
			for _, a in rawAliases do
				if a == bestAlias then
					local pfx = a:sub(1, #cmdInput)
					local sfx = a:sub(#cmdInput + 1)
					insert(aliPieces, format('<font color="%s">%s</font>%s', hex, pfx, sfx))
				else
					insert(aliPieces, a)
				end
			end
			sugAliases.Text = concat(aliPieces, " / ")
		else
			sugAliases.Visible = false
		end

		sugDesc.Text = data.Description or "No description provided."

		if not suggestion.Visible then
			openSuggestion()
		else
			repositionSuggestion()
		end
		return
	end

	local argIndex = #parts - 1 -- which argument is being typed now?
	local thisArgDef = argDefs[argIndex]

	if thisArgDef and thisArgDef.type == "player" then
		local partial = parts[#parts]
		local lowerPartial = partial:lower()

		local bestPLen, bestPlayer, matchType = math.huge
		for _, player in Players:GetPlayers() do
			local displayName, userName = player.DisplayName, player.Name
			local lowerDisplayName, lowerUserName = displayName:lower(), userName:lower()

			if lowerDisplayName:sub(1, #lowerPartial) == lowerPartial then
				if #displayName < bestPLen then
					bestPlayer, bestPLen, matchType = player, #displayName, "display"
				end
			elseif lowerUserName:sub(1, #lowerPartial) == lowerPartial then
				if #userName < bestPLen then
					bestPlayer, bestPLen, matchType = player, #userName, "name"
				end
			end
		end

		if bestPlayer then
			local target = (matchType == "display") and bestPlayer.DisplayName or bestPlayer.Name
			local remainder = target:sub(#partial + 1)

			prediction.Text = string.rep(" ", #txt) .. remainder

			local c = accentColor
			local hex = format("#%02X%02X%02X", floor(c.R * 255), floor(c.G * 255), floor(c.B * 255))

			local primaryName = target
			local secondaryName = (matchType == "display") and bestPlayer.Name or bestPlayer.DisplayName

			sugTitle.RichText = true
			sugTitle.Text = format('<font color="%s">%s</font> (%s)', hex, primaryName, secondaryName)

			sugAliases.Visible = false
			sugDesc.Text = "Player"

			if not suggestion.Visible then
				openSuggestion()
			else
				repositionSuggestion()
			end
			return
		else
			if suggestion.Visible then
				closeSuggestion()
			end
			return
		end
	end

	if suggestion.Visible then
		closeSuggestion()
	end
end

local function keyCodeToString(keyCode)
	if keyCode.Value < 127 and keyCode.Value > 33 then
		return string.char(keyCode.Value)
	else
		return keyCode.Name
	end
end

local _busy = false
addConnection(input:GetPropertyChangedSignal("Text"), function()
	if _busy then
		return
	end

	_busy = true

	local txt = input.Text:gsub(keyCodeToString(getSettingKeyCode("prefix")), "")
	local wantsTrailing = txt:sub(-1) == " "
	txt = txt
		:gsub("^%s+", "") -- leading
		:gsub("%s+", " ") -- interior
		:gsub("%s+$", "") -- trailing

	if wantsTrailing and #txt > 0 then
		txt = txt .. " "
	end

	input.Text = txt
	_busy = false

	updatePrediction(txt)
end)

addConnection(input.Focused, function()
	updatePrediction(input.Text)
end)

addConnection(UserInputService.InputBegan, function(key)
	if key.KeyCode == Enum.KeyCode.Tab and input:IsFocused() and prediction.Text ~= "" then
		sleep()

		input.Text = input.Text .. prediction.Text:gsub(" ", "")

		input.CursorPosition = #input.Text + 1
	end
end)

addConnection(input:GetPropertyChangedSignal("AbsolutePosition"), repositionSuggestion)

addConnection(runner:GetPropertyChangedSignal("Position"), function()
	if runner.Position == initialPosition then
		prediction.Text = ""
		if suggestion.Visible then
			closeSuggestion()
		end
	else
		repositionSuggestion()
	end
end)

local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local closingPosition = newUDim2(0.5, 0, 0, 200)

local activeTweens = {}
local specs = {
	open = {
		{ key = "frame", props = { Position = openedPosition, BackgroundTransparency = 0.15 } },
		{ key = "input", props = { TextTransparency = 0 } },
		{ key = "title", props = { TextTransparency = 0 } },
		{ key = "chevron", props = { ImageTransparency = 0 } },
	},

	close = {
		{ key = "chevron", props = { ImageTransparency = 1 } },
		{ key = "title", props = { TextTransparency = 1 } },

		{ key = "frame", props = { Position = closingPosition, BackgroundTransparency = 1 } },
		{ key = "input", props = { TextTransparency = 1 } },
		{ key = "prediction", props = { TextTransparency = 1 } },
	},
}

local function cancelActiveTweens()
	for _, t in activeTweens do
		if t.PlaybackState ~= Enum.PlaybackState.Completed then
			t:Cancel()
		end
	end

	activeTweens = {}
end

local function getTweenableElements()
	return {
		frame = runner,
		title = runner:FindFirstChild("Title"),
		chevron = runner:FindFirstChild("Chevron"),
		input = input,
		prediction = prediction,
	}
end

local function playTweenSequence(tweenSpecifications, delayBetweenTweens, onFinalTweenComplete)
	local tweenableElements = getTweenableElements()
	for index, tweenSpec in tweenSpecifications do
		local targetElement = tweenableElements[tweenSpec.key]
		if targetElement then
			local tween = TweenService:Create(targetElement, tweenInfo, tweenSpec.props)

			insert(activeTweens, tween)

			tween:Play()

			if index == #tweenSpecifications and onFinalTweenComplete then
				tween.Completed:Connect(function()
					onFinalTweenComplete(tween)
				end)
			end

			if delayBetweenTweens and index < #tweenSpecifications then
				sleep(delayBetweenTweens)
			end
		end
	end
end

local function openRunner()
	cancelActiveTweens()
	input.Text = ""
	input:CaptureFocus()

	local elements = getTweenableElements()
	elements.frame.Position = initialPosition
	elements.frame.BackgroundTransparency = 1
	elements.frame.Visible = true

	elements.title.TextTransparency = 1
	elements.chevron.ImageTransparency = 1
	elements.input.TextTransparency = 1

	elements.prediction.TextTransparency = 0

	playTweenSequence(specs.open, 0.05)
end

local function closeRunner()
	cancelActiveTweens()

	newThread(executeCommand, input.Text)
	newThread(closeSuggestion)

	playTweenSequence(specs.close, 0.05, function(frameTween)
		local elements = getTweenableElements()
		elements.frame.Position = initialPosition
		elements.frame.Visible = false

		for i, t in activeTweens do
			if t == frameTween then
				remove(activeTweens, i)
				break
			end
		end
	end)
end

addConnection(input.FocusLost, closeRunner)

addConnection(UserInputService.InputBegan, function(entered, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	if entered.KeyCode == getSettingKeyCode("prefix") then
		delay(0, openRunner)
	end
end)

local dashActive = false
do
	local dashY
	addConnection(UserInputService.InputBegan, function(_input, gameProcessed)
		if settings:get("features.boost") then
			if gameProcessed or _input.KeyCode ~= getSettingKeyCode("boost") then
				return
			end

			currentCharacter.Animate.Enabled = false
			currentCharacter.Animate.Enabled = true

			dashActive = true
			dashY = currentRoot.Position.Y

			executeCommand("noclip")
		end
	end)

	addConnection(UserInputService.InputEnded, function(_input, gameProcessed)
		if gameProcessed or _input.KeyCode ~= getSettingKeyCode("boost") then
			return
		end

		dashActive = false
		executeCommand("clip")
	end)

	addConnection(RunService.Stepped, function()
		if not dashActive then
			return
		end

		local dir = currentHumanoid.MoveDirection
		local speed = (
			UserInputService:IsKeyDown(getSettingKeyCode("extra_boost"))
			and settings:get("features.boostExtraSpeed")
		) or settings:get("features.boostSpeed")

		local horiz = dir.Magnitude > 0 and newVector3(dir.X, 0, dir.Z).Unit * speed or Vector3.zero
		currentRoot.AssemblyLinearVelocity = newVector3(horiz.X, 0, horiz.Z)

		if math.abs(currentRoot.Position.Y - dashY) > 0.01 then
			local position = currentRoot.CFrame.Position
			currentRoot.CFrame = newCFrame(position.X, dashY, position.Z)
				* newAngles(0, rad(currentRoot.Orientation.Y), 0)
		end
	end)
end

local RECORD_INTERVAL = 0.10 -- seconds per keyframe   (10 Hz record & rewind)
local HISTORY_HOURS = 3 -- hours of history kept
do
	local SAMPLE_COUNT = math.ceil((HISTORY_HOURS * 3600) / RECORD_INTERVAL)
	local buffer = table.create(SAMPLE_COUNT) -- pre‑allocate ring
	local head, size = 0, 0 -- next write slot & fill size

	local function push(cf)
		head = (head % SAMPLE_COUNT) + 1
		buffer[head] = cf
		size = size < SAMPLE_COUNT and (size + 1) or SAMPLE_COUNT
	end

	local recordingAcc = 0
	local rewinding = false
	local segTime = 0 -- time spent inside current segment
	local segHead = 0 -- index of the *later* keyframe in segment

	local function isAltDown()
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
	end

	addConnection(UserInputService.InputBegan, function(_input, gameProcessed)
		if gameProcessed or _input.KeyCode ~= Enum.KeyCode.R or not isAltDown() or size < 2 then
			return
		end

		segTime = 0
		rewinding, segHead = true, head
		currentHumanoid.AutoRotate = false
	end)

	addConnection(UserInputService.InputEnded, function(_input, _)
		if _input.KeyCode == Enum.KeyCode.R then
			rewinding = false
			currentHumanoid.AutoRotate = true
		end
	end)

	addConnection(RunService.Heartbeat, function(dt)
		local humanoid = currentHumanoid
		local root = currentRoot
		if humanoid:GetState() == Enum.HumanoidStateType.Dead then
			return
		end

		if rewinding then
			segTime += dt
			while segTime >= RECORD_INTERVAL do
				segTime -= RECORD_INTERVAL
				segHead = (segHead - 1 <= 0) and size or (segHead - 1)
				if segHead == head then
					segTime = 0
					break
				end
			end

			local nextIdx = (segHead - 1 <= 0) and size or (segHead - 1)
			local cfLater = buffer[segHead] -- later frame (current index)
			local cfEarly = buffer[nextIdx] -- earlier frame
			local alpha = segTime / RECORD_INTERVAL
			root.CFrame = cfLater:Lerp(cfEarly, alpha)

			return
		end

		recordingAcc += dt
		if recordingAcc >= RECORD_INTERVAL then
			recordingAcc -= RECORD_INTERVAL
			push(root.CFrame)
		end
	end)

	addConnection(Player.CharacterAdded, function()
		head, size, rewinding = 0, 0, false
	end)
end

local MAX_CLICK_DISTANCE = 1500
local VALIDATE_HEIGHT = 3
do
	local function getRootClearance(rootPart, params)
		local downHit = workspace:Raycast(rootPart.Position, newVector3(0, -1000, 0), params)
		if downHit then
			return rootPart.Position.Y - downHit.Position.Y
		else
			local humanoid = currentHumanoid
			return humanoid and (humanoid.HipHeight + rootPart.Size.Y / 2) or 5
		end
	end

	local function getFirstOpaqueHit(origin, direction, params)
		local maxDist = MAX_CLICK_DISTANCE
		local dirUnit = direction.Unit
		local traveled = 0
		local startCFrame = origin

		params.FilterDescendantsInstances = params.FilterDescendantsInstances or {}

		while traveled < maxDist do
			local result = workspace:Raycast(startCFrame, dirUnit * (maxDist - traveled), params)
			if not result then
				return nil
			end

			local part = result.Instance
			if part.Transparency < 1 or not part.CanCollide then
				return result
			end

			local hitPos = result.Position
			local segmentLen = (hitPos - origin).Magnitude
			traveled = segmentLen
			if traveled >= maxDist then
				return nil
			end

			startCFrame = hitPos + dirUnit * 0.1

			insert(params.FilterDescendantsInstances, part)
		end

		return nil
	end

	local function clickTeleport(_input, gameProcessed)
		if
			gameProcessed
			or _input.UserInputType ~= Enum.UserInputType.MouseButton1
			or not UserInputService:IsKeyDown(getSettingKeyCode("teleport"))
		then
			return
		end

		local character = currentCharacter
		local humanoid = currentHumanoid
		local rootPart = currentRoot
		if not (character and humanoid and rootPart) then
			return
		end

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Blacklist
		params.FilterDescendantsInstances = { character }
		params.IgnoreWater = true

		local cam = workspace.CurrentCamera
		local ray = cam:ScreenPointToRay(_input.Position.X, _input.Position.Y)
		local hit = getFirstOpaqueHit(ray.Origin, ray.Direction, params)
		if not hit then
			return
		end

		local groundHit = workspace:Raycast(
			hit.Position + newVector3(0, VALIDATE_HEIGHT, 0),
			newVector3(0, -VALIDATE_HEIGHT - 1000, 0),
			params
		)
		local groundPos = (groundHit and groundHit.Position) or hit.Position

		local clearance = getRootClearance(rootPart, params)
		local targetPos = groundPos
			+ newVector3(0, clearance + (humanoid.RigType == Enum.HumanoidRigType.R6 and 1.5 or 0), 0)

		if humanoid.Sit then
			humanoid.Sit = false
		end

		local look = cam.CFrame.LookVector
		local forward = newVector3(look.X, 0, look.Z)
		if forward.Magnitude < 0.1 then
			forward = rootPart.CFrame.LookVector
		end

		character:PivotTo(CFrame.lookAt(targetPos, targetPos + forward.Unit))

		for _, part in character:GetChildren() do
			if part:IsA("BasePart") then
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
	addConnection(UserInputService.InputBegan, function(_input, gameProcessed)
		if settings:get("features.clickTeleport") then
			clickTeleport(_input, gameProcessed)
		end
	end)
end

-- MARK: Commands
createCommand({ "p", "print" }, {
	{ name = "input", type = "string" },
}, function(args)
	print(args.input)
end, "Prints a string to the console.")

local PlaceId, JobId = game.PlaceId, game.JobId
do
	createCommand({ "rejoin", "rj" }, nil, function()
		notify("Rejoining..")

		queue_on_teleport([[game:GetService("ReplicatedFirst"):RemoveDefaultLoadingScreen()]])

		if #Players:GetPlayers() <= 1 then
			Players.LocalPlayer:Kick("\nRejoining..")

			delay(0.15, function()
				TeleportService:Teleport(PlaceId, Players.LocalPlayer)
			end)
		else
			TeleportService:TeleportToPlaceInstance(PlaceId, JobId, Players.LocalPlayer)
		end
	end, "Rejoins the current server instance.")

	createCommand({ "rejoinrespawn", "rjre" }, nil, function()
		local Position = Players.LocalPlayer.Character:GetPivot()

		queue_on_teleport(format(
			[[
			local PlayerAdded, CharacterAdded
			PlayerAdded = game:GetService("Players").PlayerAdded:Connect(function(Player)
				CharacterAdded = Player.CharacterAdded:Connect(function(Character)
					Character:WaitForChild("HumanoidRootPart")
					Character:PivotTo(CFrame.new(%f, %f, %f))
					CharacterAdded:Disconnect()
				end)
				PlayerAdded:Disconnect()
			end)
				]],
			Position.X,
			Position.Y,
			Position.Z
		))

		executeCommand("rejoin")
	end, "Rejoins the current server and respawns at the previous location.")

	createCommand({ "serverhop", "hop" }, nil, function()
		notify("Looking for servers..")
		local servers = fetchServers()

		if #servers > 0 then
			local index = random(1, #servers)
			local choice = servers[index]
			notify("Found server! " .. color.yellow(choice.id))

			currentHumanoid.Jump = true
			TeleportService:TeleportToPlaceInstance(game.PlaceId, choice.id, Player)
		else
			notify("Serverhop couldn't find a server")
		end
	end, "Finds and teleports to a different, non-full server.")
end

local participantStateMap = {
	__mode = "k",
}

local seenBefore = {}

local function resolveName(player)
	if player.Name == player.DisplayName then
		return player.Name
	else
		return ("%s\n(@%s)"):format(player.DisplayName, player.Name)
	end
end

local function updateDisplayName(player)
	if settings:get("features.enhancedDisplays") then
		local char = player.Character
		local hum = char and char:FindFirstChild("Humanoid")
		if not hum then
			return
		end

		local nameStr = resolveName(player)
		local playerId = player.userId
		for _, userId in participantStateMap do
			if playerId == userId then
				hum.DisplayName = nameStr
				return
			end
		end

		nameStr = nameStr .. " 🔇"
		hum.DisplayName = nameStr
	end
end

local function updateAll()
	for _, player in Players:GetPlayers() do
		seenBefore[player.UserId] = true

		if player.Character and player.Character:FindFirstChild("Humanoid") then
			updateDisplayName(player)
		end

		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("Humanoid", 5)
			updateDisplayName(player)
		end)
	end
end

do
	for _, userId in VoiceChatInternal:GetParticipants() or {} do
		insert(participantStateMap, userId)

		local player = Players:GetPlayerByUserId(userId)
		if player then
			updateDisplayName(player)
		end
	end

	VoiceChatInternal.ParticipantsStateChanged:Connect(
		function(leftParticipants, joinedParticipants, updatedParticipants)
			for _, userId in leftParticipants do
				remove(participantStateMap, userId)

				local player = Players:GetPlayerByUserId(userId)
				if player then
					updateDisplayName(player)
				end
			end

			for _, userId in joinedParticipants do
				insert(participantStateMap, userId)

				local player = Players:GetPlayerByUserId(userId)
				if player then
					updateDisplayName(player)
				end
			end

			for userIdKey, state in updatedParticipants do
				local userId = tonumber(userIdKey) or userIdKey

				participantStateMap[userId] = state

				local player = Players:GetPlayerByUserId(userId)
				if player then
					updateDisplayName(player)
				end
			end
		end
	)

	local function resolveTitleName(player)
		local isFriend = Player:IsFriendsWith(player.UserId)

		local colorFunc
		if isFriend then
			colorFunc = color.green
		else
			colorFunc = color.cyan
		end

		return colorFunc(
			player.DisplayName ~= player.Name and player.DisplayName .. " (@" .. player.Name .. ")" or player.Name
		)
	end

	addConnection(Players.PlayerAdded, function(player)
		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("Humanoid", 5)
			updateDisplayName(player)
		end)

		if player.Character and player.Character:FindFirstChild("Humanoid") then
			updateDisplayName(player)
		end

		if seenBefore[player.UserId] then
			if settings:get("features.notifyRejoin") then
				notify(color.italic(resolveTitleName(player) .. " has rejoined the game"))
			end
		else
			seenBefore[player.UserId] = true

			if settings:get("features.notifyJoin") then
				notify(color.italic(resolveTitleName(player) .. " has joined the game"))
			end
		end
	end)

	addConnection(Players.PlayerRemoving, function(player)
		if settings:get("features.notifyLeave") then
			notify(color.italic(resolveTitleName(player) .. " has left the game"))
		end

		seenBefore[player.UserId] = true
	end)

	updateAll()
end

local soundHats = {
	__mode = "k",
}
do
	addConnection(Players.PlayerAdded, function(player)
		addConnection(player.CharacterAdded, function(character)
			for _, object in character:GetDescendants() do
				if object:IsA("Sound") and object.Parent.Name == "Handle" then
					insert(soundHats, object)
				end
			end

			addConnection(character.DescendantAdded, function(descendant)
				if descendant:IsA("Sound") and descendant.Parent.Name == "Handle" then
					insert(soundHats, descendant)
				end
			end)
		end)
	end)

	for _, player in Players:GetPlayers() do
		if player.Character then
			for _, object in player.Character:GetDescendants() do
				if object:IsA("Sound") and object.Parent.Name == "Handle" then
					insert(soundHats, object)
				end
			end
		end
	end
end

createCommand({ "re", "respawn" }, nil, function()
	local character = currentCharacter
	local savedPosition = character:GetPivot()

	local humanoid = currentHumanoid
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Dead)
	end

	local characterAdded
	characterAdded = Player.CharacterAdded:Connect(function(char)
		char:WaitForChild("HumanoidRootPart")
		char:PivotTo(savedPosition)
		characterAdded:Disconnect()
	end)
end, "Respawns the player character at the current location.")

createCommand({ "ire", "instantrespawn" }, nil, function()
	notify(("Respawning in %s sec(s)..."):format("~" .. color.yellow(round(Players.RespawnTime))))

	replicatesignal(Player.ConnectDiedSignalBackend)
	sleep(Players.RespawnTime - 0.02)
	local character = currentCharacter
	local savedPosition = character:GetPivot()
	local cameraCFrame = workspace.CurrentCamera.CFrame
	replicatesignal(Player.Kill)

	local characterAdded
	characterAdded = Player.CharacterAdded:Connect(function(char)
		char:WaitForChild("HumanoidRootPart")
		char:PivotTo(savedPosition)
		RunService.PreRender:Wait()
		workspace.CurrentCamera.CFrame = cameraCFrame
		characterAdded:Disconnect()
	end)
end, "Respawns the player character at the current location. But instant.")

local chatLogs = {}
local joinLeaveLogs = {}
local friendChatLogs = {}
local friendJoinLeaveLogs = {}

local chatLoggingEnabled = true
local playerLoggingEnabled = true

local chatLogSection, chatControlSection
local chatFriendLogSection, chatFriendControlSection

local playerLogSection, playerControlSection
local playerFriendLogSection, playerFriendControlSection

local function formatName(player)
	local display = player.DisplayName
	local username = player.Name
	if display:lower() == username:lower() then
		return display
	else
		return format("%s (@%s)", display, username)
	end
end

local function isFriend(plr)
	return Player:IsFriendsWith(plr.UserId)
end

local function insertEntry(tbl, section, entry)
	insert(tbl, entry)
	if section then
		section:addEntry(entry.title, entry.desc, entry.sub)
	end
end

local function hookChat(player)
	addConnection(player.Chatted, function(msg)
		if not chatLoggingEnabled then
			return
		end

		local ts = os.date("%H:%M:%S")
		local entry = {
			title = formatName(player),
			desc = msg,
			sub = ts,
		}

		insertEntry(chatLogs, chatLogSection, entry)
		if isFriend(player) then
			insertEntry(friendChatLogs, chatFriendLogSection, entry)
		end
	end)
end

for _, player in Players:GetPlayers() do
	hookChat(player)
end

addConnection(Players.PlayerAdded, function(p)
	if playerLoggingEnabled then
		local ts = os.date("%H:%M:%S")
		local entry = {
			title = formatName(p),
			desc = "joined the game",
			sub = ts,
		}

		insertEntry(joinLeaveLogs, playerLogSection, entry)
		if isFriend(p) then
			insertEntry(friendJoinLeaveLogs, playerFriendLogSection, entry)
		end
	end

	hookChat(p)
end)

addConnection(Players.PlayerRemoving, function(p)
	if playerLoggingEnabled then
		local ts = os.date("%H:%M:%S")
		local entry = {
			title = formatName(p),
			desc = "left the game",
			sub = ts,
		}

		insertEntry(joinLeaveLogs, playerLogSection, entry)
		if isFriend(p) then
			insertEntry(friendJoinLeaveLogs, playerFriendLogSection, entry)
		end
	end
end)

createCommand({ "chatlogs", "clogs" }, nil, function()
	local win = Window.new({
		name = "Chat Log",
		size = newUDim2(0, 400, 0, 450),
		icon = "rbxassetid://123574741127420",
	})

	local tabAll = win:addTab("All")

	chatControlSection = tabAll:addSection("Options")
	chatControlSection:addButton("Clear", function()
		chatLogs = {}
		if chatLogSection then
			for _, obj in chatLogSection.container:GetChildren() do
				if obj:IsA("Frame") and obj.Name == "Entry" then
					obj:Destroy()
				end
			end
		end
	end)

	chatControlSection:addButton("Save", function()
		local json = HttpService:JSONEncode(chatLogs)
		if setclipboard then
			setclipboard(json)
			notify("Chat log JSON copied to clipboard.")
		else
			warn("Clipboard unavailable; printed JSON:")
			print(json)
		end
	end)

	chatControlSection:addToggle("Logging Enabled", function(on)
		chatLoggingEnabled = on
		notify("Chat logging " .. (on and "enabled" or "disabled") .. ".")
	end, chatLoggingEnabled)

	chatLogSection = tabAll:addSection("Messages")
	for _, entry in chatLogs do
		chatLogSection:addEntry(entry.title, entry.desc, entry.sub)
	end

	local tabFriends = win:addTab("Friends")

	chatFriendControlSection = tabFriends:addSection("Options")
	chatFriendControlSection:addButton("Clear", function()
		friendChatLogs = {}
		if chatFriendLogSection then
			for _, obj in chatFriendLogSection.container:GetChildren() do
				if obj:IsA("Frame") and obj.Name == "Entry" then
					obj:Destroy()
				end
			end
		end
	end)

	chatFriendControlSection:addButton("Save", function()
		local json = HttpService:JSONEncode(friendChatLogs)
		if setclipboard then
			setclipboard(json)
			notify("Friends chat log JSON copied to clipboard.")
		else
			warn("Clipboard unavailable; printed JSON:")
			print(json)
		end
	end)

	chatFriendControlSection:addToggle("Logging Enabled", function(on)
		chatLoggingEnabled = on
		notify("Chat logging " .. (on and "enabled" or "disabled") .. ".")
	end, chatLoggingEnabled)

	chatFriendLogSection = tabFriends:addSection("Friend Messages")
	for _, entry in friendChatLogs do
		chatFriendLogSection:addEntry(entry.title, entry.desc, entry.sub)
	end
end, "Opens a live chat message log UI.")

createCommand({ "jlogs", "joinlogs" }, nil, function()
	local win = Window.new({
		name = "Player Log",
		size = newUDim2(0, 400, 0, 450),
		icon = "rbxassetid://95361495864145",
	})

	local tabAll = win:addTab("All")

	playerControlSection = tabAll:addSection("Options")
	playerControlSection:addButton("Clear", function()
		joinLeaveLogs = {}
		if playerLogSection then
			for _, obj in playerLogSection.container:GetChildren() do
				if obj:IsA("Frame") and obj.Name == "Entry" then
					obj:Destroy()
				end
			end
		end
	end)

	playerControlSection:addButton("Save", function()
		local json = HttpService:JSONEncode(joinLeaveLogs)
		if setclipboard then
			setclipboard(json)
			notify("Player log JSON copied to clipboard.")
		else
			warn("Clipboard unavailable; printed JSON:")
			print(json)
		end
	end)

	playerControlSection:addToggle("Logging Enabled", function(on)
		playerLoggingEnabled = on
		notify("Player logging " .. (on and "enabled" or "disabled") .. ".")
	end, playerLoggingEnabled)

	playerLogSection = tabAll:addSection("Events")
	for _, entry in joinLeaveLogs do
		playerLogSection:addEntry(entry.title, entry.desc, entry.sub)
	end

	local tabFriends = win:addTab("Friends")

	playerFriendControlSection = tabFriends:addSection("Options")
	playerFriendControlSection:addButton("Clear", function()
		friendJoinLeaveLogs = {}
		if playerFriendLogSection then
			for _, obj in playerFriendLogSection.container:GetChildren() do
				if obj:IsA("Frame") and obj.Name == "Entry" then
					obj:Destroy()
				end
			end
		end
	end)

	playerFriendControlSection:addButton("Save", function()
		local json = HttpService:JSONEncode(friendJoinLeaveLogs)
		if setclipboard then
			setclipboard(json)
			notify("Friends player log JSON copied to clipboard.")
		else
			warn("Clipboard unavailable; printed JSON:")
			print(json)
		end
	end)

	playerFriendControlSection:addToggle("Logging Enabled", function(on)
		playerLoggingEnabled = on
		notify("Player logging " .. (on and "enabled" or "disabled") .. ".")
	end, playerLoggingEnabled)

	playerFriendLogSection = tabFriends:addSection("Friend Events")
	for _, entry in friendJoinLeaveLogs do
		playerFriendLogSection:addEntry(entry.title, entry.desc, entry.sub)
	end
end, "Opens a live join/leave log UI (with All & Friends tabs).")

createCommand({ "to", "teleport", "goto" }, {
	{ name = "target", type = "player" },
}, function(args)
	local targetPlayer = args.target

	local localCharacter = currentCharacter
	local targetCharacter = targetPlayer.Character

	local targetPosition = targetCharacter:GetPivot()

	localCharacter:PivotTo(targetPosition)
	notify("Teleported to " .. color.cyan(targetPlayer.DisplayName))
end, "Teleports you to another player.")

createCommand({ "fling" }, {
	{ name = "target", type = "player" },
}, function(args)
	local target = args.target
	local root = currentRoot

	spoofProperty(root, "Velocity")
	spoofProperty(root, "Anchored")

	local oldPos, oldVelocity = root.CFrame, root.Velocity
	local targetRoot = target.Character:WaitForChild("HumanoidRootPart", 5)
	local targetPos = targetRoot.Position
	local running = addConnection(RunService.Stepped, function(step)
		step = step - Services.Workspace.DistributedGameTime

		root.CFrame = (targetRoot.CFrame - (newVector3(0, 1e6, 0) * step)) + (targetRoot.Velocity * (step * 30))
		root.Velocity = newVector3(0, 1e6, 0)
	end)

	local starttime = tick()
	repeat
		sleep()
	until (targetPos - targetRoot.Position).magnitude >= 60 or tick() - starttime >= 3.5

	running:Disconnect()

	sleep()

	repeat
		sleep()
		root.Velocity = oldVelocity
		root.CFrame = oldPos

	until root.Velocity == oldVelocity

	sleep(2)

	root.Anchored = true
	running:Disconnect()
	root.Anchored = false
	root.Velocity = oldVelocity
	root.CFrame = oldPos
end, "Flings the target using your character.")

createCommand({ "removechar", "delchar" }, {
	{ name = "target", type = "player" },
}, function(args)
	local targetPlayer = args.target
	local targetCharacter = targetPlayer.Character

	targetCharacter:Destroy()
end, "Deletes the target player's character.")

createCommand({ "speed", "walkspeed" }, {
	{ name = "value", type = "number" },
}, function(args)
	local humanoid = currentHumanoid
	if humanoid then
		spoofProperty(humanoid, "WalkSpeed")
		humanoid.WalkSpeed = args.value
		notify("Walkspeed set to " .. color.cyan(args.value))
	else
		notify("Couldn't find humanoid")
		return
	end
end, "Sets the player's walk speed.")

createCommand({ "hipheight", "hh" }, {
	{ name = "value", type = "number" },
}, function(args)
	local humanoid = currentHumanoid
	if humanoid then
		spoofProperty(humanoid, "HipHeight")

		humanoid.HipHeight = args.value

		notify("HipHeight set to " .. color.cyan(args.value))
	else
		notify("Couldn't find humanoid")
		return
	end
end, "Sets the player's hip height.")

createCommand({ "jumppower", "jp" }, {
	{ name = "value", type = "number" },
}, function(args)
	local humanoid = currentHumanoid
	if humanoid then
		spoofProperty(humanoid, "JumpPower")
		spoofProperty(humanoid, "UseJumpPower")

		humanoid.JumpPower = args.value

		notify("JumpPower set to " .. color.cyan(args.value))
	else
		notify("Couldn't find humanoid")
		return
	end
end, "Sets the player's jump power.")

local isNoclipEnabled = false
do
	local noclipEnabled = false
	local connections = {}

	local function clearConnections()
		for _, conn in connections do
			conn:Disconnect()
		end
		connections = {}
	end

	local function disableCollision(part)
		if part:IsA("BasePart") then
			part.CanCollide = false
		end
	end

	local function applyToCharacter(character)
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				disableCollision(part)
				spoofProperty(part, "CanCollide")
			end
		end

		connections.descAdded = character.DescendantAdded:Connect(disableCollision)

		connections.heartbeat = RunService.Heartbeat:Connect(function()
			for _, part in character:GetDescendants() do
				if part:IsA("BasePart") and part.CanCollide then
					part.CanCollide = false
				end
			end
		end)
	end

	local function enableNoclip()
		if noclipEnabled then
			return
		end
		noclipEnabled = true

		connections.charAdded = Player.CharacterAdded:Connect(function(char)
			clearConnections()
			applyToCharacter(char)
		end)

		applyToCharacter(currentCharacter)
	end

	local function disableNoclip()
		if not noclipEnabled then
			return
		end
		noclipEnabled = false

		clearConnections()

		if currentCharacter then
			for _, part in currentCharacter:GetChildren() do
				if part:IsA("BasePart") and part.Name == "Torso" or part.Name == "Head" then
					part.CanCollide = true
				end
			end
		end
	end

	createCommand({ "noclip", "nc" }, nil, function()
		if isNoclipEnabled then
			disableNoclip()
		else
			enableNoclip()
		end
		isNoclipEnabled = not isNoclipEnabled
	end, "Toggles noclip mode, allowing movement through objects.")

	createCommand({ "clip" }, nil, function()
		disableNoclip()
		isNoclipEnabled = false
	end, "Disables noclip mode.")
end

-- might come back one day?
-- createCommand({ "joinvc", "unsuspend" }, nil, function()
-- 	VoiceChatService:joinVoice()
-- end, "Attempts to join the voice chat. Useful for bypassing suspensions.")

createCommand({ "spectate", "spec", "view" }, {
	{ name = "target", type = "player" },
}, function(args)
	local target = args.target
	if not target.Character then
		notify(color.red("Target player's character not found"))
		return
	end

	workspace.CurrentCamera.CameraSubject = target.Character
end, "Changes the camera to spectate the target player.")

createCommand({ "gravity" }, {
	{ name = "value", type = "number" },
}, function(args)
	spoofProperty(workspace, "Gravity")
	workspace.Gravity = args.value
end, "Sets the workspace gravity.")

createCommand({ "spin" }, {
	{ name = "value", type = "number" },
}, function(args)
	if currentRoot:FindFirstChild("Spin") then
		currentRoot:FindFirstChild("Spin"):Destroy()
	end

	if args.value > 0 then
		create("BodyAngularVelocity", "Spin", {
			Parent = currentRoot,
			MaxTorque = Vector3.new(0, math.huge, 0),
			AngularVelocity = Vector3.new(0, args.value, 0),
		})

		notify("Started spinning!")
		return
	else
		if currentRoot:FindFirstChild("Spin") then
			currentRoot:FindFirstChild("Spin"):Destroy()
		end

		notify("Stopped spinning.")
	end

	notify("Value must be greater than 0!")
end, "Makes your character spin.")

local ascending, descending = false, false
do
	local flyLoop

	addConnection(UserInputService.InputBegan, function(_input, gameProcessed)
		if gameProcessed then
			return
		end
		if _input.KeyCode == Enum.KeyCode.E then
			ascending = true
		elseif _input.KeyCode == Enum.KeyCode.Q then
			descending = true
		end
	end)

	addConnection(UserInputService.InputEnded, function(_input, gameProcessed)
		if gameProcessed then
			return
		end
		if _input.KeyCode == Enum.KeyCode.E then
			ascending = false
		elseif _input.KeyCode == Enum.KeyCode.Q then
			descending = false
		end
	end)

	createCommand({ "fly" }, nil, function()
		if flyLoop then
			notify("Fly mode is already enabled.")
			return
		end

		local character = currentCharacter
		local humanoid = currentHumanoid

		spoofProperty(humanoid, "PlatformStand")
		humanoid.PlatformStand = true

		local Head = character:WaitForChild("Head")
		spoofProperty(Head, "Anchored")
		Head.Anchored = true

		flyLoop = addConnection(RunService.Heartbeat, function(deltaTime)
			local moveDirection = currentHumanoid.MoveDirection * (50 * deltaTime)

			local vertSpeed = 50 * deltaTime
			if ascending then
				moveDirection = moveDirection + newVector3(0, vertSpeed, 0)
			elseif descending then
				moveDirection = moveDirection + newVector3(0, -vertSpeed, 0)
			end

			local headCFrame = Head.CFrame
			local cameraCFrame = workspace.CurrentCamera.CFrame
			local cameraOffset = headCFrame:ToObjectSpace(cameraCFrame).Position
			cameraCFrame = cameraCFrame * newCFrame(-cameraOffset.X, -cameraOffset.Y, -cameraOffset.Z + 1)

			local cameraPosition = cameraCFrame.Position
			local headPosition = headCFrame.Position

			local objectSpaceVelocity = newCFrame(
				cameraPosition,
				newVector3(headPosition.X, cameraPosition.Y, headPosition.Z)
			):VectorToObjectSpace(moveDirection)

			Head.CFrame = newCFrame(headPosition) * (cameraCFrame - cameraPosition) * newCFrame(objectSpaceVelocity)
		end)

		notify("Fly mode enabled. Hold E to go up, Q to go down.")
	end, "Enables fly mode.")

	createCommand({ "unfly" }, nil, function()
		if flyLoop then
			flyLoop:Disconnect()
			flyLoop = nil
			currentHumanoid.PlatformStand = false

			local Head = currentCharacter:WaitForChild("Head")
			Head.Anchored = false
			notify("Fly mode disabled.")
		else
			notify("Fly mode is not enabled.")
		end
	end, "Disables fly mode.")
end

createCommand({ "notify" }, {
	{ name = "value", type = "string" },
}, function(args)
	notify(args.value)
end, "Displays a notification with the given text.")

createCommand({ "freeze" }, nil, function()
	local character = currentCharacter

	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			spoofProperty(part, "Anchored")
			part.Anchored = true
		end
	end
	notify("Character frozen.")
end, "Anchors all parts of the player's character, freezing them in place.")

createCommand({ "flip" }, nil, function()
	local character = currentCharacter
	local hrp = character:FindFirstChild("HumanoidRootPart")

	if hrp then
		hrp.CFrame = hrp.CFrame * newAngles(0, 0, math.pi)
		notify("Character flipped 180 degrees")
	else
		notify(format("%s not found.", tostring(color.red("HumanoidRootPart"))))
		return
	end
end, "Flips the player's character upside down.")

createCommand({ "fov" }, {
	{ name = "value", type = "number" },
}, function(args)
	local camera = workspace.CurrentCamera
	spoofProperty(camera, "FieldOfView")
	camera.FieldOfView = args.value
	notify("Field of View set to " .. color.cyan(args.value))
end, "Sets the camera's field of view.")

local waypointPosition
do
	createCommand({ "setwp", "setwaypoint" }, nil, function()
		local character = currentCharacter
		waypointPosition = character:GetPivot()
		notify("Waypoint set to current position.")
	end, "Saves the current position as a waypoint.")

	createCommand({ "gotowp", "gotowaypoint" }, nil, function()
		if not waypointPosition then
			notify("No waypoint has been set")
			return
		end

		local character = currentCharacter
		character:PivotTo(waypointPosition)
		notify("Teleported to waypoint.")
	end, "Teleports the player to the saved waypoint.")
end

createCommand({ "joindate", "accage", "age" }, {
	{ name = "target", type = "player" },
}, function(args)
	local target = args.target

	local daysOld = target.AccountAge
	if daysOld == 0 then
		notify(target.DisplayName .. " joined today!")
		return
	end

	local joinTs = os.time() - daysOld * 86400
	local joinDate = os.date("%B %d, %Y", joinTs)

	local years = floor(daysOld / 365)
	local months = floor((daysOld % 365) / 30)
	local days = daysOld % 30

	local parts = {}
	if years > 0 then
		insert(parts, years .. (years == 1 and " year" or " years"))
	end

	if months > 0 then
		insert(parts, months .. (months == 1 and " month" or " months"))
	end

	if days > 0 then
		insert(parts, days .. (days == 1 and " day" or " days"))
	end

	local ago = concat(parts, ", ")
	notify(format("%s joined on %s (%s ago)", target.DisplayName, color.cyan(joinDate), ago))
end, "Displays the target player's account join date and ag	e.")

createCommand({ "commands", "cmds" }, nil, function()
	local commandCount = 0
	for _ in commandRegistry do
		commandCount += 1
	end

	local sortedNames = {}
	for name in commandRegistry do
		insert(sortedNames, name)
	end

	sort(sortedNames)

	local commandsWin = Window.new({
		name = "Commands",
		size = newUDim2(0, 400, 0, 450),
		icon = "rbxassetid://73151131089661",
	})

	local mainTab = commandsWin:addTab("All")
	local section = mainTab:addSection("Total: " .. commandCount)

	for _, key in sortedNames do
		local data = commandRegistry[key]

		local primary = data.Aliases[1]
		local title = primary
		if data.ArgumentsDefinition and #data.ArgumentsDefinition > 0 then
			local argNames = {}
			for _, arg in data.ArgumentsDefinition do
				insert(argNames, arg.name)
			end

			title = title .. format('  <font size="%d">(%s)</font>', 17, concat(argNames, ", "))
		end

		local aliasStr = nil
		if data.Aliases and #data.Aliases > 1 then
			aliasStr = concat(data.Aliases, " / ")
		end

		local desc = data.Description or ""

		section:addEntry(title, desc, aliasStr)
	end
end, "Lists all available commands in the console.")

createCommand({ "infinitejump", "ij" }, nil, function()
	addConnection(UserInputService.JumpRequest, function()
		local humanoid = currentHumanoid
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)

	notify("Infinite Jump enabled")
end, "Enables infinite jumping.")

createCommand({ "muteallhats", "mah" }, nil, function()
	if Services.SoundService.RespectFilteringEnabled then
		notify(color.red("You cannot mute sound hats, RespectFilteringEnabled is on"))
		return
	end

	addConnection(RunService.Stepped, function()
		for _, sound in soundHats do
			sound.Playing = false
		end
	end)

	notify("Muted sound hats for all players in the server")
end, "Mutes sounds originating from player hats.")

createCommand({ "hydroxide", "rspy" }, nil, function()
	notify("Loading Hydroxide")

	local owner = "Upbolt"
	local branch = "revision"

	local function webImport(file)
		return loadstring(
			game:HttpGetAsync(("https://raw.githubusercontent.com/%s/Hydroxide/%s/%s.lua"):format(owner, branch, file)),
			file .. ".lua"
		)()
	end

	webImport("init")
	webImport("ui/main")
end, "Loads the Hydroxide script.")

createCommand({ "dex", "explorer" }, nil, function()
	notify("Loading Dex Explorer")
	loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/infyiff/backup/main/dex.lua"))()
end, "Loads Dex Explorer.")

createCommand({ "unload" }, nil, function()
	disconnectAllManagedConnections()

	holder:Destroy()
	notifHolder:Destroy()

	getgenv().SORA_LOADED = false
	notify("Script unloaded.")
end, "Unloads the script.")

createCommand({ "shiftlock" }, nil, function()
	if Player.DevEnableMouseLock then
		notify("Shiftlock is already on")
		return
	end

	Player.DevEnableMouseLock = true
	return notify("Shiftlock is now on")
end, "Enables the shift lock camera mode.")

createCommand({ "copyname", "copyuser" }, {
	{ name = "target", type = "player" },
}, function(args)
	local target = args.target
	if setclipboard then
		setclipboard(target.Name)
		notify("Copied " .. color.cyan(target.Name) .. "'s username")
	else
		notify("Your exploit doesnt support setclipboard")
	end
end, "Copies the target player's username to the clipboard.")

createCommand({ "inspect", "examine" }, {
	{ name = "target", type = "player" },
}, function(args)
	local GuiService = Services.GuiService
	GuiService:CloseInspectMenu()
	GuiService:InspectPlayerFromUserId(args.target.UserId)
	notify("Opening inspect menu for " .. color.cyan(args.target.DisplayName))
end, "Opens the Roblox inspect menu for the target player.")

createCommand({ "copyid", "copyuserid" }, {
	{ name = "target", type = "player" },
}, function(args)
	local target = args.target
	if setclipboard then
		setclipboard(target.UserId)
		notify("Copied " .. target.Name .. "'s user id (" .. color.cyan(tostring(target.UserId)) .. ")")
	else
		notify("Your exploit doesnt support setclipboard")
	end
end, "Copies the target player's user ID to the clipboard.")

createCommand({ "sit" }, nil, function()
	local humanoid = currentHumanoid
	if humanoid then
		humanoid.Sit = true
		notify("Sitting down")
	else
		notify("Could not find Humanoid to sit")
		return
	end
end, "Makes the player's character sit down.")

local walkflinging = false
createCommand({ "walkfling" }, nil, function()
	local root = currentCharacter:WaitForChild("HumanoidRootPart")

	if walkflinging then
		walkflinging = false
		return
	end

	currentHumanoid.Died:Connect(function()
		walkflinging = false
	end)

	executeCommand("noclip")
	spoofProperty(root, "Velocity")
	spoofProperty(root, "Position")

	walkflinging = true
	repeat
		RunService.Heartbeat:Wait()
		if currentCharacter then
			local vel, movel = nil, 0.1

			vel = root.Velocity
			root.Velocity = vel * 10000 + newVector3(0, 10000, 0)

			RunService.RenderStepped:Wait()
			root.Velocity = vel

			RunService.Stepped:Wait()
			root.Velocity = vel + newVector3(0, movel, 0)
			movel = movel * -1
		end
	until walkflinging == false
end, "Lets you walk around and fling people.")

createCommand({ "time", "settime" }, {
	{ name = "hour", type = "number" },
}, function(args)
	local lighting = Services.Lighting
	local hour = args.hour

	if hour < 0 or hour > 24 then
		notify(color.red("Invalid hour. Please provide a number between 0 and 24"))
		return
	end

	spoofProperty(lighting, "ClockTime")

	lighting.ClockTime = hour
	notify(format("Client time set to %.2d:00", floor(hour)))
end, "Sets the client-side time of day.")

createCommand({ "camdist", "zoomdist" }, {
	{ name = "distance", type = "number" },
}, function(args)
	local distance = args.distance

	if distance <= 0.5 then
		notify("Invalid distance. Minimum is 0.5")
		return
	end

	spoofProperty(Player, "CameraMaxZoomDistance")
	Player.CameraMaxZoomDistance = distance

	notify("Max camera zoom distance set to " .. color.cyan(distance))
end, "Sets the maximum camera zoom distance.")

local function displayTreeRecursive(instance, indentPrefix, currentDepth, maxDepth)
	if maxDepth > 0 and currentDepth >= maxDepth then
		return
	end

	local children = instance:GetChildren()

	sort(children, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)

	local childCount = #children
	for i, child in children do
		local isLast = (i == childCount)

		local branch = isLast and "└" or "├"
		local linePrefix = indentPrefix .. branch .. "── "

		print(linePrefix .. child.Name .. " [" .. child.ClassName .. "]")

		local nextIndentPrefix = indentPrefix .. (isLast and "  " or "│ ")

		if #child:GetChildren() > 0 then
			displayTreeRecursive(child, nextIndentPrefix, currentDepth + 1, maxDepth)
		end
	end
end

createCommand({ "reload" }, nil, function()
	executeCommand("unload")

	loadstring(readfile("admin.luau"))()
	notify("Script reloaded.")
end, "Unloads and reloads the script.")

createCommand({ "explore", "ls" }, {
	{ name = "path", type = "string" },
	{ name = "depth", type = "number", isOptional = true },
}, function(args)
	local targetInstance = workspace
	local pathString = args.path
	local maxDepth = args.depth and (args.depth + 1) or 2

	if pathString and #pathString > 0 then
		local codeToRun = "return " .. pathString
		local success, result = pcall(function()
			return loadstring(codeToRun)()
		end)

		if success then
			if typeof(result) == "Instance" then
				targetInstance = result
				notify("Path resolved successfully: " .. color.cyan(targetInstance:GetFullName()))
			else
				notify(
					"Error: Path resolved but did not return an Instance. Result type: "
						.. typeof(result)
						.. ". Using workspace instead"
				)
				targetInstance = workspace
			end
		else
			notify("Error resolving path '" .. pathString .. "': " .. tostring(result) .. ". Using workspace instead")
			targetInstance = workspace
		end
	else
		notify("No path provided. Exploring children of workspace")
		targetInstance = workspace
	end

	if not targetInstance then
		notify("Error: Target instance is unexpectedly nil. Aborting")
		print("------------------------------------------")
		return
	end

	local depthInfo = (maxDepth == math.huge) and "(Full Depth)" or "(Depth Limit: " .. (maxDepth - 1) .. ")"
	print("--- Tree for: " .. targetInstance:GetFullName() .. " " .. depthInfo .. " ---")

	print(targetInstance.Name .. " [" .. targetInstance.ClassName .. "]")

	local children = targetInstance:GetChildren()

	if #children == 0 then
		print((targetInstance:IsA("DataModel") and " (Workspace is empty)" or " (Instance has no children)"))
	else
		displayTreeRecursive(targetInstance, "", 1, maxDepth)
	end

	print("------------------------------------------")
end, "Lists the children of an instance path in the console.")

createCommand({ "ping" }, nil, function()
	local Stats = Services.Stats
	local DataPing = Stats.Network.ServerStatsItem["Data Ping"]

	notify(
		"Your ping is "
			.. color.yellow(format("%.2f ms", tonumber(match(DataPing.GetValueString(DataPing), "([%d%.]+)")) or 0))
	)
end, "Displays the current server ping.")

createCommand({ "values", "stats" }, nil, function()
	local player = Players.LocalPlayer
	local humanoid = currentHumanoid -- for brevity
	local terrain = workspace.Terrain
	local camera = workspace.CurrentCamera

	local freezeHumanoidValues = false
	local humanoidOriginalValues = {}
	local freezeConnections = {}

	local humanoidNumericProps = {
		"WalkSpeed",
		"JumpPower",
		"JumpHeight",
		"HipHeight",
		"MaxHealth",
		"Health",
	}

	local function watchHumanoidProperty(prop)
		if freezeConnections[prop] then
			freezeConnections[prop]:Disconnect()
		end

		humanoidOriginalValues[prop] = humanoid[prop]
		freezeConnections[prop] = humanoid:GetPropertyChangedSignal(prop):Connect(function()
			if freezeHumanoidValues and humanoid[prop] ~= humanoidOriginalValues[prop] then
				humanoid[prop] = humanoidOriginalValues[prop]
			end
		end)
	end

	local function addNumberField(section, target, property)
		if target[property] == nil then
			return
		end

		section:addTextbox(property .. " (" .. tostring(target[property]) .. ")", "FocusLost", function(text)
			local num = tonumber(text)
			if num then
				target[property] = num

				if target == humanoid and freezeHumanoidValues then
					humanoidOriginalValues[property] = num
				end

				notify(property .. " set to " .. num .. ".")
			else
				warn(property .. " must be numeric. Got '" .. text .. "'.")
			end
		end)
	end

	local function addToggleField(section, target, property)
		if target[property] == nil then
			return
		end
		section:addToggle(property, function(state)
			target[property] = state
			notify(property .. " set to " .. tostring(state) .. ".")
		end, target[property])
	end

	local function addEnumDropdown(section, target, property, enumType)
		if target[property] == nil or not Enum[enumType] then
			return
		end
		local names = {}

		for _, item in Enum[enumType]:GetEnumItems() do
			insert(names, item.Name)
		end

		section:addLabel(enumType)
		section:addDropdown(names, function(choice)
			target[property] = Enum[enumType][choice]
			notify(property .. " set to " .. choice .. ".")
		end, target[property].Name)
	end

	local function addInstanceTextbox(section, target, property)
		section:addTextbox(property .. " (" .. tostring(target[property]) .. ")", "FocusLost", function(text)
			local obj
			if text == "" then
				obj = nil
			else
				obj = game:FindFirstChild(text, true)
				if not obj then
					warn("Instance '" .. text .. "' not found. Property unchanged.")
					return
				end
			end
			target[property] = obj
			notify(property .. " set to " .. tostring(obj) .. ".")
		end)
	end

	local win = Window.new({
		name = "Value Editor",
		size = newUDim2(0, 600, 0, 640),
		icon = "rbxassetid://75564684860550",
	})

	local charTab = win:addTab("Character")
	local charEnums = charTab:addSection("Humanoid Enums")
	local charNums = charTab:addSection("Humanoid Values")
	local charBools = charTab:addSection("Humanoid Booleans")

	if humanoid then
		for _, prop in humanoidNumericProps do
			addNumberField(charNums, humanoid, prop)
		end

		charNums:addToggle("Freeze Humanoid Values", function(state)
			freezeHumanoidValues = state
			if state then
				for _, prop in humanoidNumericProps do
					watchHumanoidProperty(prop)
				end

				notify("Humanoid values frozen.")
			else
				for _, conn in freezeConnections do
					conn:Disconnect()
				end

				clear(freezeConnections)
				notify("Humanoid values unfrozen.")
			end
		end, freezeHumanoidValues)

		for _, prop in
			{
				"UseJumpPower",
				"AutoRotate",
				"AutoJumpEnabled",
				"Sit",
				"PlatformStand",
				"Jump",
				"BreakJointsOnDeath",
			}
		do
			addToggleField(charBools, humanoid, prop)
		end

		addEnumDropdown(charEnums, humanoid, "DisplayDistanceType", "HumanoidDisplayDistanceType")
		addEnumDropdown(charEnums, humanoid, "NameOcclusion", "NameOcclusion")
		addEnumDropdown(charEnums, humanoid, "HealthDisplayType", "HumanoidHealthDisplayType")
	else
		charTab:addEntry(nil, "Humanoid not found.")
	end

	local playerTab = win:addTab("Player")
	local pEnums = playerTab:addSection("Camera / Movement Modes")
	local pNums = playerTab:addSection("Numeric Settings")
	local pBools = playerTab:addSection("Toggles")

	for _, prop in
		{
			"CameraMinZoomDistance",
			"CameraMaxZoomDistance",
			"HealthDisplayDistance",
			"NameDisplayDistance",
		}
	do
		addNumberField(pNums, player, prop)
	end

	for _, prop in { "CanLoadCharacterAppearance", "DevEnableMouseLock", "AutoJumpEnabled", "Neutral" } do
		addToggleField(pBools, player, prop)
	end

	addEnumDropdown(pEnums, player, "CameraMode", "CameraMode")
	addEnumDropdown(pEnums, player, "DevCameraOcclusionMode", "DevCameraOcclusionMode")

	local wsTab = win:addTab("Workspace")
	local wsPhys = wsTab:addSection("Physics Numbers")
	local wsRefs = wsTab:addSection("References")

	for _, prop in { "Gravity", "AirDensity", "FallenPartsDestroyHeight" } do
		addNumberField(wsPhys, workspace, prop)
	end

	addInstanceTextbox(wsRefs, workspace, "CurrentCamera")

	local lightTab = win:addTab("Lighting")
	local lightEnum = lightTab:addSection("Lighting Technology")
	local lightNums = lightTab:addSection("Environment Numbers")

	addEnumDropdown(lightEnum, Services.Lighting, "Technology", "Technology")

	for _, prop in
		{
			"ClockTime",
			"Brightness",
			"ExposureCompensation",
			"FogStart",
			"FogEnd",
			"ShadowSoftness",
			"GeographicLatitude",
			"EnvironmentDiffuseScale",
			"EnvironmentSpecularScale",
		}
	do
		addNumberField(lightNums, Services.Lighting, prop)
	end

	local camTab = win:addTab("Camera")
	local camNums = camTab:addSection("Numeric")
	local camEnums = camTab:addSection("Modes")
	local camBools = camTab:addSection("Toggles")

	addNumberField(camNums, camera, "FieldOfView")
	addNumberField(camNums, camera, "NearPlaneZ")

	addEnumDropdown(camEnums, camera, "CameraType", "CameraType")
	addEnumDropdown(camEnums, camera, "FieldOfViewMode", "FieldOfViewMode")
	addToggleField(camBools, camera, "HeadLocked")

	local guiTab = win:addTab("StarterGui")
	local guiBools = guiTab:addSection("Toggles")
	for _, prop in { "ResetPlayerGuiOnSpawn", "ShowDevelopmentGui" } do
		addToggleField(guiBools, Services.StarterGui, prop)
	end

	local terrTab = win:addTab("Terrain")
	local waterSec = terrTab:addSection("Water")
	for _, prop in { "WaterWaveSize", "WaterWaveSpeed", "WaterReflectance", "WaterTransparency" } do
		addNumberField(waterSec, terrain, prop)
	end
end, "Lets you view an modify a wide array of properties.")

createCommand({ "servers" }, nil, function()
	local servers = fetchServers()

	local win = Window.new({
		name = "Servers",
		size = newUDim2(0, 400, 0, 500),
	})

	local tab = win:addTab("Server List")

	local optionsSection = tab:addSection("Options")
	optionsSection:addButton("Join Lowest Ping", function()
		if #servers > 0 then
			local lowestPingServer = servers[1]
			for _, server in servers do
				if server.ping < lowestPingServer.ping then
					lowestPingServer = server
				end
			end

			TeleportService:TeleportToPlaceInstance(game.PlaceId, lowestPingServer.id, Players.LocalPlayer)
		end
	end)

	optionsSection:addButton("Join Random", function()
		if #servers > 0 then
			TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[random(1, #servers)].id, Players.LocalPlayer)
		end
	end)

	local averagePing = 0
	local totalPing = 0

	-- Calculate average ping
	for _, server in servers do
		totalPing = totalPing + server.ping
	end
	averagePing = totalPing / #servers

	local function colorizePing(ping)
		local color
		if ping < averagePing * 0.75 then
			color = colors.green
		elseif ping < averagePing * 1.25 then
			color = colors.yellow
		else
			color = colors.red
		end

		return { text = ping .. " ms", color = color }
	end

	local serverSection = tab:addSection("Servers")
	for _, server in servers do
		local coloredPing = colorizePing(server.ping)

		local pingColorHex =
			format("#%02X%02X%02X", coloredPing.color.R * 255, coloredPing.color.G * 255, coloredPing.color.B * 255)

		serverSection:addEntry(
			server.id,
			"Ping: <font color='"
				.. pingColorHex
				.. "'>"
				.. coloredPing.text
				.. "</font>\n"
				.. "Players: "
				.. server.players
				.. "/"
				.. server.maxPlayers,
			nil
		)

		serverSection:addButton("Join Server", function()
			TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, Players.LocalPlayer)
		end)
	end
end, "View a list of servers, join the one with the lowest ping, or join any available server.")

local function countAt(endpointFmt, id)
	local data = httpGetJson(endpointFmt:format(id))
	return data and data.count or 0
end

createCommand({ "info", "playerinfo" }, {
	{ name = "target", type = "player" },
}, function(args)
	local target = args.target
	local userId = target.UserId

	local profile = httpGetJson(("https://users.roblox.com/v1/users/%d"):format(userId))
	if not profile then
		return notify("Unable to fetch profile for " .. target.Name)
	end

	local displayName = profile.displayName or target.DisplayName
	local username = profile.name or target.Name
	local description = profile.description or "No profile description"
	local membershipType = profile.membershipType or "None"

	local followers = countAt("https://friends.roblox.com/v1/users/%d/followers/count", userId)
	local following = countAt("https://friends.roblox.com/v1/users/%d/followings/count", userId)
	local friends = (httpGetJson(("https://friends.roblox.com/v1/users/%d/friends?limit=100"):format(userId))) or {}
	friends = friends.data or {}

	local groups = (httpGetJson(("https://groups.roblox.com/v1/users/%d/groups/roles"):format(userId))) or {}
	groups = groups.data or {}

	local char = target.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")

	local health, maxHealth = 0, 0
	local walkSpeed, jumpPower = 0, 0
	if humanoid then
		health, maxHealth = humanoid.Health, humanoid.MaxHealth
		walkSpeed, jumpPower = humanoid.WalkSpeed, humanoid.JumpPower
	end

	local win = Window.new({
		name = displayName,
		size = newUDim2(0, 400, 0, 450),
		icon = "rbxassetid://89230703899950",
	})

	do
		local tab = win:addTab("Overview")
		local idSec = tab:addSection("Identity")

		idSec:addViewport(char, true)
		idSec:addEntry("Display Name", displayName)
		idSec:addEntry("Username", username)
		idSec:addEntry("User ID", tostring(userId))
		idSec:addEntry("Account Age", ("%d days"):format(target.AccountAge))
		idSec:addEntry("Membership", membershipType)
		idSec:addEntry("Description", description)

		local socSec = tab:addSection("Social")
		socSec:addEntry("Followers", tostring(followers))
		socSec:addEntry("Following", tostring(following))

		local statSec = tab:addSection("Live Stats")
		statSec:addEntry("Health", ("%d / %d"):format(health, maxHealth))
		statSec:addEntry("WalkSpeed", tostring(walkSpeed))
		statSec:addEntry("JumpPower", tostring(jumpPower))
	end

	do
		local tab = win:addTab(format("Friends (%d)", #friends))
		local sec = tab:addSection("Friends List")

		if #friends == 0 then
			sec:addLabel("No friends found")
		else
			for _, friend in friends do
				local disp = (friend.displayName ~= "" and friend.displayName) or friend.name
				sec:addEntry(disp, "(@" .. friend.name .. ")")
			end
		end
	end

	do
		local function numberFormat(n)
			local numberString = tostring(n)

			local sign, int, frac = numberString:match("([+-]?)(%d+)(%.?%d*)")
			int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")

			return sign .. int .. frac
		end

		local tab = win:addTab(format("Groups (%d)", #groups))
		local sec = tab:addSection("Group Memberships")

		if #groups == 0 then
			sec:addLabel("Not in any groups")
		else
			for _, groupData in groups do
				sec:addEntry(
					groupData.group.name,
					("Role: %s (%d)"):format(groupData.role.name, groupData.role.rank),
					numberFormat(groupData.group.memberCount) .. " members"
				)
			end
		end
	end

	do
		local tab = win:addTab("Accessories")
		local ok, info = pcall(Players.GetCharacterAppearanceInfoAsync, Players, userId)
		local assets = (ok and info and info.assets) or nil

		if not assets then
			tab:addSection("Error"):addLabel("⚠️ Failed to fetch appearance")
			return
		elseif #assets == 0 then
			tab:addSection("None"):addLabel("No accessories / face / head equipped")
			return
		end

		-- group by type
		local grouped = {}
		for _, asset in assets do
			local key = (asset.assetType and asset.assetType.name) or "Other"
			(grouped[key] or table.create(0))[#(grouped[key] or {}) + 1] = asset
			grouped[key] = grouped[key] or { asset } -- first insert when nil
		end

		local ORDER = {
			"HairAccessory",
			"Hat",
			"Face",
			"FaceAccessory",
			"NeckAccessory",
			"ShoulderAccessory",
			"FrontAccessory",
			"BackAccessory",
			"WaistAccessory",
			"Shirt",
			"Jacket",
			"Sweater",
			"TShirt",
			"Pants",
			"ShirtAccessory",
			"JacketAccessory",
			"SweaterAccessory",
			"PantsAccessory",
			"Head",
			"Torso",
			"LeftArm",
			"RightArm",
			"LeftLeg",
			"RightLeg",
		}

		local function render(cat)
			local list = grouped[cat]
			if not list then
				return
			end

			local sec = tab:addSection(cat)
			for _, accessory in list do
				sec:addEntry(accessory.name, tostring(accessory.id))
			end
		end

		for _, category in ORDER do
			render(category)
		end
	end
end, "Show extended profile, social stats, friends, groups, and accessories for a player.")

local function toTitleCase(snakeStr)
	local words = {}
	for word in string.gmatch(snakeStr, "[^_]+") do
		local _lower = lower(word)
		local capitalized = string.upper(string.sub(_lower, 1, 1)) .. string.sub(_lower, 2)

		insert(words, capitalized)
	end

	return concat(words, " ")
end

createCommand({ "settings", "config" }, nil, function()
	local win = Window.new({
		name = "Settings",
		icon = "rbxassetid://119339965149654",
		size = newUDim2(0, 450, 0, 500),
	})

	local generalTab = win:addTab("General")
	do
		local keySection = generalTab:addSection("Keybinds")
		for keyName, _ in Sora.keys do
			keySection:addTextbox(
				toTitleCase(keyName) .. " (" .. settings:get("keys." .. keyName) .. ")",
				"FocusLost",
				function(txt)
					if #txt > 0 then
						settings:set("keys." .. keyName, txt)
					end
				end
			)
		end

		local custSection = generalTab:addSection("Customization")
		custSection:addTextbox(
			("Accent color (hex or r,g,b) - (#%02X%02X%02X)"):format(table.unpack(settings:get("customization.accent"))),
			"FocusLost",
			function(txt)
				txt = txt:match("^%s*(.-)%s*$")

				local r, g, b
				local hex = txt:gsub("^#", "") -- strip leading #
				if hex:match("^[%x]+$") then -- only hex chars?
					if #hex == 3 then -- #abc ➟ #aabbcc
						hex = hex:gsub(".", "%1%1")
					end

					if #hex == 6 then
						r = tonumber(hex:sub(1, 2), 16)
						g = tonumber(hex:sub(3, 4), 16)
						b = tonumber(hex:sub(5, 6), 16)
					elseif #hex == 8 and txt:sub(1, 2) == "0x" then
						-- 0xAARRGGBB or 0xRRGGBB? (keep simplest: assume RRGGBB)
						r = tonumber(hex:sub(3, 4), 16)
						g = tonumber(hex:sub(5, 6), 16)
						b = tonumber(hex:sub(7, 8), 16)
					end
				end

				if not r then
					local parts = {}
					for num in txt:gmatch("%d+") do
						parts[#parts + 1] = tonumber(num)
					end
					if #parts == 3 and parts[1] <= 255 and parts[2] <= 255 and parts[3] <= 255 then
						r, g, b = table.unpack(parts)
					end
				end

				if r and g and b then
					settings:set("customization.accent", { r, g, b })
				else
					warn(("Accent colour: '%s' is invalid - keeping previous value"):format(txt))
				end
			end
		)

		custSection:addTextbox("Notification Sound ID", "FocusLost", function(txt)
			if #txt > 0 then
				settings:set("customization.notificationSound", txt)
			end
		end)

		custSection:addTextbox("Boot Sound ID", "FocusLost", function(txt)
			if #txt > 0 then
				settings:set("customization.bootSound", txt)
			end
		end)

		custSection:addTextbox("Font ID", "FocusLost", function(txt)
			if #txt > 0 then
				settings:set("customization.font", txt)
			end
		end)

		local ctrlSection = generalTab:addSection("Controls")
		ctrlSection:addButton("Reset to Defaults", function()
			settings:reset()
			notify("Settings have been reset to defaults.")
		end)

		ctrlSection:addButton("Reload", function()
			executeCommand("reload")
		end)
	end

	local notifTab = win:addTab("Notifications")
	do
		local notifSection = notifTab:addSection("Notification Settings")
		notifSection:addTextbox(
			"Notification Length (" .. settings:get("customization.notificationLength") .. "s)",
			"FocusLost",
			function(txt)
				local v = tonumber(txt)
				if v then
					settings:set("customization.notificationLength", v)
				end
			end
		)
		notifSection:addToggle("Notification Sound Enabled", function(on)
			settings:set("features.notificationSoundEnabled", on)
		end, settings:get("features.notificationSoundEnabled"))
		notifSection:addTextbox(
			"Notification Volume (" .. settings:get("features.notificationVolume") .. ")",
			"FocusLost",
			function(txt)
				local v = tonumber(txt)
				if v then
					settings:set("features.notificationVolume", v)
				end
			end
		)
	end

	local featTab = win:addTab("Features")
	do
		local featSection = featTab:addSection("Feature Options")
		featSection:addToggle("Enhanced Display Names", function(on)
			settings:set("features.enhancedDisplays", on)

			updateAll()
		end, settings:get("features.enhancedDisplays"))

		featSection:addToggle("Boot Sound Enabled", function(on)
			settings:set("features.bootSoundEnabled", on)
		end, settings:get("features.bootSoundEnabled"))

		featSection:addToggle("Player Join Notifications", function(on)
			settings:set("features.notifyJoin", on)
		end, settings:get("features.notifyJoin"))

		featSection:addToggle("Player Leave Notifications", function(on)
			settings:set("features.notifyLeave", on)
		end, settings:get("features.notifyLeave"))

		featSection:addToggle("Player Rejoin Notifications", function(on)
			settings:set("features.notifyRejoin", on)
		end, settings:get("features.notifyRejoin"))

		featSection:addToggle("Click Teleport", function(on)
			settings:set("features.clickTeleport", on)
		end, settings:get("features.clickTeleport"))

		featSection:addToggle("Boost", function(on)
			settings:set("features.boost", on)
		end, settings:get("features.boost"))

		featSection:addTextbox("Boost Speed (" .. settings:get("features.boostSpeed") .. ")", "FocusLost", function(txt)
			if #txt > 0 then
				settings:set("features.boostSpeed", txt)
			end
		end)

		featSection:addTextbox(
			"Boost Extra Speed (" .. settings:get("features.boostExtraSpeed") .. ")",
			"FocusLost",
			function(txt)
				if #txt > 0 then
					settings:set("features.boostEXtraSpeed", txt)
				end
			end
		)
	end
end, "Opens the Settings UI.")

local elapsed = tick() - start
do
	local value, unit, fmt
	if elapsed < 1e-3 then
		value, unit, fmt = elapsed * 1e6, "µs", "%.0f"
	elseif elapsed < 1.0 then
		value, unit, fmt = elapsed * 1e3, "ms", "%.1f"
	else
		value, unit, fmt = elapsed, "s", "%.3f"
	end

	local message =
		format(color.italic("Sora loaded in " .. color.yellow(fmt) .. " %s"), value, color.italic(color.yellow(unit)))

	if settings:get("features.bootSoundEnabled") then
		local bootSound = create("Sound", "Sound", {
			RollOffMode = Enum.RollOffMode.InverseTapered,
			SoundId = settings:get("customization.bootSound"),
			Parent = Player.Character,
			Volume = 0.4,
		})

		bootSound:Play()
	end

	notify(message)
end
