local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local function safeService(name)
	local ok, svc = pcall(function()
		return game:GetService(name)
	end)
	return ok and svc or nil
end

local Lighting = safeService("Lighting")
local Workspace = safeService("Workspace")
local VirtualInputManager = safeService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	warn("[Bao123] LocalPlayer is nil")
	return
end

local parentGui = nil
pcall(function()
	parentGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
end)
if not parentGui then
	warn("[Bao123] PlayerGui unavailable")
	return
end

pcall(function()
	local oldGui = parentGui:FindFirstChild("Bao123Menu")
	if oldGui then oldGui:Destroy() end
end)

local Config = {
	Title = "b\224\186\163o123",
	MenuKey = Enum.KeyCode.V,
	SupaKey = Enum.KeyCode.G,
	FovPx = 150,
	SpeedEnabled = false,
	WalkSpeed = 32,
	JumpEnabled = false,
	JumpPower = 85,
	EspMobEnabled = false,
	NoClipEnabled = false,
	AutoCamAuraEnabled = false,
	AuraRange = 18,
	CamLerpAlpha = 0.35,
	AttackCooldownSec = 0.16,
	SupaMaxRange = 164,
	SupaMinDashVel = 35,
	SupaLockDuration = 1.2,
	SupaBackOffset = 3.2,
	SupaFloatY = 2.5,
}

local isDestroyed = false
local lagDone = false
local waitingRebind = false
local lastAttackClock = 0
local lastEspClock = 0
local lastMoveClock = 0
local statusLbl = nil

-- Supa Tech & Target variables
local SupaActive = false
local UppercutDetected = false
local Triggered = false
local TargetNameFilter = ""

-- Connections de ngat sach khi xoa menu
local connections = {}
local animConn = nil

local savedWalkSpeed, savedJumpPower, savedJumpHeight, savedUseJumpPower = nil, nil, nil, nil
local espMobEntries = {}
local savedPartCollide = {}

local function trackConn(conn)
	if conn then
		table.insert(connections, conn)
	end
	return conn
end

local function setStatus(msg)
	if isDestroyed then return end
	if statusLbl then
		pcall(function() statusLbl.Text = tostring(msg) end)
	end
end

local function isPlayerCharacterModel(model)
	if not model or not model:IsA("Model") then return false end
	if model == LocalPlayer.Character then return true end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character == model then
			return true
		end
	end
	return false
end

local function getClosestEnemyForSupa()
	local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not myRoot then return nil end

	local filter = string.lower((TargetNameFilter or ""):gsub("%s+", ""))
	local closestPlayer = nil
	local shortestDistance = Config.SupaMaxRange

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then
			local nameMatch = true
			if filter ~= "" then
				local pName = string.lower(player.Name)
				local dName = string.lower(player.DisplayName)
				if not string.find(pName, filter, 1, true) and not string.find(dName, filter, 1, true) then
					nameMatch = false
				end
			end

			if nameMatch then
				local enemyRoot = player.Character:FindFirstChild("HumanoidRootPart")
				local enemyHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
				if enemyRoot and enemyHumanoid and enemyHumanoid.Health > 0 then
					local distance = (myRoot.Position - enemyRoot.Position).Magnitude
					if distance < shortestDistance then
						shortestDistance = distance
						closestPlayer = player
					end
				end
			end
		end
	end
	return closestPlayer
end

local function bindUppercutDetector(char)
	if animConn then
		pcall(function() animConn:Disconnect() end)
		animConn = nil
	end
	if isDestroyed or not char then return end

	task.spawn(function()
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 6)
		if not hum or isDestroyed or LocalPlayer.Character ~= char then return end
		local animator = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 6)
		if not animator or isDestroyed or LocalPlayer.Character ~= char then return end

		animConn = animator.AnimationPlayed:Connect(function(track)
			if isDestroyed or not SupaActive then return end
			local id = ""
			pcall(function()
				id = string.lower(tostring(track.Animation.AnimationId))
			end)
			if string.find(id, "1047", 1, true) or string.find(id, "125", 1, true) or string.find(id, "uppercut", 1, true) then
				UppercutDetected = true
				Triggered = false
				setStatus("UPPERCUT! Bam Dash ngay")

				task.delay(1.5, function()
					if not isDestroyed and not Triggered and UppercutDetected then
						UppercutDetected = false
						if SupaActive then
							setStatus("Supa Tech: ON (cho uppercut)")
						end
					end
				end)
			end
		end)
	end)
end

