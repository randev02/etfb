local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local CoreGui           = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer       = Players.LocalPlayer

-- KILLSWITCH
do
    local ok, res = pcall(function()
        return (syn and syn.request or http and http.request or request)({
            Url    = "https://edge-config.vercel.com/ecfg_lw7ewh9ixwhtrv6urupwuijxy2bw/item/script",
            Method = "GET",
            Headers = { ["Authorization"] = "Bearer f3ec411d-2b5b-467c-b012-8bbe726926b1" }
        })
    end)
    if not ok or not res or res.StatusCode ~= 200 then return end
    local body = res.Body and res.Body:gsub("%s+", ""):lower()
    if body ~= "true" then return end
end

RunService.RenderStepped:Connect(function()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local cam = workspace.CurrentCamera
    cam.CameraType = Enum.CameraType.Scriptable
    cam.CFrame = CFrame.new(hrp.Position + Vector3.new(-20, 15, 0), hrp.Position)
end)

local CFG = {
    LOCKED_Y         = -10.00,
    DEPOSIT_PATH     = {"GameObjects","PlaceSpecific","root","Tower","Main","Prompt","ProximityPrompt"},
    DIVINE_RARITIES  = {"divine","infinity"},
    WATCHDOG_TIMEOUT = 50,
    DASH_STEP        = 20,
    DASH_INTERVAL    = 0.01,
    DASH_THRESHOLD   = 4,
}

local function getDepositPos()
    local ok, pos = pcall(function()
        local main = workspace.GameObjects.PlaceSpecific.root.Tower.Main
        local p = main:IsA("BasePart") and main.Position or main:GetPivot().Position
        return Vector3.new(p.X - 7, p.Y - 45, p.Z - 0.4)
    end)
    return ok and pos or nil
end

local function getBonusDropPos()
    local ok, pos = pcall(function()
        local shop = workspace.GameObjects.PlaceSpecific.root.UpgradeShop
        local p = shop:IsA("BasePart") and shop.Position or shop:GetPivot().Position
        return p
    end)
    return ok and pos or nil
end

local function getClaimRemote()
    local ok, r = pcall(function()
        return ReplicatedStorage
            :WaitForChild("Shared", 5)
            :WaitForChild("Remotes", 5)
            :WaitForChild("Networking", 5)
            :WaitForChild("RE/Tower/TowerClaimConfirmed", 5)
    end)
    return ok and r or nil
end

local function getDropRemote()
    local ok, r = pcall(function()
        return ReplicatedStorage
            :WaitForChild("RemoteEvents", 5)
            :WaitForChild("DropBrainrot", 5)
    end)
    return ok and r or nil
end

local sessionId = 0
local running   = false
local died      = false
local preferredSide = "any"

local function newSession() sessionId += 1; return sessionId end
local function alive(sid)   return running and (sessionId == sid) end
local function getChar()    return LocalPlayer.Character end
local function getHRP()     local c = getChar(); return c and c:FindFirstChild("HumanoidRootPart") or nil end
local function getHum()     local c = getChar(); return c and c:FindFirstChildOfClass("Humanoid") or nil end
local function getBV()      local hrp = getHRP(); return hrp and hrp:FindFirstChild("NavBV") or nil end
local function setVel(v)    local bv = getBV(); if bv then bv.Velocity = v end end
local function isAlive()    local h = getHum(); return h ~= nil and h.Health > 0 end
local function canMove(sid) return alive(sid) and isAlive() end

local function hasRenderedBrainrot()
    local c = getChar()
    return c ~= nil and c:FindFirstChild("RenderedBrainrot") ~= nil
end

local function moveTo(target, sid, finalSnap)
    local hrp = getHRP()
    if not hrp then return end
    hrp.CFrame = CFrame.new(hrp.Position.X, CFG.LOCKED_Y, target.Z)
    setVel(Vector3.zero)
    hrp = getHRP()
    while canMove(sid) and hrp and math.abs(hrp.Position.X - target.X) > CFG.DASH_THRESHOLD do
        setVel(Vector3.zero)
        local dir  = target.X > hrp.Position.X and 1 or -1
        local step = math.min(CFG.DASH_STEP, math.abs(hrp.Position.X - target.X))
        hrp.CFrame = CFrame.new(hrp.Position.X + dir * step, hrp.Position.Y, hrp.Position.Z)
        setVel(Vector3.zero)
        task.wait(CFG.DASH_INTERVAL)
        hrp = getHRP()
    end
    if finalSnap and canMove(sid) and hrp then
        hrp.CFrame = CFrame.new(target)
        setVel(Vector3.zero)
    end
