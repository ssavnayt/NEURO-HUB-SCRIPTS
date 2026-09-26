--=====================================================================--
--  Z    — камера от лица ракеты (Follow, зум колесом мыши как обычно)
--         В 1-м лице (zoom ≈ ZOOM_MIN) на весь экран растягивается
--         картинка-«кокпит» (ImageLabel с AUTOPRESS_SCREEN_IMAGE).
--         В 1-м лице при повороте камера кренится в сторону поворота
--         и плавно стабилизируется на 0 (как дрон).
--         После взрыва ракеты камера ЗАМОРАЖИВАЕТСЯ на последнем кадре
--         на AUTOPRESS_EXPLOSION_HOLD сек (1.28с) — даёт увидеть взрыв,
--         потом возвращается к игроку.
--  X    — поворот ракеты в сторону, куда смотрит камера
--  V    — стоп ракеты (убрать Velocity), удержание — полный якорь
--  B    — телепорт ракеты к случайному игроку (кроме себя)
--  M    — разблокировать мышь (чтобы кликать по меню)
--  T    — Custom Speed вкл/выкл
--  G    — режим скорости: Множитель / Своя скорость
--  N    — AutoPress: спавн BombMissile ВПЛОТНУЮ к игроку (невидимой
--         локально) + временный телепорт к ней на время активации
--         граб-кнопки + автокамера/поворот
--         (повтор действий, записанных в Cobalt-сессии)
--  Del  — выгрузка скрипта (Unload): отключение всего и очистка
--
-- HUD (показывается когда камера включена):
--   • верх-лево:     ALT — высота над землёй через raycast вниз
--   • верх-право:    SPS 67 — текущая скорость ракеты (studs/sec)
--   • право-низ:     FLIGHT 12.5s — сколько секунд летит ракета (сброс после взрыва)
--   • право-низ:     [icon] DIST 73% — пройдено стадов (≤50=100%, ≥1000=0%)
--=====================================================================--

-- Если скрипт уже был запущен ранее (повторный запуск) —
-- сначала выгружаем старую копию
pcall(function()
    if getgenv().MissileControlUnload then
        getgenv().MissileControlUnload()
    end
end)

--============================ СЕРВИСЫ ==============================--
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Workspace        = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

--============================ НАСТРОЙКИ ============================--

local KEY_CAM       = Enum.KeyCode.Z      -- бинд камеры
local KEY_STEER     = Enum.KeyCode.X      -- бинд поворота
local KEY_STOP      = Enum.KeyCode.V      -- бинд остановки
local KEY_TELEPORT  = Enum.KeyCode.B      -- бинд телепорта
local KEY_MOUSEFREE = Enum.KeyCode.M      -- бинд разблокировки мыши
local KEY_SPEED     = Enum.KeyCode.T      -- бинд Custom Speed
local KEY_SPEEDMODE = Enum.KeyCode.G      -- бинд смены режима скорости
local KEY_AUTOPRESS = Enum.KeyCode.N      -- бинд AutoPress
local KEY_UNLOAD    = Enum.KeyCode.Delete -- бинд выгрузки

local STEER_SPEED = 100            -- скорость доворота ракеты

local ZOOM_MIN   = 0.5             -- мин зум (0.5 = от первого лица ракеты)
local ZOOM_MAX   = 30              -- макс отдаление
local ZOOM_START = 0.5             -- стартовый зум (0.5 = первое лицо)

local CAM_OFFSET = Vector3.new(0, 4, 0)  -- точка "головы" ракеты

local HOLD_ANCHOR_TIME = 0.35      -- сколько держать V, чтобы заанчорить

local TELEPORT_OFFSET = Vector3.new(0, 5, 0) -- телепорт над головой игрока

-- Custom Speed
local MULT_MAX    = 3              -- максимум множителя (3 = 300% скорости игры)
local ABS_MAX     = 200            -- макс скорость в режиме "Своя" (стад/с)
local PCT_DEFAULT = 1 / 3          -- стартовое положение ползунка (= 100%)

-- AutoPress (повтор последовательности из Cobalt-сессии)
local AUTOPRESS_SPAWN_VEL  = Vector3.zero          -- не разгонять ракету при спавне
                                                          -- (в сессии была Vector3(0, 67.6, 0),
                                                          --  но тогда ракета улетает вверх; нули = остаётся рядом)
local AUTOPRESS_SPAWN_OFF  = CFrame.new(1, 0, 1)    -- спавн ВПЛОТНУЮ к игроку: 1 ст/над HRP
local AUTOPRESS_GRAB_LEN   = 5.6838154792785645     -- ExtendGrabLine из сессии
local AUTOPRESS_GRAB_HOLD  = 0.18                   -- пауза между стартом граба и endGrab, сек
local AUTOPRESS_SPAWN_WAIT = 5                      -- сколько ждать спавна, сек
local AUTOPRESS_AUTOCAM    = true                   -- сразу включить камеру+поворот
local AUTOPRESS_GRAB_NEAR  = CFrame.new(1, 0, 1)    -- куда ставить игрока относительно ракеты на время граба (вплотную)
local AUTOPRESS_GRAB_TELE_PRE = 0.05                -- пауза между телепортом к ракете и fire remotes (сек)

-- Full-screen «кокпит» в first-person: картинка растягивается на весь экран,
-- когда камера от ракеты в 1-м лице. ImageLabel.Stretch = true.
-- В чате даны и textureid, и assetid — для ImageLabel используем assetid.
local AUTOPRESS_SCREEN_IMAGE     = "rbxassetid://116676362741844"  -- assetid из чата
-- Если не грузится — поменяй на "rbxassetid://76785451525433" (textureid)
local AUTOPRESS_FP_DIST          = 1.5  -- порог 1-го лица: dist(камера, ракета) <= этого = 1-е лицо

-- Заморозка камеры после взрыва: после пропадания ракеты держим камеру
-- на последнем кадре (CameraType=Scriptable + каждый кадр пишем CFrame),
-- потом через это время вызываем setCam(false) и возвращаем игроку.
local AUTOPRESS_EXPLOSION_HOLD   = 1.28  -- сек

-- Camera banking (drone-style): при повороте камеры в 1-м лице камера
-- накреняется в сторону поворота и плавно стабилизируется обратно.
local TILT_GAIN              = 6.0    -- коэффициент: насколько сильно кренится
local TILT_MAX               = 0.35   -- макс угол крена (рад) ≈ 20°
local TILT_SMOOTH            = 0.18   -- сглаживание к нулю (чем меньше — тем медленнее стабилизируется)
local TILT_DEADZONE          = 0.0008  -- ниже этого yaw-скорости крен = 0

-- HUD: иконка дальности (рядом слева от текста)
local HUD_DIST_ICON          = "rbxassetid://116676362741844"  -- та же что и кокпит

-- HUD: дальность в стадах → проценты
--   dist <= 50   → 100%
--   dist >= 1000 → 0%
--   линейно между
local HUD_DIST_MAX_STUDS     = 5000
local HUD_DIST_FULL_STUDS    = 20

local ERR_TIME = 2.2               -- сколько висит окно ошибки

-- ПОПРАВКА ОСИ НОСА:
--   нос смотрит ВЛЕВО  от направления камеры  →  -90
--   нос смотрит ВПРАВО от направления камеры  →   90
local NOSE_FIX = CFrame.Angles(0, math.rad(90), 0)
--===================================================================--

-- Текущее состояние системы
local camOn        = false   -- камера от ракеты включена?
local steerOn      = false   -- поворот за камерой включен?
local mouseFree    = false   -- мышь разблокирована?
local stopHeld     = false   -- V зажата?
local anchoredByUs = false   -- якорь поставлен нашим скриптом?
local unloaded     = false   -- скрипт выгружен?

-- Состояние Custom Speed
local speedOn   = false      -- контроль скорости включен?
local speedMode = "mult"     -- "mult" (множитель) / "abs" (своя скорость)
local speedPct  = PCT_DEFAULT-- положение ползунка 0..1
local baseSpeed = 0          -- база: скорость игры, зафиксированная при включении
local sliderDragging = false -- ползунок перетаскивается?

