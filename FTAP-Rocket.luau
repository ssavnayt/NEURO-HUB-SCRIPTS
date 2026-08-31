--=====================================================================--
--  Z    — камера от лица ракеты (Follow, зум колесом мыши как обычно)
--  X    — поворот ракеты в сторону, куда смотрит камера
--  V    — стоп ракеты (убрать Velocity), удержание — полный якорь
--  B    — телепорт ракеты к случайному игроку (кроме себя)
--  M    — разблокировать мышь (чтобы кликать по меню)
--  T    — Custom Speed вкл/выкл
--  G    — режим скорости: Множитель / Своя скорость
--  Del  — выгрузка скрипта (Unload): отключение всего и очистка
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
local KEY_UNLOAD    = Enum.KeyCode.Delete -- бинд выгрузки

local STEER_SPEED = 100            -- скорость доворота ракеты

local ZOOM_MIN   = 0.5             -- мин зум (0.5 = от первого лица ракеты)
local ZOOM_MAX   = 30              -- макс отдаление
local ZOOM_START = 0.5             -- стартовый зум (0.5 = первое лицо)

local CAM_OFFSET = Vector3.new(0, 2, 0)  -- точка "головы" ракеты

local HOLD_ANCHOR_TIME = 0.35      -- сколько держать V, чтобы заанчорить

local TELEPORT_OFFSET = Vector3.new(0, 5, 0) -- телепорт над головой игрока

-- Custom Speed
local MULT_MAX    = 3              -- максимум множителя (3 = 300% скорости игры)
local ABS_MAX     = 200            -- макс скорость в режиме "Своя" (стад/с)
local PCT_DEFAULT = 1 / 3          -- стартовое положение ползунка (= 100%)

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
-- Ищет "Body" ракеты в папке заспавненных игрушек игрока.
local function getRocket()
    local toys = workspace:FindFirstChild(player.Name .. "SpawnedInToys")

    -- Приоритетный поиск в toys
    if toys then
        local missile = toys:FindFirstChild("BombMissile")
        if missile then
            return missile:FindFirstChild("Body")
        end
    end

    -- Запасной поиск в workspace.Other
    local other = workspace:FindFirstChild("Other")
    if other then
        local missile = other:FindFirstChild("BombMissile")
        if missile then
            return missile:FindFirstChild("Body")
        end
    end

    return nil
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

-- Делаем frame
local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(240, 362)
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
local unloadBtn   = makeBtn(320)

stopBtn.Text     = "[V]  Стоп ракеты (удерж. = якорь)"
teleportBtn.Text = "[B]  Телепорт к игроку (рандом)"
modeBtn.Text     = "[G]  Режим:  Множитель"
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
end

unloadBtn:SetAttribute("BaseColor", Color3.fromRGB(140, 45, 45))
unloadBtn.BackgroundColor3 = Color3.fromRGB(140, 45, 45)

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

----------------------------- UNLOAD ---------------------------------
-- Полная выгрузка скрипта
local function unload()
    if unloaded then
        return -- защита от повторного вызова
    end
    unloaded = true

    stopHeld = false
    speedOn  = false

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

    -- Ракета исчезла (взорвалась / удалена) — выключаем всё
    if not body then
        local wasActive = camOn or steerOn or speedOn

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
                  speedBtn, modeBtn, unloadBtn}
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
