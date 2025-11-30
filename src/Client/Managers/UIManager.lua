-- UIManager (模块脚本，放在 ReplicatedStorage 中)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local UIManager = {}
UIManager.UI_Cache = {} -- 用于缓存UI实例的表（键=元素名，值=元素对象）
UIManager.ScreenGuis = {} -- 缓存所有 ScreenGui 的表

-- 递归缓存所有 GuiObject
local function cacheGuiObjectRecursive(obj, cache)
	-- 只缓存 GuiObject 类型
	if obj:IsA("GuiObject") then
		-- 如果名字已存在，发出警告（可能有重名）
		if cache[obj.Name] then
			warn(string.format("UIManager: Duplicate UI name '%s' found. Using the latest one.", obj.Name))
		end
		-- 缓存当前对象
		cache[obj.Name] = obj
	end

	-- 递归处理所有子对象
	for _, child in ipairs(obj:GetChildren()) do
		cacheGuiObjectRecursive(child, cache)
	end
end

-- 缓存单个 ScreenGui 及其子元素
local function cacheScreenGui(self, screenGui)
	-- 缓存 ScreenGui 本身
	self.ScreenGuis[screenGui.Name] = screenGui
	self.UI_Cache[screenGui.Name] = screenGui

	-- 递归缓存所有子元素
	cacheGuiObjectRecursive(screenGui, self.UI_Cache)

	print(string.format("UIManager: Cached ScreenGui '%s' and its children", screenGui.Name))
end

-- 初始化模块，找到并缓存所有UI
function UIManager:Init()
	print("UIManager: Initializing...")

	-- 调试：打印 PlayerGui 下所有子对象
	print("UIManager: PlayerGui children:")
	for _, child in ipairs(PlayerGui:GetChildren()) do
		print(string.format("  - %s (ClassName: %s)", child.Name, child.ClassName))
	end

	-- 遍历 PlayerGui 下的所有 ScreenGui
	for _, screenGui in ipairs(PlayerGui:GetChildren()) do
		if screenGui:IsA("ScreenGui") then
			cacheScreenGui(self, screenGui)
		end
	end

	-- 监听新增的 ScreenGui（动态加载）
	PlayerGui.ChildAdded:Connect(function(child)
		if child:IsA("ScreenGui") then
			-- 等待子元素加载完成
			task.wait(0.1)
			cacheScreenGui(self, child)
			self:PrintCachedUIs()
		end
	end)

	-- 监听移除的 ScreenGui
	PlayerGui.ChildRemoved:Connect(function(child)
		if child:IsA("ScreenGui") and self.ScreenGuis[child.Name] then
			print(string.format("UIManager: Removed ScreenGui '%s' from cache", child.Name))
			self.ScreenGuis[child.Name] = nil
			-- 注意：不清理 UI_Cache 中的子元素，因为可能有重名
		end
	end)

	self:PrintCachedUIs()
end

-- 打印已缓存的UI信息
function UIManager:PrintCachedUIs()
	-- 打印缓存的UI数量
	local count = 0
	for _ in pairs(self.UI_Cache) do
		count = count + 1
	end
	print(string.format("UIManager: Cached %d UI elements.", count))

	-- 调试：打印所有缓存的UI名字
	if count > 0 then
		local names = {}
		for name in pairs(self.UI_Cache) do
			table.insert(names, name)
		end
		table.sort(names)
		print("UIManager: Cached UI names:", table.concat(names, ", "))
	end
end

--[[
	显示指定的UI元素（设置 Visible = true）

	@param uiName (string): 要显示的UI元素的名字
]]
function UIManager:ShowUI(uiName)
	local uiToShow = self.UI_Cache[uiName]
	if uiToShow then
		-- 如果是 ScreenGui，设置 Enabled
		if uiToShow:IsA("ScreenGui") then
			uiToShow.Enabled = true
			-- 如果是 GuiObject，设置 Visible
		elseif uiToShow:IsA("GuiObject") then
			uiToShow.Visible = true
		end
	else
		warn("UIManager:ShowUI - UI not found:", uiName)
		warn("Available UIs:", table.concat(self:GetCachedUINames(), ", "))
	end
end

--[[
	隐藏指定的UI元素（设置 Visible = false）

	@param uiName (string): 要隐藏的UI元素的名字
]]
function UIManager:HideUI(uiName)
	local uiToHide = self.UI_Cache[uiName]
	if uiToHide then
		-- 如果是 ScreenGui，设置 Enabled
		if uiToHide:IsA("ScreenGui") then
			uiToHide.Enabled = false
			-- 如果是 GuiObject，设置 Visible
		elseif uiToHide:IsA("GuiObject") then
			uiToHide.Visible = false
		end
	else
		warn("UIManager:HideUI - UI not found:", uiName)
		warn("Available UIs:", table.concat(self:GetCachedUINames(), ", "))
	end
