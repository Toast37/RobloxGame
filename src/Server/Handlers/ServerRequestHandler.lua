--[[
	============================================================================
	ServerRequestHandler.lua - 服务器请求验证中心
	============================================================================

	职责：
	- 统一处理所有客户端请求
	- 验证请求的合法性，防止作弊
	- 分发请求到对应的处理函数
	- 记录请求日志

	请求类型：
	- ConsumeStamina: 消耗体力
	- TakeDamage: 受到伤害
	- Heal: 治疗
	- AddStaminaModifier: 添加体力修改器
	- RemoveStaminaModifier: 移除体力修改器
	- Attack: 攻击请求（Player, Target, Action）

	使用方式：
	-- 此模块会自动初始化，无需手动调用

	注意：
	- 此模块只能在服务器端运行
	- 所有客户端请求必须经过此模块验证

	============================================================================
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 引入服务器权威数据包管理器
local ServerEntityManager = require(script.Parent:WaitForChild("ServerEntityManager"))

-- 引入游戏配置数据库（服务器只信任自己的配置）
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))

-- ============================================================================
-- ServerRequestHandler 模块
-- ============================================================================

local ServerRequestHandler = {
	_requestRemote = nil,  -- RemoteEvent for handling client requests
	_requestLog = {},  -- 请求日志（用于反作弊检测）
}

-- ============================================================================
-- 验证函数
-- ============================================================================

--[[
	验证玩家是否有效
	@param player: 玩家实例
	@return: 是否有效
]]
local function validatePlayer(player)
	if not player or not player:IsDescendantOf(Players) then
		warn("[ServerRequestHandler] Invalid player in request")
		return false
	end
	return true
end

--[[
	验证数值参数
	@param value: 数值
	@param min: 最小值
	@param max: 最大值
	@param name: 参数名称（用于日志）
	@return: 是否有效
]]
local function validateNumber(value, min, max, name)
	if type(value) ~= "number" then
		warn(string.format("[ServerRequestHandler] Invalid %s type: %s", name, type(value)))
		return false
	end

	if value < min or value > max then
		warn(string.format("[ServerRequestHandler] Invalid %s value: %s (must be between %d and %d)",
			name, tostring(value), min, max))
		return false
	end

	return true
end

--[[
	攻击验证函数（占位符，PVP 未实装）
	@param player: 发起攻击的玩家
	@param target: 攻击目标
	@param action: 攻击行为
	@return: 是否通过验证, 错误信息
]]
local function validateAttack(player, target, action)
	-- TODO: 实装 PVP 时完成此函数

	-- 基础验证
	if not player or not target then
		return false, "Invalid player or target"
	end

	if not action or type(action) ~= "string" then
		return false, "Invalid action"
	end

	-- 检查目标是否存在
	if not target:IsDescendantOf(workspace) then
		return false, "Target not in workspace"
	end

	-- 检查距离（防止超远程攻击作弊）
	local playerCharacter = player.Character
	if not playerCharacter or not playerCharacter:FindFirstChild("HumanoidRootPart") then
		return false, "Player character not found"
	end

	local targetRootPart = target:FindFirstChild("HumanoidRootPart")
	if not targetRootPart then
		return false, "Target has no HumanoidRootPart"
	end

	local distance = (playerCharacter.HumanoidRootPart.Position - targetRootPart.Position).Magnitude
	local MAX_ATTACK_RANGE = 50  -- 最大攻击范围（可调整）

	if distance > MAX_ATTACK_RANGE then
		return false, string.format("Target too far away: %.1f (max: %d)", distance, MAX_ATTACK_RANGE)
	end

	-- PVP 检查（占位符）
	-- TODO: 检查是否允许 PVP
	-- TODO: 检查是否在安全区
	-- TODO: 检查是否在同一队伍

	-- 通过验证
	return true, nil
end

-- ============================================================================
-- 请求处理函数
-- ============================================================================

--[[
	处理消耗体力请求
	@param player: 发起请求的玩家
	@param data: 请求数据
]]
local function handleConsumeStamina(player, data)
	local stamina = ServerEntityManager:GetAttribute(player, "Stamina")
	if not stamina then
		warn(string.format("[ServerRequestHandler] Stamina attribute not found for %s", player.Name))
		return
	end

	-- 验证数据合法性
	if not validateNumber(data.amount, 0, 100, "stamina consume amount") then
		return
	end

	-- 执行消耗
	local success = stamina:Consume(data.amount, data.source or "Unknown")
	if success then
		print(string.format("[ServerRequestHandler] %s consumed %d stamina (%s)",
			player.Name, data.amount, data.source or "Unknown"))
	end
end

