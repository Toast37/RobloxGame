--[[
	============================================================================
	CameraEffectManager.lua - 摄像机效果管理器
	============================================================================

	功能：
	- FOV视野管理
	- 摄像机抖动系统（一次性抖动）
	- 持续性摇晃系统（状态驱动）
	- 头部晃动系统（Head Bob）

	使用方式：
	local CameraEffectManager = require(script.CameraEffectManager)
	CameraEffectManager:AddCameraShake(1.0, 0.5)  -- 添加抖动
	CameraEffectManager:SetFOVModifier("Aiming", -20)  -- 设置FOV

	============================================================================
]]

local RunService = game:GetService("RunService")

-- ============================================================================
-- 公开变量
-- ============================================================================

local CameraEffectManager = {
	-- === FOV管理 ===
	DefaultFOV = 70,                  -- 默认视野
	FOVModifiers = {},                -- FOV修改器集合 { name = offset }
	
	-- === 视觉效果输出 ===
	CameraShakeOffset = CFrame.new(), -- 摄像机抖动偏移
	HeadBobOffset = Vector3.new(),    -- 头部晃动偏移
	HeadBobEnabled = true,            -- 是否启用头部晃动
}

-- ============================================================================
-- 私有变量
-- ============================================================================

local camera = workspace.CurrentCamera

-- === 更新循环连接 ===
local updateConnection = nil  -- 统一的更新循环

-- === 摄像机抖动系统私有变量 ===
local activeShakes = {}              -- 活动的一次性抖动 { id = shake }
local shakeIdCounter = 0             -- 抖动ID计数器
local continuousShakes = {}          -- 持续性摇晃配置
local currentActiveShake = nil       -- 当前激活的持续性摇晃名称
local shakeTransitionProgress = 0    -- 摇晃过渡进度（0-1）
local shakeTransitionSpeed = 3       -- 摇晃过渡速度（每秒）
local lastCameraShakeOffset = CFrame.new()  -- 上一帧的抖动偏移（用于平滑归零）
local shakeDecaySpeed = 10           -- 摄像机归零速度（每秒）

-- === 头部晃动系统私有变量 ===
local headBobTime = 0                -- 头部晃动时间累积
local currentBobAmplitude = 0        -- 当前晃动幅度（平滑过渡）
local currentBobFrequency = 2.5      -- 当前晃动频率（平滑过渡）
local currentBobVerticalOffset = 0   -- 当前垂直偏移（平滑过渡）

-- === 外部状态引用（需要从PlayerManager获取） ===
local PlayerStateProvider = nil      -- 玩家状态提供者

-- ============================================================================
-- FOV管理系统
-- ============================================================================

-- 计算当前应该的FOV
local function calculateFOV()
	local baseFOV = CameraEffectManager.DefaultFOV
	local totalOffset = 0

	-- 累加所有FOV修改器
	for name, offset in pairs(CameraEffectManager.FOVModifiers) do
		totalOffset = totalOffset + offset
	end

	return baseFOV + totalOffset
end

-- 更新摄像机FOV
local function updateFOV()
	if not camera then return end

	local targetFOV = calculateFOV()
	camera.FieldOfView = targetFOV
end

-- 设置FOV修改器（offset为nil或0时移除）
function CameraEffectManager:SetFOVModifier(name, offset)
	self.FOVModifiers[name] = (offset == 0 or offset == nil) and nil or offset
end

-- 获取FOV修改器
function CameraEffectManager:GetFOVModifier(name)
	return self.FOVModifiers[name] or 0
end

-- 清除所有FOV修改器
function CameraEffectManager:ClearAllFOVModifiers()
	self.FOVModifiers = {}
end

-- 获取当前总FOV
function CameraEffectManager:GetCurrentFOV()
	return calculateFOV()
end

-- ============================================================================
-- Perlin噪声函数（用于生成平滑的随机值）
-- ============================================================================

local function perlinNoise(x, seed)
	local x0 = math.floor(x)
	local x1 = x0 + 1
	local sx = x - x0

	-- 使用seed生成伪随机值
	local function hash(n)
		n = (n + seed) * 15731
		n = bit32.bxor(n, bit32.rshift(n, 13))
		n = n * 1376312589
		return (n % 10000) / 10000 - 0.5
	end

	-- 平滑插值
	local function smoothstep(t)
		return t * t * (3 - 2 * t)
	end

	local v0 = hash(x0)
	local v1 = hash(x1)

	return v0 + smoothstep(sx) * (v1 - v0)
