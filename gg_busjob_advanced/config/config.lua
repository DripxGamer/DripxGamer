Config = {}

-- ─────────────────────────────────────────────────────────────
--  Geral
-- ─────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────
--  Idioma: pt | pt-br | en | es | fr | de | it
--  Muda aqui, ou no server.cfg com:  setr gg_busjob_advanced:locale en
--  Se não puseres nada, segue o idioma do ESX ou do QB, e só depois inglês.
-- ─────────────────────────────────────────────────────────────
local function pickLocale()
    local mine = GetConvar('gg_busjob_advanced:locale', '')
    if mine ~= '' then
        return mine
    end
    for _, convar in ipairs({ 'esx:locale', 'esx_locale', 'qb_locale', 'locale' }) do
        local value = GetConvar(convar, '')
        if value ~= '' then
            return value
        end
    end
    return 'en'
end

Config.Locale = (pickLocale():lower():gsub('_', '-'))

-- auto | qbx_core | qb-core | es_extended
-- Em 'auto' procura por esta ordem: qbx_core, qb-core, es_extended.
Config.Framework = GetConvar('gg_busjob_advanced:framework', 'auto')
Config.SpeedUnit = GetConvar('gg_busjob_advanced:speedUnit', 'kmh')     -- kmh | mph
Config.Currency = '$'
Config.PaymentAccount = 'bank'                                          -- bank | cash
Config.RewardMultiplier = 1.0
-- true escreve na consola do servidor cada paragem, cada pagamento e cada falha.
-- Deixa ligado até ter a certeza de que está tudo bem.
Config.Debug = true

Config.Key = 38                          -- E
Config.KeyLabel = 'E'                    -- letra mostrada no painel
Config.CancelKey = 73                    -- X (cancelar o embarque)
Config.CancelKeyLabel = 'X'
Config.InteractionDistance = 2.5
Config.DepotRadius = 8.0

-- ─────────────────────────────────────────────────────────────
--  Paragens
-- ─────────────────────────────────────────────────────────────
Config.StopRadius = 18.0
Config.StopSpeedLimit = 1.5
Config.FirstStopDelay = 20
Config.StopCooldown = 8
-- Cada paragem dura o que precisar: o mínimo, mais um tempo por pessoa, até ao máximo.
-- Acaba sempre logo que todos entraram ou saíram.
-- Entram e saem um de cada vez pela porta, por isso a paragem dura o que a
-- gente precisar: o mínimo, mais um tempo por cada pessoa que entra ou sai.
-- Acaba sempre logo que o último se senta ou desce.
Config.StopServiceTime = 24000           -- ms máximos de uma paragem
Config.StopServiceMin = 2500             -- ms mínimos
Config.StopServicePer = 2400             -- ms por pessoa a entrar ou a sair
-- Danos e multas nunca tiram mais de (1 - este valor) do pagamento base.
-- Com 0.65, o máximo descontado é 35%.
Config.MinimumConditionMultiplier = 0.65

-- ─────────────────────────────────────────────────────────────
--  Multas (medidas no servidor, o cliente não as consegue evitar)
-- ─────────────────────────────────────────────────────────────
Config.Penalties = {
    enabled = true,
    collision = {
        minDrop = 12.0,     -- vida da carroçaria perdida num segundo para contar como colisão (0-1000)
        base = 15,          -- multa mínima por colisão
        perPoint = 0.35,    -- $ extra por cada ponto de vida perdido
        max = 90,           -- multa máxima por colisão
        cooldown = 3,       -- segundos entre colisões (uma pancada não conta duas vezes)
    },
    speeding = {
        enabled = true,
        limit = 22.0,       -- m/s (~80 km/h)
        seconds = 4,        -- segundos seguidos acima do limite
        fine = 35,
        cooldown = 15,      -- segundos entre multas por velocidade
    },
}

-- ─────────────────────────────────────────────────────────────
--  Regresso à garagem
--  Depois de largar todos os passageiros, o turno só fecha (e só paga)
--  quando o autocarro for entregue aqui.
-- ─────────────────────────────────────────────────────────────
Config.Return = {
    enabled = true,
    coords = vector3(465.9, -644.5, 27.42),
    radius = 14.0,
}