local function runSupaHeadLoop()
	task.spawn(function()
		while SupaActive and not isDestroyed do
			local myChar = LocalPlayer.Character
			local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

			if UppercutDetected and myRoot and not Triggered then
				local vel = myRoot.AssemblyLinearVelocity
				local horizontalVelocity = Vector3.new(vel.X, 0, vel.Z).Magnitude

				if horizontalVelocity > Config.SupaMinDashVel then
					Triggered = true
					UppercutDetected = false
					setStatus("SUPA LOCK ACTIVE!")

					local startTime = tick()
					while (tick() - startTime < Config.SupaLockDuration) and SupaActive and not isDestroyed do
						local target = getClosestEnemyForSupa()
						if target and target.Character and myRoot then
							local enemyHead = target.Character:FindFirstChild("Head")
							local enemyTorso = target.Character:FindFirstChild("Torso") or target.Character:FindFirstChild("UpperTorso")
							if enemyHead and enemyTorso then
								pcall(function()
									local targetPosition = enemyTorso.Position:Lerp(enemyHead.Position, 0.5)
									local targetLook = CFrame.lookAt(myRoot.Position, targetPosition)
									local desiredPosition = targetPosition - (targetLook.LookVector * Config.SupaBackOffset)
									myRoot.CFrame = CFrame.lookAt(desiredPosition, targetPosition)
									enemyTorso.AssemblyLinearVelocity = Vector3.new(0, Config.SupaFloatY, 0)
									myRoot.AssemblyLinearVelocity = Vector3.new(0, Config.SupaFloatY, 0)
								end)
							end
						end
						RunService.PostSimulation:Wait()
					end

					Triggered = false
					if SupaActive and not isDestroyed then
						setStatus("Supa Tech: ON (cho uppercut)")
					end
				end
			end
			RunService.PostSimulation:Wait()
		end
	end)
end

local function findNearestCombatTarget(myRoot)
	if not Workspace or not myRoot then return nil, nil end
	local bestPart, bestHum, bestDist = nil, nil, Config.AuraRange
	local okDesc, desc = pcall(function() return Workspace:GetDescendants() end)
	if not okDesc or type(desc) ~= "table" then return nil, nil end

	for _, inst in ipairs(desc) do
		if inst:IsA("Humanoid") and inst.Health > 0 then
			local model = inst.Parent
			if model and model:IsA("Model") and not isPlayerCharacterModel(model) then
				local tp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso") or model:FindFirstChild("Head")
				if tp and tp:IsA("BasePart") then
					local d = (tp.Position - myRoot.Position).Magnitude
					if d > 0 and d <= bestDist then
						bestDist, bestPart, bestHum = d, tp, inst
					end
				end
			end
		end
	end
	return bestPart, bestHum
end

local function triggerAuraAttack()
	local now = os.clock()
	if now - lastAttackClock < Config.AttackCooldownSec then return end
	lastAttackClock = now

	local char = LocalPlayer.Character
	if char then
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") then
				pcall(function() child:Activate() end)
			end
		end
	end

	if VirtualInputManager then
		local cam = Workspace and Workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
		local cx, cy = math.floor(vp.X * 0.5), math.floor(vp.Y * 0.5)
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
			task.delay(0.02, function()
				if not isDestroyed then
					pcall(function()
						VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
					end)
				end
			end)
		end)
	end
end

local function updateAutoCamAndKillAura()
	if isDestroyed or not Config.AutoCamAuraEnabled then return end
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end

	local targetPart, targetHum = findNearestCombatTarget(root)
	if not targetPart or not targetHum then return end

	local cam = Workspace and Workspace.CurrentCamera
	if cam then
		pcall(function()
			local lookGoal = CFrame.lookAt(cam.CFrame.Position, targetPart.Position)
			cam.CFrame = cam.CFrame:Lerp(lookGoal, math.clamp(Config.CamLerpAlpha, 0.05, 1))
		end)
	end
	triggerAuraAttack()
end

local function restoreNoClipParts()
	for part, prevCollide in pairs(savedPartCollide) do
		pcall(function()
			if part and part.Parent then part.CanCollide = prevCollide end
		end)
		savedPartCollide[part] = nil
	end
end

local function updateNoClip()
	local char = LocalPlayer.Character
	if isDestroyed or not Config.NoClipEnabled or not char then
		if next(savedPartCollide) ~= nil then restoreNoClipParts() end
		return
	end
	for _, inst in ipairs(char:GetDescendants()) do
		if inst:IsA("BasePart") then
			if savedPartCollide[inst] == nil then
				savedPartCollide[inst] = inst.CanCollide
			end
			if inst.CanCollide then
				pcall(function() inst.CanCollide = false end)
			end
		end
	end
end

local function clearEspEntry(model)
	local entry = espMobEntries[model]
	if not entry then return end
	pcall(function() if entry.highlight then entry.highlight:Destroy() end end)
	pcall(function() if entry.billboard then entry.billboard:Destroy() end end)
	espMobEntries[model] = nil
