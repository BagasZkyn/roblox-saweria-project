--[[
    Saweria Donation UI Client Script
    Place this LocalScript in StarterPlayer > StarterPlayerScripts
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Tunggu DonationNotification event
local donationEvent = ReplicatedStorage:WaitForChild("DonationNotification")

-- Queue untuk notifikasi
local notificationQueue = {}
local isShowingNotification = false

-- Warna tema Saweria
local COLORS = {
    primary = Color3.fromRGB(255, 87, 51), -- Orange-red Saweria
    secondary = Color3.fromRGB(255, 111, 80),
    background = Color3.fromRGB(26, 26, 31),
    backgroundLight = Color3.fromRGB(38, 38, 46),
    text = Color3.fromRGB(255, 255, 255),
    textSecondary = Color3.fromRGB(200, 200, 200),
    success = Color3.fromRGB(46, 213, 115),
    glow = Color3.fromRGB(255, 195, 18)
}

-- Fungsi untuk membuat UI
local function createUI()
    -- ScreenGui utama
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "SaweriaDonationUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = playerGui
    
    return screenGui
end

-- Fungsi untuk format rupiah
local function formatRupiah(amount)
    local formatted = tostring(amount)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1.%2')
        if k == 0 then break end
    end
    return "Rp" .. formatted
end

-- Fungsi untuk membuat notifikasi
local function createNotification(screenGui, donation)
    -- Container utama
    local container = Instance.new("Frame")
    container.Name = "DonationNotification"
    container.Size = UDim2.new(0, 450, 0, 0) -- Start dari 0 height
    container.Position = UDim2.new(1, -470, 0, 20) -- Start dari kanan atas
    container.AnchorPoint = Vector2.new(0, 0)
    container.BackgroundColor3 = COLORS.background
    container.BorderSizePixel = 0
    container.ClipsDescendants = true
    container.Parent = screenGui
    
    -- Corner radius
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = container
    
    -- Gradient border effect
    local borderGradient = Instance.new("UIGradient")
    borderGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, COLORS.primary),
        ColorSequenceKeypoint.new(0.5, COLORS.secondary),
        ColorSequenceKeypoint.new(1, COLORS.primary)
    }
    borderGradient.Rotation = 45
    borderGradient.Parent = container
    
    -- Stroke untuk border
    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.primary
    stroke.Thickness = 3
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = container
    
    -- Glow effect
    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.Size = UDim2.new(1, 30, 1, 30)
    shadow.Position = UDim2.new(0.5, 0, 0.5, 0)
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
    shadow.ImageColor3 = COLORS.primary
    shadow.ImageTransparency = 0.5
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(10, 10, 10, 10)
    shadow.ZIndex = 0
    shadow.Parent = container
    
    -- Header dengan icon
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 50)
    header.BackgroundColor3 = COLORS.primary
    header.BorderSizePixel = 0
    header.Parent = container
    
    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 12)
    headerCorner.Parent = header
    
    -- Fix corner bottom
    local headerFix = Instance.new("Frame")
    headerFix.Size = UDim2.new(1, 0, 0, 12)
    headerFix.Position = UDim2.new(0, 0, 1, -12)
    headerFix.BackgroundColor3 = COLORS.primary
    headerFix.BorderSizePixel = 0
    headerFix.Parent = header
    
    -- Icon Saweria (emoji heart/gift)
    local icon = Instance.new("TextLabel")
    icon.Size = UDim2.new(0, 40, 0, 40)
    icon.Position = UDim2.new(0, 10, 0.5, 0)
    icon.AnchorPoint = Vector2.new(0, 0.5)
    icon.BackgroundTransparency = 1
    icon.Text = "💝"
    icon.TextSize = 28
    icon.Font = Enum.Font.SourceSansBold
    icon.Parent = header
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -60, 1, 0)
    title.Position = UDim2.new(0, 55, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "NEW DONATION!"
    title.TextColor3 = COLORS.text
    title.TextSize = 20
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header
    
    -- Content area
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -20, 1, -60)
    content.Position = UDim2.new(0, 10, 0, 55)
    content.BackgroundTransparency = 1
    content.Parent = container
    
    -- Donator name
    local donatorName = Instance.new("TextLabel")
    donatorName.Size = UDim2.new(1, 0, 0, 30)
    donatorName.Position = UDim2.new(0, 0, 0, 5)
    donatorName.BackgroundTransparency = 1
    donatorName.Text = donation.donatorName
    donatorName.TextColor3 = COLORS.text
    donatorName.TextSize = 22
    donatorName.Font = Enum.Font.GothamBold
    donatorName.TextXAlignment = Enum.TextXAlignment.Left
    donatorName.TextTruncate = Enum.TextTruncate.AtEnd
    donatorName.Parent = content
    
    -- Amount dengan style keren
    local amountBg = Instance.new("Frame")
    amountBg.Size = UDim2.new(0, 0, 0, 35)
    amountBg.Position = UDim2.new(0, 0, 0, 40)
    amountBg.BackgroundColor3 = COLORS.success
    amountBg.BorderSizePixel = 0
    amountBg.Parent = content
    
    local amountCorner = Instance.new("UICorner")
    amountCorner.CornerRadius = UDim.new(0, 8)
    amountCorner.Parent = amountBg
    
    local amount = Instance.new("TextLabel")
    amount.Size = UDim2.new(1, -10, 1, 0)
    amount.Position = UDim2.new(0, 5, 0, 0)
    amount.BackgroundTransparency = 1
    amount.Text = formatRupiah(donation.amount)
    amount.TextColor3 = COLORS.text
    amount.TextSize = 24
    amount.Font = Enum.Font.GothamBold
    amount.TextXAlignment = Enum.TextXAlignment.Center
    amount.Parent = amountBg
    
    -- Ukuran amount background sesuai text
    local textSize = game:GetService("TextService"):GetTextSize(
        amount.Text,
        amount.TextSize,
        amount.Font,
        Vector2.new(1000, 35)
    )
    amountBg.Size = UDim2.new(0, textSize.X + 20, 0, 35)
    
    -- Message (jika ada)
    local messageY = 85
    if donation.message and donation.message ~= "" then
        local messageBg = Instance.new("Frame")
        messageBg.Size = UDim2.new(1, 0, 0, 0)
        messageBg.Position = UDim2.new(0, 0, 0, messageY)
        messageBg.BackgroundColor3 = COLORS.backgroundLight
        messageBg.BorderSizePixel = 0
        messageBg.AutomaticSize = Enum.AutomaticSize.Y
        messageBg.Parent = content
        
        local msgCorner = Instance.new("UICorner")
        msgCorner.CornerRadius = UDim.new(0, 8)
        msgCorner.Parent = messageBg
        
        local messagePadding = Instance.new("UIPadding")
        messagePadding.PaddingTop = UDim.new(0, 8)
        messagePadding.PaddingBottom = UDim.new(0, 8)
        messagePadding.PaddingLeft = UDim.new(0, 10)
        messagePadding.PaddingRight = UDim.new(0, 10)
        messagePadding.Parent = messageBg
        
        local message = Instance.new("TextLabel")
        message.Size = UDim2.new(1, 0, 0, 0)
        message.BackgroundTransparency = 1
        message.Text = '"' .. donation.message .. '"'
        message.TextColor3 = COLORS.textSecondary
        message.TextSize = 16
        message.Font = Enum.Font.Gotham
        message.TextXAlignment = Enum.TextXAlignment.Left
        message.TextYAlignment = Enum.TextYAlignment.Top
        message.TextWrapped = true
        message.AutomaticSize = Enum.AutomaticSize.Y
        message.Parent = messageBg
        
        messageY = messageY + messageBg.AbsoluteSize.Y + 10
    end
    
    -- Verified badge
    local verifiedBadge = Instance.new("Frame")
    verifiedBadge.Size = UDim2.new(0, 100, 0, 25)
    verifiedBadge.Position = UDim2.new(0, 0, 0, messageY)
    verifiedBadge.BackgroundColor3 = COLORS.backgroundLight
    verifiedBadge.BorderSizePixel = 0
    verifiedBadge.Parent = content
    
    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(0, 6)
    badgeCorner.Parent = verifiedBadge
    
    local badgeText = Instance.new("TextLabel")
    badgeText.Size = UDim2.new(1, 0, 1, 0)
    badgeText.BackgroundTransparency = 1
    badgeText.Text = "✓ Verified"
    badgeText.TextColor3 = COLORS.success
    badgeText.TextSize = 14
    badgeText.Font = Enum.Font.GothamBold
    badgeText.Parent = verifiedBadge
    
    -- Set final height
    local finalHeight = messageY + 35
    
    return container, finalHeight
