local box
local mode = 1
local xenon = {}

function xenon.log(text)
	local xenonFile
	if not fs.exists("xenon.log") then
		xenonFile = fs.open("xenon.log", "w")
	else
		xenonFile = fs.open("xenon.log", "a")
	end

	xenonFile.writeLine(text)
	xenonFile.close()
end

if term.drawPixels then
	term.setGraphicsMode(mode)
	box = require("/xenon_engine/drawing/pb_lite").new(term.current(), nil, {
		require("/xenon_engine/drawing/pb_gfxrnd"),

		force = false,
		suppress = false,
	})
else
	box = require("/xenon_engine/drawing/pb_lite").new(term.current())
end

local function q_round(num)
	return math.floor(num + 0.5)
end

local function outer_print(text, delay, y)
	delay = delay or 0.3
	y = y or select(2, term.getCursorPos())
	local termWidth = term.getSize()
	local textLen = #text

	if textLen % 2 == 0 then
		text = text .. " "
		textLen = textLen + 1
	end

	local center = math.ceil(textLen / 2)
	local screenCenter = math.ceil(termWidth / 2)
	local steps = math.ceil(textLen / 2)

	for step = 0, steps do
		local left = math.max(1, center - step)
		local right = math.min(textLen, center + step)
		local slice = text:sub(left, right)
		local sliceLen = #slice
		local startX = screenCenter - math.floor(sliceLen / 2)

		term.setCursorPos(startX, y)
		term.write(slice)
		sleep(delay)
	end
end