end

local function clearAllEspMob()
	for model in pairs(espMobEntries) do
		clearEspEntry(model)
	end
end

local function ensureEspMob(model, anchorPart)
	local entry = espMobEntries[model]
	if entry and entry.anchor ~= anchorPart then
		clearEspEntry(model)
		entry = nil
	end
	if not entry then
		local hl = Instance.new("Highlight")
		hl.Name = "Bao123_MobESP"
		hl.FillColor = Color3.fromRGB(255, 115, 182)
		hl.OutlineColor = Color3.fromRGB(255, 255, 255)
		hl.FillTransparency = 0.65
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = model
		pcall(function() hl.Parent = parentGui end)

		local bb = Instance.new("BillboardGui")
		bb.Name = "Bao123_MobTag"
		bb.Size = UDim2.new(0, 145, 0, 30)
		bb.StudsOffset = Vector3.new(0, 2.5, 0)
		bb.AlwaysOnTop = true
		bb.Adornee = anchorPart

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 0.35
		lbl.BackgroundColor3 = Color3.fromRGB(27, 22, 39)
		lbl.TextColor3 = Color3.fromRGB(255, 195, 225)
		lbl.TextStrokeTransparency = 0.2
		lbl.TextSize = 11
		lbl.Font = Enum.Font.GothamBold
		lbl.Parent = bb
		pcall(function() bb.Parent = parentGui end)

		entry = { anchor = anchorPart, highlight = hl, billboard = bb, label = lbl }
		espMobEntries[model] = entry
	end
	return entry
end

local function updateEspMob()
	if isDestroyed or not Config.EspMobEnabled then
		if next(espMobEntries) ~= nil then clearAllEspMob() end
		return
	end
	if not Workspace then return end

	local okDesc, desc = pcall(function() return Workspace:GetDescendants() end)
	if not okDesc or type(desc) ~= "table" then return end

	local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local activeModels = {}

	for _, inst in ipairs(desc) do
		if inst:IsA("Humanoid") and inst.Health > 0 then
			local model = inst.Parent
			if model and model:IsA("Model") and not isPlayerCharacterModel(model) then
				local anchor = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
				if anchor and anchor:IsA("BasePart") then
					activeModels[model] = true
					local entry = ensureEspMob(model, anchor)
					if entry and entry.label then
						local distText = myRoot and (" | " .. tostring(math.floor((myRoot.Position - anchor.Position).Magnitude)) .. "m") or ""
						entry.label.Text = model.Name .. " [" .. math.floor(inst.Health) .. "HP]" .. distText
					end
				end
			end
		end
	end

	for model in pairs(espMobEntries) do
		if not activeModels[model] or not model.Parent then
			clearEspEntry(model)
		end
	end
end

local function getHumanoid()
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return (hum and hum.Health > 0) and hum or nil
end

local function captureBaseMovement(hum)
	if not hum then return end
	if savedWalkSpeed == nil then pcall(function() savedWalkSpeed = hum.WalkSpeed end) end
	if savedUseJumpPower == nil then pcall(function() savedUseJumpPower = hum.UseJumpPower end) end
	if savedJumpPower == nil then pcall(function() savedJumpPower = hum.JumpPower end) end
	if savedJumpHeight == nil then pcall(function() savedJumpHeight = hum.JumpHeight end) end
end

local function applyMovementStats()
	local hum = getHumanoid()
	if not hum then return end
	captureBaseMovement(hum)
	pcall(function()
		hum.WalkSpeed = (not isDestroyed and Config.SpeedEnabled) and Config.WalkSpeed or (savedWalkSpeed or hum.WalkSpeed)
	end)
	pcall(function()
		if not isDestroyed and Config.JumpEnabled then
			if hum.UseJumpPower == false then
				hum.JumpHeight = math.max(7.2, (savedJumpHeight or 7.2) * (Config.JumpPower / 50))
			else
				hum.JumpPower = Config.JumpPower
			end
		else
			if savedUseJumpPower ~= nil then hum.UseJumpPower = savedUseJumpPower end
			if savedJumpHeight ~= nil then hum.JumpHeight = savedJumpHeight end
			if savedJumpPower ~= nil then hum.JumpPower = savedJumpPower end
		end
	end)
end

local function applyLightFixLag()
	if Lighting then
		pcall(function()
			Lighting.GlobalShadows = false
			Lighting.FogEnd = 9e9
		end)
	end
	if Workspace then
		local okDesc, desc = pcall(function() return Workspace:GetDescendants() end)
		if okDesc and type(desc) == "table" then
			for _, inst