-- Состояние AutoPress
local autoPressRunning = false  -- сейчас идёт авто-спавн + граб?
local autoPressLastResult = nil -- "ok" / "nospawnrf" / "nospawn" / "nograb" / err string

-- Трекинг «нашей» ракеты. После AutoPress-спавна новая ракета становится
-- текущей — весь скрипт (cam/steer/speed) будет работать с ней, а не со
-- случайно найденной старой моделью в SpawnedInToys.
local currentMissileModel = nil  -- Instance BombMissile (или nil)

-- Скрытые локально части ракеты (для невидимости только у локального игрока).
-- Скрипт клиентский → изменения Transparency/CanCollide не реплицируются.
local hiddenParts = {}  -- { [Instance] = originalTransparency, ... }

-- Заморозка камеры после взрыва. Пока hold активен — пишем последний
-- сохранённый camera.CFrame каждый кадр (CameraType=Scriptable).
-- Когда hold истекает — вызываем setCam(false) и возвращаем камеру игроку.
local explosionHoldUntil = 0     -- tick() до которого держим (0 = не активен)
local explosionCamCFrame = nil   -- последний сохранённый camera.CFrame

-- Camera banking (drone-style). Состояние крена.
local tiltLastYaw = nil          -- yaw предыдущего кадра (для deltaYaw)
local tiltCurrent = 0            -- текущий угол крена (рад), плавно → 0

-- Flight time: сколько секунд летит текущая ракета. Сбрасывается
-- при появлении НОВОЙ ракеты (currentMissileModel изменился).
local flightStartTick = 0        -- когда ракета появилась / когда начали лететь
local flightDistance = 0         -- пройденная дистанция в стадах (интеграл |velocity|*dt)
local flightMissileRef = nil     -- Instance ракеты, для которой считаем (чтобы заметить смену)

-- Имя бинда для camera tilt (drone banking). Объявлено здесь, чтобы unload()
-- (определённый ниже) мог его отвязать через UnbindFromRenderStep.
local TILT_BIND_NAME = "MissileControlTilt"

-- Все соединения скрипта (отключаются при выгрузке)
local connections = {}
local function track(conn)
    table.insert(connections, conn)
    return conn
end

-- Сохранённые настройки камеры игрока (восстанавливаются при выключении)
local savedMin
local savedMax
local savedMode

---------------------------- ПОИСК РАКЕТЫ ----------------------------
-- Возвращает Body ракеты, которой мы сейчас управляем.
-- Логика:
--   1) Если есть currentMissileModel (последняя, что мы заспавнили/использовали
--      в AutoPress) и она ещё жива — возвращаем её Body.
--   2) Иначе fallback: первая BombMissile в SpawnedInToys (на случай если
--      игрок заспавнил ракету вручную через меню игры).
-- Это фиксит баг, когда после спавна новой ракеты скрипт продолжал
-- управлять старой (FindFirstChild возвращает первую найденную).
local function getRocket()
    if currentMissileModel and currentMissileModel.Parent then
        local b = currentMissileModel:FindFirstChild("Body")
        if b then
            return b
        end
    end
    currentMissileModel = nil

    local toys = workspace:FindFirstChild(player.Name .. "SpawnedInToys")
    if toys then
        local missile = toys:FindFirstChild("BombMissile")
        if missile then
            currentMissileModel = missile
            return missile:FindFirstChild("Body")
        end
    end
    return nil
end

------------------- НЕВИДИМОСТЬ РАКЕТЫ ЛОКАЛЬНО ----------------------
-- Скрывает все BasePart / Decal / Texture внутри модели ракеты только
-- для локального игрока (скрипт клиентский → не реплицируется).
-- Также локально выключает CanCollide, чтобы игрока не пушало вплотную.
local function hideMissileLocally(missileModel)
    if not missileModel then return end
    -- Сначала восстанавливаем прошлую партию (если была)
    for obj, orig in pairs(hiddenParts) do
        pcall(function() obj.Transparency = orig end)
    end
    hiddenParts = {}

    for _, obj in ipairs(missileModel:GetDescendants()) do
        if obj:IsA("BasePart") then
            hiddenParts[obj] = obj.Transparency
            obj.Transparency = 1
            -- Локально отключаем коллизию — спавн вплотную к игроку
            --pcall(function() obj.CanCollide = false end) -- МЕШАЕТ, ФИКС :(
        elseif obj:IsA("Decal") or obj:IsA("Texture") then
            hiddenParts[obj] = obj.Transparency
            obj.Transparency = 1
        end
    end
end

local function unhideMissileLocally()
    for obj, orig in pairs(hiddenParts) do
        pcall(function() obj.Transparency = orig end)
    end
    hiddenParts = {}
end

--------------------------- АНИМАЦИИ ---------------------------------
-- Универсальный твин: возвращает объект твина
local function tween(obj, props, duration, style, dir)
    duration = duration or 0.25
    style = style or Enum.EasingStyle.Quad
    dir = dir or Enum.EasingDirection.Out

    local t = TweenService:Create(
        obj,
        TweenInfo.new(duration, style, dir),
        props
    )
    t:Play()
    return t
end

-- Осветление цвета (для подсветки при наведении)
local function lighten(color, amount)
    amount = amount or 0.25
    return color:Lerp(Color3.new(1, 1, 1), amount)
end

-- Пульсация кнопки при нажатии
local function pulse(btn)
    local sc = btn:FindFirstChildOfClass("UIScale")
    if not sc then
        return
    end

    sc.Scale = 0.92
    tween(sc, {Scale = 1}, 0.3, Enum.EasingStyle.Back)
end

-------------------------------- GUI ---------------------------------

local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "MissileControlGui"
gui.ResetOnSpawn = false
gui.Parent = playerGui

-- Full-screen «кокпит»: ImageLabel на весь экран, виден только когда
-- камера от ракеты в 1-м лице (dist камера↔ракета <= AUTOPRESS_FP_DIST).
-- IgnoreGuiInset = true → перекрывает верхнюю панель Roblox.
-- DisplayOrder высокий → поверх панели скрипта.
-- ImageLabel по умолчанию не ловит мышь → не мешает кликам.
local screenFillGui = Instance.new("ScreenGui")
screenFillGui.Name = "MissileControlScreenFill"
screenFillGui.ResetOnSpawn = false
screenFillGui.IgnoreGuiInset = true
screenFillGui.DisplayOrder = 9999
screenFillGui.Parent = playerGui

local screenFill = Instance.new("ImageLabel")
screenFill.Name = "Fill"
screenFill.Size = UDim2.fromScale(1, 1)
screenFill.Position = UDim2.fromScale(0, 0)
screenFill.BackgroundColor3 = Color3.new(0, 0, 0)
screenFill.BackgroundTransparency = 1  -- чёрный фон, если картинка не прогрузилась
screenFill.BorderSizePixel = 0
screenFill.Active = false  -- не ловит мышь
screenFill.Image = AUTOPRESS_SCREEN_IMAGE
screenFill.ScaleType = Enum.ScaleType.Stretch  -- растянуть на весь экран
screenFill.Visible = false
screenFill.Parent = screenFillGui

--------------------------- HUD ------------------------------------
-- Отдельный ScreenGui для HUD-элементов: SPS, FLIGHT, DIST%, ALT.
-- DisplayOrder ниже кокпита, чтобы в 1-м лице картинка перекрывала HUD
-- (если хочешь видеть HUD поверх кокпита — поменяй местами числа).
local hudGui = Instance.new("ScreenGui")
hudGui.Name = "MissileControlHUD"
hudGui.ResetOnSpawn = false
hudGui.IgnoreGuiInset = true
hudGui.DisplayOrder = 9998  -- ниже кокпита (9999), выше панели скрипта
hudGui.Parent = playerGui

-- Вспомогательная фабрика: текст-лейбл для HUD
local function makeHudLabel(anchorPos, anchor, sizeX, fontSize)
    -- anchorPos: UDim2 от угла экрана (Scale=0/1 + Offset)
    -- anchor: Vector2 (AnchorPoint)
    local lbl = Instance.new("TextLabel")
    lbl.AnchorPoint = anchor
    lbl.Position = anchorPos
    lbl.Size = UDim2.fromOffset(sizeX, fontSize + 8)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = fontSize
    lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    lbl.TextStrokeTransparency = 0.35
    lbl.TextXAlignment = Enum.TextXAlignment.Right
    lbl.TextYAlignment = Enum.TextYAlignment.Center
    lbl.Text = ""
    lbl.Parent = hudGui
    return lbl
end

-- SPS (верх-право)
local spsLabel = makeHudLabel(
    UDim2.new(1, -12, 0, 77.67),   -- правый край -12, верх 12
    Vector2.new(1, 0),
    160, 18
)
spsLabel.Text = "SPS = nil"

-- ALT (верх-лево, почти сверху)
local altLabel = makeHudLabel(
    UDim2.new(0, 12, 0, 52.6967),    -- левый край 12, верх 12
    Vector2.new(0, 0),
    160, 18
)
altLabel.TextXAlignment = Enum.TextXAlignment.Left
altLabel.Text = "ALT = nil"

-- FLIGHT (право-низ, почти низ)
local flightLabel = makeHudLabel(
    UDim2.new(1, -12.1314, 1, -16.3264),  -- правый край -12, низ -12
    Vector2.new(1, 1),
    160, 18
)
flightLabel.Text = "FLIGHT 0.0s"

-- DIST% — это контейнер: иконка слева + текст справа (право-низ над FLIGHT)
local distFrame = Instance.new("Frame")
distFrame.AnchorPoint = Vector2.new(1, 1)
distFrame.Position = UDim2.new(1, -12, 1, -34)  -- право -12, низ -34 (над flight)
distFrame.Size = UDim2.fromOffset(200, 26)
distFrame.BackgroundTransparency = 1
distFrame.Parent = hudGui

local distIcon = Instance.new("ImageLabel")
distIcon.AnchorPoint = Vector2.new(0, 0.5)
distIcon.Position = UDim2.new(0, 0, 0.5, 0)
distIcon.Size = UDim2.fromOffset(22, 22)
distIcon.BackgroundTransparency = 1
distIcon.Image = HUD_DIST_ICON
distIcon.ScaleType = Enum.ScaleType.Stretch
distIcon.Parent = distFrame

local distLabel = Instance.new("TextLabel")
distLabel.AnchorPoint = Vector2.new(0, 0.5)
distLabel.Position = UDim2.new(0, 28, 0.5, 0)
distLabel.Size = UDim2.new(1, -28, 0, 22)
distLabel.BackgroundTransparency = 1
distLabel.Font = Enum.Font.GothamBold
distLabel.TextSize = 18
distLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
distLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
distLabel.TextStrokeTransparency = 0.35
distLabel.TextXAlignment = Enum.TextXAlignment.Left
distLabel.TextYAlignment = Enum.TextYAlignment.Center
distLabel.Text = "DIST 0%"
distLabel.Parent = distFrame

-- Удобные переключатели видимости
local function setHudVisible(vis)
    hudGui.Enabled = vis
end
-- Изначально HUD спрятан (покажем когда camOn)
hudGui.Enabled = false

-- Делаем frame
local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(240, 398)
frame.Position = UDim2.new(0, 15, 0, 15)
frame.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
frame.BackgroundTransparency = 0.1
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 10)
frameCorner.Parent = frame

