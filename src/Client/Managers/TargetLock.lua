-- 目标锁定系统
-- 按 Tab 键锁定视野内最近的敌人

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local PlayerManager = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("Managers"):WaitForChild("PlayerManager"))

-- 配置
local LOCK_KEY = Enum.KeyCode.Tab
local DETECTION_RADIUS = 30
local MAX_LOCK_DISTANCE = 50
local RAYCAST_PARAMS = RaycastParams.new()

-- 高亮配置（只显示边缘轮廓）
local HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 0, 0)
local HIGHLIGHT_OUTLINE_TRANSPARENCY = 0

-- 状态变量
local currentHighlight = nil
local lockUpdateConnection = nil

-- 初始化射线检测参数
local function initRaycastParams()
	RAYCAST_PARAMS.FilterType = Enum.RaycastFilterType.Blacklist
	RAYCAST_PARAMS.IgnoreWater = true
end

-- 检查两点之间是否有障碍物
local function hasLineOfSight(fromPos, toPos, ignoreList)
	local direction = (toPos - fromPos)
	local distance = direction.Magnitude

	RAYCAST_PARAMS.FilterDescendantsInstances = ignoreList

	local rayResult = workspace:Raycast(fromPos, direction, RAYCAST_PARAMS)

	if rayResult then
		-- 检查射线是否击中了目标角色的一部分
		local hitModel = rayResult.Instance:FindFirstAncestorOfClass("Model")
		if hitModel and hitModel:FindFirstChild("Humanoid") then
			-- 击中的是角色模型，视为有视线
			return true
		end
		-- 击中了其他障碍物
		return false
	end

	-- 没有击中任何东西，视线畅通
	return true
end

-- 获取所有潜在目标
local function getPotentialTargets(playerCharacter)
	local targets = {}
	local playerPos = playerCharacter.HumanoidRootPart.Position

	-- 遍历工作区中的所有模型
	for _, model in pairs(workspace:GetChildren()) do
		-- 检查是否是角色模型
		if model:IsA("Model") and model ~= playerCharacter then
			local humanoid = model:FindFirstChild("Humanoid")
			local rootPart = model:FindFirstChild("HumanoidRootPart")

			if humanoid and rootPart and humanoid.Health > 0 then
				local distance = (rootPart.Position - playerPos).Magnitude

				-- 在检测范围内
				if distance <= DETECTION_RADIUS then
					table.insert(targets, {
						Model = model,
						RootPart = rootPart,
						Humanoid = humanoid,
						Distance = distance
					})
				end
			end
		end
	end

	return targets
end

-- 找到最近的可见目标
local function findNearestVisibleTarget(playerCharacter)
	local targets = getPotentialTargets(playerCharacter)

	if #targets == 0 then
		return nil
	end

	-- 按距离排序
	table.sort(targets, function(a, b)
		return a.Distance < b.Distance
	end)

	local playerPos = playerCharacter.HumanoidRootPart.Position
	local ignoreList = {playerCharacter}

	-- 从最近的开始检查视线
	for _, target in ipairs(targets) do
		local targetPos = target.RootPart.Position

		-- 检查是否有视线
		if hasLineOfSight(playerPos, targetPos, ignoreList) then
			return target.Model
		end
	end

	return nil
end

-- 创建高亮效果（只显示边缘轮廓）
local function createHighlight(targetModel)
	-- 移除旧的高亮
	if currentHighlight then
		currentHighlight:Destroy()
		currentHighlight = nil
	end

	-- 创建新的高亮（只显示轮廓）
	local highlight = Instance.new("Highlight")
	highlight.Name = "TargetLockHighlight"
	highlight.Adornee = targetModel
	highlight.FillTransparency = 1  -- 完全透明填充（不显示）
	highlight.OutlineColor = HIGHLIGHT_OUTLINE_COLOR
	highlight.OutlineTransparency = HIGHLIGHT_OUTLINE_TRANSPARENCY
	highlight.Parent = targetModel

	currentHighlight = highlight

	return highlight
end

-- 移除高亮效果
local function removeHighlight()
	if currentHighlight then
		currentHighlight:Destroy()
		currentHighlight = nil
	end
end

-- 锁定目标
local function lockTarget(targetModel)
	PlayerManager.IsTargetLocked = true
	PlayerManager.LockedTarget = targetModel

	createHighlight(targetModel)

	-- 监听目标死亡或移除
	local humanoid = targetModel:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			unlockTarget()
		end)
	end

	targetModel.AncestryChanged:Connect(function(_, parent)
		if not parent then
			unlockTarget()
		end
	end)
end

-- 解锁目标
function unlockTarget()
	PlayerManager.IsTargetLocked = false
	PlayerManager.LockedTarget = nil
	removeHighlight()
end

-- 更新锁定状态（检查距离和视线）
local function updateLockStatus(playerCharacter)
	if not PlayerManager.IsTargetLocked or not PlayerManager.LockedTarget then
		return
	end

	local target = PlayerManager.LockedTarget
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	local targetHumanoid = target:FindFirstChild("Humanoid")

	-- 检查目标是否还存在且存活
	if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
		unlockTarget()
		return
	end

	local playerPos = playerCharacter.HumanoidRootPart.Position
	local targetPos = targetRoot.Position
	local distance = (targetPos - playerPos).Magnitude

	-- 检查距离是否超出范围
	if distance > MAX_LOCK_DISTANCE then
		unlockTarget()
		return
	end

	-- 检查是否还有视线
	local ignoreList = {playerCharacter}
	if not hasLineOfSight(playerPos, targetPos, ignoreList) then
		unlockTarget()
		return
	end
	
	--检查是否进入了瞄准状态
	if PlayerManager.IsAiming then
		unlockTarget()
		return
	end
end

-- Tab 键切换锁定
local function toggleTargetLock(actionName, inputState, inputObject)
	if inputState ~= Enum.UserInputState.Begin then return end

	local character = Player.Character
	if not character then return end

	-- 如果已经锁定，则解锁
	if PlayerManager.IsTargetLocked or PlayerManager.IsAiming then
		unlockTarget()
		return
	end

	-- 查找最近的可见目标
	local target = findNearestVisibleTarget(character)

	if target then
		lockTarget(target)
	end
end

-- 初始化
local function Init()
	local character = Player.Character or Player.CharacterAdded:Wait()

	initRaycastParams()

	-- 绑定 Tab 键
	ContextActionService:BindAction("TargetLock", toggleTargetLock, false, LOCK_KEY)

	-- 启动锁定状态更新循环
	if lockUpdateConnection then
		lockUpdateConnection:Disconnect()
	end

	lockUpdateConnection = RunService.Heartbeat:Connect(function()
		if character and character.Parent then
			updateLockStatus(character)
		end
	end)
end

-- 清理
local function Cleanup()
	ContextActionService:UnbindAction("TargetLock")

	if lockUpdateConnection then
		lockUpdateConnection:Disconnect()
		lockUpdateConnection = nil
	end

	unlockTarget()
end

-- 事件监听
Player.CharacterAdded:Connect(Init)
Player.CharacterRemoving:Connect(Cleanup)

if Player.Character then
	Init()
end