local function rotate_left(grid)
	local H = #grid
	local W = 0
	for _, row in ipairs(grid) do
		W = math.max(W, #row)
	end

	local norm = {}
	for _, row in ipairs(grid) do
		if #row < W then
			row = row .. string.rep("0", W - #row)
		end
		table.insert(norm, row)
	end

	local out = {}
	for col = 1, W do
		local newrow = {}

		for row = 1, H do
			newrow[row] = norm[row]:sub(W - col + 1, W - col + 1)
		end
		out[col] = table.concat(newrow)
	end

	return out
end

local function rotate_right(grid)
	local H = #grid
	local W = 0
	for _, row in ipairs(grid) do
		W = math.max(W, #row)
	end

	local norm = {}
	for _, row in ipairs(grid) do
		if #row < W then
			row = row .. string.rep("0", W - #row)
		end
		table.insert(norm, row)
	end

	local out = {}
	for col = 1, W do
		local newrow = {}

		for i = 1, H do
			newrow[i] = norm[H - i + 1]:sub(col, col)
		end
		out[col] = table.concat(newrow)
	end

	return out
end

local function rotate_180(grid)
	local H = #grid
	local W = 0
	for _, row in ipairs(grid) do
		W = math.max(W, #row)
	end

	local norm = {}
	for _, row in ipairs(grid) do
		if #row < W then
			row = row .. string.rep("0", W - #row)
		end
		table.insert(norm, row)
	end

	local out = {}
	for r = 1, H do
		local src = norm[H - r + 1]
		local newrow = {}

		for c = 1, W do
			newrow[c] = src:sub(W - c + 1, W - c + 1)
		end
		out[r] = table.concat(newrow)
	end

	return out
end

local frame_cache = {}
local frame_cache_usage = {}
local frame_cache_order = {}
local MAX_CACHE_SIZE = 100

local function touch_cache_key(key)
	if frame_cache_usage[key] then
		-- Move to end of list
		for i = #frame_cache_order, 1, -1 do
			if frame_cache_order[i] == key then
				table.remove(frame_cache_order, i)
				break
			end
		end
	end
	frame_cache_usage[key] = true
	table.insert(frame_cache_order, key)
end

local function evict_if_needed()
	while #frame_cache_order > MAX_CACHE_SIZE do
		local oldest = table.remove(frame_cache_order, 1)
		frame_cache[oldest] = nil
		frame_cache_usage[oldest] = nil
	end
end

local function get_cached_frame(path, rotation)
	local cache_key = path .. "|" .. (rotation or "none")
	local cached = frame_cache[cache_key]
	if cached then
		touch_cache_key(cache_key)
		return cached
	end

	if not fs.exists(path) then
		return nil
	end

	local f = fs.open(path, "r")
	local lines = {}
	while true do
		local line = f.readLine()
		if not line then
			break
		end
		table.insert(lines, line)
	end
	f.close()

	if rotation == "left" then
		lines = rotate_left(lines)
	elseif rotation == "right" then
		lines = rotate_right(lines)
	elseif rotation == "down" then
		lines = rotate_180(lines)
	end

	frame_cache[cache_key] = lines
	touch_cache_key(cache_key)
	evict_if_needed()
	return lines
end

local function compact_dirty_rects(rects)
	local seen = {}
	local out = {}
	for _, r in ipairs(rects) do
		local key = string.format("%d,%d,%d,%d", r.x1, r.y1, r.x2, r.y2)
		if not seen[key] then
			seen[key] = true
			table.insert(out, r)
		end
	end
	return out
end

xenon.sprites = {}
xenon.still_sprites = {}

local cwd = "/"
local spriteListeners = {}
local eventQueue = {}
local deletionQueue = {}
local keyStates = {}
local keyCallbacks = {}
local keyRepeatTimers = {}

local term_w, term_h = term.getSize(mode)
local px_w, px_h
if mode == 0 then
	px_w, px_h = term_w * 2, term_h * 3
else
	px_w, px_h = term_w, term_h
end

local dirtyRects = {}
local background = {}

for y = 0, px_h - 1 do
	background[y] = {}
	for x = 0, px_w - 1 do
		background[y][x] = colors.black
	end
end

local currentScene = "Scene 1"

function xenon.setScene(sceneName)
	currentScene = sceneName
end

function xenon.getScene()
	return currentScene
end

function xenon.clearSceneSprites(sceneName)
	for name, sprite in pairs(xenon.sprites) do
		if sprite.scene == sceneName then
			xenon.sprites[name] = nil
		end
	end
	for name, sprite in pairs(xenon.still_sprites) do
		if sprite.scene == sceneName then
			xenon.still_sprites[name] = nil
		end
	end
end

function xenon.clearScreen()
	term.setBackgroundColor(colors.black)
	term.clear()
	for y = 0, px_h - 1 do
		for x = 0, px_w - 1 do
			background[y][x] = colors.black
		end
	end
	dirtyRects = {
		{ x1 = 0, y1 = 0, x2 = px_w - 1, y2 = px_h - 1 },
	}
end

function xenon.titleScreen()
	xenon.clearScreen()
	local w, h = term.getSize(mode)
	local half_width = w / 2
	local half_height = h / 2

	term.setTextColor(colors.lightGray)
	outer_print("XENON Engine", 0.02, 5)

	sleep(0.1)

	term.setTextColor(colors.white)
	outer_print("XENON Engine", 0.02, 5)

	term.setCursorPos(1, 10)
end

function xenon.setCWD(path)
	cwd = (path and fs.exists(path)) and path or error("Invalid path provided to xenon.setCWD", 0)
end

local function check_anim(key, refData, baseDir)
	local anim = refData[key]
	if not anim then
		error("Missing '" .. key .. "' animation in sprite reference.")
	elseif type(anim) ~= "table" or type(anim.anims) ~= "table" then
		error("Animation '" .. key .. "' must be a table with an 'anims' list.")
	else
		for i, animPath in ipairs(anim.anims) do
			local fullPath = fs.combine(baseDir, animPath)
			if not fs.exists(fullPath) then
				error("Animation file for '" .. key .. "' frame #" .. i .. " not found: " .. fullPath)
			end
		end
	end
end

local function apply_common_sprite_methods(sprite, name, spriteTable)
	function sprite:MarkDirty()
		if self.prevPosition then
			local w, h = self:GetSize()
			table.insert(dirtyRects, {
				x1 = math.max(0, self.prevPosition[1]),
				y1 = math.max(0, self.prevPosition[2]),
				x2 = math.min(px_w - 1, self.prevPosition[1] + w - 1),
				y2 = math.min(px_h - 1, self.prevPosition[2] + h - 1),
			})
		end

		local w, h = self:GetSize()
		table.insert(dirtyRects, {
			x1 = math.max(0, self.position[1]),
			y1 = math.max(0, self.position[2]),
			x2 = math.min(px_w - 1, self.position[1] + w - 1),
			y2 = math.min(px_h - 1, self.position[2] + h - 1),
		})
	end

	function sprite:SetPosition(x, y)
		self.prevPosition = { self.position[1], self.position[2] }
		self.position[1] = q_round(x)
		self.position[2] = q_round(y)
		self:MarkDirty()
	end

	function sprite:GetSize()
		if self.activeAnimation then
			local anim_data = self.data[self.activeAnimation]
			if anim_data then
				local index = self.activeFrame or 1
				local frame_path = fs.combine(self.baseDir, anim_data.anims[index])
				local lines = get_cached_frame(frame_path, self.facing)
				if lines then
					return #lines[1], #lines
				end
			end
		elseif self.data.sprite then
			local frame_path = fs.combine(self.baseDir, self.data.sprite)
			local lines = get_cached_frame(frame_path)
			if lines then
				return #lines[1], #lines
			end
		end
		return 16, 16
	end

	function sprite:Move(dx, dy)
		self.prevPosition = { self.position[1], self.position[2] }

		if self.position[1] + dx > px_w or self.position[1] + dx < 0 then
			return
		end
		self.position[1] = q_round(self.position[1] + dx)

		if self.position[2] + dy > px_h or self.position[2] + dy < 0 then
			return
		end
		self.position[2] = q_round(self.position[2] + dy)

		self:MarkDirty()
	end

	function sprite:Delete(time)
		time = time or 0
		table.insert(deletionQueue, { spriteTable, self.name, os.epoch("utc") / 1000 + time })
	end

	function sprite:SetScene(scene)
		self.scene = scene
	end

	function sprite:SetLayer(layer)
		if type(layer) ~= "number" then
			error("Layer must be a number, not a " .. type(layer))
		end
		self.layer = layer
	end

	function sprite:GetMetadataValue(key)
		return self.meta[key]
	end

	function sprite:SetMetadataValue(key, value)
		self.meta[key] = value
	end

	function sprite:AttachOnSpriteClick(func)
		spriteListeners["onSpriteClick"] = spriteListeners["onSpriteClick"] or {}
		table.insert(spriteListeners["onSpriteClick"], { self, func })
	end

	function sprite:SmoothPosition(x, y, time)
		local sx, sy = self.position[1], self.position[2]
		local steps = math.max(1, math.floor(time / 0.05))
		self._smooth = {
			start = { sx, sy },
			target = { x, y },
			time = time,
			t = 0,
			steps = steps,
		}
	end

	function sprite:SmoothMove(x, y, time)
		local sx, sy = self.position[1], self.position[2]
		local steps = math.max(1, math.floor(time / 0.05))
		self._smooth = {
			start = { sx, sy },
			target = { sx + x, sy + y },
			time = time,
			t = 0,
			steps = steps,
		}
	end

	function sprite:SetIdle(isIdle)
		self.idle = isIdle
	end

	function sprite:FireAnimation(animation)
		if not self.data[animation] then
			error("Animation '" .. animation .. "' not found in sprite reference")
		end
		self.activeAnimation = animation
		self.activeFrame = 1
		self.activeTimer = 0
		self._endOfAnim = nil
	end
end

function xenon.newSpriteRef(name, refPath)
	if xenon.sprites[name] then
		error("Sprite name '" .. name .. "' already exists", 2)
	end

	refPath = fs.combine(cwd, refPath)
	if (not refPath) or (not fs.exists(refPath)) then
		error("Sprite reference " .. refPath .. " not found for xenon.newSpriteRef")
	end

	local refFile = fs.open(refPath, "r")
	local refData = textutils.unserialise(refFile.readAll())
	refFile.close()

	local baseDir = fs.getDir(refPath)

	if not refData.allAnim then
		check_anim("forward", refData.movingAnim, baseDir)
		check_anim("left", refData.movingAnim, baseDir)
		check_anim("right", refData.movingAnim, baseDir)
		check_anim("down", refData.movingAnim, baseDir)
	else
		if not fs.exists(fs.combine(baseDir, refData.allAnim.anims[1])) then
			error("allAnim animation file not found")
		end
	end

	if not refData.allIdle then
		check_anim("idleForward", refData.idleAnim, baseDir)
		check_anim("idleLeft", refData.idleAnim, baseDir)
		check_anim("idleRight", refData.idleAnim, baseDir)
		check_anim("idleDown", refData.idleAnim, baseDir)
	else
		if not fs.exists(fs.combine(baseDir, refData.allIdle.anims[1])) then
			error("allIdle animation file not found")
		end
	end

	for _, animSet in pairs(refData) do
		if type(animSet) == "table" and animSet.anims then
			animSet.duration = tonumber(animSet.duration) or 0.1
		end
	end

	local newSprite = {
		position = { 0, 0 },
		meta = {},
		name = name,
		baseDir = baseDir,
		facing = "forward",
		idle = true,
		data = refData,
		scene = "Scene 1",
		layer = 0,
		activeAnimation = nil,
		activeFrame = 1,
		activeTimer = 0,
	}

	apply_common_sprite_methods(newSprite, name, xenon.sprites)
	newSprite:MarkDirty()

	function newSprite:SetDirection(direction)
		local valid = { forward = true, left = true, right = true, down = true }
		if not valid[direction] then
			error("sprite:SetDirection must use forward, left, right, or down as a direction.", 0)
		end

		self.facing = direction
	end

	function newSprite:AttachOnClick(func)
		spriteListeners["onClick"] = spriteListeners["onClick"] or {}
		table.insert(spriteListeners["onClick"], { self, func })
	end

	function newSprite:LookAt(x, y)
		local dx = x - self.position[1]
		local dy = y - self.position[2]
		if math.abs(dx) > math.abs(dy) then
			self.facing = (dx > 0) and "right" or "left"
		else
			self.facing = (dy > 0) and "down" or "forward"
		end
	end

	xenon.sprites[name] = newSprite

	return newSprite
end

function xenon.newStillSpriteRef(name, refPath)
	if xenon.still_sprites[name] then
		error("Sprite name '" .. name .. "' already exists", 2)
	end

	refPath = fs.combine(cwd, refPath)
	if (not refPath) or (not fs.exists(refPath)) then
		error("Sprite reference " .. refPath .. " not found for xenon.newStillSpriteRef")
	end

	local refFile = fs.open(refPath, "r")
	local refData = textutils.unserialise(refFile.readAll())
	refFile.close()

	for _, animSet in pairs(refData) do
		if type(animSet) == "table" and animSet.anims then
			animSet.duration = tonumber(animSet.duration) or 0.1
		end
	end

	if not refData.sprite then
		error("Sprite image not found", 0)
	end

	local baseDir = fs.getDir(refPath)

	local newSprite = {
		position = { 0, 0 },
		meta = {},
		name = name,
		baseDir = baseDir,
		data = refData,
		scene = "Scene 1",
		layer = 0,
		facing = "forward",
	}

	apply_common_sprite_methods(newSprite, name, xenon.still_sprites)
	newSprite:MarkDirty()

	local x0, y0 = newSprite.position[1], newSprite.position[2]
	local frame_path = fs.combine(newSprite.baseDir, newSprite.data.sprite)
	local lines = get_cached_frame(frame_path)

	if lines then
		local width = #lines[1]
		local height = #lines

		if x0 + width > 0 and x0 < px_w and y0 + height > 0 and y0 < px_h then
			for dy = 1, height do
				local py = y0 + dy - 1
				if py >= 0 and py < px_h then
					local row = lines[dy]
					local rowLen = #row
					for dx = 1, rowLen do
						local px = x0 + dx - 1
						local hex = row:sub(dx, dx)
						local color_value = colors.fromBlit(hex)
						if color_value and px >= 0 and px < px_w then
							box:set_pixel(px, py, color_value)
						end
					end
				end
			end
		end
	end

	xenon.still_sprites[name] = newSprite

	return newSprite
end

function xenon.inputLoop()
	while true do
		local event, key = os.pullEvent()

		if event == "key" then
			local keyName = keys.getName(key)
			keyStates[keyName] = { pressed = true, held = false }

			if keyCallbacks[keyName] then
				for _, callback in ipairs(keyCallbacks[keyName]) do
					callback("press")
				end
			end

			keyRepeatTimers[keyName] = os.startTimer(0.4)
		elseif event == "key_up" then
			local keyName = keys.getName(key)
			keyStates[keyName] = { pressed = false, held = false }

			if keyRepeatTimers[keyName] then
				os.cancelTimer(keyRepeatTimers[keyName])
				keyRepeatTimers[keyName] = nil
			end

			if keyCallbacks[keyName] then
				for _, callback in ipairs(keyCallbacks[keyName]) do
					callback("release")
				end
			end
		elseif event == "timer" and keyRepeatTimers[key] then
			local keyName = keys.getName(key)
			if keyStates[keyName] and keyStates[keyName].pressed then
				keyStates[keyName].held = true

				if keyCallbacks[keyName] then
					for _, callback in ipairs(keyCallbacks[keyName]) do
						callback("held")
					end
				end

				keyRepeatTimers[keyName] = os.startTimer(0.05)
			end
		end
	end
end

function xenon.registerKey(key, callback, options)
	options = options or {}
	keyCallbacks[key] = keyCallbacks[key] or {}
	table.insert(keyCallbacks[key], callback)
end

function xenon.getKeyState(key)
	if not keyStates[key] then
		return {
			pressed = false,
			held = false,
			released = not keyStates[key] and true or false,
		}
	end
	return keyStates[key]
end

function xenon.clearKeyTransients()
	for key, state in pairs(keyStates) do
		state.pressed = false
		state.released = not state.pressed and not state.held
	end
end

function xenon.createMovementSystem(sprite, options)
	options = options or {}
	local system = {
		sprite = sprite,
		speed = options.speed or 5,
		moveInterval = options.moveInterval or 0.1,
		directions = {
			w = { x = 0, y = -1 },
			s = { x = 0, y = 1 },
			a = { x = -1, y = 0 },
			d = { x = 1, y = 0 },
		},
		isMoving = false,
		movementVector = { x = 0, y = 0 },
		lastMoveTime = os.clock(),
	}

	for key, vector in pairs(system.directions) do
		xenon.registerKey(key, function(state)
			if state == "press" or state == "held" then
				system.movementVector.y = (key == "w" and -1) or (key == "s" and 1) or system.movementVector.y
				system.movementVector.x = (key == "a" and -1) or (key == "d" and 1) or system.movementVector.x
				system.isMoving = true
				system.sprite:SetIdle(false)
			elseif state == "release" then
				if key == "w" or key == "s" then
					system.movementVector.y = 0
				end
				if key == "a" or key == "d" then
					system.movementVector.x = 0
				end
				system.isMoving = (system.movementVector.x ~= 0 or system.movementVector.y ~= 0)
				system.sprite:SetIdle(not system.isMoving)
			end
		end)
	end

	function system:Update()
		local currentTime = os.clock()
		if self.isMoving and currentTime - self.lastMoveTime >= self.moveInterval then
			local dx, dy = self.movementVector.x, self.movementVector.y

			if dx ~= 0 and dy ~= 0 then
				dx = dx * 0.7071
				dy = dy * 0.7071
			end

			if math.abs(dx) > math.abs(dy) then
				self.sprite:SetDirection(dx > 0 and "right" or "left")
			else
				self.sprite:SetDirection(dy > 0 and "down" or "forward")
			end

			self.sprite:SmoothMove(
				math.floor(dx * self.speed + 0.5),
				math.floor(dy * self.speed + 0.5),
				self.moveInterval
			)

			self.lastMoveTime = currentTime
		end
	end

	return system
end

function xenon.createProjectileSystem(source, options)
	options = options or {}
	local system = {
		projectiles = {},
		source = source,
		spritePath = options.spritePath or "testgame/assets/spriterefs/fire.spr",
		speed = options.speed or 8,
		lifetime = options.lifetime or 3,
		offset = options.offset or 0,
		layer = options.layer or (source.layer + 1),
	}

	function system:Fire(direction)
		direction = direction or self.source.facing or "forward"
		local projName = "proj_" .. os.epoch("utc")
		local proj = xenon.newStillSpriteRef(projName, self.spritePath)
		proj.facing = direction
		proj.layer = self.layer

		local charX, charY = self.source.position[1], self.source.position[2]
		local charW, charH = self.source:GetSize()
		local projW, projH = proj:GetSize()

		local spawnX, spawnY = charX, charY

		if direction == "right" then
			spawnX = charX + charW + self.offset
			spawnY = charY + (charH / 2) - (projH / 2)
		elseif direction == "left" then
			spawnX = charX - projW - self.offset
			spawnY = charY + (charH / 2) - (projH / 2)
		elseif direction == "down" then
			spawnX = charX + (charW / 2) - (projW / 2)
			spawnY = charY + charH + self.offset
		else
			spawnX = charX + (charW / 2) - (projW / 2)
			spawnY = charY - projH - self.offset
		end

		proj:SetPosition(spawnX, spawnY)

		local dx, dy = 0, 0
		if direction == "right" then
			dx = self.speed
		elseif direction == "left" then
			dx = -self.speed
		elseif direction == "down" then
			dy = self.speed
		else
			dy = -self.speed
		end

		proj:SmoothMove(dx * 5, dy * 5, 0.5)

		proj:Delete(self.lifetime)

		table.insert(self.projectiles, proj)
		return proj
	end

	function system:Update()
		for i = #self.projectiles, 1, -1 do
			if not self.projectiles[i].position then
				table.remove(self.projectiles, i)
			end
		end
	end

	return system
end

function xenon.createCollisionGroup()
	local group = {
		members = {},
	}

	function group:add(sprite)
		table.insert(self.members, sprite)
	end

	function group:remove(sprite)
		for i, member in ipairs(self.members) do
			if member == sprite then
				table.remove(self.members, i)
				return true
			end
		end
		return false
	end

	function group:checkCollisions(otherGroup, callback)
		for _, spriteA in ipairs(self.members) do
			if spriteA.position then
				local ax1, ay1 = spriteA.position[1], spriteA.position[2]
				local aw, ah = spriteA:GetSize()
				local ax2, ay2 = ax1 + aw, ay1 + ah

				for _, spriteB in ipairs(otherGroup.members) do
					if spriteB.position and spriteA ~= spriteB then
						local bx1, by1 = spriteB.position[1], spriteB.position[2]
						local bw, bh = spriteB:GetSize()
						local bx2, by2 = bx1 + bw, by1 + bh

						if ax1 < bx2 and ax2 > bx1 and ay1 < by2 and ay2 > by1 then
							if callback then
								callback(spriteA, spriteB)
							end
						end
					end
				end
			end
		end
	end

	return group
end

local t = 0

function xenon.update(dt)
	xenon.clearKeyTransients()
	for i, sprite in ipairs(deletionQueue) do
		if sprite[3] <= os.epoch("utc") / 1000 then
			table.remove(deletionQueue, i)
			rawset(sprite[1], sprite[2], nil)
		end
	end

	dirtyRects = compact_dirty_rects(dirtyRects)
	for _, rect in ipairs(dirtyRects) do
		for y = math.max(0, rect.y1), math.min(px_h - 1, rect.y2) do
			for x = math.max(0, rect.x1), math.min(px_w - 1, rect.x2) do
				if background[y] and background[y][x] then
					box:set_pixel(x, y, background[y][x])
				end
			end
		end
	end
	dirtyRects = {}

	t = t + dt

	while #eventQueue ~= 0 do
		local event = table.remove(eventQueue, 1)
		if event[1] == "onClick" then
			for _, callback in ipairs(spriteListeners["onClick"] or {}) do
				callback[2](callback[1], event[2], event[3])
			end
		end
	end

	local collectedSprites = {}
	for _, sprite in pairs(xenon.sprites) do
		if sprite.scene == currentScene then
			table.insert(collectedSprites, sprite)
		end
	end
	table.sort(collectedSprites, function(a, b)
		return a.layer < b.layer
	end)

	for _, sprite in ipairs(collectedSprites) do
		if sprite._smooth then
			sprite._smooth.t = sprite._smooth.t + dt
			local t = sprite._smooth.t / sprite._smooth.time
			if t >= 1 then
				sprite.position = { sprite._smooth.target[1], sprite._smooth.target[2] }
				sprite._smooth = nil
			else
				local sx, sy = unpack(sprite._smooth.start)
				local tx, ty = unpack(sprite._smooth.target)
				local nx = q_round(sx + (tx - sx) * t)
				local ny = q_round(sy + (ty - sy) * t)
				sprite:SetPosition(q_round(nx), q_round(ny))
			end
		end

		local anim_data
		local frame_index
		local rotation = sprite.facing

		local x0, y0 = sprite.position[1], sprite.position[2]
		local old_w, old_h = sprite:GetSize()
		table.insert(dirtyRects, {
			x1 = math.max(0, x0),
			y1 = math.max(0, y0),
			x2 = math.min(px_w - 1, x0 + old_w - 1),
			y2 = math.min(px_h - 1, y0 + old_h - 1),
		})

		if sprite.activeAnimation then
			anim_data = sprite.data[sprite.activeAnimation]
			if anim_data then
				sprite.activeTimer = sprite.activeTimer + dt
				local frameCount = #anim_data.anims

				frame_index = math.floor(sprite.activeTimer / anim_data.duration) + 1
				if frame_index > frameCount then
					if not anim_data.loop then
						sprite.activeAnimation = nil
						sprite.activeTimer = 0
						frame_index = nil
					else
						frame_index = ((frame_index - 1) % frameCount) + 1
					end
				end
			else
				sprite.activeAnimation = nil
			end
		end

		if sprite.activeAnimation then
			anim_data = sprite.data[sprite.activeAnimation]
			if anim_data then
				sprite.activeTimer = sprite.activeTimer + dt
				local frameCount = #anim_data.anims
				local idx = math.floor(sprite.activeTimer / anim_data.duration) + 1

				if idx > frameCount then
					if not anim_data.loop then
						idx = frameCount
						sprite._endOfAnim = true
					else
						idx = ((idx - 1) % frameCount) + 1
					end
				end

				frame_index = idx
				sprite.activeFrame = idx
			else
				sprite.activeAnimation = nil
			end
		end

		if not sprite.activeAnimation and not sprite._endOfAnim then
			if sprite.idle then
				anim_data = sprite.data.allIdle
					or sprite.data["idle" .. sprite.facing:sub(1, 1):upper() .. sprite.facing:sub(2)]
			else
				anim_data = sprite.data.allAnim or sprite.data[sprite.facing]
			end

			if anim_data then
				frame_index = math.floor(t / anim_data.duration) % #anim_data.anims + 1
				sprite.activeFrame = frame_index
			end
		end
		if anim_data and frame_index then
			local frame_path = fs.combine(sprite.baseDir, anim_data.anims[frame_index])
			local lines = get_cached_frame(frame_path, rotation)

			if lines then
				local width = #lines[1]
				local height = #lines

				local x2_old, y2_old = x0 + old_w - 1, y0 + old_h - 1
				local x2_new, y2_new = x0 + width - 1, y0 + height - 1
				table.insert(dirtyRects, {
					x1 = math.max(0, math.min(x0, x0)),
					y1 = math.max(0, math.min(y0, y0)),
					x2 = math.min(px_w - 1, math.max(x2_old, x2_new)),
					y2 = math.min(px_h - 1, math.max(y2_old, y2_new)),
				})

				if x0 + width > 0 and x0 < px_w and y0 + height > 0 and y0 < px_h then
					for dy = 1, height do
						local py = y0 + dy - 1
						if py >= 0 and py < px_h then
							local row = lines[dy]
							local rowLen = #row
							for dx = 1, rowLen do
								local px = x0 + dx - 1
								local hex = row:sub(dx, dx)
								local color_value = colors.fromBlit(hex)
								if color_value and px >= 0 and px < px_w then
									box:set_pixel(px, py, color_value)
								end
							end
						end
					end
				end
			end

			if sprite._endOfAnim then
				sprite.activeAnimation = nil
				sprite.activeTimer = 0
				sprite._endOfAnim = nil
			end
		end
	end

	local collectedStillSprites = {}
	for _, sprite in pairs(xenon.still_sprites) do
		if sprite.scene == currentScene then
			table.insert(collectedStillSprites, sprite)
		end
	end
	table.sort(collectedStillSprites, function(a, b)
		return a.layer < b.layer
	end)

	for _, sprite in ipairs(collectedStillSprites) do
		if sprite._smooth then
			sprite._smooth.t = sprite._smooth.t + dt
			local t = sprite._smooth.t / sprite._smooth.time
			if t >= 1 then
				sprite.position = { sprite._smooth.target[1], sprite._smooth.target[2] }
				sprite._smooth = nil
			else
				local sx, sy = unpack(sprite._smooth.start)
				local tx, ty = unpack(sprite._smooth.target)
				local nx = q_round(sx + (tx - sx) * t)
				local ny = q_round(sy + (ty - sy) * t)
				sprite:SetPosition(q_round(nx), q_round(ny))
			end
		end

		local x0, y0 = sprite.position[1], sprite.position[2]
		local frame_path = fs.combine(sprite.baseDir, sprite.data.sprite)
		local lines = get_cached_frame(frame_path, sprite.facing)

		if lines then
			local width = #lines[1]
			local height = #lines

			table.insert(dirtyRects, {
				x1 = math.max(0, x0),
				y1 = math.max(0, y0),
				x2 = math.min(px_w - 1, x0 + width - 1),
				y2 = math.min(px_h - 1, y0 + height - 1),
			})

			if x0 + width > 0 and x0 < px_w and y0 + height > 0 and y0 < px_h then
				for dy = 1, height do
					local py = y0 + dy - 1
					if py >= 0 and py < px_h then
						local row = lines[dy]
						local rowLen = #row
						for dx = 1, rowLen do
							local px = x0 + dx - 1
							local hex = row:sub(dx, dx)
							local color_value = colors.fromBlit(hex)
							if color_value and px >= 0 and px < px_w then
								box:set_pixel(px, py, color_value)
							end
						end
					end
				end
			end
		end
	end

	box:render()
end

function xenon.runGame(updateFunc)
	parallel.waitForAny(function()
		while true do
			updateFunc()
			xenon.update(0.05)
			sleep(0.05)
		end
	end, xenon.inputLoop)
end

return xenon
