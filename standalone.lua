-- Standalone client utility port. No sharedRequire, remote code, or downloaded assets.
-- Run on the client. Server validation can reject movement and remote requests.
-- Removed: save-corruption rollback, anti-cheat bypass, and spoofed fall checks.
-- Thunderstorm finder makes one hop; execute again after teleporting to keep searching.

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local Run = game:GetService('RunService')
local Lighting = game:GetService('Lighting')
local Input = game:GetService('UserInputService')
local StarterGui = game:GetService('StarterGui')
local Http = game:GetService('HttpService')
local Teleport = game:GetService('TeleportService')
local Chat = game:GetService('TextChatService')
local me = Players.LocalPlayer
assert(me, 'Run this script on the client.')
local MAIN_PLACE_ID = 10266164381
local environment = _G
if type(getgenv) == 'function' then environment = getgenv() end
if type(environment.StandaloneUtilityCleanup) == 'function' then
    pcall(environment.StandaloneUtilityCleanup)
end

local alive = true
local connections, instances = {}, {}
local flags, collisionCache, killCache, esp = {}, {}, {}, {}
local savedSpeed, flight, flightAttachment, savedAutoRotate
local farmTarget, lastFarmScan, lastFarmClick = nil, -math.huge, -math.huge
local farmClick = type(mouse1click) == 'function' and mouse1click or nil
local farmHealthPaused, farmClickFailed = false, false
local spectating, danger = nil, false
local original = {FogEnd = Lighting.FogEnd, Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime}
local rainOriginal, rainObject
local events = RS:FindFirstChild('Events')
local dataEvent = events and events:FindFirstChild('DataEvent')
local dataFunction = events and events:FindFirstChild('DataFunction')
local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end
local function new(class, properties, parent)
    local object = Instance.new(class)
    for key, value in pairs(properties or {}) do object[key] = value end
    object.Parent = parent
    return object
end
local function notify(message)
    warn('[Standalone] ' .. tostring(message))
    pcall(function() StarterGui:SetCore('SendNotification', {
        Title = 'eishi is the king', Text = tostring(message), Duration = 5}) end)
end
local function character()
    local model = me.Character
    return model, model and model:FindFirstChild('HumanoidRootPart'),
        model and model:FindFirstChildOfClass('Humanoid')
end
local function fire(...)
    if not dataEvent or not dataEvent:IsA('RemoteEvent') then
        notify('This game has no compatible Events.DataEvent.')
        return
    end
    dataEvent:FireServer(...)
end
local function clearFlight()
    if flight then flight:Destroy(); flight = nil end
    if flightAttachment then flightAttachment:Destroy(); flightAttachment = nil end
    if savedAutoRotate then
        local humanoid, value = savedAutoRotate[1], savedAutoRotate[2]
        if humanoid.Parent then humanoid.AutoRotate = value end
        savedAutoRotate = nil
    end
end
local function restoreCollisions()
    for part, value in pairs(collisionCache) do
        if part.Parent then part.CanCollide = value end
    end
    table.clear(collisionCache)
end
local function restoreKillBricks()
    for part, parent in pairs(killCache) do
        pcall(function() part.Parent = parent end)
    end
    table.clear(killCache)
