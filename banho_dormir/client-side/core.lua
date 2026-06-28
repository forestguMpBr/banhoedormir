-----------------------------------------------------------------------------------------------------------------------------------------
-- BANHO E DORMIR - CLIENT SIDE (QBX / MriqBox)
-- Otimizado conforme guias oficiais FiveM e cfx.re docs
-----------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------------------------------------------------------
-- VARIÁVEIS GLOBAIS
-----------------------------------------------------------------------------------------------------------------------------------------
local Locations      = {}
local LocationCoords = {}   -- cache de vec3 para evitar recriar todo frame
local Active         = false
local Panel          = false
local ActionProp     = false
local cbCounter      = 0

-- Necessidades
local Dirt                 = 0
local Sleep                = 0
local lastHealth           = 200
local lastRagdoll          = false
local dirtCooldown         = 0
local dirtNotifyThreshold  = 0
local sleepNotifyThreshold = 0

-- Efeito visual
local lastModifier     = ''
local lastStrength     = -1
local screenEffActive  = ''

-- Moscas
local flyThread = false
local flyActive = false

-- Nojo
local nauseaActive = false

-- Cache de nativos (conforme docs oficiais: cache natives that change infrequently)
local _PlayerPedId        = PlayerPedId
local _GetEntityCoords    = GetEntityCoords
local _GetEntityHealth    = GetEntityHealth
local _IsPedRagdoll       = IsPedRagdoll
local _IsPedSwimming      = IsPedSwimming
local _IsEntityInWater    = IsEntityInWater
local _IsPedWalking       = IsPedWalking
local _IsPedRunning       = IsPedRunning
local _IsPedSprinting     = IsPedSprinting
local _IsPedInAnyVehicle  = IsPedInAnyVehicle
local _DrawMarker         = DrawMarker
local _World3dToScreen2d  = World3dToScreen2d
local _IsControlJustPressed = IsControlJustPressed

-- Cache de math
local mcos  = math.cos
local msin  = math.sin
local mmin  = math.min
local mmax  = math.max
local mfloor = math.floor

-----------------------------------------------------------------------------------------------------------------------------------------
-- UTILS
-----------------------------------------------------------------------------------------------------------------------------------------
local function LoadAnim(dict)
    if not dict then return false end
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(100) end
    return HasAnimDictLoaded(dict)
end

local function LoadModel(model)
    if not model then return false end
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelValid(hash) then return false end
    if HasModelLoaded(hash) then return true end
    RequestModel(hash)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(100) end
    return HasModelLoaded(hash)
end

local function ServerCall(eventName, ...)
    cbCounter = cbCounter + 1
    local cbId = tostring(cbCounter)
    local result, done = nil, false
    local handler
    handler = AddEventHandler('banho_dormir:cb', function(id, data)
        if id ~= cbId then return end
        result = data
        done   = true
        RemoveEventHandler(handler)
    end)
    TriggerServerEvent('banho_dormir:sv:' .. eventName, cbId, ...)
    local t = GetGameTimer() + 10000
    while not done and GetGameTimer() < t do Wait(0) end
    return result
end

local function Notify(Title, Message, Type, Time)
    lib.notify({
        title       = Title,
        description = Message,
        type        = (Type == 'verde' and 'success' or Type == 'vermelho' and 'error' or 'inform'),
        duration    = Time or 5000
    })
end