end

local function getHUD()
    local ok, h = pcall(function()
        return LocalPlayer:WaitForChild("PlayerGui")
            :WaitForChild("TowerTrialHUD", 2)
            :WaitForChild("TrialBar", 2)
    end)
    return ok and h or nil
end

local function safeText(obj)
    if not obj then return nil end
    local ok, v = pcall(function() return obj.Text end)
    return ok and v or nil
end

local function parseTimer(t)
    if not t then return nil end
    local m, s = t:match("(%d+):(%d+)")
    return m and (tonumber(m) * 60 + tonumber(s)) or nil
end

local function parseDeposits(t)
    if not t then return nil, nil end
    local a, b = t:match("(%d+)/(%d+)")
    return a and tonumber(a) or nil, b and tonumber(b) or nil
end

local function parseRarity(t)
    if not t then return nil end
    return t:match("<font[^>]*>([^<]+)</font>") or t:match(":%s*(.+)$")
end

local function readHUD()
    local hud = getHUD()
    if not hud then return nil end
    return {
        timer  = parseTimer(safeText(hud:FindFirstChild("Timer"))),
        rarity = parseRarity(safeText(hud:FindFirstChild("Requirement"))),
        depCur = select(1, parseDeposits(safeText(hud:FindFirstChild("Deposits")))),
        depMax = select(2, parseDeposits(safeText(hud:FindFirstChild("Deposits")))),
    }
end

local function findBrainrot(rarity)
    local folder = workspace:FindFirstChild("ActiveBrainrots")
    if not folder then return nil end
    for _, pass in ipairs({"exact","partial"}) do
        for _, f in ipairs(folder:GetChildren()) do
            if f:IsA("Folder") then
                local n = string.lower(f.Name)
                local r = string.lower(rarity)
                local match = (pass == "exact" and n == r) or (pass == "partial" and n:find(r, 1, true))
                if match then
                    local items = f:GetChildren()
                    -- Scan backwards from the end of the list to find the newest viable item
                    for i = #items, 1, -1 do
                        local item = items[i]
                        local pos = item:GetPivot().Position
                        local isEligible = false
                        
                        if preferredSide == "any" then
                            isEligible = true
                        elseif preferredSide == "pos" and pos.Z > 0 then
                            isEligible = true
                        elseif preferredSide == "neg" and pos.Z < 0 then
                            isEligible = true
                        end

                        if isEligible then return pos end
                    end
                end
            end
        end
    end
    return nil
end

local function findAllDivine()
    local folder = workspace:FindFirstChild("ActiveBrainrots")
    local results = {}
    if not folder then return results end
    for _, f in ipairs(folder:GetChildren()) do
        if f:IsA("Folder") then
            local n = string.lower(f.Name)
            for _, r in ipairs(CFG.DIVINE_RARITIES) do
                if n == r or n:find(r, 1, true) then
                    for _, item in ipairs(f:GetChildren()) do
                        table.insert(results, {name = f.Name, pos = item:GetPivot().Position, item = item})
                    end
                    break
                end
            end
        end
    end
    return results
end

local function configureInfinitePrompt(p)
    if p:IsA("ProximityPrompt") then
        p.HoldDuration = 0
        p.MaxActivationDistance = math.huge
    end
end

workspace.DescendantAdded:Connect(configureInfinitePrompt)

local function fireDepositPrompt()
    for _, d in ipairs(workspace:GetDescendants()) do configureInfinitePrompt(d) end
    local c = getChar()
    if c then local hum = c:FindFirstChildOfClass("Humanoid"); if hum then hum:UnequipTools() end end
    local ok, p = pcall(function()
        local obj = workspace
        for _, k in ipairs(CFG.DEPOSIT_PATH) do obj = obj[k] end
        return obj
    end)
    if ok and p then fireproximityprompt(p); return true end
    return false
end

local function fireNearestPrompt(pos)
    local best, bestDist = nil, math.huge
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local ok, dpos = pcall(function()
                return d.Parent:IsA("BasePart") and d.Parent.Position
                    or d.Parent:IsA("Model") and d.Parent:GetPivot().Position
            end)
            if ok and dpos then
                local dist = (dpos - pos).Magnitude
                if dist < bestDist then bestDist = dist; best = d end
            end
        end
    end
    if best then fireproximityprompt(best); return true end
    return false
