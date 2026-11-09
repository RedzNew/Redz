local Config: any = {
    Team = "Pirates", BringDistance = 250, RaidBringDistance = 1000, TweenSpeed = 220, HunterCapeTweenSpeed = 320,
    StartMarineFortressUntil = 150, FightHeight = 35,
    DodgeMobs = true, DodgeRadius = 24, DodgeHeight = 28, UsePortals = true,
    AutoRandomFruit = true, AutoStoreFruit = true,
    HopPlayerNear = true, NearPlayerRadius = 50, NearPlayerCooldown = 60, MaxServerPing = 150,
    RedeemCodes = true, RedeemBeliCodes = true, Items = {AutoFullyMelees = true},
}
local EngineTask = task
local env = getgenv()
local previous = _G.Kaitun3TN
local wasPaused=previous and previous.Paused==true
local raidResume=previous and previous.JobId==game.JobId and previous.Raid and table.clone(previous.Raid) or nil
if raidResume then raidResume.jobId=previous.JobId end
if previous and previous.Stop then pcall(previous.Stop) end
local API: any = {Phase = "starting", Metrics = {}, Paused = wasPaused==true}
API.JobId=game.JobId;API.RaidResume=raidResume
_G.Kaitun3TN = API
env.Kaitun3TN = API
_G.Stop = false
local stopped, started = false, os.clock()
local timeee = os.time()
local threads, connections, collisions = {}, {}, setmetatable({}, {__mode = "k"})
local ScriptStorage: any
local LocalPlayer: any
local FarmLevelQuest
local meleeDisplay={["Black Leg"]="Dark Step",["Fishman Karate"]="Water Kung Fu"}
local function CanonicalMelee(name)
    if name=="Dark Step" then return "Black Leg" end
    if name=="Water Kung Fu" then return "Fishman Karate" end
    return name
end
local function Running() return not stopped end
local function Track(c) connections[c] = true; return c end
local function RememberCollision(part)
    if collisions[part] == nil then collisions[part] = part.CanCollide end
end

function API.EndFruitApproach()
    API.FruitApproach = nil
end

local function CanFarmMob(model)
    local enemies=workspace:FindFirstChild("Enemies")
    if not enemies or not model or not model:IsDescendantOf(enemies) then return false end
    local reason=model:GetAttribute("LocalEnemy") and "LocalEnemy" or model:GetAttribute("EscapeKey") and "EscapeKey"
    if reason then
        return false
    end
    local human=model:FindFirstChildOfClass("Humanoid")
    return human~=nil and human.Health>0 and model:FindFirstChild("HumanoidRootPart")~=nil
end
API.CanFarmMob=CanFarmMob
local function Stop()
    if stopped then return end
    stopped = true; _G.Stop = true; _G.FastAttack = nil
    if API.Phase~="failed" then API.Phase = "stopped" end
    if API.Cleanup then pcall(API.Cleanup) end
    for c in connections do pcall(function() c:Disconnect() end) end
    for part, value in collisions do if part.Parent then pcall(function() part.CanCollide = value end) end end
    local current = coroutine.running()
    for thread in threads do if thread ~= current then pcall(EngineTask.cancel, thread) end end
end
API.Stop = Stop
local activityOwners=setmetatable({},{__mode="k"})
API.ActivityEpoch=0
function API.InvalidateActivity(reason)
    API.ActivityEpoch+=1
    API.Metrics=API.Metrics or {}
    if API.CancelFarm then API.CancelFarm(reason) end
end
function API.BindActivity()
    activityOwners[coroutine.running()]=API.ActivityEpoch
end
function API.BeginActivity(name)
    if API.CurrentTask~=name then
        API.CurrentTask=name
        API.InvalidateActivity("activity changed")
    end
    API.BindActivity()
end
function API.ActivityAllowed()
    local owner=activityOwners[coroutine.running()]
    return Running() and not API.Paused and not API.HopInProgress
        and (owner==nil or owner==API.ActivityEpoch)
end
function API.EndActivity()
    activityOwners[coroutine.running()]=nil
end

local task = table.clone(EngineTask)
function task.spawn(fn, ...)
    if not Running() then return end
    local owner=activityOwners[coroutine.running()]
    local thread = coroutine.create(function(...)
        activityOwners[coroutine.running()]=owner
        local ok, issue = xpcall(fn, debug.traceback, ...)
        threads[coroutine.running()] = nil
    end)
    threads[thread] = true
    EngineTask.spawn(thread, ...)
    return thread
end
function task.delay(seconds, fn, ...)
    local args = table.pack(...)
    return task.spawn(function() task.wait(seconds); fn(table.unpack(args, 1, args.n)) end)
end
function task.wait(seconds)
    if not Running() then error("runner stopped", 0) end
    local owner=activityOwners[coroutine.running()]
    if owner~=nil and not API.ActivityAllowed() then error("Activity cancelled",0) end
    local elapsed=EngineTask.wait(seconds)
    if owner~=nil and not API.ActivityAllowed() then error("Activity cancelled",0) end
    return elapsed
end
function task.cancel(thread) threads[thread] = nil; return EngineTask.cancel(thread) end
local spawn, wait = task.spawn, task.wait
local function Invoke(remote, ...)
    local epoch=API.ActivityEpoch
    local owned=activityOwners[coroutine.running()]~=nil
    local function allowed() return not owned or epoch==API.ActivityEpoch and API.ActivityAllowed() end
    if not allowed() then error("Activity cancelled before remote: "..remote.Name,0) end
    local args, result, done = table.pack(...), nil, false
    local worker = task.spawn(function()
        result = table.pack(pcall(remote.InvokeServer, remote, table.unpack(args, 1, args.n)))
        done = true
    end)
    local deadline = os.clock() + (args[1]=="StartQuest" and 3 or 15)
    while Running() and allowed() and not done and os.clock() < deadline do EngineTask.wait(.05) end
    if not allowed() then
        if worker then pcall(task.cancel,worker) end
        error("Activity cancelled during remote: "..remote.Name,0)
    end
    if not done then if worker then pcall(task.cancel, worker) end; error("Remote timeout: " .. remote.Name, 0) end
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
end

repeat task.wait(.2) until game:IsLoaded() and game.Players.LocalPlayer
local player=game.Players.LocalPlayer
repeat task.wait(.2) until player:FindFirstChild("Data") and player:FindFirstChild("DataLoaded")
if not player.Team or player.Team.Name~=Config.Team or not player.Character then
    Invoke(game.ReplicatedStorage.Remotes.CommF_,"SetTeam",Config.Team)
end
repeat task.wait(.2) until player.Team and player.Team.Name==Config.Team and player:FindFirstChild("Backpack")
    and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChildOfClass("Humanoid")