end

-- 生成平滑的抖动偏移（使用旋转而不是位置）
local function generateShakeOffset(intensity, time, seed)
	-- 使用Perlin噪声生成平滑的旋转角度
	local angleX = perlinNoise(time * 10, seed) * intensity * 2
	local angleY = perlinNoise(time * 10, seed + 100) * intensity * 2
	local angleZ = perlinNoise(time * 10, seed + 200) * intensity * 0.5  -- Z轴旋转较小

	-- 返回旋转CFrame
	return CFrame.Angles(math.rad(angleX), math.rad(angleY), math.rad(angleZ))
end

-- 计算抖动强度（考虑淡入淡出）
local function calculateShakeIntensity(shake, currentTime)
	local elapsed = currentTime - shake.startTime
	local progress = elapsed / shake.duration

	if progress >= 1 then
		return 0  -- 抖动已结束
	end

	local intensity = shake.intensity

	-- 淡入
	if elapsed < shake.fadeIn then
		intensity = intensity * (elapsed / shake.fadeIn)
	end

	-- 淡出
	local timeLeft = shake.duration - elapsed
	if timeLeft < shake.fadeOut then
		intensity = intensity * (timeLeft / shake.fadeOut)
	end

	return intensity
end

-- CFrame平滑插值函数（用于平滑归零）
local function lerpCFrame(current, target, alpha)
	-- 如果当前CFrame接近目标，直接返回目标
	local currentPos = current.Position
	local targetPos = target.Position
	local distance = (currentPos - targetPos).Magnitude

	if distance < 0.001 then
		return target
	end

	-- 使用Lerp进行平滑插值
	return current:Lerp(target, alpha)
end

-- ============================================================================
-- 摄像机抖动系统（一次性抖动 + 持续性摇晃）
-- ============================================================================

-- 更新所有抖动效果（一次性抖动 + 持续性摇晃）
local function updateCameraShake(deltaTime)
	local currentTime = tick()
	local combinedShake = CFrame.new()
	local shakesToRemove = {}

	-- ========================================
	-- 第一部分：处理一次性抖动
	-- ========================================
	for id, shake in pairs(activeShakes) do
		local intensity = calculateShakeIntensity(shake, currentTime)

		if intensity <= 0 then
			-- 标记为移除
			table.insert(shakesToRemove, id)
		else
			-- 每帧都生成新的抖动偏移（使用时间和频率）
			local elapsed = currentTime - shake.startTime
			local timeScale = elapsed * shake.frequency / 10  -- 频率影响抖动速度

			-- 使用shake.id作为seed，确保每个抖动有不同的模式
			shake.currentOffset = generateShakeOffset(intensity, timeScale, shake.id * 1000)

			-- 叠加抖动效果（考虑优先级）
			combinedShake = combinedShake * shake.currentOffset
		end
	end

	-- 移除已结束的抖动
	for _, id in ipairs(shakesToRemove) do
		activeShakes[id] = nil
	end

	-- ========================================
	-- 第二部分：处理持续性摇晃（带优先级和平滑过渡）
	-- ========================================

	-- 找出当前应该激活的最高优先级摇晃
	local targetShake = nil
	local highestPriority = -1

	for name, shake in pairs(continuousShakes) do
		if shake.enabled and shake.priority > highestPriority then
			highestPriority = shake.priority
			targetShake = shake
		end
	end

	-- 检测摇晃切换
	local targetShakeName = targetShake and targetShake.name or nil
	if targetShakeName ~= currentActiveShake then
		-- 摇晃发生切换，重置过渡进度
		currentActiveShake = targetShakeName
		shakeTransitionProgress = 0
		print("[CameraEffectManager] 摇晃切换到:", currentActiveShake or "无")
	end

	-- 更新过渡进度（平滑过渡）
	if shakeTransitionProgress < 1 then
		shakeTransitionProgress = math.min(1, shakeTransitionProgress + deltaTime * shakeTransitionSpeed)
	end

	-- 应用持续性摇晃（带过渡效果）
	if targetShake then
		local elapsed = currentTime - targetShake.startTime
		local timeScale = elapsed * targetShake.frequency / 10

		-- 生成持续性摇晃偏移
		local continuousOffset = generateShakeOffset(
			targetShake.intensity * shakeTransitionProgress,  -- 应用过渡进度
			timeScale,
			targetShake.seed
		)

		-- 叠加持续性摇晃（持续性摇晃优先级低于一次性抖动）
		combinedShake = continuousOffset * combinedShake
	end

	-- ========================================
	-- 第三部分：平滑归零系统（避免摄像机突然跳动）
	-- ========================================

	-- 检查是否有任何活动的抖动或摇晃
	local hasActiveShake = false

	-- 检查一次性抖动
	for _, _ in pairs(activeShakes) do
		hasActiveShake = true
		break
	end

	-- 检查持续性摇晃
	if not hasActiveShake and targetShake then
		hasActiveShake = true
	end

	-- 如果没有活动的抖动，平滑归零
	if not hasActiveShake then
		-- 计算平滑系数（基于归零速度和deltaTime）
		local decayAlpha = math.min(1, deltaTime * shakeDecaySpeed)

		-- 从上一帧的偏移平滑过渡到零偏移
		combinedShake = lerpCFrame(lastCameraShakeOffset, CFrame.new(), decayAlpha)
	end

	-- 保存当前偏移，供下一帧使用
	lastCameraShakeOffset = combinedShake

	-- 更新摄像机抖动偏移
	CameraEffectManager.CameraShakeOffset = combinedShake