-- Настраиваем title
-- (Active = true, чтобы ловить мышь: панель перетаскивается ЗА ЗАГОЛОВОК)
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 26)
title.BackgroundTransparency = 1
title.Active = true
title.ZIndex = 2
title.Text = "for skibidipokoyo by whtk"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Parent = frame

----------------- ПЕРЕТАСКИВАНИЕ ПАНЕЛИ ЗА ЗАГОЛОВОК ------------------
-- UIDragDetector не подходит: он перетаскивает панель при зажатии
-- В ЛЮБОМ месте, включая ползунок. Поэтому таскаем вручную за title.
do
    local dragging = false
    local dragStart, startPos

    track(title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart

            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))

    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end


-- Кнопка, на которую наведена мышь (для подсветки)
local hoveredBtn = nil

-- Фабрика кнопок: создаёт кнопку на заданной высоте внутри панели
local function makeBtn(posY)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -16, 0, 32)
    btn.Position = UDim2.new(0, 8, 0, posY)
    btn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false -- подсветку делаем своей анимацией
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 13
    btn.TextColor3 = Color3.fromRGB(235, 235, 235)
    btn.Parent = frame

    -- Скруглённые углы кнопки
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = btn

    -- Масштаб для пульсации и появления
    local sc = Instance.new("UIScale")
    sc.Parent = btn

    -- Подсветка при наведении
    track(btn.MouseEnter:Connect(function()
        hoveredBtn = btn
        local base = btn:GetAttribute("BaseColor") or Color3.fromRGB(45, 45, 60)
        tween(btn, {BackgroundColor3 = lighten(base)}, 0.15)
    end))

    track(btn.MouseLeave:Connect(function()
        if hoveredBtn == btn then
            hoveredBtn = nil
        end
        local base = btn:GetAttribute("BaseColor") or Color3.fromRGB(45, 45, 60)
        tween(btn, {BackgroundColor3 = base}, 0.15)
    end))

    return btn
end

-- Настраиваем кнопки
local camBtn      = makeBtn(30)
local steerBtn    = makeBtn(66)
local stopBtn     = makeBtn(102)
local teleportBtn = makeBtn(138)
local mouseBtn    = makeBtn(174)
local speedBtn    = makeBtn(210)
local modeBtn     = makeBtn(246)
local autopressBtn = makeBtn(320)
local unloadBtn   = makeBtn(356)

stopBtn.Text     = "[V]  Стоп ракеты (удерж. = якорь)"
teleportBtn.Text = "[B]  Телепорт к игроку (рандом)"
modeBtn.Text     = "[G]  Режим:  Множитель"
autopressBtn.Text = "[N]  AutoPress (спавн + граб)"
unloadBtn.Text   = "Выгрузить скрипт (Unload)"

---------------------------- ПОЛЗУНОК ---------------------------------
-- Подпись со значением (ZIndex 5 — выше кнопок)
local sliderLabel = Instance.new("TextLabel")
sliderLabel.Size = UDim2.new(1, -16, 0, 16)
sliderLabel.Position = UDim2.new(0, 8, 0, 284)
sliderLabel.BackgroundTransparency = 1
sliderLabel.ZIndex = 4
sliderLabel.Text = ""
sliderLabel.TextColor3 = Color3.fromRGB(170, 180, 210)
sliderLabel.Font = Enum.Font.Gotham
sliderLabel.TextSize = 12
sliderLabel.TextXAlignment = Enum.TextXAlignment.Left
sliderLabel.Parent = frame

-- Дорожка ползунка (ZIndex 6 — выше кнопок, ввод ловит сама дорожка)
local sliderTrack = Instance.new("Frame")
sliderTrack.Size = UDim2.new(1, -16, 0, 12)
sliderTrack.Position = UDim2.new(0, 8, 0, 302)
sliderTrack.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
sliderTrack.BorderSizePixel = 0
sliderTrack.ZIndex = 5
sliderTrack.Active = true -- ловит мышь для перетаскивания
sliderTrack.Parent = frame

local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(1, 0)
sliderTrack.ZIndex = 4
trackCorner.Parent = sliderTrack

-- Заполненная часть
local sliderFill = Instance.new("Frame")
sliderFill.Size = UDim2.fromScale(1, 1)
sliderFill.BackgroundColor3 = Color3.fromRGB(70, 130, 220)
sliderFill.BorderSizePixel = 0
sliderFill.Active = false
sliderFill.ZIndex = 5
sliderFill.Parent = sliderTrack

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = sliderFill

-- Круглый бегунок (ZIndex 7 — самый верх)
local sliderHandle = Instance.new("Frame")
sliderHandle.Size = UDim2.fromOffset(16, 16)
sliderHandle.AnchorPoint = Vector2.new(0.5, 0.5)
sliderHandle.Position = UDim2.new(1, 0, 0.5, 0)
sliderHandle.BackgroundColor3 = Color3.fromRGB(235, 235, 245)
sliderHandle.BorderSizePixel = 0
sliderHandle.Active = false
sliderHandle.ZIndex = 7
sliderHandle.Parent = sliderTrack

