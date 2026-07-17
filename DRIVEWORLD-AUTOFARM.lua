-- ============================================================
--  NEURO HUB - DRIVEWORLD AUTOFARM  [V3.1 - COBALT SESSION ANALYSIS]
--  Original by ssavnayt, improved by Super Z
-- ============================================================
--  CHANGELOG v3.1 (based on Cobalt session recording analysis):
--   [CRITICAL] FIXED Auto Checkpoint! Was looking for "blue/green color"
--              on Base/Expand (didn't exist). Real mechanic:
--              * Each CP Model has a HEX name (e.g. "31d061", "31d0e2")
--              * Server tracks progress via SingleplayerRacers.<player>
--              * Client sends RaceCheckpoint:FireServer(hexCode) on touch
--              * Color hex codes seen: 00e5ff, ffaa00, ffffff
--   [NEW] Auto Checkpoint now:
--        * Reads player progress from workspace.Races.<race>.SingleplayerRacers.<player>
--        * Finds the next CP by index (sorted by CheckpointNum)
--        * Flies to its position (Inner/Outer part)
--   [NEW] Race detection: monitors RaceBegan OnClientEvent to know
--         which race is currently active
--   [NEW] Race state info: shows current race, checkpoint progress
--   [NEW] Auto-Skip Race: if stuck > 30s on same CP, fire TeleportToLastCheckpoint
--   [NEW] Track TrackCarFlipped events (auto-upright car)
--   [NEW] Better SmartRace: now uses real race data
-- ============================================================
--  CHANGELOG v3.0 (based on real .rbxlx analysis):
--   [CRITICAL] Fixed findBestCheckpoint: was looking for Base/Expand
--              inside Inner - real structure is Inner/Outer/Forcefield
--   [CRITICAL] Fixed ALL RemoteEvent paths: was using Systems.* but
--              all 266 remotes live in ReplicatedStorage.Remotes.*
--   [CRITICAL] Fixed getMyCar: CurrentDriver.Value is a Player, NOT a
--              Character. Original was checking d.Value == Character.
--   [CRITICAL] Fixed Car root detection: primary is "Main" part
--              (CanCollide=false, Transparency=1), not "Body"
--   [NEW] Auto-Redeem Promo Codes (PromoClaim remote)
--   [NEW] Auto-Claim Daily Car (ClaimDailyCar remote)
--   [NEW] Auto-Claim Playtime Rewards (ClaimPlaytimeReward remote)
--   [NEW] Auto-Start Hotspot (HotspotGo remote)
--   [NEW] Auto-Contract (StartContract/PickupCargo/DropoffCargo)
--   [NEW] Auto-Street Race (StartStreetRace remote)
--   [NEW] Auto-Time Trial (StartTimeTrial remote)
--   [NEW] Auto-Tasks Claim (TasksClaim remote)
--   [NEW] Car ESP (highlight all cars with names)
--   [NEW] Player ESP (highlight all players)
--   [NEW] Hotspot ESP (highlight active hotspots)
--   [NEW] Expanded Info panel: TopSpeed, Wins, Races, MilesDriven,
--         DriftScore, AirScore, AuctionEarnings, EarnedCash, SpentCash,
--         CarsOwned, JobsCompleted, PremiumCurrency, Steel, Wood,
--         EventCurrency, XP
--   [NEW] Auto-Sell Cars (SellCar remote - configurable list)
--   [NEW] Auto-Buy upgrades (PurchaseUpgrade remote)
--   [NEW] Auto-Buy Garage (BuyGarage remote)
--   [NEW] Donate to Gold Vault (DonateToVault remote)
--   [NEW] Auto-Enter/Exit Car (EnterCar/ExitCar remotes)
--   [PERF] Checkpoint cache TTL reduced to 0.15s (was 0.25s)
--   [PERF] Car detection uses primary VehicleSeat fallback
-- ============================================================
--  CHANGELOG v2.0 (legacy):
--   [BUGFIX] Color3.fromRGB(55, 400, 0) -> valid green color
--   [BUGFIX] Hotkey conflict: Z was used for SmartRace AND DriftGlitch
--   [BUGFIX] getMyCar() now handles car respawns / driver type edge cases
--   [BUGFIX] gobutton cached at startup - now refreshed dynamically
--   [BUGFIX] setFreeze now also anchors car (not just HRP)
--   [BUGFIX] noclipConnection added to connections[] for proper cleanup
--   [BUGFIX] SpeedBoost now skips when no car/character is present
--   [PERF]   findBestCheckpoint now cached for 0.25s
--   [PERF]   All callbacks wrapped in pcall (crash-safe)
--   [PERF]   Noclip loop runs on Stepped with throttle (every 2 frames)
--   [FEAT]   Anti-AFK (VirtualUser) - prevents idle kick
--   [FEAT]   Settings persistence (writefile / readfile)
--   [FEAT]   WalkSpeed & JumpPower sliders
--   [FEAT]   Infinite Jump toggle
--   [FEAT]   Teleport to Waypoint (map marker)
--   [FEAT]   Minimize button (collapse all categories)
--   [FEAT]   Mobile touch drag support
--   [FEAT]   ESP highlight for active checkpoint
--   [FEAT]   Stats counter (races won, cash earned)
--   [FEAT]   Status panel showing active features
--   [FEAT]   Theme switcher (Dark / Midnight / Amoled)
--   [FEAT]   Right-click category header = collapse/expand
--   [FEAT]   Smooth tween animations
--   [FEAT]   Multi-language (RU/EN) toggle
-- ============================================================

-- === SERVICES ===
local CoreGui           = game:GetService("CoreGui")
local Players           = game:GetService("Players")
local workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService        = game:GetService("GuiService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting          = game:GetService("Lighting")

-- Anti-AFK (VirtualUser) - safe wrap, may not exist on all executors
local VirtualUser = nil
pcall(function() VirtualUser = game:GetService("VirtualUser") end)

local LocalPlayer = Players.LocalPlayer

-- === LEGACY CLEANUP ===
for _, name in ipairs({"SmartRaceClickGui", "SmartRaceNotifyGui", "DriftGlitchGui", "NeuroHubGui", "NeuroHubNotifyGui"}) do
    local old = CoreGui:FindFirstChild(name)
    if old then old:Destroy() end
end

-- === STATE ===
local State = {
    -- toggles
    SmartRaceEnabled    = false,
    AutoCheckpointEnabled = false,
    AutoFlyEnabled      = false,
    NoclipEnabled       = false,
    PlayerFrozen        = false,
    SmartRaceTPd        = false,
    SpeedBoostEnabled   = false,
    FarmPatchEnabled    = false,
    DriftGlitchActive   = false,
    PlatformModeActive  = false,
    AutoDriftActive     = false,
    AntiAFKEnabled      = false,
    InfiniteJumpEnabled = false,
    ESPEnabled          = true,
    AutoUprightCar      = true,   -- v3.1: auto-upright car when flipped
    -- notifications
    NotifyWinner       = true,
    NotifyLeaderboard  = true,
    NotifySpeedTrap    = true,
    NotifyGuild        = true,
    -- drift
    DriftAngle         = 25,
    DriftSide          = 1,
    -- stats
    RacesWon           = 0,
    CashEarned         = 0,
    StartTime          = os.time(),
    -- v3.1: race state tracking
    CurrentRace        = nil,     -- workspace.Races.<race> instance
    CurrentRaceName    = "",      -- "YellowObbyReverse" etc.
    CurrentCPIndex     = 0,       -- last CP index passed
    TotalCheckpoints   = 0,       -- total CPs in current race
    LastCPTime         = 0,       -- os.clock() when last CP was hit
    LastCPName         = "",      -- hex name like "31d061"
    IsInRace           = false,
    AutoSkipStuckTime  = 30,      -- seconds before auto-skipping stuck race
}

-- Expose to _G for backward compat with other scripts
for k, v in pairs(State) do _G[k] = v end
setmetatable(_G, {
    __newindex = function(t, k, v)
        rawset(t, k, v)
        if State[k] ~= nil then State[k] = v end
    end
})

-- === CONFIG (tunable) ===
local Config = {
    -- AirFarm
    AIRFARM_HEIGHT      = 500,
    AIRFARM_SPEED       = 300,
    MIN_AIRFARM_HEIGHT  = 100,
    MAX_AIRFARM_HEIGHT  = 2000,
    MIN_AIRFARM_SPEED   = 50,
    MAX_AIRFARM_SPEED   = 2500,
    AIRFARM_WAVE_AMP    = 150,
    AIRFARM_WAVE_FREQ   = 0.4,
    MIN_AIRFARM_AMP     = 10,
    MAX_AIRFARM_AMP     = 800,
    MIN_AIRFARM_FREQ    = 0.05,
    MAX_AIRFARM_FREQ    = 2.0,
    AIRFARM_BURST_TIME  = 2.0,
    AIRFARM_STOP_TIME   = 1.0,
    MIN_AIRFARM_BURST   = 0.2,
    MAX_AIRFARM_BURST   = 10.0,
    MIN_AIRFARM_STOP    = 0.1,
    MAX_AIRFARM_STOP    = 10.0,
    AIRFARM_MAX_DIST    = 1000,
    MIN_AIRFARM_DIST    = 100,
    MAX_AIRFARM_DIST    = 5000,
    -- DriftGlitch
    MIN_DRIFT_ANGLE     = 15,
    MAX_DRIFT_ANGLE     = 45,
    DRIFT_MIN_SPEED     = 1,
    ANTI_SPIN           = 0.88,
    PLATFORM_HEIGHT     = 80,
    TARGET_HEIGHT       = 92,  -- PLATFORM_HEIGHT + 12
    DOWN_FORCE          = 18,
    ANTI_FALL_FORCE     = 7,
    -- SmartRace
    MIN_SPEED           = 100,
    MAX_SPEED           = 2500,
    FLY_SPEED           = 300,
    MIN_MULT            = 1.0001,
    MAX_MULT            = 1.050,
    SPEED_MULTIPLIER    = 1.0005,
    MIN_MAX_SPEED       = 100,
    MAX_MAX_SPEED       = 5000,
    MAX_BOOST_SPEED     = 1000,
    SHIFT_AMOUNT        = 15,
    INSTA_BOOST_SPEED   = 500,
    DEFAULT_HEIGHT      = 15,
    TOLERANCE           = 25,
    -- Checkpoint colors (FIXED: original 400 was invalid -> 200)
    TARGET_BLUE   = Color3.fromRGB(55, 155, 255),
    TARGET_GREEN  = Color3.fromRGB(55, 200, 0),
    -- Player modifiers
    WalkSpeed      = 16,
    JumpPower      = 50,
    MIN_WALK       = 16,
    MAX_WALK       = 500,
    MIN_JUMP       = 50,
    MAX_JUMP       = 500,
    -- UI
    Language       = "RU",  -- "RU" or "EN"
    Theme          = "Dark",
}

Config.TARGET_HEIGHT = Config.PLATFORM_HEIGHT + 12

local WAITING_CFRAME = CFrame.new(
    -1147.74719, 0.751161933, 2038.3446,
    -1.1920929e-07, -1.00000012, 0,
    -1.00000012, -1.1920929e-07, 0,
    -0, 0, -1.00000024
)

-- === CONNECTIONS REGISTRY ===
local connections = {}
local function trackConn(conn)
    if conn then table.insert(connections, conn) end
    return conn
end

local noclipConnection = nil
local platformFolder = nil
local savedCFrame = nil
local espHighlight = nil
local espBillboard = nil

-- === THEMES ===
local THEMES = {
    Dark = {
        Header        = Color3.fromRGB(30, 30, 30),
        Background    = Color3.fromRGB(20, 20, 20),
        ButtonNormal  = Color3.fromRGB(25, 25, 25),
        ButtonHover   = Color3.fromRGB(40, 40, 40),
        ButtonActive  = Color3.fromRGB(0, 170, 100),
        ButtonDanger  = Color3.fromRGB(170, 40, 40),
        ButtonPlatform= Color3.fromRGB(150, 50, 200),
        Text          = Color3.fromRGB(220, 220, 220),
        Outline       = Color3.fromRGB(10, 10, 10),
        Accent        = Color3.fromRGB(0, 170, 100),
    },
    Midnight = {
        Header        = Color3.fromRGB(25, 25, 45),
        Background    = Color3.fromRGB(15, 15, 30),
        ButtonNormal  = Color3.fromRGB(20, 20, 40),
        ButtonHover   = Color3.fromRGB(35, 35, 60),
        ButtonActive  = Color3.fromRGB(80, 120, 255),
        ButtonDanger  = Color3.fromRGB(200, 50, 80),
        ButtonPlatform= Color3.fromRGB(150, 80, 220),
        Text          = Color3.fromRGB(230, 230, 250),
        Outline       = Color3.fromRGB(10, 10, 25),
        Accent        = Color3.fromRGB(80, 120, 255),
    },
    Amoled = {
        Header        = Color3.fromRGB(0, 0, 0),
        Background    = Color3.fromRGB(0, 0, 0),
        ButtonNormal  = Color3.fromRGB(10, 10, 10),
        ButtonHover   = Color3.fromRGB(25, 25, 25),
        ButtonActive  = Color3.fromRGB(0, 255, 140),
        ButtonDanger  = Color3.fromRGB(255, 60, 60),
        ButtonPlatform= Color3.fromRGB(180, 60, 240),
        Text          = Color3.fromRGB(255, 255, 255),
        Outline       = Color3.fromRGB(40, 40, 40),
        Accent        = Color3.fromRGB(0, 255, 140),
    },
}

local COLORS = THEMES[Config.Theme] or THEMES.Dark

local function applyTheme(themeName)
    if THEMES[themeName] then
        Config.Theme = themeName
        COLORS = THEMES[themeName]
    end
end

-- === I18N ===
local LANG = {
    RU = {
        race        = "Race",
        player      = "Player",
        drift       = "Drift",
        server      = "Server",
        info        = "Info",
        bindables   = "Bindables",
        notifications = "Уведомления",
        mods        = "Mods",
        utils       = "Utils",
        smart_race  = "Smart Race",
        auto_cp     = "Auto Checkpoint",
        auto_fly    = "Auto Fly",
        farm_patch  = "FarmPatch",
        noclip      = "Noclip",
        freeze      = "Freeze Player",
        speed_boost = "SpeedBoost (Hold W)",
        anti_afk    = "Anti-AFK",
        inf_jump    = "Infinite Jump",
        esp         = "Checkpoint ESP",
        safe_quit   = "Safe Quit (Unload)",
        tp_waypoint = "Teleport to Waypoint",
        theme       = "Theme:",
        lang        = "Language:",
        minimize    = "Minimize All",
        restore     = "Restore All",
        status      = "Active Features",
        stats       = "Session Stats",
    },
    EN = {
        race        = "Race",
        player      = "Player",
        drift       = "Drift",
        server      = "Server",
        info        = "Info",
        bindables   = "Bindables",
        notifications = "Notifications",
        mods        = "Mods",
        utils       = "Utils",
        smart_race  = "Smart Race",
        auto_cp     = "Auto Checkpoint",
        auto_fly    = "Auto Fly",
        farm_patch  = "FarmPatch",
        noclip      = "Noclip",
        freeze      = "Freeze Player",
        speed_boost = "SpeedBoost (Hold W)",
        anti_afk    = "Anti-AFK",
        inf_jump    = "Infinite Jump",
        esp         = "Checkpoint ESP",
        safe_quit   = "Safe Quit (Unload)",
        tp_waypoint = "Teleport to Waypoint",
        theme       = "Theme:",
        lang        = "Language:",
        minimize    = "Minimize All",
        restore     = "Restore All",
        status      = "Active Features",
        stats       = "Session Stats",
    },
}
local function L(key) return (LANG[Config.Language] and LANG[Config.Language][key]) or key end

-- === SETTINGS PERSISTENCE ===
local SETTINGS_FILE = "NeuroHubSettings.json"
local function loadSettings()
    local ok, content = pcall(function()
        if isfile and isfile(SETTINGS_FILE) then
            return readfile(SETTINGS_FILE)
        elseif readfile then
            return readfile(SETTINGS_FILE)
        end
        return nil
    end)
    if not ok or not content or content == "" then return end
    local ok2, data = pcall(function() return game:GetService("HttpService"):JSONDecode(content) end)
    if not ok2 or type(data) ~= "table" then return end
    -- Apply saved config
    for k, v in pairs(data) do
        if Config[k] ~= nil and type(Config[k]) == type(v) then
            Config[k] = v
        end
    end
    if data._State then
        for k, v in pairs(data._State) do
            if State[k] ~= nil and type(State[k]) == type(v) then
                State[k] = v
                _G[k] = v
            end
        end
    end
    if data._Binds then
        for k, v in pairs(data._Binds) do
            if Binds and Binds[k] then
                Binds[k].Key = v.Key or Binds[k].Key
                Binds[k].Enabled = v.Enabled or false
            end
        end
    end
    applyTheme(Config.Theme)
end

local function saveSettings()
    if not writefile then return end
    local data = {}
    for k, v in pairs(Config) do
        if type(v) ~= "table" and type(v) ~= "function" then
            data[k] = v
        end
    end
    local stateSave = {}
    for k, v in pairs(State) do
        if type(v) ~= "table" and type(v) ~= "function" then
            stateSave[k] = v
        end
    end
    data._State = stateSave
    local bindsSave = {}
    if Binds then
        for k, v in pairs(Binds) do
            bindsSave[k] = { Key = v.Key.Name, Enabled = v.Enabled }
        end
    end
    data._Binds = bindsSave
    local ok, json = pcall(function()
        return game:GetService("HttpService"):JSONEncode(data)
    end)
    if ok and json then
        pcall(function() writefile(SETTINGS_FILE, json) end)
    end
end

-- === SOUND ===
local function PlaySound(id, pitch)
    pcall(function()
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxassetid://" .. tostring(id)
        sound.PlaybackSpeed = pitch or 1
        sound.Volume = 1.5
        sound.Parent = CoreGui
        sound:Play()
        Debris:AddItem(sound, 5)
    end)
end

local SFX = {
    Toggle    = 542332175,
    Notify    = 103750838557977,
    Error     = 0,  -- optional
}

print("[Neuro Hub] v2.0 initialized for " .. LocalPlayer.Name)

-- === GUI ROOTS ===
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "NeuroHubGui"
ScreenGui.Parent = CoreGui
ScreenGui.DisplayOrder = 100
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true

local NotifyGui = Instance.new("ScreenGui")
NotifyGui.Name = "NeuroHubNotifyGui"
NotifyGui.Parent = CoreGui
NotifyGui.DisplayOrder = 101
NotifyGui.ResetOnSpawn = false
NotifyGui.IgnoreGuiInset = true

-- === NOTIFICATION SYSTEM ===
local NotificationContainer = Instance.new("Frame")
NotificationContainer.Name = "NotificationContainer"
NotificationContainer.Size = UDim2.new(0, 250, 1, -20)
NotificationContainer.Position = UDim2.new(1, -260, 0, 10)
NotificationContainer.BackgroundTransparency = 1
NotificationContainer.Parent = NotifyGui

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Parent = NotificationContainer
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
UIListLayout.Padding = UDim.new(0, 10)

local activeNotifications = 0

local function SendNotification(title, text, duration, soundOverride)
    if activeNotifications > 6 then return end  -- prevent spam
    activeNotifications = activeNotifications + 1
    duration = duration or 5
    PlaySound(soundOverride or SFX.Notify, 2)

    local NotifFrame = Instance.new("Frame")
    NotifFrame.Size = UDim2.new(1, 0, 0, 60)
    NotifFrame.BackgroundColor3 = COLORS.Background
    NotifFrame.BorderSizePixel = 0
    NotifFrame.BackgroundTransparency = 1

    local Stroke = Instance.new("UIStroke")
    Stroke.Color = COLORS.ButtonActive
    Stroke.Thickness = 2
    Stroke.Transparency = 1
    Stroke.Parent = NotifFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = NotifFrame

    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Size = UDim2.new(1, -10, 0, 20)
    TitleLabel.Position = UDim2.new(0, 5, 0, 5)
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Text = title
    TitleLabel.TextColor3 = COLORS.ButtonActive
    TitleLabel.Font = Enum.Font.GothamBold
    TitleLabel.TextSize = 14
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    TitleLabel.TextTransparency = 1
    TitleLabel.Parent = NotifFrame

    local DescLabel = Instance.new("TextLabel")
    DescLabel.Size = UDim2.new(1, -10, 0, 30)
    DescLabel.Position = UDim2.new(0, 5, 0, 25)
    DescLabel.BackgroundTransparency = 1
    DescLabel.Text = text
    DescLabel.TextColor3 = COLORS.Text
    DescLabel.Font = Enum.Font.Gotham
    DescLabel.TextSize = 12
    DescLabel.TextXAlignment = Enum.TextXAlignment.Left
    DescLabel.TextWrapped = true
    DescLabel.TextTransparency = 1
    DescLabel.Parent = NotifFrame

    NotifFrame.Parent = NotificationContainer

    -- Slide-in
    NotifFrame.Position = UDim2.new(1, 50, 0, 0)
    TweenService:Create(NotifFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0.1,
        Position = UDim2.new(0, 0, 0, 0),
    }):Play()
    TweenService:Create(Stroke, TweenInfo.new(0.4), {Transparency = 0}):Play()
    TweenService:Create(TitleLabel, TweenInfo.new(0.4), {TextTransparency = 0}):Play()
    TweenService:Create(DescLabel, TweenInfo.new(0.4), {TextTransparency = 0}):Play()

    task.spawn(function()
        task.wait(duration)
        if NotifFrame and NotifFrame.Parent then
            local tw1 = TweenService:Create(NotifFrame, TweenInfo.new(0.5), {
                BackgroundTransparency = 1,
                Position = UDim2.new(1, 50, 0, 0),
            })
            TweenService:Create(Stroke, TweenInfo.new(0.5), {Transparency = 1}):Play()
            TweenService:Create(TitleLabel, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
            TweenService:Create(DescLabel, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
            tw1:Play()
            tw1.Completed:Wait()
            NotifFrame:Destroy()
            activeNotifications = activeNotifications - 1
        end
    end)
end

-- === UI BUILDERS ===
local categoryFrames = {}  -- for minimize/restore

local function createCategory(name, position)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(0, 180, 0, 35)
    Frame.Position = position
    Frame.BackgroundColor3 = COLORS.Header
    Frame.BorderSizePixel = 0
    Frame.Parent = ScreenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = Frame

    local Outline = Instance.new("UIStroke")
    Outline.Color = COLORS.Outline
    Outline.Thickness = 2
    Outline.Parent = Frame

    local HeaderText = Instance.new("TextLabel")
    HeaderText.Size = UDim2.new(1, -10, 1, 0)
    HeaderText.Position = UDim2.new(0, 10, 0, 0)
    HeaderText.BackgroundTransparency = 1
    HeaderText.Text = name
    HeaderText.TextColor3 = COLORS.Text
    HeaderText.Font = Enum.Font.GothamBold
    HeaderText.TextSize = 14
    HeaderText.TextXAlignment = Enum.TextXAlignment.Left
    HeaderText.Parent = Frame

    local ContentFrame = Instance.new("Frame")
    ContentFrame.Size = UDim2.new(1, 0, 0, 0)
    ContentFrame.Position = UDim2.new(0, 0, 1, 0)
    ContentFrame.BackgroundColor3 = COLORS.Background
    ContentFrame.BorderSizePixel = 0
    ContentFrame.ClipsDescendants = true
    ContentFrame.AutomaticSize = Enum.AutomaticSize.Y
    ContentFrame.Parent = Frame

    local ContentOutline = Instance.new("UIStroke")
    ContentOutline.Color = COLORS.Outline
    ContentOutline.Thickness = 2
    ContentOutline.Parent = ContentFrame

    local Layout = Instance.new("UIListLayout")
    Layout.SortOrder = Enum.SortOrder.LayoutOrder
    Layout.Parent = ContentFrame

    -- Dragging (mobile + desktop)
    local dragStart, dragStartPos
    local function updateDrag(input)
        local delta = input.Position - dragStart
        Frame.Position = UDim2.new(
            0, dragStartPos.X.Offset + delta.X,
            0, dragStartPos.Y.Offset + delta.Y
        )
    end
    trackConn(Frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragStart = input.Position
            dragStartPos = Frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragStart = nil
                end
            end)
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
            ContentFrame.Visible = not ContentFrame.Visible
        end
    end))
    trackConn(Frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            if dragStart then updateDrag(input) end
        end
    end))

    table.insert(categoryFrames, {frame = Frame, content = ContentFrame})
    return ContentFrame