end

-- 添加摄像机抖动（一次性抖动）
function CameraEffectManager:AddCameraShake(intensity, duration, options)
	options = options or {}

	shakeIdCounter = shakeIdCounter + 1
	local shakeId = shakeIdCounter

	local shake = {
		id = shakeId,
		intensity = intensity or 0.5,
		duration = duration or 0.5,
		fadeIn = options.fadeIn or 0,
		fadeOut = options.fadeOut or (duration or 0.5) * 0.3,  -- 默认淡出时间为持续时间的30%
		startTime = tick(),
		frequency = options.frequency or 30,  -- 默认30Hz
		priority = options.priority or 0,  -- 优先级（数字越大优先级越高）
		currentOffset = CFrame.new(),
	}

	activeShakes[shakeId] = shake
	return shakeId
end

-- 停止指定的抖动
function CameraEffectManager:StopCameraShake(shakeId)
	if shakeId then
		activeShakes[shakeId] = nil
	end
end

-- 停止所有抖动
function CameraEffectManager:StopAllCameraShakes()
	activeShakes = {}
	CameraEffectManager.CameraShakeOffset = CFrame.new()
end

-- 预设抖动效果
function CameraEffectManager:ShakePreset(presetName)

	if presetName == "Light" then
		-- 轻微抖动 - 适用于轻微碰撞、拾取物品
		return self:AddCameraShake(0.3, 0.3, { fadeOut = 0.15, frequency = 25, priority = 1 })

	elseif presetName == "Medium" then
		-- 中等抖动 - 适用于普通攻击、跳跃落地
		return self:AddCameraShake(0.8, 0.5, { fadeOut = 0.2, frequency = 30, priority = 2 })

	elseif presetName == "Heavy" then
		-- 重度抖动 - 适用于重击、被击飞
		return self:AddCameraShake(1.5, 0.8, { fadeOut = 0.4, frequency = 35, priority = 3 })

	elseif presetName == "Explosion" then
		-- 爆炸抖动 - 快速强烈的冲击
		return self:AddCameraShake(2.5, 0.8, { fadeIn = 0.02, fadeOut = 0.5, frequency = 45, priority = 5 })

	elseif presetName == "Damage" then
		-- 受伤抖动 - 短促高频
		return self:AddCameraShake(1.2, 0.25, { fadeOut = 0.15, frequency = 50, priority = 4 })

	elseif presetName == "Landing" then
		-- 落地抖动 - 瞬间冲击后逐渐减弱
		return self:AddCameraShake(1.8, 0.4, { fadeIn = 0, fadeOut = 0.3, frequency = 40, priority = 3 })

	elseif presetName == "Rumble" then
		-- 持续震动 - 低频持续效果
		return self:AddCameraShake(0.6, 2.0, { fadeIn = 0.3, fadeOut = 0.5, frequency = 15, priority = 2 })
	else
		warn("[CameraEffectManager] 未知的预设名称:", presetName)
	end