local handleCorner = Instance.new("UICorner")
handleCorner.CornerRadius = UDim.new(1, 0)
handleCorner.Parent = sliderHandle

-- Обновляет вид ползунка и подпись значения
local function updateSliderVisual()
    sliderFill.Size = UDim2.new(speedPct, 0, 1, 0)
    sliderHandle.Position = UDim2.new(speedPct, 0, 0.5, 0)

    if speedMode == "mult" then
        sliderLabel.Text = ("Множитель:  %d%%"):format(math.floor(speedPct * MULT_MAX * 100 + 0.5))
    else
        sliderLabel.Text = ("Своя скорость:  %d стад/с"):format(math.floor(speedPct * ABS_MAX + 0.5))
    end
end

-- Цвета ползунка: активное / неактивное состояние
local SLIDER_ON = {
    label  = Color3.fromRGB(170, 180, 210),
    track  = Color3.fromRGB(35, 35, 50),
    fill   = Color3.fromRGB(70, 130, 220),
    handle = Color3.fromRGB(235, 235, 245),
}

local SLIDER_OFF = {
    label  = Color3.fromRGB(95, 100, 115),
    track  = Color3.fromRGB(26, 26, 38),
    fill   = Color3.fromRGB(45, 55, 80),
    handle = Color3.fromRGB(115, 115, 128),
}

-- Затемнение ползунка, когда Custom Speed выключен
-- (тусклые цвета, без какой-либо прозрачности)
local function setSliderDimmed(dimmed)
    local c = dimmed and SLIDER_OFF or SLIDER_ON

    tween(sliderLabel,  {TextColor3 = c.label}, 0.2)
    tween(sliderTrack,  {BackgroundColor3 = c.track}, 0.2)
    tween(sliderFill,   {BackgroundColor3 = c.fill}, 0.2)
    tween(sliderHandle, {BackgroundColor3 = c.handle}, 0.2)
end

-- Настраиваем цвета
local COLOR_ON  = Color3.fromRGB(46, 125, 70)
local COLOR_OFF = Color3.fromRGB(45, 45, 60)
local COLOR_AUTOPRESS_IDLE = Color3.fromRGB(50, 80, 110) -- синеватый акцент
local COLOR_AUTOPRESS_BUSY = Color3.fromRGB(170, 110, 30) -- оранжевый "работает"

-- Плавно меняет цвет кнопки (учитывая наведение мыши)
local function setBtnColor(btn, color)
    btn:SetAttribute("BaseColor", color)

    local target = (hoveredBtn == btn) and lighten(color) or color
    tween(btn, {BackgroundColor3 = target}, 0.2)
end

-- Обновляет текст и цвет кнопок по текущему состоянию
local function updateGui()
    -- Камера
    if camOn then
        camBtn.Text = "[Z]  Камера от ракеты:  ВКЛ"
        setBtnColor(camBtn, COLOR_ON)
    else
        camBtn.Text = "[Z]  Камера от ракеты:  ВЫКЛ"
        setBtnColor(camBtn, COLOR_OFF)
    end

    -- Поворот
    if steerOn then
        steerBtn.Text = "[X]  Поворот за камерой:  ВКЛ"
        setBtnColor(steerBtn, COLOR_ON)
    else
        steerBtn.Text = "[X]  Поворот за камерой:  ВЫКЛ"
        setBtnColor(steerBtn, COLOR_OFF)
    end

    -- Разблок мыши
    if mouseFree then
        mouseBtn.Text = "[M]  Разблок. мышь:  ВКЛ"
        setBtnColor(mouseBtn, COLOR_ON)
    else
        mouseBtn.Text = "[M]  Разблок. мышь:  ВЫКЛ"
        setBtnColor(mouseBtn, COLOR_OFF)
    end

    -- Custom Speed
    if speedOn then
        speedBtn.Text = "[T]  Custom Speed:  ВКЛ"
        setBtnColor(speedBtn, COLOR_ON)
        setSliderDimmed(false)
    else
        speedBtn.Text = "[T]  Custom Speed:  ВЫКЛ"
        setBtnColor(speedBtn, COLOR_OFF)
        setSliderDimmed(true)
    end

    -- Режим скорости
    if speedMode == "mult" then
        modeBtn.Text = "[G]  Режим:  Множитель"
    else
        modeBtn.Text = "[G]  Режим:  Своя скорость"
    end

    -- AutoPress
    if autoPressRunning then
        autopressBtn.Text = "[N]  AutoPress:  ИДЁТ…"
        setBtnColor(autopressBtn, COLOR_AUTOPRESS_BUSY)
    elseif autoPressLastResult == "ok" then
        autopressBtn.Text = "[N]  AutoPress:  ГОТОВО"
        setBtnColor(autopressBtn, COLOR_ON)
    elseif autoPressLastResult and autoPressLastResult ~= "ok" then
        autopressBtn.Text = "[N]  AutoPress:  ОШИБКА"
        setBtnColor(autopressBtn, Color3.fromRGB(140, 45, 45))
    else
        autopressBtn.Text = "[N]  AutoPress (спавн + граб)"
        setBtnColor(autopressBtn, COLOR_AUTOPRESS_IDLE)
    end
end

unloadBtn:SetAttribute("BaseColor", Color3.fromRGB(140, 45, 45))
unloadBtn.BackgroundColor3 = Color3.fromRGB(140, 45, 45)

autopressBtn:SetAttribute("BaseColor", COLOR_AUTOPRESS_IDLE)
autopressBtn.BackgroundColor3 = COLOR_AUTOPRESS_IDLE

--------------------------- ОШИБКА -----------------------------------
-- Анимированное окно ошибки сверху экрана
local errFrame = nil
local errToken = 0