end

task.spawn(function()
    local p = CoreGui:WaitForChild("PurchasePromptApp", 10)
    if p then p.Enabled = false end
end)
CoreGui.ChildAdded:Connect(function(c)
    if c.Name == "FoundationOverlay" then c.Enabled = false end
end)
do
    local fo = CoreGui:FindFirstChild("FoundationOverlay")
    if fo then fo.Enabled = false end
end

RunService.Stepped:Connect(function()
    local char = getChar()
    if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end
end)

local function setupCharacter(char)
    local hrp = char:WaitForChild("HumanoidRootPart")
    local hum = char:WaitForChild("Humanoid")
    for _, name in ipairs({"NavBV","NavBG"}) do
        local old = hrp:FindFirstChild(name)
        if old then old:Destroy() end
    end
    local bv = Instance.new("BodyVelocity", hrp)
    bv.Name = "NavBV"; bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge); bv.Velocity = Vector3.zero
    local bg = Instance.new("BodyGyro", hrp)
    bg.Name = "NavBG"; bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    hum.Died:Connect(function() died = true; setVel(Vector3.zero) end)
end

setupCharacter(LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait())
LocalPlayer.CharacterAdded:Connect(function(char) task.wait(0.5); setupCharacter(char) end)

local watchdogRunning = false
local lastPhaseChange = tick()
local mainLoop

local function setPhase() lastPhaseChange = tick() end

local function startWatchdog()
    if watchdogRunning then return end
    watchdogRunning = true
    task.spawn(function()
        while running do
            task.wait(5)
            if not running then break end
            if tick() - lastPhaseChange > CFG.WATCHDOG_TIMEOUT then
                lastPhaseChange = tick()
                watchdogRunning = false
                died = false
                task.wait(0.3)
                task.spawn(mainLoop, newSession())
                return
            end
        end
        watchdogRunning = false
    end)
end

local function waitForRespawn(sid)
    local deadline = tick() + 10
    while alive(sid) do
        task.wait(0.5)
        if isAlive() then task.wait(1); died = false; return true end
        if tick() > deadline then return false end
    end
    return false
end

local function claimAndScan(sid)
    if not alive(sid) then return end
    setPhase()
    local remote = getClaimRemote()
    if remote then
        for i = 1, 3 do
            if not alive(sid) then return end
            remote:FireServer(); task.wait(0.2)
        end
    end
    setPhase()
    local scanStart = tick()
    local attempted = {}
    while alive(sid) and (tick() - scanStart) < 5 do
        local fresh = {}
        for _, t in ipairs(findAllDivine()) do
            local seen = false
            for _, done in ipairs(attempted) do
                if (t.pos - done).Magnitude < 5 then seen = true; break end
            end
            if not seen then table.insert(fresh, t) end
        end
        if #fresh == 0 then task.wait(0.5); continue end
        for _, t in ipairs(fresh) do
            if not alive(sid) or (tick() - scanStart) >= 5 then break end
            table.insert(attempted, t.pos)
            moveTo(t.pos, sid, false)
            if not alive(sid) then break end
            local prompt = t.item and t.item:FindFirstChild("Root") and t.item.Root:FindFirstChild("TakePrompt")
            if prompt then fireproximityprompt(prompt)
            else fireNearestPrompt(getHRP() and getHRP().Position or t.pos) end
            task.wait(0.2)
        end
        if alive(sid) and hasRenderedBrainrot() then
            local dropPos = getBonusDropPos()
            if dropPos then
                moveTo(dropPos, sid, false)
                if alive(sid) then fireNearestPrompt(getHRP() and getHRP().Position or dropPos); task.wait(0.3) end
            end
        end
    end
end

