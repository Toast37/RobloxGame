--[[
	============================================================================
	Attribute.lua - 数据包基类
	============================================================================

	功能：
	- 作为 LocalAttribute 和 MirrorAttribute 的基类
	- 定义基础接口和事件系统
	- SetValue 和 Update 作为空函数兜底

	子类：
	- LocalAttribute: 完整功能（服务器和客户端本地玩家）
	- MirrorAttribute: 阉割版（客户端其他玩家/NPC）

	============================================================================
]]

local Attribute = {}
Attribute.__index = Attribute  -- 使用 Metatable 实现方法共享

-- ============================================================================
-- 构造函数
-- ============================================================================

--[[
	创建新的数据包实例（基类）
	@param owner: 拥有者（Player 或 Character）
	@param name: 数据包名称（如 "Stamina", "Health"）
	@param config: 配置表
		- MaxValue: 最大值
		- CurrentValue: 当前值（可选，默认等于 MaxValue）
	@return: Attribute 实例
]]
function Attribute.new(owner, name, config)
	local self = setmetatable({}, Attribute)

	-- 基础数据
	self.Owner = owner
	self.Name = name
	self.MaxValue = config.MaxValue or 100
	self.CurrentValue = config.CurrentValue or self.MaxValue

	-- 事件系统
	self.EventListeners = {
		Changed = {},      -- 任何变化
		Consumed = {},     -- 消耗
		Restored = {},     -- 恢复
		Depleted = {},     -- 耗尽
	}

	return self
end

-- ============================================================================
-- 基础接口（空实现，由子类覆盖）
-- ============================================================================

--[[
	直接设置数值（空实现，由子类覆盖）
	@param value: 新值
]]
function Attribute:SetValue(value)
	-- 空实现，兜底函数
end

--[[
	更新修改器和自动恢复（空实现，由子类覆盖）
	@param deltaTime: 帧间隔时间
]]
function Attribute:Update(deltaTime)
	-- 空实现，兜底函数
end

--[[
	瞬间消耗数值（空实现，由子类覆盖）
	@param amount: 消耗量
	@param source: 来源标识（可选）
	@return: 是否成功
]]
function Attribute:Consume(amount, source)
	warn("[Attribute] Consume not implemented in base class")
	return false
end

--[[
	瞬间恢复数值（空实现，由子类覆盖）
	@param amount: 恢复量
	@param source: 来源标识（可选）
]]
function Attribute:Restore(amount, source)
	warn("[Attribute] Restore not implemented in base class")
end

-- ============================================================================
-- 事件系统（基类实现，所有子类共享）
-- ============================================================================

--[[
	订阅事件
	@param eventName: 事件名称（"Changed", "Consumed", "Restored", "Depleted"）
	@param callback: 回调函数
	@return: 监听器 ID
]]
function Attribute:OnEvent(eventName, callback)
	if not self.EventListeners[eventName] then
		warn("[Attribute] Unknown event:", eventName)
		return nil
	end

	if type(callback) ~= "function" then
		warn("[Attribute] Callback must be a function")
		return nil
	end

	local listenerId = tostring(tick()) .. "_" .. tostring(math.random(1000, 9999))
	self.EventListeners[eventName][listenerId] = callback

	return listenerId
end

--[[
	取消订阅事件
	@param eventName: 事件名称
	@param listenerId: 监听器 ID
]]
function Attribute:OffEvent(eventName, listenerId)
	if not self.EventListeners[eventName] then
		warn("[Attribute] Unknown event:", eventName)
		return
	end

	self.EventListeners[eventName][listenerId] = nil
end

--[[
	触发事件
	@param eventName: 事件名称
	@param data: 事件数据
]]
function Attribute:FireEvent(eventName, data)
	if not self.EventListeners[eventName] then return end

	for _, callback in pairs(self.EventListeners[eventName]) do
		local success, err = pcall(callback, data)
		if not success then
			warn("[Attribute] Error in event listener:", err)
		end
	end
end

-- ============================================================================
-- 清理
-- ============================================================================

--[[
	销毁数据包
]]
function Attribute:Destroy()
	self.EventListeners = {}
end

return Attribute