local function showError(message)
    -- Перезапускаем окно, если ошибка показывается уже сейчас
    errToken += 1
    local myToken = errToken

    if errFrame then
        errFrame:Destroy()
        errFrame = nil
    end

    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0)
    f.BackgroundColor3 = Color3.fromRGB(70, 22, 22)
    f.BorderSizePixel = 0
    f.Size = UDim2.fromOffset(340, 58)
    f.Position = UDim2.new(0.5, 0, 0, -80) -- старт за экраном сверху
    f.ZIndex = 10
    f.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = f

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(190, 60, 60)
    stroke.Thickness = 1.5
    stroke.Parent = f

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -16, 1, 0)
    label.Position = UDim2.new(0, 8, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = "⚠  " .. message
    label.TextColor3 = Color3.fromRGB(255, 120, 120)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.TextWrapped = true
    label.ZIndex = 10
    label.Parent = f

    errFrame = f

    -- Выезжает сверху с лёгким отскоком
    tween(f, {Position = UDim2.new(0.5, 0, 0, 18)}, 0.35, Enum.EasingStyle.Back)

    -- Через ERR_TIME уезжает обратно и удаляется
    task.delay(ERR_TIME, function()
        if myToken ~= errToken or unloaded then
            return
        end

        local out = tween(
            f,
            {Position = UDim2.new(0.5, 0, 0, -80)},
            0.3,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.In
        )
        out.Completed:Wait()

        if myToken == errToken then
            f:Destroy()
            if errFrame == f then
                errFrame = nil
            end
        end
    end)
end

--------------------------- ВКЛ / ВЫКЛ -------------------------------

-- Включает / выключает камеру от лица ракеты
local function setCam(state)
    local body = getRocket()

    -- Ошибка, если ракеты нет
    if state and not body then
        showError("Ракета не найдена! Заспавнь BombMissile")
        return
    end

    camOn = state

    if camOn then
		hideMissileLocally(newMissile, true)
        -- Запоминаем всё, что меняем, чтобы вернуть при выключении
        savedMin  = player.CameraMinZoomDistance
        savedMax  = player.CameraMaxZoomDistance
        savedMode = player.CameraMode

        -- Разрешаем зум и снимаем принудительное первое лицо
        -- (иначе зум колесом мыши заблокирован)
        player.CameraMinZoomDistance = ZOOM_MIN
        player.CameraMaxZoomDistance = ZOOM_MAX
        player.CameraMode = Enum.CameraMode.Classic

        -- Стартовый взгляд — по носу ракеты
        camera.CameraType = Enum.CameraType.Scriptable

        -- ФИКС: НОС РАКЕТЫ БАГОВАЛСЯ
        local noseCFrame = body.CFrame * NOSE_FIX:Inverse()
        local look = noseCFrame.LookVector

        local pos = (body.CFrame * CFrame.new(CAM_OFFSET)).Position
        camera.CFrame = CFrame.lookAt(pos, pos + look)

        camera.CameraSubject = body
        camera.CameraType = Enum.CameraType.Follow

        -- Принудительный стартовый зум:
        -- зажимаем min = max на один кадр, камера обязана встать
        -- на это расстояние, после чего max возвращаем обратно
        player.CameraMinZoomDistance = ZOOM_START
        player.CameraMaxZoomDistance = ZOOM_START
        task.wait()
        player.CameraMinZoomDistance = ZOOM_MIN
        player.CameraMaxZoomDistance = ZOOM_MAX
    else
        player.CameraMinZoomDistance = savedMin or 0.5
        player.CameraMaxZoomDistance = savedMax or 400
        player.CameraMode = savedMode or Enum.CameraMode.LockFirstPerson

        camera.CameraType = Enum.CameraType.Custom

        local hum = player.Character
            and player.Character:FindFirstChildOfClass("Humanoid")

        if hum then
            camera.CameraSubject = hum
        end

        -- Скрываем full-screen картинку (если камеру выключили вручную)
        if screenFill.Visible then
            screenFill.Visible = false
        end

        -- Прячем HUD
        hudGui.Enabled = false

        -- Сбрасываем состояние крена (чтобы не осталось при возврате камеры)
        tiltCurrent = 0
        tiltLastYaw = nil
    end

    updateGui()
end

-- Включает / выключает поворот ракеты за камерой
local function setSteer(state)
    -- Ошибка, если ракеты нет
    if state and not getRocket() then
        showError("Ракета не найдена! Заспавнь BombMissile")
        return
    end

    steerOn = state
    updateGui()
end

------------------------- CUSTOM SPEED -------------------------------
-- Применяет выбранную скорость к ракете.
-- Вызывается каждый кадр: applyCustomSpeed(body, dt), dt — из RunService.RenderStepped/Heartbeat
local function applyCustomSpeed(body, dt)
    local vel = body.AssemblyLinearVelocity
    local speed = vel.Magnitude

    -- Направление: из текущей скорости, а если ракета стоит — по носу
    local dir
    if speed > 0.5 then
        dir = vel.Unit
    else
        dir = (body.CFrame * NOSE_FIX:Inverse()).LookVector
    end

    -- Множитель: 1 = нейтрально (не мешаем игре), >1 = буст
    local mult = 1 + speedPct * MULT_MAX

    local targetSpeed

    if speedMode == "mult" then
        -- Пока множитель нейтральный — база догоняет естественный разгон ракеты,
        -- чтобы включение буста не сбрасывало скорость вниз
        if mult <= 1.01 and speed > 1 then
            baseSpeed = speed
        end

        -- Стоячую ракету в этом режиме не трогаем (нечего множить)
        if speed <= 0.5 then
            return
        end

        targetSpeed = baseSpeed * mult
    else
        -- Своя скорость: даже стоячей ракете задаём ход по носу
        targetSpeed = speedPct * ABS_MAX
    end

    -- Плавное приближение к цели вместо жёсткой перезаписи каждый кадр
    -- (коэффициент больше — реакция резче)
    local alpha = 1 - math.exp(-dt * 12)
    local newVel = vel:Lerp(dir * targetSpeed, alpha)

    -- Движитель ищем в самой ракете и среди её соседей
    local parent = body.Parent
    local bv = body:FindFirstChildWhichIsA("BodyVelocity")
        or (parent and parent:FindFirstChildWhichIsA("BodyVelocity", true))
    local lv = body:FindFirstChildWhichIsA("LinearVelocity")
        or (parent and parent:FindFirstChildWhichIsA("LinearVelocity", true))

    if bv then
        -- Снимаем лимит силы, иначе движитель не догонит заданную скорость
        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bv.Velocity = newVel
    elseif lv then
        lv.MaxForce = math.huge
        lv.VectorVelocity = newVel
    else
        body.AssemblyLinearVelocity = newVel
    end
end

-- Включает / выключает контроль скорости
local function setSpeed(state)
    if state then
        local body = getRocket()

        if not body then
            showError("Ракета не найдена! Заспавнь BombMissile")
            return
        end

        -- Фиксируем игровую скорость как базу для множителя
        baseSpeed = body.AssemblyLinearVelocity.Magnitude
    end

    speedOn = state
    updateGui()
end

-- Переключает режим: множитель <-> своя скорость
local function toggleSpeedMode()
    if speedMode == "mult" then
        speedMode = "abs"
    else
        speedMode = "mult"

        -- Переснимаем базу с текущей скорости ракеты
        local body = getRocket()
        baseSpeed = body and body.AssemblyLinearVelocity.Magnitude or 0
    end

    updateGui()
    updateSliderVisual()
end

-- Телепорт ракеты к случайному игроку (кроме себя)
-- Возвращает: "norocket" / "notargets" / true
local function teleportRocket()
    local body = getRocket()

    if not body then
        return "norocket"
    end

    -- Собираем живых игроков кроме себя
    local targets = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character then
            local root = plr.Character:FindFirstChild("HumanoidRootPart")
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")

            if root and hum and hum.Health > 0 then
                table.insert(targets, root)
            end
        end
    end

    -- Некуда телепортировать
    if #targets == 0 then
        return "notargets"
    end

    local root = targets[math.random(1, #targets)]

    -- Гасим скорость, чтобы ракета не улетела после телепорта
    body.AssemblyLinearVelocity = Vector3.zero
    body.AssemblyAngularVelocity = Vector3.zero

    -- Ставим ракету чуть выше головы игрока
    body.CFrame = root.CFrame * CFrame.new(TELEPORT_OFFSET)

    return true
end

-- Разблокировка мыши (чтобы кликать по меню при заблокированном курсоре)
local MOUSE_BIND_NAME = "MissileControl_MouseFree"

local function setMouseFree(state)
    mouseFree = state

    if mouseFree then
        -- Форсим свободный курсор КАЖДЫЙ кадр ПОСЛЕ обновления камеры,
        -- иначе скрипты камеры вернут LockCenter обратно
        pcall(function()
            RunService:BindToRenderStep(
                MOUSE_BIND_NAME,
                Enum.RenderPriority.Camera.Value + 1,
                function()
                    if not mouseFree then
                        return
                    end

                    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
                    UserInputService.MouseIconEnabled = true
                end
            )
        end)
    else
        pcall(function()
            RunService:UnbindFromRenderStep(MOUSE_BIND_NAME)
        end)
    end

    updateGui()
end

---------------------------- AutoPress ------------------------------
-- AutoPress повторяет цепочку действий, зафиксированных в Cobalt-сессии:
--
--   t≈59.09s  SpawnToyRemoteFunction:InvokeServer("BombMissile", CFrame, Vector3(0, 67.6, 0))
--   t≈61.71s  GrabEvents.CreateGrabLine:FireServer(Button, Button.CFrame)
--   t≈61.71s  GrabEvents.ExtendGrabLine:  FireServer(5.6838)
--   t≈61.71s  GrabEvents.SetNetworkOwner: FireServer(Button, Body.CFrame)
--   t≈61.89s  GrabEvents.DestroyGrabLine: FireServer(Button)
--
-- Bindable-события ActionEvent / GrabNotifyEvent намеренно НЕ дёргаем —
-- это внутренние уведомления игры, их плодит сам GrabbingScript, когда
-- игрок жмёт кнопку Grab. Мы дёргаем только сетевые Remotes, как в сессии.

-- Кэш ссылок на реплицированные ресурсы (один поиск на всю сессию работы)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local spawnRF, grabEvents, createGrabRE, extendGrabRE, setOwnerRE, destroyGrabRE

local function ensureRemotes()
    if spawnRF == nil then
        local menuToys = ReplicatedStorage:FindFirstChild("MenuToys")
        spawnRF = menuToys and menuToys:FindFirstChild("SpawnToyRemoteFunction")
    end
    if grabEvents == nil then
        grabEvents = ReplicatedStorage:FindFirstChild("GrabEvents")
    end
    if grabEvents then
        if createGrabRE  == nil then createGrabRE  = grabEvents:FindFirstChild("CreateGrabLine")    end
        if extendGrabRE  == nil then extendGrabRE  = grabEvents:FindFirstChild("ExtendGrabLine")    end
        if setOwnerRE    == nil then setOwnerRE    = grabEvents:FindFirstChild("SetNetworkOwner")   end
        if destroyGrabRE == nil then destroyGrabRE = grabEvents:FindFirstChild("DestroyGrabLine")  end
    end
end

-- Ищет дочерний "Button" у модели ракеты (BombMissile.Button, реже Body.Button).
-- В сессии CreateGrabLine:FireServer получал именно этот инстанс.
local function findRocketButton(body)
    if not body then return nil end
    local missile = body.Parent or body
    if missile == body then
        -- body — это уже сама модель (теоретически)
        return body:FindFirstChild("Button")
            or body:FindFirstChild("Button", true)
    end
    return missile:FindFirstChild("Button")
        or body:FindFirstChild("Button")
        or missile:FindFirstChild("Button", true)
end

-- Запускает полный цикл AutoPress в отдельном потоке.
-- Возвращает в autoPressLastResult строку состояния: "ok" или причину ошибки.
local function autoPress()
    if unloaded then return end
    if autoPressRunning then
        showError("AutoPress уже работает — подожди")
        return
    end

    ensureRemotes()

    if not spawnRF then
        autoPressLastResult = "nospawnrf"
        updateGui()
        showError("SpawnToyRemoteFunction не найден")
        return
    end

    autoPressRunning = true
    autoPressLastResult = nil
    updateGui()

    -- Запускаем в task.spawn, чтобы не морозить RenderStepped и обработку ввода
    task.spawn(function()
        local ok_err = "ok"

        -- 1) Спавним НОВУЮ ракету ВСЕГДА — даже если в SpawnedInToys уже
        --    висит старая. Снапшотим существующие модели до спавна, чтобы
        --    потом найти ИМЕННО новую (не первую попавшуюся — иначе при
        --    наличии старой ракеты граб уйдёт к ней, а новая не активируется).
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then
            ok_err = "nochar"
        else
            -- Снапшот: какие BombMissile уже есть в SpawnedInToys ДО спавна
            local oldMissiles = {}
            local toysBefore = workspace:FindFirstChild(player.Name .. "SpawnedInToys")
            if toysBefore then
                for _, m in ipairs(toysBefore:GetChildren()) do
                    if m.Name == "BombMissile" then
                        oldMissiles[m] = true
                    end
                end
            end

            -- Спавним прямо рядом с игроком (4 ст/над головой, 3 ст/вперёд)
            local spawnCF = root.CFrame * AUTOPRESS_SPAWN_OFF

            local invoke_ok, invoke_err = pcall(function()
                spawnRF:InvokeServer("BombMissile", spawnCF, AUTOPRESS_SPAWN_VEL)
            end)
            if not invoke_ok then
                ok_err = "spawn: " .. tostring(invoke_err)
            else
                -- Ждём появления НОВОЙ ракеты — той, которой НЕ было в oldMissiles
                local newBody = nil
                local newMissile = nil
                local t0 = tick()
                while not unloaded and (tick() - t0) < AUTOPRESS_SPAWN_WAIT do
                    local toys = workspace:FindFirstChild(player.Name .. "SpawnedInToys")
                    if toys then
                        for _, m in ipairs(toys:GetChildren()) do
                            if m.Name == "BombMissile" and not oldMissiles[m] then
                                local b = m:FindFirstChild("Body")
                                if b then
                                    newBody = b
                                    newMissile = m
                                    break
                                end
                            end
                        end
                    end
                    if newBody then break end
                    task.wait(0.1)
                end

                if newBody and newMissile then
                    -- Запоминаем как текущую — теперь весь скрипт работает с ней
                    currentMissileModel = newMissile
                    -- Скрываем ракету локально (для локального игрока):
                    -- Transparency=1 на всех BasePart/Decal/Texture + CanCollide=false.
                    -- Только локально, на сервер/других клиентов не влияет.
                else
                    ok_err = "nospawn"
                end
            end
        end

        -- Берём Body через getRocket() — теперь вернёт именно новую
        local body = getRocket()

        -- 2) Grab-цикл: телепорт игрока к ракете ТОЛЬКО на время активации
        --    кнопки, затем возврат обратно. Без постоянного вельда/седла.
        --    (по сессии: CreateGrabLine → ExtendGrabLine → SetNetworkOwner →
        --     пауза ~0.18с → DestroyGrabLine)
        if ok_err == "ok" and body and not unloaded then
            local button = findRocketButton(body)

            if not button then
                ok_err = "nograb"
            else
                local char = player.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                local savedCF = hrp and hrp.CFrame

                -- 2a) Телепорт игрока прямо к ракете (рядом с кнопкой)
                if hrp then
                    pcall(function()
                        hrp.CFrame = body.CFrame * AUTOPRESS_GRAB_NEAR
                        hrp.AssemblyLinearVelocity = Vector3.zero
                        hrp.AssemblyAngularVelocity = Vector3.zero
                    end)
                    -- Даём серверу кадр зарегистрировать близость
                    local pre_t = tick()
                    while not unloaded and (tick() - pre_t) < AUTOPRESS_GRAB_TELE_PRE do
                        task.wait()
                    end
                end

                -- 2b) Fire remotes (как в сессии)
                -- CreateGrabLine:FireServer(Button, Button.CFrame)  (строка 449 GrabbingScript)
                pcall(function()
                    if createGrabRE then
                        createGrabRE:FireServer(button, button.CFrame)
                    end
                end)
                -- ExtendGrabLine: FireServer(5.6838)                  (строка 450)
                pcall(function()
                    if extendGrabRE then
                        extendGrabRE:FireServer(AUTOPRESS_GRAB_LEN)
                    end
                end)
                -- SetNetworkOwner: FireServer(Button, Body.CFrame)   (строка 490)
                pcall(function()
                    if setOwnerRE then
                        setOwnerRE:FireServer(button, body.CFrame)
                    end
                end)

                -- 2c) Hold (в сессии ≈ 0.178с между стартом граба и endGrab)
                local hold_t = tick()
                while not unloaded and (tick() - hold_t) < AUTOPRESS_GRAB_HOLD do
                    task.wait()
                end

                -- 2d) DestroyGrabLine: FireServer(Button)               (строка 152, endGrab)
                pcall(function()
                    if destroyGrabRE then
                        destroyGrabRE:FireServer(button)
                    end
                end)

                -- 2e) ВСЕГДА возвращаем игрока обратно — даже если remote упал
                if hrp and savedCF then
                    pcall(function()
                        hrp.CFrame = savedCF
                        hrp.AssemblyLinearVelocity = Vector3.zero
                        hrp.AssemblyAngularVelocity = Vector3.zero
                    end)
                end
            end
        end

        -- 3) (Опционально) сразу подхватываем ракету камерой и поворотом.
        --    Если камера уже была включена — переподключаем на НОВУЮ ракету
        --    (setCam(false) + setCam(true)), иначе CameraSubject остался бы
        --    на старом Body.
        if ok_err == "ok" and AUTOPRESS_AUTOCAM and not unloaded then
            if camOn then
                setCam(false)  -- отпускаем старую
            end
            setCam(true)       -- подключаемся к новой (getRocket() вернёт currentMissileModel)
            if not steerOn then
                setSteer(true)
            end
        end

        autoPressRunning = false
        autoPressLastResult = ok_err
        if not unloaded then updateGui() end

        if ok_err == "ok" then
            showError("AutoPress: ракета готова")
        elseif ok_err == "nospawn" then
            showError("AutoPress: BombMissile не появился после InvokeServer")
        elseif ok_err == "nograb" then
            showError("AutoPress: у ракеты нет инстанса Button — граб пропущен")
        elseif ok_err == "nospawnrf" then
            showError("AutoPress: SpawnToyRemoteFunction не найден")
        elseif ok_err == "nochar" then
            showError("AutoPress: нет персонажа — встань и нажми N ещё раз")
        else
            showError("AutoPress: " .. tostring(ok_err))
        end
    end)