end

-- Fungsi untuk play sound
local function playNotificationSound()
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://6026984224" -- Notification sound
    sound.Volume = 0.5
    sound.Parent = SoundService
    sound:Play()
    
    game:GetService("Debris"):AddItem(sound, 2)
end

-- Fungsi untuk show notifikasi dengan animasi
local function showNotification(donation)
    if isShowingNotification then
        table.insert(notificationQueue, donation)
        return
    end
    
    isShowingNotification = true
    
    local screenGui = playerGui:FindFirstChild("SaweriaDonationUI")
    if not screenGui then
        screenGui = createUI()
    end
    
    local notification, finalHeight = createNotification(screenGui, donation)
    
    -- Play sound
    playNotificationSound()
    
    -- Animasi slide in + expand
    local slideInTween = TweenService:Create(
        notification,
        TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = UDim2.new(1, -470, 0, 20)}
    )
    
    local expandTween = TweenService:Create(
        notification,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.new(0, 450, 0, finalHeight)}
    )
    
    expandTween:Play()
    slideInTween:Play()
    
    -- Pulse effect untuk border
    spawn(function()
        for i = 1, 3 do
            local stroke = notification:FindFirstChildOfClass("UIStroke")
            if stroke then
                local pulseTween = TweenService:Create(
                    stroke,
                    TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
                    {Thickness = 5}
                )
                pulseTween:Play()
                pulseTween.Completed:Wait()
                
                local reverseTween = TweenService:Create(
                    stroke,
                    TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
                    {Thickness = 3}
                )
                reverseTween:Play()
                reverseTween.Completed:Wait()
            end
            wait(0.1)
        end
    end)
    
    -- Tunggu 7 detik
    wait(7)
    
    -- Animasi slide out
    local slideOutTween = TweenService:Create(
        notification,
        TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In),
        {
            Position = UDim2.new(1, 20, 0, 20),
            Size = UDim2.new(0, 450, 0, 0)
        }
    )
    
    slideOutTween:Play()
    slideOutTween.Completed:Wait()
    
    notification:Destroy()
    
    isShowingNotification = false
    
    -- Process queue
    if #notificationQueue > 0 then
        local nextDonation = table.remove(notificationQueue, 1)
        showNotification(nextDonation)
    end
end

-- Listen untuk donation events
donationEvent.OnClientEvent:Connect(function(donation)
    showNotification(donation)
end)

print("[Saweria] Donation UI initialized!")