end

--[[
	获取所有已缓存的UI名字列表

	@return (table): 所有UI名字的数组
]]
function UIManager:GetCachedUINames()
	local names = {}
	for name in pairs(self.UI_Cache) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

--[[
	检查UI是否存在于缓存中

	@param uiName (string): UI元素的名字
	@return (boolean): 是否存在
]]
function UIManager:HasUI(uiName)
	return self.UI_Cache[uiName] ~= nil
end

--[[
	获取UI对象引用

	@param uiName (string): UI元素的名字
	@return (Instance|nil): UI对象，如果不存在返回nil
]]
function UIManager:GetUI(uiName)
	local ui = self.UI_Cache[uiName]
	if not ui then
		warn("UIManager:GetUI - UI not found:", uiName)
	end
	return ui
end

--[[
	设置UI透明度

	@param uiName (string): 要设置透明度的UI的名字
	@param Alpha (number): 目标透明度值 (0 = 完全不透明, 1 = 完全透明)
	@param useTween (boolean, 可选): 是否平滑过渡，默认为true
	@param tweenDuration (number, 可选): 过渡时长（秒），默认为0.3
]]
function UIManager:SettingAlpha(uiName, Alpha, useTween, tweenDuration)
	-- 参数默认值
	useTween = (useTween == nil) and true or useTween
	tweenDuration = tweenDuration or 0.3
	Alpha = math.clamp(Alpha, 0, 1)

	local ui = self.UI_Cache[uiName]
	if not ui then
		warn("UIManager:SettingAlpha - UI not found:", uiName)
		return
	end

	-- 递归设置所有子元素的透明度
	local function setTransparencyRecursive(obj, targetAlpha, animate)
		-- 处理不同类型的GuiObject透明度属性
		if obj:IsA("GuiObject") then
			local properties = {}

			-- 背景透明度
			if obj:IsA("Frame") or obj:IsA("TextButton") or obj:IsA("TextLabel") or obj:IsA("ImageButton") then
				if obj.BackgroundTransparency ~= nil then
					properties.BackgroundTransparency = targetAlpha
				end
			end

			-- 图片透明度
			if obj:IsA("ImageButton") or obj:IsA("ImageLabel") then
				if obj.ImageTransparency ~= nil then
					properties.ImageTransparency = targetAlpha
				end
			end

			-- 文字透明度
			if obj:IsA("TextButton") or obj:IsA("TextLabel") or obj:IsA("TextBox") then
				if obj.TextTransparency ~= nil then
					properties.TextTransparency = targetAlpha
				end
				-- 文字描边透明度
				if obj.TextStrokeTransparency ~= nil then
					-- 保持描边相对透明度（通常比文字更透明）
					local strokeOffset = 0.5
					properties.TextStrokeTransparency = math.clamp(targetAlpha + strokeOffset, 0, 1)
				end
			end

			-- 应用透明度变化
			if next(properties) then
				if animate then
					-- 使用Tween平滑过渡
					local tween = TweenService:Create(
						obj,
						TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						properties
					)
					tween:Play()
				else
					-- 直接设置
					for prop, value in pairs(properties) do
						obj[prop] = value
					end
				end
			end
		end

		-- 递归处理所有子对象
		for _, child in ipairs(obj:GetChildren()) do
			setTransparencyRecursive(child, targetAlpha, animate)
		end
	end

	-- 开始递归设置透明度
	setTransparencyRecursive(ui, Alpha, useTween)
end

--[[
	移动UI到目标位置

	@param uiName (string): 要移动的UI元素的名字
	@param targetPosition (UDim2): 目标位置
	@param useTween (boolean, 可选): 是否使用平滑过渡，默认为true
	@param tweenDuration (number, 可选): 过渡时长（秒），默认为0.2
]]
function UIManager:MoveUI(uiName, targetPosition, useTween, tweenDuration)
	-- 参数默认值
	useTween = (useTween == nil) and true or useTween
	tweenDuration = tweenDuration or 0.2

	local ui = self.UI_Cache[uiName]
	if not ui then
		warn("UIManager:MoveUI - UI not found:", uiName)
		return
	end

	-- 检查UI是否有Position属性
	if not ui:IsA("GuiObject") then
		warn("UIManager:MoveUI - UI is not a GuiObject:", uiName)
		return
	end

	if useTween then
		-- 使用Tween平滑移动
		local tween = TweenService:Create(
			ui,
			TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Position = targetPosition}
		)
		tween:Play()
	else
		-- 直接设置位置
		ui.Position = targetPosition
	end
end


-- 延迟初始化，确保所有UI都已从StarterGui复制到PlayerGui
task.defer(function()
	UIManager:Init()
end)

return UIManager