end

-- ============================================================================
-- 持续性摇晃系统（用于瞄准、蹲下等状态的轻微晃动）
-- ============================================================================

-- 初始化持续性摇晃配置
local function initializeContinuousShakes()
	-- 瞄准时的轻微晃动（模拟呼吸和肌肉紧张）
	continuousShakes["Aiming"] = {
		name = "Aiming",
		enabled = false,
		intensity = 0.06,  -- 轻微晃动，模拟瞄准时的呼吸
		frequency = 4,     -- 低频率，模拟呼吸节奏（约4次/秒）
		priority = 10,     -- 高优先级
		seed = 1000,
		startTime = tick(),
	}

	-- 蹲下时的轻微晃动（更稳定的姿势）
	continuousShakes["Crouching"] = {
		name = "Crouching",
		enabled = false,
		intensity = 0.04,  -- 更轻微的晃动，蹲下更稳定
		frequency = 3,     -- 更低频率，模拟稳定的蹲姿
		priority = 8,      -- 中等优先级
		seed = 2000,
		startTime = tick(),
	}

	-- 蹲下瞄准时的极轻微晃动（最稳定的组合状态）
	continuousShakes["CrouchAiming"] = {
		name = "CrouchAiming",
		enabled = false,
		intensity = 0.025, -- 极轻微晃动，蹲下瞄准最稳定
		frequency = 2.5,   -- 极低频率，模拟缓慢的呼吸
		priority = 15,     -- 高优先级
		seed = 3000,
		startTime = tick(),
	}

	-- 奔跑时的晃动（剧烈运动）
	continuousShakes["Running"] = {
		name = "Running",
		enabled = false,
		intensity = 0.1,  -- 较明显的晃动，模拟奔跑时的颠簸
		frequency = 8,    -- 较高频率，模拟脚步节奏
		priority = 5,      -- 较低优先级
		seed = 4000,
		startTime = tick(),
	}

	-- 受伤时的持续晃动（身体不稳）
	continuousShakes["Injured"] = {
		name = "Injured",
		enabled = false,
		intensity = 0.18,  -- 明显晃动，模拟受伤后的不稳定
		frequency = 8,     -- 中等频率，不规则的晃动
		priority = 12,     -- 高优先级
		seed = 5000,
		startTime = tick(),
	}

	-- 筋疲力尽时的缓慢晃动
	continuousShakes["Exhausted"] = {
		name = "Exhausted",
		enabled = false,
		intensity = 0.06,  -- 轻微晃动，模拟瞄准时的呼吸
		frequency = 4,     -- 低频率，模拟呼吸节奏（约4次/秒）
		priority = 18,     -- 最高优先级
		seed = 6000,
		startTime = tick(),
	}
end

-- 启用持续性摇晃
function CameraEffectManager:EnableContinuousShake(shakeName)
	local shake = continuousShakes[shakeName]
	if not shake then
		warn("[CameraEffectManager] 未知的持续性摇晃:", shakeName)
		return
	end

	if not shake.enabled then
		shake.enabled = true
		shake.startTime = tick()
	end
end

-- 禁用持续性摇晃
function CameraEffectManager:DisableContinuousShake(shakeName)
	local shake = continuousShakes[shakeName]
	if not shake then
		warn("[CameraEffectManager] 未知的持续性摇晃:", shakeName)
		return
	end

	shake.enabled = false
end

-- 禁用所有持续性摇晃
function CameraEffectManager:DisableAllContinuousShakes()
	for name, shake in pairs(continuousShakes) do
		shake.enabled = false
	end
	print("[CameraEffectManager] 禁用所有持续性摇晃")
end