end

----------------------------- UNLOAD ---------------------------------
-- Полная выгрузка скрипта
local function unload()
    if unloaded then
        return -- защита от повторного вызова
    end
    unloaded = true

    stopHeld = false
    speedOn  = false
    autoPressRunning = false

    if camOn then
        setCam(false)
    end
    steerOn = false

    setMouseFree(false)

    -- Снимаем якорь, если ставили его мы
    if anchoredByUs then
        local body = getRocket()
        if body then
            body.Anchored = false
        end
        anchoredByUs = false
    end

    -- Возвращаем видимость ракеты (была скрыта локально)
    unhideMissileLocally()

    -- Сбрасываем трекинг и hold-состояние камеры
    currentMissileModel = nil
    explosionHoldUntil = 0
    explosionCamCFrame = nil

    -- Сбрасываем счётчики полёта и крен
    flightMissileRef = nil
    flightStartTick = 0
    flightDistance = 0
    tiltCurrent = 0
    tiltLastYaw = nil

    -- Отвязываем tilt-обработчик от RenderStep
    pcall(function()
        RunService:UnbindFromRenderStep(TILT_BIND_NAME)
    end)

    for _, conn in ipairs(connections) do
        conn:Disconnect()
    end
    table.clear(connections)

    -- Анимация ухода панели влево, затем удаление
    pcall(function()
        tween(
            frame,
            {
                Position = frame.Position - UDim2.fromOffset(300, 0),
                BackgroundTransparency = 1
            },
            0.3,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.In
        )
    end)

    task.delay(0.32, function()
        gui:Destroy()
        -- Уничтожаем и full-screen кокпит + HUD
        pcall(function() screenFillGui:Destroy() end)
        pcall(function() hudGui:Destroy() end)
    end)

    pcall(function()
        if getgenv().MissileControlUnload == unload then
            getgenv().MissileControlUnload = nil
        end
    end)