local function Main()
        ScriptStorage = {IsInitalized = false, PlayerData = {}, Melees = {}, CurrentMeleeData = {}, Enemies = {}, Tools = {}, Backpack = {}, IgnoreStoreFruits = {}, Connections = {LocalPlayer = {}}, NPCs = {}, Map = {}}
    Players = game.Players
    LocalPlayer = Players.LocalPlayer
    Character = Players.LocalPlayer.Character
    Humanoid = Character:WaitForChild('Humanoid')
    HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
    PlayerGui = LocalPlayer:WaitForChild('PlayerGui', 10)
    Lighting = game:GetService('Lighting')
    Services = {}
    setmetatable(Services, {__index = function(_, J) return game:GetService(J) end})
    setmetatable(ScriptStorage.Enemies, {__index = function(_, J) local mob=Services.Workspace.Enemies:FindFirstChild(J)
        if CanFarmMob(mob) then return mob end
    end})
    setmetatable(ScriptStorage.Map, {__index = function(_, J) return Services.Workspace.Map:FindFirstChild(J) or Services.Workspace:FindFirstChild(J) end})
    setmetatable(ScriptStorage.Tools, {__index = function(_, J) local char,backpack=LocalPlayer.Character,LocalPlayer:FindFirstChild("Backpack")
        local display=meleeDisplay[J] or J
        return (char and (char:FindFirstChild(J) or char:FindFirstChild(display)))
            or (backpack and (backpack:FindFirstChild(J) or backpack:FindFirstChild(display))) end})
    setmetatable(ScriptStorage.NPCs, {__index = function(_, J) if not J then return end; return workspace.NPCs:FindFirstChild(J) or game.ReplicatedStorage.NPCs:FindFirstChild(J) end})
    function SetTask(key,text)
        text=tostring(text)
        if key=="MainTask" then
            if API.Status==text then return end
            API.Status=text

        elseif key=="SubTask" then
            API.SubTask=text
        end
    end
    Remotes = {}
    BindedMeleeNPCNames = {DragonClaw="Sabi", Superhuman="Martial Arts Master", BlackLeg = 'Dark Step Teacher', Electro = "Mad Scientist", FishmanKarate = "Water Kung-fu Teacher", DeathStep = "Phoeyu, the Reformed", SharkmanKarate = 'Sharkman Teacher', DragonTalon = "Uzoth", ElectricClaw = 'Previous Hero', Godhuman = "Ancient Monk"}
    local J = {}
    setmetatable(Remotes, {__index = function(_, remoteName)
        if remoteName ~= 'CommF_' then
            return Services.ReplicatedStorage.Remotes[remoteName]
        end
        local W = {InvokeServer = function(a, ...)
            local a, h = ...
            if a=="TravelDressrosa" and SeaIndex==1 then
                if LocalPlayer.Data.Level.Value<700 then return false end
                local progress=Invoke(Services.ReplicatedStorage.Remotes.CommF_,"DressrosaQuestProgress")
                if type(progress)~="table" or progress.KilledIceBoss~=true then return false end
            elseif a=="TravelZou" and SeaIndex==2 then
                if LocalPlayer.Data.Level.Value<1500 or not Sea2UnlocksReady() then return false end
                local progress=Invoke(Services.ReplicatedStorage.Remotes.CommF_,"ZQuestProgress","Check")
                if progress~=1 and progress~=2 then return false end
            end
            if type(a)=="string" and a:sub(1,6)=="Travel" then
                if os.clock()<(API.NextTravelAt or 0) then return false end
                API.NextTravelAt=os.clock()+30

            end
            local style=type(a)=="string" and h==nil and a:match("^Buy(.+)$")
            if a=="BlackbeardReward" and h=="DragonClaw" and select(3,...)=="2" then style="DragonClaw" end
            if a=="BuyElectricClaw" and h=="Start" then style="ElectricClaw" end
            local teacher=style and BindedMeleeNPCNames[style]
            if teacher and (not API.NearMeleeTeacher or not API.NearMeleeTeacher(teacher)) then return end
            return Invoke(Services.ReplicatedStorage.Remotes.CommF_, ...)
        end}
        rawset(Remotes, remoteName, W)
        return W
    end})
    Tasks = {}
    function AwaitUntilPlayerLoaded(player)
        while Running() do
            local char=player.Character
            local human=char and char:FindFirstChildOfClass("Humanoid")
            if human and human.Health>0 and char:FindFirstChild("HumanoidRootPart") and player:FindFirstChild("Backpack") then return end
            task.wait(.1)
        end
    end
    function AddPoint()
        local W = {}
        local a
        for _, h in LocalPlayer.Data.Stats:GetChildren() do
            if h and h:FindFirstChild('Level') then W[h.Name] = h.Level.Value end
        end
        if W.Melee < MaxLevel then
            a = "Melee"
        elseif W.Defense < MaxLevel then
            a = 'Defense'
        else
            a = 'Sword'
        end
        Remotes.CommF_:InvokeServer("AddPoint", a, 999)
    end
    function RefreshPlayerData()
        for _,value in LocalPlayer.Data:GetChildren() do
            if value:IsA("ValueBase") then ScriptStorage.PlayerData[value.Name]=value.Value end
        end
    end
    function MeleeCheck(W)
        if W and W:IsA("Tool") and W.ToolTip=="Melee" and not W:FindFirstChild("Level") then return end
        if W and typeof(W) == "Instance" and W:IsA("Tool") then
            if W.ToolTip == "Melee" then
                if ScriptStorage.Connections.Melees then ScriptStorage.Connections.Melees:Disconnect() end
                local name=CanonicalMelee(W.Name)
                ScriptStorage.CurrentMeleeData.Name = name
                ScriptStorage.Connections.Melees = Track(W.Level.Changed:Connect(function(a)
                    ScriptStorage.Melees[name] = a

                end))
                ScriptStorage.Melees[name] = W.Level.Value

            end
        end
    end
    MeleeCheck(LocalPlayer.Character:FindFirstChildOfClass('Tool'))
    RefreshPlayerData()
    function RegisterLocalPlayerEventsConnection()
        for _, W in ScriptStorage.Connections.LocalPlayer do pcall(function() W:Disconnect() end) end
        AwaitUntilPlayerLoaded(LocalPlayer)
        local backpack=LocalPlayer:FindFirstChild("Backpack")
        if not Running() or not backpack then return end
        LocalPlayer:SetAttribute("IsAvailable", true)
        Character=LocalPlayer.Character; Humanoid=Character:FindFirstChildOfClass("Humanoid"); HumanoidRootPart=Character:FindFirstChild("HumanoidRootPart")
        ScriptStorage.Connections.LocalPlayer["HealthCheck"] = Track(LocalPlayer.Character:WaitForChild("Humanoid"):GetPropertyChangedSignal("Health"):Connect(function()
            local W = LocalPlayer.Character.Humanoid.Health
            LocalPlayer:SetAttribute("IsAvailable", W > 10)
            ScriptStorage.LocalPlayerHealth = W
        end))
        ScriptStorage.Connections.LocalPlayer['Melee'] = Track(LocalPlayer.Character.ChildAdded:Connect(MeleeCheck))
        ScriptStorage.Connections.LocalPlayer['Fruit'] = Track(backpack.ChildAdded:Connect(function(tool)

            MeleeCheck(tool)
        end))
        table.foreach(backpack:GetChildren(), function(_, W) MeleeCheck(W) end)
        local W = LocalPlayer.Data:WaitForChild('Points')
        ScriptStorage.Connections.LocalPlayer.PointConnection = Track(W:GetPropertyChangedSignal('Value'):Connect(function()
            local W = LocalPlayer.Data:WaitForChild('Points')
            if OldPointValue == W.Value then return end
            OldPointValue = W.Value
            AddPoint()
        end))
    end
    RegisterLocalPlayerEventsConnection(LocalPlayer)
    Track(game.Players.LocalPlayer.CharacterAdded:Connect(function(W)
        RegisterLocalPlayerEventsConnection(LocalPlayer)
    end))
    MeleesTable = {"Black Leg", 'Electro', "Fishman Karate", "Dragon Claw", "Superhuman", 'Death Step', 'Electric Claw', 'Sharkman Karate', 'Dragon Talon', "Godhuman", "SanguineArt"}
    MeleesId = {'BlackLeg', "Electro", 'FishmanKarate', "DragonClaw", "Superhuman", 'DeathStep', "ElectricClaw", "SharkmanKarate", 'DragonTalon', 'Godhuman', "SanguineArt"}
    MeleePrices = {["Black Leg"] = {Price = {Beli = 150000}, Id = "BlackLeg", NextLevelRequirement = 400, position = CFrame.new()}, ['Electro'] = {Price = {Beli = 500000}, Id = 'Electro', NextLevelRequirement = 400}, ['Fishman Karate'] = {Price = {Beli = 750000}, NextLevelRequirement = 400}, ['Dragon Claw'] = {Price = {Fragments = 1500}, NextLevelRequirement = 400}, ["Superhuman"] = {Price = {Beli = 3000000}, NextLevelRequirement = 400}, ["Death Step"] = {Price = {Beli = 2500000, Fragments = 5000}, NextLevelRequirement = 400}, ['Sharkman Karate'] = {Price = {Beli = 2500000, Fragments = 5000}, NextLevelRequirement = 400}, ['Electric Claw'] = {Price = {Beli = 3000000, Fragments = 5000}, NextLevelRequirement = 400}, ['Dragon Talon'] = {Price = {Beli = 3000000, Fragments = 5000}, NextLevelRequirement = 400}, ["Godhuman"] = {Price = {Beli = 5000000, Fragments = 5000}, NextLevelRequirement = 350}}
    GodhumanMaterials = {['Fish Tail'] = {20, 3, {"Fishman Raider", "Fishman Captain"}, {'DeepForestIsland3', 1, 1775, 'Turtle Adventure Quest Giver'}}, ['Dragon Scale'] = {10, 3, {"Dragon Crew Warrior", "Dragon Crew Archer"}, {'DragonCrewQuest', 1, 1575, 'Dragon Crew Quest Giver'}}, ["Magma Ore"] = {20, 2, {'Magma Ninja'}, {"FireSideQuest", 1, 1100, "Fire Quest Giver"}}, ["Mystic Droplet"] = {10, 2, {'Sea Soldier', 'Water Fighter'}, {'ForgottenQuest', 2, 1425, 'Forgotten Quest Giver'}}}
    SeaIndexes = {"Main", "Dressrosa", "Zou"}
    MaxLevel = 2800
    placeId = game.PlaceId
    if placeId == 85211729168715 or placeId == 2753915549 then
        Sea = 'Main'
        SeaIndex = 1
    elseif placeId == 79091703265657 or placeId == 4442272183 then
        Sea = "Dressrosa"
        SeaIndex = 2
        Config.BringDistance = 350
    elseif placeId == 100117331123089 or placeId == 7449423635 then
        Sea = "Zou"
        SeaIndex = 3
        Config.BringDistance = 350
    end
    Portals = ({{Vector3.new(-7894.6201171875, 5545.49169921875, -380.246346191406), Vector3.new(-4607.82275390625, 872.5422973632812, -1667.556884765625), Vector3.new(61163.8515625, 11.759522438049316, 1819.7841796875), Vector3.new(3876.280517578125, 35.10614013671875, -1939.3201904296875)}, {Vector3.new(-288.46246337890625, 306.130615234375, 597.9988403320312), Vector3.new(2284.912109375, 15.152046203613281, 905.48291015625), Vector3.new(923.21252441406, 126.9760055542, 32852.83203125), Vector3.new(-6508.5581054688, 89.034996032715, -132.83953857422)}, {}})[SeaIndex]
    function ConvertTo(W, a) return W.new(a.X, a.Y, a.Z) end
    function CaculateDistance(W, a)
        if not W then return 0 end
        local char=LocalPlayer.Character
        local root=char and char:FindFirstChild("HumanoidRootPart")
        if not a and not root then return math.huge end
        a = a or root.CFrame
        local h, X = ConvertTo(Vector3, W), ConvertTo(Vector3, a)
        return (h - X).magnitude
    end
    function GetMonAsSortedRange()
        local mobs,distances={},{}
        for _,mob in workspace.Enemies:GetChildren() do
            if CanFarmMob(mob) then
                table.insert(mobs,mob)
                distances[mob]=CaculateDistance(mob.HumanoidRootPart.Position)
            end
        end
        table.sort(mobs,function(a,b) return distances[a]<distances[b] end)
        return mobs
    end
    function GetMeleeIdByName(W) for a, h in MeleesTable do if h == W then return MeleesId[a] end end end
    function getpos(name)
        local npc=ScriptStorage.NPCs[name]
        return npc and npc:GetPivot()
    end
    function BuyMelee(W, a)
        local remote=Remotes.CommF_
        if a then
            local owned
            if ScriptStorage.Tools[W] then
                owned=true
            elseif W=="DragonClaw" then
                return remote:InvokeServer("BlackbeardReward",W,"1")
            else
                owned=remote:InvokeServer("Buy"..W,true)==1
            end
            if W=="Electro" and owned then
                API.ElectroUnlocked=true
            end
            return owned
        end
        if W=="Electro" and not API.ElectroUnlocked then
            return false
        end
        API.MeleeBuying=W
        local ok,result
        if W=="DragonClaw" then
            ok,result=pcall(remote.InvokeServer,remote,"BlackbeardReward",W,"2")
        else
            ok,result=pcall(remote.InvokeServer,remote,"Buy"..W)
        end
        API.MeleeBuying=nil
        API.LastMeleePurchase={id=W,response=tostring(result),transportUncertain=not ok or nil}
        if not ok then return end
        return result
    end
    function FruitIdToName(J)
        local W = string.match(J, "(((%u)%-?)([^-.]+))$")
        return W .. ' Fruit'
    end
    function Split(J, W)
        if W == nil then W = "%s" end
        local a = {}
        for h in string.gmatch(J, '([^' .. W .. ']+)') do table.insert(a, h) end
        return a
    end
    function FruitNameToId(J)
        local W = Split(J)[1]
        return W .. '-' .. W
    end
    local J = {CurrentLevel = 2, CurrentQuests = {}, BlacklistedQuestIds = {BartiloQuest = 1, CitizenQuest = 1, Trainees = 1, MarineQuest = 1, ImpelQuest = 1}}
    local W = require(game.ReplicatedStorage.GuideModule).Data.NPCList
    repeat task.wait() until game.Players.LocalPlayer.DataLoaded and ScriptStorage
    J.Quests = require(game.ReplicatedStorage.Quests)
    function J.RefreshQuest(W)
        while not ScriptStorage.PlayerData.Level do
            task.wait(1)
        end
        local a = 0
        local h
        for X, w in J.Quests do
            if not J.BlacklistedQuestIds[X] then
                if (w[1].LevelReq >= a and w[1].LevelReq <= ScriptStorage.PlayerData.Level) then
                    a = w[1].LevelReq
                    h = w
                    W.CurrentQuestId = X
                    if ScriptStorage.PlayerData.Level >= 1500 and SeaIndex == 2 and X == 'ForgottenQuest' then break end
                end
            end
        end
        local a = h[#h]
        for _, X in a.Task do if X == 1 then table.remove(h, #h) end end
        for a, X in require(game.ReplicatedStorage.GuideModule).Data.NPCList do
            for _, w in X.Levels do if w == h[#h].LevelReq then W.CurrentNpc = a.CFrame end end
        end
        W.CurrentQuests = h
    end
    function J.MarkAsCompleted(W) W.CurrentLevel = W.CurrentLevel == 2 and 1 or 2 end
    function J.AbandonQuest()
        Remotes.CommF_:InvokeServer("AbandonQuest")
    end
    function J.StartQuest(W, a)
        return Remotes.CommF_:InvokeServer("StartQuest", W, a)
    end
    local function IndexMobSpawn(spawn)
        if not spawn:IsA("BasePart") then return end
        local name=spawn.Name:match("^(.-)%s+%[Lv%.") or spawn.Name
        local regions=ScriptStorage.MobRegions[name]
        if not regions then regions={};ScriptStorage.MobRegions[name]=regions end
        if not table.find(regions,spawn.CFrame) then table.insert(regions,spawn.CFrame) end
    end
    ScriptStorage.MobRegions={}
    local function BindMobSpawns()
        local origin=workspace:WaitForChild("_WorldOrigin")
        local spawns=origin:WaitForChild("EnemySpawns")
        if not Running() then return end
        for _,spawn in spawns:GetChildren() do IndexMobSpawn(spawn) end
        Track(spawns.ChildAdded:Connect(IndexMobSpawn))
    end
    task.spawn(BindMobSpawns)
    TweenController = {}
    function GetPortal(a)
        if not API.ActivityAllowed() or API.IsRaidActive and API.IsRaidActive() then return end
        local moveEpoch=API.ActivityEpoch
        local character=LocalPlayer.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        if not root or not Running() or API.Paused or API.HopInProgress then return end
        local tags=game:GetService("CollectionService")
        if tags:HasTag(LocalPlayer,"Teleporting") then return end
        local nearest,point=math.huge,nil
        for _,candidate in Portals do
            local distance=CaculateDistance(candidate,a)
            if distance<CaculateDistance(a)-300 and distance<nearest then
                nearest=distance;point=candidate
            end
        end
        if not point then return end
        if SeaIndex==2 then
            local map=workspace:FindFirstChild("Map")
            for _,name in {"GhostShip","GhostShipInterior"} do
                local model=map and map:FindFirstChild(name)
                local spawn=model and model:FindFirstChild("TeleportSpawn")
                if spawn and (spawn.Position-point).Magnitude<50 then point=spawn.Position;break end
            end
        end
        local response=Remotes.CommF_:InvokeServer("requestEntrance",point)
        -- Native AnimateEntrance applies the returned position on the client.
        if typeof(response)=="Vector3" and Running() and not API.Paused and not API.HopInProgress
            and LocalPlayer.Character==character and root.Parent and moveEpoch==API.ActivityEpoch and API.ActivityAllowed() then
            root.CFrame=CFrame.new(response)
        end
        return point,response
    end
    local W = {}
    local a = game:GetService('Players')
    local h = {}
    function GetAllBladeHits()
        local hits={}
        local root=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not root or not API.FarmCenter then return hits end
        for _,mob in workspace.Enemies:GetChildren() do
            if CanFarmMob(mob) and (mob.HumanoidRootPart.Position-root.Position).Magnitude<=65
                and (not API.IsRoundMob or API.IsRoundMob(mob)) then table.insert(hits,mob) end
        end
        return hits
    end
    local X = (Services.ReplicatedStorage.Modules.Net)
    local w = require(X):RemoteEvent("RegisterAttack", true)
    local D = require(X):RemoteEvent("RegisterHit", true)
    function h:Attack()
        if not API.ActivityAllowed() then return end
        local X = GetAllBladeHits()
        if #X == 0 then return end
        local y = {[1] = nil, [2] = {}, [4] = "078da341"}
        for _, L in pairs(X) do
            w:FireServer(0)
            if not y[1] then y[1] = L.Head end
            table.insert(y[2], {[1] = L, [2] = L.HumanoidRootPart})
            table.insert(y[2], L)
        end
        D:FireServer(unpack(y))
    end
    task.spawn(function()
        while task.wait(0.01) do if _G.FastAttack == os.time() then pcall(function() h:Attack() end) end end
    end)
    function W.Attack(h) pcall(function() _G.FastAttack = os.time() end) end
    CombatController = {GRAB = true, CurrentIndex = 1}
    LastFound = os.time()
    function CombatController.Search(names)
        local nearest,nearestDistance=nil,math.huge
        local now=os.clock()
        for _,mob in workspace.Enemies:GetChildren() do
            if table.find(names,mob.Name) and CanFarmMob(mob) and (mob:GetAttribute("KaitunSkipUntil") or 0)<=now then
                local distance=CaculateDistance(mob.HumanoidRootPart.Position)
                if not nearest or distance<nearestDistance then nearest,nearestDistance=mob,distance end
            end
        end
        return nearest
    end
    function CombatController.Attack(h, X, w, D, camp, includeBosses)
        local pinned=typeof(h)=="Instance" and h or nil
        if not API.ActivityAllowed() then return end
        sethiddenproperty(game.Players.LocalPlayer, 'SimulationRadius', math.huge)
        h = pinned and {pinned.Name} or type(h) == "string" and {h} or (h or {})
        for y, L in (h) do

            if pinned then
                MonResult=pinned
            elseif camp then
                MonResult=camp.target
            elseif X then
                local b = GetMonAsSortedRange()[1]
                local C = b and b:FindFirstChild('HumanoidRootPart') and b.HumanoidRootPart.Position
                if C and CaculateDistance(C) < w then MonResult = b end
            else
                MonResult = CombatController.Search(h)
            end
            if MonResult and CanFarmMob(MonResult) then
                L=MonResult.Name
            API.BeginBringRound(MonResult,camp,includeBosses)
                local roundStarted=os.clock()
                local lastHP,lastDamage=MonResult.Humanoid.Health,roundStarted
                LastFound = os.time()
                local h, w = 0, os.time()
                local w, b = 0, os.time()
                while task.wait() do
                    if _G.Stop or API.Paused or not Running() then return end
                    if D and D() then return end
                    if not MonResult then break end
                    local C = MonResult:FindFirstChild('Humanoid')
                    local p = MonResult:FindFirstChild('HumanoidRootPart')
                    if not CanFarmMob(MonResult) then
                        if MonResult.Name=="Don Swan" and C and C.Health<=0 then Storage:Set("SwanDefeated",true) end
                        break
                    end
                    if C.Health<lastHP then
                        lastDamage=os.clock()
                    elseif CaculateDistance(p.Position)>65 then lastDamage=os.clock() end
                    lastHP=C.Health
                    if os.clock()-roundStarted>(MonResult.Name=="Core" and 90 or 60)
                        or MonResult.Name~="Core" and os.clock()-lastDamage>5 then
                        MonResult:SetAttribute("KaitunSkipUntil",os.clock()+8)
                        break
                    end
                    TweenController.Create(FarmPose(tostring(L), p.CFrame))
                    CombatController.Grab(tostring(L))
                    if CaculateDistance(p.Position + Vector3.new(0, 35, 0)) < 150 then
                        y = D and D()
                        local wanted=ScriptStorage.ForceMelee
                        FunctionsHandler.LocalPlayerController.Methods.EquipTool:Call(wanted and ScriptStorage.Tools[wanted] and wanted or "Melee")
                        W:Attack(MonResult)
                        if os.time() ~= b then
                            b = os.time()
                            h = h + 1
                            w = w + 1
                        end
                        if h > 30 and MonResult.Name ~= "Core" then
                            break
                        end
                    end
                end
            elseif not X and not pinned then
                if (os.time() - LastFound) > 200 then
                    LastFound=os.time()

                    return
                end
                local h = ScriptStorage.MobRegions[L]
                if not h or #h==0 then return end
                local X
                if not h[CombatController.CurrentIndex] then CombatController.CurrentIndex = 1 end
                X = h[CombatController.CurrentIndex]
                local h = os.time()
                local pose=FarmPose(tostring(L),typeof(X)=="CFrame" and X or CFrame.new(X))
                TweenController.Create(pose)
                if CaculateDistance(pose) < 15 then CombatController.CurrentIndex = CombatController.CurrentIndex + 1 end
            end
        end
    end
    FunctionsHandler = {Initalized = false}
    setmetatable(FunctionsHandler, {__index = function(_, key)
        return {
            Initalized = false,
            Register = function(enabled)
                if enabled == false then return end
                local result={Methods={},Values={},Initalized=true}
                function result:RegisterMethod(name,callback)
                    self.Methods[name]={Name=name,Callback=callback,Call=function(method,...) return method.Callback(...) end}
                    return true
                end
                function result:Set(name,value) self.Values[name]=value end
                function result:Get(name) return self.Values[name] end
                FunctionsHandler[key]=result
                return result
            end,
        }
    end})
    FunctionsHandler.LocalPlayerController.Register()
    FunctionsHandler.LevelFarm:Register()
    FunctionsHandler.SecondSeaPuzzle:Register()
    FunctionsHandler.ColosseumPuzzle:Register()
    FunctionsHandler.Trevor:Register()
    FunctionsHandler.ThirdSeaPuzzle:Register()
    FunctionsHandler.PirateRaid:Register()
    FunctionsHandler.RaidController:Register()
    FunctionsHandler.MeleesController:Register()
    FunctionsHandler.CollectDrops:Register()
    FunctionsHandler.UtillyItemsActivitation:Register()
    FunctionsHandler.LevelFarm:RegisterMethod("Refresh", function()
        return 4
    end)
    FunctionsHandler.LevelFarm:RegisterMethod("Start", function(h)
        if SeaIndex == 1 and LocalPlayer.Data.Level.Value < Config.StartMarineFortressUntil then
            API.Metrics.SelectedCamp = {name = "Chief Petty Officer", mode = "without quest until 150"}
            SetTask("MainTask", "Early grind to 150 | Chief Petty Officer")
            CombatController.Attack("Chief Petty Officer", nil, nil, function()
                return LocalPlayer.Data.Level.Value >= Config.StartMarineFortressUntil
            end)
            return
        end
        if GodHumanFlag then return API.FarmGodhumanMaterial() end
        if h == 4 then return FarmLevelQuest()
        end
    end)
    FunctionsHandler.LocalPlayerController:RegisterMethod("EquipTool", function(wanted)
        local char=LocalPlayer.Character
        local backpack=LocalPlayer:FindFirstChild("Backpack")
        local human=char and char:FindFirstChildOfClass("Humanoid")
        if not API.ActivityAllowed() or not backpack or not human or human.Health<=0 then return end
        for _,tool in backpack:GetChildren() do
            if tool:IsA("Tool") and tool.Name~="Tool" and (CanonicalMelee(tool.Name)==wanted or tool.Name==wanted or tool.ToolTip==wanted)
                and (not API.CanDrawMelee or API.CanDrawMelee(tool)) then
                human:EquipTool(tool)
                return
            end
        end
    end)
    local nextElectroBuyCheck=0
    local beginMeleeAction
    FunctionsHandler.MeleesController:RegisterMethod('Start', function()
        local godhuman=ScriptStorage.Backpack.Godhuman
        if LocalPlayer.Data.Level.Value>=MaxLevel and (godhuman or ScriptStorage.Tools.Godhuman) then

            SetTask("MainTask","Kaitun 3TN | Max level and Godhuman")
            return API.Stop()
        end
        if not Config.Items.AutoFullyMelees then return end
        for index,name in MeleesTable do
            local data,id=MeleePrices[name],MeleesId[index]
            if not data then return end
            if id=="Electro" and not API.ElectroUnlocked and os.clock()>=nextElectroBuyCheck then
                nextElectroBuyCheck=os.clock()+15
                BuyMelee(id,true)
            end
            if name=="Dragon Talon" and not IsFireEssenceGave then
                IsFireEssenceGave=type(Remotes.CommF_:InvokeServer("BuyDragonTalon",true))=="number"
                if not IsFireEssenceGave then
                    SetTask("SubTask","Waiting for Fire Essence")
                    return
                end
            end
            local mastery=ScriptStorage.Melees[name]
            if name=="Godhuman" and not mastery then
                if not API.InventoryKnown then return end
                GodHumanFlag=API.MissingGodhumanMaterial()~=nil
                if GodHumanFlag then return end
            end
            if mastery and mastery>=data.NextLevelRequirement then continue end
            if mastery then
                SetTask("SubTask","Farming mastery for "..name.." ("..mastery.." / "..data.NextLevelRequirement..")")
                if not API.HasSelectedMelee(name) then BuyMelee(id) end
                return
            end
            for currency,price in data.Price do
                if (ScriptStorage.PlayerData[currency] or 0)<price then
                    SetTask("SubTask","Farming "..currency.." ("..price..") for "..name)
                    return
                end
            end
            if not API.HasSelectedMelee(name) then BuyMelee(id);return end
        end
    end)
    FunctionsHandler.ColosseumPuzzle:RegisterMethod("Refresh", function()
        if SeaIndex ~= 2 then return end
        if ScriptStorage.PlayerData.Level < 850 or ScriptStorage.Backpack['Warrior Helmet'] then return end
        local k = Remotes.CommF_:InvokeServer("BartiloQuestProgress")
        if not k.KilledBandits then Result = 1
        elseif not k.KilledSpring then
            if ScriptStorage.Enemies.Jeremy then Result = 2 end
        elseif not k.DidPlates then Result = 3 end
        FunctionsHandler.ColosseumPuzzle:Set("CurrentProgressLevel", Result)
        FunctionsHandler.ColosseumPuzzle:Set("LastestRefreshSenque", os.time())
        return Result
    end)
    FunctionsHandler.ColosseumPuzzle:RegisterMethod('Start', function()
        local k, h = FunctionsHandler.ColosseumPuzzle:Get("CurrentProgressLevel"), FunctionsHandler.ColosseumPuzzle:Get("LastestRefreshSenque")
        FunctionsHandler.ColosseumPuzzle:Set("CurrentProgressLevel", nil)
        if not k then
            FunctionsHandler.ColosseumPuzzle.Methods.Refresh:Call()
            return FunctionsHandler.ColosseumPuzzle.Methods.Start:Call()
        elseif k == 1 then
            SetTask("MainTask", 'Auto Bartilo Quest - Defeating 50x Swan Pirate')
            local h, X = J:GetCurrentClaimQuest()
            if h then
                if not string.find(X, '50') then J.AbandonQuest()
                else CombatController.Attack("Swan Pirate") end
            else
                J.StartQuest('BartiloQuest', 1)
            end
        elseif k == 2 then
            SetTask('MainTask', "Auto Bartilo Quest - Defeating Jeremy")
            CombatController.Attack("Jeremy")
        elseif k == 3 then
            SetTask("MainTask", 'Auto Bartilo Quest - Doing Puzzle')
            if CaculateDistance(CFrame.new(-1837.46155, 44.2921753, 1656.1987, 0.999881566, -1.03885048e-22, -0.0153914848, 1.07805858e-22, 1, 2.53909284e-22, 0.0153914848, -2.55538502e-22, 0.999881566)) > 10 then
                TweenController.Create(CFrame.new(-1837.46155, 44.2921753, 1656.1987, 0.999881566, -1.03885048e-22, -0.0153914848, 1.07805858e-22, 1, 2.53909284e-22, 0.0153914848, -2.55538502e-22, 0.999881566))
            else
                LocalPlayer = game.Players.LocalPlayer
                LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1836.0, 11, 1714)
                task.wait(.5)
                LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1850.49329, 13.1789551, 1750.89685)
                task.wait(1)
                LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1858.87305, 19.3777466, 1712.01807)
                task.wait(1)
                LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1803.94324, 16.5789185, 1750.89685)
                task.wait(1)
                LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1858.55835, 16.8604317, 1724.79541)
                task.wait(1)
                LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1869.54224, 15.987854, 1681.00659)
                task.wait(1)
                LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1800.0979, 16.4978027, 1684.52368)
                task.wait(1)
                LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1819.26343, 14.795166, 1717.90625)
                task.wait(1)
                LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1813.51843, 14.8604736, 1724.79541)
            end
        end
    end)
    FunctionsHandler.RaidController:RegisterMethod('RefreshRaidType', function()
        for _, k in require(game.ReplicatedStorage.Raids).raids do
            if string.find(ScriptStorage.PlayerData.DevilFruit, k) then
                FunctionsHandler.RaidController:Set('CurrentChip', k)
                return
            end
        end
        FunctionsHandler.RaidController:Set('CurrentChip', 'Flame')
    end)
    FunctionsHandler.RaidController:RegisterMethod("GetRaidableFruit", function()
        local fruit,count=nil,0
        for _,row in ScriptStorage.Backpack do
            if row.Type=="Blox Fruit" and row.Value and row.Value<1000000
                and not table.find(ScriptStorage.IgnoreStoreFruits,row.Name) then
                count+=row.Count or 1
                if not fruit or row.Value<fruit.Value then fruit=row end
            end
        end
        return fruit,count
    end)
    function CheckSpecialMicrochip()
        local char,backpack=LocalPlayer.Character,LocalPlayer:FindFirstChild("Backpack")
        if not char or not backpack then return end
        return char:FindFirstChild("Special Microchip") or backpack:FindFirstChild("Special Microchip")
    end
    local fruitRetry
    local function canReachFruit(handle)
        if not handle or not handle:IsA("BasePart") then return false end
        if SeaIndex~=2 or LocalPlayer.Data.Level.Value>=1000 or handle.Position.Z<=20000 then return true end
        local character=LocalPlayer.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        return root~=nil and root.Position.Z>20000
    end
    FunctionsHandler.CollectDrops:RegisterMethod("Refresh", function()
        local backpack=LocalPlayer:FindFirstChild("Backpack")
        if not backpack then return end
        if ScriptStorage.Tools["Fire Essence"] then
            return
        end
        local k = {}
        for h in ScriptStorage.Backpack do k[FruitIdToName(h)] = h end
        local target=API.FruitApproach and API.FruitApproach.target
        if target and target.Parent==workspace and API.ShouldCollectDroppedFruit(target) and canReachFruit(target:FindFirstChild("Handle")) then
            FunctionsHandler.CollectDrops:Set('CurrentProgressLevel',target)
            return target
        end
        for _, h in workspace:GetChildren() do
            if not string.find(h.Name,"Fruit",1,true) or not API.ShouldCollectDroppedFruit(h) then continue end
            local handle=h:FindFirstChild("Handle")
            if not canReachFruit(handle) then continue end
            local cooling=fruitRetry and os.clock()<fruitRetry.untilTime and fruitRetry.name==h.Name
                and (handle.Position-fruitRetry.position).Magnitude<3
            if not cooling and not backpack:FindFirstChild(h.Name) and not k[tostring(h)] and not ScriptStorage.Backpack[FruitNameToId(tostring(h))] then
                FunctionsHandler.CollectDrops:Set('CurrentProgressLevel', h)
                return h
            end
        end
    end)
    FunctionsHandler.CollectDrops:RegisterMethod('Start', function()
        local k = FunctionsHandler.CollectDrops:Get('CurrentProgressLevel')
        FunctionsHandler.CollectDrops:Set('CurrentProgressLevel', nil)
        local handle=k and k.Parent==workspace and API.ShouldCollectDroppedFruit(k) and k:FindFirstChild("Handle")
        if canReachFruit(handle) then
            local approach=API.FruitApproach
            local now=os.clock()
            local character=LocalPlayer.Character
            local root=character and character:FindFirstChild("HumanoidRootPart")
            local position=root and root.Position
            if not approach or approach.target~=k then
                approach={target=k,position=position,startedAt=now,untilTime=now+20,deadline=now+150}
                API.FruitApproach=approach

            elseif position and (not approach.position or (position-approach.position).Magnitude>=20) then
                approach.position=position
                approach.untilTime=now+20
            end
            if position then
                approach.distance=math.round((position-handle.Position).Magnitude)
                approach.closest=math.min(approach.closest or math.huge,approach.distance)
            end
            if now>=approach.untilTime or now>=approach.deadline then
                fruitRetry={name=k.Name,position=handle.Position,untilTime=now+60}
                API.EndFruitApproach("approach timed out")
                return
            end
            SetTask("MainTask", "Auto Collect Drop Items - " .. tostring(k))
            TweenController.Create(handle.CFrame+Vector3.new(0,2,0))
        else
            API.EndFruitApproach("target unavailable")
        end
    end)
    local nextPreviousHeroCheck,previousHeroReady=0,false
    local function PreviousHeroReady()
        local data=LocalPlayer.Data
        local price=MeleePrices["Electric Claw"].Price
        if SeaIndex~=3 or ScriptStorage.Melees["Electric Claw"] or (ScriptStorage.Melees.Electro or 0)<400
            or data.Beli.Value<price.Beli or data.Fragments.Value<price.Fragments then return false end
        if os.clock()>=nextPreviousHeroCheck then
            nextPreviousHeroCheck=os.clock()+15
            local nativeState=Remotes.CommF_:InvokeServer("BuyElectricClaw",true)
            previousHeroReady=(nativeState==0 or nativeState==1 or nativeState==4) and nativeState or false
        end
        return previousHeroReady
    end
    FunctionsHandler.UtillyItemsActivitation:RegisterMethod('Refresh', function()
        local key=PendingProgressKey()
        if key then
            FunctionsHandler.UtillyItemsActivitation:Set("CurrentProgressLevel",key)
            return key
        end
        if PreviousHeroReady() then
            FunctionsHandler.UtillyItemsActivitation:Set("CurrentProgressLevel","Previous Hero")
            return "Previous Hero"
        end
        if SeaIndex==3 and ScriptStorage.Tools['Fire Essence'] and os.clock()>=(API.NextFireEssenceAt or 0) then
            FunctionsHandler.UtillyItemsActivitation:Set('CurrentProgressLevel', "Uzoth")
            return 'Uzoth'
        end
    end)
    FunctionsHandler.UtillyItemsActivitation:RegisterMethod('Start', function()
        local k = FunctionsHandler.UtillyItemsActivitation:Get("CurrentProgressLevel")
        FunctionsHandler.UtillyItemsActivitation:Set("CurrentProgressLevel", nil)
        if k=="Hidden Key" or k=="Library Key" then
            return UseProgressKey(k)
        elseif k == 'Water Key' then
            return UseProgressKey("Water Key")
        elseif k == 'Previous Hero' then
            local ready=previousHeroReady
            previousHeroReady=false;nextPreviousHeroCheck=os.clock()+15
            if ready==0 or ready==1 then return API.TryElectricClawPurchase() end
            SetTask("MainTask","Previous Hero | Approaching teacher")
            if not API.ApproachMeleeTeacher("ElectricClaw","Electric Claw") or Remotes.CommF_:InvokeServer("BuyElectricClaw",true)~=4 then return end
            local mansion=CFrame.new(-12548,332.378,-7617)
            local deadline=os.clock()+30
            Remotes.CommF_:InvokeServer("BuyElectricClaw","Start")
            SetTask("MainTask","Previous Hero | Racing to Mansion")
            while CaculateDistance(mansion)>30 and os.clock()<deadline and API.ActivityAllowed()
                and not (API.IsRaidBusy and API.IsRaidBusy()) do
                TweenController.Create(mansion)
                task.wait(.1)
            end
            if not API.ActivityAllowed() or API.IsRaidBusy and API.IsRaidBusy() then return end
            local state=Remotes.CommF_:InvokeServer("BuyElectricClaw",true)
            SetTask("MainTask",(state==0 or state==1) and "Previous Hero | Unlock confirmed" or "Previous Hero | Unlock unconfirmed")

            if state==0 or state==1 then API.TryElectricClawPurchase() end
        elseif k == "Uzoth" then
            API.NextFireEssenceAt=os.clock()+30
            local char=LocalPlayer.Character
            local bag=LocalPlayer:FindFirstChild("Backpack")
            if not char or not bag then return end
            SetTask("MainTask","Fire Essence | Submitting to Uzoth")
            if not API.ApproachMeleeTeacher("DragonTalon","Fire Essence") then return end
            FunctionsHandler.LocalPlayerController.Methods.EquipTool:Call("Fire Essence")
            task.wait(.25)
            if char~=LocalPlayer.Character or not char:FindFirstChild("Fire Essence") then return end
            local response=Remotes.CommF_:InvokeServer("BuyDragonTalon",true)
            task.wait(.5)
            if type(response)=="number" and char==LocalPlayer.Character
                and not char:FindFirstChild("Fire Essence") and not bag:FindFirstChild("Fire Essence") then
                IsFireEssenceGave=true

                API.TryTalonPurchase()
            end
        end
    end)
    FunctionsHandler.Trevor:RegisterMethod('GetFruit', function()
        for _, k in ScriptStorage.Backpack do
            if k.Type == "Blox Fruit" then
                if k.Value and k.Value > 1000000 and k.Value < 2500000 then return k end
            end
        end
    end)
    FunctionsHandler.Trevor:RegisterMethod('Refresh', function()
        if FunctionsHandler.Trevor:Get('IsCompleted') or os.time() -  timeee < 1 then return end
        if ScriptStorage.PlayerData.Level < 1100 or SeaIndex ~= 2 then return end
        local k = FunctionsHandler.Trevor.Methods.GetFruit:Call()
        if k then FunctionsHandler.Trevor:Set('Fruit', k) end
        TrevorDebounce = os.time()
        if not FunctionsHandler.Trevor:Get('IsCompleted') then
            FunctionsHandler.Trevor:Set('IsCompleted', (Remotes.CommF_:InvokeServer("TalkTrevor", "1") == 0))
        end
        return not FunctionsHandler.Trevor:Get("IsCompleted") and k
    end)
    FunctionsHandler.Trevor:RegisterMethod("Start", function()
        local k = FunctionsHandler.Trevor:Get("Fruit")
        FunctionsHandler.Trevor:Set('Fruit', nil)
        table.insert(ScriptStorage.IgnoreStoreFruits, k.Name)
        Remotes.CommF_:InvokeServer('LoadFruit', k.Name)
        task.wait()
        FunctionsHandler.LocalPlayerController.Methods.EquipTool:Call(FruitIdToName(k.Name))
        Remotes.CommF_:InvokeServer('TalkTrevor', '1')
        Remotes.CommF_:InvokeServer('TalkTrevor', "2")
        Remotes.CommF_:InvokeServer("TalkTrevor", "3")
        task.wait(1)
        FunctionsHandler.Trevor:Set('IsCompleted',Remotes.CommF_:InvokeServer("TalkTrevor","1")==0)
        local index=table.find(ScriptStorage.IgnoreStoreFruits,k.Name)
        if index then table.remove(ScriptStorage.IgnoreStoreFruits,index) end
    end)
    Storage = {WRITE_DELAY = .5, Data = {}}
    local storagePath=".storage_u_"..tostring(LocalPlayer)
    local storageHttp=Services.HttpService
    local storageDirty=false
    local loaded,saved=pcall(function()
        if isfile(storagePath) then return storageHttp:JSONDecode(readfile(storagePath)) end
    end)
    if loaded and type(saved)=="table" then Storage.Data=saved end
    function Storage:Set(key,value)
        self.Data[key]=value
        storageDirty=true
    end
    function Storage:Get(key) return self.Data[key] end
    function Storage:Save()
        if not storageDirty then return end
        writefile(storagePath,storageHttp:JSONEncode(self.Data))
        storageDirty=false
    end
    task.spawn(function()
        while Running() and task.wait(Storage.WRITE_DELAY) do
            if storageDirty then
                pcall(Storage.Save,Storage)
            end
        end
    end)
    local Support = (function()
local Support={}
function Support.CanRoll(quote,beli,reserve)
    return type(quote)=="table" and quote.RequirementsMet==true
        and type(quote.Price)=="table" and type(quote.Price.Value)=="number"
        and quote.Price.Value>=0 and beli-quote.Price.Value>=reserve
end
function Support.Random(config,api,player,reserve)
    if not config.AutoRandomFruit or player.Data.Level.Value<50 then return end
    local remote=game.ReplicatedStorage.Modules.Net:FindFirstChild("RF/GachaNetworkRF")
    if not remote then return end
    local quote=Invoke(remote,{Context="Check",BoxName="ZiolesGacha",SpokeNPC="Blox Fruit Gacha"})
    if not Support.CanRoll(quote,player.Data.Beli.Value,reserve) or not api.ActivityAllowed() then return end
    return Invoke(remote,{Context="Purchase",BoxName="ZiolesGacha"})==true
end
function Support.ShouldRejoin(visible,title,now,attempts,lastAttempt)
    if not visible or (title~="Disconnected" and title~="Connection Error") then return false end
    if attempts==0 and not lastAttempt then return true end
    return now-(lastAttempt or 0)>=math.min(120,30*2^math.min(math.max(attempts-1,0),2))
end
function Support.FishmanGate(currentX,targetX)
    if (currentX>59100)==(targetX>59100) then return nil end
    return targetX>59100 and "Entrance" or "Exit"
end
function Support.NearestQuestGiver(rows,id,level)
    local best
    for _,row in rows do
        if row.id==id and (not level or row.level==level) and (not best or row.distance<best.distance) then best=row end
    end
    return best
end
function Support.FarmMotion(time,radius,height)
    radius=math.clamp(radius,0,40);height=math.clamp(height,10,40)
    return math.sin(time*1.8)*radius,height,math.cos(time*1.8)*radius*.65
end
-- Cover origins whose clamped pull still lands inside melee range.
function Support.CampCenter(points,reference,radius,reach)
    local reachSquared=reach^2
    local near={}
    for _,p in points do
        local dx,dy,dz=p.x-reference.x,p.y-reference.y,p.z-reference.z
        if dx*dx+dy*dy+dz*dz<=radius*radius then table.insert(near,p) end
    end
    if #near==0 then return reference.x,reference.y,reference.z,0 end
    local candidates=table.clone(near)
    local mean={x=0,y=0,z=0}
    for _,p in near do mean.x+=p.x;mean.y+=p.y;mean.z+=p.z end
    mean.x/=#near;mean.y/=#near;mean.z/=#near
    table.insert(candidates,mean)
    for i,p in near do
        for j=i+1,#near do
            local q=near[j]
            table.insert(candidates,{x=(p.x+q.x)/2,y=(p.y+q.y)/2,z=(p.z+q.z)/2})
        end
    end
    local best,count,spread,bestScore=reference,0,math.huge,-1
    for _,candidate in candidates do
        local covered,primary,total=0,0,0
        for _,p in near do
            local dx,dy,dz=p.x-candidate.x,p.y-candidate.y,p.z-candidate.z
            local d=dx*dx+dy*dy+dz*dz
            if d<=reachSquared then covered+=1;total=math.max(total,d);if p.primary then primary+=1 end end
        end
        local score=primary*1000+covered
        if score>bestScore or score==bestScore and total<spread then best=candidate;count=covered;spread=total;bestScore=score end
    end
    return best.x,best.y,best.z,count
end

function Support.DodgeRadius(spread,height,radius)
    return math.clamp(math.sqrt(math.max(0,65*65-height*height))-spread-4,0,radius)
end

function Support.QuestNpcDistance(position,spawns,playerPosition)
    local distance,nearest=math.huge,nil
    for _,spawn in spawns or {} do
        local gap=(position-spawn.Position).Magnitude
        if gap<distance then distance,nearest=gap,spawn.Position end
    end
    return nearest and distance or (position-playerPosition).Magnitude,nearest
end

function Support.FarmQuestIndex(quests,index,level)
    local highest=index
    for i,row in quests do
        if row.LevelReq<=level and row.LevelReq>quests[highest].LevelReq then
            for _,count in row.Task do if count>1 then highest=i;break end end
        end
    end
    return highest
end

function Support.LibraryConfirmed(response,consumed,state)
    return state=="door absent" and (response==true or consumed==true)
end

function Support.Sea2Ready(death,shark)
    return death==true and shark==true
end

function Support.SharkmanUnlocked(response)
    -- Native dialogue: string = missing key;3 = key delivered, mastery still insufficient.
    return type(response)=="number" and response%1==0 and response>=0 and response<=3
end

function Support.InShip(position)
    return position.Z>20000 and math.abs(position.X)<10000
end

function Support.ShipCrossing(position,target)
    return Support.InShip(position)~=Support.InShip(target)
end

return Support

    end)()
    local QuestState = (function()
local QuestState={}
function QuestState.Read(data)
    if not data or not data.Info then return false,"" end
    local title={}
    local first
    for name,count in data.Info.Task or {} do
        first=first or name
        local done=data.Progress and data.Progress[name] or 0
        table.insert(title,"Defeat "..tostring(count).." "..name.." ("..tostring(done).."/"..tostring(count)..")")
    end
    local display=data.Info.Name or first
    return display or false,table.concat(title," | ")
end
return QuestState

    end)()
    local InventoryAdapter = (function()
local Adapter={}
function Adapter.Normalize(rows,definitions,meleelist,prices,lookup)
    assert(type(rows)=="table","inventory unavailable")
    local byId,result={},{}
    for _,row in rows do
        if row.ItemId and row.Key then
            byId[row.ItemId]=byId[row.ItemId] or {}
            byId[row.ItemId][row.Key]=row.Value
        end
    end
    for id,values in byId do
        local entry=definitions[id]
        local item=entry and entry.Id
        local quantity=tonumber(values.Quantity)
        if item and (values.IsOwned==true or (quantity and quantity>0)) then
            local name=item.StorageKey
            local config=lookup and lookup(id)
            local physical=config and config.State and config.State.StorageMethod=="StoredFruits"
                and config.Index and config.Index.IdType=="PhysicalMoveset"
            local kind=physical and "Blox Fruit" or ((table.find(meleelist,name) or (config and config.Moveset and config.Moveset.Type=="FightingStyle")) and "Melee" or "Material")
            result[name]={Name=name,Count=quantity or 1,Mastery=tonumber(values.Mastery) or 0,
                Type=kind,Value=(config and config.Quality and config.Quality.MoneyPrice) or (prices and prices[name]),ItemId=id}
        end
    end
    return result
end
return Adapter

    end)()
    local ElectroMovement = (function()
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Movement = {}

function Movement.Unpin(context)
	local hold = context._motionHold
	if not hold then return end
	hold.pin = nil
	if hold.pinStep then hold.pinStep:Disconnect(); hold.pinStep = nil end
end

function Movement.Release(context)
	local hold = context._motionHold
	if not hold then return end
	Movement.Unpin(context)
	context._motionHold = nil
	if hold.constraint then hold.constraint:Destroy() end
	if hold.attachment then hold.attachment:Destroy() end
	if hold.collisionConnection then hold.collisionConnection:Disconnect() end
	if hold.collisionStep then hold.collisionStep:Disconnect() end
	for part, canCollide in pairs(hold.collisions or {}) do
		if part.Parent then part.CanCollide = canCollide end
	end
	if hold.humanoid and hold.humanoid.Parent then hold.humanoid.AutoRotate = hold.autoRotate end
end

function Movement.Hold(context, root, humanoid)
	local current = context._motionHold
	if current and current.root == root and current.constraint.Parent then return end
	Movement.Release(context)
	local attachment = Instance.new("Attachment")
	attachment.Name = "KaitunMovementAttachment"
	attachment.Parent = root
	local constraint = Instance.new("LinearVelocity")
	constraint.Name = "KaitunMovementHold"
	constraint.Attachment0 = attachment
	constraint.RelativeTo = Enum.ActuatorRelativeTo.World
	constraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	constraint.VectorVelocity = Vector3.zero
	constraint.ForceLimitsEnabled = true
	constraint.MaxForce = math.max(root.AssemblyMass * workspace.Gravity * 20, 100000)
	constraint.Parent = root
	context._motionHold = { root = root, humanoid = humanoid, autoRotate = humanoid.AutoRotate, attachment = attachment, constraint = constraint }
	local hold = context._motionHold
	hold.collisions = {}
	local character = root.Parent
	local function suppressCollision(part)
		if part:IsA("BasePart") then
			if hold.collisions[part] == nil then hold.collisions[part] = part.CanCollide end
			part.CanCollide = false
		end
	end
	for _, part in ipairs(character:GetDescendants()) do suppressCollision(part) end
	hold.collisionConnection = Track(character.DescendantAdded:Connect(suppressCollision))
	hold.collisionStep = Track(RunService.PreSimulation:Connect(function()
		for part in pairs(hold.collisions) do
			if part.Parent then part.CanCollide = false end
		end
	end))
	humanoid.AutoRotate = false
	root.AssemblyLinearVelocity = Vector3.zero
end

function Movement.Pin(context, destination)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local human = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not human or human.Health <= 0 then return false, "character not ready for position hold" end
	Movement.Hold(context, root, human)
	local hold = context._motionHold
	hold.pin = destination
	if not hold.pinStep then
		hold.pinStep = Track(RunService.PostSimulation:Connect(function()
			if hold.pin and not context.IsCancelled() and root.Parent and Players.LocalPlayer.Character == character then
				root.CFrame = hold.pin
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end))
	end
	root.CFrame = destination
	return true
end

function Movement.To(context, destination, speed)
	if context.IsCancelled() then return false, "stopped" end
	Movement.Unpin(context)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid and humanoid.Health > 0) then return false, "character not ready" end
	if typeof(destination) == "Vector3" then destination = CFrame.new(destination) end
	speed = math.clamp(tonumber(speed) or 220, 10, 220)
	local distance = (root.Position - destination.Position).Magnitude
	local duration = math.max(distance / speed, 0.15)
	if duration > 120 then return false, "destination exceeds movement timeout" end
	Movement.Hold(context, root, humanoid)
	local start = root.CFrame
	local value = Instance.new("CFrameValue")
	value.Value = start
	local tween = TweenService:Create(value, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Value = destination })
	context.SetTween(tween)
	local step = Track(RunService.PreSimulation:Connect(function()
		if not context.IsCancelled() and root.Parent and Players.LocalPlayer.Character == character then root.CFrame = value.Value end
	end))
	if context.Emit then context.Emit("MOVE_START", { distance = math.floor(distance), speed = speed, target = tostring(destination.Position), mode = "CFrameValue/PreSimulation + gravity hold" }) end
	local ok, succeeded, reason = xpcall(function()
		tween:Play()
		local started = os.clock()
		while tween.PlaybackState == Enum.PlaybackState.Playing do
			if context.IsCancelled() then return false, "stopped" end
			if Players.LocalPlayer.Character ~= character or not root.Parent or humanoid.Health <= 0 then return false, "character changed or died" end
			local drift = (root.Position - value.Value.Position).Magnitude
			local remaining = (root.Position - destination.Position).Magnitude
			if drift > 80 then return false, "movement drift " .. math.floor(drift) .. " studs" end
			if os.clock() - started > duration + 3 then return false, "movement timeout" end
			task.wait(0.1)
		end
		if tween.PlaybackState ~= Enum.PlaybackState.Completed or context.IsCancelled() then return false, "movement cancelled" end
		root.CFrame = destination
		task.wait(0.15)
		if context.IsCancelled() or not root.Parent then return false, "stopped" end
		local remaining = (root.Position - destination.Position).Magnitude
		if context.Emit then context.Emit("MOVE_END", { remaining = math.floor(remaining) }) end
		return remaining <= 12, remaining > 12 and "movement finished outside destination" or nil
	end, debug.traceback)
	step:Disconnect()
	if tween.PlaybackState == Enum.PlaybackState.Playing then tween:Cancel() end
	value:Destroy()
	context.SetTween(nil)
	if not ok then return false, tostring(succeeded) end
	return succeeded == true, reason
