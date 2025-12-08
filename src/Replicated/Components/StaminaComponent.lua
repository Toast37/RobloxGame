--[[
	============================================================================
	StaminaComponent.lua - 通用体力组件
	============================================================================

	职责：
	- 为任何实体提供体力管理能力
	- 包装 Attribute 数据包，提供业务接口
	- 触发耗尽逻辑和视觉效果

	使用方式：
	local StaminaComponent = require(ReplicatedStorage.Components.StaminaComponent)

	-- 创建组件
	local stamina = StaminaComponent.new(player, {
		MaxStamina = 100,
		RegenRate = 8,
		RegenCooldown = 1
	}, function(entity)
		print(entity.Name .. " 精疲力竭！")
	end)

	-- 使用组件
	stamina:Consume(20, "Dodge")
	stamina:Restore(50, "Potion")
	stamina:AddEffect("Running", -10, nil)

	适用于：
	- ✅ 玩家（Player）
	- ✅ NPC（可以有体力限制）
	- ✅ 载具（燃料系统）
	- ✅ 任何需要"消耗资源"的实体

	============================================================================
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引入 ClientEntityManager（客户端镜像管理器）
local ClientEntityManager = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("System"):WaitForChild("ClientEntityManager"))

-- ============================================================================
-- StaminaComponent 类
-- ============================================================================

local StaminaComponent = {}
StaminaComponent.__index = StaminaComponent

--[[
	构造函数
	@param entity: 关联的实体（Player, Character, Model 等）
	@param config: 配置表
		- MaxStamina: 最大体力值（必填）
		- RegenRate: 自动恢复速率，每秒（可选，默认 8）
		- RegenCooldown: 恢复冷却时间，秒（可选，默认 1）
	@param onDepletedCallback: 体力耗尽回调函数（可选）
	@param onRestoredCallback: 体力恢复回调函数（可选）
	@return: StaminaComponent 实例
]]
function StaminaComponent.new(entity, config, onDepletedCallback, onRestoredCallback)
	local self = setmetatable({}, StaminaComponent)

	-- 关联的实体
	self.Entity = entity

	-- 配置参数
	self.MaxStamina = config.MaxStamina or 100
	self.RegenRate = config.RegenRate or 8
	self.RegenCooldown = config.RegenCooldown or 1

	-- 回调函数
	self.OnDepletedCallback = onDepletedCallback
	self.OnRestoredCallback = onRestoredCallback

	-- 状态标志
	self.IsExhausted = false

	-- 事件监听器 ID（用于清理）
	self._eventListeners = {}

	-- 使用 ClientEntityManager 创建镜像数据包
	self.Stamina = ClientEntityManager:CreateAttribute(entity, "Stamina", {
		MaxValue = self.MaxStamina,
		CurrentValue = self.MaxStamina,
		RegenRate = self.RegenRate,
		RegenCooldown = self.RegenCooldown
	})

	-- 订阅耗尽事件
	local depletedListenerId = self.Stamina:OnEvent("Depleted", function(data)
		self:_onDepleted(data)
	end)
	table.insert(self._eventListeners, {event = "Depleted", id = depletedListenerId})

	-- 订阅恢复事件（检测是否从精疲力竭状态恢复）
	local restoredListenerId = self.Stamina:OnEvent("Restored", function(data)
		if data.percentage >= 0.3 and self.IsExhausted then
			self.IsExhausted = false
			if self.OnRestoredCallback then
				self.OnRestoredCallback(self.Entity, data)
			end
			print(string.format("[StaminaComponent] %s 从精疲力竭状态恢复",
				self.Entity.Name or tostring(self.Entity)))
		end
	end)
	table.insert(self._eventListeners, {event = "Restored", id = restoredListenerId})

	print(string.format("[StaminaComponent] 为 %s 创建体力组件 (最大体力: %d)",
		entity.Name or tostring(entity), self.MaxStamina))

	return self
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--[[
	消耗体力
	@param amount: 消耗量
	@param source: 来源标识（可选，如 "Dodge", "Sprint", "Attack"）
	@return: 是否成功消耗
]]
function StaminaComponent:Consume(amount, source)
	if self.IsExhausted then
		return false
	end

	-- 调用数据包的 Consume 方法
	return self.Stamina:Consume(amount, source or "Unknown")
end

--[[
	恢复体力
	@param amount: 恢复量
	@param source: 来源标识（可选，如 "Potion", "Rest"）
]]
function StaminaComponent:Restore(amount, source)
	-- 调用数据包的 Restore 方法
	self.Stamina:Restore(amount, source or "Unknown")
end

--[[
	添加持续效果（奔跑消耗、疲劳、兴奋等）
	@param name: 效果名称
	@param changePerSecond: 每秒变化量（负数为消耗，正数为恢复）
	@param duration: 持续时间（秒），nil 表示无限持续
	@return: 修改器 ID

	示例：
	- 奔跑：AddEffect("Running", -10, nil)  -- 每秒消耗10点，直到停止奔跑
	- 疲劳：AddEffect("Fatigue", -5, 20)  -- 每秒消耗5点，持续20秒
	- 兴奋：AddEffect("Energized", 15, 30)  -- 每秒恢复15点，持续30秒
]]
function StaminaComponent:AddEffect(name, changePerSecond, duration)
	if self.IsExhausted and changePerSecond < 0 then
		-- 精疲力竭时不能添加消耗效果
		return nil
	end

	-- 调用数据包的 AddModifier 方法
	return self.Stamina:AddModifier(name, changePerSecond, duration)
end

--[[
	移除持续效果（通过 ID）
	@param modifierId: 修改器 ID
	@return: 是否成功移除
]]
function StaminaComponent:RemoveEffect(modifierId)
	return self.Stamina:RemoveModifier(modifierId)
end

--[[
	移除持续效果（通过名称）
	@param name: 效果名称
	@return: 移除的数量

	示例：
	- 停止奔跑：RemoveEffect("Running")
]]
function StaminaComponent:RemoveEffectByName(name)
	return self.Stamina:RemoveModifierByName(name)
end

--[[
	清除所有持续效果
]]
function StaminaComponent:ClearAllEffects()
	self.Stamina:ClearAllModifiers()
end

--[[
	获取当前体力
	@return: 当前体力
]]
function StaminaComponent:GetCurrentStamina()
	return self.Stamina.CurrentValue
end

--[[
	获取最大体力
	@return: 最大体力
]]
function StaminaComponent:GetMaxStamina()
	return self.Stamina.MaxValue
end

--[[
	获取体力百分比
	@return: 体力百分比（0.0 - 1.0）
]]
function StaminaComponent:GetStaminaPercentage()
	if not self.Stamina then return 0 end
	return self.Stamina.CurrentValue / self.Stamina.MaxValue
end

--[[
	是否精疲力竭
	@return: true 表示精疲力竭，false 表示正常
]]
function StaminaComponent:IsExhaustedState()
	return self.IsExhausted
end

--[[
	订阅体力事件
	@param eventName: 事件名称（"Changed", "Consumed", "Restored", "Depleted"）
	@param callback: 回调函数
	@return: 监听器 ID

	示例：
	stamina:OnEvent("Changed", function(data)
		print("体力变化：", data.currentValue, "/", data.maxValue)
	end)
]]
function StaminaComponent:OnEvent(eventName, callback)
	local listenerId = self.Stamina:OnEvent(eventName, callback)
	if listenerId then
		table.insert(self._eventListeners, {event = eventName, id = listenerId})
	end
	return listenerId
end

-- ============================================================================
-- 内部方法
-- ============================================================================

--[[
	内部：体力耗尽处理
]]
function StaminaComponent:_onDepleted(data)
	self.IsExhausted = true

	-- 清除所有消耗型修改器（保留恢复型修改器）
	for id, modifier in pairs(self.Stamina.Modifiers) do
		if modifier.changePerSecond < 0 then
			self.Stamina:RemoveModifier(id)
		end
	end

	print(string.format("[StaminaComponent] %s 体力耗尽，进入精疲力竭状态",
		self.Entity.Name or tostring(self.Entity)))

	-- 触发耗尽回调
	if self.OnDepletedCallback then
		self.OnDepletedCallback(self.Entity, data)
	end

	-- 可以在这里添加通用的耗尽效果
	self:_triggerExhaustedEffects()
end

--[[
	内部：触发精疲力竭效果（可选）
]]
function StaminaComponent:_triggerExhaustedEffects()
	-- 可以在这里添加精疲力竭效果
	-- 玩家：喘气音效、屏幕效果
	-- NPC：减速、无法攻击
end

-- ============================================================================
-- 清理
-- ============================================================================

--[[
	清理组件
]]
function StaminaComponent:Cleanup()
	print(string.format("[StaminaComponent] 清理 %s 的体力组件",
		self.Entity.Name or tostring(self.Entity)))

	-- 取消所有事件订阅
	for _, listener in ipairs(self._eventListeners) do
		self.Stamina:OffEvent(listener.event, listener.id)
	end
	self._eventListeners = {}

	-- 清理数据包
	ClientEntityManager:CleanupAttribute(self.Entity, "Stamina")

	-- 清空引用
	self.Stamina = nil
	self.Entity = nil
	self.OnDepletedCallback = nil
	self.OnRestoredCallback = nil
end

return StaminaComponent
