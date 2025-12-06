-- ============================================================================
-- AnimationConfigs.lua - 动画配置文件
-- 职责：集中管理所有动画ID，方便玩家自定义修改
-- ⚠️ 修改此文件可以替换游戏中的动画，但需要确保动画ID有效
-- ============================================================================

local AnimationConfigs = {}

-- ============================================================================
-- 基础动画配置（非攻击类）
-- ============================================================================
AnimationConfigs.BasicAnimations = {
	Dodge = "rbxassetid://115583572020539",     -- 闪避翻滚动画
	Down = "rbxassetid://74409949830270",       -- 蹲下动画（循环）
	Aiming = "rbxassetid://97130422316194",     -- 瞄准动画
}

-- ============================================================================
-- 攻击动画配置（按武器类型分类）
-- ============================================================================
-- 格式说明：
-- [武器类型] = {
--     [攻击类型] = { 动画ID数组 }
-- }
--
-- 攻击类型：
-- - LightAttack: 轻攻击（连招）
-- - HeavyAttack: 重攻击
-- - Skill: 技能动画
--
-- 动画ID数组：
-- - 按顺序播放，索引从1开始
-- - 支持连招：LightAttack[1] → [2] → [3] → 循环回[1]

AnimationConfigs.AttackAnimations = {
	-- 徒手/无武器
	None = {
		LightAttack = {
			"rbxassetid://86626408791230",   -- 轻攻击1：左拳
			"rbxassetid://132519929912742",  -- 轻攻击2：右拳
			-- 继续添加更多连招动画，例如：
			-- "rbxassetid://123456789",     -- 轻攻击3：踢腿
		},
		HeavyAttack = {
			-- 重攻击动画预留
			-- "rbxassetid://987654321",     -- 重攻击：蓄力一拳
		},
	},

	-- 剑类武器示例（可以自己添加）
	Sword = {
		LightAttack = {
			-- "rbxassetid://111111111",     -- 横斩
			-- "rbxassetid://222222222",     -- 竖劈
			-- "rbxassetid://333333333",     -- 刺击
		},
		HeavyAttack = {
			-- "rbxassetid://444444444",     -- 旋风斩
		},
	},

	-- 枪类武器示例
	Gun = {
		LightAttack = {
			-- "rbxassetid://555555555",     -- 射击动画
		},
		HeavyAttack = {
			-- "rbxassetid://666666666",     -- 蓄力射击
		},
	},
}

-- ============================================================================
-- 工具函数
-- ============================================================================

-- 获取基础动画ID
-- @param animationName: 动画名称（如 "Dodge", "Down", "Aiming"）
-- @return: 动画ID字符串，如果不存在返回nil
function AnimationConfigs.GetBasicAnimation(animationName)
	return AnimationConfigs.BasicAnimations[animationName]
end

-- 获取攻击动画数组
-- @param weaponType: 武器类型（如 "None", "Sword", "Gun"）
-- @param attackType: 攻击类型（如 "LightAttack", "HeavyAttack"）
-- @return: 动画ID数组，如果不存在返回空数组
function AnimationConfigs.GetAttackAnimations(weaponType, attackType)
	local weaponData = AnimationConfigs.AttackAnimations[weaponType]
	if not weaponData then
		warn("[AnimationConfigs] 未找到武器类型: " .. tostring(weaponType))
		return {}
	end

	local animations = weaponData[attackType]
	if not animations then
		warn("[AnimationConfigs] 未找到攻击类型: " .. tostring(weaponType) .. "." .. tostring(attackType))
		return {}
	end

	return animations
end

-- 获取所有武器类型列表
-- @return: 武器类型名称数组
function AnimationConfigs.GetAllWeaponTypes()
	local weaponTypes = {}
	for weaponType, _ in pairs(AnimationConfigs.AttackAnimations) do
		table.insert(weaponTypes, weaponType)
	end
	return weaponTypes
end

-- 检查武器类型是否存在
-- @param weaponType: 武器类型
-- @return: true/false
function AnimationConfigs.HasWeaponType(weaponType)
	return AnimationConfigs.AttackAnimations[weaponType] ~= nil
end

-- 获取攻击动画数量
-- @param weaponType: 武器类型
-- @param attackType: 攻击类型
-- @return: 动画数量
function AnimationConfigs.GetAttackAnimationCount(weaponType, attackType)
	local animations = AnimationConfigs.GetAttackAnimations(weaponType, attackType)
	return #animations
end

return AnimationConfigs
