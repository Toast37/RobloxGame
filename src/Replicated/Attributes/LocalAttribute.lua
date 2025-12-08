--[[
	============================================================================
	LocalAttribute.lua - 本地数据包（完整功能）
	============================================================================

	功能：
	- 继承自 Attribute 基类
	- 完整的数值管理（体力、生命值、魔法值等）
	- 修改器队列系统（持续增减）
	- 自动恢复机制
	- 事件系统（变化、消耗、恢复、耗尽等）

	使用场景：
	- 服务器端：所有玩家和 NPC 的数据包
	- 客户端：本地玩家的数据包（用于客户端预测）

	使用方式：
	local LocalAttribute = require(script.LocalAttribute)
	local stamina = LocalAttribute.new(player, "Stamina", {
		MaxValue = 100,
		CurrentValue = 100,
		RegenRate = 8,
		RegenCooldown = 1
	})

	============================================================================
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Attribute = require(ReplicatedStorage:WaitForChild("Replicated"):WaitForChild("Attributes"):WaitForChild("Attribute"))

local LocalAttribute = setmetatable({}, {__index = Attribute})
LocalAttribute.__index = LocalAttribute

-- ============================================================================
-- 构造函数
-- ============================================================================

--[[
	创建新的本地数据包实例
	@param owner: 拥有者（Player 或 Character）
	@param name: 数据包名称（如 "Stamina", "Health"）
	@param config: 配置表
		- MaxValue: 最大值
		- CurrentValue: 当前值（可选，默认等于 MaxValue）
		- RegenRate: 恢复速率（每秒，可选，默认 0）
		- RegenCooldown: 恢复冷却时间（秒，可选，默认 0）
	@return: LocalAttribute 实例
]]
function LocalAttribute.new(owner, name, config)
	-- 调用基类构造函数
	local self = Attribute.new(owner, name, config)
	setmetatable(self, LocalAttribute)

	-- LocalAttribute 特有的属性
	self.RegenRate = config.RegenRate or 0
	self.RegenCooldown = config.RegenCooldown or 0

	-- 修改器系统
	self.Modifiers = {}  -- { id = {name, func, changePerSecond, duration, startTime} }
	self.ModifierIdCounter = 0

	-- 自动恢复系统
	self.QueueEmptyTime = nil
	self.IsNaturalRegenActive = false

	-- 耗尽状态标记（防止重复触发 Depleted 事件）
	self.IsDepleted = false

	return self
end

-- ============================================================================
-- 核心方法（覆盖基类）
-- ============================================================================

--[[
	瞬间消耗数值
	@param amount: 消耗量
	@param source: 来源标识（可选，用于事件追踪）
	@return: 是否成功
]]
function LocalAttribute:Consume(amount, source)
	if amount < 0 then
		warn("[LocalAttribute] Consume amount must be positive, got", amount)
		return false
	end

	if self.CurrentValue < amount then
		return false
	end

	local previousValue = self.CurrentValue
	self.CurrentValue = self.CurrentValue - amount

	-- 重置自动恢复冷却
	self.QueueEmptyTime = nil
	self.IsNaturalRegenActive = false

	-- 触发事件
	self:FireEvent("Consumed", {
		currentValue = self.CurrentValue,
		previousValue = previousValue,
		amount = amount,
		maxValue = self.MaxValue,
		percentage = self.CurrentValue / self.MaxValue,
		source = source or "Unknown"
	})

	self:FireEvent("Changed", {
		currentValue = self.CurrentValue,
		previousValue = previousValue,
		change = -amount,
		maxValue = self.MaxValue,
		percentage = self.CurrentValue / self.MaxValue
	})

	-- 检查是否耗尽（只在第一次触发）
	if self.CurrentValue <= 0 and not self.IsDepleted then
		self.IsDepleted = true
		self:FireEvent("Depleted", {
			currentValue = 0,
			maxValue = self.MaxValue
		})
	end

	return true
end

--[[
	瞬间恢复数值
	@param amount: 恢复量
	@param source: 来源标识（可选）
]]
function LocalAttribute:Restore(amount, source)
	if amount < 0 then
		warn("[LocalAttribute] Restore amount must be positive, got", amount)
		return
	end

	local previousValue = self.CurrentValue
	self.CurrentValue = math.min(self.CurrentValue + amount, self.MaxValue)

	local actualRestore = self.CurrentValue - previousValue

	if actualRestore > 0 then
		-- 恢复后重置耗尽标记
		if self.CurrentValue > 0 and self.IsDepleted then
			self.IsDepleted = false
		end

		self:FireEvent("Restored", {
			currentValue = self.CurrentValue,
			previousValue = previousValue,
			amount = actualRestore,
			maxValue = self.MaxValue,
			percentage = self.CurrentValue / self.MaxValue,
			source = source or "Unknown"
		})

		self:FireEvent("Changed", {
			currentValue = self.CurrentValue,
			previousValue = previousValue,
			change = actualRestore,
			maxValue = self.MaxValue,
			percentage = self.CurrentValue / self.MaxValue
		})
	end
end

--[[
	直接设置数值（用于服务器强制同步）
	@param value: 新值
]]
function LocalAttribute:SetValue(value)
	local previousValue = self.CurrentValue
	self.CurrentValue = math.clamp(value, 0, self.MaxValue)

	if self.CurrentValue ~= previousValue then
		self:FireEvent("Changed", {
			currentValue = self.CurrentValue,
			previousValue = previousValue,
			change = self.CurrentValue - previousValue,
			maxValue = self.MaxValue,
			percentage = self.CurrentValue / self.MaxValue
		})
	end
end

-- ============================================================================
-- 修改器系统
-- ============================================================================

--[[
	添加数值修改器（持续增减）
	@param name: 修改器名称
	@param changePerSecond: 每秒变化量（正数为恢复，负数为消耗）
	@param duration: 持续时间（秒），nil 表示无限持续
	@return: 修改器 ID
]]
function LocalAttribute:AddModifier(name, changePerSecond, duration)
	self.ModifierIdCounter = self.ModifierIdCounter + 1
	local modifierId = self.ModifierIdCounter

	local startTime = tick()

	local modifierFunc = function(deltaTime)
		local previousValue = self.CurrentValue
		local change = changePerSecond * deltaTime
		self.CurrentValue = math.clamp(
			self.CurrentValue + change,
			0,
			self.MaxValue
		)

		local actualChange = self.CurrentValue - previousValue
		if actualChange ~= 0 then
			if actualChange < 0 then
				self:FireEvent("Consumed", {
					currentValue = self.CurrentValue,
					previousValue = previousValue,
					amount = -actualChange,
					maxValue = self.MaxValue,
					percentage = self.CurrentValue / self.MaxValue,
					source = name
				})
			else
				self:FireEvent("Restored", {
					currentValue = self.CurrentValue,
					previousValue = previousValue,
					amount = actualChange,
					maxValue = self.MaxValue,
					percentage = self.CurrentValue / self.MaxValue,
					source = name
				})
			end

			self:FireEvent("Changed", {
				currentValue = self.CurrentValue,
				previousValue = previousValue,
				change = actualChange,
				maxValue = self.MaxValue,
				percentage = self.CurrentValue / self.MaxValue
			})
		end

		-- 检查是否超过持续时间
		if duration then
			local elapsed = tick() - startTime
			if elapsed >= duration then
				return false
			end
		end

		return true
	end

	self.Modifiers[modifierId] = {
		id = modifierId,
		name = name,
		func = modifierFunc,
		changePerSecond = changePerSecond,
		duration = duration,
		startTime = startTime,
	}

	return modifierId
end

--[[
	移除修改器（通过 ID）
	@param modifierId: 修改器 ID
]]
function LocalAttribute:RemoveModifier(modifierId)
	if self.Modifiers[modifierId] then
		self.Modifiers[modifierId] = nil
		return true
	end
	return false
end

--[[
	移除修改器（通过名称）
	@param name: 修改器名称
	@return: 移除的数量
]]
function LocalAttribute:RemoveModifierByName(name)
	local removedCount = 0
	for id, modifier in pairs(self.Modifiers) do
		if modifier.name == name then
			self.Modifiers[id] = nil
			removedCount = removedCount + 1
		end
	end
	return removedCount
end

--[[
	清除所有修改器
]]
function LocalAttribute:ClearAllModifiers()
	self.Modifiers = {}
	self.QueueEmptyTime = nil
	self.IsNaturalRegenActive = false
end

-- ============================================================================
-- 更新系统（需要外部每帧调用）
-- ============================================================================

--[[
	更新修改器和自动恢复
	@param deltaTime: 帧间隔时间
]]
function LocalAttribute:Update(deltaTime)
	-- 执行所有修改器
	local hasActiveModifiers = false
	local modifiersToRemove = {}

	for id, modifier in pairs(self.Modifiers) do
		hasActiveModifiers = true
		local shouldContinue = modifier.func(deltaTime)
		if shouldContinue == false then
			table.insert(modifiersToRemove, id)
		end
	end

	-- 移除已完成的修改器
	for _, id in ipairs(modifiersToRemove) do
		self.Modifiers[id] = nil
	end

	-- 检测队列空窗时间
	if not hasActiveModifiers then
		if self.QueueEmptyTime == nil then
			self.QueueEmptyTime = tick()
			self.IsNaturalRegenActive = false
		else
			local emptyDuration = tick() - self.QueueEmptyTime
			if emptyDuration >= self.RegenCooldown then
				self.IsNaturalRegenActive = true
			end
		end
	else
		self.QueueEmptyTime = nil
		self.IsNaturalRegenActive = false
	end

	-- 自然恢复
	if self.IsNaturalRegenActive and self.RegenRate > 0 then
		local previousValue = self.CurrentValue
		local regenAmount = self.RegenRate * deltaTime
		self.CurrentValue = math.min(self.MaxValue, self.CurrentValue + regenAmount)

		if self.CurrentValue > previousValue then
			local actualRegen = self.CurrentValue - previousValue
			self:FireEvent("Restored", {
				currentValue = self.CurrentValue,
				previousValue = previousValue,
				amount = actualRegen,
				maxValue = self.MaxValue,
				percentage = self.CurrentValue / self.MaxValue,
				source = "NaturalRegen"
			})

			self:FireEvent("Changed", {
				currentValue = self.CurrentValue,
				previousValue = previousValue,
				change = actualRegen,
				maxValue = self.MaxValue,
				percentage = self.CurrentValue / self.MaxValue
			})
		end
	end

	-- 检查耗尽（只在第一次触发）
	if self.CurrentValue <= 0 and not self.IsDepleted then
		self.IsDepleted = true
		self:FireEvent("Depleted", {
			currentValue = 0,
			maxValue = self.MaxValue
		})
	elseif self.CurrentValue > 0 and self.IsDepleted then
		-- 恢复后重置耗尽标记
		self.IsDepleted = false
	end
end

-- ============================================================================
-- 清理
-- ============================================================================

--[[
	销毁数据包
]]
function LocalAttribute:Destroy()
	self:ClearAllModifiers()
	self.EventListeners = {}
end

return LocalAttribute