-- 设置持续性摇晃参数
function CameraEffectManager:SetContinuousShakeConfig(shakeName, config)
	if not continuousShakes[shakeName] then
		warn("[CameraEffectManager] 未知的持续性摇晃名称:", shakeName)
		return
	end

	for key, value in pairs(config) do
		if continuousShakes[shakeName][key] ~= nil and key ~= "name" and key ~= "enabled" then
			continuousShakes[shakeName][key] = value
		end
	end

	print("[CameraEffectManager] 更新持续性摇晃配置:", shakeName)
end

-- 获取持续性摇晃配置
function CameraEffectManager:GetContinuousShakeConfig(shakeName)
	if shakeName then
		return continuousShakes[shakeName]
	else
		return continuousShakes
	end
end

-- 获取当前激活的持续性摇晃信息（调试用）
function CameraEffectManager:GetActiveShakeInfo()
	return {
		currentShake = currentActiveShake,
		transitionProgress = shakeTransitionProgress,
		allShakes = continuousShakes,
	}
end

-- 设置晃动过渡速度
function CameraEffectManager:SetShakeTransitionSpeed(speed)
	shakeTransitionSpeed = math.max(0.1, speed)
end

-- 获取晃动过渡速度
function CameraEffectManager:GetShakeTransitionSpeed()
	return shakeTransitionSpeed
end

-- 设置摄像机归零速度
function CameraEffectManager:SetShakeDecaySpeed(speed)
	shakeDecaySpeed = math.max(0.1, speed)
end

-- 获取摄像机归零速度
function CameraEffectManager:GetShakeDecaySpeed()
	return shakeDecaySpeed
end

-- 自动管理持续性摇晃（根据玩家状态）
local function updateContinuousShakesBasedOnState()
	if not PlayerStateProvider then return end

	-- 精疲力竭状态（最高优先级）
	if PlayerStateProvider.IsExhausted then
		CameraEffectManager:EnableContinuousShake("Exhausted")
		CameraEffectManager:DisableContinuousShake("CrouchAiming")
		CameraEffectManager:DisableContinuousShake("Aiming")
		CameraEffectManager:DisableContinuousShake("Crouching")
		CameraEffectManager:DisableContinuousShake("Running")
		return
	end

	-- 蹲下瞄准组合状态
	if PlayerStateProvider.IsCrouching and PlayerStateProvider.IsAiming then
		CameraEffectManager:EnableContinuousShake("CrouchAiming")
		CameraEffectManager:DisableContinuousShake("Aiming")
		CameraEffectManager:DisableContinuousShake("Crouching")
		CameraEffectManager:DisableContinuousShake("Running")
		return
	end

	-- 瞄准状态
	if PlayerStateProvider.IsAiming then
		CameraEffectManager:EnableContinuousShake("Aiming")
		CameraEffectManager:DisableContinuousShake("CrouchAiming")
		CameraEffectManager:DisableContinuousShake("Crouching")
		CameraEffectManager:DisableContinuousShake("Running")
		return
	end

	-- 蹲下状态
	if PlayerStateProvider.IsCrouching then
		CameraEffectManager:EnableContinuousShake("Crouching")
		CameraEffectManager:DisableContinuousShake("CrouchAiming")
		CameraEffectManager:DisableContinuousShake("Aiming")
		CameraEffectManager:DisableContinuousShake("Running")
		return
	end

	-- 奔跑状态
	if PlayerStateProvider.IsRunning then
		CameraEffectManager:EnableContinuousShake("Running")
		CameraEffectManager:DisableContinuousShake("CrouchAiming")
		CameraEffectManager:DisableContinuousShake("Aiming")
		CameraEffectManager:DisableContinuousShake("Crouching")
		return
	end

	-- 默认状态：禁用所有
	CameraEffectManager:DisableContinuousShake("CrouchAiming")
	CameraEffectManager:DisableContinuousShake("Aiming")
	CameraEffectManager:DisableContinuousShake("Crouching")
	CameraEffectManager:DisableContinuousShake("Running")
end

-- ============================================================================
-- 头部晃动系统（Head Bob）
-- ============================================================================