end

local function createLabel(parent, text)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 25)
    Frame.BackgroundColor3 = COLORS.ButtonNormal
    Frame.BorderSizePixel = 0
    Frame.Parent = parent

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -10, 1, 0)
    Label.Position = UDim2.new(0, 5, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = text
    Label.TextColor3 = COLORS.Text
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 12
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Frame
    return Label
end

local function createToggle(parent, text, defaultState, callback)
    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(1, 0, 0, 35)
    Button.BackgroundColor3 = defaultState and COLORS.ButtonActive or COLORS.ButtonNormal
    Button.BorderSizePixel = 0
    Button.Text = text
    Button.TextColor3 = COLORS.Text
    Button.Font = Enum.Font.Gotham
    Button.TextSize = 13
    Button.AutoButtonColor = false
    Button.Parent = parent

    local state = defaultState
    trackConn(Button.MouseEnter:Connect(function()
        if not state then Button.BackgroundColor3 = COLORS.ButtonHover end
    end))
    trackConn(Button.MouseLeave:Connect(function()
        Button.BackgroundColor3 = state and COLORS.ButtonActive or COLORS.ButtonNormal
    end))
    trackConn(Button.MouseButton1Click:Connect(function()
        state = not state
        Button.BackgroundColor3 = state and COLORS.ButtonActive or COLORS.ButtonHover
        if state then PlaySound(SFX.Toggle, 1) end
        pcall(callback, state, Button)
        -- Persist settings on toggle (parent chain: Button -> ContentFrame -> Frame -> ScreenGui)
        if parent and parent.Parent and parent.Parent.Parent and parent.Parent.Parent.Name == "NeuroHubGui" then
            saveSettings()
        end
    end))
    return Button
end

local function createAction(parent, text, callback, isDanger, customColor)
    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(1, 0, 0, 35)
    Button.BackgroundColor3 = customColor or (isDanger and COLORS.ButtonDanger or COLORS.ButtonNormal)
    Button.BorderSizePixel = 0
    Button.Text = text
    Button.TextColor3 = COLORS.Text
    Button.Font = Enum.Font.Gotham
    Button.TextSize = 13
    Button.AutoButtonColor = false
    Button.Parent = parent

    local function bg() return customColor or (isDanger and COLORS.ButtonDanger or COLORS.ButtonNormal) end
    trackConn(Button.MouseEnter:Connect(function()
        if not isDanger and not customColor then Button.BackgroundColor3 = COLORS.ButtonHover end
    end))
    trackConn(Button.MouseLeave:Connect(function() Button.BackgroundColor3 = bg() end))
    trackConn(Button.MouseButton1Click:Connect(function()
        if not isDanger and not customColor then Button.BackgroundColor3 = COLORS.ButtonActive end
        PlaySound(SFX.Toggle, 1)
        task.spawn(function()
            pcall(callback, Button)
            task.wait(0.2)
            if not isDanger and not customColor then Button.BackgroundColor3 = COLORS.ButtonHover end
        end)
    end))
    return Button
end

local function createSlider(parent, prefixText, minVal, maxVal, defaultVal, decimals, callback)
    decimals = decimals or 0
    local SliderFrame = Instance.new("Frame")
    SliderFrame.Size = UDim2.new(1, 0, 0, 45)
    SliderFrame.BackgroundColor3 = COLORS.ButtonNormal
    SliderFrame.BorderSizePixel = 0
    SliderFrame.Parent = parent

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, 0, 0, 25)
    Label.BackgroundTransparency = 1
    Label.Text = prefixText .. string.format("%."..decimals.."f", defaultVal)
    Label.TextColor3 = COLORS.Text
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 13
    Label.Parent = SliderFrame

    local SliderBg = Instance.new("Frame")
    SliderBg.Size = UDim2.new(0.8, 0, 0, 6)
    SliderBg.Position = UDim2.new(0.1, 0, 0, 30)
    SliderBg.BackgroundColor3 = COLORS.Background
    SliderBg.BorderSizePixel = 0
    SliderBg.Parent = SliderFrame

    local SliderFill = Instance.new("Frame")
    SliderFill.Size = UDim2.new((defaultVal - minVal) / (maxVal - minVal), 0, 1, 0)
    SliderFill.BackgroundColor3 = COLORS.ButtonActive
    SliderFill.BorderSizePixel = 0
    SliderFill.Parent = SliderBg

    local SliderBtn = Instance.new("TextButton")
    SliderBtn.Size = UDim2.new(1, 0, 1, 10)
    SliderBtn.Position = UDim2.new(0, 0, 0, -5)
    SliderBtn.BackgroundTransparency = 1
    SliderBtn.Text = ""
    SliderBtn.Parent = SliderBg

    local dragging = false
    local function updateSlider(input)
        local sliderX = SliderBg.AbsolutePosition.X
        local sliderWidth = SliderBg.AbsoluteSize.X
        local inputX = input.Position.X
        local percent = math.clamp((inputX - sliderX) / sliderWidth, 0, 1)
        local newVal = minVal + (maxVal - minVal) * percent
        if decimals == 0 then
            newVal = math.floor(newVal)
        else
            local mult = 10^decimals
            newVal = math.floor(newVal * mult + 0.5) / mult
        end
        Label.Text = prefixText .. string.format("%."..decimals.."f", newVal)
        SliderFill.Size = UDim2.new(percent, 0, 1, 0)
        pcall(callback, newVal)
    end

    trackConn(SliderBtn.MouseButton1Down:Connect(function()
        dragging = true
        updateSlider({Position = Vector3.new(Players.LocalPlayer:GetMouse().X, 0, 0)})
    end))
    trackConn(SliderBtn.TouchTap:Connect(function(_, pos)
        dragging = true
        updateSlider({Position = Vector3.new(pos.X, 0, 0)})
    end))
    trackConn(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                      or input.UserInputType == Enum.UserInputType.Touch) then
            updateSlider(input)
        end
    end))
    trackConn(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then saveSettings() end
            dragging = false
        end
    end))
    return Label
end

-- === KEYBINDS ===
local Binds = {
    FastStop        = { Key = Enum.KeyCode.Space,        Enabled = false },
    GoUp            = { Key = Enum.KeyCode.U,            Enabled = false },
    GoDown          = { Key = Enum.KeyCode.J,            Enabled = false },
    InstaBoost      = { Key = Enum.KeyCode.G,            Enabled = false },
    ToggleSmartRace = { Key = Enum.KeyCode.Z,            Enabled = false },
    ToggleAutoCP    = { Key = Enum.KeyCode.X,            Enabled = false },
    ToggleNoclip    = { Key = Enum.KeyCode.C,            Enabled = false },
    ToggleGUI       = { Key = Enum.KeyCode.RightShift,   Enabled = true },  -- new: hide/show GUI
}
local currentlyBinding = nil

