--[[
	============================================================================
	ServerPlayerManager.lua - 服务器玩家管理器
	============================================================================

	职责：
	- 监听玩家加入/离开
	- 为每个玩家创建服务器权威数据包
	- 管理玩家数据包的生命周期

	注意：
	- 此模块只能在服务器端运行
	- 客户端请求处理已移至 ServerRequestHandler

	============================================================================
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引入服务器权威数据包管理器
local ServerEntityManager = require(script.Parent:WaitForChild("ServerEntityManager"))

-- 引入游戏配置数据库
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))

-- ============================================================================
-- ServerPlayerManager 模块
-- ============================================================================

local ServerPlayerManager = {}

-- ============================================================================
-- 玩家数据包初始化
-- ============================================================================

--[[
	初始化玩家数据包
	@param player: 玩家实例
]]
local function initPlayer(player)
	print(string.format("[ServerPlayerManager] Initializing player: %s", player.Name))

	-- 等待角色加载
	local character = player.Character or player.CharacterAdded:Wait()

	-- 从配置数据库获取玩家属性配置
	local playerConfig = GameConfig.GetCharacterConfig("Player")

	-- 创建生命值数据包（使用配置数据）
	local health = ServerEntityManager:CreateAttribute(player, "Health", playerConfig.Health)

	-- 创建体力数据包（使用配置数据）
	local stamina = ServerEntityManager:CreateAttribute(player, "Stamina", playerConfig.Stamina)

	print(string.format("[ServerPlayerManager] Player %s initialized with config data", player.Name))
	print(string.format("  - Health: %d/%d (Regen: %.1f/s, Cooldown: %.1fs)",
		playerConfig.Health.CurrentValue,
		playerConfig.Health.MaxValue,
		playerConfig.Health.RegenRate,
		playerConfig.Health.RegenCooldown))
	print(string.format("  - Stamina: %d/%d (Regen: %.1f/s, Cooldown: %.1fs)",
		playerConfig.Stamina.CurrentValue,
		playerConfig.Stamina.MaxValue,
		playerConfig.Stamina.RegenRate,
		playerConfig.Stamina.RegenCooldown))
end

--[[
	清理玩家数据包
	@param player: 玩家实例
]]
local function cleanupPlayer(player)
	print(string.format("[ServerPlayerManager] Cleaning up player: %s", player.Name))

	-- 清理玩家的所有数据包
	ServerEntityManager:CleanupEntity(player)
end

-- ============================================================================
-- 初始化
-- ============================================================================

local function init()
	print("[ServerPlayerManager] Initializing...")

	-- 监听玩家加入
	Players.PlayerAdded:Connect(function(player)
		initPlayer(player)

		-- 监听角色重生
		player.CharacterAdded:Connect(function(character)
			-- 清理旧数据包
			ServerEntityManager:CleanupEntity(player)
			-- 重新初始化
			initPlayer(player)
		end)
	end)

	-- 监听玩家离开
	Players.PlayerRemoving:Connect(cleanupPlayer)

	-- 为已存在的玩家初始化
	for _, player in ipairs(Players:GetPlayers()) do
		initPlayer(player)
	end

	print("[ServerPlayerManager] Initialized")
	print("[ServerPlayerManager] Player lifecycle management active")
end

-- 自动初始化
init()

return ServerPlayerManager
