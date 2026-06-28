-----------------------------------------------------------------------------------------------------------------------------------------
-- BANHO E DORMIR - SERVER SIDE (QBX / MriqBox)
-----------------------------------------------------------------------------------------------------------------------------------------
local Loaded    = false
local Locations = {}
local Active    = {}

-- Cache de needs em memória para evitar MySQL a cada evento de dano
local NeedsCache  = {}  -- [citizenid] = { dirt, sleep, dirty = true/false }
local SaveCooldown = {} -- [citizenid] = timestamp última gravação
local SAVE_INTERVAL = 30 -- segundos mínimos entre gravações no banco
-----------------------------------------------------------------------------------------------------------------------------------------
-- BASIC
-----------------------------------------------------------------------------------------------------------------------------------------
local function Notify(source, Title, Message, Type, Time)
    if source and source > 0 then
        TriggerClientEvent('banho_dormir:Notify', source, Title, Message, Type or 'amarelo', Time or 5000)
    end
end

local function DeepCopy(Value)
    if type(Value) ~= 'table' then return Value end
    local Copy = {}
    for Key, Data in pairs(Value) do Copy[Key] = DeepCopy(Data) end
    return Copy
end

local function CleanText(Value, Default, Limit)
    local Text = tostring(Value or Default or '')
    Text = Text:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if Limit and #Text > Limit then Text = Text:sub(1, Limit) end
    return Text
end

local function IsAdmin(source)
    if not source then return false end

    if GetResourceState('qbx_core') == 'started' and exports.qbx_core then
        local player = exports.qbx_core:GetPlayer(source)
        if player and player.Functions and player.Functions.HasPermission then
            if player.Functions.HasPermission('god') or player.Functions.HasPermission('admin') then
                return true
            end
        end
    end

    if GetResourceState('qb-core') == 'started' then
        local QBCore = exports['qb-core']:GetCoreObject()
        if QBCore and QBCore.Functions and QBCore.Functions.HasPermission then
            if QBCore.Functions.HasPermission(source, 'god') or
               QBCore.Functions.HasPermission(source, 'admin') then
                return true
            end
        end
    end

    return IsPlayerAceAllowed(tostring(source), 'group.admin') or
           IsPlayerAceAllowed(tostring(source), 'admin')
end

local function Number(Value, Default, Min, Max)
    local Result = tonumber(Value) or Default or 0
    if Min then Result = math.max(Min, Result) end
    if Max then Result = math.min(Max, Result) end
    return Result
end

local function Effects(Type, Data)
    local Defaults = BathSleep.Types[Type] and BathSleep.Types[Type].Effects or {}
    Data = type(Data) == 'table' and Data or {}
    return {
        Health = Number(Data.Health, Defaults.Health or 0, 0, 100),
        Hunger = Number(Data.Hunger, Defaults.Hunger or 0, 0, 100),
        Thirst = Number(Data.Thirst, Defaults.Thirst or 0, 0, 100),
        Stress = Number(Data.Stress, Defaults.Stress or 0, 0, 100)
    }
end

local function Normalize(Location)
    if type(Location) ~= 'table' or not BathSleep.Types[Location.Type] then return false end
    local Type   = Location.Type
    local Config = BathSleep.Types[Type]
    local Coords = type(Location.Coords) == 'table' and Location.Coords or {}
    local Id     = CleanText(Location.Id, Type .. '-' .. os.time() .. math.random(100, 999), 40)
    local Name   = CleanText(Location.Name, Config.Label, 48)
    if Id   == '' then Id   = Type .. '-' .. os.time() .. math.random(100, 999) end
    if Name == '' then Name = Config.Label end
    return {
        Id       = Id,
        Type     = Type,
        Name     = Name,
        Coords   = {
            x = Number(Coords.x or Location.x, 0),
            y = Number(Coords.y or Location.y, 0),
            z = Number(Coords.z or Location.z, 0),
            w = Number(Coords.w or Location.w or Location.Heading, 0, 0, 360)
        },
        Duration = math.floor(Number(Location.Duration, Config.DefaultDuration or 10000, 3000, 120000)),
        Price    = math.floor(Number(Location.Price,    Config.DefaultPrice    or 0,     0, 100000000)),
        Reward   = math.floor(Number(Location.Reward or Location.Payment, Config.DefaultReward or 0, 0, BathSleep.MaxReward or 100000000)),
        Effects  = Effects(Type, Location.Effects),
        Enabled  = Location.Enabled ~= false
    }
