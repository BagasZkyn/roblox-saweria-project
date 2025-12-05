--[[
    Saweria Donation Handler for Roblox
    Place this script in ServerScriptService
    
    Setup Instructions:
    1. Ganti WEBHOOK_URL dengan URL Vercel API kamu
    2. Ganti WEBHOOK_SECRET dengan secret yang sama di Vercel
    3. Pastikan HttpService sudah enabled di Game Settings
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- KONFIGURASI - GANTI INI!
local WEBHOOK_URL = "https://your-project.vercel.app/api/webhook/poll"
local WEBHOOK_SECRET = "your-secret-key-here-change-this" -- Harus sama dengan di Vercel
local POLL_INTERVAL = 5 -- Polling setiap 5 detik (jangan terlalu cepat!)

-- RemoteEvent untuk komunikasi dengan client
local donationEvent = Instance.new("RemoteEvent")
donationEvent.Name = "DonationNotification"
donationEvent.Parent = ReplicatedStorage

-- Rate limiting untuk mencegah spam
local lastPollTime = 0
local MIN_POLL_INTERVAL = 3 -- Minimum 3 detik antar poll

-- Cache untuk mencegah notifikasi duplicate
local processedDonations = {}
local MAX_CACHE_SIZE = 100

-- Fungsi untuk membersihkan cache lama
local function cleanupCache()
    local count = 0
    for _ in pairs(processedDonations) do
        count = count + 1
    end
    
    if count > MAX_CACHE_SIZE then
        -- Hapus setengah cache terlama
        local toRemove = {}
        local removed = 0
        for id, _ in pairs(processedDonations) do
            table.insert(toRemove, id)
            removed = removed + 1
            if removed >= MAX_CACHE_SIZE / 2 then
                break
            end
        end
        
        for _, id in ipairs(toRemove) do
            processedDonations[id] = nil
        end
    end
end

-- Fungsi untuk poll notifikasi dari API
local function pollDonations()
    local currentTime = tick()
    
    -- Rate limiting check
    if currentTime - lastPollTime < MIN_POLL_INTERVAL then
        return
    end
    
    lastPollTime = currentTime
    
    local success, response = pcall(function()
        return HttpService:RequestAsync({
            Url = WEBHOOK_URL,
            Method = "GET",
            Headers = {
                ["Content-Type"] = "application/json",
                ["X-Webhook-Secret"] = WEBHOOK_SECRET
            }
        })
    end)
    
    if not success then
        warn("Failed to poll donations:", response)
        return
    end
    
    if response.StatusCode ~= 200 then
        warn("Poll failed with status:", response.StatusCode, response.Body)
        return
    end
    
    local success, data = pcall(function()
        return HttpService:JSONDecode(response.Body)
    end)
    
    if not success then
        warn("Failed to parse response:", data)
        return
    end
    
    if data.success and data.notifications then
        for _, donation in ipairs(data.notifications) do
            -- Check duplicate
            if not processedDonations[donation.id] then
                processedDonations[donation.id] = true
                
                -- Format data untuk client
                local formattedDonation = {
                    id = donation.id,
                    donatorName = donation.donatorName,
                    amount = donation.amount,
                    message = donation.message,
                    timestamp = donation.timestamp,
                    verified = donation.verified
                }
                
                -- Kirim ke semua client
                donationEvent:FireAllClients(formattedDonation)
                
                -- Log untuk debug
                print(string.format(
                    "[Saweria] New donation: %s donated Rp%s - %s",
                    donation.donatorName,
                    formatCurrency(donation.amount),
                    donation.message
                ))
                
                -- Cleanup cache jika perlu
                cleanupCache()
            end
        end
    end
end

-- Fungsi untuk format currency
function formatCurrency(amount)
    local formatted = tostring(amount)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1.%2')
        if k == 0 then break end
    end
    return formatted
end

-- Health check
local function healthCheck()
    spawn(function()
        while wait(60) do -- Check setiap 1 menit
            local success, response = pcall(function()
                return HttpService:RequestAsync({
                    Url = WEBHOOK_URL:gsub("/poll", "/health"),
                    Method = "GET"
                })
            end)
            
            if success and response.StatusCode == 200 then
                print("[Saweria] Health check: OK")
            else
                warn("[Saweria] Health check failed!")
            end
        end
    end)
end

-- Main loop
local function startPolling()
    print("[Saweria] Donation handler started!")
    print("[Saweria] Polling from:", WEBHOOK_URL)
    
    -- Start health check
    healthCheck()
    
    -- Main polling loop
    while wait(POLL_INTERVAL) do
        local success, err = pcall(pollDonations)
        if not success then
            warn("[Saweria] Polling error:", err)
        end
    end
end

-- Fungsi untuk handle player join (optional - bisa kirim welcome message)
Players.PlayerAdded:Connect(function(player)
    -- Bisa kirim notifikasi sebelumnya ke player yang baru join
    -- atau welcome message
end)

-- Start the system
startPolling()