local function createKeybind(parent, text, bindId)
    local BindFrame = Instance.new("Frame")
    BindFrame.Size = UDim2.new(1, 0, 0, 35)
    BindFrame.BackgroundColor3 = COLORS.ButtonNormal
    BindFrame.BorderSizePixel = 0
    BindFrame.Parent = parent

    local ToggleBtn = Instance.new("TextButton")
    ToggleBtn.Size = UDim2.new(0, 25, 0, 25)
    ToggleBtn.Position = UDim2.new(0, 5, 0, 5)
    ToggleBtn.BackgroundColor3 = COLORS.Background
    ToggleBtn.BorderSizePixel = 0
    ToggleBtn.Text = ""
    ToggleBtn.AutoButtonColor = false
    ToggleBtn.Parent = BindFrame

    local function updateToggleUI()
        ToggleBtn.BackgroundColor3 = Binds[bindId].Enabled and COLORS.ButtonActive or COLORS.ButtonDanger
    end
    updateToggleUI()

    trackConn(ToggleBtn.MouseButton1Click:Connect(function()
        Binds[bindId].Enabled = not Binds[bindId].Enabled
        if Binds[bindId].Enabled then PlaySound(SFX.Toggle, 1) end
        updateToggleUI()
        saveSettings()
    end))

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -95, 1, 0)
    Label.Position = UDim2.new(0, 35, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = text
    Label.TextColor3 = COLORS.Text
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 12
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = BindFrame

    local KeyBtn = Instance.new("TextButton")
    KeyBtn.Size = UDim2.new(0, 50, 0, 25)
    KeyBtn.Position = UDim2.new(1, -55, 0, 5)
    KeyBtn.BackgroundColor3 = COLORS.Header
    KeyBtn.BorderSizePixel = 0
    KeyBtn.Text = Binds[bindId].Key.Name
    KeyBtn.TextColor3 = COLORS.ButtonActive
    KeyBtn.Font = Enum.Font.GothamBold
    KeyBtn.TextSize = 11
    KeyBtn.Parent = BindFrame
    Binds[bindId].Btn = KeyBtn

    trackConn(KeyBtn.MouseButton1Click:Connect(function()
        KeyBtn.Text = "..."
        currentlyBinding = bindId
    end))
end

-- ============================================================
--  CORE HELPER FUNCTIONS
-- ============================================================

-- Refresh gobutton position dynamically (fixes stale cache bug)
local function getGoButton()
    local queue = LocalPlayer.PlayerGui:FindFirstChild("LiveQueue")
    if not queue then return nil end
    local btn = queue:FindFirstChild("Center") and queue.Center:FindFirstChild("Teleport")
    return btn
end

local function getGoButtonCenter()
    local btn = getGoButton()
    if not btn or not btn.Visible then return nil end
    local pos = btn.AbsolutePosition
    local size = btn.AbsoluteSize
    local inset = GuiService:GetGuiInset()
    return Vector2.new(pos.X + size.X / 2, pos.Y + size.Y / 2 + inset.Y)
end

-- Find local player's car
-- Based on .rbxlx analysis:
--   * CurrentDriver is an ObjectValue whose .Value is a Player (NOT a Character!)
--   * PrimaryPart is named "Main" (CanCollide=false, Transparency=1)
--   * Seats folder contains "Driver" (VehicleSeat) + "Passenger" (Seat)
local function getMyCar()
    local cars = workspace:FindFirstChild("Cars")
    if not cars then return nil end
    local me = LocalPlayer
    local myChar = me.Character
    for _, car in ipairs(cars:GetChildren()) do
        -- Primary path: check CurrentDriver ObjectValue -> Player
        local d = car:FindFirstChild("CurrentDriver")
        if d and d:IsA("ObjectValue") then
            local val = d.Value
            if val == me then return car end
            -- Some games might store the Player's name as a string
            if typeof(val) == "string" and val == me.Name then return car end
        end
    end
    -- Fallback: check if local player's character is seated in any car
    if myChar then
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.SeatPart then
            local seat = humanoid.SeatPart
            if seat:IsA("VehicleSeat") then
                local carModel = seat:FindFirstAncestorOfClass("Model")
                if carModel and carModel.Parent == cars then
                    return carModel
                end
            end
        end
    end
    return nil
end

local function getRootPart()
    local car = getMyCar()
    if car then
        -- "Main" is the proper PrimaryPart in Drive World cars
        return car.PrimaryPart or car:FindFirstChild("Main") or car:FindFirstChild("Body") or car:FindFirstChildWhichIsA("BasePart")
    end
    local char = LocalPlayer.Character
    if char then
        return char:FindFirstChild("HumanoidRootPart")
    end
    return nil
end

local function getCarInfo()
    local char = LocalPlayer.Character
    if not char then return nil, nil end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.SeatPart and humanoid.SeatPart:IsA("VehicleSeat") then
        local seat = humanoid.SeatPart
        local carModel = seat:FindFirstAncestorOfClass("Model")
        return (carModel and carModel.PrimaryPart or seat), carModel
    end
    -- Fallback to getMyCar
    local car = getMyCar()
    if car then
        return (car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart")), car
    end
    return nil, nil
end

-- ============================================================
--  NOCLIP & FREEZE
-- ============================================================

local noclipSkip = 0
local function updateNoclip(state)
    State.NoclipEnabled = state
    _G.NoclipEnabled = state
    if state then
        if not noclipConnection then
            noclipConnection = RunService.Stepped:Connect(function()
                -- Throttle: every 2 frames
                noclipSkip = noclipSkip + 1
                if noclipSkip % 2 ~= 0 then return end
                local car = getMyCar()
                if car then
                    for _, part in ipairs(car:GetDescendants()) do
                        if part:IsA("BasePart") then part.CanCollide = false end
                    end
                end
                local char = LocalPlayer.Character
                if char then
                    for _, part in ipairs(char:GetDescendants()) do
                        if part:IsA("BasePart") then part.CanCollide = false end
                    end
                end
            end)
            table.insert(connections, noclipConnection)
        end
    else
        if noclipConnection then
            noclipConnection:Disconnect()
            noclipConnection = nil
        end
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart")
                and part.Name ~= "DoorMain" and part.Name ~= "Exhaust"
                and part.Name ~= "Main" and part.Name ~= "Stars"
                and part.Name ~= "Contrast" then
                    part.CanCollide = true
                end
            end
        end
        local car = getMyCar()
        if car then
            for _, part in ipairs(car:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = true end
            end
        end
    end
end

local function setFreeze(state)
    State.PlayerFrozen = state
    _G.PlayerFrozen = state
    -- Anchor HRP
    local char = LocalPlayer.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.Anchored = state end
    end
    -- Also anchor car parts (FIX: original only anchored HRP)
    if state then
        local car = getMyCar()
        if car then
            local root = car.PrimaryPart or car:FindFirstChild("Body") or car:FindFirstChildWhichIsA("BasePart")
            if root then root.Anchored = true end
        end
    else
        local car = getMyCar()
        if car then
            local root = car.PrimaryPart or car:FindFirstChild("Body") or car:FindFirstChildWhichIsA("BasePart")
            if root then root.Anchored = false end
        end
    end
end

-- ============================================================
--  ANTI-AFK
-- ============================================================
local antiAFKConn = nil
local function setAntiAFK(state)
    State.AntiAFKEnabled = state
    _G.AntiAFKEnabled = state
    if state then
        if not VirtualUser then
            SendNotification("Anti-AFK", "VirtualUser not available on this executor. Using idle reset only.", 4)
        end
        if antiAFKConn then antiAFKConn:Disconnect() end
        antiAFKConn = LocalPlayer.Idled:Connect(function()
            pcall(function()
                if VirtualUser then
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new())
                end
            end)
            -- Also nudge the character so the server sees activity
            pcall(function()
                local char = LocalPlayer.Character
                if char then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local humanoid = char:FindFirstChildOfClass("Humanoid")
                    if hrp and humanoid then
                        -- tiny camera nudge - won't actually move player
                        humanoid:Move(Vector3.new(0, 0, 0), false)
                    end
                end
            end)
        end)
        table.insert(connections, antiAFKConn)
        SendNotification("Anti-AFK", "Active. You will not be kicked for idling.", 4)
    else
        if antiAFKConn then
            antiAFKConn:Disconnect()
            antiAFKConn = nil
        end
    end
end

-- ============================================================
--  ESP FOR CHECKPOINTS
-- ============================================================
local function clearESP()
    if espHighlight then espHighlight:Destroy() espHighlight = nil end
    if espBillboard then espBillboard:Destroy() espBillboard = nil end
end

local function setESP(target)
    clearESP()
    if not target or not State.ESPEnabled then return end
    pcall(function()
        espHighlight = Instance.new("Highlight")
        espHighlight.Name = "NeuroHubESP"
        espHighlight.Adornee = target
        espHighlight.FillColor = COLORS.ButtonActive
        espHighlight.OutlineColor = Color3.new(1, 1, 1)
        espHighlight.FillTransparency = 0.5
        espHighlight.OutlineTransparency = 0
        espHighlight.Parent = target

        espBillboard = Instance.new("BillboardGui")
        espBillboard.Name = "NeuroHubESPLabel"
        espBillboard.Adornee = target
        espBillboard.Size = UDim2.new(0, 150, 0, 30)
        espBillboard.StudsOffset = Vector3.new(0, 5, 0)
        espBillboard.AlwaysOnTop = true
        espBillboard.Parent = target
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = "TARGET"
        lbl.TextColor3 = COLORS.ButtonActive
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 16
        lbl.Parent = espBillboard
    end)
end

-- ============================================================
--  CHECKPOINT FINDING - v3.1 PROPER IMPLEMENTATION
--  Based on Cobalt session recording analysis:
--    * Server tracks progress via workspace.Races.<race>.SingleplayerRacers.<player>.Checkpoint
--    * CP Models in Checkpoints folder have hex names like "31d061"
--    * Each CP Model has: Inner, Outer, Forcefield parts
--    * Some CP Models also have Config/CheckpointNum IntValue
--    * When player touches CP, client fires Remotes.RaceCheckpoint:FireServer(hexName)
--    * Server advances Checkpoint counter
--  Strategy:
--    1. Find player's active race (via SingleplayerRacers.<player> existence)
--    2. Read current Checkpoint value from player's racer folder
--    3. Find CPs in race.Checkpoints folder, sort by CheckpointNum
--    4. Return the next CP after current progress
-- ============================================================
local cpCache = { target = nil, time = 0, race = nil, progress = -1 }
local CP_CACHE_DURATION = 0.15

-- Keep old color functions for backward compat (unused now but kept for safety)
local function isBlue(c)
    if not c then return false end
    return math.abs(c.R*255 - Config.TARGET_BLUE.R*255) <= Config.TOLERANCE
       and math.abs(c.G*255 - Config.TARGET_BLUE.G*255) <= Config.TOLERANCE
       and math.abs(c.B*255 - Config.TARGET_BLUE.B*255) <= Config.TOLERANCE
end

local function isGreen(c)
    if not c then return false end
    if c.G * 255 > 200 and c.R * 255 < 100 then return true end
    return math.abs(c.R*255 - Config.TARGET_GREEN.R*255) <= Config.TOLERANCE
       and math.abs(c.G*255 - Config.TARGET_GREEN.G*255) <= Config.TOLERANCE
       and math.abs(c.B*255 - Config.TARGET_GREEN.B*255) <= Config.TOLERANCE
end

-- Helper: find which race the local player is currently in
local function findActiveRace()
    local races = workspace:FindFirstChild("Races")
    if not races then return nil, nil end
    local myName = LocalPlayer.Name

    for _, race in ipairs(races:GetChildren()) do
        -- Check SingleplayerRacers first
        local spRacers = race:FindFirstChild("SingleplayerRacers")
        if spRacers and spRacers:FindFirstChild(myName) then
            return race, spRacers[myName]
        end
        -- Check MultiplayerRacers
        local mpRacers = race:FindFirstChild("MultiplayerRacers")
        if mpRacers and mpRacers:FindFirstChild(myName) then
            return race, mpRacers[myName]
        end
    end
    return nil, nil
end

-- Helper: read current CP progress from racer folder
-- racerFolder typically has: DrivingLock (BoolValue), and other state
-- The actual CP count is stored as a property on the racer's data
local function getPlayerCPProgress(racerFolder)
    if not racerFolder then return 0 end
    -- Try different field names seen in races
    for _, fieldName in ipairs({"Checkpoint", "CurrentCheckpoint", "CPProgress", "LastCheckpoint"}) do
        local v = racerFolder:FindFirstChild(fieldName)
        if v and v:IsA("IntValue") then
            return v.Value
        end
    end
    -- Fallback: count children that look like progress markers
    return 0
end

-- Helper: get position of a CP Model
local function getCPPosition(cpModel)
    if not cpModel then return nil end
    -- Try PrimaryPart first
    local pp = cpModel.PrimaryPart
    if pp then return pp.Position end
    -- Then Inner / Outer / Forcefield
    for _, partName in ipairs({"Inner", "Outer", "Forcefield"}) do
        local part = cpModel:FindFirstChild(partName)
        if part and (part:IsA("BasePart") or part:IsA("MeshPart")) then
            return part.Position
        end
    end
    -- Then any BasePart
    local any = cpModel:FindFirstChildWhichIsA("BasePart")
    if any then return any.Position end
    -- Try PivotTo
    local ok, pivot = pcall(function() return cpModel:GetPivot() end)
    if ok and pivot then return pivot.Position end
    return nil
end

-- Helper: sort checkpoints by CheckpointNum
local function getSortedCheckpoints(race)
    if not race then return {} end
    local cpFolder = race:FindFirstChild("Checkpoints")
    if not cpFolder then return {} end

    local cps = {}
    for _, cp in ipairs(cpFolder:GetChildren()) do
        if cp:IsA("Model") then
            local num = nil
            -- Look for Config/CheckpointNum
            local cfg = cp:FindFirstChild("Config")
            if cfg then
                local cpNum = cfg:FindFirstChild("CheckpointNum")
                if cpNum and cpNum:IsA("IntValue") then
                    num = cpNum.Value
                end
            end
            -- Fallback: try top-level CheckpointNum
            if not num then
                local cpNum = cp:FindFirstChild("CheckpointNum")
                if cpNum and cpNum:IsA("IntValue") then
                    num = cpNum.Value
                end
            end
            -- If no CheckpointNum, try to parse from name (hex -> numeric)
            if not num then
                local name = cp.Name
                -- Convert hex string to number for sorting
                local ok, parsed = pcall(function() return tonumber(name, 16) end)
                if ok and parsed then num = parsed end
            end
            table.insert(cps, {model = cp, num = num or 999, name = cp.Name})
        end
    end

    table.sort(cps, function(a, b) return a.num < b.num end)
    return cps
end

-- MAIN: find best checkpoint to fly to
local function findBestCheckpoint(useCache)
    -- Find active race
    local race, racerFolder = findActiveRace()

    -- Cache check - only valid if race hasn't changed and progress hasn't changed
    local currentProgress = getPlayerCPProgress(racerFolder)
    if useCache and cpCache.target and cpCache.target.Parent
       and (os.clock() - cpCache.time) < CP_CACHE_DURATION
       and cpCache.race == race
       and cpCache.progress == currentProgress then
        return cpCache.target
    end

    -- Update race state
    if race then
        State.CurrentRace = race
        State.CurrentRaceName = race.Name
        State.CurrentCPIndex = currentProgress
        State.IsInRace = true
    else
        State.CurrentRace = nil
        State.CurrentRaceName = ""
        State.IsInRace = false
    end

    if not race then
        -- No active race - fall back to finding any race with visible blue CP
        -- (in case the game uses color indicators on non-active race setups)
        local races = workspace:FindFirstChild("Races")
        if races then
            for _, r in ipairs(races:GetChildren()) do
                local cpFolder = r:FindFirstChild("Checkpoints")
                if cpFolder then
                    for _, cp in ipairs(cpFolder:GetChildren()) do
                        for _, partName in ipairs({"Inner", "Outer", "Forcefield"}) do
                            local part = cp:FindFirstChild(partName)
                            if part and (part:IsA("BasePart") or part:IsA("MeshPart")) then
                                if isBlue(part.Color) then
                                    cpCache.target = cp
                                    cpCache.time = os.clock()
                                    cpCache.race = nil
                                    cpCache.progress = -1
                                    return cp
                                end
                            end
                        end
                    end
                end
            end
        end
        return nil
    end

    -- Active race found! Get sorted CPs
    local sortedCPs = getSortedCheckpoints(race)
    State.TotalCheckpoints = #sortedCPs

    if #sortedCPs == 0 then return nil end

    -- Next CP index = currentProgress + 1 (1-indexed)
    -- If currentProgress is 0 (just started), target is CP #1
    -- If we've passed all CPs, target the last (finish line)
    local targetIdx = math.min(currentProgress + 1, #sortedCPs)
    local target = sortedCPs[targetIdx]

    if target then
        cpCache.target = target.model
        cpCache.time = os.clock()
        cpCache.race = race
        cpCache.progress = currentProgress
        State.LastCPName = target.name
        return target.model
    end

    return nil
end

-- ============================================================
--  DRIFT GLITCH UI UPDATE
-- ============================================================
local driftButtons = {}

local function updateDriftUI()
    if driftButtons.Toggle then
        driftButtons.Toggle.BackgroundColor3 = State.DriftGlitchActive and COLORS.ButtonActive or COLORS.ButtonNormal
    end
    if driftButtons.Platform then
        driftButtons.Platform.BackgroundColor3 = State.PlatformModeActive and COLORS.ButtonActive or COLORS.ButtonPlatform
    end
    if driftButtons.AutoDrift then
        driftButtons.AutoDrift.BackgroundColor3 = State.AutoDriftActive and COLORS.ButtonActive or COLORS.ButtonNormal
        driftButtons.AutoDrift.Text = State.AutoDriftActive and "AutoDrift ACTIVE [R]" or "AutoDrift [R]"
    end
    if driftButtons.AngleLabel then
        driftButtons.AngleLabel.Text = string.format("Angle: %.1f° | Side: %s", State.DriftAngle, State.DriftSide == 1 and "Right" or "Left")
    end
end

local function togglePlatform()
    local root, carModel = getCarInfo()
    if not root or not carModel then
        SendNotification("Drift Glitch", "Сядь в машину!", 3)
        return
    end
    State.PlatformModeActive = not State.PlatformModeActive
    _G.PlatformModeActive = State.PlatformModeActive

    if State.PlatformModeActive then
        if platformFolder then platformFolder:Destroy() end
        platformFolder = Instance.new("Folder")
        platformFolder.Name = "DriftPlatformFolder"
        platformFolder.Parent = workspace

        local floor = Instance.new("Part")
        floor.Name = "DriftFloor"
        floor.Size = Vector3.new(6000, 12, 6000)
        floor.Position = Vector3.new(0, Config.PLATFORM_HEIGHT, 0)
        floor.Anchored = true
        floor.Transparency = 0.35
        floor.Color = Color3.fromRGB(50, 50, 90)
        floor.Material = Enum.Material.Neon
        floor.Parent = platformFolder

        savedCFrame = root.CFrame
        carModel:PivotTo(CFrame.new(0, Config.PLATFORM_HEIGHT + 15, 0))
        SendNotification("Drift Glitch", "Платформа включена!", 3)
    else
        if platformFolder then
            platformFolder:Destroy()
            platformFolder = nil
        end
        if savedCFrame and root then
            root.CFrame = savedCFrame
        end
        SendNotification("Drift Glitch", "Платформа отключена.", 3)
    end
    updateDriftUI()
end

-- ============================================================
--  SAFE QUIT
-- ============================================================
local function SafeQuit()
    State.SmartRaceEnabled = false
    State.AutoCheckpointEnabled = false
    State.AutoFlyEnabled = false
    State.NoclipEnabled = false
    State.PlayerFrozen = false
    State.SpeedBoostEnabled = false
    State.FarmPatchEnabled = false
    State.DriftGlitchActive = false
    State.PlatformModeActive = false
    State.AutoDriftActive = false
    State.AntiAFKEnabled = false
    State.InfiniteJumpEnabled = false

    -- Mirror to _G
    for k, v in pairs(State) do _G[k] = v end

    if platformFolder then platformFolder:Destroy() platformFolder = nil end
    clearESP()

    pcall(updateNoclip, false)
    pcall(setFreeze, false)
    if antiAFKConn then antiAFKConn:Disconnect() antiAFKConn = nil end

    local root = getRootPart()
    if root then
        pcall(function() root.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end)
    end

    for _, conn in ipairs(connections) do
        if conn and conn.Connected then
            pcall(function() conn:Disconnect() end)
        end
    end
    table.clear(connections)

    saveSettings()
    if ScreenGui then ScreenGui:Destroy() end
    if NotifyGui then NotifyGui:Destroy() end
    print("[Neuro Hub] Unloaded safely. Bye!")
end

-- ============================================================
--  TELEPORT TO WAYPOINT (map marker)
-- ============================================================
local function teleportToWaypoint()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local mouseHit = LocalPlayer:GetMouse().Hit
    if mouseHit then
        hrp.CFrame = CFrame.new(mouseHit.Position + Vector3.new(0, 5, 0))
        SendNotification("Teleport", "Teleported to waypoint.", 3)
    else
        SendNotification("Teleport", "Click on the map first.", 3)
    end
end

-- ============================================================
--  LOOP FORWARD DECLARATIONS
-- ============================================================
local startSmartRaceLoop, startAutoCPLoop, startAutoFlyLoop, startFarmPatchLoop

local function flyTo(car, targetPart)
    local root = car.PrimaryPart or car:FindFirstChild("Main") or car:FindFirstChild("Body") or car:FindFirstChildWhichIsA("BasePart")
    if not root then return end

    -- targetPart might be a Model (checkpoint) - get its position via PrimaryPart or first BasePart
    local targetPos
    if typeof(targetPart) == "Instance" then
        if targetPart:IsA("BasePart") or targetPart:IsA("MeshPart") then
            targetPos = targetPart.Position
        elseif targetPart:IsA("Model") then
            -- Try PrimaryPart, then Inner, Outer, Forcefield, first BasePart
            local pp = targetPart.PrimaryPart
            if pp then
                targetPos = pp.Position
            else
                local inner = targetPart:FindFirstChild("Inner")
                if inner and (inner:IsA("BasePart") or inner:IsA("MeshPart")) then
                    targetPos = inner.Position
                else
                    local outer = targetPart:FindFirstChild("Outer")
                    if outer and (outer:IsA("BasePart") or outer:IsA("MeshPart")) then
                        targetPos = outer.Position
                    else
                        local ff = targetPart:FindFirstChild("Forcefield")
                        if ff and (ff:IsA("BasePart") or ff:IsA("MeshPart")) then
                            targetPos = ff.Position
                        else
                            local anyPart = targetPart:FindFirstChildWhichIsA("BasePart")
                            if anyPart then
                                targetPos = anyPart.Position
                            else
                                return
                            end
                        end
                    end
                end
            end
        else
            return
        end
    else
        return
    end

    targetPos = targetPos + Vector3.new(0, Config.DEFAULT_HEIGHT, 0)
    local direction = (targetPos - root.Position)
    if direction.Magnitude > 5 then
        root.AssemblyLinearVelocity = direction.Unit * Config.FLY_SPEED
        root.CFrame = CFrame.lookAt(root.Position, Vector3.new(targetPos.X, root.Position.Y, targetPos.Z))
    else
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    end
end

-- ============================================================
--  SMART RACE LOOP
-- ============================================================
function startSmartRaceLoop()
    task.spawn(function()
        while State.SmartRaceEnabled do
            local target = findBestCheckpoint(true)
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")

            if not target then
                if hrp then
                    local goCenter = getGoButtonCenter()
                    if goCenter and State.SmartRaceTPd == false then
                        State.SmartRaceTPd = true
                        _G.SmartRaceTPd = true
                        pcall(function()
                            VirtualInputManager:SendMouseButtonEvent(goCenter.X, goCenter.Y, 0, true, game, 1)
                            task.wait(0.1)
                            VirtualInputManager:SendMouseButtonEvent(goCenter.X, goCenter.Y, 0, false, game, 1)
                        end)
                    end
                    pcall(function() hrp.AssemblyLinearVelocity = Vector3.new(0,0,0) end)
                end
                pcall(updateNoclip, false)
                clearESP()
                task.wait(0.1)
            else
                setESP(target)
                if hrp then hrp.Anchored = false end
                for i = 1, 70 do
                    if not State.SmartRaceEnabled then break end
                    task.wait(0.1)
                end
                if not State.SmartRaceEnabled then break end
                pcall(updateNoclip, true)
                local missingTime = 0
                while State.SmartRaceEnabled do
                    target = findBestCheckpoint(true)
                    if target then
                        missingTime = 0
                        setESP(target)
                        local myCar = getMyCar()
                        if myCar then flyTo(myCar, target) end
                    else
                        local dt = task.wait()
                        missingTime = missingTime + dt
                        if missingTime > 2 then break end
                        local myCar = getMyCar()
                        if myCar and myCar.PrimaryPart then
                            myCar.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
                        end
                        State.SmartRaceTPd = false
                        _G.SmartRaceTPd = false
                    end
                    task.wait()
                end
            end
            task.wait()
        end
        clearESP()
        pcall(updateNoclip, false)
    end)
end

-- ============================================================
--  AUTO CHECKPOINT LOOP
-- ============================================================
function startAutoCPLoop()
    task.spawn(function()
        while State.AutoCheckpointEnabled do
            local target = findBestCheckpoint(true)
            local car = getMyCar()
            if target and car then
                setESP(target)
                flyTo(car, target)
            elseif car and car.PrimaryPart then
                pcall(function() car.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0,0,0) end)
            end
            task.wait()
        end
        clearESP()
    end)
end

-- ============================================================
--  AUTO FLY LOOP (improved physics)
-- ============================================================
function startAutoFlyLoop()
    task.spawn(function()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local startCF = hrp and hrp.CFrame or WAITING_CFRAME

        while State.AutoFlyEnabled do
            char = LocalPlayer.Character
            hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                pcall(function()
                    hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                    hrp.CFrame = startCF
                end)
                task.wait(0.2)
                if State.AutoFlyEnabled then
                    pcall(function() hrp.AssemblyLinearVelocity = Vector3.new(0, Config.FLY_SPEED, 0) end)
                    task.wait(1.5)
                end
                if State.AutoFlyEnabled and hrp then
                    pcall(function() hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end)
                    task.wait(0.5)
                end
            end
            task.wait()
        end
        char = LocalPlayer.Character
        hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                hrp.CFrame = startCF
            end)
        end
    end)
end

-- ============================================================
--  FARM PATCH LOOP (with wave motion)
-- ============================================================
function startFarmPatchLoop()
    task.spawn(function()
        pcall(updateNoclip, true)
        local t          = 0
        local phaseTime  = 0
        local isBursting = true
        local xSpeed     = 0

        while State.FarmPatchEnabled do
            local dt = task.wait()
            phaseTime = phaseTime + dt

            if isBursting and phaseTime >= Config.AIRFARM_BURST_TIME then
                isBursting = false
                phaseTime  = 0
            elseif not isBursting and phaseTime >= Config.AIRFARM_STOP_TIME then
                isBursting = true
                phaseTime  = 0
            end

            local car = getMyCar()
            if not car then continue end

            local root = car.PrimaryPart or car:FindFirstChild("Body") or car:FindFirstChildWhichIsA("BasePart")
            if not root then continue end

            local pos = root.Position
            local flatDist = Vector3.new(pos.X, 0, pos.Z).Magnitude

            if flatDist > Config.AIRFARM_MAX_DIST then
                local resetY = (State.PlatformModeActive and platformFolder)
                               and (Config.PLATFORM_HEIGHT + 15)
                               or  Config.AIRFARM_HEIGHT
                pcall(function()
                    car:PivotTo(CFrame.new(0, resetY, 0))
                    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                    root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                end)
                isBursting = false
                phaseTime  = 0
                xSpeed     = 0
                t          = 0
                continue
            end

            local yVel = 0

            if isBursting then
                t = t + dt
                local targetY   = Config.AIRFARM_HEIGHT + math.sin(t * Config.AIRFARM_WAVE_FREQ * math.pi * 2) * Config.AIRFARM_WAVE_AMP
                local idealYVel = Config.AIRFARM_WAVE_AMP * Config.AIRFARM_WAVE_FREQ * math.pi * 2
                                  * math.cos(t * Config.AIRFARM_WAVE_FREQ * math.pi * 2)
                local yDiff = targetY - pos.Y
                yVel = math.clamp(idealYVel + yDiff * 4, -Config.AIRFARM_SPEED, Config.AIRFARM_SPEED)

                local rampDur = math.max(Config.AIRFARM_STOP_TIME * 0.6, 0.2)
                local ramp    = math.min(phaseTime / rampDur, 1)
                xSpeed = Config.AIRFARM_SPEED * ramp

                local lookTarget = Vector3.new(pos.X + 10, pos.Y + yVel * 0.1, pos.Z)
                if pos.Y == pos.Y then  -- guard against NaN
                    pcall(function() root.CFrame = CFrame.lookAt(pos, lookTarget) end)
                end
            else
                local brakeDur = 0.25
                local brake    = math.max(1 - phaseTime / brakeDur, 0)
                xSpeed = Config.AIRFARM_SPEED * brake

                local snapY = (State.PlatformModeActive and platformFolder)
                              and (Config.PLATFORM_HEIGHT + 14)
                              or  Config.AIRFARM_HEIGHT

                local yDiff = snapY - pos.Y
                yVel = math.clamp(yDiff * 6, -Config.AIRFARM_SPEED, Config.AIRFARM_SPEED)

                local lookTarget = Vector3.new(pos.X + 1, pos.Y + yVel * 0.05, pos.Z)
                pcall(function() root.CFrame = CFrame.lookAt(pos, lookTarget) end)
            end

            pcall(function()
                root.AssemblyLinearVelocity = Vector3.new(xSpeed, yVel, 0)
            end)
        end

        pcall(updateNoclip, false)
        local car = getMyCar()
        if car then
            local root = car.PrimaryPart or car:FindFirstChild("Body") or car:FindFirstChildWhichIsA("BasePart")
            if root then
                pcall(function() root.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end)
            end
        end
    end)
end

-- ============================================================
--  DRIFT GLITCH MAIN LOOP (Stepped)
-- ============================================================
trackConn(RunService.Stepped:Connect(function()
    if not State.DriftGlitchActive then return end
    local root, carModel = getCarInfo()
    if not root or not carModel then return end

    local velocity = root.AssemblyLinearVelocity
    local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    local speed = flatVelocity.Magnitude
    if speed < Config.DRIFT_MIN_SPEED then return end

    local look = root.CFrame.LookVector
    local lookFlat = Vector3.new(look.X, 0, look.Z).Unit
    local directionMult = lookFlat:Dot(flatVelocity.Unit) < 0 and -1 or 1

    local targetAngle = math.rad(State.DriftAngle * State.DriftSide)
    local rotatedLook = (CFrame.Angles(0, targetAngle, 0) * lookFlat) * directionMult

    local boostSpeed = math.max(speed, 220)
    local targetVelocity = rotatedLook * boostSpeed
    local driftVelocity = flatVelocity:Lerp(targetVelocity, 0.16)

    pcall(function()
        root.AssemblyLinearVelocity = Vector3.new(
            driftVelocity.X * 0.82 + flatVelocity.X * 0.18,
            velocity.Y,
            driftVelocity.Z * 0.82 + flatVelocity.Z * 0.18
        )

        local angVel = root.AssemblyAngularVelocity
        root.AssemblyAngularVelocity = Vector3.new(
            angVel.X * 0.12,
            angVel.Y * Config.ANTI_SPIN,
            angVel.Z * 0.12
        )
    end)

    if State.PlatformModeActive and platformFolder then
        local pos = root.Position
        local height = pos.Y
        local horizontalDist = Vector3.new(pos.X, 0, pos.Z).Magnitude

        pcall(function()
            if height > Config.PLATFORM_HEIGHT + 8 then
                root.AssemblyLinearVelocity = root.AssemblyLinearVelocity - Vector3.new(0, Config.DOWN_FORCE, 0)
            end
            if height < Config.TARGET_HEIGHT + 6 then
                root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + Vector3.new(0, Config.ANTI_FALL_FORCE, 0)
            end
            if horizontalDist > 1950 or height < Config.PLATFORM_HEIGHT - 40 then
                carModel:PivotTo(CFrame.new(0, Config.PLATFORM_HEIGHT + 15, 0) * CFrame.Angles(0, math.rad(math.random(-40,40)), 0))
                root.AssemblyLinearVelocity = Vector3.new(0, 5, 0)
            end
        end)
    end
end))

-- ============================================================
--  AUTO DRIFT (R key toggle - toggles drift on/off periodically)
-- ============================================================
trackConn(RunService.Heartbeat:Connect(function()
    if not State.AutoDriftActive then return end
    -- AutoDrift: re-engages drift glitch if speed drops too low
    local root = getRootPart()
    if not root then return end
    local vel = root.AssemblyLinearVelocity
    local flatSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
    if flatSpeed < 30 and State.AutoDriftActive then
        -- Give a small forward nudge
        pcall(function()
            root.AssemblyLinearVelocity = root.CFrame.LookVector * 250 + Vector3.new(0, vel.Y, 0)
        end)
    end
end))

-- ============================================================
--  SPEED BOOST (Heartbeat)
-- ============================================================
trackConn(RunService.Heartbeat:Connect(function(deltaTime)
    if not State.SpeedBoostEnabled then return end
    if not UserInputService:IsKeyDown(Enum.KeyCode.W) then return end
    if State.PlayerFrozen then return end  -- skip when frozen

    local root = getRootPart()
    if not root then return end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {root.Parent}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    local rayDirection = Vector3.new(0, -6, 0)
    local rayResult = workspace:Raycast(root.Position, rayDirection, raycastParams)
    if not rayResult then return end

    local currentVelocity = root.AssemblyLinearVelocity
    local lookVector = root.CFrame.LookVector
    local currentForwardSpeed = currentVelocity:Dot(lookVector)
    if currentForwardSpeed <= 5 then return end

    local frameMultiplier = math.pow(Config.SPEED_MULTIPLIER, deltaTime * 60)
    local newForwardSpeed = currentForwardSpeed * frameMultiplier
    newForwardSpeed = math.min(newForwardSpeed, Config.MAX_BOOST_SPEED)
    local boostVelocity = lookVector * newForwardSpeed
    pcall(function()
        root.AssemblyLinearVelocity = Vector3.new(boostVelocity.X, currentVelocity.Y, boostVelocity.Z)
    end)
end))

-- ============================================================
--  INFINITE JUMP
-- ============================================================
trackConn(UserInputService.JumpRequest:Connect(function()
    if not State.InfiniteJumpEnabled then return end
    local char = LocalPlayer.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end)
    end
end))

