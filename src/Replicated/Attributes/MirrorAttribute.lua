--[[
	============================================================================
	MirrorAttribute.lua - 镜像数据包（阉割版）
	============================================================================

	功能：
	- 继承自 Attribute 基类
	- 只有 SetValue 方法，用于接收服务器广播
	- 没有修改器系统、自动恢复、Consume、Restore 等功能
	- 避免客户端计算 NPC/其他玩家身上的数据包造成不必要的性能开销

	使用场景：
	- 客户端：其他玩家和 NPC 的数据包
	- 只在服务器发出数值更改的广播时才会进行数值更改

	使用方式：
	local MirrorAttribute = require(script.MirrorAttribute)
	local health = MirrorAttribute.new(npc, "Health", {
		MaxValue = 500,
		CurrentValue = 500
	})

	-- 接收服务器广播
	health:SetValue(450)

	============================================================================
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Attribute = require(ReplicatedStorage:WaitForChild("Replicated"):WaitForChild("Attributes"):WaitForChild("Attribute"))

local MirrorAttribute = setmetatable({}, {__index = Attribute})
MirrorAttribute.__index = MirrorAttribute

-- ============================================================================
-- 构造函数
-- ============================================================================

--[[
	创建新的镜像数据包实例
	@param owner: 拥有者（Player 或 Character）
	@param name: 数据包名称（如 "Stamina", "Health"）
	@param config: 配置表
		- MaxValue: 最大值
		- CurrentValue: 当前值（可选，默认等于 MaxValue）
	@return: MirrorAttribute 实例
]]
function MirrorAttribute.new(owner, name, config)
	-- 调用基类构造函数
	local self = Attribute.new(owner, name, config)
	setmetatable(self, MirrorAttribute)

	return self
end

-- ============================================================================
-- 核心方法（只覆盖 SetValue）
-- ============================================================================

--[[
	直接设置数值（用于接收服务器广播）
	@param value: 新值
]]
function MirrorAttribute:SetValue(value)
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
-- 不支持的方法（继承自基类的警告实现）
-- ============================================================================

-- Consume、Restore、Update 等方法已在基类中定义为警告实现
-- MirrorAttribute 不覆盖它们，因此调用会触发基类的警告

return MirrorAttribute