end
local gui = new('ScreenGui', {Name = 'StandaloneUtility', ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, me:WaitForChild('PlayerGui'))
table.insert(instances, gui)
local frame = new('Frame', {Size = UDim2.fromOffset(430, 530),
    Position = UDim2.new(0.5, -215, 0.5, -265),
    BackgroundColor3 = Color3.fromRGB(25, 27, 34), BorderSizePixel = 0}, gui)
new('UICorner', {CornerRadius = UDim.new(0, 10)}, frame)
local title = new('TextLabel', {Text = 'eishi is the king  |  RightShift: hide',
    Size = UDim2.new(1, -45, 0, 42), BackgroundTransparency = 1,
    TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 14}, frame)
local close = new('TextButton', {Text = 'X', Size = UDim2.fromOffset(38, 34),
    Position = UDim2.new(1, -41, 0, 4), BackgroundTransparency = 1,
    TextColor3 = Color3.new(1, 0.4, 0.4), TextSize = 18}, frame)
local scroll = new('ScrollingFrame', {Position = UDim2.fromOffset(10, 45),
    Size = UDim2.new(1, -20, 1, -55), BackgroundTransparency = 1,
    BorderSizePixel = 0, ScrollBarThickness = 5, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y}, frame)
new('UIListLayout', {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, scroll)
local order = 0
local function row(class, text, height)
    order = order + 1
    return new(class, {LayoutOrder = order, Size = UDim2.new(1, -8, 0, height or 32),
        BackgroundColor3 = Color3.fromRGB(39, 42, 53), BorderSizePixel = 0,
        Text = text, TextColor3 = Color3.fromRGB(235, 238, 245),
        Font = Enum.Font.Gotham, TextSize = 13}, scroll)
end
local function section(text)
    local label = row('TextLabel', text, 27)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
end
local function button(text, callback)
    local object = row('TextButton', text)
    connect(object.Activated, function()
        local ok, err = pcall(callback)
        if not ok then notify(err) end
    end)
    return object
end
local function toggle(key, label, callback)
    flags[key] = false
    local object
    object = button('[OFF] ' .. label, function()
        local desired = not flags[key]
        if callback then callback(desired) end
        flags[key] = desired
        object.Text = (desired and '[ON] ' or '[OFF] ') .. label
        object.TextColor3 = desired and Color3.fromRGB(120, 235, 170) or Color3.fromRGB(235, 238, 245)
    end)
end
local function field(label, default)
    local object = row('TextBox', tostring(default or ''))
    object.PlaceholderText = label
    object.ClearTextOnFocus = false
    return object
end
local function numberField(label, value, min, max)
    section(label)
    local box = field(label, value)
    connect(box.FocusLost, function()
        box.Text = tostring(math.clamp(tonumber(box.Text) or value, min, max))
    end)
    return function() return math.clamp(tonumber(box.Text) or value, min, max) end
end
local function cleanup()
    if not alive then return end
    alive = false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    clearFlight()
    restoreCollisions()
    restoreKillBricks()
    if savedSpeed and savedSpeed[1].Parent then savedSpeed[1].WalkSpeed = savedSpeed[2] end
    for key, value in pairs(original) do Lighting[key] = value end
    if rainObject and rainObject.Parent then rainObject.Value = rainOriginal end
    for _, item in pairs(esp) do item.gui:Destroy() end
    local _, _, humanoid = character()
    if workspace.CurrentCamera and humanoid then workspace.CurrentCamera.CameraSubject = humanoid end
    for _, object in ipairs(instances) do object:Destroy() end
    if environment.StandaloneUtilityCleanup == cleanup then environment.StandaloneUtilityCleanup = nil end
end
environment.StandaloneUtilityCleanup = cleanup
connect(close.Activated, cleanup)
connect(Input.InputBegan, function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.RightShift then frame.Visible = not frame.Visible end
end)
local dragging, dragStart, frameStart
connect(title.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, frameStart = true, input.Position, frame.Position
    end
end)
connect(Input.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
end)
connect(Input.InputChanged, function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(frameStart.X.Scale, frameStart.X.Offset + delta.X,
            frameStart.Y.Scale, frameStart.Y.Offset + delta.Y)
    end
end)

section('Movement')
toggle('fly', 'Fly (WASD, Space up, Ctrl down)', function(value)
    assert(not value or not flags.farm, 'Disable Mob Farm before enabling Fly.')
    if not value then clearFlight() end
end)
local flySpeed = numberField('Fly speed', 60, 0, 500)
toggle('speed', 'Custom walk speed', function(value)
    if not value and savedSpeed then
        if savedSpeed[1].Parent then savedSpeed[1].WalkSpeed = savedSpeed[2] end
        savedSpeed = nil
    end
end)
local moveSpeed = numberField('Walk speed', 32, 0, 500)
toggle('noclip', 'No clip', function(value) if not value then restoreCollisions() end end)
local function trackKill(part)
    if flags.noKill and (part.Name == 'Void' or part.Name == 'LavarossaVoid') and part:IsA('BasePart') and not killCache[part] then
        killCache[part] = part.Parent
        part.Parent = nil
    end
end
toggle('noKill', 'Remove named kill bricks locally', function(value)
    if value then
        -- Callback runs before toggle state changes.
        flags.noKill = true
        for _, part in ipairs(workspace:GetDescendants()) do trackKill(part) end
    else restoreKillBricks() end
end)
connect(workspace.DescendantAdded, trackKill)
button('Attach behind nearest humanoid', function()
    local char, root = character()
    assert(root, 'Character is not ready.')
    local nearest, distance = nil, math.huge
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA('Model') and obj ~= char and obj:FindFirstChildOfClass('Humanoid') then
            local npc = obj:FindFirstChild('NPC') or obj:FindFirstChild('Npc')
            local part = obj:FindFirstChild('HumanoidRootPart')
            if part and not (npc and npc.Value == 'Dialog') then
                local d = (part.Position - root.Position).Magnitude
                if d < distance then nearest, distance = part, d end
            end
        end
    end
    assert(nearest, 'No nearby target found.')
    root.CFrame = nearest.CFrame * CFrame.new(0, 0, 2)
end)
button('Reset character', function()
    local _, _, humanoid = character()
    if humanoid then humanoid.Health = 0 end
end)
button('Remove local ForceField', function()
    local char = me.Character
    local ff = char and char:FindFirstChildOfClass('ForceField')
    if ff then ff:Destroy() end
end)
button('Disconnect (blocked while danger flag is active)', function()
    if danger then notify('You are in danger.'); return end
    me:Kick('Disconnected using eishi is the king.')
end)

section('Bloodlines — mob farm')
section('Optional target: exact mob name (case insensitive)')
local farmName = field('Enter mob name, for example Bandit')
toggle('farmNameFilter', 'Only farm the entered mob name', function(value)
    if value then
        assert(farmName.Text:match('^%s*(.-)%s*$') ~= '', 'Enter a mob name before enabling the name filter.')
    end
    farmTarget, lastFarmScan = nil, -math.huge
end)
connect(farmName.FocusLost, function()
    farmName.Text = farmName.Text:match('^%s*(.-)%s*$')
    farmTarget, lastFarmScan = nil, -math.huge
end)
toggle('farm', 'Mob farm: hover + repeated clicks', function(value)
    if value then
        assert(farmClick, 'Repeated attacks require the mouse1click function in your client environment.')
        assert(not flags.fly, 'Disable Fly before enabling Mob Farm.')
        farmTarget, lastFarmScan, lastFarmClick = nil, -math.huge, -math.huge
        farmHealthPaused, farmClickFailed = false, false
        notify('Farm enabled. Hide this menu with RightShift to allow attack clicks. Hovering does not guarantee protection.')
    else
        farmTarget = nil
    end
end)
local farmHeight = numberField('Farm height above mob (studs)', 6, 0, 20)
local farmOffset = numberField('Farm distance behind mob (studs)', 2, 1, 10)
local farmRange = numberField('Farm target search radius (studs)', 150, 10, 1000)
local farmInterval = numberField('Attack click interval (seconds)', 0.4, 0.15, 3)
local farmMinHealth = numberField('Pause farm below health percent', 20, 0, 99)
local function combatMob(model)
    if not model or not model:IsA('Model') or not model:IsDescendantOf(workspace)
        or Players:GetPlayerFromCharacter(model) then return nil end
    if flags.farmNameFilter then
        local wanted = farmName.Text:match('^%s*(.-)%s*$'):lower()
        if wanted == '' or model.Name:lower() ~= wanted then return nil end
    end
    local marker = model:FindFirstChild('NPC') or model:FindFirstChild('Npc')
    if not marker or not marker:IsA('StringValue') or marker.Value ~= 'Combat' then return nil end
    local humanoid = model:FindFirstChildOfClass('Humanoid')
    local root = model:FindFirstChild('HumanoidRootPart') or model.PrimaryPart
    if humanoid and humanoid.Health > 0 and root and root:IsA('BasePart') then return root end
    return nil
end
local function updateFarm(root, humanoid)
    if not flags.farm or farmClickFailed or not root or not humanoid or humanoid.Health <= 0 then
        farmTarget = nil
        return
    end
    local healthPercent = humanoid.Health / math.max(humanoid.MaxHealth, 1) * 100
    if healthPercent < farmMinHealth() then
        farmTarget = nil
        if not farmHealthPaused then
            notify('Mob farm paused: low health. This does not move you to safety.')
            farmHealthPaused = true
        end
        return
    end
    farmHealthPaused = false
    local targetRoot = combatMob(farmTarget)
    if targetRoot and (targetRoot.Position - root.Position).Magnitude > farmRange() then targetRoot = nil end
    if not targetRoot then
        farmTarget = nil
        if os.clock() - lastFarmScan < 0.5 then return end
        lastFarmScan = os.clock()
        local nearest = farmRange()
        for _, model in ipairs(workspace:GetChildren()) do
            local candidate = combatMob(model)
            if candidate then
                local distance = (candidate.Position - root.Position).Magnitude
                if distance <= nearest then
                    nearest, farmTarget, targetRoot = distance, model, candidate
                end
            end
        end
    end
    if not targetRoot then return end
    local position = (targetRoot.CFrame * CFrame.new(0, 0, farmOffset())).Position
        + Vector3.new(0, farmHeight(), 0)
    local facing = Vector3.new(targetRoot.Position.X, position.Y, targetRoot.Position.Z)
    root.CFrame = CFrame.lookAt(position, facing)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

section('Visuals')
toggle('fog', 'No fog', function(value) if not value then Lighting.FogEnd = original.FogEnd end end)
toggle('bright', 'Full bright', function(value) if not value then Lighting.Brightness = original.Brightness end end)
local brightness = numberField('Brightness', 3, 1, 10)
toggle('rain', 'No rain', function(value)
    local object = RS:FindFirstChild('Raining')
    if value then
        assert(object and object:IsA('StringValue'), 'Compatible Raining StringValue was not found.')
        rainObject, rainOriginal = object, object.Value
    elseif rainObject and rainObject.Parent then rainObject.Value = rainOriginal end
end)
toggle('time', 'Override time', function(value) if not value then Lighting.ClockTime = original.ClockTime end end)
local clockTime = numberField('Time (0–24; morning 6.3, afternoon 14, evening 18)', 14, 0, 24)
section('ESP')
toggle('playerESP', 'Player names / locations')
toggle('playerHealthESP', 'Show player health')
toggle('npcESP', 'NPC names')
toggle('mobESP', 'Mob names')
toggle('areaESP', 'Area names')
toggle('healthESP', 'Show mob health')
toggle('distanceESP', 'Show distance')
local maxDistance = numberField('ESP max distance', 10000, 100, 100000)
local function espEntry(target, part, kind, player)
    local existing = esp[target]
    if existing then
        if existing.part == part then return end
        existing.gui:Destroy()
        esp[target] = nil
    end
    local billboard = new('BillboardGui', {Name = 'StandaloneESP', Adornee = part,
        Size = UDim2.fromOffset(240, 48), StudsOffset = Vector3.new(0, 3, 0),
        AlwaysOnTop = true, Enabled = false}, gui)
    local label = new('TextLabel', {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        TextColor3 = kind == 'mobESP' and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(150, 220, 255),
        TextStrokeTransparency = 0.3, Font = Enum.Font.GothamBold, TextSize = 13}, billboard)
    esp[target] = {gui = billboard, label = label, part = part, kind = kind, player = player}
end
local function discoverPlayers()
    if not flags.playerESP then return end
    for _, player in ipairs(Players:GetPlayers()) do
        local model = player.Character
        local part = model and (model:FindFirstChild('HumanoidRootPart') or model:FindFirstChild('Head'))
        if player ~= me and model and model:IsDescendantOf(workspace) and part and part:IsA('BasePart') then
            espEntry(model, part, 'playerESP', player)
        end
    end
end
local function discoverESP()
    for _, object in ipairs(workspace:GetChildren()) do
        if object:IsA('Model') and not Players:GetPlayerFromCharacter(object) then
            local marker = object:FindFirstChild('NPC') or object:FindFirstChild('Npc')
            local part = object:FindFirstChild('HumanoidRootPart') or object:FindFirstChild('Main') or object.PrimaryPart
            if marker and part and part:IsA('BasePart') then
                if marker.Value == 'Dialog' then espEntry(object, part, 'npcESP')
                elseif marker.Value == 'Combat' then espEntry(object, part, 'mobESP') end
            end
        end
    end
    local locations = workspace:FindFirstChild('Locations')
    if locations then
        for _, object in ipairs(locations:GetChildren()) do
            local part = object:IsA('BasePart') and object or object:FindFirstChildWhichIsA('BasePart', true)
            if part then espEntry(object, part, 'areaESP') end
        end
    end
end

section('Teleports / spectate — enter exact names')
local playerName = field('Player username')
local function targetPlayer()
    local text = playerName.Text:match('^%s*(.-)%s*$')
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name:lower() == text:lower() then return player end
    end
    error('Enter an exact player username.')
end
local function teleportTo(part)
    local _, root = character()
    assert(root and part and part:IsA('BasePart'), 'Destination or character is unavailable.')
    root.CFrame = part.CFrame * CFrame.new(0, 0, 5)
end
button('Teleport to player', function()
    local target = targetPlayer()
    teleportTo(target.Character and target.Character:FindFirstChild('HumanoidRootPart'))
end)
button('Spectate player', function()
    local target = targetPlayer()
    local humanoid = target.Character and target.Character:FindFirstChildOfClass('Humanoid')
    assert(humanoid and workspace.CurrentCamera, 'Target character is not ready.')
    spectating = target
    workspace.CurrentCamera.CameraSubject = humanoid
end)
button('Stop spectating', function()
    spectating = nil
    local _, _, humanoid = character()
    if humanoid and workspace.CurrentCamera then workspace.CurrentCamera.CameraSubject = humanoid end
end)
local npcName = field('NPC name')
button('Teleport to NPC', function()
    local npc = workspace:FindFirstChild(npcName.Text)
    assert(npc, 'NPC was not found.')
    teleportTo(npc:FindFirstChild('HumanoidRootPart') or npc:FindFirstChild('Main') or npc:FindFirstChildWhichIsA('BasePart', true))
end)
local pointName = field('Chakra point name')
button('Teleport to chakra point', function()
    local folder = workspace:FindFirstChild('ChakraPoints')
    if folder then
        for _, point in ipairs(folder:GetChildren()) do
            local name = point:FindFirstChild('PointName')
            if name and name.Value == pointName.Text then teleportTo(point:FindFirstChild('Main')); return end
        end
    end
    error('Chakra point was not found.')
end)
button('List NPC / chakra names in console', function()
    for _, obj in ipairs(workspace:GetChildren()) do
        local marker = obj:FindFirstChild('NPC') or obj:FindFirstChild('Npc')
        if marker and marker.Value == 'Dialog' then print('NPC:', obj.Name) end
    end
    local folder = workspace:FindFirstChild('ChakraPoints')
    if folder then for _, obj in ipairs(folder:GetChildren()) do
        local name = obj:FindFirstChild('PointName')
        if name then print('Chakra:', name.Value) end
    end end
    notify('Names printed in the console.')
end)

section('Game-specific actions')
toggle('pickup', 'Auto pickup within 50 studs')
local itemName = field('Item name')
button('Purchase one item (original Pay request)', function()
    assert(itemName.Text ~= '', 'Enter an item name.')
    assert(dataFunction and dataFunction:IsA('RemoteFunction'), 'Compatible DataFunction was not found.')
    local result = dataFunction:InvokeServer('Pay', 1, itemName.Text, 1)
    notify('Request completed; server decides the result. See console.')
    print('[Standalone purchase result]', result)
end)
button('List purchasable items in console', function()
    local module = RS:FindFirstChild('GameManager')
    assert(module and module:IsA('ModuleScript'), 'GameManager was not found.')
    local manager = require(module)
    for name, item in pairs(manager.Items or {}) do
        if item.Buyabble or item.Buyable then print('Item:', name) end
    end
    notify('Items printed in the console.')
end)

section('Alerts / chat')
toggle('memberAlert', 'Group 7450839 member alerts (rank > 0)')
toggle('soundAlert', 'Alert sound')
toggle('chakraAlert', 'Chakra Sense notifications')
local function sound()
    if not flags.soundAlert then return end
    local alert = new('Sound', {SoundId = 'rbxasset://sounds/electronicpingshort.wav',
        Volume = 1}, game:GetService('SoundService'))
    table.insert(instances, alert)
    alert:Play()
    game:GetService('Debris'):AddItem(alert, 4)
end
local logLabel = row('TextLabel', '', 130)
logLabel.TextWrapped = true
logLabel.TextXAlignment = Enum.TextXAlignment.Left
logLabel.TextYAlignment = Enum.TextYAlignment.Top
logLabel.Visible = false
local messages = {}
toggle('chat', 'Chat logger', function(value) logLabel.Visible = value end)
local function log(name, text)
    if not flags.chat then return end
    table.insert(messages, os.date('%H:%M:%S') .. ' [' .. name .. '] ' .. text)
    while #messages > 6 do table.remove(messages, 1) end
    logLabel.Text = table.concat(messages, '\n')
end
if Chat.ChatVersion == Enum.ChatVersion.TextChatService then
    connect(Chat.MessageReceived, function(message)
        local source = message.TextSource
        local player = source and Players:GetPlayerByUserId(source.UserId)
        log(player and player.Name or 'System', message.Text)
    end)
else
    local chatEvents = RS:FindFirstChild('DefaultChatSystemChatEvents')
    local filtered = chatEvents and chatEvents:FindFirstChild('OnMessageDoneFiltering')
    if filtered then connect(filtered.OnClientEvent, function(message)
        log(message.FromSpeaker or 'Unknown', message.Message or '')
    end) end
end
local members = {}
local function inspectPlayer(player)
    task.spawn(function()
        for attempt = 1, 3 do
            if not alive or player.Parent ~= Players then return end
            local ok, rank = pcall(function() return player:GetRankInGroup(7450839) end)
            if ok then
                if not alive then return end
                members[player] = rank > 0
                if rank > 0 and flags.memberAlert then
                    notify(player.Name .. ' is in group 7450839 (rank ' .. rank .. ').')
                    sound()
                end
                return
            end
            task.wait(attempt)
        end
    end)
end
for _, player in ipairs(Players:GetPlayers()) do inspectPlayer(player) end
connect(Players.PlayerAdded, inspectPlayer)
connect(Players.PlayerRemoving, function(player)
    if members[player] and flags.memberAlert then notify('Group member left: ' .. player.Name); sound() end
    members[player] = nil
    if spectating == player then
        spectating = nil
        local _, _, humanoid = character()
        if humanoid and workspace.CurrentCamera then workspace.CurrentCamera.CameraSubject = humanoid end
    end
end)
if dataEvent and dataEvent:IsA('RemoteEvent') then connect(dataEvent.OnClientEvent, function(event)
    if event == 'InDanger' then danger = true elseif event == 'OutOfDanger' then danger = false end
end) end
local function watchCooldown(folder)
    local function inspect(obj)
        if flags.chakraAlert and obj.Name == 'Chakra Sense' then notify(folder.Name .. ' has Chakra Sense.') end
    end
    connect(folder.ChildAdded, inspect)
    for _, obj in ipairs(folder:GetChildren()) do inspect(obj) end
end
local watchedCooldowns = {}
local function attachCooldowns(folder)
    if folder.Name ~= 'Cooldowns' or watchedCooldowns[folder] then return end
    watchedCooldowns[folder] = true
    connect(folder.ChildAdded, watchCooldown)
    for _, child in ipairs(folder:GetChildren()) do watchCooldown(child) end
end
connect(RS.ChildAdded, attachCooldowns)
local cooldowns = RS:FindFirstChild('Cooldowns')
if cooldowns then attachCooldowns(cooldowns) end

section('Server finder')
local searching = false
button('Find thunderstorm server — one hop', function()
    if searching then return end
    if workspace:FindFirstChild('Thunderstorm') then notify('Thunderstorm found in this server.'); return end
    local requestFunction = request or http_request or (syn and syn.request)
    assert(type(requestFunction) == 'function', 'Server listing requires an executor HTTP request function.')
    assert(game.PlaceId == MAIN_PLACE_ID, 'This finder only supports the original gameplay place.')
    searching = true
    task.spawn(function()
        local ok, err = pcall(function()
            local cursor, candidates = '', {}
            for page = 1, 5 do
                if not alive then return end
                local url = 'https://games.roblox.com/v1/games/' .. MAIN_PLACE_ID .. '/servers/Public?sortOrder=Asc&limit=100'
                if cursor ~= '' then url = url .. '&cursor=' .. Http:UrlEncode(cursor) end
                local response = requestFunction({Url = url, Method = 'GET'})
                assert(response and (response.StatusCode == 200 or response.Success == true), 'Server listing failed or was rate limited.')
                local decoded = Http:JSONDecode(response.Body)
                for _, server in ipairs(decoded.data or {}) do
                    if server.id ~= game.JobId and server.playing < server.maxPlayers then table.insert(candidates, server.id) end
                end
                cursor = decoded.nextPageCursor
                if #candidates > 0 or not cursor then break end
                task.wait(1)
            end
            if not alive then return end
            assert(#candidates > 0, 'No available server found.')
            notify('Hopping. Run this script again in the next server to check its weather.')
            Teleport:TeleportToPlaceInstance(MAIN_PLACE_ID, candidates[math.random(1, #candidates)], me)
        end)
        searching = false
        if not ok and alive then notify(err) end
    end)
end)

-- Frame work is restricted to movement / lighting; scans use slower intervals.
connect(Run.PreSimulation, function()
    local char, root, humanoid = character()
    updateFarm(root, humanoid)
    if flags.noclip and char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA('BasePart') then
                if collisionCache[part] == nil then collisionCache[part] = part.CanCollide end
                part.CanCollide = false
            end
        end
    end
    if flags.speed and humanoid then
        if not savedSpeed or savedSpeed[1] ~= humanoid then savedSpeed = {humanoid, humanoid.WalkSpeed} end
        humanoid.WalkSpeed = moveSpeed()
    end
    if flags.fly and root and humanoid then
        if not flight or flight.Parent ~= root then
            clearFlight()
            savedAutoRotate = {humanoid, humanoid.AutoRotate}
            humanoid.AutoRotate = false
            flightAttachment = new('Attachment', {}, root)
            flight = new('LinearVelocity', {Attachment0 = flightAttachment,
                RelativeTo = Enum.ActuatorRelativeTo.World, MaxForce = math.huge,
                VectorVelocity = Vector3.zero}, root)
        end
        local camera = workspace.CurrentCamera
        local direction = Vector3.zero
        if camera and not Input:GetFocusedTextBox() then
            if Input:IsKeyDown(Enum.KeyCode.W) then direction = direction + camera.CFrame.LookVector end
            if Input:IsKeyDown(Enum.KeyCode.S) then direction = direction - camera.CFrame.LookVector end
            if Input:IsKeyDown(Enum.KeyCode.D) then direction = direction + camera.CFrame.RightVector end
            if Input:IsKeyDown(Enum.KeyCode.A) then direction = direction - camera.CFrame.RightVector end
            if Input:IsKeyDown(Enum.KeyCode.Space) then direction = direction + Vector3.yAxis end
            if Input:IsKeyDown(Enum.KeyCode.LeftControl) then direction = direction - Vector3.yAxis end
        end
        if direction.Magnitude > 1 then direction = direction.Unit end
        flight.VectorVelocity = direction * flySpeed()
    elseif flight then clearFlight() end
    if flags.fog then Lighting.FogEnd = 1e9 end
    if flags.bright then Lighting.Brightness = brightness() end
    if flags.time then Lighting.ClockTime = clockTime() end
    if flags.rain and rainObject and rainObject.Parent then rainObject.Value = '' end
end)
local elapsed, discovery = 0, 0
local pickupTimes = setmetatable({}, {__mode = 'k'})
connect(Run.Heartbeat, function(delta)
    elapsed, discovery = elapsed + delta, discovery + delta
    if elapsed < 0.25 then return end
    elapsed = 0
    local _, root = character()
    discoverPlayers()
    if flags.farm and not farmClickFailed and farmTarget and not farmHealthPaused and combatMob(farmTarget)
        and root and not frame.Visible and not Input:GetFocusedTextBox()
        and os.clock() - lastFarmClick >= farmInterval() then
        lastFarmClick = os.clock()
        local ok, err = pcall(farmClick)
        if not ok then
            farmClickFailed = true
            farmTarget = nil
            notify('Mob farm paused: automatic clicking failed: ' .. tostring(err))
        end
    end
    if discovery >= 2 then
        discovery = 0
        if flags.npcESP or flags.mobESP or flags.areaESP then discoverESP() end
    end
    for object, item in pairs(esp) do
        if not object:IsDescendantOf(workspace) or not item.part:IsDescendantOf(workspace)
            or (item.player and (item.player.Parent ~= Players or item.player.Character ~= object)) then
            item.gui:Destroy(); esp[object] = nil
        else
            local distance = root and (root.Position - item.part.Position).Magnitude or math.huge
            item.gui.Enabled = flags[item.kind] and distance <= maxDistance()
            if item.gui.Enabled then
                local text = object.Name
                if item.player then
                    local player = item.player
                    text = player.DisplayName == player.Name and player.Name
                        or (player.DisplayName .. ' (@' .. player.Name .. ')')
                    item.label.TextColor3 = (not player.Neutral and player.Team)
                        and player.TeamColor.Color or Color3.fromRGB(120, 235, 170)
                end
                local humanoid = object:FindFirstChildOfClass('Humanoid')
                local showHealth = (item.kind == 'mobESP' and flags.healthESP)
                    or (item.kind == 'playerESP' and flags.playerHealthESP)
                if showHealth and humanoid then
                    text = text .. string.format(' [%d/%d HP]', math.floor(humanoid.Health), math.floor(humanoid.MaxHealth))
                end
                if flags.distanceESP then text = text .. string.format(' [%d studs]', math.floor(distance)) end
                item.label.Text = text
            end
        end
    end
    if flags.pickup and root and dataEvent and dataEvent:IsA('RemoteEvent') then
        local sent = 0
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA('BasePart') and obj:FindFirstChild('Pickupable') then
                local id = obj:FindFirstChild('ID')
                if id and (root.Position - obj.Position).Magnitude < 50 and os.clock() - (pickupTimes[obj] or -math.huge) >= 1 then
                    pickupTimes[obj] = os.clock()
                    dataEvent:FireServer('PickUp', id.Value)
                    sent = sent + 1
                    if sent >= 5 then break end
                end
            end
        end
    end
end)
notify('Loaded. RightShift hides the menu; X unloads and restores tracked changes.')
if game.PlaceId ~= MAIN_PLACE_ID then notify('Different place: game-specific actions may be unavailable.') end