-- ─────────────────────────────────────────────────────────────
--  Fim do turno
--  O autocarro NUNCA desaparece com o jogador lá dentro.
-- ─────────────────────────────────────────────────────────────
Config.Finish = {
    leaveSeconds = 45,       -- tempo que o jogador tem para sair antes de ser tirado do lugar
    graceSeconds = 15,       -- tempo mínimo que o autocarro fica no destino depois de pago
    hardCapSeconds = 180,    -- limite absoluto: depois disto o servidor apaga-o de qualquer forma
}

-- Se o motorista sair do autocarro a meio da rota, começa a contagem.
-- Se não voltar a tempo, o turno falha e a sequência volta a zero.
Config.ExitTimer = {
    enabled = true,
    seconds = 45,
}

-- ─────────────────────────────────────────────────────────────
--  Histórico (últimas rotas mostradas no terminal)
-- ─────────────────────────────────────────────────────────────
Config.History = {
    limit = 12,             -- quantas rotas aparecem no terminal
    keep = 40,              -- quantas se guardam por motorista na base de dados
}

-- ─────────────────────────────────────────────────────────────
--  Recompensa diária
-- ─────────────────────────────────────────────────────────────
Config.DailyJobsRequired = 5
Config.DailyReward = {
    money = 1000,
    experience = 250,
}

-- ─────────────────────────────────────────────────────────────
--  Bónus de pagamento
--  Pagamento final = base + bónus de tempo + bónus de sequência + gorjetas
--                    - multas e danos
-- ─────────────────────────────────────────────────────────────
Config.Bonuses = {
    parSpeed = 13.0,        -- m/s médios usados para calcular o tempo de referência (~47 km/h)
    parPadding = 60,        -- segundos extra no tempo de referência
    routeFactor = 1.35,     -- as ruas são mais longas do que a linha reta entre paragens
    timeBonusMax = 0.15,    -- +15% se terminares dentro do tempo de referência
    timeFalloff = 0.60,     -- o bónus chega a 0 quando passas 60% do tempo de referência
    streakPerRoute = 0.02,  -- +2% por cada rota seguida sem terminar o turno antes do fim
    streakMax = 0.20,       -- máximo de +20%
    perfectExperience = 1.10, -- +10% de XP numa rota de 5 estrelas
    tips = {
        enabled = true,
        min = 2,            -- gorjeta por passageiro (antes do fator de avaliação)
        max = 9,
        minRating = 3,      -- estrelas mínimas para receber gorjetas
    },
}

-- ─────────────────────────────────────────────────────────────
--  Passageiros (peds locais que esperam nas paragens e entram no autocarro)
-- ─────────────────────────────────────────────────────────────
Config.Passengers = {
    enabled = true,
    spawnDistance = 130.0,
    despawnDistance = 220.0,
    scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
    seated = true,                 -- os passageiros entram e sentam-se no autocarro (só o motorista os vê)
    alightAtPickup = 2,            -- quantos saem numa paragem de recolha (liberta lugares para os novos); 0 desliga
    seatWait = 3500,               -- ms à espera de um lugar livre antes de desistir e se desvanecer à porta
    boardSeat = 0,                 -- lugar ligado à porta da frente: é por aqui que todos entram e saem
    -- Portas que abrem na paragem. 1 = porta da frente do lado do passeio.
    -- NUNCA metas 4 nem 5: no GTA são o capô e a mala. Era isso que abria a mala.
    doors = { 1 },
    queueSpacing = 0.85,           -- espaço (m) entre cada um na bicha à porta
    enterTimeout = 9000,           -- ms que o jogo tem para meter um passageiro dentro
    enterRetries = 1,              -- tentativas extra se a porta estiver bloqueada
    -- Quando o jogo não consegue mesmo meter alguém pela porta a tempo:
    -- true (por omissão) apaga-o um instante à porta e ele aparece já sentado,
    -- sem se ver nenhum salto; false deixa-o simplesmente desaparecer à porta.
    seatQuietly = true,
    doorBone = 'door_pside_f',     -- osso da porta de entrada: é aí que se forma a bicha
    doorOffset = 1.0,              -- distância (m) à porta onde a bicha se encosta
    walkSpeed = 1.5,               -- 1.0 caminhar, 2.0 correr
    exitTimeout = 6000,            -- ms que o jogo tem para deixar sair um passageiro
    alightSpeed = 1.0,             -- velocidade a afastarem-se depois de saírem
    alightWalk = 7.0,              -- distância (m) que percorrem antes de desaparecerem
    alightLinger = 2000,           -- ms que ficam à vista depois de saírem
    models = {
        'a_m_y_business_01', 'a_f_y_business_01', 'a_m_y_hipster_01', 'a_f_y_hipster_01',
        'a_m_m_business_01', 'a_f_m_bevhills_01', 'a_m_y_stbla_01', 'a_f_y_tourist_01',
        'a_m_y_runner_01', 'a_f_y_fitness_01', 'a_m_y_vinewood_01', 'a_f_y_vinewood_01',
    },
}

