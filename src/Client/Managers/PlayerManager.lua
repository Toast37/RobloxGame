--[[
	============================================================================
	PlayerManager.lua - 玩家状态和组件管理器
	============================================================================

	功能：
	- 玩家状态标志管理（蹲下、瞄准、奔跑、精疲力竭、残血、死亡等）
	- 移动速度自动控制
	- 组件实例管理（HealthComponent, StaminaComponent）

	使用方式：
	local PlayerManager = require(script.PlayerManager)
	PlayerManager.IsAiming = true  -- 设置瞄准状态

	-- 组件访问
	PlayerManager.StaminaComp:Consume(20, "Dodge")
	PlayerManager.HealthComp:Restore(50, "Potion")

	注意：
	- 这是一个客户端模块（仅客户端使用）
	- 使用组件系统管理生命值和体力
	- 状态标志由组件事件自动更新
	- 摄像机效果由 CameraEffectManager 管理

	============================================================================
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引入管理器和组件
local CameraEffectManager = require(ReplicatedStorage:WaitForChild("CameraEffectManager"))
local HealthComponent = require(ReplicatedStorage:WaitForChild("HealthComponent"))
local StaminaComponent = require(ReplicatedStorage:WaitForChild("StaminaComponent"))

-- 引入游戏配置数据库
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

-- ============================================================================
-- 公开状态变量
-- ============================================================================

local PlayerManager = {
	-- === 组件实例 ===
	HealthComp = nil,                 -- 生命值组件
	StaminaComp = nil,                -- 体力组件

	-- === 状态标志 ===
	IsExhausted = false,              -- 精疲力竭状态（体力耗尽）
	IsLowHealth = false,              -- 残血状态（生命值低于30%）
	IsDead = false,                   -- 死亡状态

	-- === 移动状态 ===
	IsCrouching = false,              -- 是否蹲下
	IsAiming = false,                 -- 是否瞄准
	IsRunning = false,                -- 是否奔跑
	IsDodging = false,                -- 是否闪避

	-- === 移动参数 ===
	DefaultWalkSpeed = 16,            -- 默认行走速度
	MoveSpeed = 0,                    -- 当前移动速度（供摄像机效果使用）
	DefaultJumpHeight = 7.2,          -- 默认跳跃高度
	DefaultHipHeight = 2,             -- 默认髋部高度
	CrouchSpeedMultiplier = 0.5,      -- 蹲下速度倍数
	AimSpeedMultiplier = 0.5,         -- 瞄准速度倍数
	RunSpeedMultiplier = 1.5,         -- 奔跑速度倍数
	ExhaustedSpeedMultiplier = 0.5,   -- 筋疲力尽速度倍数

	-- === 摄像机参数 ===
	DefaultCameraOffset = Vector3.new(2.5, 2.5, 5),
	RawCameraAngleX = 0,              -- 原始摄像机水平角度（供准心系统使用）
	RawCameraAngleY = 0,              -- 原始摄像机垂直角度（供准心系统使用）

	-- === 目标锁定 ===
	IsTargetLocked = false,           -- 是否锁定目标
	LockedTarget = nil,               -- 锁定的目标
	LockDetectionRadius = 30,         -- 锁定检测半径
}

-- ============================================================================
-- 私有变量
-- ============================================================================

-- === 角色引用 ===
local player = Players.LocalPlayer
local character = nil
local humanoid = nil

-- === 更新循环连接 ===
local speedUpdateConnection = nil

-- ============================================================================
-- 速度管理系统
-- ============================================================================

--[[
	计算当前应该的移动速度
	公式：最终速度 = 基础速度 × 瞄准倍数 × 蹲下倍数 × 奔跑倍数 × 精疲力竭倍数
]]
local function calculateSpeed()
	local speed = PlayerManager.DefaultWalkSpeed

	if PlayerManager.IsAiming then
		speed = speed * PlayerManager.AimSpeedMultiplier
	end

	if PlayerManager.IsCrouching then
		speed = speed * PlayerManager.CrouchSpeedMultiplier
	end

	if PlayerManager.IsRunning then
		speed = speed * PlayerManager.RunSpeedMultiplier
	end

	if PlayerManager.IsExhausted then
		speed = speed * PlayerManager.ExhaustedSpeedMultiplier
	end

	return speed
end

-- 更新角色移动速度
local function updateSpeed()
	if not humanoid or humanoid.Health <= 0 or PlayerManager.IsDodging then
		return
	end

	humanoid.WalkSpeed = calculateSpeed()

	-- 更新移动速度（归一化值 0-1，供摄像机效果使用）
	PlayerManager.MoveSpeed = humanoid.MoveDirection.Magnitude
end

-- ============================================================================
-- 初始化
-- ============================================================================

-- 设置角色
local function setupCharacter(newCharacter)
	character = newCharacter
	humanoid = character:WaitForChild("Humanoid")

	-- 断开旧的连接
	if speedUpdateConnection then
		speedUpdateConnection:Disconnect()
	end

	-- 每帧更新速度
	speedUpdateConnection = RunService.Heartbeat:Connect(updateSpeed)

	-- 从配置数据库获取玩家属性
	local playerConfig = GameConfig.GetCharacterConfig("Player")

	-- 创建生命值组件（使用配置数据）
	PlayerManager.HealthComp = HealthComponent.new(player, {
		MaxHealth = playerConfig.Health.MaxValue,
		RegenRate = playerConfig.Health.RegenRate,
		RegenCooldown = playerConfig.Health.RegenCooldown,
	}, function(entity, data)
		-- 死亡回调
		PlayerManager.IsDead = true
		print("[PlayerManager] 玩家死亡")
	end)

	-- 创建体力组件（使用配置数据）
	PlayerManager.StaminaComp = StaminaComponent.new(player, {
		MaxStamina = playerConfig.Stamina.MaxValue,
		RegenRate = playerConfig.Stamina.RegenRate,
		RegenCooldown = playerConfig.Stamina.RegenCooldown,
	}, function(entity, data)
		-- 体力耗尽回调
		PlayerManager.IsExhausted = true
		PlayerManager.IsRunning = false  -- 体力耗尽时停止奔跑
		print("[PlayerManager] 精疲力竭状态激活")
	end, function(entity, data)
		-- 体力恢复回调
		if data.percentage >= 0.3 then
			PlayerManager.IsExhausted = false
			print("[PlayerManager] 精疲力竭状态解除")
		end
	end)

	-- 监听生命值变化，更新 IsLowHealth 状态
	PlayerManager.HealthComp:OnEvent("Changed", function(data)
		local wasLowHealth = PlayerManager.IsLowHealth
		PlayerManager.IsLowHealth = data.percentage < 0.3

		if PlayerManager.IsLowHealth and not wasLowHealth then
			print("[PlayerManager] 残血状态激活")
			--（残血状态占位符）
		elseif not PlayerManager.IsLowHealth and wasLowHealth then
			print("[PlayerManager] 残血状态解除")

		end
	end)

	-- 设置 CameraEffectManager 的玩家状态提供者
	CameraEffectManager:SetPlayerStateProvider(PlayerManager)

	print("[PlayerManager] 角色初始化完成（使用配置数据）")
	print(string.format("[PlayerManager] - 生命值: %d (恢复: %.1f/s, 冷却: %.1fs)",
		playerConfig.Health.MaxValue,
		playerConfig.Health.RegenRate,
		playerConfig.Health.RegenCooldown))
	print(string.format("[PlayerManager] - 体力: %d (恢复: %.1f/s, 冷却: %.1fs)",
		playerConfig.Stamina.MaxValue,
		playerConfig.Stamina.RegenRate,
		playerConfig.Stamina.RegenCooldown))
	print("[PlayerManager] - 状态事件监听已激活")
end

-- 初始化管理器
local function init()
	if player.Character then
		setupCharacter(player.Character)
	end

	player.CharacterAdded:Connect(setupCharacter)

	print("[PlayerManager] 初始化完成")
	print("[PlayerManager] - 组件系统（HealthComponent, StaminaComponent）")
	print("[PlayerManager] - 速度管理系统")
	print("[PlayerManager] - 状态标志管理")
end

-- 自动初始化
init()

return PlayerManager