end
-----------------------------------------------------------------------------------------------------------------------------------------
-- PERSISTÊNCIA DE LOCAIS
-----------------------------------------------------------------------------------------------------------------------------------------
local function LoadLocations()
    if Loaded then return Locations end
    local Result = MySQL.scalar.await('SELECT `data` FROM `banho_dormir_locations` WHERE `id` = 1')
    local Stored = Result and json.decode(Result)
    if type(Stored) ~= 'table' or #Stored == 0 then
        Stored = DeepCopy(BathSleep.DefaultLocations)
    end
    Locations = {}
    for _, Location in ipairs(Stored) do
        local Normalized = Normalize(Location)
        if Normalized then Locations[#Locations + 1] = Normalized end
    end
    Loaded = true
    return Locations
end

local function SaveLocations()
    MySQL.update.await(
        'INSERT INTO `banho_dormir_locations` (`id`, `data`) VALUES (1, ?) ON DUPLICATE KEY UPDATE `data` = ?',
        { json.encode(Locations), json.encode(Locations) }
    )
    TriggerClientEvent('banho_dormir:Sync', -1, Locations)
end

local function FindLocation(Id, Type)
    LoadLocations()
    for Index, Location in ipairs(Locations) do
        if Location.Id == Id and (not Type or Location.Type == Type) then
            return Location, Index
        end
    end
    return false, false
end
-----------------------------------------------------------------------------------------------------------------------------------------
-- PERSISTÊNCIA DE NECESSIDADES (com cache em memória + gravação com cooldown)
-----------------------------------------------------------------------------------------------------------------------------------------
local function GetCitizenId(source)
    local Player = exports.qbx_core:GetPlayer(source)
    return Player and Player.PlayerData.citizenid or nil
end

local function FlushNeeds(citizenid)
    local cache = NeedsCache[citizenid]
    if not cache or not cache.dirty then return end
    cache.dirty = false
    MySQL.update.await(
        'INSERT INTO `banho_dormir_needs` (`citizenid`, `dirt`, `sleep`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `dirt` = ?, `sleep` = ?',
        { citizenid, cache.dirt, cache.sleep, cache.dirt, cache.sleep }
    )
end

local function UpdateNeedsCache(citizenid, dirt, sleep, forceFlush)
    if not citizenid then return end
    NeedsCache[citizenid] = NeedsCache[citizenid] or { dirt = 0, sleep = 0, dirty = false }
    local cache = NeedsCache[citizenid]
    cache.dirt  = math.max(0, math.min(100, dirt))
    cache.sleep = math.max(0, math.min(100, sleep))
    cache.dirty = true

    local now = os.time()
    if forceFlush or not SaveCooldown[citizenid] or (now - SaveCooldown[citizenid]) >= SAVE_INTERVAL then
        SaveCooldown[citizenid] = now
        FlushNeeds(citizenid)
    end
end
-----------------------------------------------------------------------------------------------------------------------------------------
-- CALLBACKS
-----------------------------------------------------------------------------------------------------------------------------------------
RegisterNetEvent('banho_dormir:sv:Locations', function(cbId)
    local source = source
    TriggerClientEvent('banho_dormir:cb', source, cbId, LoadLocations())
end)

RegisterNetEvent('banho_dormir:sv:Panel', function(cbId)
    local source = source
    if not IsAdmin(source) then
        Notify(source, 'Banho e Dormir', 'Voce nao possui permissao.', 'vermelho', 5000)
        TriggerClientEvent('banho_dormir:cb', source, cbId, false)
        return
    end
    TriggerClientEvent('banho_dormir:cb', source, cbId, { Locations = LoadLocations(), Types = BathSleep.Types })
end)

RegisterNetEvent('banho_dormir:sv:SaveLocation', function(cbId, Data)
    local source = source
    if not IsAdmin(source) then
        Notify(source, 'Banho e Dormir', 'Voce nao possui permissao.', 'vermelho', 5000)
        TriggerClientEvent('banho_dormir:cb', source, cbId, false)
        return
    end
    local Location = Normalize(Data)
    if not Location then
        Notify(source, 'Banho e Dormir', 'Dados invalidos.', 'vermelho', 5000)
        TriggerClientEvent('banho_dormir:cb', source, cbId, false)
        return
    end
    local _, Index = FindLocation(Location.Id)
    if Index then Locations[Index] = Location
    else Locations[#Locations + 1] = Location end
    SaveLocations()
    Notify(source, 'Banho e Dormir', 'Local salvo com sucesso.', 'verde', 5000)
    TriggerClientEvent('banho_dormir:cb', source, cbId, { Locations = Locations, Location = Location })
end)

RegisterNetEvent('banho_dormir:sv:DeleteLocation', function(cbId, Id)
    local source = source
    if not IsAdmin(source) then
        Notify(source, 'Banho e Dormir', 'Voce nao possui permissao.', 'vermelho', 5000)
        TriggerClientEvent('banho_dormir:cb', source, cbId, false)
        return
    end
    local _, Index = FindLocation(tostring(Id or ''))
    if not Index then
        Notify(source, 'Banho e Dormir', 'Local nao encontrado.', 'amarelo', 5000)
        TriggerClientEvent('banho_dormir:cb', source, cbId, false)
        return
    end
    table.remove(Locations, Index)
    SaveLocations()
    Notify(source, 'Banho e Dormir', 'Local removido.', 'verde', 5000)
    TriggerClientEvent('banho_dormir:cb', source, cbId, { Locations = Locations })
end)

RegisterNetEvent('banho_dormir:sv:StartAction', function(cbId, Id, Type)
    local source   = source
    local Player   = exports.qbx_core:GetPlayer(source)
    local Location = FindLocation(tostring(Id or ''), tostring(Type or ''))

    if not Player or not Location or not Location.Enabled then
        TriggerClientEvent('banho_dormir:cb', source, cbId, false)
        return
    end

    if Location.Price > 0 then
        local Money = Player.PlayerData.money['cash'] or 0
        if Money < Location.Price then
            Notify(source, Location.Name, 'Voce nao possui dinheiro suficiente.', 'vermelho', 5000)
            TriggerClientEvent('banho_dormir:cb', source, cbId, false)
            return
        end
        Player.Functions.RemoveMoney('cash', Location.Price, 'banho-dormir-pagamento')
    end

    local Seconds  = math.ceil(Location.Duration / 1000)
    local Now      = os.time()
    Active[source] = {
        Id      = Location.Id,
        Type    = Location.Type,
        Finish  = Now + Seconds,
        Expires = Now + Seconds + 8
    }

    TriggerClientEvent('banho_dormir:cb', source, cbId, {
        Id       = Location.Id,
        Type     = Location.Type,
        Name     = Location.Name,
        Duration = Location.Duration,
        Price    = Location.Price,
        Reward   = Location.Reward,
        Effects  = Location.Effects
    })
end)

RegisterNetEvent('banho_dormir:sv:FinishAction', function(cbId, Id, Type)
    local source  = source
    local Player  = exports.qbx_core:GetPlayer(source)
    local Current = Active[source]
    local Now     = os.time()

    if not Player or not Current or Current.Id ~= Id or Current.Type ~= Type
        or Now < Current.Finish or Now > Current.Expires then
        Active[source] = nil
        TriggerClientEvent('banho_dormir:cb', source, cbId, false)
        return
    end

    local Location = FindLocation(Id, Type)
    if not Location then
        Active[source] = nil
        TriggerClientEvent('banho_dormir:cb', source, cbId, false)
        return
    end

    local Fx = Location.Effects or {}

    if (Fx.Hunger or 0) > 0 then
        local v = Player.PlayerData.metadata['hunger'] or 0
        Player.Functions.SetMetaData('hunger', math.min(100, v + Fx.Hunger))
    end
    if (Fx.Thirst or 0) > 0 then
        local v = Player.PlayerData.metadata['thirst'] or 0
        Player.Functions.SetMetaData('thirst', math.min(100, v + Fx.Thirst))
    end
    if (Fx.Stress or 0) > 0 then
        local v = Player.PlayerData.metadata['stress'] or 100
        Player.Functions.SetMetaData('stress', math.max(0, v - Fx.Stress))
    end

    local Reward = tonumber(Location.Reward) or 0
    if Reward > 0 then
        Player.Functions.AddMoney('cash', Reward, 'banho-dormir-recompensa')
    end

    local Response = DeepCopy(Fx)
    Response.Reward = Reward
    Active[source]  = nil

    -- Zera necessidade no cache e força flush imediato
    local citizenid = Player.PlayerData.citizenid
    local cache = NeedsCache[citizenid] or { dirt = 0, sleep = 0 }
    if Type == 'bath' then
        UpdateNeedsCache(citizenid, 0, cache.sleep, true)
    elseif Type == 'sleep' then
        UpdateNeedsCache(citizenid, cache.dirt, 0, true)
    end

    TriggerClientEvent('banho_dormir:ResetNeed', source, Type)
    TriggerClientEvent('banho_dormir:cb', source, cbId, Response)
end)

RegisterNetEvent('banho_dormir:sv:CancelAction', function()
    Active[source] = nil
end)
-----------------------------------------------------------------------------------------------------------------------------------------
-- NECESSIDADES
-----------------------------------------------------------------------------------------------------------------------------------------

-- Atualiza cache (gravação no banco com cooldown de 30s)
RegisterNetEvent('banho_dormir:sv:UpdateNeeds', function(dirt, sleep)
    local src       = source
    local citizenid = GetCitizenId(src)
    if not citizenid then return end
    UpdateNeedsCache(citizenid,
        math.max(0, math.min(100, tonumber(dirt)  or 0)),
        math.max(0, math.min(100, tonumber(sleep) or 0)),
        false
    )
end)

-- Aplica stress proporcionalmente
RegisterNetEvent('banho_dormir:sv:ApplyStress', function(level)
    local src    = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local gain = math.floor((level / 100) * 3)
    if gain <= 0 then return end
    local current = Player.PlayerData.metadata['stress'] or 0
    Player.Functions.SetMetaData('stress', math.min(100, current + gain))
end)

-- Carrega necessidades ao entrar (evento do QBX)
AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local src       = Player.PlayerData.source
    local citizenid = Player.PlayerData.citizenid
    local result    = MySQL.single.await('SELECT `dirt`, `sleep` FROM `banho_dormir_needs` WHERE `citizenid` = ?', { citizenid })
    local dirt      = result and tonumber(result.dirt)  or 0
    local sleep     = result and tonumber(result.sleep) or 0
    NeedsCache[citizenid] = { dirt = dirt, sleep = sleep, dirty = false }
    TriggerClientEvent('banho_dormir:LoadNeeds', src, dirt, sleep)
end)

-- Também escuta evento do qbx_core caso o servidor use ele
AddEventHandler('qbx_core:server:playerLoaded', function(Player)
    local src       = Player.PlayerData.source
    local citizenid = Player.PlayerData.citizenid
    if NeedsCache[citizenid] then return end  -- já carregou pelo outro evento
    local result = MySQL.single.await('SELECT `dirt`, `sleep` FROM `banho_dormir_needs` WHERE `citizenid` = ?', { citizenid })
    local dirt   = result and tonumber(result.dirt)  or 0
    local sleep  = result and tonumber(result.sleep) or 0
    NeedsCache[citizenid] = { dirt = dirt, sleep = sleep, dirty = false }
    TriggerClientEvent('banho_dormir:LoadNeeds', src, dirt, sleep)
end)
-----------------------------------------------------------------------------------------------------------------------------------------
-- PLAYER DROPPED — flush forçado ao sair
-----------------------------------------------------------------------------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local src       = source
    Active[src]     = nil
    local citizenid = GetCitizenId(src)
    if citizenid then
        FlushNeeds(citizenid)
        NeedsCache[citizenid]  = nil
        SaveCooldown[citizenid] = nil
    end
end)