-- ─────────────────────────────────────────────────────────────
--  Classificação (top motoristas)
-- ─────────────────────────────────────────────────────────────
Config.Ranking = {
    enabled = true,
    limit = 10,
    cacheSeconds = 60,
}

-- ─────────────────────────────────────────────────────────────
--  Interface
-- ─────────────────────────────────────────────────────────────
Config.UI = {
    backdrop = 'game',           -- game: vês o jogo por trás do terminal | scene: cenário noturno desenhado
    theme = 'amber',             -- cor do painel: amber | emerald | azure | violet | rose (cada jogador pode mudar no terminal)
    accent = '#ffb020',          -- usada só se o theme não for reconhecido
    hudSide = 'right',           -- right | left (lista de paragens durante o turno)
    blur = true,                 -- desfoca o jogo quando o terminal está aberto
    ticketSeconds = 14,          -- tempo que o bilhete final fica no ecrã
    markerColor = { 255, 176, 32 },       -- paragens onde sobem passageiros
    dropoffColor = { 47, 208, 166 },      -- paragens onde descem (e o destino final)
    garageColor = { 130, 170, 255 },      -- entrega do autocarro na garagem
}

-- Conquistas: aparecem no perfil quando a estatística chega ao valor.
-- stat: completed | level | earned | perfect | bestStreak | passengers
Config.Badges = {
    { id = 'first',      stat = 'completed',  value = 1 },
    { id = 'regular',    stat = 'completed',  value = 25 },
    { id = 'veteran',    stat = 'completed',  value = 100 },
    { id = 'level5',     stat = 'level',      value = 5 },
    { id = 'level10',    stat = 'level',      value = 10 },
    { id = 'stars',      stat = 'perfect',    value = 10 },
    { id = 'streak',     stat = 'bestStreak', value = 10 },
    { id = 'crowd',      stat = 'passengers', value = 500 },
    { id = 'bank',       stat = 'earned',     value = 50000 },
}

-- ─────────────────────────────────────────────────────────────
--  Terminal
-- ─────────────────────────────────────────────────────────────
Config.Depot = {
    label = 'Bus Depot',
    ped = 's_m_y_xmech_01',
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    coords = vector4(449.55, -650.86, 28.48, 260.34),
    blip = {
        enabled = true,
        sprite = 513,
        color = 83,
        scale = 0.8,
    },
    spawns = {
        vector4(457.56, -654.52, 28.64, 213.58),
        vector4(458.9, -648.49, 29.01, 214.19),
        vector4(459.3, -641.36, 29.29, 212.99),
        vector4(460.82, -635.32, 28.48, 213.58),
        vector4(461.7, -628.39, 28.49, 212.82),
        vector4(461.15, -619.72, 28.5, 213.08),
        vector4(462.08, -613.18, 28.49, 213.5),
        vector4(462.95, -606.41, 29.33, 213.97),
        vector4(466.78, -649.99, 28.98, 173.2),
        vector4(468.41, -636.34, 29.33, 173.2),
        vector4(470.94, -615.05, 29.33, 173.23),
    },
}

Config.Vehicles = {
    { model = 'coach', label = 'Coach', seats = 8, level = 1 },
    { model = 'bus', label = 'Bus', seats = 14, level = 6 },
    { model = 'airbus', label = 'Airbus', seats = 14, level = 6 },
}

Config.Levels = {
    [1] = 0,
    [2] = 500,
    [3] = 1500,
    [4] = 4000,
    [5] = 7500,
    [6] = 10000,
    [7] = 50000,
    [8] = 150000,
    [9] = 300000,
    [10] = 500000,
}