--[[
	处理受到伤害请求
	@param player: 发起请求的玩家
	@param data: 请求数据
]]
local function handleTakeDamage(player, data)
	local health = ServerEntityManager:GetAttribute(player, "Health")
	if not health then
		warn(string.format("[ServerRequestHandler] Health attribute not found for %s", player.Name))
		return
	end

	-- 验证数据合法性
	if not validateNumber(data.amount, 0, 1000, "damage amount") then
		return
	end

	-- 执行伤害
	local success = health:Consume(data.amount, data.source or "Unknown")
	if success then
		print(string.format("[ServerRequestHandler] %s took %d damage (%s)",
			player.Name, data.amount, data.source or "Unknown"))
	end
end

--[[
	处理治疗请求
	@param player: 发起请求的玩家
	@param data: 请求数据
]]
local function handleHeal(player, data)
	local health = ServerEntityManager:GetAttribute(player, "Health")
	if not health then
		warn(string.format("[ServerRequestHandler] Health attribute not found for %s", player.Name))
		return
	end

	-- 验证数据合法性
	if not validateNumber(data.amount, 0, 1000, "heal amount") then
		return
	end

	-- 执行治疗
	health:Restore(data.amount, data.source or "Unknown")
	print(string.format("[ServerRequestHandler] %s healed %d HP (%s)",
		player.Name, data.amount, data.source or "Unknown"))
end

--[[
	处理添加体力修改器请求
	@param player: 发起请求的玩家
	@param data: 请求数据
]]
local function handleAddStaminaModifier(player, data)
	local stamina = ServerEntityManager:GetAttribute(player, "Stamina")
	if not stamina then
		warn(string.format("[ServerRequestHandler] Stamina attribute not found for %s", player.Name))
		return
	end

	-- 验证数据合法性
	if not validateNumber(data.changePerSecond, -100, 100, "modifier changePerSecond") then
		return
	end

	-- 添加修改器
	local modifierId = stamina:AddModifier(
		data.name or "UnknownModifier",
		data.changePerSecond,
		data.duration
	)
	print(string.format("[ServerRequestHandler] %s added stamina modifier: %s (%.1f/s)",
		player.Name, data.name, data.changePerSecond))
end

--[[
	处理移除体力修改器请求
	@param player: 发起请求的玩家
	@param data: 请求数据
]]
local function handleRemoveStaminaModifier(player, data)
	local stamina = ServerEntityManager:GetAttribute(player, "Stamina")
	if not stamina then
		warn(string.format("[ServerRequestHandler] Stamina attribute not found for %s", player.Name))
		return
	end

	local removed = stamina:RemoveModifierByName(data.name)
	if removed > 0 then
		print(string.format("[ServerRequestHandler] %s removed stamina modifier: %s",
			player.Name, data.name))
	end
end