end

return Movement

    end)()
    local ElectroCombat = (function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local NativeCombat = {}
local fruitM1SpeedModule = ReplicatedStorage:FindFirstChild("Modules")
	and ReplicatedStorage.Modules:FindFirstChild("FruitM1Speed")
local fruitM1SpeedLoaded, fruitM1SpeedResult = pcall(require, fruitM1SpeedModule)
local CombatController = require(ReplicatedStorage.Controllers.CombatController)
local CombatUtil = require(ReplicatedStorage.Modules.CombatUtil)
function NativeCombat.CheckContext()
	local ok, err = pcall(require, ReplicatedStorage:FindFirstChild("Global"))
	if not ok then
		return false, "native M1 requires game script thread context 2: " .. tostring(err)
	end
	if not fruitM1SpeedLoaded or type(fruitM1SpeedResult) ~= "table"
		or type(fruitM1SpeedResult.getWeaponCooldownScale) ~= "function" then
		return false, "native M1 cooldown module failed to preload: " .. tostring(fruitM1SpeedResult)
	end
	return true
end

local function getWeaponType(tool)
	local ok, result = pcall(function()
		local name = CombatUtil:GetWeaponName(tool)
		return CombatUtil:GetWeaponData(name).WeaponType
	end)
	if ok then
		return result
	end
	return nil
end

function NativeCombat.GetM1Tool()
	local player = Players.LocalPlayer
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return nil, "character not ready" end

	local backpack = player:FindFirstChildOfClass("Backpack")
	for _, container in {character, backpack} do
		for _, tool in container:GetChildren() do
			if not tool:IsA("Tool") or getWeaponType(tool) ~= "Melee" then continue end
			if tool.Parent ~= character then
				humanoid:EquipTool(tool)
				task.wait(.25)
			end
			if player.Character == character and tool.Parent == character then return tool end
			return nil, "melee did not equip on the current character"
		end
	end
	return nil, "quest requires an available melee tool"
end

function NativeCombat.AttackM1(tool, cancelled)
	local player = Players.LocalPlayer
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (tool and humanoid and humanoid.Health > 0) or getWeaponType(tool) ~= "Melee" then
		return false, "character or melee unavailable"
	end
	local busy = character:FindFirstChild("Busy")
	local stun = character:FindFirstChild("Stun")
	if (busy and busy.Value) or (stun and stun.Value > 0) then
		return false, "retry: game combat is busy or stunned"
	end
	if tool.Parent ~= character then
		local backpack = player:FindFirstChildOfClass("Backpack")
		if not backpack or tool.Parent ~= backpack then return false, "weapon removed or character changed" end
		humanoid:EquipTool(tool)
		task.wait(.2)
	end
	if type(CombatController.Attack) ~= "function" then return false, "native Attack method unavailable" end
	local canCheck, canAttack = pcall(CombatUtil.CanAttack, CombatUtil, character, "Melee")
	if not canCheck then return false, "retry: native combat gate check failed: " .. tostring(canAttack) end
	if not canAttack then return false, "retry: game combat is busy or stunned" end

	local globalOK, global = pcall(require, ReplicatedStorage.Global)
	if globalOK and global.mobileSelectionFrame then return false, "retry: native mobile skill selection is active" end
	local cacheOK, cache = pcall(CombatUtil.GetMovesetAnimCache, CombatUtil, humanoid)
	if cacheOK and not cache then return false, "retry: native M1 animations are not ready" end
	if player.Character ~= character or tool.Parent ~= character or (cancelled and cancelled()) then
		return false, "retry: melee or Electro activity changed"
	end
	local ok, err = xpcall(CombatController.Attack, debug.traceback, CombatController, tool)
	if not ok then return false, "native M1 call failed: " .. tostring(err) end
	return true
end

return NativeCombat

    end)()
    local ElectroProgress = (function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Progress = {}
local ADDRESS = "Sea1/Frozen Village/Breaking the Ice"

function Progress.Read(address)
	local net = ReplicatedStorage:FindFirstChild("Modules")
		and ReplicatedStorage.Modules:FindFirstChild("Net")
	local remote = net and net:FindFirstChild("RF/RequestBonusMomentReplication")
	if not (remote and remote:IsA("RemoteFunction")) then
		return nil, "progress remote unavailable"
	end

	-- A dropped connection can leave InvokeServer suspended indefinitely.
	-- This request is read-only; abandon the local waiter and let the runner
	-- retry rather than freeze a quest before its movement/M1 stage.
	local finished, timedOut, ok, result = false, false, false, nil
	local thread = task.spawn(function()
		ok, result = pcall(function()
			return remote:InvokeServer({ Type = "GetMomentProgress" })
		end)
		finished = true
	end)
	-- The watchdog also survives cancellation of the quest's outer thread.
	local watchdog=task.delay(6,function()
		if not finished then
			timedOut,finished=true,true
			pcall(task.cancel,thread)
		end
	end)
	while not finished do task.wait(.05) end
	pcall(task.cancel,watchdog)
	if timedOut then
		return nil, "progress response timed out; connection may have dropped"
	end
	if not ok then
		return nil, tostring(result)
	end
	if type(result) ~= "table" or type(result.Data) ~= "table" then
		return nil, "unexpected progress response"
	end

	return result.Data[address or ADDRESS]
end

return Progress

    end)()
    local ElectroQuest = (function()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Quest = {
	Id = "Sea1/Sky/Electric Fighting Teacher",
	Name = "Electric Fighting Teacher",
	Reward = { NPC = "Mad Scientist", GuideId = "SkyElectroTeacher", Island = "Sky", Levels = 5,
		Position = Vector3.new(-4628.8877, 12.1299, -355.7178) },
}
local HIT_TAG = "M1HitRegistry"

local function character(context)
	if context.IsCancelled() then error("stopped", 0) end
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local human = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and human and human.Health > 0) then error("character changed or died", 0) end
	if context._ElectricQuest and char ~= context._ElectricQuest.Character then error("character changed or died", 0) end
	return char, root, human
end

local function progress(context)
	local complete, issue = context.Progress.Read(Quest.Id)
	if complete == nil then error("NV05 server progress unavailable: " .. tostring(issue), 0) end
	return complete == true
end

local function travel(context, point, config, look)
	character(context)
	local destination = look and CFrame.lookAt(point, look) or CFrame.new(point)
	local ok, issue = context.Actions.Travel(context, destination, config.TravelSpeed or 200)
	if not ok then error(tostring(issue), 0) end
end

local function visitScientist(context, config)
	context.SetStatus("Travelling to Mad Scientist")
	travel(context, Quest.Reward.Position + Vector3.new(0, 4, 7), config)
	local deadline = os.clock() + (config.TargetLoadTimeout or 20)
	local model
	repeat
		character(context)
		local npcs = workspace:FindFirstChild("NPCs")
		model = npcs and npcs:FindFirstChild(Quest.Reward.NPC)
		if not model then task.wait(.2) end
	until model or os.clock() > deadline
	if not model then error("Mad Scientist did not stream in", 0) end
	local pivot = model:GetPivot()
	travel(context, pivot.Position + Vector3.new(0, 3, 7), config, pivot.Position)
	context.Movement.Release(context)
	local _, root = character(context)
	if (root.Position - pivot.Position).Magnitude > 12 then error("outside Mad Scientist interaction range", 0) end
	return model
end

local function partValid(part)
	return typeof(part) == "Instance" and part:IsA("BasePart") and part:IsDescendantOf(workspace)
end

local function rootValid(root)
	local map = workspace:FindFirstChild("Map")
	local sky = map and map:FindFirstChild("Sky")
	return sky and partValid(root) and root:IsDescendantOf(sky)
end

local function hasBolt(state)
	return state == 3 or state == 4
end

local function readState()
	local value = Remotes.CommF_:InvokeServer("ElectroQuestState")
	if type(value) ~= "number" then error("native ElectroQuestState unavailable", 0) end
	return value
end

local function observe(context)
	local active, popped, ended = {}, setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
	local events = ReplicatedStorage.Remotes:FindFirstChild("BonusMomentsRemoteEvent")
	if not events then error("native cloud events unavailable", 0) end
	local diagnostics = context._ElectricQuest
	local function mark(root, hit)
		if not rootValid(root) then return end
		local row = active[root] or { Revision = 0, LastProgress = os.clock() }
		if row.Part ~= hit then row.Revision += 1; row.LastProgress = os.clock() end
		row.Part = hit
		active[root] = row
		return row
	end
	local connection = Track(events.OnClientEvent:Connect(function(name, event, a, b, c)
		if name ~= Quest.Name or context.IsCancelled() then return end
		diagnostics.LastEvent = event
		if event == "Charge" then
			ended[a] = nil
			local hit = partValid(b) and b or a
			popped[hit] = nil
			mark(a, hit)
		elseif event == "Split" then
			if active[a] then
				local row = mark(a, partValid(c) and c or nil)
				if row then row.Revision += 1; row.LastProgress = os.clock() end
			end
		elseif event == "Pop" then
			if typeof(a) == "Instance" then popped[a] = true end
			for _, row in pairs(active) do
				if row.Part == a then row.Part = nil; row.Revision += 1; row.LastProgress = os.clock() end
			end
		elseif event == "Break" or event == "Discharge" then
			active[a] = nil
			ended[a] = true
			if event == "Break" then
				diagnostics.LastBreakLightning = c == true

			end
		elseif event == "Restore" then
			active[a] = nil; ended[a] = nil; popped[a] = nil
		elseif event == "Clear" then
			table.clear(active); table.clear(popped); table.clear(ended)
		end
	end))
	context.AddCleanup(function() connection:Disconnect() end)

	local function sync()
		-- Read the same live tables used by Charge/Discharge and sparkPart.
		-- No cloud state, hit tag, attribute, or native upvalue is modified.
		local getter = debug and debug.getupvalues or getupvalues
		if type(getter) ~= "function" then return false end
		local module = ReplicatedStorage.BonusMoments:FindFirstChild(Quest.Name)
		if not module then return false end
		local loaded, native = pcall(require, module)
		if not loaded or not native.RemoteEvents or type(native.RemoteEvents.Charge) ~= "function" then return false end
		local ok, upvalues = pcall(getter, native.RemoteEvents.Charge)
		if not ok or type(upvalues) ~= "table" or type(upvalues[3]) ~= "table" or type(upvalues[4]) ~= "table" then return false end
		local hitByRoot, charged = upvalues[3], upvalues[4]
		for root, value in pairs(charged) do
			if typeof(root) ~= "Instance" or type(value) ~= "boolean" then return false end
		end
		for root, hit in pairs(hitByRoot) do
			if typeof(root) ~= "Instance" or typeof(hit) ~= "Instance" then return false end
		end
		for root in pairs(active) do if charged[root] ~= true or ended[root] then active[root] = nil end end
		for root, chargedNow in pairs(charged) do
			if chargedNow and not ended[root] and rootValid(root) then
				local hit = hitByRoot[root] or root
				if popped[hit] then hit = nil end
				mark(root, hit)
			end
		end
		return true
	end
	local function valid(root, row)
		local hit = row and row.Part
		return not ended[root] and rootValid(root) and partValid(hit) and not popped[hit]
			and CollectionService:HasTag(hit, HIT_TAG) and hit.Transparency < .05
			and hit.LocalTransparencyModifier < .95 and hit.Size.Magnitude > .5
	end
	return active, sync, valid
end