local function HelpText(Text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(Text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function DrawText3D(x, y, z, Text)
    local onScreen, sx, sy = _World3dToScreen2d(x, y, z)
    if not onScreen then return end
    SetTextFont(4)
    SetTextScale(0.34, 0.34)
    SetTextColour(255, 255, 255, 235)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(Text)
    EndTextCommandDisplayText(sx, sy)
end

local function TypeConfig(Type)
    return BathSleep.Types[Type] or BathSleep.Types.bath
end

local function CanUse(Ped)
    if Active then return false end
    if _IsPedInAnyVehicle(Ped) then
        Notify('Banho e Dormir', 'Saia do veiculo primeiro.', 'amarelo', 4000)
        return false
    end
    if _GetEntityHealth(Ped) <= 100 or LocalPlayer.state.Dead or LocalPlayer.state.Handcuff or LocalPlayer.state.Prison then
        Notify('Banho e Dormir', 'Voce nao pode fazer isso agora.', 'amarelo', 4000)
        return false
    end
    return true
end

local function ApplyHealth(Amount)
    Amount = tonumber(Amount) or 0
    if Amount <= 0 then return end
    local Ped = _PlayerPedId()
    SetEntityHealth(Ped, mmin(200, _GetEntityHealth(Ped) + Amount))
end

local function RebuildLocationCoords()
    LocationCoords = {}
    for i, loc in ipairs(Locations) do
        local C = loc.Coords or {}
        LocationCoords[i] = vec3(tonumber(C.x) or 0, tonumber(C.y) or 0, tonumber(C.z) or 0)
    end
end

-----------------------------------------------------------------------------------------------------------------------------------------
-- EFEITO VISUAL — só chama nativos se estado mudou
-----------------------------------------------------------------------------------------------------------------------------------------
local function SetVisualEffect(modifier, strength)
    if modifier == lastModifier and math.abs(strength - lastStrength) < 0.01 then return end
    lastModifier = modifier
    lastStrength = strength

    if screenEffActive ~= '' then
        StopScreenEffect(screenEffActive)
        screenEffActive = ''
    end
    ClearTimecycleModifier()

    if modifier == '' then return end

    if modifier == 'dirt' then
        SetTimecycleModifier('hud_def_desat_Trevor')
        SetTimecycleModifierStrength(strength)
    elseif modifier == 'sleep' then
        SetTimecycleModifier('hud_def_desat_Neutral')
        SetTimecycleModifierStrength(strength)
    elseif modifier == 'nausea' then
        screenEffActive = 'DrugsMichaelAliensFightIn'
        StartScreenEffect(screenEffActive, 0, true)
    end
end

-----------------------------------------------------------------------------------------------------------------------------------------
-- MOSCAS — StartNetworkedParticleFxNonLoopedOnPedBone no bone da cabeça
-- Fonte: github.com/YimMenu/YimMenu/discussions/2282
-----------------------------------------------------------------------------------------------------------------------------------------
local function StartFlies(Ped)
    if flyThread then return end
    flyThread = true
    flyActive = true

    CreateThread(function()
        local flies = {}
        for i = 1, 5 do
            flies[i] = {
                angle  = (i - 1) * (6.28 / 5),
                speed  = 0.02 + math.random() * 0.02,
                radius = 0.4 + math.random() * 0.25,
                height = 0.5 + math.random() * 0.5,
                buzz   = math.random() * 6.28,
                alpha  = 180 + math.random(0, 75)
            }
        end

        while flyActive and DoesEntityExist(Ped) do
            local base = _GetEntityCoords(Ped)
            for _, f in ipairs(flies) do
                f.angle = f.angle + f.speed
                if f.angle > 6.28 then f.angle = f.angle - 6.28 end
                f.buzz = f.buzz + 0.15
                local r  = f.radius + msin(f.buzz * 1.3) * 0.08
                local wx = base.x + mcos(f.angle) * r
                local wy = base.y + msin(f.angle) * r
                local wz = base.z + f.height + msin(f.buzz) * 0.12
                local onScreen, sx, sy = _World3dToScreen2d(wx, wy, wz)
                if onScreen then
                    local sz = 0.003 + msin(f.buzz * 0.5) * 0.001
                    DrawRect(sx, sy, sz, sz * 1.8, 8, 8, 8, f.alpha)
                end
            end
            Wait(0)
        end

        flyThread = false
        flyActive = false
    end)
end

local function StopFlies()
    flyActive = false
end
-----------------------------------------------------------------------------------------------------------------------------------------
-- SUJEIRA — publica nível via state bag para outros lerem (nojo)
-----------------------------------------------------------------------------------------------------------------------------------------
local function SetDirtState(value)
    Dirt = mmax(0, mmin(100, value))
    LocalPlayer.state:set('banho_dirt', mfloor(Dirt), true)
end

-----------------------------------------------------------------------------------------------------------------------------------------
-- NOJO — verificado na thread de markers a cada 3s
-----------------------------------------------------------------------------------------------------------------------------------------
local function CheckNausea(myCoords)
    local myId     = PlayerId()
    local nearDirty = false
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= myId then
            local otherPed = GetPlayerPed(pid)
            if DoesEntityExist(otherPed) then
                local otherDirt = Player(pid).state.banho_dirt or 0
                if otherDirt >= 75 and #(myCoords - _GetEntityCoords(otherPed)) <= 3.0 then
                    nearDirty = true
                    break
                end
            end
        end
    end

    if nearDirty and not nauseaActive then
        nauseaActive = true
        Notify('Higiene', 'Tem alguem muito sujo perto de voce! Se afaste.', 'error', 5000)
    elseif not nearDirty and nauseaActive then
        nauseaActive = false
        Notify('Higiene', 'Melhorou! Voce se afastou da pessoa suja.', 'inform', 3000)
    end
end

-----------------------------------------------------------------------------------------------------------------------------------------
-- SUJEIRA — adiciona com cooldown, notifica só ao cruzar threshold
-----------------------------------------------------------------------------------------------------------------------------------------
local dirtMsgs = {
    [30] = { 'Voce esta ficando sujo. Tome um banho em breve.', 'inform' },
    [60] = { 'Voce esta muito sujo! Tome um banho.',             'error'  },
    [85] = { 'Voce esta extremamente sujo! Tome um banho agora!','error'  },
}

local function AddDirt(amount)
    local now = GetGameTimer()
    if now < dirtCooldown then return end
    dirtCooldown = now + 8000

    SetDirtState(Dirt + (amount or 10))
    TriggerServerEvent('banho_dormir:sv:UpdateNeeds', Dirt, Sleep)

    local threshold = Dirt >= 85 and 85 or Dirt >= 60 and 60 or Dirt >= 30 and 30 or 0
    if threshold > 0 and threshold ~= dirtNotifyThreshold then
        dirtNotifyThreshold = threshold
        lib.notify({ title = 'Higiene', description = dirtMsgs[threshold][1], type = dirtMsgs[threshold][2], duration = 6000 })
    end
end

-----------------------------------------------------------------------------------------------------------------------------------------
-- ACTION (prop, anim, sound, progress)
-----------------------------------------------------------------------------------------------------------------------------------------
local function Progress(Label, Duration, Type)
    SendNUIMessage({ Action = 'Progress', Payload = { Label = Label, Duration = Duration, Type = Type } })
end

local function CloseProgress()
    SendNUIMessage({ Action = 'ProgressClose' })
end

local function StartActionSound(Config)
    local S = Config.Sound
    if not S or not S.Enabled then return end
    SendNUIMessage({ Action = 'Sound', Payload = { Name = S.Name or 'rain', Volume = S.Volume or 0.28 } })
end

local function StopActionSound()
    SendNUIMessage({ Action = 'SoundStop' })
end

local function SetBlocked(State)
    LocalPlayer.state:set('Commands', State, true)
    LocalPlayer.state:set('Buttons',  State, true)
    LocalPlayer.state:set('Cancel',   State, true)
end

local function DeleteActionProp()
    if ActionProp and DoesEntityExist(ActionProp) then DeleteEntity(ActionProp) end
    ActionProp = false
end

local function CreateActionProp(Config)
    DeleteActionProp()
    local Prop = Config.Prop
    if not Prop or not Prop.Enabled then return end
    local Ped    = _PlayerPedId()
    local pos    = _GetEntityCoords(Ped)
    local Models = Prop.Models or { Prop.Model }
    local Hash   = false
    for _, Model in ipairs(Models) do
        if Model and LoadModel(Model) then Hash = GetHashKey(Model) break end
    end
    if not Hash then return end
    ActionProp = CreateObject(Hash, pos.x, pos.y, pos.z + 0.2, false, false, false)
    if not ActionProp or not DoesEntityExist(ActionProp) then ActionProp = false return end
    SetEntityCollision(ActionProp, false, false)
    local Off = Prop.Offset   or vec3(0, 0, 0)
    local Rot = Prop.Rotation or vec3(0, 0, 0)
    AttachEntityToEntity(ActionProp, Ped, GetPedBoneIndex(Ped, Prop.Bone or 57005),
        Off.x, Off.y, Off.z, Rot.x, Rot.y, Rot.z, true, true, false, true, 1, true)
end

local function PlayAction(Location, idx)
    local Ped    = _PlayerPedId()
    local Config = TypeConfig(Location.Type)
    local Anim   = Config.Animation or {}
    local pos    = LocationCoords[idx]
    SetEntityHeading(Ped, tonumber(Location.Coords and Location.Coords.w) or 0.0)
    if Location.Type == 'sleep' then
        SetEntityCoords(Ped, pos.x, pos.y, pos.z + (Anim.ZOffset or 0.0), false, false, false, false)
    end
    if Anim.Dict and Anim.Name and LoadAnim(Anim.Dict) then
        TaskPlayAnim(Ped, Anim.Dict, Anim.Name, 8.0, 8.0, -1, Anim.Flags or 1, 1.0, false, false, false)
        return 'anim'
    elseif Anim.Scenario then
        TaskStartScenarioInPlace(Ped, Anim.Scenario, 0, true)
        return 'scenario'
    end
    return false
end

local function StopAction()
    local Ped = _PlayerPedId()
    DeleteActionProp()
    StopActionSound()
    ClearPedTasks(Ped)
    FreezeEntityPosition(Ped, false)
    SetBlocked(false)
    Active = false
    CloseProgress()
end

-----------------------------------------------------------------------------------------------------------------------------------------
-- START LOCATION
-----------------------------------------------------------------------------------------------------------------------------------------
local function StartLocation(Location, idx)
    CreateThread(function()
        local Ped = _PlayerPedId()
        if not CanUse(Ped) then return end

        local Response = ServerCall('StartAction', Location.Id, Location.Type)
        if not Response then return end

        local Config   = TypeConfig(Location.Type)
        local Duration = tonumber(Response.Duration) or Config.DefaultDuration or 10000
        local Finished = false
        local Timer    = GetGameTimer() + Duration

        Active = true
        SetBlocked(true)
        FreezeEntityPosition(Ped, true)
        local AnimMode = PlayAction(Location, idx)
        CreateActionProp(Config)
        StartActionSound(Config)
        Progress(Config.ProgressLabel or Config.Label, Duration, Location.Type)

        CreateThread(function()
            while Active and GetGameTimer() < Timer do
                DisableControlAction(0, 18,  true)
                DisableControlAction(0, 24,  true)
                DisableControlAction(0, 25,  true)
                DisableControlAction(0, 30,  true)
                DisableControlAction(0, 31,  true)
                DisableControlAction(0, 75,  true)
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                DisablePlayerFiring(Ped, true)
                if _IsControlJustPressed(0, BathSleep.Keys.Cancel) or _GetEntityHealth(Ped) <= 100 then
                    TriggerServerEvent('banho_dormir:sv:CancelAction')
                    StopAction()
                    Notify('Banho e Dormir', 'Acao cancelada.', 'amarelo', 4000)
                    return
                end
                if AnimMode == 'anim' and not IsEntityPlayingAnim(Ped, Config.Animation.Dict or '', Config.Animation.Name or '', 3) then
                    PlayAction(Location, idx)
                end
                Wait(0)
            end

            if Active then Finished = true end
            StopAction()

            if Finished then
                local Effects = ServerCall('FinishAction', Location.Id, Location.Type)
                if Effects then
                    ApplyHealth(Effects.Health)
                    Notify(Response.Name, Config.Label .. ' concluido.', 'verde', 5000)
                end
            end
        end)
    end)
end

-----------------------------------------------------------------------------------------------------------------------------------------
-- EVENTOS DO SERVIDOR
-----------------------------------------------------------------------------------------------------------------------------------------
RegisterNetEvent('banho_dormir:Sync', function(Data)
    Locations = type(Data) == 'table' and Data or {}
    RebuildLocationCoords()
    if Panel then SendNUIMessage({ Action = 'Refresh', Payload = { Locations = Locations } }) end
end)

RegisterNetEvent('banho_dormir:Notify', function(Title, Message, Type, Time)
    Notify(Title, Message, Type, Time)
end)

RegisterNetEvent('banho_dormir:cb', function(id, data)
    -- handlers via AddEventHandler no ServerCall
end)

RegisterNetEvent('banho_dormir:LoadNeeds', function(dirt, sleep)
    SetDirtState(tonumber(dirt)  or 0)
    Sleep = mmax(0, mmin(100, tonumber(sleep) or 0))
end)

RegisterNetEvent('banho_dormir:ResetNeed', function(needType)
    if needType == 'bath' then
        SetDirtState(0)
        StopFlies()
        dirtNotifyThreshold = 0
    elseif needType == 'sleep' then
        Sleep = 0
        sleepNotifyThreshold = 0
    end
    SetVisualEffect('', 0)
end)

-----------------------------------------------------------------------------------------------------------------------------------------
-- INIT
-----------------------------------------------------------------------------------------------------------------------------------------
CreateThread(function()
    Wait(1000)
    Locations = ServerCall('Locations') or {}
    RebuildLocationCoords()
end)

-----------------------------------------------------------------------------------------------------------------------------------------
-- THREAD MARKERS + NOJO
-- Padrão do guia de otimização: thread lenta filtra, thread rápida desenha
-- Fonte: gist.github.com/nnsdev + electron-services.com/blog/posts/optimization
-----------------------------------------------------------------------------------------------------------------------------------------
local nearbyLocations = {}  -- locations dentro do DrawDistance (filtradas a cada 500ms)
local nearInteract    = nil -- location dentro do InteractDistance

-- Thread lenta: filtra locations próximas a cada 500ms
CreateThread(function()
    local nauseaCheck = 0
    while true do
        local Ped      = _PlayerPedId()
        local myCoords = _GetEntityCoords(Ped)
        nearbyLocations = {}
        nearInteract    = nil

        for i, Location in ipairs(Locations) do
            if Location.Enabled then
                local dist = #(myCoords - LocationCoords[i])
                if dist <= BathSleep.Marker.DrawDistance then
                    nearbyLocations[#nearbyLocations + 1] = { loc = Location, idx = i, dist = dist }
                    if dist <= BathSleep.Marker.InteractDistance then
                        nearInteract = { loc = Location, idx = i }
                    end
                end
            end
        end

        -- Nojo a cada 3s
        local now = GetGameTimer()
        if now >= nauseaCheck then
            nauseaCheck = now + 3000
            CheckNausea(myCoords)
        end

        Wait(500)
    end
end)

-- Thread rápida: só desenha o que foi filtrado
CreateThread(function()
    while true do
        if #nearbyLocations > 0 then
            for _, entry in ipairs(nearbyLocations) do
                local Location = entry.loc
                local pos      = LocationCoords[entry.idx]
                local Config   = TypeConfig(Location.Type)
                local Color    = Location.Type == 'sleep' and BathSleep.Marker.SleepColor or BathSleep.Marker.BathColor

                _DrawMarker(BathSleep.Marker.Type,
                    pos.x, pos.y, pos.z + 0.35,
                    0, 0, 0, 0, 0, 0,
                    BathSleep.Marker.Scale.x, BathSleep.Marker.Scale.y, BathSleep.Marker.Scale.z,
                    Color[1], Color[2], Color[3], Color[4],
                    false, false, 2, false, nil, nil, false)

                DrawText3D(pos.x, pos.y, pos.z + 0.72, '~g~' .. Config.Label .. '~w~ - ' .. Location.Name)
            end

            if nearInteract then
                HelpText('Pressione ~INPUT_CONTEXT~ para ' .. TypeConfig(nearInteract.loc.Type).Verb .. '.')
                if _IsControlJustPressed(0, BathSleep.Keys.Interact) then
                    StartLocation(nearInteract.loc, nearInteract.idx)
                end
            end

            Wait(0)
        else
            Wait(500)
        end
    end
end)

-----------------------------------------------------------------------------------------------------------------------------------------
-- THREAD DETECÇÃO DE SUJEIRA (Wait 1000)
-- Raycast de material separado via timer interno (pesado, a cada 3s)
-----------------------------------------------------------------------------------------------------------------------------------------
local mudMaterials = {
    [0x8EDF9A3B] = true, [0xAD6A0B01] = true,
    [0x95BB4C37] = true, [0xB4F8A219] = true, [0x9A4B057A] = true,
}
local mudCheck = 0

CreateThread(function()
    while true do
        Wait(1000)
        if LocalPlayer.state.Dead then goto continue end

        local Ped = _PlayerPedId()

        -- Ragdoll
        local isRagdoll = _IsPedRagdoll(Ped)
        if isRagdoll and not lastRagdoll then AddDirt(15) end
        lastRagdoll = isRagdoll

        -- Dano
        local hp = _GetEntityHealth(Ped)
        if hp < lastHealth and (lastHealth - hp) >= 5 then AddDirt(10) end
        lastHealth = hp

        -- Água
        if _IsPedSwimming(Ped) or _IsEntityInWater(Ped) then AddDirt(5) end

        -- Lama/terra a cada 3s
        local now = GetGameTimer()
        if now >= mudCheck then
            mudCheck = now + 3000
            if _IsPedWalking(Ped) or _IsPedRunning(Ped) or _IsPedSprinting(Ped) then
                local pos = _GetEntityCoords(Ped)
                local ray = StartShapeTestRay(pos.x, pos.y, pos.z, pos.x, pos.y, pos.z - 1.2, 17, Ped, 7)
                local _, hit, _, _, material = GetShapeTestResultIncludingMaterial(ray)
                if hit == 1 and mudMaterials[material] then AddDirt(3) end
            end
        end

        ::continue::
    end
end)

-----------------------------------------------------------------------------------------------------------------------------------------
-- THREAD SONO (+1 a cada 54s = 100% em 1h30)
-----------------------------------------------------------------------------------------------------------------------------------------
local sleepMsgs = {
    [50] = { 'Voce esta com sono. Durma em breve.',        'inform' },
    [75] = { 'Voce esta muito cansado! Precisa dormir.',    'error'  },
    [90] = { 'Voce esta exausto! Durma agora!',             'error'  },
}

CreateThread(function()
    while true do
        Wait(54000)
        if LocalPlayer.state.Dead then goto continue end

        Sleep = mmin(100, Sleep + 1)
        TriggerServerEvent('banho_dormir:sv:UpdateNeeds', Dirt, Sleep)

        local threshold = Sleep >= 90 and 90 or Sleep >= 75 and 75 or Sleep >= 50 and 50 or 0
        if threshold > 0 and threshold ~= sleepNotifyThreshold then
            sleepNotifyThreshold = threshold
            lib.notify({ title = 'Cansaco', description = sleepMsgs[threshold][1], type = sleepMsgs[threshold][2], duration = 6000 })
        end

        ::continue::
    end
end)

-----------------------------------------------------------------------------------------------------------------------------------------
-- THREAD EFEITOS VISUAIS + STRESS + MOSCAS (unificada a cada 5s)
-----------------------------------------------------------------------------------------------------------------------------------------
CreateThread(function()
    local stressTimer = GetGameTimer()

    while true do
        Wait(5000)
        if LocalPlayer.state.Dead then
            SetVisualEffect('', 0)
            StopFlies()
            goto continue
        end

        local dirtLevel  = Dirt
        local sleepLevel = Sleep
        local Ped        = _PlayerPedId()

        -- Efeito visual por prioridade
        if nauseaActive then
            SetVisualEffect('nausea', 1.0)
        elseif dirtLevel >= 40 then
            SetVisualEffect('dirt', (dirtLevel - 40) / 60 * 0.6)
        elseif sleepLevel >= 50 then
            SetVisualEffect('sleep', (sleepLevel - 50) / 50 * 0.5)
        else
            SetVisualEffect('', 0)
        end

        -- Moscas: só muda quando cruza threshold
        if dirtLevel >= 85 and not flyThread then
            StartFlies(Ped)
        elseif dirtLevel < 85 and flyActive then
            StopFlies()
        end

        -- Stress a cada 60s
        local now = GetGameTimer()
        if now >= stressTimer then
            stressTimer = now + 60000
            local combined = mmax(dirtLevel, sleepLevel)
            if combined >= 30 then
                TriggerServerEvent('banho_dormir:sv:ApplyStress', combined)
            end
        end

        ::continue::
    end
end)

-----------------------------------------------------------------------------------------------------------------------------------------
-- PANEL
-----------------------------------------------------------------------------------------------------------------------------------------
local function OpenPanel()
    if Panel then return end
    local Data = ServerCall('Panel')
    if not Data then return end
    Panel = true
    SetNuiFocus(true, true)
    SendNUIMessage({ Action = 'Open', Payload = Data })
end

RegisterCommand(BathSleep.Commands.Panel, function()
    CreateThread(function() OpenPanel() end)
end)

-----------------------------------------------------------------------------------------------------------------------------------------
-- NUI CALLBACKS
-----------------------------------------------------------------------------------------------------------------------------------------
RegisterNUICallback('Close', function(Data, Callback)
    Panel = false
    SetNuiFocus(false, false)
    SendNUIMessage({ Action = 'Close' })
    Callback('Ok')
end)

RegisterNUICallback('CurrentPosition', function(Data, Callback)
    local Ped = _PlayerPedId()
    local pos = _GetEntityCoords(Ped)
    Callback({
        x = tonumber(string.format('%.2f', pos.x)),
        y = tonumber(string.format('%.2f', pos.y)),
        z = tonumber(string.format('%.2f', pos.z)),
        w = tonumber(string.format('%.2f', GetEntityHeading(Ped)))
    })
end)

RegisterNUICallback('SaveLocation', function(Data, Callback)
    CreateThread(function()
        local Response = ServerCall('SaveLocation', Data)
        if Response and Response.Locations then
            Locations = Response.Locations
            RebuildLocationCoords()
        end
        Callback(Response or false)
    end)
end)

RegisterNUICallback('DeleteLocation', function(Data, Callback)
    CreateThread(function()
        local Response = ServerCall('DeleteLocation', Data and Data.Id)
        if Response and Response.Locations then
            Locations = Response.Locations
            RebuildLocationCoords()
        end
        Callback(Response or false)
    end)
end)

-----------------------------------------------------------------------------------------------------------------------------------------
-- COMANDO DE TESTE (remova em produção)
-----------------------------------------------------------------------------------------------------------------------------------------
RegisterCommand(BathSleep.TestCommand, function(source, args)
    CreateThread(function()
        local dirt  = tonumber(args[1])
        local sleep = tonumber(args[2])

        if dirt  then SetDirtState(mmax(0, mmin(100, dirt))) end
        if sleep then Sleep = mmax(0, mmin(100, sleep)) end

        TriggerServerEvent('banho_dormir:sv:UpdateNeeds', Dirt, Sleep)

        local dirtLevel  = Dirt
        local sleepLevel = Sleep
        local Ped        = _PlayerPedId()

        -- Aplica efeitos imediatamente
        if nauseaActive then
            SetVisualEffect('nausea', 1.0)
        elseif dirtLevel >= 40 then
            SetVisualEffect('dirt', (dirtLevel - 40) / 60 * 0.6)
        elseif sleepLevel >= 50 then
            SetVisualEffect('sleep', (sleepLevel - 50) / 50 * 0.5)
        else
            SetVisualEffect('', 0)
        end

        if dirtLevel >= 85 and not flyThread then
            StartFlies(Ped)
        elseif dirtLevel < 85 and flyActive then
            StopFlies()
        end

        lib.notify({
            title       = 'Teste',
            description = ('Sujeira: %d%% | Sono: %d%%'):format(mfloor(dirtLevel), mfloor(sleepLevel)),
            type        = 'inform',
            duration    = 4000
        })
    end)
end)