-- ─────────────────────────────────────────────────────────────
--  Chaves do autocarro
--  Corre no servidor logo que o autocarro está registado. Tenta todos os
--  sistemas conhecidos e escreve na consola do servidor o que conseguiu.
--  Se o teu não estiver aqui, acrescenta uma linha `try(...)`.
-- ─────────────────────────────────────────────────────────────
Config.GiveKeys = function(source, vehicle, plate)
    local resource = GetCurrentResourceName()
    local model = GetEntityModel(vehicle)
    local gave = {}

    -- Tenta uma chamada. Só conta se o recurso estiver a correr e nada rebentar.
    local function try(name, label, fn)
        if GetResourceState(name) ~= 'started' then
            return false
        end
        local ok, err = pcall(fn)
        if ok then
            gave[#gave + 1] = ('%s (%s)'):format(name, label)
            return true
        end
        if Config.Debug then
            print(('[%s] chaves: %s/%s falhou -> %s'):format(resource, name, label, tostring(err)))
        end
        return false
    end

    -- Qbox. A assinatura mudou entre versões, por isso tentam-se as duas.
    if GetResourceState('qbx_vehiclekeys') == 'started' then
        local _ = try('qbx_vehiclekeys', 'GiveKeys(src, veh)', function()
            exports.qbx_vehiclekeys:GiveKeys(source, vehicle)
        end) or try('qbx_vehiclekeys', 'GiveKeys(src, veh, true)', function()
            exports.qbx_vehiclekeys:GiveKeys(source, vehicle, true)
        end)
    end

    try('qb-vehiclekeys', 'SetOwner', function()
        TriggerClientEvent('vehiclekeys:client:SetOwner', source, plate)
    end)

    if GetResourceState('qs-vehiclekeys') == 'started' then
        local _ = try('qs-vehiclekeys', 'GiveServerKeys', function()
            exports['qs-vehiclekeys']:GiveServerKeys(source, plate, model, true)
        end) or try('qs-vehiclekeys', 'GiveKeys', function()
            exports['qs-vehiclekeys']:GiveKeys(source, plate)
        end)
    end

    try('wasabi_carlock', 'GiveKey', function()
        exports.wasabi_carlock:GiveKey(source, plate)
    end)

    try('Renewed-Vehiclekeys', 'addKey', function()
        exports['Renewed-Vehiclekeys']:addKey(source, plate)
    end)

    if GetResourceState('MrNewbVehicleKeys') == 'started' then
        local _ = try('MrNewbVehicleKeys', 'GiveKeys(src, veh)', function()
            exports.MrNewbVehicleKeys:GiveKeys(source, vehicle)
        end) or try('MrNewbVehicleKeys', 'GiveKeys(src, plate)', function()
            exports.MrNewbVehicleKeys:GiveKeys(source, plate)
        end)
    end

    try('t1ger_keys', 'GiveKeys', function()
        exports.t1ger_keys:GiveKeys(source, plate, model)
    end)

    try('vehicles_keys', 'SetOwner', function()
        TriggerClientEvent('vehicles_keys:client:SetOwner', source, plate)
    end)

    try('okokGarage', 'GiveKeys', function()
        TriggerClientEvent('okokGarage:GiveKeys', source, plate)
    end)

    try('cd_garage', 'AddKeys', function()
        TriggerClientEvent('cd_garage:AddKeys', source, plate)
    end)

    if #gave > 0 then
        if Config.Debug then
            print(('[%s] chaves do %s entregues por: %s'):format(resource, plate, table.concat(gave, ', ')))
        end
        return
    end

    -- Nenhum sistema pegou. Diz quais é que estão a correr, para se saber qual falta.
    local running = {}
    for index = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(index)
        if name and GetResourceState(name) == 'started' then
            local lower = name:lower()
            if lower:find('key') or lower:find('lock') or lower:find('garage') then
                running[#running + 1] = name
            end
        end
    end

    print(('[%s] NENHUM sistema de chaves respondeu. Recursos de chaves/garagem a correr: %s')
        :format(resource, #running > 0 and table.concat(running, ', ') or 'nenhum encontrado'))
    print(('[%s] Acrescenta o teu em Config.GiveKeys, em config/config.lua.'):format(resource))
end

-- Lado do cliente, para os sistemas que só reagem aqui. Corre logo a seguir.
Config.GiveKeysClient = function(vehicle, plate)
    local function try(name, fn)
        if GetResourceState(name) == 'started' then
            pcall(fn)
        end
    end

    -- qb-vehiclekeys e compatíveis ouvem este evento no cliente
    TriggerEvent('vehiclekeys:client:SetOwner', plate)
    TriggerEvent('vehicles_keys:client:SetOwner', plate)

    try('qbx_vehiclekeys', function() exports.qbx_vehiclekeys:GiveKeys(vehicle) end)
    try('qs-vehiclekeys', function()
        exports['qs-vehiclekeys']:GiveKeys(plate, GetEntityModel(vehicle), true)
    end)
end
