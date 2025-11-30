--[[
	============================================================================
	GameConfig.lua - 游戏配置数据库（服务器权威）
	============================================================================

	职责：
	- 存储所有游戏配置数据（角色属性、武器、技能等）
	- 提供配置查询接口
	- 防止客户端篡改数据

	重要原则：
	- 服务器只信任自己的配置数据
	- 客户端传来的数值一个都不能信
	- 所有数值验证都基于此配置数据库

	使用方式：
	local GameConfig = require(script.GameConfig)
	local playerConfig = GameConfig.Characters.Player
	local weaponConfig = GameConfig.Weapons.Sword

	============================================================================
]]

local GameConfig = {}

-- ============================================================================
-- 角色属性配置
-- ============================================================================

GameConfig.Characters = {
	-- 玩家默认属性
	Player = {
		-- 生命值配置
		Health = {
			MaxValue = 100,
			CurrentValue = 100,
			RegenRate = 0,          -- 不自动恢复（需要道具/技能）
			RegenCooldown = 0,
		},

		-- 体力配置
		Stamina = {
			MaxValue = 100,
			CurrentValue = 100,
			RegenRate = 8,          -- 每秒恢复 8 点
			RegenCooldown = 1,      -- 消耗后 1 秒开始恢复
		},

		-- 移动速度
		MoveSpeed = {
			Walk = 16,              -- 行走速度
			Run = 24,               -- 奔跑速度
			Sprint = 32,            -- 冲刺速度
		},

		-- 防御属性
		Defense = {
			Physical = 0,           -- 物理防御
			Magical = 0,            -- 魔法防御
		},
	},

	-- NPC 配置示例
	NPC = {
		-- 普通敌人
		BasicEnemy = {
			Health = {
				MaxValue = 50,
				CurrentValue = 50,
				RegenRate = 0,
				RegenCooldown = 0,
			},
			Stamina = {
				MaxValue = 50,
				CurrentValue = 50,
				RegenRate = 5,
				RegenCooldown = 2,
			},
			MoveSpeed = {
				Walk = 12,
				Run = 18,
				Sprint = 0,         -- 不能冲刺
			},
			Defense = {
				Physical = 5,
				Magical = 0,
			},
		},

		-- 精英敌人
		EliteEnemy = {
			Health = {
				MaxValue = 150,
				CurrentValue = 150,
				RegenRate = 1,      -- 缓慢恢复
				RegenCooldown = 5,
			},
			Stamina = {
				MaxValue = 100,
				CurrentValue = 100,
				RegenRate = 6,
				RegenCooldown = 1.5,
			},
			MoveSpeed = {
				Walk = 14,
				Run = 20,
				Sprint = 28,
			},
			Defense = {
				Physical = 10,
				Magical = 5,
			},
		},

		-- Boss
		Boss = {
			Health = {
				MaxValue = 500,
				CurrentValue = 500,
				RegenRate = 2,
				RegenCooldown = 10,
			},
			Stamina = {
				MaxValue = 200,
				CurrentValue = 200,
				RegenRate = 10,
				RegenCooldown = 2,
			},
			MoveSpeed = {
				Walk = 10,
				Run = 16,
				Sprint = 24,
			},
			Defense = {
				Physical = 20,
				Magical = 15,
			},
		},
	},
}

-- ============================================================================
-- 辅助函数
-- ============================================================================

--[[
	获取角色配置
	@param characterType: 角色类型（"Player", "BasicEnemy", "EliteEnemy", "Boss"）
	@return: 配置表
]]
function GameConfig.GetCharacterConfig(characterType)
	if characterType == "Player" then
		return GameConfig.Characters.Player
	else
		return GameConfig.Characters.NPC[characterType]
	end
end

--[[
	获取武器配置
	@param weaponType: 武器类型（"Melee" 或 "Ranged"）
	@param weaponName: 武器名称（"Sword", "Axe", "Bow" 等）
	@return: 配置表
]]
function GameConfig.GetWeaponConfig(weaponType, weaponName)
	if GameConfig.Weapons[weaponType] then
		return GameConfig.Weapons[weaponType][weaponName]
	end
	return nil
end

--[[
	获取技能配置
	@param classType: 职业类型（"Warrior", "Assassin", "Mage"）
	@param skillName: 技能名称
	@return: 配置表
]]
function GameConfig.GetSkillConfig(classType, skillName)
	if GameConfig.Skills[classType] then
		return GameConfig.Skills[classType][skillName]
	end
	return nil
end

--[[
	获取消耗品配置
	@param itemName: 物品名称
	@return: 配置表
]]
function GameConfig.GetConsumableConfig(itemName)
	return GameConfig.Consumables[itemName]
end

--[[
	验证攻击范围是否合法
	@param range: 攻击范围
	@return: 是否合法
]]
function GameConfig.ValidateAttackRange(range)
	return range <= GameConfig.GameRules.Combat.MaxAttackRange
end

--[[
	计算实际伤害（带浮动和暴击）
	@param baseDamage: 基础伤害（Min-Max 之间）
	@param isCrit: 是否暴击
	@param critMultiplier: 暴击倍率（可选）
	@return: 实际伤害
]]
function GameConfig.CalculateDamage(baseDamage, isCrit, critMultiplier)
	local variance = GameConfig.GameRules.Combat.DamageVariance
	local damage = baseDamage * (1 + math.random() * variance * 2 - variance)

	if isCrit then
		local mult = critMultiplier or 1.5
		mult = math.clamp(mult,
			GameConfig.GameRules.Combat.CritDamageMin,
			GameConfig.GameRules.Combat.CritDamageMax)
		damage = damage * mult
	end

	return math.floor(damage + 0.5)  -- 四舍五入
end

return GameConfig