--[[
	处理攻击请求
	@param player: 发起请求的玩家
	@param data: 请求数据
		- Target: 攻击目标（Model）
		- Action: 攻击行为（字符串，如 "MeleeAttack", "Sword", "Skill_HeavyStrike"）
]]
local function handleAttack(player, data)
	-- 验证参数是否存在
	if not data.Target or not data.Action then
		warn(string.format("[ServerRequestHandler] Missing Target or Action in attack request from %s",
			player.Name))
		return
	end

	-- 验证攻击是否合法
	local isValid, errorMessage = validateAttack(player, data.Target, data.Action)

	if not isValid then
		warn(string.format("[ServerRequestHandler] Attack validation failed for %s: %s",
			player.Name, errorMessage))
		return
	end

	print(string.format("[ServerRequestHandler] %s attacks %s with action: %s",
		player.Name, tostring(data.Target), data.Action))

	-- ============================================================
	-- 服务器权威伤害计算（不信任客户端传来的任何数值）
	-- ============================================================

	local damage = 0
	local weaponConfig = nil
	local skillConfig = nil
	local staminaCost = 0

	-- 解析攻击类型
	if data.Action:find("Skill_") then
		-- 技能攻击
		local skillName = data.Action:gsub("Skill_", "")

		-- TODO: 从玩家身上获取职业信息
		-- 这里暂时使用 Warrior 作为示例
		local classType = "Warrior"
		skillConfig = GameConfig.GetSkillConfig(classType, skillName)

		if not skillConfig then
			warn(string.format("[ServerRequestHandler] Invalid skill: %s", skillName))
			return
		end

		-- 从配置获取技能伤害和消耗
		damage = math.random(skillConfig.Damage.Min, skillConfig.Damage.Max)
		staminaCost = skillConfig.StaminaCost

		print(string.format("[ServerRequestHandler] Using skill: %s (Damage: %d, Cost: %d)",
			skillConfig.Name, damage, staminaCost))

	elseif data.Action:find("Weapon_") then
		-- 武器攻击
		local weaponName = data.Action:gsub("Weapon_", "")

		-- TODO: 验证玩家是否真的装备了这个武器
		-- 暂时假设是近战武器
		weaponConfig = GameConfig.GetWeaponConfig("Melee", weaponName)

		if not weaponConfig then
			warn(string.format("[ServerRequestHandler] Invalid weapon: %s", weaponName))
			return
		end

		-- 从配置获取武器伤害和消耗
		local baseDamage = math.random(weaponConfig.Damage.Min, weaponConfig.Damage.Max)

		-- 计算是否暴击
		local isCrit = math.random() < weaponConfig.CritChance

		-- 计算最终伤害（带浮动和暴击）
		damage = GameConfig.CalculateDamage(baseDamage, isCrit, weaponConfig.CritMultiplier)
		staminaCost = weaponConfig.StaminaCost

		print(string.format("[ServerRequestHandler] Using weapon: %s (Damage: %d%s, Cost: %d)",
			weaponConfig.Name, damage, isCrit and " CRIT!" or "", staminaCost))

	else
		-- 默认普通攻击
		damage = math.random(10, 15)
		staminaCost = 5
		print(string.format("[ServerRequestHandler] Basic attack (Damage: %d, Cost: %d)",
			damage, staminaCost))
	end

	-- ============================================================
	-- 消耗玩家体力（服务器验证）
	-- ============================================================

	local playerStamina = ServerEntityManager:GetAttribute(player, "Stamina")
	if not playerStamina then
		warn(string.format("[ServerRequestHandler] Player %s has no Stamina attribute", player.Name))
		return
	end

	-- 检查体力是否足够
	if playerStamina.CurrentValue < staminaCost then
		warn(string.format("[ServerRequestHandler] %s has insufficient stamina: %.1f < %d",
			player.Name, playerStamina.CurrentValue, staminaCost))
		-- TODO: 通知客户端体力不足
		return
	end

	-- 消耗体力
	playerStamina:Consume(staminaCost, "Attack")

	-- ============================================================
	-- 对目标造成伤害（服务器权威）
	-- ============================================================

	local targetHealth = ServerEntityManager:GetAttribute(data.Target, "Health")
	if targetHealth then
		targetHealth:Consume(damage, string.format("Attack by %s", player.Name))
		print(string.format("[ServerRequestHandler] Dealt %d damage to %s", damage, tostring(data.Target)))

		-- TODO: 广播攻击事件给所有客户端（播放特效、音效等）
		-- TODO: 检查目标是否死亡
	else
		warn(string.format("[ServerRequestHandler] Target %s has no Health attribute", tostring(data.Target)))
	end
end

-- ============================================================================
-- 主请求处理入口
-- ============================================================================

--[[
	处理客户端请求（统一入口）
	@param player: 发起请求的玩家
	@param action: 请求的操作类型（字符串）
	@param data: 请求数据（表）
]]
local function handleClientRequest(player, action, data)
	-- 验证玩家是否有效
	if not validatePlayer(player) then
		return
	end

	-- 记录请求日志（用于反作弊分析）
	table.insert(ServerRequestHandler._requestLog, {
		player = player,
		action = action,
		timestamp = tick(),
	})

	-- 根据操作类型分发请求
	if action == "ConsumeStamina" then
		handleConsumeStamina(player, data)

	elseif action == "TakeDamage" then
		handleTakeDamage(player, data)

	elseif action == "Heal" then
		handleHeal(player, data)

	elseif action == "AddStaminaModifier" then
		handleAddStaminaModifier(player, data)

	elseif action == "RemoveStaminaModifier" then
		handleRemoveStaminaModifier(player, data)

	elseif action == "Attack" then
		handleAttack(player, data)

	else
		warn(string.format("[ServerRequestHandler] Unknown action from %s: %s",
			player.Name, tostring(action)))
	end
end

-- ============================================================================
-- 初始化
-- ============================================================================

local function init()
	-- 只在服务器端初始化
	if not RunService:IsServer() then
		error("[ServerRequestHandler] This module can only be required on the server!")
	end

	print("[ServerRequestHandler] Initializing...")

	-- 获取 RemoteEvent
	local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not remoteEvents then
		error("[ServerRequestHandler] RemoteEvents folder not found!")
	end

	ServerRequestHandler._requestRemote = remoteEvents:WaitForChild("RequestAction", 10)
	if not ServerRequestHandler._requestRemote then
		error("[ServerRequestHandler] RequestAction RemoteEvent not found!")
	end

	-- 监听客户端请求
	ServerRequestHandler._requestRemote.OnServerEvent:Connect(handleClientRequest)

	print("[ServerRequestHandler] Initialized")
	print("[ServerRequestHandler] Listening for client requests")
	print("[ServerRequestHandler] - ConsumeStamina")
	print("[ServerRequestHandler] - TakeDamage")
	print("[ServerRequestHandler] - Heal")
	print("[ServerRequestHandler] - AddStaminaModifier")
	print("[ServerRequestHandler] - RemoveStaminaModifier")
	print("[ServerRequestHandler] - Attack (with validation)")
end

-- 自动初始化
init()

return ServerRequestHandler