-- ============================================================
--  WALKSPEED / JUMPPOWER APPLIER
-- ============================================================
local function applyPlayerModifiers()
    local char = LocalPlayer.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    pcall(function()
        humanoid.WalkSpeed = Config.WalkSpeed
        humanoid.UseJumpPower = true
        humanoid.JumpPower = Config.JumpPower
    end)
end

trackConn(LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    if State.PlayerFrozen then
        local hrp = char:WaitForChild("HumanoidRootPart", 5)
        if hrp then hrp.Anchored = true end
    end
    applyPlayerModifiers()
end))

-- Apply once on startup
task.spawn(function()
    task.wait(1)
    applyPlayerModifiers()
end)

-- ============================================================
--  CREATE UI CATEGORIES & BUTTONS
-- ============================================================
local buttons = {}

local function disableAllModes(exclude)
    if exclude ~= "SmartRace" then
        State.SmartRaceEnabled = false; _G.SmartRaceEnabled = false
        if buttons.SmartRace then buttons.SmartRace.BackgroundColor3 = COLORS.ButtonNormal end
    end
    if exclude ~= "AutoCheckpoint" then
        State.AutoCheckpointEnabled = false; _G.AutoCheckpointEnabled = false
        if buttons.AutoCP then buttons.AutoCP.BackgroundColor3 = COLORS.ButtonNormal end
    end
    if exclude ~= "AutoFly" then
        State.AutoFlyEnabled = false; _G.AutoFlyEnabled = false
        if buttons.AutoFly then buttons.AutoFly.BackgroundColor3 = COLORS.ButtonNormal end
    end
    if exclude ~= "FarmPatch" then
        State.FarmPatchEnabled = false; _G.FarmPatchEnabled = false
        if buttons.FarmPatch then buttons.FarmPatch.BackgroundColor3 = COLORS.ButtonNormal end
    end
