--===================================
-- 获取组件
--===================================
local ReplicatedStorage = game.ReplicatedStorage
local PlayerManager = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("Managers"):WaitForChild("PlayerManager"))
local UIManager = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("Managers"):WaitForChild("UIManager"))

--===================================
-- 获取服务
--===================================
local TweenService = game:GetService("TweenService")

--===================================
-- 参数配置
--===================================
local staminaBar = script.Parent:WaitForChild("Stamina") -- 获取Stamina（显示的UI）
local staminaSize = staminaBar.Size -- 记录初始Stamina的尺寸
local eventListenerID -- 存储监听者ID

-- 体力条颜色配置
local LOW_STAMINA_THRESHOLD = 0.4 -- 低体力阈值
local lowStaminaColor = Color3.new(1, 1, 0) -- 低体力条颜色
local normalStaminaColor = Color3.new(1, 1, 1) -- 正常体力条颜色
local exhaustedStaminaColor = Color3.new(1, 0, 0) -- 筋疲力尽时体力条颜色

-- 体力条颜色动画配置
local colorTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local lowStaminaAnimation = TweenService:Create(staminaBar, colorTweenInfo, {BackgroundColor3 = lowStaminaColor})
local normalStaminaAnimation = TweenService:Create(staminaBar, colorTweenInfo, {BackgroundColor3 = normalStaminaColor})
local exhaustedStaminaAnimation = TweenService:Create(staminaBar, colorTweenInfo, {BackgroundColor3 = exhaustedStaminaColor})

-- 体力条透明度动画配置
local alphaTweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local fullStaminaAlpha = TweenService:Create(staminaBar, alphaTweenInfo, {BackgroundTransparency = 0.7})
local unfullStaminaAlpha = TweenService:Create(staminaBar, alphaTweenInfo, {BackgroundTransparency = 0})

--===================================
-- 初始化 & 销毁函数
--===================================

local function setupUI()
	-- 等待 PlayerManager.Stamina 初始化
	while not PlayerManager.Stamina do
		task.wait(0.1)
	end

	-- 订阅体力变化事件（使用新的 API）
	eventListenerID = PlayerManager.Stamina:OnEvent("Changed", function(data)
		-- 更新体力条尺寸
		local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local staminaChangeAnimation = TweenService:Create(
			staminaBar,
			tweenInfo,
			{Size = UDim2.new(data.percentage, 0, staminaSize.Y.Scale, 0)}
		)
		staminaChangeAnimation:Play()

		-- 更新体力条颜色
		if PlayerManager.IsExhausted then
			-- 精疲力竭状态：红色
			exhaustedStaminaAnimation:Play()
		elseif data.currentValue < data.maxValue * LOW_STAMINA_THRESHOLD then
			-- 低体力状态：黄色
			lowStaminaAnimation:Play()
		else
			-- 正常状态：白色
			normalStaminaAnimation:Play()
		end

		-- 更新体力条透明度
		if data.currentValue == data.maxValue then
			-- 满体力：半透明
			fullStaminaAlpha:Play()
		else
			-- 非满体力：不透明
			unfullStaminaAlpha:Play()
		end
	end)

	print("[StaminaUI] 已订阅体力变化事件")
end

local function cleanup()
	-- 取消订阅事件
	if PlayerManager.Stamina and eventListenerID then
		PlayerManager.Stamina:OffEvent("Changed", eventListenerID)
		print("[StaminaUI] 已取消体力变化事件订阅")
	end

	script:Destroy()
end

--===================================
-- 触发 & 连接
--===================================

setupUI()

staminaBar.Destroying:Connect(cleanup)