function Quest.Run(context, config)
	config = config or {}
	if (game.PlaceId ~= 2753915549 and game.PlaceId ~= 85211729168715) then return false, "NV05 requires Sea 1" end
	local char = Players.LocalPlayer.Character
	context._ElectricQuest = { Character = char, StartingLevel = Players.LocalPlayer.Data.Level.Value }
	if progress(context) then context._ElectricQuest.InitiallyComplete = true; return true end
	character(context)
	local interaction = require(ReplicatedStorage.Util.BonusMomentInteraction)
	if interaction.isTransformed(char) then return false, "exit fruit transformation before NV05" end
	local ready, issue = context.Combat.CheckContext()
	if not ready then return false, issue end
	local active, sync, valid = observe(context)
	local state = readState()
	if state == 0 or state == 5 then
		visitScientist(context, config)
		state = readState()
		if state == 0 or state == 5 then
			context.SetStatus("Accepting Mad Scientist's Lightning Bolt task")
			local accepted = Remotes.CommF_:InvokeServer("AcceptElectroQuest")
			state = readState()
			if accepted ~= 1 and state ~= 1 and not hasBolt(state) then return false, "Mad Scientist rejected NV05" end
		end
	end
	local deadline = os.clock() + (config.QuestTimeout or 900)
	local nextState, nextProgress, lastAttack = 0, 0, 0
	local heldRoot, heldPart, heldSize
	local calls = 0
	while not hasBolt(state) do
		local current, root, human = character(context)
		if os.clock() >= deadline then return false, "NV05 timed out without authoritative Lightning Bolt state" end
		if os.clock() >= nextState then
			state = readState(); nextState = os.clock() + .8

			if hasBolt(state) then break end
			if state ~= 1 then return false, "NV05 changed to unexpected state " .. tostring(state) end
		end
		if os.clock() >= nextProgress then
			nextProgress = os.clock() + 3
			if progress(context) then return true end
		end
		local seeded = sync()
		local selectedRoot, selected, best
		for cloud, row in pairs(active) do
			if valid(cloud, row) then
				local distance = (root.Position - row.Part.Position).Magnitude
				if not best or distance < best then selectedRoot, selected, best = cloud, row, distance end
			end
		end
		if not selected then
			if heldRoot then context.Movement.Unpin(context); heldRoot, heldPart, heldSize = nil, nil, nil end
			context.SetStatus(seeded and "Waiting for a currently charged native cloud" or "Waiting for native Charge; snapshot unavailable")
			task.wait(.2)
			continue
		end
		local part, revision = selected.Part, selected.Revision
		local center = part.Position + Vector3.new(0, config.CenterHeight or 0, 0)
		local pose = CFrame.lookAt(center, center + Vector3.new(0, 0, -1))
		if heldRoot ~= selectedRoot or heldPart ~= part or (root.Position - center).Magnitude > 10 then
			context.SetStatus("Moving to the live center of the charged cloud piece")
			local moved, moveIssue = context.Actions.Travel(context, pose, config.ApproachSpeed or 200)
			if not moved then return false, moveIssue end
			sync()
			if active[selectedRoot] ~= selected or selected.Part ~= part or selected.Revision ~= revision or not valid(selectedRoot, selected) then continue end
			heldRoot, heldPart, heldSize = selectedRoot, part, part.Size
		end
		if active[selectedRoot] ~= selected or selected.Part ~= part or not valid(selectedRoot, selected) then continue end
		center = part.Position + Vector3.new(0, config.CenterHeight or 0, 0)
		local pinned, pinIssue = context.Movement.Pin(context, CFrame.lookAt(center, center + Vector3.new(0, 0, -1)))
		if not pinned then return false, pinIssue end
		if heldSize and (part.Size - heldSize).Magnitude > .1 then selected.LastProgress = os.clock(); heldSize = part.Size end
		if os.clock() - lastAttack >= (config.AttackInterval or .4) then
			local tool, toolIssue = context.Combat.GetM1Tool()
			if not tool then return false, toolIssue end
			character(context)
			sync()
			if active[selectedRoot] ~= selected or selected.Part ~= part or not valid(selectedRoot, selected) then continue end
			context.SetStatus("Hitting only the native charged piece; following Split/Pop")
			local attacked, attackIssue = context.Combat.AttackM1(tool, context.IsCancelled)
			lastAttack = os.clock()
			if attacked then calls += 1 end

			if not attacked and not tostring(attackIssue):find("retry:", 1, true) then return false, attackIssue end
		end
		task.wait(.1)
	end
	context.Movement.Unpin(context)

	visitScientist(context, config)
	state = readState()
	if not hasBolt(state) then return false, "Lightning Bolt state was lost before delivery" end
	context.SetStatus("Handing Lightning Bolt to Mad Scientist")
	local delivered = Remotes.CommF_:InvokeServer("DeliverLightningBolt")
	if delivered ~= 1 then return false, "Mad Scientist did not confirm Lightning Bolt delivery" end
	context._ElectricQuest.Delivered = true
	local verifyDeadline = os.clock() + (config.ProgressTimeout or 20)
	repeat
		character(context)
		if progress(context) then  return true end
		task.wait(.4)
	until os.clock() >= verifyDeadline
	return false, "Lightning Bolt delivered, but server objective remains unconfirmed"
end

function Quest.FinishReward(context, config)
	config = config or {}
	if not progress(context) then return false, "NV05 server objective is not complete" end
	local player = Players.LocalPlayer
	local before = context.StartingLevel and context.StartingLevel() or context._ElectricQuest.StartingLevel

	visitScientist(context, config)
	local guide = require(ReplicatedStorage.BonusMomentsGuide)
	local response = guide.interactQuestGiver(Quest.Reward.GuideId)
	local map = require(ReplicatedStorage.Definitions.Map)
	local definition = map.getBonusMoment(map.getIsland(map.getMap("Sea1"), Quest.Reward.Island), Quest.Name)
	local expected = definition and definition.Dialogue
	local opening = type(response) == "table" and response.OpeningDialogue
	local function matches(lines)
		for _, line in ipairs(type(opening) == "table" and opening or {}) do
			for _, wanted in ipairs(type(lines) == "table" and lines or {}) do if line == wanted then return true end end
		end
		return false
	end
	if context._ElectricQuest.InitiallyComplete and expected and not matches(expected.Reward) then
		-- A verified completed run returns nil from SkyElectroTeacher after its
		-- reward has been collected. Check at the real NPC and query the tracker.
		local ok, tracker = pcall(guide.getRewardTracker)
		local target = ok and tracker and tracker.Options and tracker.Options.Target
		local pending = typeof(target) == "Vector3" and (target - Quest.Reward.Position).Magnitude < 20
		if ok and not pending and progress(context) then

			return true
		end
	end
	if type(response) ~= "table" then return false, "Mad Scientist reward guide returned no dialogue" end
	local deadline = os.clock() + (config.RewardTimeout or 20)
	repeat
		character(context)
		local level = player.Data.Level.Value
		local ok, tracker = pcall(guide.getRewardTracker)
		local target = ok and tracker and tracker.Options and tracker.Options.Target
		local pending = typeof(target) == "Vector3" and (target - Quest.Reward.Position).Magnitude < 20

		if ok and not pending and progress(context) and level >= math.min(before + 5, 3000) then

			return true
		end
		task.wait(.4)
	until os.clock() > deadline
	return false, "NV05 objective complete; level reward has not been confirmed"
end