end

local function toggleSmartRaceLogic(state)
    State.SmartRaceEnabled = state
    _G.SmartRaceEnabled = state
    buttons.SmartRace.BackgroundColor3 = state and COLORS.ButtonActive or COLORS.ButtonNormal
    if state then
        disableAllModes("SmartRace")
        startSmartRaceLoop()
    else
        pcall(updateNoclip, false)
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            char.HumanoidRootPart.Anchored = false
        end
    end
end

local function toggleAutoCPLogic(state)
    State.AutoCheckpointEnabled = state
    _G.AutoCheckpointEnabled = state
    buttons.AutoCP.BackgroundColor3 = state and COLORS.ButtonActive or COLORS.ButtonNormal
    if state then
        disableAllModes("AutoCheckpoint")
        startAutoCPLoop()
    end
end

local function toggleNoclipLogic(state)
    pcall(updateNoclip, state)
    if buttons.Noclip then
        buttons.Noclip.BackgroundColor3 = state and COLORS.ButtonActive or COLORS.ButtonNormal
    end
end

-- --- 1. RACE ---
local RaceCategory = createCategory("Race", UDim2.new(0, 50, 0, 50))

buttons.SmartRace = createToggle(RaceCategory, "Smart Race", false, toggleSmartRaceLogic)
buttons.AutoCP    = createToggle(RaceCategory, "Auto Checkpoint v3.1", false, toggleAutoCPLogic)
buttons.AutoFly   = createToggle(RaceCategory, "Auto Fly", false, function(state)
    State.AutoFlyEnabled = state
    _G.AutoFlyEnabled = state
    if state then
        disableAllModes("AutoFly")
        startAutoFlyLoop()
    end
end)

createSlider(RaceCategory, "Fly Speed: ", Config.MIN_SPEED, Config.MAX_SPEED, Config.FLY_SPEED, 0, function(val) Config.FLY_SPEED = val end)

buttons.FarmPatch = createToggle(RaceCategory, "FarmPatch", false, function(state)
    State.FarmPatchEnabled = state
    _G.FarmPatchEnabled = state
    buttons.FarmPatch.BackgroundColor3 = state and COLORS.ButtonActive or COLORS.ButtonNormal
    if state then
        disableAllModes("FarmPatch")
        pcall(updateNoclip, true)
        startFarmPatchLoop()
    else
        pcall(updateNoclip, false)
        local car = getMyCar()
        if car and car.PrimaryPart then
            pcall(function() car.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end)
        end
    end
end)

createSlider(RaceCategory, "FarmPatch Height: ", Config.MIN_AIRFARM_HEIGHT, Config.MAX_AIRFARM_HEIGHT, Config.AIRFARM_HEIGHT, 0, function(val) Config.AIRFARM_HEIGHT = val end)
createSlider(RaceCategory, "FarmPatch Speed: ",  Config.MIN_AIRFARM_SPEED,  Config.MAX_AIRFARM_SPEED,  Config.AIRFARM_SPEED,  0, function(val) Config.AIRFARM_SPEED = val end)
createSlider(RaceCategory, "Wave Amplitude: ",   Config.MIN_AIRFARM_AMP,    Config.MAX_AIRFARM_AMP,    Config.AIRFARM_WAVE_AMP, 0, function(val) Config.AIRFARM_WAVE_AMP = val end)
createSlider(RaceCategory, "Wave Frequency: ",   Config.MIN_AIRFARM_FREQ,   Config.MAX_AIRFARM_FREQ,   Config.AIRFARM_WAVE_FREQ, 2, function(val) Config.AIRFARM_WAVE_FREQ = val end)
createSlider(RaceCategory, "Burst Time (s): ",   Config.MIN_AIRFARM_BURST,  Config.MAX_AIRFARM_BURST,  Config.AIRFARM_BURST_TIME, 1, function(val) Config.AIRFARM_BURST_TIME = val end)
createSlider(RaceCategory, "Stop Time (s): ",    Config.MIN_AIRFARM_STOP,   Config.MAX_AIRFARM_STOP,   Config.AIRFARM_STOP_TIME, 1, function(val) Config.AIRFARM_STOP_TIME = val end)
createSlider(RaceCategory, "Max Dist (TP): ",    Config.MIN_AIRFARM_DIST,   Config.MAX_AIRFARM_DIST,   Config.AIRFARM_MAX_DIST, 0, function(val) Config.AIRFARM_MAX_DIST = val end)

-- --- 2. PLAYER ---
local PlayerCategory = createCategory("Player", UDim2.new(0, 250, 0, 50))

buttons.Noclip = createToggle(PlayerCategory, "Noclip", false, toggleNoclipLogic)
createToggle(PlayerCategory, "Freeze Player", false, function(state) setFreeze(state) end)
createToggle(PlayerCategory, "SpeedBoost (Hold W)", false, function(state)
    State.SpeedBoostEnabled = state
    _G.SpeedBoostEnabled = state
end)
createToggle(PlayerCategory, "Anti-AFK", false, function(state) setAntiAFK(state) end)
createToggle(PlayerCategory, "Infinite Jump", false, function(state)
    State.InfiniteJumpEnabled = state
    _G.InfiniteJumpEnabled = state
end)
createToggle(PlayerCategory, "Checkpoint ESP", State.ESPEnabled, function(state)
    State.ESPEnabled = state
    _G.ESPEnabled = state
    if not state then clearESP() end
end)
createToggle(PlayerCategory, "Auto-Upright Car", State.AutoUprightCar, function(state)
    State.AutoUprightCar = state
    _G.AutoUprightCar = state
end)

createSlider(PlayerCategory, "Speed Multiplier: ", Config.MIN_MULT, Config.MAX_MULT, Config.SPEED_MULTIPLIER, 3, function(val) Config.SPEED_MULTIPLIER = val end)
createSlider(PlayerCategory, "Max Boost Speed: ",  Config.MIN_MAX_SPEED, Config.MAX_MAX_SPEED, Config.MAX_BOOST_SPEED, 0, function(val) Config.MAX_BOOST_SPEED = val end)
createSlider(PlayerCategory, "Walk Speed: ",       Config.MIN_WALK, Config.MAX_WALK, Config.WalkSpeed, 0, function(val)
    Config.WalkSpeed = val
    applyPlayerModifiers()
end)
createSlider(PlayerCategory, "Jump Power: ",       Config.MIN_JUMP, Config.MAX_JUMP, Config.JumpPower, 0, function(val)
    Config.JumpPower = val
    applyPlayerModifiers()
end)

-- --- 3. DRIFT ---
local DriftCategory = createCategory("Drift", UDim2.new(0, 450, 0, 50))

driftButtons.AngleLabel = createLabel(DriftCategory, string.format("Angle: %.1f° | Side: Right", State.DriftAngle))

driftButtons.Toggle = createAction(DriftCategory, "Toggle Glitch [B]", function(btn)
    State.DriftGlitchActive = not State.DriftGlitchActive
    _G.DriftGlitchActive = State.DriftGlitchActive
    updateDriftUI()
end)

driftButtons.Platform = createAction(DriftCategory, "Platform Mode [P]", function(btn)
    togglePlatform()
end, false, COLORS.ButtonPlatform)

driftButtons.AutoDrift = createAction(DriftCategory, "AutoDrift [R]", function(btn)
    State.AutoDriftActive = not State.AutoDriftActive
    _G.AutoDriftActive = State.AutoDriftActive
    updateDriftUI()
end)

createAction(DriftCategory, "Side: Right -> Left [V]", function(btn)
    State.DriftSide = State.DriftSide * -1
    _G.DriftSide = State.DriftSide
    btn.Text = State.DriftSide == 1 and "Side: Right -> Left [V]" or "Side: Left -> Right [V]"
    updateDriftUI()
end)

createSlider(DriftCategory, "Drift Angle: ", Config.MIN_DRIFT_ANGLE, Config.MAX_DRIFT_ANGLE, State.DriftAngle, 0, function(val)
    State.DriftAngle = val
    _G.DriftAngle = val
    updateDriftUI()
end)

-- --- 4. SERVER ---
-- Based on .rbxlx analysis: all remotes live in ReplicatedStorage.Remotes
-- (NOT in ReplicatedStorage.Systems.* as the original script assumed!)
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)