-- 头部晃动配置（可调节参数）
local HeadBobConfig = {
	-- 走路晃动
	Walk = {
		Enabled = true,
		VerticalAmplitude = 0.15,      -- 垂直晃动幅度
		HorizontalAmplitude = 0.08,    -- 水平晃动幅度
		Frequency = 2.5,               -- 晃动频率（Hz）
		VerticalOffset = 0,            -- 垂直偏移（用于调整中心点）
	},

	-- 奔跑晃动
	Run = {
		Enabled = true,
		VerticalAmplitude = 0.25,      -- 垂直晃动幅度（更大）
		HorizontalAmplitude = 0.12,    -- 水平晃动幅度（更大）
		Frequency = 3.5,               -- 晃动频率（更快）
		VerticalOffset = 0,            -- 垂直偏移
	},

	-- 蹲下移动晃动
	Crouch = {
		Enabled = true,
		VerticalAmplitude = 0.08,      -- 垂直晃动幅度（更小，更稳定）
		HorizontalAmplitude = 0.04,    -- 水平晃动幅度（更小）
		Frequency = 2.0,               -- 晃动频率（更慢）
		VerticalOffset = -0.05,        -- 垂直偏移（视角稍微降低）
	},

	-- 瞄准移动晃动
	Aiming = {
		Enabled = true,
		VerticalAmplitude = 0.05,      -- 垂直晃动幅度（最小，精准瞄准）
		HorizontalAmplitude = 0.02,    -- 水平晃动幅度（最小）
		Frequency = 1.8,               -- 晃动频率（最慢，稳定）
		VerticalOffset = 0,            -- 垂直偏移
	},

	-- 蹲下瞄准移动晃动（组合状态）
	CrouchAiming = {
		Enabled = true,
		VerticalAmplitude = 0.03,      -- 垂直晃动幅度（极小，最稳定）
		HorizontalAmplitude = 0.015,   -- 水平晃动幅度（极小）
		Frequency = 1.5,               -- 晃动频率（极慢）
		VerticalOffset = -0.03,        -- 垂直偏移（稍微降低）
	},

	-- 精疲力竭移动晃动
	Exhausted = {
		Enabled = true,
		VerticalAmplitude = 0.35,      -- 垂直晃动幅度（很大，模拟疲惫）
		HorizontalAmplitude = 0.18,    -- 水平晃动幅度（很大，摇摇晃晃）
		Frequency = 2.0,               -- 晃动频率（较慢，沉重感）
		VerticalOffset = -0.1,         -- 垂直偏移（视角降低，模拟弯腰）
	},

	-- 平滑过渡
	TransitionSpeed = 1,             -- 状态切换时的平滑速度
}

-- 选择当前应该使用的头部晃动配置（基于优先级系统）
local function selectHeadBobConfig()
	if not PlayerStateProvider then
		return HeadBobConfig.Walk, "Walk"
	end

	-- 检查精疲力竭状态（最高优先级）
	if PlayerStateProvider.IsExhausted and HeadBobConfig.Exhausted then
		return HeadBobConfig.Exhausted, "Exhausted"
	end

	-- 检查组合状态（优先级最高）
	if PlayerStateProvider.IsCrouching and PlayerStateProvider.IsAiming then
		return HeadBobConfig.CrouchAiming, "CrouchAiming"
	end

	-- 检查单一高优先级状态
	if PlayerStateProvider.IsAiming then
		return HeadBobConfig.Aiming, "Aiming"
	end

	if PlayerStateProvider.IsCrouching then
		return HeadBobConfig.Crouch, "Crouch"
	end

	if PlayerStateProvider.IsRunning then
		return HeadBobConfig.Run, "Run"
	end

	-- 默认走路
	return HeadBobConfig.Walk, "Walk"
end