mainLoop = function(sid)
    startWatchdog()
    while alive(sid) do
        task.wait(0.05)
        died = false
        setPhase()

        local frozenAt, skipWait = nil, false
        do
            local h1 = readHUD(); task.wait(1)
            if not alive(sid) then break end
            local h2 = readHUD()
            if h1 and h2 and h1.timer ~= nil and h2.timer ~= nil and h1.timer ~= h2.timer then
                skipWait = true
            end
            if not skipWait then
                local lastSec, stableAt = nil, nil
                while alive(sid) do
                    if died then waitForRespawn(sid); if not alive(sid) then break end end
                    local h = readHUD()
                    local secs = h and h.timer or nil
                    if secs == nil then
                        lastSec, stableAt = nil, nil; task.wait(1)
                    elseif secs ~= lastSec then
                        lastSec = secs; stableAt = tick(); task.wait(0.5)
                    else
                        if tick() - (stableAt or tick()) >= 1 then frozenAt = secs; break end
                        task.wait(0.25)
                    end
                end
            end
        end

        if not alive(sid) then break end
        setPhase()

        local activated, attempts = false, 0
        while alive(sid) and not activated do
            if died then
                local ok = waitForRespawn(sid)
                if not ok or not alive(sid) then break end
            end
            attempts += 1
            if attempts > 20 then break end
            local depPos = getDepositPos()
            if not depPos then task.wait(1); continue end
            moveTo(depPos, sid, true)
            if not alive(sid) then break end
            if died then continue end
            local dropRemote = getDropRemote()
            if dropRemote then dropRemote:FireServer() end
            task.wait(0.2)
            fireDepositPrompt()
            task.wait(0.6)
            local h = readHUD()
            local secs = h and h.timer or nil
            if secs ~= nil and secs ~= frozenAt then
                activated = true
            else
                claimAndScan(sid); if not alive(sid) then break end; setPhase()
            end
        end

        if not alive(sid) then break end
        if not activated then task.wait(2); continue end

        setPhase(); task.wait(0.5)
        local h      = readHUD()
        local rarity = h and h.rarity or nil
        local maxDeps = (h and h.depMax) or 10
        if not rarity then task.wait(1); continue end
        task.wait(0.3)
        setPhase()

        local trialComplete = false
        while alive(sid) and not trialComplete do
            task.wait(0.05)

            if died then
                local respawned = waitForRespawn(sid)
                if not respawned or not alive(sid) then break end
                task.wait(0.5); local ha = readHUD(); task.wait(1.5); local hb = readHUD()
                if ha and hb and ha.timer ~= nil and hb.timer ~= nil and ha.timer ~= hb.timer then
                    local fresh = readHUD()
                    if fresh then rarity = fresh.rarity or rarity; maxDeps = fresh.depMax or maxDeps end
                else
                    break
                end
            end

            local h2 = readHUD()
            if h2 and h2.depCur and h2.depMax and h2.depCur >= h2.depMax then trialComplete = true; break end
            if h2 and h2.rarity and h2.rarity ~= rarity then rarity = h2.rarity end

            local targetPos = findBrainrot(rarity)
            if not targetPos then task.wait(1); continue end

            local dropRemote = getDropRemote()
            if dropRemote then dropRemote:FireServer() end
            moveTo(targetPos, sid, false)
            if not alive(sid) or died then continue end
            task.wait(0.1)
            fireNearestPrompt(getHRP() and getHRP().Position or targetPos)
            
            task.wait(0.5)
            if not hasRenderedBrainrot() then 
                task.wait(0.5)
                if not hasRenderedBrainrot() then
                    if targetPos.Z > 0 then
                        preferredSide = "neg"
                    else
                        preferredSide = "pos"
                    end
                    continue 
                end
            end
            
            setPhase()

            local depPos = getDepositPos()
            if not depPos then task.wait(1); continue end
            moveTo(depPos, sid, true)
            if not alive(sid) or died then continue end

            local deposited = false
            for _ = 1, 12 do
                if not alive(sid) or died then break end
                fireDepositPrompt(); task.wait(1.0)
                if not hasRenderedBrainrot() then deposited = true; task.wait(2.3); break end
            end

            if not deposited then task.spawn(mainLoop, newSession()); return end
        end

        if not alive(sid) then break end
        if not trialComplete then continue end
        setPhase()

        local depPos = getDepositPos()
        if depPos then
            moveTo(depPos, sid, true)
            if alive(sid) then
                local dropRemote = getDropRemote()
                if dropRemote then dropRemote:FireServer() end
                task.wait(0.2); fireDepositPrompt(); task.wait(0.5)
            end
        end

        claimAndScan(sid)
        task.wait(1)
    end
    setVel(Vector3.zero)
end

running = true
task.spawn(mainLoop, newSession())