local ServerCategory = createCategory("Server", UDim2.new(0, 650, 0, 50))
createAction(ServerCategory, "ServerSide AFK", function(btn)
    btn.Text = "Setting AFK..."
    pcall(function()
        -- CORRECTED: was Systems.Social.PlayerToggledAFK
        Remotes.PlayerToggledAFK:FireServer("Ping")
    end)
    task.wait(0.5)
    btn.Text = "ServerSide AFK"
end)
createAction(ServerCategory, "Server Exit Car", function(btn)
    btn.Text = "Exiting car..."
    pcall(function()
        -- CORRECTED: was Systems.Cars.ExitCar (also it's InvokeServer, not FireServer)
        Remotes.ExitCar:InvokeServer()
    end)
    task.wait(0.5)
    btn.Text = "Server Exit Car"
end)
createAction(ServerCategory, "Server Enter Car", function(btn)
    btn.Text = "Entering car..."
    pcall(function()
        Remotes.EnterCar:InvokeServer()
    end)
    task.wait(0.5)
    btn.Text = "Server Enter Car"
end)
createAction(ServerCategory, "Spawn My Car", function(btn)
    btn.Text = "Spawning..."
    pcall(function()
        Remotes.SpawnPlayerCar:InvokeServer()
    end)
    task.wait(0.5)
    btn.Text = "Spawn My Car"
end)
-- v3.1: Start Solo Race (uses real remote calls from Cobalt session)
-- Based on Cobalt recording: GetSoloRaceMenu -> ConfirmSoloRaceChoice("raceName", "myBest", true)
createAction(ServerCategory, "Start Solo Race (race name)", function(btn)
    btn.Text = "Starting..."
    print("[Neuro Hub] To start a solo race, set:")
    print("  getgenv().NeuroHubSoloRace = 'YellowObbyReverse'  -- or any race name")
    print("  Then press this button again")
    print("  Available races: YellowObbyReverse, YellowObby, WoodlandRally,")
    print("  WestCityCircuit, WaterfallRush, TunnelSprint, HighwayRampLoop, etc.")
    if getgenv and getgenv().NeuroHubSoloRace then
        local raceName = getgenv().NeuroHubSoloRace
        pcall(function()
            Remotes.GetSoloRaceMenu:InvokeServer(raceName, true)
            task.wait(0.3)
            Remotes.ConfirmSoloRaceChoice:FireServer(raceName, "myBest", true)
        end)
        SendNotification("Solo Race", "Started: " .. raceName, 4)
    else
        SendNotification("Solo Race", "Set getgenv().NeuroHubSoloRace first!", 5)
    end
    task.wait(1)
    btn.Text = "Start Solo Race"
end)
-- v3.1: Quick start common races
createAction(ServerCategory, "Start YellowObbyReverse", function(btn)
    btn.Text = "Starting..."
    pcall(function()
        Remotes.GetSoloRaceMenu:InvokeServer("YellowObbyReverse", true)
        task.wait(0.3)
        Remotes.ConfirmSoloRaceChoice:FireServer("YellowObbyReverse", "myBest", true)
    end)
    task.wait(0.5)
    btn.Text = "Start YellowObbyReverse"
end)
createAction(ServerCategory, "Start TunnelSprint", function(btn)
    btn.Text = "Starting..."
    pcall(function()
        Remotes.GetSoloRaceMenu:InvokeServer("TunnelSprint", true)
        task.wait(0.3)
        Remotes.ConfirmSoloRaceChoice:FireServer("TunnelSprint", "myBest", true)
    end)
    task.wait(0.5)
    btn.Text = "Start TunnelSprint"
end)
createAction(ServerCategory, "Teleport To Last CP", function(btn)
    btn.Text = "Teleporting..."
    pcall(function()
        Remotes.TeleportToLastCheckpoint:FireServer()
    end)
    task.wait(0.5)
    btn.Text = "Teleport To Last CP"
end)
-- v3.1: Force redeem (seen in Cobalt)
createAction(ServerCategory, "Force Redeem", function(btn)
    btn.Text = "Redeeming..."
    pcall(function()
        Remotes.ForceRedeem:InvokeServer()
    end)
    task.wait(0.5)
    btn.Text = "Force Redeem"
end)
createAction(ServerCategory, "Claim Daily Car", function(btn)
    btn.Text = "Claiming..."
    pcall(function()
        Remotes.ClaimDailyCar:InvokeServer()
    end)
    task.wait(0.5)
    btn.Text = "Claim Daily Car"
end)
createAction(ServerCategory, "Claim Playtime", function(btn)
    btn.Text = "Claiming..."
    pcall(function()
        Remotes.ClaimPlaytimeReward:InvokeServer()
    end)
    task.wait(0.5)
    btn.Text = "Claim Playtime"
end)
createAction(ServerCategory, "Claim Daily Gold", function(btn)
    btn.Text = "Claiming..."
    pcall(function()
        Remotes.ClaimDailyGold:InvokeServer()
    end)
    task.wait(0.5)
    btn.Text = "Claim Daily Gold"
end)
createAction(ServerCategory, "Redeem Promo Code", function(btn)
    btn.Text = "Enter code in console..."
    -- Prompt user via console
    local code = ""
    pcall(function()
        if getcustomasset then end
    end)
    print("[Neuro Hub] To redeem a promo code, run:")
    print("  getgenv().NeuroHub_PromoCode = 'YOUR_CODE'")
    print("  Then run: loadstring(game:HttpGet('https://your-url/promo.lua'))()")
    print("  OR use the Auto-Redeem toggle in Utils category")
    task.wait(2)
    btn.Text = "Redeem Promo Code"
end)
createAction(ServerCategory, "Safe Quit (Unload)", function() SafeQuit() end, true)

-- --- 5. INFO ---
local InfoCategory = createCategory("Info", UDim2.new(0, 850, 0, 50))

local SwitcherFrame = Instance.new("Frame")
SwitcherFrame.Size = UDim2.new(1, 0, 0, 30)
SwitcherFrame.BackgroundColor3 = COLORS.Header
SwitcherFrame.BorderSizePixel = 0
SwitcherFrame.Parent = InfoCategory

local PrevBtn = Instance.new("TextButton")
PrevBtn.Size = UDim2.new(0, 30, 1, 0)
PrevBtn.BackgroundColor3 = COLORS.Header
PrevBtn.BorderSizePixel = 0
PrevBtn.Text = "<"
PrevBtn.TextColor3 = COLORS.ButtonActive
PrevBtn.Font = Enum.Font.GothamBold
PrevBtn.TextSize = 16
PrevBtn.Parent = SwitcherFrame

local NextBtn = Instance.new("TextButton")
NextBtn.Size = UDim2.new(0, 30, 1, 0)
NextBtn.Position = UDim2.new(1, -30, 0, 0)
NextBtn.BackgroundColor3 = COLORS.Header
NextBtn.BorderSizePixel = 0
NextBtn.Text = ">"
NextBtn.TextColor3 = COLORS.ButtonActive
NextBtn.Font = Enum.Font.GothamBold
NextBtn.TextSize = 16
NextBtn.Parent = SwitcherFrame

local TargetNameLabel = Instance.new("TextLabel")
TargetNameLabel.Size = UDim2.new(1, -60, 1, 0)
TargetNameLabel.Position = UDim2.new(0, 30, 0, 0)
TargetNameLabel.BackgroundTransparency = 1
TargetNameLabel.Text = LocalPlayer.Name
TargetNameLabel.TextColor3 = COLORS.Text
TargetNameLabel.Font = Enum.Font.GothamBold
TargetNameLabel.TextSize = 12
TargetNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
TargetNameLabel.Parent = SwitcherFrame

local moneyLabel   = createLabel(InfoCategory, "Money: N/A")
local levelLabel   = createLabel(InfoCategory, "Level: N/A")
local airLabel     = createLabel(InfoCategory, "Air Score: N/A")
local driftLabel   = createLabel(InfoCategory, "Drift Score: N/A")
local auctionLabel = createLabel(InfoCategory, "Auction Earned: N/A")
local spentLabel   = createLabel(InfoCategory, "Spent: N/A")
local clubLabel    = createLabel(InfoCategory, "Club: N/A")
local statsLabel   = createLabel(InfoCategory, "Session: 0s | Races: 0")
local statusLabel  = createLabel(InfoCategory, "Active: none")
-- NEW in v3.0: expanded stats based on real PlayerData structure
local premiumLabel = createLabel(InfoCategory, "Premium: N/A")
local xpLabel      = createLabel(InfoCategory, "XP: N/A")
local winsLabel    = createLabel(InfoCategory, "Wins: N/A")
local racesLabel   = createLabel(InfoCategory, "Races: N/A")
local milesLabel   = createLabel(InfoCategory, "Miles: N/A")
local topspeedLabel= createLabel(InfoCategory, "Top Speed: N/A")
local earnedLabel  = createLabel(InfoCategory, "Earned Cash: N/A")
local carsLabel    = createLabel(InfoCategory, "Cars Owned: N/A")
local jobsLabel    = createLabel(InfoCategory, "Jobs Done: N/A")
local steelLabel   = createLabel(InfoCategory, "Steel: N/A")
local woodLabel    = createLabel(InfoCategory, "Wood: N/A")
local eventCurLabel= createLabel(InfoCategory, "Event Cur: N/A")
-- v3.1: Race state info
local raceStatusLabel   = createLabel(InfoCategory, "Race: not in race")
local raceProgressLabel = createLabel(InfoCategory, "CP Progress: 0/0")
local raceCPNameLabel   = createLabel(InfoCategory, "Next CP: none")
local raceStuckLabel    = createLabel(InfoCategory, "Stuck: 0s")

local targetPlayer = LocalPlayer
local function changePlayer(step)
    local plrs = Players:GetPlayers()
    if #plrs == 0 then return end
    local currentIndex = 1
    for i, p in ipairs(plrs) do
        if p == targetPlayer then currentIndex = i break end
    end
    currentIndex = currentIndex + step
    if currentIndex > #plrs then currentIndex = 1 end
    if currentIndex < 1 then currentIndex = #plrs end
    targetPlayer = plrs[currentIndex]
    TargetNameLabel.Text = targetPlayer.Name
    moneyLabel.Text = "Money: Loading..."
    levelLabel.Text = "Level: Loading..."
    airLabel.Text = "Air Score: Loading..."
    driftLabel.Text = "Drift Score: Loading..."
    auctionLabel.Text = "Auction Earned: Loading..."
    spentLabel.Text = "Spent: Loading..."
    clubLabel.Text = "Club: Loading..."
    premiumLabel.Text = "Premium: Loading..."
    xpLabel.Text = "XP: Loading..."
    winsLabel.Text = "Wins: Loading..."
    racesLabel.Text = "Races: Loading..."
    milesLabel.Text = "Miles: Loading..."
    topspeedLabel.Text = "Top Speed: Loading..."
    earnedLabel.Text = "Earned Cash: Loading..."
    carsLabel.Text = "Cars Owned: Loading..."
    jobsLabel.Text = "Jobs Done: Loading..."
    steelLabel.Text = "Steel: Loading..."
    woodLabel.Text = "Wood: Loading..."
    eventCurLabel.Text = "Event Cur: Loading..."
end

trackConn(PrevBtn.MouseButton1Click:Connect(function() changePlayer(-1) end))
trackConn(NextBtn.MouseButton1Click:Connect(function() changePlayer(1) end))

-- Info polling loop
task.spawn(function()
    while task.wait(1) do
        if not ScreenGui or not ScreenGui.Parent then break end
        if not targetPlayer or not targetPlayer.Parent then
            targetPlayer = LocalPlayer
            TargetNameLabel.Text = targetPlayer.Name
        end
        local pName = targetPlayer.Name
        local leaderstats = targetPlayer:FindFirstChild("leaderstats")
        if leaderstats then
            local cash = leaderstats:FindFirstChild("Cash")
            if cash then
                moneyLabel.Text = "Money: " .. tostring(cash.Value)
                -- Track cash earned (only for local player)
                if targetPlayer == LocalPlayer then
                    local cashVal = tonumber(cash.Value) or 0
                    if State.LastCash then
                        local delta = cashVal - State.LastCash
                        if delta > 0 then
                            State.CashEarned = State.CashEarned + delta
                            _G.CashEarned = State.CashEarned
                        end
                    end
                    State.LastCash = cashVal
                end
            else moneyLabel.Text = "Money: N/A" end
            local level = leaderstats:FindFirstChild("Level")
            if level then
                local lvlVal = tonumber(level.Value) or 0
                local extraText = lvlVal > 10 and " (> 10)" or " (<= 10)"
                levelLabel.Text = "Level: " .. tostring(lvlVal) .. extraText
            else levelLabel.Text = "Level: N/A" end
        else
            moneyLabel.Text = "Money: N/A"
            levelLabel.Text = "Level: N/A"
        end

        local playerDataFolder = ReplicatedStorage:FindFirstChild("PlayerData")
        if playerDataFolder then
            local myData = playerDataFolder:FindFirstChild(pName)
            if myData then
                local stats = myData:FindFirstChild("Stats")
                if stats then
                    local function getStat(name, label, prefix)
                        local s = stats:FindFirstChild(name)
                        if s then
                            local v = s.Value
                            if typeof(v) == "number" and v == math.floor(v) then
                                label.Text = (prefix or name) .. ": " .. tostring(v)
                            else
                                label.Text = (prefix or name) .. ": " .. string.format("%.2f", tonumber(v) or 0)
                            end
                        else
                            label.Text = (prefix or name) .. ": N/A"
                        end
                    end
                    getStat("AirScore", airLabel, "Air Score")
                    getStat("DriftScore", driftLabel, "Drift Score")
                    getStat("AuctionEarnings", auctionLabel, "Auction Earned")
                    getStat("SpentCash", spentLabel, "Spent")
                    getStat("Wins", winsLabel, "Wins")
                    getStat("Races", racesLabel, "Races")
                    getStat("MilesDriven", milesLabel, "Miles")
                    getStat("TopSpeed", topspeedLabel, "Top Speed")
                    getStat("EarnedCash", earnedLabel, "Earned Cash")
                    getStat("JobsCompleted", jobsLabel, "Jobs Done")
                else
                    airLabel.Text = "Air Score: N/A"
                    driftLabel.Text = "Drift Score: N/A"
                    auctionLabel.Text = "Auction Earned: N/A"
                    spentLabel.Text = "Spent: N/A"
                    winsLabel.Text = "Wins: N/A"
                    racesLabel.Text = "Races: N/A"
                    milesLabel.Text = "Miles: N/A"
                    topspeedLabel.Text = "Top Speed: N/A"
                    earnedLabel.Text = "Earned Cash: N/A"
                    jobsLabel.Text = "Jobs Done: N/A"
                end

                -- NEW: Premium currency, XP, Steel, Wood, EventCurrency (top-level on PlayerData)
                local function getTopVal(name, label, prefix)
                    local v = myData:FindFirstChild(name)
                    if v then
                        label.Text = (prefix or name) .. ": " .. tostring(v.Value)
                    else
                        label.Text = (prefix or name) .. ": N/A"
                    end
                end
                getTopVal("PremiumCurrency", premiumLabel, "Premium")
                getTopVal("XP", xpLabel, "XP")
                getTopVal("Steel", steelLabel, "Steel")
                getTopVal("Wood", woodLabel, "Wood")
                getTopVal("EventCurrency", eventCurLabel, "Event Cur")

                local club = myData:FindFirstChild("ClubTag")
                if club then clubLabel.Text = "Club: " .. tostring(club.Value) else clubLabel.Text = "Club: N/A" end

                -- NEW: Count cars owned
                local inv = myData:FindFirstChild("Inventory")
                if inv then
                    local carsInv = inv:FindFirstChild("Cars")
                    if carsInv then
                        carsLabel.Text = "Cars Owned: " .. #carsInv:GetChildren()
                    else
                        carsLabel.Text = "Cars Owned: N/A"
                    end
                else
                    carsLabel.Text = "Cars Owned: N/A"
                end
            else
                airLabel.Text = "Air Score: N/A"
                driftLabel.Text = "Drift Score: N/A"
                auctionLabel.Text = "Auction Earned: N/A"
                spentLabel.Text = "Spent: N/A"
                clubLabel.Text = "Club: N/A"
                premiumLabel.Text = "Premium: N/A"
                xpLabel.Text = "XP: N/A"
                winsLabel.Text = "Wins: N/A"
                racesLabel.Text = "Races: N/A"
                milesLabel.Text = "Miles: N/A"
                topspeedLabel.Text = "Top Speed: N/A"
                earnedLabel.Text = "Earned Cash: N/A"
                carsLabel.Text = "Cars Owned: N/A"
                jobsLabel.Text = "Jobs Done: N/A"
                steelLabel.Text = "Steel: N/A"
                woodLabel.Text = "Wood: N/A"
                eventCurLabel.Text = "Event Cur: N/A"
            end
        end

        -- Session stats
        local sessionTime = os.time() - State.StartTime
        local mins = math.floor(sessionTime / 60)
        local secs = sessionTime % 60
        statsLabel.Text = string.format("Session: %dm %ds | Races: %d", mins, secs, State.RacesWon)

        -- Active features status
        local active = {}
        if State.SmartRaceEnabled then table.insert(active, "SR") end
        if State.AutoCheckpointEnabled then table.insert(active, "CP") end
        if State.AutoFlyEnabled then table.insert(active, "Fly") end
        if State.FarmPatchEnabled then table.insert(active, "Farm") end
        if State.NoclipEnabled then table.insert(active, "NC") end
        if State.SpeedBoostEnabled then table.insert(active, "SB") end
        if State.DriftGlitchActive then table.insert(active, "Drift") end
        if State.AntiAFKEnabled then table.insert(active, "AFK") end
        statusLabel.Text = "Active: " .. (#active > 0 and table.concat(active, ", ") or "none")

        -- v3.1: Race state info
        if State.IsInRace and State.CurrentRaceName ~= "" then
            raceStatusLabel.Text = "Race: " .. State.CurrentRaceName
            raceProgressLabel.Text = string.format("CP Progress: %d/%d",
                State.CurrentCPIndex, State.TotalCheckpoints)
            raceCPNameLabel.Text = "Next CP: " .. (State.LastCPName or "none")

            local stuckSec = math.floor(os.clock() - State.LastCPTime)
            raceStuckLabel.Text = "Stuck: " .. stuckSec .. "s"
        else
            raceStatusLabel.Text = "Race: not in race"
            raceProgressLabel.Text = "CP Progress: 0/0"
            raceCPNameLabel.Text = "Next CP: none"
            raceStuckLabel.Text = "Stuck: 0s"
        end
    end
end)

-- --- 6. BINDABLES ---
local BindsCategory = createCategory("Bindables", UDim2.new(0, 1050, 0, 50))

createKeybind(BindsCategory, "Fast Stop",         "FastStop")
createKeybind(BindsCategory, "Go Up",             "GoUp")
createKeybind(BindsCategory, "Go Down",           "GoDown")
createKeybind(BindsCategory, "Momental Boost",    "InstaBoost")
createKeybind(BindsCategory, "Toggle SmartRace",  "ToggleSmartRace")
createKeybind(BindsCategory, "Toggle AutoCP",     "ToggleAutoCP")
createKeybind(BindsCategory, "Toggle Noclip",     "ToggleNoclip")
createKeybind(BindsCategory, "Toggle GUI",        "ToggleGUI")

createSlider(BindsCategory, "Shift Amount: ", 1, 100,   Config.SHIFT_AMOUNT,    0, function(val) Config.SHIFT_AMOUNT = val end)
createSlider(BindsCategory, "Insta Boost: ",  100, 5000, Config.INSTA_BOOST_SPEED, 0, function(val) Config.INSTA_BOOST_SPEED = val end)

-- --- 7. NOTIFICATIONS ---
local NotifCategory = createCategory("Notifications", UDim2.new(0, 1250, 0, 50))

createToggle(NotifCategory, "Notify Winner",      State.NotifyWinner,     function(s) State.NotifyWinner = s; _G.NotifyWinner = s end)
createToggle(NotifCategory, "Notify Leaderboard", State.NotifyLeaderboard, function(s) State.NotifyLeaderboard = s; _G.NotifyLeaderboard = s end)
createToggle(NotifCategory, "Notify SpeedTrap",   State.NotifySpeedTrap,  function(s) State.NotifySpeedTrap = s; _G.NotifySpeedTrap = s end)
createToggle(NotifCategory, "Notify Guild",       State.NotifyGuild,      function(s) State.NotifyGuild = s; _G.NotifyGuild = s end)
createToggle(NotifCategory, "Notify Auction",     true,  function(s) State.NotifyAuction = s end)
createToggle(NotifCategory, "Notify Tickets",     true,  function(s) State.NotifyTickets = s end)
createToggle(NotifCategory, "Notify Hotspot",     true,  function(s) State.NotifyHotspot = s end)
createToggle(NotifCategory, "Notify Garage",      true,  function(s) State.NotifyGarage = s end)

-- --- 8. AUTO (new in v3.0 - based on real RemoteEvents) ---
local AutoCategory = createCategory("Auto", UDim2.new(0, 1450, 0, 50))

-- Auto-claim loop state
local autoClaimLoops = {
    dailyCar = false,
    playtime = false,
    dailyGold = false,
    hotspot = false,
    tasks = false,
    promoCodes = false,
}

-- Auto-Claim Daily Car
createToggle(AutoCategory, "Auto Daily Car", false, function(state)
    autoClaimLoops.dailyCar = state
    if state then
        task.spawn(function()
            while autoClaimLoops.dailyCar do
                pcall(function() Remotes.ClaimDailyCar:InvokeServer() end)
                task.wait(3600)  -- check every hour
            end
        end)
        SendNotification("Auto Daily Car", "Will attempt to claim every hour", 4)
    end
end)

-- Auto-Claim Playtime Reward
createToggle(AutoCategory, "Auto Playtime", false, function(state)
    autoClaimLoops.playtime = state
    if state then
        task.spawn(function()
            while autoClaimLoops.playtime do
                pcall(function() Remotes.ClaimPlaytimeReward:InvokeServer() end)
                task.wait(300)  -- every 5 min
            end
        end)
        SendNotification("Auto Playtime", "Will claim every 5 min", 4)
    end
end)

-- Auto-Claim Daily Gold (DrivePlus subscription reward)
createToggle(AutoCategory, "Auto Daily Gold", false, function(state)
    autoClaimLoops.dailyGold = state
    if state then
        task.spawn(function()
            while autoClaimLoops.dailyGold do
                pcall(function() Remotes.ClaimDailyGold:InvokeServer() end)
                task.wait(3600)  -- every hour
            end
        end)
    end
end)

-- Auto-Hotspot join
createToggle(AutoCategory, "Auto Hotspot", false, function(state)
    autoClaimLoops.hotspot = state
    if state then
        task.spawn(function()
            while autoClaimLoops.hotspot do
                pcall(function() Remotes.HotspotGo:FireServer() end)
                pcall(function() Remotes.ClaimReward:FireServer() end)
                task.wait(10)  -- every 10 sec
            end
        end)
        SendNotification("Auto Hotspot", "Joining & claiming hotspot rewards", 4)
    end
end)

-- Auto-claim Tasks
createToggle(AutoCategory, "Auto Tasks Claim", false, function(state)
    autoClaimLoops.tasks = state
    if state then
        task.spawn(function()
            while autoClaimLoops.tasks do
                pcall(function() Remotes.TasksClaim:InvokeServer() end)
                task.wait(60)  -- every minute
            end
        end)
    end
end)

-- Auto-Redeem Promo Codes from list
local promoCodesList = {"RELEASE", "DRIVEWORLD", "TWITTER", "DISCORD", "SUB2BLOX", "FREEMONEY"}
createToggle(AutoCategory, "Auto Redeem Codes", false, function(state)
    autoClaimLoops.promoCodes = state
    if state then
        task.spawn(function()
            while autoClaimLoops.promoCodes do
                for _, code in ipairs(promoCodesList) do
                    pcall(function() Remotes.PromoClaim:InvokeServer(code) end)
                    task.wait(1)
                end
                task.wait(600)  -- retry every 10 min
            end
        end)
        SendNotification("Auto Codes", "Trying " .. #promoCodesList .. " codes every 10 min", 4)
    end
end)

-- Auto-Buy Garage (loops through garage names)
createAction(AutoCategory, "Try Buy Garage", function(btn)
    btn.Text = "Trying..."
    pcall(function()
        Remotes.BuyGarage:InvokeServer()
    end)
    task.wait(1)
    btn.Text = "Try Buy Garage"
end)

-- Auto-Sell duplicate cars
createAction(AutoCategory, "Sell Duplicate Cars", function(btn)
    btn.Text = "Selling..."
    local playerData = ReplicatedStorage:FindFirstChild("PlayerData")
    if playerData then
        local myData = playerData:FindFirstChild(LocalPlayer.Name)
        if myData then
            local inv = myData:FindFirstChild("Inventory")
            if inv then
                local cars = inv:FindFirstChild("Cars")
                if cars then
                    local seen = {}
                    local sold = 0
                    for _, carFolder in ipairs(cars:GetChildren()) do
                        local carName = carFolder.Name
                        if seen[carName] then
                            -- duplicate! try to sell
                            local id = carFolder:FindFirstChild("Id")
                            if id then
                                pcall(function() Remotes.SellCar:InvokeServer(id.Value) end)
                                sold = sold + 1
                                task.wait(0.5)
                            end
                        else
                            seen[carName] = true
                        end
                    end
                    SendNotification("Sell Dupes", "Sold " .. sold .. " duplicate cars", 5)
                end
            end
        end
    end
    btn.Text = "Sell Duplicate Cars"
end)

-- Donate to Gold Vault
createAction(AutoCategory, "Donate 1000 to Vault", function(btn)
    btn.Text = "Donating..."
    pcall(function()
        Remotes.DonateToVault:InvokeServer(1000)
    end)
    task.wait(1)
    btn.Text = "Donate 1000 to Vault"
end)

-- Purchase Earnings Boost
createAction(AutoCategory, "Buy Earnings Boost", function(btn)
    btn.Text = "Buying..."
    pcall(function()
        Remotes.PurchaseEarningsBoost:InvokeServer()
    end)
    task.wait(1)
    btn.Text = "Buy Earnings Boost"
end)

-- Auto-Buy upgrades loop
local autoUpgradeLoop = false
createToggle(AutoCategory, "Auto Buy Upgrades", false, function(state)
    autoUpgradeLoop = state
    if state then
        task.spawn(function()
            while autoUpgradeLoop do
                pcall(function() Remotes.PurchaseUpgrade:InvokeServer() end)
                task.wait(5)
            end
        end)
    end
end)

-- --- 9. TELEPORT (new in v3.0) ---
local TeleportCategory = createCategory("Teleport", UDim2.new(0, 1650, 0, 50))

-- Teleport to random race
createAction(TeleportCategory, "TP to Nearest Race", function(btn)
    btn.Text = "Teleporting..."
    local races = workspace:FindFirstChild("Races")
    if races then
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local hrp = char.HumanoidRootPart
            local bestRace, bestDist = nil, math.huge
            for _, race in ipairs(races:GetChildren()) do
                local spawns = race:FindFirstChild("Spawns")
                if spawns then
                    local firstSpawn = spawns:FindFirstChildOfClass("Model") or spawns:FindFirstChildWhichIsA("BasePart")
                    if firstSpawn then
                        local pos = firstSpawn:IsA("Model") and firstSpawn:GetPivot().Position or firstSpawn.Position
                        local dist = (pos - hrp.Position).Magnitude
                        if dist < bestDist then
                            bestDist = dist
                            bestRace = race
                        end
                    end
                end
            end
            if bestRace then
                local spawns = bestRace:FindFirstChild("Spawns")
                local firstSpawn = spawns:FindFirstChildOfClass("Model") or spawns:FindFirstChildWhichIsA("BasePart")
                if firstSpawn then
                    local pos = firstSpawn:IsA("Model") and firstSpawn:GetPivot().Position or firstSpawn.Position
                    pcall(function()
                        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 5, 0))
                    end)
                    SendNotification("Teleport", "Teleported to " .. bestRace.Name, 3)
                end
            end
        end
    end
    task.wait(0.5)
    btn.Text = "TP to Nearest Race"
end)

-- Teleport to Garage
createAction(TeleportCategory, "TP to My Garage", function(btn)
    btn.Text = "Teleporting..."
    local garages = workspace:FindFirstChild("Garages")
    if garages then
        local myGarage = garages:FindFirstChild(LocalPlayer.Name)
        if myGarage then
            local char = LocalPlayer.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                local hrp = char.HumanoidRootPart
                -- Find a spawn point in garage
                local spawn = myGarage:FindFirstChild("SpawnLocation") or myGarage:FindFirstChildWhichIsA("BasePart")
                if spawn then
                    pcall(function()
                        hrp.CFrame = CFrame.new(spawn.Position + Vector3.new(0, 5, 0))
                    end)
                    SendNotification("Teleport", "Teleported to your garage", 3)
                end
            end
        else
            SendNotification("Teleport", "You don't own a garage", 3)
        end
    end
    task.wait(0.5)
    btn.Text = "TP to My Garage"
end)

-- Teleport to Car Spawn
createAction(TeleportCategory, "TP to My Car", function(btn)
    btn.Text = "Teleporting..."
    local car = getMyCar()
    if car then
        local root = car.PrimaryPart or car:FindFirstChild("Main") or car:FindFirstChildWhichIsA("BasePart")
        local char = LocalPlayer.Character
        if root and char and char:FindFirstChild("HumanoidRootPart") then
            pcall(function()
                char.HumanoidRootPart.CFrame = root.CFrame + Vector3.new(0, 5, 0)
            end)
            SendNotification("Teleport", "Teleported to your car", 3)
        end
    else
        -- Spawn car first
        pcall(function() Remotes.SpawnPlayerCar:InvokeServer() end)
        task.wait(1)
        local newCar = getMyCar()
        if newCar then
            local root = newCar.PrimaryPart or newCar:FindFirstChild("Main") or newCar:FindFirstChildWhichIsA("BasePart")
            local char = LocalPlayer.Character
            if root and char and char:FindFirstChild("HumanoidRootPart") then
                pcall(function()
                    char.HumanoidRootPart.CFrame = root.CFrame + Vector3.new(0, 5, 0)
                end)
                SendNotification("Teleport", "Spawned & teleported to your car", 3)
            end
        else
            SendNotification("Teleport", "Could not find/spawn car", 3)
        end
    end
    task.wait(0.5)
    btn.Text = "TP to My Car"
end)

-- Teleport to Waypoint (map marker)
createAction(TeleportCategory, "TP to Waypoint", function(btn)
    teleportToWaypoint()
end)

-- --- 10. UTILS ---
local UtilsCategory = createCategory("Utils", UDim2.new(0, 1850, 0, 50))

createAction(UtilsCategory, "Teleport to Waypoint", function(btn)
    teleportToWaypoint()
end)

createAction(UtilsCategory, "Save Position", function(btn)
    local root = getRootPart()
    if root then
        State.SavedPos = root.CFrame
        SendNotification("Position", "Saved!", 3)
    else
        SendNotification("Position", "No root part found.", 3)
    end
end)

createAction(UtilsCategory, "Load Position", function(btn)
    if State.SavedPos then
        local root = getRootPart()
        if root then
            pcall(function() root.CFrame = State.SavedPos end)
            SendNotification("Position", "Loaded!", 3)
        end
    else
        SendNotification("Position", "No saved position.", 3)
    end
end)

createAction(UtilsCategory, "Minimize All", function(btn)
    for _, cat in ipairs(categoryFrames) do
        cat.content.Visible = false
    end
    btn.Text = "Restore All"
    btn.MouseButton1Click:Once(function()
        for _, cat in ipairs(categoryFrames) do
            cat.content.Visible = true
        end
        btn.Text = "Minimize All"
    end)
end)

-- Theme switcher
local themeFrame = Instance.new("Frame")
themeFrame.Size = UDim2.new(1, 0, 0, 30)
themeFrame.BackgroundColor3 = COLORS.Header
themeFrame.BorderSizePixel = 0
themeFrame.Parent = UtilsCategory

local themeLabel = Instance.new("TextLabel")
themeLabel.Size = UDim2.new(0.4, 0, 1, 0)
themeLabel.BackgroundTransparency = 1
themeLabel.Text = "Theme:"
themeLabel.TextColor3 = COLORS.Text
themeLabel.Font = Enum.Font.Gotham
themeLabel.TextSize = 12
themeLabel.TextXAlignment = Enum.TextXAlignment.Left
themeLabel.Position = UDim2.new(0, 5, 0, 0)
themeLabel.Parent = themeFrame

local themeDropdown = Instance.new("TextButton")
themeDropdown.Size = UDim2.new(0.6, -10, 0, 25)
themeDropdown.Position = UDim2.new(0.4, 5, 0, 2)
themeDropdown.BackgroundColor3 = COLORS.ButtonNormal
themeDropdown.BorderSizePixel = 0
themeDropdown.Text = Config.Theme
themeDropdown.TextColor3 = COLORS.ButtonActive
themeDropdown.Font = Enum.Font.GothamBold
themeDropdown.TextSize = 12
themeDropdown.Parent = themeFrame

local themesList = {"Dark", "Midnight", "Amoled"}
local themeIndex = 1
for i, t in ipairs(themesList) do
    if t == Config.Theme then themeIndex = i break end
end

trackConn(themeDropdown.MouseButton1Click:Connect(function()
    themeIndex = themeIndex + 1
    if themeIndex > #themesList then themeIndex = 1 end
    local newTheme = themesList[themeIndex]
    applyTheme(newTheme)
    themeDropdown.Text = newTheme
    SendNotification("Theme", "Switched to " .. newTheme .. ". Reload script to apply fully.", 4)
    saveSettings()
end))

-- Language switcher
local langFrame = Instance.new("Frame")
langFrame.Size = UDim2.new(1, 0, 0, 30)
langFrame.BackgroundColor3 = COLORS.Header
langFrame.BorderSizePixel = 0
langFrame.Parent = UtilsCategory

local langLabel = Instance.new("TextLabel")
langLabel.Size = UDim2.new(0.4, 0, 1, 0)
langLabel.BackgroundTransparency = 1
langLabel.Text = "Language:"
langLabel.TextColor3 = COLORS.Text
langLabel.Font = Enum.Font.Gotham
langLabel.TextSize = 12
langLabel.TextXAlignment = Enum.TextXAlignment.Left
langLabel.Position = UDim2.new(0, 5, 0, 0)
langLabel.Parent = langFrame

local langBtn = Instance.new("TextButton")
langBtn.Size = UDim2.new(0.6, -10, 0, 25)
langBtn.Position = UDim2.new(0.4, 5, 0, 2)
langBtn.BackgroundColor3 = COLORS.ButtonNormal
langBtn.BorderSizePixel = 0
langBtn.Text = Config.Language
langBtn.TextColor3 = COLORS.ButtonActive
langBtn.Font = Enum.Font.GothamBold
langBtn.TextSize = 12
langBtn.Parent = langFrame

trackConn(langBtn.MouseButton1Click:Connect(function()
    Config.Language = Config.Language == "RU" and "EN" or "RU"
    langBtn.Text = Config.Language
    saveSettings()
    SendNotification("Language", "Switched to " .. Config.Language .. ". Reload to apply.", 3)
end))

-- ============================================================
--  NOTIFICATION EVENT HANDLERS
--  CORRECTED: All remotes are in ReplicatedStorage.Remotes (not Systems.*)
-- ============================================================
local RemotesNotify = ReplicatedStorage:WaitForChild("Remotes", 5)

if RemotesNotify then
    -- Race Winner broadcast
    local R_Winner = RemotesNotify:FindFirstChild("BroadcastWinner")
    if R_Winner then
        trackConn(R_Winner.OnClientEvent:Connect(function(plr, time, raceLoc)
            if not State.NotifyWinner then return end
            local pName = typeof(plr) == "Instance" and plr.Name or tostring(plr)
            local rName = typeof(raceLoc) == "Instance" and raceLoc.Name or tostring(raceLoc)
            local formatTime = string.format("%.2f", tonumber(time) or 0)
            SendNotification("Race Winner!", pName.." won on "..rName.."\nTime: "..formatTime.."s", 6)
            if plr == LocalPlayer or pName == LocalPlayer.Name then
                State.RacesWon = State.RacesWon + 1
                _G.RacesWon = State.RacesWon
            end
        end))
    end

    -- Daily Races Leaderboard update
    local R_Leaderboard = RemotesNotify:FindFirstChild("LeaderboardUpdated")
    if R_Leaderboard then
        trackConn(R_Leaderboard.OnClientEvent:Connect(function(...)
            if not State.NotifyLeaderboard then return end
            SendNotification("Leaderboard", "Daily Races Leaderboard has been updated!", 5)
            print("[Neuro Hub - LeaderboardUpdated]")
            local args = {...}
            for i, v in ipairs(args) do print("Arg " .. tostring(i) .. ":", v) end
        end))
    end

    -- Speed Trap camera snap
    local R_SpeedTrap = RemotesNotify:FindFirstChild("CameraSnapped")
    if R_SpeedTrap then
        trackConn(R_SpeedTrap.OnClientEvent:Connect(function(...)
            if State.NotifySpeedTrap then SendNotification("Speed Trap", "Camera Snapped!", 4) end
        end))
    end

    -- Guild/Club updates
    local R_Guild = RemotesNotify:FindFirstChild("Update")
    if R_Guild then
        trackConn(R_Guild.OnClientEvent:Connect(function(data)
            if not State.NotifyGuild then return end
            SendNotification("Club Updated", "Guild data was updated! Check Console (F9)", 5)
            print("[Neuro Hub - GuildUpdate]")
            if type(data) == "table" then
                print("CanMembersInvite:", tostring(data.CanMembersInvite))
                print("PublicallyJoinable:", tostring(data.PublicallyJoinable))
                print("Owner (UserID):", tostring(data.Owner))
                print("Members:")
                if type(data.Members) == "table" then
                    for k, v in pairs(data.Members) do print("  ["..tostring(k).."] = ", v) end
                end
            else
                print("Data:", data)
            end
        end))
    end

    -- NEW: Listen for CurrencyEarned (track cash gains in real-time)
    local R_Currency = RemotesNotify:FindFirstChild("CurrencyEarned")
    if R_Currency then
        trackConn(R_Currency.OnClientEvent:Connect(function(...)
            local args = {...}
            if #args > 0 then
                local amount = tonumber(args[1]) or 0
                if amount > 0 then
                    State.CashEarned = State.CashEarned + amount
                    _G.CashEarned = State.CashEarned
                end
            end
        end))
    end

    -- NEW: Listen for RaceBegan (auto-track race starts)
    local R_RaceBegan = RemotesNotify:FindFirstChild("RaceBegan")
    if R_RaceBegan then
        trackConn(R_RaceBegan.OnClientEvent:Connect(function(...)
            if State.NotifyWinner then
                SendNotification("Race Started", "A race has begun!", 3)
            end
        end))
    end

    -- NEW: Listen for RaceEnded
    local R_RaceEnded = RemotesNotify:FindFirstChild("RaceEnded")
    if R_RaceEnded then
        trackConn(R_RaceEnded.OnClientEvent:Connect(function(...)
            print("[Neuro Hub - RaceEnded]", ...)
        end))
    end

    -- NEW: Listen for Auction events
    local R_AuctionCompleted = RemotesNotify:FindFirstChild("AuctionCompleted")
    if R_AuctionCompleted then
        trackConn(R_AuctionCompleted.OnClientEvent:Connect(function(...)
            SendNotification("Auction", "An auction was completed!", 4)
        end))
    end

    -- NEW: Listen for TicketsEarned (BattlePass)
    local R_Tickets = RemotesNotify:FindFirstChild("TicketsEarned")
    if R_Tickets then
        trackConn(R_Tickets.OnClientEvent:Connect(function(...)
            local args = {...}
            local amount = tonumber(args[1]) or 0
            if amount > 0 then
                SendNotification("Tickets Earned!", "+" .. amount .. " BattlePass tickets", 4)
            end
        end))
    end

    -- NEW: Listen for GarageInviteReceived
    local R_GarageInvite = RemotesNotify:FindFirstChild("GarageInviteReceived")
    if R_GarageInvite then
        trackConn(R_GarageInvite.OnClientEvent:Connect(function(...)
            SendNotification("Garage Invite", "You received a garage invite!", 5)
        end))
    end

    -- NEW: Listen for Hotspot events
    local R_HotspotGo = RemotesNotify:FindFirstChild("HotspotGo")
    if R_HotspotGo then
        trackConn(R_HotspotGo.OnClientEvent:Connect(function(...)
            SendNotification("Hotspot", "Hotspot event started! Join now!", 5)
        end))
    end
end

-- ============================================================
--  v3.1: RACE STATE LISTENERS
--  Listen for RaceBegan / RaceEnded / RaceCheckpoint events to track state
--  Listen for TrackCarFlipped to auto-upright the car
-- ============================================================

-- Listen for RaceBegan
local R_RaceBegan = RemotesNotify and RemotesNotify:FindFirstChild("RaceBegan")
if R_RaceBegan then
    trackConn(R_RaceBegan.OnClientEvent:Connect(function(raceData)
        pcall(function()
            if type(raceData) == "table" then
                local race = raceData.race
                local raceName = raceData.raceName
                local carName = raceData.carName
                local startCP = raceData.checkpoint or 0

                State.CurrentRace = race
                State.CurrentRaceName = raceName or (race and race.Name) or ""
                State.CurrentCPIndex = startCP
                State.IsInRace = true
                State.LastCPTime = os.clock()

                -- Reset cache so findBestCheckpoint refreshes
                cpCache.target = nil
                cpCache.race = nil
                cpCache.progress = -1

                SendNotification("Race Started",
                    "Race: " .. (raceName or "?") .. "\n" ..
                    "Car: " .. (carName or "?") .. "\n" ..
                    "Start CP: " .. tostring(startCP), 5)
            end
        end)
    end))
end

-- Listen for RaceEnded
local R_RaceEnded = RemotesNotify and RemotesNotify:FindFirstChild("RaceEnded")
if R_RaceEnded then
    trackConn(R_RaceEnded.OnClientEvent:Connect(function(raceData, payout)
        pcall(function()
            local raceName = ""
            local totalSpeed = 0
            local prizeXP = 0
            local finished = false

            if type(raceData) == "table" then
                raceName = raceData.raceName or ""
                totalSpeed = raceData.totalSpeed or 0
                prizeXP = raceData.prizeXP or 0
                finished = raceData.finished or false
            end

            State.IsInRace = false
            State.CurrentRace = nil
            State.CurrentRaceName = ""

            -- Track wins
            if finished then
                State.RacesWon = State.RacesWon + 1
                _G.RacesWon = State.RacesWon
            end

            local msg = "Race: " .. raceName .. "\n"
            msg = msg .. "Speed: " .. string.format("%.1f", totalSpeed) .. "\n"
            msg = msg .. "XP: +" .. tostring(prizeXP) .. "\n"
            msg = msg .. (finished and "FINISHED!" or "DNF")

            SendNotification("Race Ended", msg, 6)
        end)
    end))
end

-- Listen for RaceCheckpoint - track CP progress
local R_RaceCheckpoint = RemotesNotify and RemotesNotify:FindFirstChild("RaceCheckpoint")
if R_RaceCheckpoint then
    -- RaceCheckpoint is FireServer (outgoing), so we can't listen directly
    -- But we can monitor the player's racer folder for changes
    -- Or hook the remote via metatable spoof (too risky)
    -- Instead, poll racerFolder periodically in a thread
end

-- Poll race state every 0.5s to detect CP changes
task.spawn(function()
    while task.wait(0.5) do
        if not ScreenGui or not ScreenGui.Parent then break end
        pcall(function()
            local race, racerFolder = findActiveRace()
            if race and racerFolder then
                local newProgress = getPlayerCPProgress(racerFolder)
                if newProgress ~= State.CurrentCPIndex then
                    -- CP changed!
                    State.LastCPTime = os.clock()
                    local oldIdx = State.CurrentCPIndex
                    State.CurrentCPIndex = newProgress
                    State.CurrentRace = race
                    State.CurrentRaceName = race.Name
                    State.IsInRace = true

                    -- Reset cache to find next CP
                    cpCache.target = nil
                    cpCache.progress = -1

                    print(string.format("[Neuro Hub] CP progress: %d -> %d (race=%s)",
                        oldIdx, newProgress, race.Name))
                end
            else
                if State.IsInRace then
                    -- We were in a race but not anymore
                    State.IsInRace = false
                end
            end
        end)
    end
end)

-- v3.1: Auto-upright car when flipped
-- Listen for TrackCarFlipped event - if our car flips, auto-correct
local R_TrackCarFlipped = RemotesNotify and RemotesNotify:FindFirstChild("TrackCarFlipped")
if R_TrackCarFlipped then
    trackConn(R_TrackCarFlipped.OnClientEvent:Connect(function(...)
        if not State.AutoUprightCar then return end
        pcall(function()
            task.wait(0.5)
            local car = getMyCar()
            if car then
                local root = car.PrimaryPart or car:FindFirstChild("Main") or car:FindFirstChildWhichIsA("BasePart")
                if root then
                    -- Check if car is upside down (UpVector pointing down)
                    local up = root.CFrame.UpVector
                    if up.Y < 0.3 then
                        -- Car is flipped - rotate it upright
                        local pos = root.Position
                        local newPos = pos + Vector3.new(0, 5, 0)
                        pcall(function()
                            car:PivotTo(CFrame.new(newPos) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0))
                            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                        end)
                        SendNotification("Auto-Upright", "Car was flipped - auto-corrected!", 3)
                    end
                end
            end
        end)
    end))