-- 更新头部晃动
local function updateHeadBob(deltaTime)
	if not PlayerStateProvider then
		CameraEffectManager.HeadBobOffset = Vector3.new(0, 0, 0)
		return
	end

	-- 检查是否启用头部晃动
	if not CameraEffectManager.HeadBobEnabled then
		CameraEffectManager.HeadBobOffset = Vector3.new(0, 0, 0)
		return
	end

	-- 获取移动速度（需要从外部获取）
	local moveSpeed = PlayerStateProvider.MoveSpeed or 0

	-- 如果没有移动，逐渐减弱晃动
	if moveSpeed < 0.1 then
		currentBobAmplitude = currentBobAmplitude * (1 - HeadBobConfig.TransitionSpeed)
		currentBobVerticalOffset = currentBobVerticalOffset * (1 - HeadBobConfig.TransitionSpeed)

		if currentBobAmplitude < 0.001 then
			-- 平滑归零而不是直接归零
			CameraEffectManager.HeadBobOffset = CameraEffectManager.HeadBobOffset * (1 - HeadBobConfig.TransitionSpeed)

			-- 当非常接近零时才完全归零
			if CameraEffectManager.HeadBobOffset.Magnitude < 0.001 then
				CameraEffectManager.HeadBobOffset = Vector3.new(0, 0, 0)
			end
			return
		end
	else
		-- 选择当前状态的配置
		local config, stateName = selectHeadBobConfig()

		if not config.Enabled then
			CameraEffectManager.HeadBobOffset = Vector3.new(0, 0, 0)
			return
		end

		-- 平滑过渡到目标幅度和频率
		-- moveSpeed 已经是归一化的值（0-1）
		local targetAmplitude = moveSpeed
		currentBobAmplitude = currentBobAmplitude + (targetAmplitude - currentBobAmplitude) * HeadBobConfig.TransitionSpeed
		currentBobFrequency = currentBobFrequency + (config.Frequency - currentBobFrequency) * HeadBobConfig.TransitionSpeed
		currentBobVerticalOffset = currentBobVerticalOffset + (config.VerticalOffset - currentBobVerticalOffset) * HeadBobConfig.TransitionSpeed

		-- 更新时间
		headBobTime = headBobTime + deltaTime * currentBobFrequency

		-- 计算晃动偏移（使用正弦波）
		local verticalBob = math.sin(headBobTime * math.pi * 2) * config.VerticalAmplitude * currentBobAmplitude
		local horizontalBob = math.sin(headBobTime * math.pi) * config.HorizontalAmplitude * currentBobAmplitude

		-- 添加垂直偏移（平滑过渡）
		verticalBob = verticalBob + currentBobVerticalOffset

		-- 更新偏移
		CameraEffectManager.HeadBobOffset = Vector3.new(horizontalBob, verticalBob, 0)
	end
end

-- 设置头部晃动参数
function CameraEffectManager:SetHeadBobConfig(mode, config)
	if not HeadBobConfig[mode] then
		warn("[CameraEffectManager] 无效的Head Bob模式:", mode)
		return
	end

	if not config then
		warn("[CameraEffectManager] 配置不能为空")
		return
	end

	-- 更新配置
	for key, value in pairs(config) do
		if HeadBobConfig[mode][key] ~= nil then
			HeadBobConfig[mode][key] = value
		end
	end
end

-- 获取头部晃动配置
function CameraEffectManager:GetHeadBobConfig(mode)
	if mode then
		return HeadBobConfig[mode]
	else
		return HeadBobConfig
	end
end

-- 启用/禁用头部晃动
function CameraEffectManager:SetHeadBobEnabled(enabled)
	self.HeadBobEnabled = enabled
	if not enabled then
		self.HeadBobOffset = Vector3.new(0, 0, 0)
	end
end

-- ============================================================================
-- 初始化和更新循环
-- ============================================================================

-- 设置玩家状态提供者（从PlayerManager获取状态）
function CameraEffectManager:SetPlayerStateProvider(provider)
	PlayerStateProvider = provider
	print("[CameraEffectManager] 玩家状态提供者已设置")
end

-- 统一的更新函数（合并所有更新到一个循环中）
local function updateAll(deltaTime)
	updateFOV()
	updateCameraShake(deltaTime)
	updateContinuousShakesBasedOnState()
	updateHeadBob(deltaTime)
end

-- 初始化
local function init()
	-- 初始化持续性摇晃配置
	initializeContinuousShakes()

	-- 启动统一的更新循环（只有一个 RenderStepped 连接）
	if updateConnection then
		updateConnection:Disconnect()
	end
	updateConnection = RunService.RenderStepped:Connect(updateAll)

	print("[CameraEffectManager] 初始化完成")
	print("[CameraEffectManager] - FOV管理系统")
	print("[CameraEffectManager] - 摄像机抖动系统")
	print("[CameraEffectManager] - 持续性摇晃系统")
	print("[CameraEffectManager] - 头部晃动系统")
end

-- 自动初始化
init()

return CameraEffectManager