end

-- Глобальная ссылка: getgenv().MissileControlUnload()
pcall(function()
    getgenv().MissileControlUnload = unload
end)

--------------------------- КНОПКИ GUI --------------------------------
-- Обёртка: пульсация + действие
local function bindBtn(btn, fn)
    track(btn.MouseButton1Click:Connect(function()
        pulse(btn)
        fn()
    end))
end

bindBtn(camBtn, function()
    setCam(not camOn)
end)

bindBtn(steerBtn, function()
    setSteer(not steerOn)
end)

bindBtn(stopBtn, function()
    -- Кнопка = разовое "прижать" ракету на месте
    local body = getRocket()
    if body then
        body.AssemblyLinearVelocity = Vector3.zero
        body.AssemblyAngularVelocity = Vector3.zero
    else
        showError("Ракета не найдена! Заспавнь BombMissile")
    end
end)

bindBtn(teleportBtn, function()
    local res = teleportRocket()

    if res == "norocket" then
        showError("Ракета не найдена! Заспавнь BombMissile")
    elseif res == "notargets" then
        showError("Нет других игроков для телепорта")
    end
end)

bindBtn(mouseBtn, function()
    setMouseFree(not mouseFree)
end)

bindBtn(speedBtn, function()
    setSpeed(not speedOn)
end)

bindBtn(modeBtn, toggleSpeedMode)

bindBtn(autopressBtn, autoPress)

bindBtn(unloadBtn, unload)

--------------------- ПЕРЕТАСКИВАНИЕ ПОЛЗУНКА ------------------------
-- Ставит ползунок по X-координате мыши
local function setSliderFromX(mouseX)
    local absPos  = sliderTrack.AbsolutePosition.X
    local absSize = sliderTrack.AbsoluteSize.X

    if absSize <= 0 then
        return
    end

    speedPct = math.clamp((mouseX - absPos) / absSize, 0, 1)
    updateSliderVisual()
end

track(sliderTrack.InputBegan:Connect(function(input)
    if not speedOn then
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        sliderDragging = true
        setSliderFromX(input.Position.X)
    end
end))

track(UserInputService.InputChanged:Connect(function(input)
    if not sliderDragging then
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        setSliderFromX(input.Position.X)
    end
end))

track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        sliderDragging = false
    end
end))


----------------------------- КЛАВИШИ --------------------------------
-- Обработка нажатий клавиш
track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end

    if input.KeyCode == KEY_CAM then
        pulse(camBtn)
        setCam(not camOn)
    elseif input.KeyCode == KEY_STEER then
        pulse(steerBtn)
        setSteer(not steerOn)
    elseif input.KeyCode == KEY_STOP then
        pulse(stopBtn)

        local body = getRocket()

        if not body then
            showError("Ракета не найдена! Заспавнь BombMissile")
            return
        end

        -- Разовое нажатие: сразу убираем скорость
        body.AssemblyLinearVelocity = Vector3.zero
        body.AssemblyAngularVelocity = Vector3.zero

        -- Запоминаем, что клавиша зажата
        stopHeld = true

        -- Если V удержана дольше HOLD_ANCHOR_TIME — якорим совсем
        task.delay(HOLD_ANCHOR_TIME, function()
            if stopHeld then
                local b = getRocket()
                if b then
                    b.Anchored = true
                    anchoredByUs = true
                end
            end
        end)
    elseif input.KeyCode == KEY_TELEPORT then
        pulse(teleportBtn)

        local res = teleportRocket()

        if res == "norocket" then
            showError("Ракета не найдена! Заспавнь BombMissile")
        elseif res == "notargets" then
            showError("Нет других игроков для телепорта")
        end
    elseif input.KeyCode == KEY_MOUSEFREE then
        pulse(mouseBtn)
        setMouseFree(not mouseFree)
    elseif input.KeyCode == KEY_SPEED then
        pulse(speedBtn)
        setSpeed(not speedOn)
    elseif input.KeyCode == KEY_SPEEDMODE then
        pulse(modeBtn)
        toggleSpeedMode()
    elseif input.KeyCode == KEY_AUTOPRESS then
        pulse(autopressBtn)
        autoPress()
    elseif input.KeyCode == KEY_UNLOAD then
        unload()
    end
end))

-- Отпускание клавиш (для снятия якоря с V)
track(UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == KEY_STOP then
        stopHeld = false

        if anchoredByUs then
            local body = getRocket()
            if body then
                body.Anchored = false
            end
            anchoredByUs = false
        end
    end
end))