end

-- v3.1: Auto-skip stuck race
-- If we haven't progressed in AutoSkipStuckTime seconds, fire TeleportToLastCheckpoint
task.spawn(function()
    while task.wait(2) do
        if not ScreenGui or not ScreenGui.Parent then break end
        if not State.IsInRace then continue end
        if not (State.SmartRaceEnabled or State.AutoCheckpointEnabled) then continue end

        local stuckTime = os.clock() - State.LastCPTime
        if stuckTime > State.AutoSkipStuckTime then
            -- We're stuck! Try teleporting to last CP
            pcall(function()
                Remotes.TeleportToLastCheckpoint:FireServer()
            end)
            State.LastCPTime = os.clock()  -- reset to avoid spam
            SendNotification("Auto-Skip", "Stuck for " .. tostring(State.AutoSkipStuckTime) ..
                "s - teleporting to last CP", 4)
        end
    end
end)

-- ============================================================
--  GLOBAL INPUT HANDLER
-- ============================================================
trackConn(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    -- Keybind capture mode
    if currentlyBinding then
        if input.KeyCode == Enum.KeyCode.Escape then
            currentlyBinding = nil
            return
        end
        if input.KeyCode ~= Enum.KeyCode.Unknown then
            Binds[currentlyBinding].Key = input.KeyCode
            if Binds[currentlyBinding].Btn then
                Binds[currentlyBinding].Btn.Text = input.KeyCode.Name
            end
            currentlyBinding = nil
            saveSettings()
        end
        return
    end

    -- GUI hide/show via Ctrl (legacy)
    if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
        if ScreenGui then ScreenGui.Enabled = not ScreenGui.Enabled end
        return
    end

    if gameProcessed then return end

    local keyCode = input.KeyCode

    -- Custom keybinds
    if Binds.ToggleGUI.Enabled and keyCode == Binds.ToggleGUI.Key then
        if ScreenGui then ScreenGui.Enabled = not ScreenGui.Enabled end
        return
    end

    if Binds.FastStop.Enabled and keyCode == Binds.FastStop.Key then
        local root = getRootPart()
        if root then
            pcall(function()
                root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end)
        end
    end

    if Binds.GoUp.Enabled and keyCode == Binds.GoUp.Key then
        local root = getRootPart()
        if root then
            pcall(function() root.CFrame = root.CFrame + Vector3.new(0, Config.SHIFT_AMOUNT, 0) end)
        end
    end

    if Binds.GoDown.Enabled and keyCode == Binds.GoDown.Key then
        local root = getRootPart()
        if root then
            pcall(function() root.CFrame = root.CFrame - Vector3.new(0, Config.SHIFT_AMOUNT, 0) end)
        end
    end

    if Binds.InstaBoost.Enabled and keyCode == Binds.InstaBoost.Key then
        local root = getRootPart()
        if root then
            pcall(function() root.AssemblyLinearVelocity = root.CFrame.LookVector * Config.INSTA_BOOST_SPEED end)
        end
    end

    if Binds.ToggleSmartRace.Enabled and keyCode == Binds.ToggleSmartRace.Key then
        local newState = not State.SmartRaceEnabled
        if newState then PlaySound(SFX.Toggle, 1) end
        toggleSmartRaceLogic(newState)
    end

    if Binds.ToggleAutoCP.Enabled and keyCode == Binds.ToggleAutoCP.Key then
        local newState = not State.AutoCheckpointEnabled
        if newState then PlaySound(SFX.Toggle, 1) end
        toggleAutoCPLogic(newState)
    end

    if Binds.ToggleNoclip.Enabled and keyCode == Binds.ToggleNoclip.Key then
        local newState = not State.NoclipEnabled
        if newState then PlaySound(SFX.Toggle, 1) end
        toggleNoclipLogic(newState)
    end

    -- DriftGlitch hotkeys (FIXED: Z was conflicting with SmartRace toggle, now B)
    if keyCode == Enum.KeyCode.B then
        State.DriftGlitchActive = not State.DriftGlitchActive
        _G.DriftGlitchActive = State.DriftGlitchActive
        updateDriftUI()
    elseif keyCode == Enum.KeyCode.P then
        togglePlatform()
    elseif keyCode == Enum.KeyCode.R then
        State.AutoDriftActive = not State.AutoDriftActive
        _G.AutoDriftActive = State.AutoDriftActive
        updateDriftUI()
    elseif keyCode == Enum.KeyCode.E then
        State.DriftAngle = math.clamp(State.DriftAngle + 1, Config.MIN_DRIFT_ANGLE, Config.MAX_DRIFT_ANGLE)
        _G.DriftAngle = State.DriftAngle
        updateDriftUI()
    elseif keyCode == Enum.KeyCode.Q then
        State.DriftAngle = math.clamp(State.DriftAngle - 1, Config.MIN_DRIFT_ANGLE, Config.MAX_DRIFT_ANGLE)
        _G.DriftAngle = State.DriftAngle
        updateDriftUI()
    elseif keyCode == Enum.KeyCode.V then
        -- Drift side toggle
        State.DriftSide = State.DriftSide * -1
        _G.DriftSide = State.DriftSide
        updateDriftUI()
    end
end))

