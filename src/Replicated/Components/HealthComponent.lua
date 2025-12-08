--[[
	============================================================================
	HealthComponent.lua - 通用生命值组件
	============================================================================

	职责：
	- 为任何实体提供生命值管理能力
	- 包装 Attribute 数据包，提供业务接口
	- 触发死亡逻辑和视觉效果

	使用方式：
	local HealthComponent = require(ReplicatedStorage.Components.HealthComponent)

	-- 创建组件
	local health = HealthComponent.new(player, {
		MaxHealth = 100,
		RegenRate = 2,
		RegenCooldown = 3
	}, function(entity)
		print(entity.Name .. " 死亡了！")
	end)

	-- 使用组件
	health:TakeDamage(50, "Enemy", "Physical")
	health:Heal(30, "Potion")
	health:AddEffect("Poison", -5, 10)

	适用于：
	- ✅ 玩家（Player）
	- ✅ NPC敌人（Enemy）
	- ✅ 友方NPC（Ally）
	- ✅ 可破坏物体（Destructible Furniture）
	- ✅ 载具（Vehicle）

	============================================================================
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引入 ClientEntityManager（客户端镜像管理器）
local ClientEntityManager = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("System"):WaitForChild("ClientEntityManager"))

-- ============================================================================
-- HealthComponent 类
-- ============================================================================

local HealthComponent = {}
HealthComponent.__index = HealthComponent

--[[
	构造函数
	@param entity: 关联的实体（Player, Character, Model 等）
	@param config: 配置表
		- MaxHealth: 最大生命值（必填）
		- RegenRate: 自动恢复速率，每秒（可选，默认 0）
		- RegenCooldown: 恢复冷却时间，秒（可选，默认 0）
	@param onDeathCallback: 死亡回调函数（可选）
	@return: HealthComponent 实例
]]
function HealthComponent.new(entity, config, onDeathCallback)
	local self = setmetatable({}, HealthComponent)

	-- 关联的实体
	self.Entity = entity

	-- 配置参数
	self.MaxHealth = config.MaxHealth or 100
	self.RegenRate = config.RegenRate or 0
	self.RegenCooldown = config.RegenCooldown or 0

	-- 死亡回调
	self.OnDeathCallback = onDeathCallback

	-- 状态标志
	self.IsDead = false

	-- 事件监听器 ID（用于清理）
	self._eventListeners = {}

	-- 使用 ClientEntityManager 创建镜像数据包
	self.Health = ClientEntityManager:CreateAttribute(entity, "Health", {
		MaxValue = self.MaxHealth,
		CurrentValue = self.MaxHealth,
		RegenRate = self.RegenRate,
		RegenCooldown = self.RegenCooldown
	})

	-- 订阅死亡事件
	local depletedListenerId = self.Health:OnEvent("Depleted", function(data)
		self:_onDeath(data)
	end)
	table.insert(self._eventListeners, {event = "Depleted", id = depletedListenerId})

	print(string.format("[HealthComponent] 为 %s 创建生命值组件 (最大生命值: %d)",
		entity.Name or tostring(entity), self.MaxHealth))

	return self
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--[[
	受伤（扣除生命值）
	@param amount: 伤害量
	@param source: 来源标识（可选，如 "Enemy", "Fall", "Fire"）
	@param damageType: 伤害类型（可选，如 "Physical", "Magic", "Fire"）
	@return: 是否成功扣除
]]
function HealthComponent:TakeDamage(amount, source, damageType)
	if self.IsDead then
		return false
	end

	-- 调用数据包的 Consume 方法
	local success = self.Health:Consume(amount, source or "Unknown")

	if success then
		-- 触发受伤效果（音效、粒子、UI等）
		self:_triggerHitEffects(amount, damageType or "Physical")
	end

	return success
end

--[[
	治疗（恢复生命值）
	@param amount: 治疗量
	@param source: 来源标识（可选，如 "Potion", "Spell", "NaturalRegen"）
]]
function HealthComponent:Heal(amount, source)
	if self.IsDead then
		return
	end

	-- 调用数据包的 Restore 方法
	self.Health:Restore(amount, source or "Unknown")

	-- 可以在这里触发治疗效果（绿色粒子、音效等）
	self:_triggerHealEffects(amount)
end

--[[
	添加持续效果（中毒、燃烧、再生等）
	@param name: 效果名称
	@param changePerSecond: 每秒变化量（负数为伤害，正数为治疗）
	@param duration: 持续时间（秒），nil 表示无限持续
	@return: 修改器 ID

	示例：
	- 中毒：AddEffect("Poison", -5, 10)  -- 每秒扣5点，持续10秒
	- 生命恢复：AddEffect("Regeneration", 3, 20)  -- 每秒恢复3点，持续20秒
	- 流血：AddEffect("Bleeding", -2, nil)  -- 每秒扣2点，直到移除
]]
function HealthComponent:AddEffect(name, changePerSecond, duration)
	if self.IsDead then
		return nil
	end

	-- 调用数据包的 AddModifier 方法
	return self.Health:AddModifier(name, changePerSecond, duration)
end

--[[
	移除持续效果（通过 ID）
	@param modifierId: 修改器 ID
	@return: 是否成功移除
]]
function HealthComponent:RemoveEffect(modifierId)
	return self.Health:RemoveModifier(modifierId)
end

--[[
	移除持续效果（通过名称）
	@param name: 效果名称
	@return: 移除的数量

	示例：
	- 解毒：RemoveEffect("Poison")
	- 止血：RemoveEffect("Bleeding")
]]
function HealthComponent:RemoveEffectByName(name)
	return self.Health:RemoveModifierByName(name)
end

--[[
	清除所有持续效果

	示例：
	- 净化所有 Debuff：ClearAllEffects()
]]
function HealthComponent:ClearAllEffects()
	self.Health:ClearAllModifiers()
end

--[[
	获取当前生命值
	@return: 当前生命值
]]
function HealthComponent:GetCurrentHealth()
	return self.Health.CurrentValue
end

--[[
	获取最大生命值
	@return: 最大生命值
]]
function HealthComponent:GetMaxHealth()
	return self.Health.MaxValue
end

--[[
	获取生命值百分比
	@return: 生命值百分比（0.0 - 1.0）
]]
function HealthComponent:GetHealthPercentage()
	if not self.Health then return 0 end
	return self.Health.CurrentValue / self.Health.MaxValue
end

--[[
	是否还活着
	@return: true 表示活着，false 表示死亡
]]
function HealthComponent:IsAlive()
	return not self.IsDead
end

--[[
	订阅生命值事件
	@param eventName: 事件名称（"Changed", "Consumed", "Restored", "Depleted"）
	@param callback: 回调函数
	@return: 监听器 ID

	示例：
	health:OnEvent("Changed", function(data)
		print("生命值变化：", data.currentValue, "/", data.maxValue)
	end)
]]
function HealthComponent:OnEvent(eventName, callback)
	local listenerId = self.Health:OnEvent(eventName, callback)
	if listenerId then
		table.insert(self._eventListeners, {event = eventName, id = listenerId})
	end
	return listenerId
end

-- ============================================================================
-- 内部方法
-- ============================================================================

--[[
	内部：死亡处理
]]
function HealthComponent:_onDeath(data)
	if self.IsDead then return end

	self.IsDead = true

	-- 清除所有效果
	self:ClearAllEffects()

	print(string.format("[HealthComponent] %s 已死亡", self.Entity.Name or tostring(self.Entity)))

	-- 触发死亡回调
	if self.OnDeathCallback then
		self.OnDeathCallback(self.Entity, data)
	end

	-- 可以在这里添加通用的死亡效果
	self:_triggerDeathEffects()
end

--[[
	内部：触发受伤效果（可选，根据实体类型自定义）
]]
function HealthComponent:_triggerHitEffects(amount, damageType)
	-- 这里可以根据实体类型添加不同的效果
	-- 玩家：屏幕红边、伤害数字
	-- NPC：血液粒子、受伤音效
	-- 家具：裂纹贴图、木屑粒子

	-- 示例：打印伤害日志
	print(string.format("[HealthComponent] %s 受到 %d 点 %s 伤害（剩余: %.1f%%）",
		self.Entity.Name or tostring(self.Entity),
		amount,
		damageType,
		self:GetHealthPercentage() * 100
	))
end

--[[
	内部：触发治疗效果（可选）
]]
function HealthComponent:_triggerHealEffects(amount)
	-- 可以在这里添加治疗效果（绿色粒子、音效等）
	print(string.format("[HealthComponent] %s 恢复 %d 点生命值",
		self.Entity.Name or tostring(self.Entity),
		amount
	))
end

--[[
	内部：触发死亡效果（可选）
]]
function HealthComponent:_triggerDeathEffects()
	-- 可以在这里添加通用的死亡效果
	-- 例如：播放死亡音效、显示死亡粒子等
end

-- ============================================================================
-- 清理
-- ============================================================================

--[[
	清理组件
]]
function HealthComponent:Cleanup()
	print(string.format("[HealthComponent] 清理 %s 的生命值组件",
		self.Entity.Name or tostring(self.Entity)))

	-- 取消所有事件订阅
	for _, listener in ipairs(self._eventListeners) do
		self.Health:OffEvent(listener.event, listener.id)
	end
	self._eventListeners = {}

	-- 清理数据包
	ClientEntityManager:CleanupAttribute(self.Entity, "Health")

	-- 清空引用
	self.Health = nil
	self.Entity = nil
	self.OnDeathCallback = nil
end

return HealthComponent