--------------------------- ГЛАВНЫЙ ЦИКЛ -----------------------------
track(RunService.RenderStepped:Connect(function(dt)
    -- Камера может пересоздаться (например, при респавне)
    camera = workspace.CurrentCamera

    local body = getRocket()

    -- Ракета исчезла (взорвалась / удалена)
    if not body then
        local wasActive = camOn or steerOn or speedOn

        -- Первый кадр после пропадания ракеты — запускаем hold:
        -- замораживаем камеру на последней позиции на AUTOPRESS_EXPLOSION_HOLD сек.
        -- Это даёт игроку увидеть взрыв/последствия, потом камера вернётся.
        if wasActive and explosionHoldUntil == 0 then
            explosionHoldUntil = tick() + AUTOPRESS_EXPLOSION_HOLD
            -- Если успели сохранить последний CFrame — фиксируем Scriptable
            if explosionCamCFrame then
                pcall(function() camera.CameraType = Enum.CameraType.Scriptable end)
            end
        end

        -- Пока hold не истёк — держим камеру на последнем кадре.
        -- Картинку-кокпит НЕ трогаем (остаётся видимой если была — для эффекта взрыва).
        if explosionHoldUntil ~= 0 and tick() < explosionHoldUntil then
            if explosionCamCFrame then
                pcall(function() camera.CFrame = explosionCamCFrame end)
            end
            return
        end

        -- Hold истёк (или управления не было) — финальная зачистка
        explosionHoldUntil = 0
        explosionCamCFrame = nil

        -- Скрываем full-screen картинку, если она была
        if screenFill.Visible then
            screenFill.Visible = false
        end

        -- Возвращаем видимость ракеты (если вдруг ещё какие-то части остались)
        unhideMissileLocally()

        if camOn then
            setCam(false)
        end

        if steerOn then
            setSteer(false)
        end

        if speedOn then
            speedOn = false
            updateGui()
        end

        -- Ошибка показываем один раз, только если ракету использовали
        if wasActive then
            showError("Ракета не найдена!")
        end

        anchoredByUs = false

        return
    end

    -- Тело снова появилось (новая ракета через AutoPress) — сбрасываем hold
    if explosionHoldUntil ~= 0 then
        explosionHoldUntil = 0
        explosionCamCFrame = nil
    end

    -- Если сменилась модель ракеты (новый AutoPress) — сброс счётчиков полёта
    if flightMissileRef ~= body then
        flightMissileRef = body
        flightStartTick = tick()
        flightDistance = 0
    end

    -- Сохраняем последний camera.CFrame — на случай взрыва в следующем кадре
    if camOn then
        explosionCamCFrame = camera.CFrame
    end

    -- FULL-SCREEN «КОКПИТ»: показываем картинку на весь экран,
    -- если камера от ракеты включена И мы в 1-м лице (dist камера↔ракета <= порога).
    if camOn then
        local camDist = (camera.CFrame.Position - body.Position).Magnitude
        local wantVisible = camDist <= AUTOPRESS_FP_DIST
        if screenFill.Visible ~= wantVisible then
            screenFill.Visible = wantVisible
        end
    elseif screenFill.Visible then
        screenFill.Visible = false
    end

    -- Считаем актуальную скорость (studs/sec) и интегрируем дистанцию
    local spsNow = body.AssemblyLinearVelocity.Magnitude
    flightDistance = flightDistance + spsNow * dt

    -- ALT: высота над землёй через raycast вниз. Если луч ни во что не упёрся —
    -- берём Y координату (относительно 0 мира).
    local altValue = body.Position.Y
    local rayDir = Vector3.new(0, -1, 0)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    -- Исключаем саму ракету из рейкаста
    local excList = { body }
    local missile = body.Parent
    if missile then
        table.insert(excList, missile)
    end
    rayParams.FilterDescendantsInstances = excList
    local ray = Workspace:Raycast(body.Position, rayDir * 5000, rayParams)
    if ray then
        altValue = body.Position.Y - ray.Position.Y
    end

    -- DIST% (от дистанции полёта в стадах)
    local distPct = 100
    if flightDistance >= HUD_DIST_MAX_STUDS then
        distPct = 0
    elseif flightDistance > HUD_DIST_FULL_STUDS then
        -- Линейная интерполяция между full и max
        distPct = math.floor(
            (1 - (flightDistance - HUD_DIST_FULL_STUDS)
                / (HUD_DIST_MAX_STUDS - HUD_DIST_FULL_STUDS)) * 100 + 0.5
        )
    end

    -- FLIGHT: время с момента заспавна ракеты
    local flightSec = tick() - flightStartTick

    -- Обновляем HUD (только когда camOn — иначе прячем)
    if camOn then
        if not hudGui.Enabled then
            hudGui.Enabled = true
        end
        spsLabel.Text    = ("SPS %d"):format(math.floor(spsNow + 0.5))
        altLabel.Text    = ("ALT %d"):format(math.floor(altValue + 0.5))
        flightLabel.Text = ("FLIGHT %.1fs"):format(flightSec)
        distLabel.Text   = ("DIST %d%%"):format(distPct)
    elseif hudGui.Enabled then
        hudGui.Enabled = false
    end

    -- ПОКА V ЗАЖАТА (до якоря) — постоянно гасим скорость,
    -- чтобы рабочий код полёта не разгонял ракету обратно
    if stopHeld and not anchoredByUs then
        body.AssemblyLinearVelocity = Vector3.zero
        body.AssemblyAngularVelocity = Vector3.zero
    end

    -- CUSTOM SPEED
    -- Пока ракета остановлена вручную (V) — контроль скорости не мешает
    if speedOn and not stopHeld and not anchoredByUs then
        applyCustomSpeed(body, dt)
    end

    -- ПОВОРОТ РАКЕТЫ ЗА КАМЕРОЙ
    if steerOn then
        -- Строим вектора
        local camLook = camera.CFrame.LookVector
        local lookPoint = body.Position + camLook

        -- Целевая ориентация: носом в сторону взгляда камеры
        local target = CFrame.lookAt(body.Position, lookPoint) * NOSE_FIX

        -- Плавный доворот, не зависящий от FPS
        local alpha = 1 - math.exp(-STEER_SPEED * dt)
        body.CFrame = body.CFrame:Lerp(target, alpha)
    end
end))

----------------------- CAMERA TILT (DRONE BANK) ---------------------
-- Отдельный BindToRenderStep с приоритетом ВЫШЕ Camera — отрабатывает
-- ПОСЛЕ позиционирования камеры движком и докручивает roll (крен) в
-- сторону поворота. Потом плавно стабилизируется на 0 (как дрон).
-- (TILT_BIND_NAME объявлен выше, в секции state, чтобы unload() видел.)
local function tiltUpdate()
    if unloaded then return end
    if not camOn then
        tiltLastYaw = nil
        return
    end

    local body = getRocket()
    if not body then
        tiltLastYaw = nil
        return
    end

    -- Только в 1-м лице (как пользователь просил)
    local camDist = (camera.CFrame.Position - body.Position).Magnitude
    if camDist > AUTOPRESS_FP_DIST then
        -- Не 1-е лицо: крен плавно гаснет
        tiltCurrent = tiltCurrent * 0.85
        tiltLastYaw = nil
        if math.abs(tiltCurrent) > 0.0005 then
            camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, tiltCurrent)
        end
        return
    end

    -- Текущий yaw камеры (вокруг оси Y)
    local lv = camera.CFrame.LookVector
    local yaw = math.atan2(-lv.X, -lv.Z)

    if tiltLastYaw == nil then
        tiltLastYaw = yaw
    else
        local dy = yaw - tiltLastYaw
        -- Нормализация в [-π, π]
        while dy > math.pi do dy = dy - 2 * math.pi end
        while dy < -math.pi do dy = dy + 2 * math.pi end
        tiltLastYaw = yaw

        if math.abs(dy) < TILT_DEADZONE then
            dy = 0
        end

        -- Целевой крен: пропорционален скорости поворота
        local target = dy * TILT_GAIN
        if target > TILT_MAX then target = TILT_MAX end
        if target < -TILT_MAX then target = -TILT_MAX end

        -- Сглаживание к цели
        tiltCurrent = tiltCurrent + (target - tiltCurrent) * 0.22

        -- Когда поворот прекратился — крен плавно к 0
        if dy == 0 then
            tiltCurrent = tiltCurrent * (1 - TILT_SMOOTH)
            if math.abs(tiltCurrent) < 0.0005 then
                tiltCurrent = 0
            end
        end
    end

    if math.abs(tiltCurrent) > 0.0005 then
        camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, tiltCurrent)
    end
end
pcall(function()
    RunService:BindToRenderStep(
        TILT_BIND_NAME,
        Enum.RenderPriority.Camera.Value + 1,  -- после камеры
        tiltUpdate
    )
end)

--------------------- ВХОДНАЯ АНИМАЦИЯ МЕНЮ --------------------------
do
    -- Панель выезжает слева с отскоком
    local finalPos = frame.Position
    frame.Position = finalPos - UDim2.fromOffset(300, 0)
    tween(frame, {Position = finalPos}, 0.45, Enum.EasingStyle.Back)

    -- Заголовок плавно проявляется
    title.TextTransparency = 1
    task.delay(0.1, function()
        if unloaded then return end
        tween(title, {TextTransparency = 0}, 0.35)
    end)

    -- Кнопки появляются по очереди
    local btns = {camBtn, steerBtn, stopBtn, teleportBtn, mouseBtn,
                  speedBtn, modeBtn, autopressBtn, unloadBtn}
    for i, btn in ipairs(btns) do
        local sc = btn:FindFirstChildOfClass("UIScale")
        sc.Scale = 0

        task.delay(0.12 + i * 0.05, function()
            if unloaded then return end
            tween(sc, {Scale = 1}, 0.3, Enum.EasingStyle.Back)
        end)
    end
end

-- Первичная отрисовка состояния кнопок и ползунка
updateSliderVisual()
updateGui()