-- ============================================================
--  INITIALIZATION
-- ============================================================
loadSettings()
updateDriftUI()

-- Apply saved WalkSpeed/JumpPower
task.spawn(function()
    task.wait(1)
    applyPlayerModifiers()
end)

-- Auto-enable Anti-AFK by default for safety
if State.AntiAFKEnabled then
    setAntiAFK(true)
end

-- Welcome notification
task.spawn(function()
    task.wait(1.5)
    SendNotification("Neuro Hub v3.1", "Loaded with Cobalt session analysis!\nAuto Checkpoint FIXED - now reads real race state\nNew: Race tracking, Auto-Upright, Auto-Skip stuck", 8)
end)

print("==========================================")
print("  NEURO HUB v3.1 - Loaded successfully")
print("  Based on Cobalt session recording analysis")
print("  FIXED: Auto Checkpoint now uses real race state from")
print("         workspace.Races.<race>.SingleplayerRacers.<player>")
print("  NEW: RaceBegan/RaceEnded listeners")
print("  NEW: Auto-Upright car when flipped")
print("  NEW: Auto-Skip stuck race (30s -> TeleportToLastCheckpoint)")
print("  NEW: Race info panel (race name, CP progress, stuck time)")
print("  NEW: Start Solo Race, Start YellowObbyReverse, Start TunnelSprint")
print("  Press RightShift to toggle GUI")
print("  Press Ctrl+click categories to drag")
print("  Right-click category to collapse")
print("==========================================")