return Quest

    end)()
    local ServerHop = (function()
local HopPolicy={}
function HopPolicy.CanHop(reason,distance,radius,combat)
    return reason=="manual" or reason=="boss key"
        or reason=="player combat" and combat==true
        or reason=="nearby player" and type(distance)=="number" and distance>=0 and distance<=radius
end
function HopPolicy.ChooseKeyServer(servers,current,maxPlayers,history,now)
    local candidates={}
    for id,row in servers do
        local count=type(row)=="table" and tonumber(row.Count)
        local prior=history[id]
        if id~=current and count and count>=0 and count<maxPlayers and (not prior or now-(prior.at or 0)>600) then
            table.insert(candidates,{job=id,region=row.Region,players=count})
        end
    end
    if #candidates>0 then return candidates[math.random(#candidates)] end
end
function HopPolicy.RegionAllowed(region)
    local value=tostring(region or ""):lower():gsub("[^a-z]","")
    return value=="sg" or value=="hk" or value=="asiasg" or value=="asiahk"
        or value:find("singapore",1,true)~=nil or value:find("hongkong",1,true)~=nil
end
function HopPolicy.Choose(servers,current,maxPlayers,history,now,maxPing)
    local best,bestScore
    local badRegions={}
    local function group(region) return tostring(region):lower():find("singapore",1,true) and "SG" or "HK" end
    for _,prior in history do
        if type(prior)=="table" and prior.ping and prior.ping>(maxPing or 150) then badRegions[group(prior.region)]=true end
    end
    for id,row in type(servers)=="table" and servers or {} do
        local count=type(row)=="table" and tonumber(row.Count)
        local prior=history[id]
        if type(id)=="string" and id~=current and count and count>=0 and count<maxPlayers
            and HopPolicy.RegionAllowed(row.Region) and (not prior or now-(prior.at or 0)>600) then
            local ping=tonumber(row.Ping or row.ping)
            local score=count*10+(ping or 150)+(badRegions[group(row.Region)] and 1000 or 0)
            if not bestScore or score<bestScore then best={job=id,region=row.Region,players=count,advertisedPing=ping};bestScore=score end
        end
    end
    return best
end
function HopPolicy.Median(samples)
    if #samples==0 then return nil end
    local copy=table.clone(samples);table.sort(copy)
    return copy[math.ceil(#copy/2)]
end
function HopPolicy.Start(ctx)
    local API,Config,task=ctx.API,ctx.Config,ctx.task
    local Running,Track,Invoke=ctx.Running,ctx.Track,ctx.Invoke
    local player=game.Players.LocalPlayer
    local browser=game.ReplicatedStorage:WaitForChild("__ServerBrowser")
    local http=game:GetService("HttpService")
    local file="Kaitun3TN.hop."..player.UserId..".json"
    local record={history={},attempts=0,lastHop=0}
    pcall(function()
        if isfile(file) then
            local data=http:JSONDecode(readfile(file))
            if type(data)=="table" and type(data.history)=="table" then record=data end
        end
    end)
    local function save() pcall(writefile,file,http:JSONEncode(record)) end
    local busy,nextTry,cache,cacheAt=false,0,{},-math.huge
    local attempt=0
    local function currentJob()
        local ok,id=pcall(Invoke,browser,"getjob")
        return ok and type(id)=="string" and id or game.JobId
    end
    local current=currentJob()
    local function nearestPlayer()
        local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        local nearest=math.huge
        if not root then return nearest end
        for _,other in game.Players:GetPlayers() do
            local char=other~=player and other.Character
            local part=char and char:FindFirstChild("HumanoidRootPart")
            local human=char and char:FindFirstChildOfClass("Humanoid")
            if part and human and human.Health>0 then nearest=math.min(nearest,(part.Position-root.Position).Magnitude) end
        end
        return nearest
    end
    local function factoryActive()
        local enemies=workspace:FindFirstChild("Enemies")
        local core=enemies and enemies:FindFirstChild("Core")
        local human=core and core:FindFirstChildOfClass("Humanoid")
        return human and human.Health>0
    end
    local function pvpCombat()
        local gui=player:FindFirstChild("PlayerGui")
        local main=gui and gui:FindFirstChild("Main")
        local bottom=main and main:FindFirstChild("BottomHUDList")
        local label=bottom and bottom:FindFirstChild("InCombat")
        return label~=nil and label:IsA("GuiObject") and label.Visible
    end
    local function servers()
        if os.clock()-cacheAt<60 then return cache end
        local page,done,rows=0,0,{}
        local workers={}
        for worker=1,6 do
            table.insert(workers,task.spawn(function()
                while Running() do
                    page+=1;local shard=page;if shard>100 then break end
                    local ok,data=pcall(Invoke,browser,shard)
                    if ok and type(data)=="table" then for id,row in data do rows[id]=row end end
                    done+=1
                end
            end))
        end
        local deadline=os.clock()+30
        while Running() and done<100 and os.clock()<deadline do task.wait(.1) end
        for _,worker in workers do if coroutine.status(worker)~="dead" then pcall(task.cancel,worker) end end
        cache,cacheAt=rows,os.clock()
        return rows
    end
    local function failed(issue)
        busy=false;API.HopInProgress=false;API.Phase="running"

        record.pending=nil;save()
        nextTry=os.clock()+30
    end
    API.RequestHop=function(reason,retry)
        if busy or API.Paused or not Running() then return false,"runner busy" end
        if os.clock()<nextTry then return false,"retry waiting" end
        if API.IsRaidBusy and API.IsRaidBusy() then return false,"raid in progress" end
        local distance=reason=="nearby player" and nearestPlayer() or nil
        local combat=reason=="player combat" and pvpCombat()
        if not HopPolicy.CanHop(reason,distance,Config.NearPlayerRadius,combat) then return false,"trigger cleared" end
        if reason=="boss key" and (not ctx.NeedBossKey or not ctx.NeedBossKey()) then return false end
        if reason~="manual" and factoryActive() then return false,"Factory active" end
        if reason~="manual" and ctx.KeyPending and ctx.KeyPending() then return false,"key pending" end
        if not retry and os.time()-(record.lastHop or 0)<Config.NearPlayerCooldown then return false,"cooldown" end
        busy=true;API.HopInProgress=true;API.Phase="hopping"
        attempt+=1
        local currentAttempt=attempt
        if API.CancelFarm then API.CancelFarm() end

        -- Keep a confirmed sighting valid while the server browser runs.
        task.spawn(function()
            local ok,issue=pcall(function()
                local rows=servers()
                if not busy or attempt~=currentAttempt then return end
                local choose=reason=="boss key" and HopPolicy.ChooseKeyServer or HopPolicy.Choose
                local target=choose(rows,current,game.Players.MaxPlayers,record.history,os.time(),Config.MaxServerPing)
                if not target then error("No eligible server in native server browser") end
                if API.Paused or not Running() then failed("Runner paused or stopped");return end
                if API.IsRaidBusy and API.IsRaidBusy() then failed("Raid in progress");return end
                if reason~="manual" and factoryActive() then failed("Factory active");return end
                  if reason~="manual" and ctx.KeyPending and ctx.KeyPending() then
                      failed("Key pending; teleport deferred")
                      return
                  end
                if reason=="boss key" and not ctx.NeedBossKey() then
                    failed("Key hunt no longer needed")
                    return
                end
                record.attempts=retry and (record.attempts or 0)+1 or 1
                target.reason=reason
                record.lastHop=os.time();record.pending=target
                record.history[target.job]={at=os.time(),region=target.region}
                for id,row in record.history do if os.time()-(row.at or 0)>3600 then record.history[id]=nil end end
                save();

                Invoke(browser,"teleport",target.job)
            end)
            if not ok and busy and attempt==currentAttempt then failed(issue) end
        end)
        task.delay(65,function() if busy and attempt==currentAttempt then failed("Teleport was not confirmed") end end)
        return true
    end
    Track(game:GetService("TeleportService").TeleportInitFailed:Connect(function(who,result,message)
        if who==player and busy then failed(tostring(result).." | "..tostring(message)) end
    end))
    task.spawn(function()
        while Running() do
            local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if Config.HopPlayerNear and root and not busy and not API.Paused then
                local nearest=nearestPlayer()
                local nearby=nearest<=Config.NearPlayerRadius
                local reason=pvpCombat() and "player combat" or nearby and "nearby player"
                if reason and API.CurrentTask=="LevelFarm" then API.RequestHop(reason) end
            end
            task.wait(.5)
        end
    end)
    task.spawn(function()
        while Running() and API.Phase=="initializing" do task.wait(1) end
        task.wait(4)
        local prior=record.pending and record.pending.job==current and record.pending or record.history[current]
        if not prior then return end
        if record.pending and record.pending.job==current then

            record.pending=nil;save()
        end
        if not HopPolicy.RegionAllowed(prior.region) then return end
        local samples={}
        for i=1,7 do
            local stat=game:GetService("Stats").Network.ServerStatsItem:FindFirstChild("Data Ping")
            local ping=stat and stat:GetValue()
            if type(ping)=="number" and ping>0 then table.insert(samples,ping) end
            task.wait(1)
        end
        local ping=HopPolicy.Median(samples)
        record.history[current]={at=os.time(),region=prior.region,ping=ping}
        record.pending=nil;save()
    end)
end
return HopPolicy

    end)()
    local itemDefinitions=require(game.ReplicatedStorage.Economy.ItemId.RawSource)
    local itemPrices={}
    local itemConfig=require(game.ReplicatedStorage.ItemConfig)
    local nextInventoryRefresh=0
    function RefreshInventory()
        if os.clock()<nextInventoryRefresh then return end
        local rows=Invoke(game.ReplicatedStorage.Modules.Net["RF/GetAllItemValues"])
        local normalized=InventoryAdapter.Normalize(rows,itemDefinitions,MeleesTable or {},itemPrices,itemConfig.tryGet)
        nextInventoryRefresh=os.clock()+10
        ScriptStorage.Backpack=normalized
        for name,item in normalized do
            if item.Type=="Melee" then ScriptStorage.Melees[CanonicalMelee(name)]=item.Mastery end
        end
        API.InventoryKnown=true
        if API.RestoreHunterCape then API.RestoreHunterCape(rows) end
    end
    -- Shares Main() locals with the supplied Electro and farm adapters.
    local electroCleanups={}
    local electroContext={}
    local farmContext={IsCancelled=function() return not Running() or API.Paused end}
    local farmDestination,farmCharacter,farmDoorSide
    local farmMoveEpoch,previousRootPosition
    local lastBoostCorrection,boostPosition,boostDirection=-math.huge,nil,nil
    local previousPortal=-math.huge
    local portalInFlight=false
    local skyGateAttempt,skyGateRetryAt=nil,0
    local function ClearFarmMove(keepHold)
        farmDestination=nil;farmCharacter=nil;farmDoorSide=nil
        farmMoveEpoch=nil;previousRootPosition=nil;portalInFlight=false
        boostPosition,boostDirection=nil,nil
        if not keepHold then ElectroMovement.Release(farmContext) end
    end
    API.ClearMove=ClearFarmMove
    local function NativeTransition()
        return game:GetService("CollectionService"):HasTag(LocalPlayer,"Teleporting")
    end
    function TweenController.Create(target)
        if not target or not Running() or API.Paused or API.HopInProgress or API.Phase=="electro" or not API.ActivityAllowed() then return end
        local exiting=API.CurrentTask=="RaidController" and API.Raid and API.Raid.exiting
        if API.Raid and API.Raid.awaitingExit and not exiting then ClearFarmMove();return end
        local moveEpoch=API.ActivityEpoch
        if NativeTransition() then ClearFarmMove();return end
        if portalInFlight then return end
        local char=LocalPlayer.Character
        local root=char and char:FindFirstChild("HumanoidRootPart")
        local human=char and char:FindFirstChildOfClass("Humanoid")
        if not root or not human or human.Health<=0 then ClearFarmMove();return end
        if farmDestination and previousRootPosition and (root.Position-previousRootPosition).Magnitude>1000 then
            ClearFarmMove();return
        end
        local cf=typeof(target)=="CFrame" and target or CFrame.new(target)
        local raidActive=exiting or API.IsRaidActive and API.IsRaidActive()
        if not raidActive and SeaIndex==1 and Config.UsePortals then
            local upper=root.Position.Y>4000
            local targetUpper=cf.Position.Y>4000
            if skyGateAttempt and (skyGateAttempt.character~=char or skyGateAttempt.epoch~=moveEpoch) then skyGateAttempt=nil end
            if skyGateAttempt and upper~=skyGateAttempt.upper then
                skyGateAttempt=nil
            end
            if upper~=targetUpper and os.clock()>=skyGateRetryAt then
                local name=upper and "Exit" or "Entrance"
                local map=workspace:FindFirstChild("Map")
                local island=map and map:FindFirstChild(upper and "SkyArea2" or "Sky")
                local gate=island and island:FindFirstChild(name)
                if gate and gate.CanTouch~=false then
                    if not skyGateAttempt then
                        skyGateAttempt={name=name,upper=upper,character=char,epoch=moveEpoch,deadline=os.clock()+50}
                    end
                    if (root.Position-gate.Position).Magnitude<10 then skyGateAttempt.atGate=skyGateAttempt.atGate or os.clock() end
                    if os.clock()<skyGateAttempt.deadline and os.clock()-(skyGateAttempt.atGate or math.huge)<5 then
                        farmCharacter=char;farmDoorSide=nil;farmMoveEpoch=moveEpoch;previousRootPosition=root.Position
                        farmDestination=CFrame.new(gate.Position+Vector3.new(0,.5,0))
                        return
                    end
                    skyGateAttempt=nil;skyGateRetryAt=os.clock()+45
                end
            end
        end
        local gateName=not raidActive and SeaIndex==1 and Support.FishmanGate(root.Position.X,cf.Position.X)
        if gateName then
            local map=workspace:FindFirstChild("Map")
            local gates=map and map:FindFirstChild("TeleportSpawn")
            local gate=gates and gates:FindFirstChild(gateName)
            if gate then
                cf=CFrame.new(gate.Position+Vector3.new(0,.5,0))
            end
        end
        if (root.Position-cf.Position).Magnitude>1000 and os.clock()-previousPortal>8
            and not raidActive and Config.UsePortals and (SeaIndex==1 or SeaIndex==2) then
            previousPortal=os.clock()
            farmDestination=nil;farmDoorSide=nil;farmMoveEpoch=nil;previousRootPosition=nil
            ElectroMovement.Hold(farmContext,root,human)
            local request={}
            portalInFlight=request
            local ok,point=pcall(GetPortal,cf)
            if ok and point then task.wait(.4) end
            if portalInFlight~=request then return end
            portalInFlight=false
            if moveEpoch~=API.ActivityEpoch or not API.ActivityAllowed() then ClearFarmMove();return end
            if not Running() or API.Paused or API.HopInProgress or API.Phase=="electro"
                or LocalPlayer.Character~=char or not root.Parent or human.Health<=0 or NativeTransition() then
                ClearFarmMove();return
            end
        end
        farmCharacter=char;farmDoorSide=nil;farmMoveEpoch=moveEpoch;previousRootPosition=root.Position
        if not raidActive and SeaIndex==2 and Support.ShipCrossing(root.Position,cf.Position) then
            local map=workspace:FindFirstChild("Map")
            local model=map and map:FindFirstChild(Support.InShip(root.Position) and "GhostShipInterior" or "GhostShip")
            local gate=model and model:FindFirstChild("Teleport")
            farmDestination=gate and gate.CFrame or nil
                farmDoorSide=Support.InShip(root.Position)
            return
        end
        if not raidActive and SeaIndex==3 and cf.Position.Y< -1000
            and (cf.Position-Vector3.new(11256,-2138,9888)).Magnitude<(root.Position-cf.Position).Magnitude-700 then
            local boat=CFrame.new(-16269,23,1371)
            if (root.Position-boat.Position).Magnitude>60 then
                farmDestination=boat;return
            elseif os.clock()-previousPortal>8 then
                previousPortal=os.clock()
                Invoke(require(game.ReplicatedStorage.Modules.Net):RemoteFunction("SubmarineWorkerSpeak"),"TravelToSubmergedIsland")
                ClearFarmMove();return
            end
        end
        farmDestination=cf
    end
    local eliteEquippedCharacter
    local function NormalFarmMovement()
        return API.CurrentTask=="LevelFarm" or API.CurrentTask=="BonesStock"
    end
    local function EliteSpeedBuff(char,human)
        return human.WalkSpeed>=64 and (eliteEquippedCharacter==char or char:FindFirstChild("HunterCapeGreen")~=nil)
    end
    Track(game:GetService("RunService").PreSimulation:Connect(function(dt)
        if not Running() or API.Paused or API.Phase=="electro" or API.HopInProgress then
            ClearFarmMove();return
        end
        if NativeTransition() then
            ClearFarmMove()
            return
        end
        if portalInFlight or not farmDestination then return end
        if farmMoveEpoch~=API.ActivityEpoch then ClearFarmMove();return end
        local char=LocalPlayer.Character
        local root=char and char:FindFirstChild("HumanoidRootPart")
        local human=char and char:FindFirstChildOfClass("Humanoid")
        if char~=farmCharacter or not root or not human or human.Health<=0 then ClearFarmMove();return end
        if previousRootPosition and (root.Position-previousRootPosition).Magnitude>1000 then
            ClearFarmMove();return
        end
        -- The native tag can start and finish between frames; never reuse an old-side door.
        if farmDoorSide~=nil and farmDoorSide~=Support.InShip(root.Position) then ClearFarmMove();return end
        local camp=API.Metrics.SelectedCamp
        if API.CurrentTask=="LevelFarm" and camp and camp.name then CombatController.Grab(camp.name) end
        ElectroMovement.Hold(farmContext,root,human)
        local delta=farmDestination.Position-root.Position
        local distance=delta.Magnitude
        local direction=distance>.1 and delta.Unit
        if boostPosition then
            local rollback=(boostPosition-root.Position):Dot(boostDirection)
            if rollback>8 and os.clock()-lastBoostCorrection>=60 then
                lastBoostCorrection=os.clock()

            end
        end
        local speed=Config.TweenSpeed
        local boost=direction and SeaIndex==3 and NormalFarmMovement() and speed==220
            and Config.HunterCapeTweenSpeed>speed and EliteSpeedBuff(char,human)
        if boost then speed=Config.HunterCapeTweenSpeed end
        local step=math.min(distance,speed*math.min(dt,.1))
        if direction then root.CFrame=CFrame.new(root.Position+direction*step) end
        boostPosition=boost and root.Position or nil
        boostDirection=boost and direction or nil
        root.AssemblyLinearVelocity=Vector3.zero
        root.AssemblyAngularVelocity=Vector3.zero
        previousRootPosition=root.Position
    end))
    do
        local checkedCharacter,nextEquipAt=nil,0
        function API.RestoreHunterCape(rows)
            if SeaIndex~=3 or not Running() then return end
            local char=LocalPlayer.Character
            local human=char and char:FindFirstChildOfClass("Humanoid")
            local owned,equipped
            for _,row in rows do
                local id=row.ItemId
                if type(id)=="number" and id>=1215 and id<=1220 and row.Value==true then
                    if row.Key=="IsEquipped" then equipped=row end
                    if row.Key=="IsOwned" and type(row.NetworkedUID)=="string"
                        and (not owned or id<owned.ItemId) then owned=row end
                end
            end
            API.EliteSpeedAccessoryOwned=owned~=nil or equipped~=nil
            eliteEquippedCharacter=equipped and char or nil
            if equipped or not owned or not human or human.Health<=0 or not NormalFarmMovement()
                or API.Paused or API.HopInProgress or API.IsRaidBusy and API.IsRaidBusy() then return end
            if char~=checkedCharacter then checkedCharacter=char;nextEquipAt=0 end
            if os.clock()<nextEquipAt then return end
            nextEquipAt=os.clock()+20
            task.spawn(function()
                if not Running() or API.Paused or API.HopInProgress or not NormalFarmMovement() or LocalPlayer.Character~=char
                    or API.IsRaidBusy and API.IsRaidBusy() then return end
                local ok,issue=pcall(function()
                    local storage=game.ReplicatedStorage
                    local remote=require(storage.Controllers.UI.Inventory.RemoteUtil)
                    local action=require(storage.PseudoEnum).InventoryAction.EquipItem
                    remote.invokeAction(action,owned.ItemId,owned.NetworkedUID,false):await()
                end)
                if not Running() or LocalPlayer.Character~=char then return end

            end)
        end
    end
    electroContext.IsCancelled=function() return not Running() or API.Paused or ShouldYieldForEvent and ShouldYieldForEvent("ElectroQuest") end
    electroContext.AddCleanup=function(fn) table.insert(electroCleanups,fn) end
    electroContext.SetStatus=function(text) SetTask("MainTask",text) end
    electroContext.SetTween=function(tween) electroContext.Tween=tween end
    electroContext.Progress=ElectroProgress
    electroContext.Combat=ElectroCombat
    electroContext.Movement=ElectroMovement
    electroContext.Actions={Travel=function(ctx,cf,speed) return ElectroMovement.To(ctx,cf,speed) end}
    local function releaseElectro()
        if electroContext.Tween then pcall(function() electroContext.Tween:Cancel() end) end
        ElectroMovement.Release(electroContext)
        for _,fn in electroCleanups do pcall(fn) end
        table.clear(electroCleanups)
    end
    local lastElectroTry=-math.huge
    function RunElectro()
        if Remotes.CommF_:InvokeServer("BuyElectro",true)==1 then API.ElectroUnlocked=true; return true end
        if SeaIndex~=1 then Remotes.CommF_:InvokeServer("TravelMain"); return false end
        if os.clock()-lastElectroTry<120 then return false end
        lastElectroTry=os.clock()
        API.Phase="electro"
        farmDestination=nil
        ElectroMovement.Release(farmContext)
        local identity=getthreadidentity()
        setthreadidentity(2)
        local ok,done,issue=xpcall(function()
            local complete,reason=ElectroQuest.Run(electroContext,{QuestTimeout=900,TravelSpeed=220,ApproachSpeed=220})
            if not complete then return false,reason end
            -- The supplied module separates objective and level reward; purchase is separate too.
            local rewarded,rewardIssue=ElectroQuest.FinishReward(electroContext,{TravelSpeed=220})
            API.ElectroReward={confirmed=rewarded,issue=tostring(rewardIssue)}
            if not rewarded then return false,rewardIssue end
            API.ElectroUnlocked=true
            Storage:Set("ElectroRewardReceipt",API.ElectroReward);Storage:Save()
            return true
        end,debug.traceback)
        releaseElectro()
        setthreadidentity(identity)
        API.Phase="farming"
        if not ok or not done then  return false end
        return true
    end
    local ownedMobs=setmetatable({},{__mode="k"})
    local regularFarmNames={}
    for _,rows in require(game.ReplicatedStorage.Quests) do
        for _,quest in rows do
            if type(quest)=="table" and quest.Task then
                for name,count in quest.Task do if count>1 then regularFarmNames[name]=true end end
            end
        end
    end
    local round
    local function mobOrigin(root)
        local row=ownedMobs[root]
        return row and row.origin or root.Position
    end
    local function IsBringMobInRange(mob,center,radius)
        return not (API.IsElitePirate and API.IsElitePirate(mob))
            and (mobOrigin(mob.HumanoidRootPart)-center).Magnitude<=(radius or Config.BringDistance)
    end
    local function ReleaseMob(root,row)
        local mob=root.Parent
        if not mob then return end
        local human=mob:FindFirstChildOfClass("Humanoid")
        if human and row.walkSpeed then
            human.WalkSpeed=row.walkSpeed; human.JumpPower=row.jumpPower; human.AutoRotate=row.autoRotate
        end
        for _,name in {"FarmingVelocity","FarmingPosition"} do
            local object=root:FindFirstChild(name)
            if object then object:Destroy() end
        end
        for _,part in mob:GetDescendants() do
            if part:IsA("BasePart") and collisions[part]~=nil then part.CanCollide=collisions[part] end
        end
        root:SetAttribute("Kaitun3TNOrigin",nil)
    end
    function API.EndBringRound()
        round=nil
        API.FarmCenter=nil
        for root,row in ownedMobs do ReleaseMob(root,row);ownedMobs[root]=nil end
    end
    function API.BeginBringRound(mob,camp,includeBosses)
        API.EndBringRound()
        local root=mob.HumanoidRootPart
        round={name=mob.Name,root=root,anchor=root.Position}
        round.includeBosses=includeBosses==true
        round.radius=API.CurrentTask=="RaidController" and API.RaidActive and Config.RaidBringDistance or Config.BringDistance
        if camp then round.anchor=camp.center;round.camp=camp end
        API.FarmCenter=round.anchor
    end
    function API.IsRoundMob(mob)
        if not round then return true end
        return mob.HumanoidRootPart==round.root
            or (round.includeBosses or not mob:GetAttribute("IsBoss")) and IsBringMobInRange(mob,round.anchor,round.radius)
    end
    function FarmPose(name,fallback)
        if round and round.camp and round.name==name then fallback=round.anchor end
        fallback=typeof(fallback)=="CFrame" and fallback or CFrame.new(fallback)
        if not round or round.name~=name or not Config.DodgeMobs then
            return fallback+Vector3.new(0,Config.FightHeight,0)
        end
        local spread=API.Metrics.Bring and API.Metrics.Bring.name==name and API.Metrics.Bring.spread or 0
        local radius=Support.DodgeRadius(spread,Config.DodgeHeight,Config.DodgeRadius)
        local x,y,z=Support.FarmMotion(os.clock()-started,radius,Config.DodgeHeight)
        return fallback+Vector3.new(x,y,z)
    end
    local oldCleanup=API.Cleanup
    API.Cleanup=function()
        ElectroMovement.Release(farmContext)
        releaseElectro()
        if oldCleanup then oldCleanup() end
        API.EndBringRound()
        if ScriptStorage.Connections then
            for _,c in ScriptStorage.Connections.LocalPlayer do pcall(function() c:Disconnect() end) end
            for _,c in ScriptStorage.Connections do if typeof(c)=="RBXScriptConnection" then pcall(function() c:Disconnect() end) end end
        end
    end
    local lastBring=-math.huge
    function CombatController.Grab(name)
        if os.clock()-lastBring<.15 then return end
        local root=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not round or round.name~=name or not API.ActivityAllowed() or not root or not CombatController.GRAB then return end
        local center=round.anchor
        if (root.Position-center).Magnitude>110 then return end
        lastBring=os.clock()
        pcall(sethiddenproperty,LocalPlayer,"SimulationRadius",math.huge)
        local owned,extras,unowned,failed,gathered,spread=0,0,0,0,0,0
        local extrasGathered=0
        for _,mob in workspace.Enemies:GetChildren() do
            local h=mob:FindFirstChildOfClass("Humanoid")
            local r=mob:FindFirstChild("HumanoidRootPart")
            if CanFarmMob(mob) and (round.includeBosses or not mob:GetAttribute("IsBoss")) and h and h.Health>0 and r
                and API.IsRoundMob(mob) then
                if not isnetworkowner(r) then
                    unowned+=1
                    continue
                end
                local row=ownedMobs[r] or {collide=r.CanCollide,origin=mobOrigin(r),returns=0}
                r:SetAttribute("Kaitun3TNOrigin",row.origin)
                ownedMobs[r]=row
                -- A server correction only excludes this NPC temporarily.
                if row.retryAt and os.clock()>=row.retryAt then
                    row.returns=0; row.released=false; row.command=nil
                    row.lastReturn=nil; row.retryAt=nil
                end
                if row.returns<3 and row.command and (r.Position-row.command).Magnitude>30
                    and (r.Position-row.origin).Magnitude<15 and os.clock()-(row.lastReturn or -math.huge)>1 then
                    row.returns+=1; row.lastReturn=os.clock()
                end
                if row.returns>=3 then
                    failed+=1
                    if not row.released then
                        row.released=true; row.retryAt=os.clock()+30
                        ReleaseMob(r,row)
                    end
                    continue
                end
                for _,part in mob:GetDescendants() do
                    if part:IsA("BasePart") then RememberCollision(part); part.CanCollide=false end
                end
                if not row.walkSpeed then row.walkSpeed=h.WalkSpeed; row.jumpPower=h.JumpPower; row.autoRotate=h.AutoRotate end
                h.WalkSpeed=0; h.JumpPower=0; h.AutoRotate=false
                r.AssemblyLinearVelocity=Vector3.zero
                local velocity=r:FindFirstChild("FarmingVelocity") or Instance.new("BodyVelocity")
                velocity.Name="FarmingVelocity"; velocity.MaxForce=Vector3.new(math.huge,math.huge,math.huge)
                velocity.Velocity=Vector3.zero; velocity.Parent=r
                local destination=center
                spread=math.max(spread,(destination-center).Magnitude)
                local delta=destination-r.Position
                local nextPosition=delta.Magnitude>55 and r.Position+delta.Unit*55 or destination
                r.CFrame=CFrame.new(nextPosition); row.command=nextPosition
                owned+=1
                local inReach=(r.Position-root.Position).Magnitude<=65
                if inReach then gathered+=1 end
                if mob.Name~=name then
                    extras+=1
                    if inReach then
                        extrasGathered+=1
                    end
                end
            end
        end
        API.Metrics.Bring={name=name,radius=round.radius,leash=round.radius,owned=owned,quest=owned-extras,extras=extras,extrasGathered=extrasGathered,unowned=unowned,skipped=failed,gathered=gathered,spread=spread}
    end
    -- Do not pick a single-target boss quest as the fallback farming quest.
    local farmQuest=require(game.ReplicatedStorage.Quests)
    local function forcedCamp()
        return SeaIndex==1 and LocalPlayer.Data.Level.Value<Config.StartMarineFortressUntil and "Chief Petty Officer"
    end
    local guideData=require(game.ReplicatedStorage.GuideModule.GuideData).Data
    local nativeNet=game.ReplicatedStorage.Modules.Net
    local itemChange=nativeNet:FindFirstChild("RE/OnItemValueChanged")
    if itemChange then
        Track(itemChange.OnClientEvent:Connect(function(rows)
            for _,row in type(rows)=="table" and rows or {} do
                local definition=itemDefinitions[row.ItemId]
                local name=definition and definition.Id.StorageKey
                if name and row.Key=="Mastery" and table.find(MeleesTable,name) then
                    ScriptStorage.Melees[name]=row.Value
                end
            end
        end))
    end
    task.spawn(function()
        while Running() do
            pcall(RefreshInventory)
            task.wait(10)
        end
    end)
    function J.GetCurrentClaimQuest()
        return QuestState.Read(guideData.QuestData)
    end
    Track(Remotes.QuestUpdate.OnClientEvent:Connect(function(data)
        if not data then pcall(function() J:RefreshQuest(); J:MarkAsCompleted() end) end
    end))
    local function nearestQuestNpc(id,index,fallback)
        local root=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not root then return fallback end
        local quest=farmQuest[id] and farmQuest[id][index]
        local level=quest and quest.LevelReq
        local spawns={}
        for name in quest and quest.Task or {} do
            for _,spawn in ScriptStorage.MobRegions[name] or {} do table.insert(spawns,spawn) end
        end
        local rows={}
        for part,info in require(game.ReplicatedStorage.GuideModule).Data.NPCList do
            if info.InternalQuestName==id and typeof(part)=="Instance" then
                local r=part:IsA("BasePart") and part or part:FindFirstChild("HumanoidRootPart")
                if r and (not level or table.find(info.Levels or {},level)) then
                    local distance,farm=Support.QuestNpcDistance(r.Position,spawns,root.Position)
                    table.insert(rows,{id=id,level=level,distance=distance,playerDistance=(r.Position-root.Position).Magnitude,
                        farm=farm,cf=r.CFrame,name=info.NPCName})
                end
            end
        end
        local best=Support.NearestQuestGiver(rows,id,level)
        if best then
            return best.cf
        end
        return fallback
    end
    function J.GetCurrentQuest(self)
        local level=LocalPlayer.Data.Level.Value
        local forced=forcedCamp()
        if forced then
            local best,bestId,bestIndex
            for id,rows in farmQuest do
                if not self.BlacklistedQuestIds[id] then
                    for index,row in rows do
                        if type(row)=="table" and row.Task and (row.Task[forced] or 0)>1
                            and row.LevelReq<=level and (not best or row.LevelReq>best.LevelReq) then
                            best,bestId,bestIndex=row,id,index
                        end
                    end
                end
            end
            if best then
                local npc=nearestQuestNpc(bestId,bestIndex,nil)
                if npc then return forced,npc,bestId,bestIndex,best.Name end
            end
            return forced,nil,nil,nil,forced
        end
        local rows=self.CurrentQuests
        if not rows[1] then return end
        local index=rows[self.CurrentLevel] and rows[self.CurrentLevel].LevelReq<=level and self.CurrentLevel or 1
        index=Support.FarmQuestIndex(self.CurrentQuests,index,LocalPlayer.Data.Level.Value)
        local row=rows[index]
        local name=next(row.Task)
        local id=self.CurrentQuestId
        API.Metrics.SelectedCamp={name=name,id=id,index=index}
        return name,nearestQuestNpc(id,index,self.CurrentNpc),id,index,row.Name
    end
    FunctionsHandler.ElectroQuest:Register()
    FunctionsHandler.ElectroQuest:RegisterMethod("Refresh",function()
        if SeaIndex~=1 or LocalPlayer.Data.Level.Value<150 or API.ElectroUnlocked
            or not ScriptStorage.Backpack["Black Leg"] or os.clock()-lastElectroTry<120 then return end
        return LocalPlayer:GetAttribute("CurrentLocation")=="Skylands"
    end)
    FunctionsHandler.ElectroQuest:RegisterMethod("Start",RunElectro)
    FunctionsHandler.SecondSeaPuzzle:RegisterMethod('Refresh', function()
        if ScriptStorage.PlayerData.Level < 700 or SeaIndex ~= 1 then return end
        local k = Remotes.CommF_:InvokeServer('DressrosaQuestProgress')
        if type(k)~="table" then return end
        local Result
        if not k.TalkedDetective then Result = 1
        elseif not k.KilledIceBoss then
            Result = 2
        else
            Result = 3
        end
        FunctionsHandler.SecondSeaPuzzle:Set("CurrentProgressLevel", Result)
        FunctionsHandler.SecondSeaPuzzle:Set('LastestRefreshSenque', os.time())
        return Result
    end)
    FunctionsHandler.SecondSeaPuzzle:RegisterMethod("Start", function()
        local k, h = FunctionsHandler.SecondSeaPuzzle:Get('CurrentProgressLevel'), FunctionsHandler.SecondSeaPuzzle:Get('LastestRefreshSenque')
        FunctionsHandler.SecondSeaPuzzle:Set('CurrentProgressLevel', nil)
        if not k then
            FunctionsHandler.SecondSeaPuzzle.Methods.Refresh:Call()
            return FunctionsHandler.SecondSeaPuzzle.Methods.Start:Call()
        elseif k == 1 then
            SetTask('MainTask', "Auto Second Sea - Talk To Detective")
            Remotes.CommF_:InvokeServer('DressrosaQuestProgress', 'Detective')
        elseif k == 2 then
            SetTask('MainTask', 'Auto Second Sea - Using Key')
            Remotes.CommF_:InvokeServer('DressrosaQuestProgress', 'UseKey')
            SetTask("MainTask", "Auto Second Sea - Defeating Ice Admiral")
            CombatController.Attack("Ice Admiral")
        elseif k == 3 then
            SetTask('MainTask', 'Sea Travel | Teleporting to Second Sea')
            Remotes.CommF_:InvokeServer('TravelDressrosa')
        end
    end)
    FunctionsHandler.ThirdSeaPuzzle:RegisterMethod("Start",function(stage)
        if stage=="travel" then
            SetTask("MainTask","Sea 3 unlock | Traveling")
            Remotes.CommF_:InvokeServer("TravelZou")
            return
        end
        SetTask("MainTask","Sea 3 unlock | rip_indra")
        Remotes.CommF_:InvokeServer("ZQuestProgress","Begin")
        local deadline=os.clock()+150
        while Running() and os.clock()<deadline do
            local state=Remotes.CommF_:InvokeServer("ZQuestProgress","Check")
            if state==1 or state==2 then
                Remotes.CommF_:InvokeServer("TravelZou")
                return
            end
            if ScriptStorage.Enemies.rip_indra then
                CombatController.Attack("rip_indra")
            else
                task.wait(1)
            end
        end

    end)

    local keyRetries={}
    API.ProgressKeys={}
    for _,name in {"Library Key","Water Key","Hidden Key"} do
        local saved=Storage:Get("KeyReceipt:"..name)
        if type(saved)=="table" and saved.confirmed==true then API.ProgressKeys[name]=saved end
    end
    local function libraryDoor()
        local castle=workspace.Map:FindFirstChild("IceCastle")
        local hall=castle and castle:FindFirstChild("Hall")
        local door=hall and hall:FindFirstChild("LibraryDoor")
        if not door then return nil,"unknown" end
        return door,door:FindFirstChild("PhoeyuDoor") and "locked" or "door absent"
    end
    function PendingProgressKey()
        if SeaIndex~=2 then return nil end
        local _,state=libraryDoor()
        for _,name in {"Library Key","Water Key","Hidden Key"} do
            local row=API.ProgressKeys[name]
            if ScriptStorage.Tools[name] and os.clock()>=(keyRetries[name] or 0)
                and not (row and row.confirmed)
                and not (name=="Hidden Key" and (ScriptStorage.Backpack.Rengoku or row and row.confirmed))
                and not (row and row.attempted and name=="Library Key" and state=="door absent") then
                return name
            end
        end
    end
    local function KeyMustStay()
        local backpack=LocalPlayer:FindFirstChildOfClass("Backpack")
        local char=LocalPlayer.Character
        for _,name in {"Water Key","Library Key","Fire Essence"} do
            if (backpack and backpack:FindFirstChild(name) or char and char:FindFirstChild(name))
                and not (API.ProgressKeys[name] and API.ProgressKeys[name].confirmed) then return true end
        end
        if API.CurrentTask=="UtillyItemsActivitation" and ScriptStorage.Tools["Hidden Key"] and not ScriptStorage.Backpack.Rengoku then return true end
        if ScriptStorage.Tools["Library Key"] then
            local _,state=libraryDoor()
            local row=API.ProgressKeys["Library Key"]
            if row and row.confirmed then return false end
            return not row or not row.attempted or state~="door absent"
        end
        return false
    end
    function UseProgressKey(name)
        if not ScriptStorage.Tools[name] then return end
        if os.clock()<(keyRetries[name] or 0) then return end
        if name=="Library Key" then
            local door,state=libraryDoor()
            if not door then
                API.ProgressKeys[name]={status="door not streamed; retry",confirmed=false}
                keyRetries[name]=os.clock()+10
                return
            end
            local locked=door:FindFirstChild("PhoeyuDoor")
            local target=locked or door
            local cf=target:IsA("BasePart") and target.CFrame or target:GetPivot()
            SetTask("MainTask","Library Key | Approaching library door")
            TweenController.Create(cf+Vector3.new(0,3,0))
            if CaculateDistance(cf)>12 then return end
        end
        SetTask("MainTask",name.." | Submitting key")
        local character=LocalPlayer.Character
        FunctionsHandler.LocalPlayerController.Methods.EquipTool:Call(name)
        local response
        if name=="Water Key" then
            task.wait(.25)
            if not character or LocalPlayer.Character~=character or not character:FindFirstChild(name) then
                keyRetries[name]=os.clock()+3
                return
            end
            response=Remotes.CommF_:InvokeServer("BuySharkmanKarate",true)
        else response=Remotes.CommF_:InvokeServer(name=="Library Key" and "OpenLibrary" or "OpenRengoku") end
        task.wait(.5)
        nextInventoryRefresh=0
        pcall(RefreshInventory)
        local _,state=libraryDoor()
        local human=character and character:FindFirstChildOfClass("Humanoid")
        local consumed=LocalPlayer.Character==character and human and human.Health>0
            and LocalPlayer:FindFirstChild("Backpack")~=nil and ScriptStorage.Tools[name]==nil
        local confirmed=name=="Water Key" and (consumed==true or Support.SharkmanUnlocked(response) or ScriptStorage.Backpack["Sharkman Karate"]~=nil)
            or name=="Hidden Key" and ScriptStorage.Backpack.Rengoku~=nil
            or name=="Library Key" and Support.LibraryConfirmed(response,consumed,state)
        local row={at=os.time(),attempted=true,response=tostring(response),consumed=consumed,
            responseType=typeof(response),confirmed=confirmed,
            status=confirmed and "confirmed" or "not confirmed; inspect response",door=state}
        API.ProgressKeys[name]=row
        Storage:Set("KeyReceipt:"..name,row);Storage:Save()

        keyRetries[name]=os.clock()+30
    end
    local unlockQueryAt=0
    API.Sea2Unlocks={death=false,sharkman=false,ready=false,status="waiting for server receipts"}
    function Sea2UnlocksReady()
        if SeaIndex~=2 then return true end
        local result=API.Sea2Unlocks
        local library=API.ProgressKeys["Library Key"]
        local water=API.ProgressKeys["Water Key"]
        local death=ScriptStorage.Backpack["Death Step"]~=nil or (library and library.confirmed==true) or result.death==true
        local shark=ScriptStorage.Backpack["Sharkman Karate"]~=nil or (water and water.confirmed==true) or result.sharkman==true
        if not (death and shark) and os.clock()>=unlockQueryAt then
            unlockQueryAt=os.clock()+15
            if not death then
                local response=Remotes.CommF_:InvokeServer("BuyDeathStep",true)
                result.deathResponse=tostring(response);death=response==1
            end
            if not shark then
                local response=Remotes.CommF_:InvokeServer("BuySharkmanKarate",true)
                result.sharkmanResponse=tostring(response);shark=Support.SharkmanUnlocked(response)
                if shark then
                    local row={at=os.time(),response=tostring(response),responseType=typeof(response),confirmed=true,
                        status=response==3 and "key unlocked; mastery pending" or "native learning dialogue available",
                        proof="BuySharkmanKarate(true) mapped by native SharkmanTeacher dialogue"}
                    API.ProgressKeys["Water Key"]=row
                    Storage:Set("KeyReceipt:Water Key",row);Storage:Save()
                end
            end
        end
        result.death=death==true;result.sharkman=shark==true
        result.ready=Support.Sea2Ready(death,shark)
        result.status=result.ready and "unlocked; original purchase order continues" or
            (not death and "Sea3 blocked: unlock library / Death Step" or "Sea3 blocked: unlock Sharkman with Water Key")
        if not result.ready then SetTask("SubTask",result.status) end
        return result.ready
    end
    local nextSea3Check,sea3Stage=0,nil
    FunctionsHandler.ThirdSeaPuzzle:RegisterMethod("Refresh",function()
        if SeaIndex~=2 or ScriptStorage.PlayerData.Level<1500 or not Sea2UnlocksReady() then return end
        if os.clock()>=nextSea3Check then
            nextSea3Check=os.clock()+3
            local state=Remotes.CommF_:InvokeServer("ZQuestProgress","Check")
            sea3Stage=state==0 and "encounter" or (state==1 or state==2) and "travel" or nil
            API.NeedsDonSwan=not sea3Stage and FunctionsHandler.Trevor:Get("IsCompleted")==true
        end
        return sea3Stage
    end)
    Sea2UnlocksReady()
    API.Phase = "initializing"
    local complete=ElectroProgress.Read(ElectroQuest.Id)
    if complete==true then
        API.ElectroUnlocked=true
        API.ElectroReward=Storage:Get("ElectroRewardReceipt") or {objectiveConfirmed=true,status="server objective complete; previous reward receipt unavailable"}
    end
    local function QuestIdentity(data)
        local info=data and data.Info
        if not info then return nil end
        local id=data.InternalQuestName or data.QuestId or data.QuestID or data.QuestName or info.InternalQuestName
        local index=data.QuestIndex or data.QuestLevel or info.QuestIndex
        if not index and id and info.LevelReq then
            for candidate,row in farmQuest[id] or {} do
                if row.LevelReq==info.LevelReq then index=candidate;break end
            end
        end
        return id,index
    end
    local function ClaimMatches(id, index, held)
        local data = guideData.QuestData
        if not data or not data.Info then return nil end
        if held and held.UID and data.UID and held.UID~=data.UID then return false end
        local actualId,actualIndex=QuestIdentity(data)
        if id and actualId and actualId~=id or index and actualIndex and actualIndex~=index then return false end
        local expected=farmQuest[id] and farmQuest[id][index] or held and held.Info
        if not expected then return false end
        local tasks=data.Info.Task
        if type(tasks)=="table" and type(expected.Task)=="table" then
            for name,count in expected.Task do if tasks[name]~=count then return false end end
            for name,count in tasks do if expected.Task[name]~=count then return false end end
            return true
        end
        return id~=nil and index~=nil and actualId==id and actualIndex==index or data.Info==expected
    end
    local nextQuestClaim=0
    local function QuestTravelBudget(npc)
        return math.clamp(CaculateDistance(npc)/math.max(1,Config.TweenSpeed)+15,30,330)
    end
    local alternateCamp,nextAlternateCamp=nil,0
    local function FarmAlternateCamp(name,id,held,questDone)
        if API.CurrentTask~="LevelFarm" and API.CurrentTask~="BonesStock" then return false end
        if alternateCamp and (alternateCamp.uid~=held.UID or alternateCamp.questMob~=name or alternateCamp.id~=id) then alternateCamp=nil end
        local mobs
        if not alternateCamp then
            if os.clock()<nextAlternateCamp then return false end
            local home,homeDistance=nil,160
            for _,spawn in ScriptStorage.MobRegions[name] or {} do
                local distance=CaculateDistance(spawn.Position)
                if distance<homeDistance then home,homeDistance=spawn.Position,distance end
            end
            if not home then return false end
            mobs=workspace.Enemies:GetChildren()
            local seed,nearest=nil,750
            for _,mob in mobs do
                if not CanFarmMob(mob) then continue end
                if mob.Name==name then return false end
                if not (API.IsElitePirate and API.IsElitePirate(mob)) and (mob:GetAttribute("KaitunSkipUntil") or 0)<=os.clock() then
                    local distance=CaculateDistance(mob.HumanoidRootPart.Position)
                    if distance<nearest then seed,nearest=mob,distance end
                end
            end
            if not seed then return false end
            local origin=seed.HumanoidRootPart.Position
            local points={}
            for _,mob in mobs do
                if mob.Name~=seed.Name or not CanFarmMob(mob) then continue end
                local p=mob.HumanoidRootPart.Position
                if (p-origin).Magnitude<=2*Config.BringDistance then
                    table.insert(points,{x=p.X,y=p.Y,z=p.Z,primary=mob==seed})
                end
            end
            local x,y,z=Support.CampCenter(points,{x=origin.X,y=origin.Y,z=origin.Z},2*Config.BringDistance,Config.BringDistance)
            local center=Vector3.new(x,y,z)
            local count=0
            for _,mob in mobs do
                if CanFarmMob(mob) and IsBringMobInRange(mob,center) then count+=1 end
            end
            alternateCamp={id=id,uid=held.UID,questMob=name,name=seed.Name,home=home,center=center,expires=os.clock()+55}
        end
        local camp=alternateCamp
        if not camp.returning then
            local target,nearest,alive=nil,math.huge,0
            for _,mob in mobs or workspace.Enemies:GetChildren() do
                if not CanFarmMob(mob) or not IsBringMobInRange(mob,camp.center) then continue end
                alive+=1
                if (mob:GetAttribute("KaitunSkipUntil") or 0)>os.clock() then continue end
                local score=(mob.HumanoidRootPart.Position-camp.center).Magnitude
                    + (mob.Name==camp.name and 0 or Config.BringDistance)
                if score<nearest then target,nearest=mob,score end
            end
            if target and os.clock()<camp.expires then
                camp.target=target
                SetTask("MainTask","Level Farming | "..target.Name.." | Alternate camp")
                CombatController.Attack(target.Name,nil,nil,function()
                    local quest=guideData.QuestData
                    return os.clock()>=camp.expires or not quest or quest.UID~=camp.uid or questDone()
                end,camp,true)
                return true
            end
            camp.returning=true
        end
        if CaculateDistance(camp.home)>65 then
            SetTask("MainTask","Level Farming | "..name.." | Returning to quest camp")
            TweenController.Create(camp.home+Vector3.new(0,Config.FightHeight,0))
            return true
        end
        alternateCamp=nil;nextAlternateCamp=os.clock()+8
        return false
    end
    FarmLevelQuest=function(selection,stop)
        local held=guideData.QuestData
        if held and held.Info then
            API.QuestApproach=nil
            local id,index=QuestIdentity(held)
            local name,hasFarmMob
            for mob,count in held.Info.Task or {} do
                if regularFarmNames[mob] then
                    hasFarmMob=true
                    if (held.Progress and held.Progress[mob] or 0)<count then name=mob;break end
                end
            end
            if not name then
                alternateCamp=nil
                if not hasFarmMob and next(held.Info.Task or {}) and os.clock()>=nextQuestClaim then
                    nextQuestClaim=os.clock()+3
                    J.AbandonQuest()
                end
                return
            end
            if API.TrackMaterialQuest then API.TrackMaterialQuest(name,id,index) end
            API.Metrics.SelectedCamp={name=name,id=id,index=index}
            local function questDone()
                if stop and stop() then return true end
                if ClaimMatches(id,index,held)~=true then return true end
                local data=guideData.QuestData
                return data.Progress and (data.Progress[name] or 0)>=held.Info.Task[name]
            end
            if questDone() then alternateCamp=nil;return end
            if FarmAlternateCamp(name,id,held,questDone) then return end
            SetTask("MainTask","Level Farming | "..name.." | Defeating Enemies")
            CombatController.Attack(name,nil,nil,questDone,nil,true)
            return
        end
        alternateCamp=nil
        if os.clock()<nextQuestClaim then return end
        local approach=API.QuestApproach
        if not approach then
            selection=selection or API.MaterialQuest and API.MaterialQuest()
            local name,npc,id,index
            if selection then name,npc,id,index=selection.name,selection.npc,selection.id,selection.index
            else name,npc,id,index=J:GetCurrentQuest() end
            if not name or not id or not index or not npc then
                if selection then
                    local spawn=ScriptStorage.MobRegions[name] and ScriptStorage.MobRegions[name][1]
                    if spawn then TweenController.Create(spawn+Vector3.new(0,25,0)) end
                else J:RefreshQuest() end
                return
            end
            local travelBudget=QuestTravelBudget(npc)
            approach={name=name,npc=npc,id=id,index=index,expires=os.clock()+travelBudget,owner=API.CurrentTask}
            API.QuestApproach=approach
        end
        if os.clock()>=approach.expires then
            API.QuestApproach=nil; nextQuestClaim=os.clock()+3
            return
        end
        SetTask("MainTask","Level Farming | "..approach.name.." | Claiming Quest")
        TweenController.Create(approach.npc+Vector3.new(0,5,3))
        if CaculateDistance(approach.npc)>10 then return end
        local deadline=os.clock()+3
        nextQuestClaim=deadline+3
        local worker=task.spawn(function()
            pcall(J.StartQuest,approach.id,approach.index)
        end)
        while os.clock()<deadline and not (guideData.QuestData and guideData.QuestData.Info) do task.wait(.1) end
        if worker then pcall(task.cancel,worker) end
        API.QuestApproach=nil
        nextQuestClaim=guideData.QuestData and guideData.QuestData.Info and 0 or os.clock()+3
    end
    local lastRandom, fruitBusy, lastBuso = -math.huge, false, -math.huge
    local gachaKey="FruitGachaAt:"..LocalPlayer.UserId
    local lastPurchase=Storage:Get(gachaKey) or 0
    local function randomReady()
        return Config.AutoRandomFruit and LocalPlayer.Data.Level.Value>=50
            and os.clock()-lastRandom>=60 and os.time()-lastPurchase>=7200
    end
    local function CheckBuso()
        local char=LocalPlayer.Character
        if not char or os.clock()-lastBuso<3 then return end
        local function enabled()
            return char:GetAttribute("BusoEnabled")==true or char:FindFirstChild("HasBuso")~=nil
        end
        local function owned()
            return enabled() or char:HasTag("Buso") or LocalPlayer:HasTag("Buso")
        end
        lastBuso=os.clock()
        if not owned() and LocalPlayer.Data.Beli.Value>=25000 then
            Remotes.CommF_:InvokeServer("BuyHaki","Buso")
        end
        if LocalPlayer.Character~=char then return end
        if owned() and not enabled() then Remotes.CommF_:InvokeServer("Buso") end
    end
    local storeAttempts=setmetatable({},{__mode="k"})
    local function StoreFruit(probe)
        if not Config.AutoStoreFruit then return end
        for _, container in {LocalPlayer:FindFirstChild("Backpack"), LocalPlayer.Character} do
            for _, tool in container and container:GetChildren() or {} do
                local original=tool:IsA("Tool") and tool:GetAttribute("OriginalName")
                if original and tool:FindFirstChild("Handle") and not table.find(ScriptStorage.IgnoreStoreFruits,original) then
                    local stored=ScriptStorage.Backpack[original]
                    local count=stored and stored.Count or 0
                    local attempt=storeAttempts[tool]
                    if attempt and attempt.count==count and os.clock()<attempt.retryAt then continue end
                    if probe then return true end
                    attempt={count=count,retryAt=os.clock()+60}
                    storeAttempts[tool]=attempt
                    local response=Remotes.CommF_:InvokeServer("StoreFruit",original,tool)
                    local full=response==1 and tool.Parent==container
                    if full then attempt.retryAt=math.huge end
                end
            end
        end
    end
    local function supportReady()
        return not fruitBusy and StoreFruit(true)
    end
    FunctionsHandler.SupportPriority:Register()
    FunctionsHandler.SupportPriority:RegisterMethod("Refresh", supportReady)
    FunctionsHandler.SupportPriority:RegisterMethod("Start", function()
        if fruitBusy then return end
        fruitBusy = true
        local ok, issue = pcall(StoreFruit)
        fruitBusy = false
    end)
    local function RollRewards()
        if not API.BootComplete or not API.ActivityAllowed() or API.CurrentTask=="MeleesController" or API.MeleeBuying
            or API.RaidStarting and API.Raid and API.Raid.status=="buying chip" then return end
        local bones=API.BonesRollReady and API.BonesRollReady()
        local fruit=randomReady()
        if not bones and not fruit then return end
        API.RewardRollBusy=true
        local ok,issue=pcall(function()
            if bones then API.RollBones() end
            if fruit and API.ActivityAllowed() then
                lastRandom=os.clock()
                if Support.Random(Config,API,LocalPlayer,0) then
                    lastPurchase=os.time()
                    Storage:Set(gachaKey,lastPurchase);Storage:Save()

                end
            end
        end)
        API.RewardRollBusy=nil
    end
    FunctionsHandler.FactoryEvent:Register()
    FunctionsHandler.FactoryEvent:RegisterMethod("Refresh",function()
        local core = SeaIndex == 2 and ScriptStorage.Enemies.Core
        return CanFarmMob(core) and core
    end)
    FunctionsHandler.FactoryEvent:RegisterMethod("Start",function(core)
        if not CanFarmMob(core) then return end
        SetTask("MainTask","Factory | Defeating Core")
        CombatController.Attack("Core")
    end)
    do
        local raid=FunctionsHandler.PirateRaid
        local center=Vector3.new(-5543.5327148438,313.80062866211,-2964.2585449219)
        local expires,emptySince=0,nil
        local function finish(reason)
            expires=0;emptySince=nil

        end
        local function notice(label)
            if not label:IsA("TextLabel") or label.Name~="Notification" then return end
            local message=string.lower(label.Text:gsub("<[^>]+>",""))
            if message:find("pirates are raiding castle",1,true) or message:find("pirates have been spotted approaching",1,true) then
                expires=os.clock()+120;emptySince=nil
            elseif expires>0 and (message:find("pirates have stopped raiding",1,true)
                or message:find("pirates have been defeated",1,true) or message:find("for dealing the final blow",1,true)) then
                finish("end notice")
            end
        end
        if SeaIndex==3 then
            task.spawn(function()
                local gui=LocalPlayer:WaitForChild("PlayerGui",15)
                local notifications=gui and gui:WaitForChild("Notifications",15)
                local stack=notifications and notifications:WaitForChild("NotificationStack",15)
                if not stack then return end
                Track(stack.ChildAdded:Connect(function(label) task.delay(0,notice,label) end))
                for _,label in stack:GetChildren() do notice(label) end
            end)
        end
        local function eligible(mob)
            return CanFarmMob(mob) and not mob:GetAttribute("IsBoss") and (mob.HumanoidRootPart.Position-center).Magnitude<500
        end
        raid:RegisterMethod("Refresh",function()
            if expires==0 then return end
            if os.clock()>=expires then finish("timeout");return end
            return true
        end)
        raid:RegisterMethod("Start",function()
            if not raid.Methods.Refresh:Call() then return end
            if CaculateDistance(center)>500 then

                TweenController.Create(center)
                return
            end
            for _,mob in workspace.Enemies:GetChildren() do
                if eligible(mob) then
                    emptySince=nil

                    CombatController.Attack(mob,nil,nil,function()
                        return expires==0 or os.clock()>=expires or not eligible(mob)
                    end)
                    return
                end
            end
            TweenController.Create(center)
            emptySince=emptySince or os.clock()
            if os.clock()-emptySince>=25 then finish("no targets at Castle") end
        end)
    end
    local function NeedBossKey()
        if SeaIndex~=2 or KeyMustStay() then return end
        local level=LocalPlayer.Data.Level.Value
        local unlocks=API.Sea2Unlocks
        local frost,forgotten=farmQuest.FrostQuest,farmQuest.ForgottenQuest
        if not unlocks.death and frost and level>=frost[1].LevelReq then return "Awakened Ice Admiral" end
        if not unlocks.sharkman and forgotten and level>=forgotten[1].LevelReq then return "Tide Keeper" end
        if level>=1500 and unlocks.death and unlocks.sharkman and API.NeedsDonSwan then return "Don Swan" end
    end
    FunctionsHandler.BossKeyHunt:Register()
    FunctionsHandler.BossKeyHunt:RegisterMethod("Refresh",function()
        if not NeedBossKey() or CanFarmMob(ScriptStorage.Enemies.Core) then return end
        local held=guideData.QuestData
        for name,count in held and held.Info and held.Info.Task or {} do
            if regularFarmNames[name] and (held.Progress and held.Progress[name] or 0)<count then return end
        end
        Sea2UnlocksReady()
        return NeedBossKey()
    end)
    FunctionsHandler.BossKeyHunt:RegisterMethod("Start",function(name)
        local route=name=="Don Swan" and "Sea 3 unlock" or "Sea 2 key hunt"
        local spawn=ScriptStorage.MobRegions[name] and ScriptStorage.MobRegions[name][1]
        if not spawn then
            SetTask("MainTask",route.." | missing spawn for "..name)
            task.wait(3)
            return
        end
        if CaculateDistance(spawn)>100 then
            SetTask("MainTask",route.." | approaching "..name)
            TweenController.Create(spawn+Vector3.new(0,25,0))
            return
        end
        local boss=workspace.Enemies:FindFirstChild(name)
        if CanFarmMob(boss) then
            SetTask("MainTask",route.." | defeating "..name)
            CombatController.Attack(name)
            if CanFarmMob(boss) then return end
        else
            SetTask("MainTask",route.." | checking spawn for "..name)
        end
        task.wait(3)
        if CaculateDistance(spawn)>100 or CanFarmMob(workspace.Enemies:FindFirstChild(name)) then return end
        if name=="Don Swan" and FunctionsHandler.ThirdSeaPuzzle.Methods.Refresh:Call() then return end
        if NeedBossKey()==name then
            API.EndActivity()
            API.RequestHop("boss key")
        end
    end)
    local eventOrder={"FactoryEvent","PirateRaid","CollectDrops","SupportPriority"}
    local function ReadyEvent(before,check)
        for _,name in eventOrder do
            if name==before then break end
            if check then
                if check(name) then return name end
            elseif FunctionsHandler[name].Methods.Refresh:Call() then
                return name
            end
        end
    end
    TasksOrder={"UtillyItemsActivitation","SecondSeaPuzzle","ColosseumPuzzle","Trevor","ThirdSeaPuzzle"}
    for _,name in eventOrder do table.insert(TasksOrder,name) end
    for _,name in {"BossKeyHunt","ElectroQuest","RaidController","LevelFarm"} do table.insert(TasksOrder,name) end
    function ShouldYieldForEvent(active)
        if API.HopInProgress then return true end
        if API.IsRaidBusy and API.IsRaidBusy() then return active~="RaidController" end
        if ReadyEvent(active) then return true end
        return active~="UtillyItemsActivitation" and active~="ElectroQuest" and not table.find(eventOrder,active) and PendingProgressKey()~=nil
    end
    local savedCleanup = API.Cleanup
    local function ReleaseFarm(reason)
        dessertCamp=nil
        local keepHold=reason=="activity changed" and Running() and not API.Paused
            and not API.HopInProgress and API.CurrentTask~="ElectroQuest"
        API.QuestApproach=nil
        API.EndFruitApproach("activity changed")
        if API.ClearMove then API.ClearMove(keepHold) else farmDestination=nil end
        if not keepHold then ElectroMovement.Release(farmContext) end
        releaseElectro()
        API.EndBringRound()
        for part,value in collisions do if part.Parent then part.CanCollide=value end end
        _G.FastAttack=nil
    end
    API.Pause=function()
        API.Paused=true; API.InvalidateActivity("pause")
        if API.CancelRaid then API.CancelRaid() end
    end
    API.CancelFarm=ReleaseFarm
    API.Resume=function() if Running() then API.Paused=false end end
    API.Cleanup=function()
        ReleaseFarm()
        if savedCleanup then savedCleanup() end
    end
    task.spawn(function()
        while Running() do
            if not API.Paused then
                API.BindActivity()
                local ok,issue=pcall(function()
                    if LocalPlayer.Data.Points.Value>0 then AddPoint() end
                    if API.BootComplete or API.IsRaidActive and API.IsRaidActive() then CheckBuso() end
                end)
                API.EndActivity()
                RollRewards()
            end
            task.wait(2)
        end
    end)
    ServerHop.Start({API=API,Config=Config,task=task,Running=Running,Track=Track,Invoke=Invoke,KeyPending=KeyMustStay,NeedBossKey=NeedBossKey})
    do
        local names={Diablo=true,Deandre=true,Urban=true}
        local key="EliteOnce"
        local receipt=Storage:Get(key)
        if type(receipt)~="table" or type(receipt.baseline)~="number" then receipt=nil end
        local state={status="waiting for Sea 3",completed=receipt and receipt.completed==true or false}
        function API.IsElitePirate(mob)
            return mob~=nil and names[mob.Name]==true
        end
        local nextProbe,nextAttempt=0,0
        local target
        local function save()
            Storage:Set(key,receipt)
            Storage:Save()
        end
        local function checkProgress()
            local progress=tonumber(Remotes.CommF_:InvokeServer("EliteHunter","Progress"))
            nextProbe=os.clock()+5
            if not progress or progress<0 then return end
            if receipt and progress>receipt.baseline then
                receipt.completed=true
                receipt.progress=progress
                save()
                state.completed=true
                state.status="native Elite progress confirmed"
            end
            return progress
        end
        local function assignedElite(held)
            local tasks=held and held.Info and held.Info.Task
            if type(tasks)~="table" then return end
            for name,count in tasks do
                if names[name] and count==1 then return name end
            end
        end
        local function liveElite(name)
            local enemies=workspace:FindFirstChild("Enemies")
            local closest,distance=nil,math.huge
            for _,mob in enemies and enemies:GetChildren() or {} do
                if API.IsElitePirate(mob) and (not name or mob.Name==name) and CanFarmMob(mob) then
                    local delta=CaculateDistance(mob.HumanoidRootPart.Position)
                    if delta<distance then closest,distance=mob,delta end
                end
            end
            return closest
        end
        local function allowed()
            return API.CurrentTask=="EliteOnce" and API.ActivityAllowed() and not ShouldYieldForEvent("EliteOnce")
        end
        local controller=FunctionsHandler.EliteOnce:Register()
        controller:RegisterMethod("Refresh",function()
            if state.completed then state.status="native Elite progress confirmed";return end
            if SeaIndex~=3 or LocalPlayer.Data.Level.Value<1500 or not API.InventoryKnown or API.Paused
                or API.HopInProgress or API.IsRaidBusy and API.IsRaidBusy() then return end
            if receipt and receipt.attackAt and os.clock()>=nextProbe
                and (nextProbe==0 or os.time()-receipt.attackAt<=20) then
                if not checkProgress() or state.completed then return end
            end
            if API.EliteSpeedAccessoryOwned then state.status="Elite accessory already owned";return end
            if os.clock()<nextAttempt then return end
            local held=guideData.QuestData
            local name=assignedElite(held)
            if held and not name or API.QuestApproach then state.status="waiting for active quest to finish";return end
            if not held and receipt and receipt.attackAt and os.time()-receipt.attackAt<8 then
                state.status="waiting for native Elite receipt";return
            end
            target=liveElite(name)
            state.status=target and "live Elite available" or "waiting for live Elite"
            return target~=nil
        end)
        controller:RegisterMethod("Start",function()
            if state.completed or not allowed() or not CanFarmMob(target) then return end
            local progress=checkProgress()
            if not progress or state.completed or not allowed() or not CanFarmMob(target) then return end
            if not receipt then receipt={baseline=progress};save() end
            local held=guideData.QuestData
            if not held then
                Remotes.CommF_:InvokeServer("EliteHunter")
                local deadline=os.clock()+3
                while allowed() and not guideData.QuestData and os.clock()<deadline do task.wait(.1) end
                held=guideData.QuestData
            end
            local name=assignedElite(held)
            local mob=name and liveElite(name)
            if not mob or not allowed() then nextAttempt=os.clock()+10;return end
            receipt.attackAt=os.time()
            save()
            state.status="fighting "..name
            SetTask("MainTask","Elite Once | "..name)
            local deadline=os.clock()+120
            CombatController.Attack(name,nil,nil,function()
                return os.clock()>=deadline or not allowed() or not CanFarmMob(mob)
                    or assignedElite(guideData.QuestData)~=name
            end)
            nextAttempt=os.clock()+6
            if not allowed() then return end
            state.status="waiting for native Elite receipt"
            checkProgress()
        end)
    end

    table.insert(TasksOrder,table.find(TasksOrder,"LevelFarm"),"EliteOnce")
    local function QuestForMobs(names)
        local best
        for id,rows in farmQuest do
            for index,row in rows do
                if type(row)=="table" and row.Task and row.LevelReq and row.LevelReq<=LocalPlayer.Data.Level.Value
                    and (not best or row.LevelReq>best.level) then
                    for name in row.Task do
                        if table.find(names,name) then best={name=name,id=id,index=index,level=row.LevelReq};break end
                    end
                end
            end
        end
        if best then best.npc=nearestQuestNpc(best.id,best.index,nil) end
        return best
    end
    local function inventoryCount(name)
        return (ScriptStorage.Backpack[name] or {}).Count or 0
    end
    local localMaterials={}
    for name,row in GodhumanMaterials do
        if row[2]==SeaIndex then localMaterials[name]=row end
    end
    if SeaIndex==1 then
        localMaterials["Magma Ore"]={GodhumanMaterials["Magma Ore"][1],1,{"Military Soldier","Military Spy"}}
        localMaterials["Fish Tail"]={GodhumanMaterials["Fish Tail"][1],1,{"Fishman Warrior","Fishman Commando"}}
    end
    function API.MissingGodhumanMaterial()
        if not API.InventoryKnown then return end
        for name,row in localMaterials do
            if inventoryCount(name)<row[1] then return name,row end
        end
        for name,row in GodhumanMaterials do
            if inventoryCount(name)<row[1] then return name,row end
        end
    end
    local materialKey="MaterialQuest:"..LocalPlayer.UserId..":"..SeaIndex
    local materialLock=Storage:Get(materialKey)
    if type(materialLock)~="table" or not localMaterials[materialLock.item] then materialLock=nil end
    function API.TrackMaterialQuest(name,id,index)
        if materialLock or not API.InventoryKnown or ScriptStorage.Melees.Godhuman or LocalPlayer.Data.Level.Value<150 then return end
        for item,row in localMaterials do
            if table.find(row[3],name) and inventoryCount(item)<row[1] then
                materialLock={item=item,name=name,id=id,index=index}
                Storage:Set(materialKey,materialLock);Storage:Save()

                return
            end
        end
    end
    function API.MaterialQuest()
        local lock=materialLock
        if not lock or not API.InventoryKnown then return end
        local row=localMaterials[lock.item]
        local count=inventoryCount(lock.item)
        if ScriptStorage.Melees.Godhuman or count>=row[1] then
            materialLock=nil
            Storage:Set(materialKey,nil);Storage:Save()
            return
        end
        if lock.id and lock.index then
            return {name=lock.name,id=lock.id,index=lock.index,npc=nearestQuestNpc(lock.id,lock.index,nil)}
        end
        return QuestForMobs(row[3])
    end
    function API.FarmGodhumanMaterial()
        local name,row=API.MissingGodhumanMaterial()
        if not name then GodHumanFlag=false; return end
        if guideData.QuestData and guideData.QuestData.Info then return FarmLevelQuest() end
        SetTask("MainTask","Godhuman materials | "..name)
        if SeaIndex~=row[2] then return Remotes.CommF_:InvokeServer("Travel"..SeaIndexes[row[2]]) end
        local selection=QuestForMobs(row[3])
        if selection then return FarmLevelQuest(selection) end
    end

    local haunted={"Reborn Skeleton","Living Zombie","Demonic Soul","Possessed Mummy","Posessed Mummy"}
    local bonesKey="BonesFilling:"..LocalPlayer.UserId
    local bonesGoal=2500
    local firstHauntedLevel=farmQuest.HauntedQuest1 and farmQuest.HauntedQuest1[1].LevelReq or math.huge
    local filling=Storage:Get(bonesKey)
    local function UpdateBonesFill(count)
        local nextFill=count<bonesGoal and (filling~=false or count<50)
        if nextFill~=filling then
            filling=nextFill
            Storage:Set(bonesKey,filling); Storage:Save()

        end
        return filling
    end
    local function hasHauntedQuest()
        local q=guideData.QuestData
        if not q or not q.Info then return true end
        for name in q.Info.Task or {} do if table.find(haunted,name) then return true end end
        return false
    end
    FunctionsHandler.BonesStock:Register()
    FunctionsHandler.BonesStock:RegisterMethod("Refresh",function()
        if SeaIndex==3 and LocalPlayer.Data.Level.Value>=firstHauntedLevel and API.InventoryKnown and UpdateBonesFill(inventoryCount("Bones"))
            and not materialLock and hasHauntedQuest() then return QuestForMobs(haunted) end
    end)
    FunctionsHandler.BonesStock:RegisterMethod("Start",function(selection)
        local count=inventoryCount("Bones")
        if not UpdateBonesFill(count) then
            if API.QuestApproach and API.QuestApproach.owner=="BonesStock" then API.QuestApproach=nil end
            return
        end
        if type(selection)~="table" then selection=API.QuestApproach end
        if not selection then return end

        FarmLevelQuest(selection,function() return not UpdateBonesFill(inventoryCount("Bones")) end)
    end)
    local nextBoneCheck=0
    function API.BonesRollReady()
        if SeaIndex~=3 or LocalPlayer.Data.Level.Value<firstHauntedLevel or not API.InventoryKnown then return end
        return os.clock()>=nextBoneCheck and inventoryCount("Bones")>=50
    end
    function API.RollBones()
        nextBoneCheck=os.clock()+30
        local stock,_,state,message=Remotes.CommF_:InvokeServer("Bones","Check")
        local count=tonumber(stock)
        local remaining=tonumber(state)
        if remaining==0 then
            local hours,minutes
            if type(message)=="string" then hours,minutes=message:match("^(%d+):(%d%d)$") end
            local delay=hours and math.max(30,tonumber(hours)*3600+tonumber(minutes)*60) or 60
            nextBoneCheck=os.clock()+delay
            local held=inventoryCount("Bones")
            UpdateBonesFill(held)

            return
        end
        if not remaining or remaining<1 or not count or count<50 or not API.ActivityAllowed() then return end

        UpdateBonesFill(count)
        local fragments=LocalPlayer.Data:FindFirstChild("Fragments")
        local fragmentsBefore=fragments and fragments.Value
        local raid=API.Raid
        local raidStart=raid and raid.lastEvent=="StartTimer" and raid.lastEventAt
        Remotes.CommF_:InvokeServer("Bones","Buy",1,1)
        task.wait(.5)
        nextInventoryRefresh=0
        RefreshInventory()
        if raidStart and fragmentsBefore and API.RecordRaidExternalFragments then
            API.RecordRaidExternalFragments(fragments.Value-fragmentsBefore,raidStart)
        end
        local spent=math.max(0,count-inventoryCount("Bones"))
        if spent>=50 then
            nextBoneCheck=os.clock()+2
        end

    end
    table.insert(TasksOrder,table.find(TasksOrder,"LevelFarm"),"BonesStock")
    do
        local previousBuy=BuyMelee
        local controller=FunctionsHandler.MeleesController
        local previousStart=controller.Methods.Start.Callback
        local owner,blocked=nil,{}
        local priorityMelee
        local retries={}
        local teacherCamps={
            [1]={BlackLeg="Pirate",Electro="Sky Bandit",FishmanKarate="Fishman Warrior"},
            [2]={BlackLeg="Magma Ninja",Electro="Magma Ninja",FishmanKarate="Magma Ninja",DragonClaw="Mercenary",
                Superhuman="Snow Trooper",DeathStep="Arctic Warrior",SharkmanKarate="Sea Soldier"},
        }
        local sea3Teachers={ElectricClaw={-10371.47,330.76,-10131.42},DragonTalon={5661.90,1210.88,863.18},
            Godhuman={-13774.09,333.73,-9879.91}}
        local function localTeacher(name)
            local npcs=workspace:FindFirstChild("NPCs")
            return npcs and (npcs:FindFirstChild(name) or name=="Sharkman Teacher" and npcs:FindFirstChild("Daigrock, the Sharkman"))
        end
        function API.NearMeleeTeacher(name)
            local npc=localTeacher(name)
            local distance=npc and CaculateDistance(npc:GetPivot())
            return distance and distance<=10,distance
        end
        local paymentPrefix="MeleePending:"..LocalPlayer.UserId..":"
        local function savePayment(key,row)
            Storage:Set(key,row)
            Storage:Save()
        end
        local inherited=previous and previous.LastMeleePurchase
        if inherited and inherited.paymentUnconfirmed and inherited.id then
            savePayment(paymentPrefix..inherited.id,inherited)
            API.LastMeleePurchase=inherited
        end
        local function allowed(epoch,character)
            local raidBusy=API.IsRaidBusy or API.IsRaidActive
            return Running() and not API.Paused and not _G.Stop and not API.HopInProgress
                and epoch==API.ActivityEpoch and character==LocalPlayer.Character
                and (not API.ActivityAllowed or API.ActivityAllowed())
                and (not raidBusy or not raidBusy())
        end
        beginMeleeAction=function()
            if not allowed(API.ActivityEpoch,LocalPlayer.Character) or API.QuestApproach or API.RewardRollBusy then
                error(blocked,0)
            end
            CurrentTask="MeleesController"
            API.BeginActivity(CurrentTask)
        end
        local function receipt(name)
            local display=meleeDisplay[name] or name
            local id=GetMeleeIdByName(name)
            for _,container in {LocalPlayer.Character,LocalPlayer:FindFirstChild("Backpack")} do
                local tool=container:FindFirstChild(name) or container:FindFirstChild(display) or id and container:FindFirstChild(id)
                if tool and tool:IsA("Tool") and tool.ToolTip=="Melee" and tool.Parent==container then return tool end
            end
        end
        local function selectedMelee()
            if ScriptStorage.ForceMelee then return ScriptStorage.ForceMelee end
            local character=LocalPlayer.Character
            local bag=LocalPlayer:FindFirstChild("Backpack")
            local tool=character and character:FindFirstChildOfClass("Tool")
            if not tool or tool.ToolTip~="Melee" then
                tool=nil
                if not bag then return end
                for _,candidate in bag:GetChildren() do
                    if candidate:IsA("Tool") and candidate.ToolTip=="Melee" then
                        if tool then return end
                        tool=candidate
                    end
                end
            end
            if tool then
                local index=table.find(MeleesId,tool.Name)
                ScriptStorage.ForceMelee=index and MeleesTable[index] or CanonicalMelee(tool.Name)
            end
            return ScriptStorage.ForceMelee
        end
        function API.HasSelectedMelee(name)
            return selectedMelee()==name and receipt(name)~=nil
        end
        function API.CanDrawMelee(tool)
            if tool.ToolTip~="Melee" then return true end
            local name=selectedMelee()
            return name~=nil and receipt(name)==tool
        end
        local function approachTeacher(id,name,epoch,character)
            local teacher=BindedMeleeNPCNames[id]
            if not teacher then return false end
            local streamedAt
            local deadline=os.clock()+150
            while allowed(epoch,character) and os.clock()<deadline do
                local npc=localTeacher(teacher)
                local pivot=npc and npc:GetPivot()
                local distance=pivot and CaculateDistance(pivot)
                if distance and distance<=10 then return true end
                local point=SeaIndex==3 and sea3Teachers[id]
                local destination=pivot or point and CFrame.new(table.unpack(point))
                    or workspace:FindFirstChild("NPCs") and getpos(teacher)
                if not destination and SeaIndex==3 then
                    destination=CFrame.new(-5008.51,313.85,-2817.10)
                end
                if not destination then
                    local camp=teacherCamps[SeaIndex] and teacherCamps[SeaIndex][id]
                    local regions=camp and ScriptStorage.MobRegions[camp]
                    local spawn=regions and regions[1]
                    if spawn then destination=typeof(spawn)=="CFrame" and spawn or CFrame.new(spawn) end
                end
                if not destination then return false end
                distance=distance or CaculateDistance(destination)

                SetTask("SubTask",name.." | approaching "..teacher)
                TweenController.Create(destination+Vector3.new(0,3,0))
                if not npc and distance<60 then
                    streamedAt=streamedAt or os.clock()
                    if os.clock()-streamedAt>=8 then return false end
                end
                task.wait(.1)
            end
            return false
        end
        function API.ApproachMeleeTeacher(id,name)
            return approachTeacher(id,name,API.ActivityEpoch,LocalPlayer.Character)
        end
        function BuyMelee(id,query,...)
            if query then return previousBuy(id,query,...) end
            local index=table.find(MeleesId,id)
            local name=index and MeleesTable[index]
            if not name or coroutine.running()~=owner then return end
            local paymentKey=paymentPrefix..id
            local data=LocalPlayer.Data
            local existing=receipt(name)
            local owned=ScriptStorage.Melees[name]~=nil or existing~=nil
            local pending=Storage:Get(paymentKey)
            if pending and pending.response=="nil" and not pending.transportUncertain and pending.paidBeli==0 and pending.paidFragments==0 then
                nextInventoryRefresh=0
                local refreshed=pcall(RefreshInventory)
                if refreshed and API.InventoryKnown and (not pending.beforeBeli or data.Beli.Value>=pending.beforeBeli)
                    and (not pending.beforeFragments or data.Fragments.Value>=pending.beforeFragments) then
                    existing=receipt(name)
                    owned=ScriptStorage.Melees[name]~=nil or existing~=nil
                    pending=nil;savePayment(paymentKey)
                end
            end
            local retry=id=="DragonClaw" and API.RetryDragonClaw==true
            if pending then
                if not owned and not retry then
                    API.LastMeleePurchase=pending
                    SetTask("SubTask",name.." | payment needs verification")
                    error(blocked,0)
                end
                if owned then savePayment(paymentKey) end
            end
            if os.clock()<(retries[id] or 0) then
                SetTask("SubTask","Waiting for "..name.." purchase confirmation")
                error(blocked,0)
            end
            if id=="Electro" and not API.ElectroUnlocked then
                previousBuy(id,query,...)
                error(blocked,0)
            end
            beginMeleeAction()
            local epoch,character=API.ActivityEpoch,LocalPlayer.Character
            if not approachTeacher(id,name,epoch,character) then
                retries[id]=os.clock()+15
                SetTask("SubTask",name.." | waiting for teacher")

                error(blocked,0)
            end
            if id=="ElectricClaw" and not owned then
                local state=Remotes.CommF_:InvokeServer("BuyElectricClaw",true)
                if state~=0 and state~=1 then
                    retries[id]=os.clock()+15
                    SetTask("SubTask",state==4 and "Electric Claw | Previous Hero quest required" or "Electric Claw | native readiness unconfirmed")
                    error(blocked,0)
                end
            end
            if id=="DragonClaw" and not owned then
                local offer=previousBuy(id,true)
                if not offer or (offer~=1 and LocalPlayer.Data.Fragments.Value<1500) or not allowed(epoch,character) then
                    retries[id]=os.clock()+15
                    error(blocked,0)
                end
            end
            local beforeBeli,beforeFragments=data.Beli.Value,data.Fragments.Value
            local teacher=BindedMeleeNPCNames[id]
            local near,distance=API.NearMeleeTeacher(teacher)
            if not near then error(blocked,0) end
            if not owned then
                savePayment(paymentKey,{id=id,name=name,confirmed=false,paymentUnconfirmed=true,status="purchase pending",
                    beforeBeli=beforeBeli,beforeFragments=beforeFragments})
            end
            if not allowed(epoch,character) or not API.NearMeleeTeacher(teacher) then
                if not owned then savePayment(paymentKey,pending) end
                error(blocked,0)
            end
            if retry then API.RetryDragonClaw=nil end
            API.LastMeleePurchase=nil
            local result=previousBuy(id,query,...)
            local tool=receipt(name);local deadline=os.clock()+2.5
            while not tool and allowed(epoch,character) and os.clock()<deadline do
                task.wait(.05);tool=receipt(name)
            end
            local row=API.LastMeleePurchase
            if not row or row.id~=id then row={id=id,response=tostring(result)} end
            local confirmed=tool~=nil and allowed(epoch,character)
                and (not existing or not row.transportUncertain and API.NearMeleeTeacher(teacher))
            row.id=id;row.name=name;row.confirmed=confirmed
            row.teacher=teacher;row.distance=math.round(distance*10)/10
            row.status=confirmed and "tool received" or "purchase unconfirmed; keep melee order"
            row.tool=tool and tool.Name or nil
            row.paidBeli=math.max(0,beforeBeli-data.Beli.Value)
            row.paidFragments=math.max(0,beforeFragments-data.Fragments.Value)
            row.beforeBeli=beforeBeli;row.beforeFragments=beforeFragments
            row.paymentUnconfirmed=not owned and not confirmed
                and (pending~=nil or row.transportUncertain==true or row.paidBeli>0 or row.paidFragments>0 or result==1 or result==true)
            if not owned then
                savePayment(paymentKey,row.paymentUnconfirmed and row or nil)
            end
            API.LastMeleePurchase=row
            if not confirmed then
                retries[id]=os.clock()+5
                SetTask("SubTask","Waiting for "..name.." purchase confirmation")
                error(blocked,0)
            end
            retries[id]=nil
            ScriptStorage.ForceMelee=name
            FunctionsHandler.LocalPlayerController.Methods.EquipTool:Call(name)
            row.equipped=tool.Parent==character

            return result
        end
        local function asOwner(callback,...)
            local previousOwner=owner;owner=coroutine.running()
            local ok,result=pcall(callback,...)
            owner=previousOwner
            if not ok and result~=blocked then error(result,0) end
            return ok,result
        end
        controller:RegisterMethod("Start",function()
            if not allowed(API.ActivityEpoch,LocalPlayer.Character) then return end
            local equip
            if priorityMelee then
                local style=MeleePrices[priorityMelee]
                local mastery=ScriptStorage.Melees[priorityMelee] or 0
                if mastery>=style.NextLevelRequirement then
                    priorityMelee=nil
                elseif API.HasSelectedMelee(priorityMelee) then
                    SetTask("SubTask",priorityMelee.." | mastery "..mastery.." / "..style.NextLevelRequirement)
                    return
                else
                    equip=GetMeleeIdByName(priorityMelee)
                end
            end
            API.BindActivity()
            local ok,result
            if equip then ok,result=asOwner(BuyMelee,equip)
            else ok,result=asOwner(previousStart) end
            if ok then return result end
        end)
        local function tryUnlockedMelee(name,requirement)
            local data=LocalPlayer.Data
            local style=MeleePrices[name]
            if not Config.Items.AutoFullyMelees or ScriptStorage.Melees[name] or API.HasSelectedMelee(name)
                or (ScriptStorage.Melees[requirement] or 0)<400
                or data.Beli.Value<style.Price.Beli or data.Fragments.Value<style.Price.Fragments then return end
            if asOwner(BuyMelee,GetMeleeIdByName(name)) and API.HasSelectedMelee(name) then priorityMelee=name end
        end
        function API.TryTalonPurchase() return tryUnlockedMelee("Dragon Talon","Dragon Claw") end
        function API.TryElectricClawPurchase() return tryUnlockedMelee("Electric Claw","Electro") end
    end
    do
        local raid=FunctionsHandler.RaidController
        local lastTimer,startingAt,startingEpoch,retryAt,cancelEpoch=-math.huge,nil,nil,0,0
        local remoteTried,localRetried=false,false
        local state={jobId=game.JobId,status="idle",phase="idle",attempts=0,events={}}
        local exitOrigin
        local reservedFruit
        local function releaseRaidFruit()
            local index=reservedFruit and table.find(ScriptStorage.IgnoreStoreFruits,reservedFruit)
            if index then table.remove(ScriptStorage.IgnoreStoreFruits,index) end
            reservedFruit=nil
        end
        local function rootPosition()
            local char=LocalPlayer.Character;local root=char and char:FindFirstChild("HumanoidRootPart")
            return root and root.Position
        end
        local function movedFrom(origin)
            local position=origin and rootPosition()
            return position and (position-origin).Magnitude>20
        end
        local function prepareExit()
            local needed=LocalPlayer:GetAttribute("IslandRaiding")==true
            exitOrigin=needed and rootPosition() or nil
            state.exit={attempts=0,nextTry=0,needed=needed,complete=not needed,status=needed and "pending" or "already exited natively"}
            state.awaitingExit=needed;state.exiting=false
            state.phase=needed and "awaiting exit" or "finished"
        end
        local function completeExit(verified)
            local row=state.exit
            if verified then row.confirmed=true;row.confirmedAt=workspace:GetServerTimeNow() end
            row.complete=true;row.status=verified and "verified native exit" or "native exit observed"
            if (state.exiting or verified) and API.CurrentTask=="RaidController" and API.ClearMove then API.ClearMove() end
            state.awaitingExit=false;state.exiting=false;state.phase="finished";state.status=row.status
        end
        local resume=API.RaidResume
        if resume and resume.jobId==game.JobId and resume.finished==true
            and resume.finishedReceipt and resume.finishedReceipt.event=="Finished" then
            for _,key in {"finished","finishedAt","finishedReceipt","fragmentsBaseline","fragmentsEnd","fragmentsGain","rewardObserved","result"} do state[key]=resume[key] end
            state.lastEvent="Finished";state.lastEventAt=state.finishedReceipt.at
            prepareExit()
        end
        API.Raid=state;API.RaidActive=false;API.RaidStarting=false
        local function clearStart(reason,delay)
            releaseRaidFruit()
            API.RaidStarting=false;startingAt=nil;startingEpoch=nil;state.exiting=false
            remoteTried=false;localRetried=false
            state.status=reason;state.phase=reason=="active" and "active" or "idle";retryAt=os.clock()+(delay or 0)
        end
        API.CancelRaid=function()
            if state.exiting and API.CurrentTask=="RaidController" and API.ClearMove then API.ClearMove() end
            cancelEpoch+=1;clearStart("cancelled")
        end
        local data=LocalPlayer:FindFirstChild("Data")
        local fragments=data and data:FindFirstChild("Fragments")
        local batchKey="MeleeRaidBatch"
        local batch=Storage:Get(batchKey)
        if type(batch)~="table" then batch={number=0,active=false} end
        local budget={number=batch.number,active=batch.active}
        state.batch=budget
        local function godhumanOwned()
            return ScriptStorage.Melees.Godhuman or ScriptStorage.Backpack.Godhuman or ScriptStorage.Tools.Godhuman
        end
        local function remainingBudget()
            if godhumanOwned() or not Config.Items.AutoFullyMelees then return 0 end
            if not API.InventoryKnown then return nil end
            local total=0
            for _,name in MeleesTable do
                local style=MeleePrices[name]
                if style and not ScriptStorage.Melees[name] and not ScriptStorage.Backpack[name] then
                    total+=style.Price.Fragments or 0
                end
                if name=="Godhuman" then break end
            end
            return total
        end
        local function setBatch(active,status)
            budget.status=status
            if batch.active==active then return end
            batch.active=active
            if active then batch.number=(batch.number or 0)+1 end
            budget.active=active;budget.number=batch.number
            Storage:Set(batchKey,batch);Storage:Save()
        end
        local function batchReady()
            local level=ScriptStorage.PlayerData.Level
            if SeaIndex==1 or not level or level<1300 or not fragments then return false end
            local remaining=remainingBudget()
            if remaining==nil then budget.status="waiting for inventory";return false end
            local balance=fragments.Value
            budget.remaining=remaining;budget.fragments=balance
            if remaining<=balance then
                setBatch(false,godhumanOwned() and "Godhuman owned" or "fragment budget funded")
                return false
            end
            local fruit,count=raid.Methods.GetRaidableFruit:Call()
            local chip=CheckSpecialMicrochip()
            budget.stock=count
            if not fruit and not chip then setBatch(false,"stock exhausted");return false end
            if batch.active then return true,fruit end
            local covered=(count+(chip and 1 or 0))*1000>=remaining-balance
            if count>15 or (batch.number>0 or level>=MaxLevel) and covered then
                setBatch(true,count>15 and "common fruit stock" or "fragment top-up")
                return true,fruit
            end
            budget.status="waiting for fruit stock"
            return false
        end
        function API.IsRaidBatchReady()
            return batch.active and batchReady()
        end
        local fruitPrices={}
        function API.ShouldCollectDroppedFruit(drop)
            local remaining=remainingBudget()
            if remaining==nil or remaining>(fragments and fragments.Value or 0) then return not batch.active end
            local name=drop:GetAttribute("OriginalName")
            if not name then
                local fruit=drop.Name:match("^(.+) Fruit$")
                name=fruit and fruit.."-"..fruit
            end
            if not name then return false end
            if fruitPrices[name]==nil then
                fruitPrices[name]=false
                for id,entry in itemDefinitions do
                    if entry.Id and entry.Id.StorageKey==name then
                        local definition=itemConfig.tryGet(id)
                        fruitPrices[name]=definition and definition.Quality and definition.Quality.MoneyPrice or false
                        if fruitPrices[name] then break end
                    end
                end
            end
            local price=fruitPrices[name]
            return type(price)=="number" and price>=1000000
        end
        local function updateFragments()
            if not state.finished and state.lastEvent~="StartTimer" then return end
            if state.finished and state.finishedAt and workspace:GetServerTimeNow()-state.finishedAt>8 then return end
            state.fragmentsEnd=fragments and fragments.Value or 0
            state.fragmentsGain=state.fragmentsEnd-(state.fragmentsBaseline or state.fragmentsEnd)
            state.rewardObserved=state.fragmentsGain>0
            if state.finished then state.result=state.rewardObserved and "Finished; fragment increase observed" or "Finished; no fragment increase observed" end
        end
        function API.RecordRaidExternalFragments(gain,raidStart)
            if gain>0 and state.lastEvent=="StartTimer" and state.lastEventAt==raidStart then
                state.fragmentsBaseline+=gain
                updateFragments()
            end
        end
        state.fragmentsBaseline=state.fragmentsBaseline or (fragments and fragments.Value or 0)
        state.fragmentsGain=state.fragmentsGain or 0;state.rewardObserved=state.rewardObserved==true
        updateFragments()
        if fragments then Track(fragments.Changed:Connect(updateFragments)) end
        Track(Remotes.Raids.OnClientEvent:Connect(function(event,duration,serverStartTime)
            if event~="StartTimer" and event~="Finished" then return end
            if event=="Finished" and state.finished then return end
            local at=workspace:GetServerTimeNow()
            state.lastEvent=event;state.lastEventAt=at
            table.insert(state.events,{event=event,at=at,duration=duration,serverStartTime=serverStartTime})
            if #state.events>12 then table.remove(state.events,1) end
            if event=="StartTimer" then
                state.finished=false;state.awaitingExit=false;state.exiting=false;state.exit=nil;exitOrigin=nil;state.finishedAt=nil;state.result=nil
                state.duration=duration;state.serverStartTime=serverStartTime
                state.serverEndTime=type(duration)=="number" and type(serverStartTime)=="number" and serverStartTime+duration or nil
                state.fragmentsBaseline=fragments and fragments.Value or 0;updateFragments()
                state.status="native raid started";state.phase="active"
            else
                state.finished=true;state.finishedAt=at;updateFragments()
                state.finishedReceipt={event=event,at=at,fragments=state.fragmentsEnd,gain=state.fragmentsGain}
                cancelEpoch+=1;API.RaidActive=false
                clearStart("native Finished received")
                prepareExit()
                if API.CurrentTask=="RaidController" and API.ClearMove then API.ClearMove() end
            end
        end))
        local function timerVisible()
            local gui=LocalPlayer:FindFirstChild("PlayerGui")
            local main=gui and gui:FindFirstChild("Main")
            local hud=main and main:FindFirstChild("TopHUDList")
            local timer=hud and hud:FindFirstChild("RaidTimer")
            return timer~=nil and timer.Visible==true
        end
        local function currentIsland()
            local char=LocalPlayer.Character
            local root=char and char:FindFirstChild("HumanoidRootPart")
            local origin=workspace:FindFirstChild("_WorldOrigin")
            local locations=origin and origin:FindFirstChild("Locations")
            if not root or not locations then return end
            local current=LocalPlayer:GetAttribute("IslandRaiding")==true and LocalPlayer:GetAttribute("CurrentLocation")
            local nearby,highest,fallback,nearest=nil,0,nil,15000
            for _,marker in locations:GetChildren() do
                local tier=tonumber(marker.Name:match("^Island ([1-5])$"))
                if tier then
                    local distance=(marker.Position-root.Position).Magnitude
                    if tier>highest and distance<2000 and marker.Position.Magnitude>7000 then
                        nearby,highest=marker,tier
                    end
                    if marker.Name==current and distance<nearest then fallback,nearest=marker,distance end
                end
            end
            return nearby or fallback
        end
        API.IsRaidActive=function()
            local now=os.clock();local native=LocalPlayer:GetAttribute("IslandRaiding")
            if API.RaidStarting and (not Running() or API.Paused or _G.Stop or API.HopInProgress
                or startingEpoch~=API.ActivityEpoch) then clearStart("cancelled") end
            if state.finished then
                API.RaidActive=false
                if state.awaitingExit then
                    if native==false and movedFrom(exitOrigin) then
                        completeExit(false)
                    else
                        state.phase=state.exiting and "exiting" or "awaiting exit"
                    end
                end
            elseif type(native)=="boolean" then
                API.RaidActive=native
            else
                local visible=timerVisible()
                if visible then lastTimer=now end
                API.RaidActive=visible or now-lastTimer<=8 and currentIsland()~=nil
            end
            return API.RaidActive
        end
        API.IsRaidBusy=function()
            return API.IsRaidActive() or API.RaidStarting or state.awaitingExit==true
        end
        raid:RegisterMethod("GetCurrentRaidIsland",function()
            return API.IsRaidActive() and currentIsland() or nil
        end)
        raid:RegisterMethod("Refresh",function()
            if API.IsRaidBusy() then return true end
            if os.clock()<retryAt then return nil end
            return batchReady()
        end)
        raid:RegisterMethod("Start",function()
            local epoch=API.ActivityEpoch;local character=LocalPlayer.Character;local cancellation=cancelEpoch
            local function allowed()
                return Running() and not API.Paused and not _G.Stop and not API.HopInProgress
                    and API.CurrentTask=="RaidController" and API.ActivityEpoch==epoch and cancellation==cancelEpoch
                    and LocalPlayer.Character==character and (not API.ActivityAllowed or API.ActivityAllowed())
            end
            local function waitFor(check,seconds)
                local deadline=os.clock()+seconds
                repeat
                    if not allowed() then return false end
                    if check() then return true end
                    task.wait(.1)
                until os.clock()>=deadline
                return false
            end
            local function exitRaid(root)
                local row=state.exit
                if not state.finished or not row or row.complete or row.exhausted then return end
                if LocalPlayer:GetAttribute("IslandRaiding")~=true then row.status="waiting for native exit transition";return end
                row.startedAt=row.startedAt or os.clock()
                if row.attempts>=3 or os.clock()-row.startedAt>=30 then
                    row.exhausted=true;row.status="native exit unconfirmed; retry window exhausted";state.status=row.status;state.exiting=false;state.phase="awaiting exit"
                    if API.ClearMove then API.ClearMove() end
                    return
                end
                if os.clock()<row.nextTry then state.exiting=false;state.phase="awaiting exit";return end
                local folder=workspace:FindFirstChild("NPCs")
                local npc=folder and folder:FindFirstChild("Mysterious Entity")
                    or ScriptStorage.NPCs and ScriptStorage.NPCs["Mysterious Entity"]
                local point
                if npc and npc.Parent then
                    local ok,cf=pcall(npc.GetPivot,npc)
                    if ok and (cf.Position-root.Position).Magnitude<=500 then point=cf end
                end
                state.exiting=true;state.phase="exiting";row.npcAvailable=point~=nil
                if point and (point.Position-root.Position).Magnitude>12 then
                    row.status="approaching Mysterious Entity";state.status=row.status
                    TweenController.Create(point);return
                end
                if not allowed() then state.exiting=false;return end
                if API.ClearMove then API.ClearMove() end
                local from=root.Position
                row.attempts+=1;row.nextTry=os.clock()+5;row.at=workspace:GetServerTimeNow();row.status="requesting native exit"
                local response=Remotes.CommF_:InvokeServer("Awakener","Teleport")
                row.response=response
                if not allowed() then state.exiting=false;state.phase="awaiting exit";row.status="cancelled";return end
                local transitioned=response==1 and waitFor(function()
                    return LocalPlayer:GetAttribute("IslandRaiding")==false and movedFrom(from)
                end,math.max(0,math.min(5,30-(os.clock()-row.startedAt))))
                state.exiting=false
                if transitioned then
                    completeExit(true)
                else
                    row.status=allowed() and "native exit unconfirmed" or "cancelled";state.status=row.status
                    row.nextTry=os.clock()+5;state.phase="awaiting exit"
                end
            end
            local function run()
                if not allowed() then clearStart("cancelled");return end
                local root=character and character:FindFirstChild("HumanoidRootPart")
                local human=character and character:FindFirstChildOfClass("Humanoid")
                if not root or not human or human.Health<=0 then clearStart("waiting for character");return end
                if API.IsRaidActive() then
                    if API.RaidStarting and API.ClearMove then API.ClearMove() end
                    clearStart("active")
                    local island=currentIsland()
                    if not island then state.status="waiting for native raid arrival / next island";return end
                    SetTask("MainTask","Auto Raid - "..island.Name.." / 5")
                    local fought=false
                    for _,mob in GetMonAsSortedRange() do
                        if not allowed() or not API.IsRaidActive() then return end
                        local started=os.clock()
                        local function cancelled()
                            return not allowed() or not API.IsRaidActive() or os.clock()-started>=60
                                or not CanFarmMob(mob) or CaculateDistance(mob.HumanoidRootPart.Position)>=1000
                        end
                        while not cancelled() do
                            fought=true
                            local targetHuman=mob:FindFirstChild("Humanoid")
                            state.target={name=mob.Name,healthBefore=targetHuman.Health,startedAt=workspace:GetServerTimeNow()}
                            local ok,message=pcall(CombatController.Attack,mob,nil,nil,cancelled)
                            state.target.healthAfter=targetHuman.Health
                            state.target.damage=math.max(0,state.target.healthBefore-state.target.healthAfter)
                            if not ok then error(message,0) end
                            task.wait(.05)
                        end
                    end
                    if allowed() and not fought then TweenController.Create(island.Position+Vector3.new(0,100,0)) end
                    return
                end
                if state.awaitingExit then exitRaid(root);return end
                if os.clock()<retryAt then return end
                local ready,fruit=batchReady()
                if not ready then clearStart("raid batch not ready");return end
                if not startingAt then startingAt=os.clock();startingEpoch=epoch end
                API.RaidStarting=true;state.phase="starting"
                if os.clock()-startingAt>120 then clearStart("summon approach timed out",30);return end
                if localRetried and not CheckSpecialMicrochip() then clearStart("chip disappeared before retry",30);return end
                if not raid:Get("CurrentChip") then
                    raid.Methods.RefreshRaidType:Call()
                    fruit=nil
                end
                if not allowed() then clearStart("cancelled");return end
                local map=workspace:FindFirstChild("Map")
                local model=map and map:FindFirstChild(({[2]="CircleIsland",[3]="Boat Castle"})[SeaIndex])
                local summon=model and model:FindFirstChild("RaidSummon2")
                local button=summon and summon:FindFirstChild("Button")
                button=button and button:FindFirstChild("Main")
                local detector=button and button:FindFirstChildOfClass("ClickDetector")
                if not detector then
                    state.status="approaching raid site; waiting for summon button"
                    local npcs=Services.ReplicatedStorage.NPCs
                    local teacher=npcs and npcs:FindFirstChild("Mysterious Scientist")
                    if teacher then TweenController.Create(teacher:GetPivot())
                    elseif SeaIndex==3 then TweenController.Create(CFrame.new(Vector3.new(-5008.51,313.85,-2817.10)))
                    elseif model then TweenController.Create(model:GetModelCFrame()) end
                    return
                end
                if not CheckSpecialMicrochip() then
                    if API.RewardRollBusy then return end
                    fruit=fruit or raid.Methods.GetRaidableFruit:Call()
                    if not fruit then clearStart("waiting for chip or raidable fruit",10);return end
                    state.status="buying chip";SetTask("MainTask","Auto Raid - Buying Chip - "..raid:Get("CurrentChip"))
                    reservedFruit=fruit.Name
                    table.insert(ScriptStorage.IgnoreStoreFruits,reservedFruit)
                    Remotes.CommF_:InvokeServer("LoadFruit",fruit.Name)
                    if not allowed() then clearStart("cancelled");return end
                    local beli=data and data:FindFirstChild("Beli")
                    local beforeBeli,beforeFragments=beli and beli.Value,fragments and fragments.Value
                    local response=Remotes.CommF_:InvokeServer("RaidsNpc","Select",raid:Get("CurrentChip"))
                    local received=waitFor(CheckSpecialMicrochip,2)
                    releaseRaidFruit()
                    if not received then
                        clearStart(allowed() and "chip purchase unconfirmed" or "cancelled",10);return
                    end
                end
                if not allowed() then clearStart("cancelled");return end
                state.status="approaching summon button"
                local distance=(button.Position-root.Position).Magnitude
                local remote=distance>12
                if remote and (remoteTried or localRetried) then
                    TweenController.Create(button.CFrame);return
                end
                if not CheckSpecialMicrochip() then clearStart("chip disappeared",10);return end
                FunctionsHandler.LocalPlayerController.Methods.EquipTool:Call("Special Microchip")
                if not allowed() or not CheckSpecialMicrochip() then clearStart("cancelled or chip disappeared");return end
                if API.ClearMove then API.ClearMove() end
                if state.finished and state.exit and state.exit.complete and LocalPlayer:GetAttribute("IslandRaiding")==false then
                    state.previousFinish={receipt=state.finishedReceipt,result=state.result,fragmentsGain=state.fragmentsGain}
                    state.finished=false;state.awaitingExit=false;state.exiting=false;state.exit=nil;exitOrigin=nil
                end
                state.lastEvent=nil
                state.fragmentsBaseline=fragments and fragments.Value or 0
                state.fragmentsEnd=state.fragmentsBaseline;state.fragmentsGain=0;state.rewardObserved=false
                local sent=true
                if remote then
                    remoteTried=true
                    sent=pcall(fireclickdetector,detector)
                else
                    fireclickdetector(detector)
                end
                state.attempts+=1
                state.status=remote and "waiting for remote summon confirmation" or "waiting for native raid state"
                SetTask("MainTask","Auto Raid - Waiting Until Raid Is Started")
                local active=false
                if sent then
                    local deadline=os.clock()+20
                    if remote then
                        waitFor(function() return API.IsRaidActive() or not CheckSpecialMicrochip() end,5)
                    end
                    active=API.IsRaidActive()
                    if not active and (not remote or not CheckSpecialMicrochip()) then
                        active=waitFor(API.IsRaidActive,math.max(0,deadline-os.clock()))
                    end
                end
                local held=not not CheckSpecialMicrochip()
                if not allowed() then
                    clearStart("cancelled")
                elseif active then
                    if API.ClearMove then API.ClearMove() end
                    clearStart("active")
                elseif not held then
                    clearStart("native raid start unconfirmed",30)
                elseif remote then
                    state.status="remote summon unconfirmed; approaching button"
                elseif not localRetried then
                    localRetried=true;retryAt=os.clock()+30
                    state.status="waiting to retry at summon button"
                else
                    clearStart("native raid start unconfirmed",30)
                end
            end
            local ok,message=xpcall(run,debug.traceback)
            if not ok then
                if state.exiting and API.ActivityEpoch==epoch and API.CurrentTask=="RaidController" and API.ClearMove then API.ClearMove() end
                clearStart("raid error",30);
            end
        end)
        local previousCleanup=API.Cleanup
        API.Cleanup=function()
            cancelEpoch+=1;clearStart("stopped");API.RaidActive=false
            if previousCleanup then previousCleanup() end
        end
    end
    local expCodes={'EASTEREXP', 'LIGHTNINGABUSE', '1LOSTADMIN', 'BANEXPLOIT', 'NOMOREHACK', "WildDares", 'BossBuild', 'GetPranked', 'EARN_FRUITS',  'FIGHT4FRUIT', "kittgaming", 'TRIPLEABUSE', "Sub2CaptainMaui", 'Sub2Fer999', "Enyu_is_Pro", "Magicbus", "JCWK", 'Starcodeheo', 'Bluxxy', 'SUB2GAMERROBOT_EXP1', 'Sub2NoobMaster123', 'Sub2Daigrock', "Axiore", "TantaiGaming", 'StrawHatMaine', 'Sub2OfficialNoobie', "TheGreatAce", "SEATROLLING", "24NOADMIN", 'ADMIN_TROLL', 'NEWTROLL', 'SECRET_ADMIN', "staffbattle", "NOEXPLOIT", "NOOB2ADMIN", "CODESLIDE", "fruitconcepts"}
    local ledgerKey="RedeemCodes:"..LocalPlayer.UserId
    local results=Storage:Get(ledgerKey) or {}
    local beliCodes={"FUDD10","fudd10_v2","Chandler"}
    local function RedeemAllCodes()
        for _,codes in {Config.RedeemCodes and expCodes or {},Config.RedeemBeliCodes and beliCodes or {}} do
            for _,code in codes do
                if not Running() then return end
                local row=results[code]
                if not row then
                    SetTask("MainTask","Code Redemption | "..code)
                    local ok,response,extra=pcall(Invoke,Remotes.Redeem,code)
                    local message=type(response)=="string" and response or type(extra)=="string" and extra or ""
                    local text=string.lower(message)
                    local terminal=response==true or text:find("success",1,true) or text:find("already",1,true)
                        or text:find("invalid",1,true) or text:find("expired",1,true) or text:find("not found",1,true)
                        or text:find("must ",1,true) or text:find("does not exist",1,true)
                    row={ok=ok,response=tostring(response),message=message,accepted=response==true or text:find("success",1,true)~=nil}
                    if ok and terminal then
                        results[code]=row
                        Storage:Set(ledgerKey,results)
                        Storage:Save()
                    end
                    task.wait(.25)
                end
            end
        end
    end

    -- Poll only Roblox's own disconnect prompt, independent of farm/remote waits.
    local rejoinPending=false
    API.Rejoin={attempts=0}
    function API.RequestRejoin(reason)
        if not Running() or rejoinPending then return false end
        rejoinPending=true
        API.Rejoin.attempts+=1; API.Rejoin.lastAttempt=os.clock()
        API.Rejoin.reason=reason; API.Rejoin.status="requesting"
        local worker=task.spawn(function()
            local ok,issue=pcall(function()

                game:GetService("TeleportService"):Teleport(game.PlaceId,LocalPlayer)
            end)
            if not ok then API.Rejoin.error=tostring(issue); API.Rejoin.status="retry waiting" end
            rejoinPending=false
        end)
        task.delay(30,function()
            if rejoinPending then
                pcall(EngineTask.cancel,worker)
                rejoinPending=false; API.Rejoin.status="request timed out; retry waiting"
            end
        end)
        return true
    end
    task.spawn(function()
        while Running() do
            local gui=game:GetService("CoreGui"):FindFirstChild("RobloxPromptGui")
            local prompt=gui and gui:FindFirstChild("ErrorPrompt",true)
            local title=prompt and prompt:FindFirstChild("ErrorTitle",true)
            if Support.ShouldRejoin(prompt and prompt.Visible,title and title.Text,os.clock(),API.Rejoin.attempts,API.Rejoin.lastAttempt) then
                API.RequestRejoin(title.Text)
            end
            task.wait(5)
        end
    end)

    SetTask("MainTask","n/a")
    SetTask("SubTask","n/a")
    function RefreshTasksData()
        if _G.Stop or API.Paused or not Running() then return end
        if API.IsRaidBusy and API.IsRaidBusy() then
            CurrentTask="RaidController";API.BeginActivity(CurrentTask)
            FunctionsHandler.RaidController.Methods.Start:Call(true)
            return
        end
        local checked={}
        local function checkEvent(name)
            if checked[name]==nil then checked[name]=FunctionsHandler[name].Methods.Refresh:Call() or false end
            return checked[name]
        end
        if API.QuestApproach and not ReadyEvent(nil,checkEvent) and not PreviousHeroReady() then
            local owner=API.QuestApproach.owner or "LevelFarm"
            API.BeginActivity(owner)
            FunctionsHandler[owner].Methods.Start:Call(4)
            return
        end
        if API.FruitApproach and not ReadyEvent("CollectDrops",checkEvent) and not PreviousHeroReady() then
            if checkEvent("CollectDrops") then
                API.BeginActivity("CollectDrops")
                FunctionsHandler.CollectDrops.Methods.Start:Call()
                return
            end
            API.EndFruitApproach("target unavailable")
        end
        for _,name in TasksOrder do
            local methods=FunctionsHandler[name].Methods
            if not methods or not methods.Refresh or not methods.Start then continue end
            local ready
            if table.find(eventOrder,name) then ready=checkEvent(name)
            else ready=methods.Refresh:Call() end
            if ready then
                CurrentTask=name
                API.BeginActivity(name)
                API.Phase="running"
                methods.Start:Call(ready)
                return
            end
        end
    end
    if not API.Paused then AddPoint() end
    J:RefreshQuest()
    RefreshInventory()
    Track(Remotes.CommE.OnClientEvent:Connect(function(...)
        local J = {...}
        if string.find(J[1], 'Item') then RefreshInventory() end
    end))
    Track(a.LocalPlayer.Idled:Connect(function()
        Services.VirtualUser:CaptureController()
        Services.VirtualUser:ClickButton2(Vector2.new())
    end))
    task.spawn(function()
        local nextPlayerData=0
        while Running() and task.wait() do
            local char=LocalPlayer.Character
            local human=char and char:FindFirstChildOfClass("Humanoid")
            if human and human.Sit then human:ChangeState(Enum.HumanoidStateType.Jumping) end
            local now=os.clock()
            if now>=nextPlayerData then
                nextPlayerData=now+.1
                RefreshPlayerData()
            end
        end
    end)
    if not API.Paused then AddPoint() end
    local function FinishBoot()
        if API.BootComplete or API.Paused or API.IsRaidBusy and API.IsRaidBusy() then return end
        API.BindActivity()
        pcall(CheckBuso)
        RedeemAllCodes()
        API.BootComplete=true

        pcall(function()
    Remotes.CommF_:InvokeServer("BuyHaki", "Geppo")
    Remotes.CommF_:InvokeServer("BuyHaki", "Soru")
    Remotes.CommF_:InvokeServer("KenTalk", "Buy")
        end)
        API.EndActivity()
    end
    FinishBoot()
    while Running() and task.wait(.1) do
        if not API.Paused and not API.HopInProgress then
            local ok,issue=xpcall(function()
            FinishBoot()
            local urgent=SeaIndex==3 and (ScriptStorage.Tools["Fire Essence"]~=nil
                or not (API.IsRaidBusy and API.IsRaidBusy()) and PreviousHeroReady())
            if not urgent and not API.QuestApproach and not API.FruitApproach and not (API.IsRaidBusy and API.IsRaidBusy())
                and not (API.IsRaidBatchReady and API.IsRaidBatchReady()) and not ReadyEvent() then
                FunctionsHandler.MeleesController.Methods.Start:Call()
            end
            RefreshTasksData()
            end,debug.traceback)
            API.EndBringRound()
            API.EndActivity()
        end
    end
end

task.spawn(function()
    local ok,failure=xpcall(Main,debug.traceback)
    if not ok and Running() then API.Phase="failed";API.Stop() end
end)
