local TABLE = 'gg_busjob_advanced_profiles'
local HISTORY = 'gg_busjob_advanced_history'

local profiles = {}
local sessions = {}
local starting = {}
local databaseReady = false
local frameworkName
local qbCore
local ranking = { at = 0, rows = {} }

-- ─────────────────────────────────────────────────────────────
--  Framework
-- ─────────────────────────────────────────────────────────────
local function detectFramework()
    if Config.Framework == 'qbx_core' or Config.Framework == 'qb-core' then
        frameworkName = Config.Framework
    elseif GetResourceState('qbx_core') == 'started' then
        frameworkName = 'qbx_core'
    elseif GetResourceState('qb-core') == 'started' then
        frameworkName = 'qb-core'
    else
        error(('[%s] Start qbx_core or qb-core, or set gg_busjob_advanced:framework.'):format(GetCurrentResourceName()))
    end

    if frameworkName == 'qb-core' then
        qbCore = exports['qb-core']:GetCoreObject()
    end
end

local function getPlayer(source)
    if frameworkName == 'qbx_core' then
        return exports.qbx_core:GetPlayer(source)
    end
    return qbCore.Functions.GetPlayer(source)
end

local function getIdentifier(player)
    local data = player and player.PlayerData
    return data and data.citizenid and tostring(data.citizenid) or nil
end

local function getCharacterName(player)
    local data = player and player.PlayerData
    local info = data and data.charinfo
    if info and info.firstname then
        local name = ('%s %s'):format(info.firstname, info.lastname or ''):gsub('%s+$', '')
        return name:sub(1, 48)
    end
    return 'Driver'
end

-- ─────────────────────────────────────────────────────────────
--  Níveis e dia
-- ─────────────────────────────────────────────────────────────
local function getLevel(experience)
    local level = 1
    for candidate, requirement in pairs(Config.Levels) do
        if experience >= requirement and candidate > level then
            level = candidate
        end
    end
    return level
end

local function currentDate()
    return os.date('!%Y-%m-%d')
end

local function resetDaily(profile)
    local today = currentDate()
    if profile.daily_date ~= today then
        profile.daily_date = today
        profile.daily_completed = 0
        profile.daily_claimed = false
    end
end

-- ─────────────────────────────────────────────────────────────
--  Base de dados
-- ─────────────────────────────────────────────────────────────
local function ensureColumn(column, definition)
    local exists = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
    ]], { TABLE, column })

    if tonumber(exists) == 0 then
        MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(TABLE, column, definition))
    end
end

local function saveProfile(identifier, profile)
    MySQL.query(([[
        INSERT INTO `%s`
            (citizenid, name, experience, completed, earned, daily_date, daily_completed, daily_claimed,
             streak, best_streak, rating_total, rated, perfect, passengers)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            name = VALUES(name),
            experience = VALUES(experience),
            completed = VALUES(completed),
            earned = VALUES(earned),
            daily_date = VALUES(daily_date),
            daily_completed = VALUES(daily_completed),
            daily_claimed = VALUES(daily_claimed),
            streak = VALUES(streak),
            best_streak = VALUES(best_streak),
            rating_total = VALUES(rating_total),
            rated = VALUES(rated),
            perfect = VALUES(perfect),
            passengers = VALUES(passengers)
    ]]):format(TABLE), {
        identifier,
        profile.name,
        profile.experience,
        profile.completed,
        profile.earned,
        profile.daily_date,
        profile.daily_completed,
        profile.daily_claimed and 1 or 0,
        profile.streak,
        profile.best_streak,
        profile.rating_total,
        profile.rated,
        profile.perfect,
        profile.passengers,
    })
end

local function getProfile(source)
    while not databaseReady do
        Wait(100)
    end

    local player = getPlayer(source)
    local identifier = getIdentifier(player)
    if not identifier then
        return nil, nil
    end

    local profile = profiles[identifier]
    if not profile then
        local row = MySQL.single.await(
            ('SELECT * FROM `%s` WHERE citizenid = ?'):format(TABLE),
            { identifier }
        )
        -- oxmysql pode devolver TINYINT(1) como número ou booleano, e BIGINT como texto.
        local function num(value)
            return tonumber(value) or 0
        end

        profile = {
            name = row and row.name or nil,
            experience = row and num(row.experience) or 0,
            completed = row and num(row.completed) or 0,
            earned = row and num(row.earned) or 0,
            daily_date = row and row.daily_date or currentDate(),
            daily_completed = row and num(row.daily_completed) or 0,
            daily_claimed = row ~= nil and (row.daily_claimed == 1 or row.daily_claimed == true or row.daily_claimed == '1'),
            streak = row and num(row.streak) or 0,
            best_streak = row and num(row.best_streak) or 0,
            rating_total = row and num(row.rating_total) or 0,
            rated = row and num(row.rated) or 0,
            perfect = row and num(row.perfect) or 0,
            passengers = row and num(row.passengers) or 0,
        }
        profiles[identifier] = profile
    end

    profile.name = getCharacterName(player)
    resetDaily(profile)
    return profile, identifier
end

local function profileResponse(profile)
    local level = getLevel(profile.experience)
    local streakBonus = math.min(Config.Bonuses.streakMax, profile.streak * Config.Bonuses.streakPerRoute)

    return {
        ok = true,
        name = profile.name,
        experience = profile.experience,
        level = level,
        levelExperience = Config.Levels[level],
        nextLevelExperience = Config.Levels[level + 1],
        completed = profile.completed,
        earned = profile.earned,
        passengers = profile.passengers,
        perfect = profile.perfect,
        streak = profile.streak,
        bestStreak = profile.best_streak,
        streakBonus = streakBonus,
        rating = profile.rated > 0 and (profile.rating_total / profile.rated) or 0,
        dailyCompleted = profile.daily_completed,
        dailyAvailable = profile.daily_completed >= Config.DailyJobsRequired and not profile.daily_claimed,
        dailyClaimed = profile.daily_claimed,
    }
end

-- ─────────────────────────────────────────────────────────────
--  Utilitários
-- ─────────────────────────────────────────────────────────────
local function getDepotPosition()
    local coords = Config.Depot.coords
    return vector3(coords.x, coords.y, coords.z)
end

local function isAtDepot(source, radius)
    local ped = GetPlayerPed(source)
    return ped ~= 0 and #(GetEntityCoords(ped) - getDepotPosition()) <= radius
end

local function findVehicle(model)
    for _, vehicle in ipairs(Config.Vehicles) do
        if vehicle.model == model then
            return vehicle
        end
    end
end

-- Escreve na consola do servidor o que se passa em cada turno (Config.Debug).
local function logShift(format, ...)
    if Config.Debug == false then
        return
    end
    print(('[%s] %s'):format(GetCurrentResourceName(), (select('#', ...) > 0) and format:format(...) or format))
end

-- Contas pela ordem em que se tenta pagar: a configurada e, se essa falhar, a outra.
local MONEY_ACCOUNTS = { Config.PaymentAccount, Config.PaymentAccount == 'cash' and 'bank' or 'cash' }

-- Uma tentativa numa conta. Tenta a API do objeto do jogador e, no Qbox, também o export.
local function tryAddMoney(source, account, amount, reason)
    local player = getPlayer(source)

    if player and player.Functions and type(player.Functions.AddMoney) == 'function' then
        local called, result = pcall(player.Functions.AddMoney, account, amount, reason)
        if called and result ~= false then
            return true, 'player.Functions.AddMoney'
        end
        if not called then
            logShift('AddMoney(%s) deu erro: %s', account, tostring(result))
        end
    end

    if frameworkName == 'qbx_core' then
        local called, result = pcall(function()
            return exports.qbx_core:AddMoney(source, account, amount, reason)
        end)
        if called and result ~= false then
            return true, 'exports.qbx_core:AddMoney'
        end
    end

    return false
end

-- Paga ao jogador. Tenta 3 vezes em cada conta antes de desistir.
-- Devolve: pago (bool), conta usada, como foi feito.
local function payPlayer(source, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        -- Nada a pagar não é uma falha: a rota conta como concluída.
        return true, Config.PaymentAccount, 'nada a pagar'
    end

    for _, account in ipairs(MONEY_ACCOUNTS) do
        for _ = 1, 3 do
            local ok, how = tryAddMoney(source, account, amount, reason)
            if ok then
                if account ~= Config.PaymentAccount then
                    logShift('Pagou %d em "%s" porque "%s" recusou.', amount, account, Config.PaymentAccount)
                end
                return true, account, how
            end
        end
    end

    return false
end

local function deleteSessionVehicle(session)
    if not session or not session.vehicleNetId then
        return
    end
    local vehicle = NetworkGetEntityFromNetworkId(session.vehicleNetId)
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        DeleteEntity(vehicle)
    end
end

-- Fim de turno: o autocarro só vai embora depois de o lugar do condutor estar vazio
-- (e nunca antes de `graceMs`). O limite `hardCapMs` evita autocarros abandonados.
local function retireSessionVehicle(session, graceMs, hardCapMs)
    local netId = session and session.vehicleNetId
    if not netId then
        return
    end

    local grace = graceMs or 15000
    local hardCap = math.max(hardCapMs or 180000, grace + 1000)

    CreateThread(function()
        local startedAt = GetGameTimer()
        while true do
            Wait(1000)
            local vehicle = NetworkGetEntityFromNetworkId(netId)
            if vehicle == 0 or not DoesEntityExist(vehicle) then
                return      -- já não existe (o cliente apagou-o)
            end

            local elapsed = GetGameTimer() - startedAt
            local empty = GetPedInVehicleSeat(vehicle, -1) == 0

            if (empty and elapsed >= grace) or elapsed >= hardCap then
                DeleteEntity(vehicle)
                return
            end
        end
    end)
end

-- graceMs: dá tempo ao jogador para sair do autocarro antes de ele desaparecer.
local function removeSession(source, graceMs)
    local session = sessions[source]
    if not session then
        return
    end
    sessions[source] = nil

    if graceMs and graceMs > 0 then
        retireSessionVehicle(session, graceMs, Config.Finish and Config.Finish.hardCapSeconds and Config.Finish.hardCapSeconds * 1000 or nil)
    else
        deleteSessionVehicle(session)
    end
end

local function makePlate()
    while true do
        local plate = ('BUS%05d'):format(math.random(0, 99999))
        local inUse = false
        for _, session in pairs(sessions) do
            if session.plate == plate then
                inUse = true
                break
            end
        end
        if not inUse then
            return plate
        end
    end
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

-- Os valores de LIMIT vão escritos na query (já validados como inteiros).
local function safeInt(value, fallback)
    return math.max(1, math.floor(tonumber(value) or fallback))
end

-- ─────────────────────────────────────────────────────────────
--  Histórico
-- ─────────────────────────────────────────────────────────────
local function addHistory(identifier, routeId, label, payment, penalty, stars, duration)
    MySQL.query(([[
        INSERT INTO `%s` (citizenid, route_id, route_label, payment, penalty, rating, duration)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]]):format(HISTORY), { identifier, routeId, label, payment, penalty, stars, duration }, function()
        -- Só guardamos as últimas rotas de cada motorista.
        MySQL.query(([[
            DELETE FROM `%s` WHERE citizenid = ? AND id NOT IN (
                SELECT id FROM (
                    SELECT id FROM `%s` WHERE citizenid = ? ORDER BY id DESC LIMIT %d
                ) AS keep_rows
            )
        ]]):format(HISTORY, HISTORY, safeInt(Config.History.keep, 40)), { identifier, identifier })
    end)
end

-- ─────────────────────────────────────────────────────────────
--  Vigilância do turno (corre no servidor, o cliente não decide nada)
--   · multas por colisão e por excesso de velocidade
--   · contagem decrescente quando o motorista sai do autocarro
-- ─────────────────────────────────────────────────────────────
local function failSession(source, reason)
    local session = sessions[source]
    if not session then
        return
    end

    -- Falhar o turno quebra a sequência.
    local profile = profiles[session.identifier]
    if profile and profile.streak > 0 then
        profile.streak = 0
        saveProfile(session.identifier, profile)
    end

    TriggerClientEvent('gg_busjob_advanced:routeFailed', source, reason)
    removeSession(source)
end

local function applyPenalty(source, session, kind, amount)
    local route = Config.Routes[session.routeId]
    local reward = route.rewards.money * Config.RewardMultiplier
    -- As multas nunca tiram mais do que o autocarro já poderia tirar por danos.
    local room = math.floor(reward * (1 - Config.MinimumConditionMultiplier)) - session.penalty
    amount = math.max(0, math.min(amount, room))

    session.penalty = session.penalty + amount
    session.counts[kind] = session.counts[kind] + 1

    TriggerClientEvent('gg_busjob_advanced:penalty', source, {
        kind = kind,
        amount = amount,
        total = session.penalty,
        collisions = session.counts.collision,
        speeding = session.counts.speeding,
    })
end

-- O lugar do condutor lido pelo servidor engana-se de vez em quando (sincronização).
-- Por isso pergunta-se das duas maneiras antes de dizer que o jogador saiu.
local function isDriving(source, session, vehicle)
    local ped = GetPlayerPed(source)
    if ped == 0 then
        return false
    end
    if GetPedInVehicleSeat(vehicle, -1) == ped then
        return true
    end
    -- Segunda opinião: em que veículo está o jogador?
    local inside = GetVehiclePedIsIn(ped, false)
    if inside ~= 0 and inside == vehicle then
        return true
    end
    if inside ~= 0 and session.vehicleNetId
        and NetworkGetNetworkIdFromEntity(inside) == session.vehicleNetId then
        return true
    end
    return false
end

local function watchDriver(source, session, vehicle, now)
    local exitTimer = Config.ExitTimer
    if not exitTimer.enabled then
        return true
    end

    local behindWheel = isDriving(source, session, vehicle)
    if behindWheel then
        session.seated = true
        if session.outSince then
            session.outSince = nil
            TriggerClientEvent('gg_busjob_advanced:exitTimer', source, false)
        end
        return true
    end

    -- Ainda nem chegou a sentar-se: não conta.
    if not session.seated then
        return true
    end

    if not session.outSince then
        session.outSince = now
        TriggerClientEvent('gg_busjob_advanced:exitTimer', source, exitTimer.seconds)
        return true
    end

    if now - session.outSince >= exitTimer.seconds then
        failSession(source, 'left_vehicle')
        return false
    end
    return true
end

local function watchDriving(source, session, vehicle, now)
    local penalties = Config.Penalties
    if not penalties.enabled then
        return
    end

    local collision = penalties.collision
    local body = GetVehicleBodyHealth(vehicle)
    local drop = (session.lastBody or body) - body
    session.lastBody = body

    if drop >= collision.minDrop and now - session.lastCollisionAt >= collision.cooldown then
        session.lastCollisionAt = now
        local fine = clamp(math.floor(collision.base + drop * collision.perPoint + 0.5), collision.base, collision.max)
        applyPenalty(source, session, 'collision', fine)
    end

    local speeding = penalties.speeding
    if speeding.enabled then
        if GetEntitySpeed(vehicle) > speeding.limit then
            session.speedingFor = session.speedingFor + 1
            if session.speedingFor >= speeding.seconds and now - session.lastSpeedingAt >= speeding.cooldown then
                session.speedingFor = 0
                session.lastSpeedingAt = now
                applyPenalty(source, session, 'speeding', speeding.fine)
            end
        else
            session.speedingFor = 0
        end
    end
end

local function watchSessions()
    local now = os.time()
    for source, session in pairs(sessions) do
        if session.vehicleNetId then
            local vehicle = NetworkGetEntityFromNetworkId(session.vehicleNetId)
            if vehicle == 0 or not DoesEntityExist(vehicle) then
                -- Pode ser só a rede a demorar. Antes de desistir confirma-se que o
                -- jogador também não está dentro de nenhum autocarro.
                local ped = GetPlayerPed(source)
                local inside = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
                if inside ~= 0 and DoesEntityExist(inside) then
                    session.missing = 0
                    -- O autocarro mudou de identificador de rede: segue o novo.
                    local newNetId = NetworkGetNetworkIdFromEntity(inside)
                    if newNetId ~= 0 and GetEntityModel(inside) == joaat(session.model) then
                        session.vehicleNetId = newNetId
                        logShift('O autocarro de %s mudou de netId para %d.', tostring(session.identifier), newNetId)
                    end
                else
                    session.missing = session.missing + 1
                    if session.missing >= 30 then
                        logShift('Perdi o autocarro de %s durante 30s. Turno terminado.', tostring(session.identifier))
                        failSession(source, 'vehicle_lost')
                    end
                end
            else
                session.missing = 0
                if watchDriver(source, session, vehicle, now) then
                    watchDriving(source, session, vehicle, now)
                end
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
--  Arranque
-- ─────────────────────────────────────────────────────────────
CreateThread(function()
    detectFramework()
    MySQL.ready(function()
        MySQL.query.await(([[
            CREATE TABLE IF NOT EXISTS `%s` (
                citizenid VARCHAR(64) NOT NULL,
                experience INT UNSIGNED NOT NULL DEFAULT 0,
                completed INT UNSIGNED NOT NULL DEFAULT 0,
                earned BIGINT UNSIGNED NOT NULL DEFAULT 0,
                daily_date CHAR(10) NOT NULL,
                daily_completed INT UNSIGNED NOT NULL DEFAULT 0,
                daily_claimed TINYINT(1) NOT NULL DEFAULT 0,
                PRIMARY KEY (citizenid)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]]):format(TABLE))

        -- Migração da v2: os perfis existentes mantêm-se e ganham as colunas novas.
        ensureColumn('name', 'VARCHAR(64) NULL')
        ensureColumn('streak', 'INT UNSIGNED NOT NULL DEFAULT 0')
        ensureColumn('best_streak', 'INT UNSIGNED NOT NULL DEFAULT 0')
        ensureColumn('rating_total', 'INT UNSIGNED NOT NULL DEFAULT 0')
        ensureColumn('rated', 'INT UNSIGNED NOT NULL DEFAULT 0')
        ensureColumn('perfect', 'INT UNSIGNED NOT NULL DEFAULT 0')
        ensureColumn('passengers', 'INT UNSIGNED NOT NULL DEFAULT 0')

        MySQL.query.await(([[
            CREATE TABLE IF NOT EXISTS `%s` (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                citizenid VARCHAR(64) NOT NULL,
                route_id INT UNSIGNED NOT NULL,
                route_label VARCHAR(64) NOT NULL,
                payment INT NOT NULL DEFAULT 0,
                penalty INT UNSIGNED NOT NULL DEFAULT 0,
                rating TINYINT UNSIGNED NOT NULL DEFAULT 0,
                duration INT UNSIGNED NOT NULL DEFAULT 0,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_citizen (citizenid, id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]]):format(HISTORY))

        databaseReady = true
    end)
end)

-- ─────────────────────────────────────────────────────────────
--  Callbacks
-- ─────────────────────────────────────────────────────────────
lib.callback.register('gg_busjob_advanced:getProfile', function(source)
    local profile = getProfile(source)
    if not profile then
        return { ok = false }
    end
    return profileResponse(profile)
end)

lib.callback.register('gg_busjob_advanced:getRanking', function(source)
    if not Config.Ranking.enabled then
        return { ok = true, rows = {}, position = nil }
    end

    local profile, identifier = getProfile(source)
    if not profile then
        return { ok = false }
    end

    if os.time() - ranking.at >= Config.Ranking.cacheSeconds then
        ranking.rows = MySQL.query.await(([[
            SELECT citizenid, name, experience, completed, earned
            FROM `%s` WHERE completed > 0
            ORDER BY experience DESC, completed DESC
            LIMIT %d
        ]]):format(TABLE, safeInt(Config.Ranking.limit, 10))) or {}
        ranking.at = os.time()
    end

    local rows = {}
    for index, row in ipairs(ranking.rows) do
        rows[index] = {
            rank = index,
            name = row.name or '—',
            level = getLevel(row.experience),
            completed = row.completed,
            earned = row.earned,
            me = row.citizenid == identifier,
        }
    end

    local position
    if profile.completed > 0 then
        position = tonumber(MySQL.scalar.await(
            ('SELECT COUNT(*) + 1 FROM `%s` WHERE completed > 0 AND experience > ?'):format(TABLE),
            { profile.experience }
        ))
    end

    return { ok = true, rows = rows, position = position }
end)

-- Últimas rotas do motorista (data em segundos unix; a interface formata no idioma certo).
lib.callback.register('gg_busjob_advanced:getHistory', function(source)
    local profile, identifier = getProfile(source)
    if not profile then
        return { ok = false }
    end

    local rows = MySQL.query.await(([[
        SELECT route_id, route_label, payment, penalty, rating, duration, UNIX_TIMESTAMP(created_at) AS ts
        FROM `%s` WHERE citizenid = ?
        ORDER BY id DESC
        LIMIT %d
    ]]):format(HISTORY, safeInt(Config.History.limit, 12)), { identifier }) or {}

    local history = {}
    for index, row in ipairs(rows) do
        history[index] = {
            routeId = tonumber(row.route_id) or 0,
            label = row.route_label,
            payment = tonumber(row.payment) or 0,
            penalty = tonumber(row.penalty) or 0,
            rating = tonumber(row.rating) or 0,
            duration = tonumber(row.duration) or 0,
            ts = tonumber(row.ts) or 0,
        }
    end
    return { ok = true, history = history }
end)

-- Quem está de serviço neste momento.
lib.callback.register('gg_busjob_advanced:getWorkers', function(source)
    local workers = {}
    local now = os.time()

    for workerSource, session in pairs(sessions) do
        local route = Config.Routes[session.routeId]
        if session.vehicleNetId and route then
            local profile = profiles[session.identifier]
            workers[#workers + 1] = {
                name = profile and profile.name or '—',
                routeId = session.routeId,
                stop = math.min(session.nextStop, #route.stops),
                total = #route.stops,
                elapsed = now - session.startedAt,
                me = workerSource == source,
            }
        end
    end

    table.sort(workers, function(a, b)
        return a.elapsed > b.elapsed
    end)
    for index = #workers, 13, -1 do
        workers[index] = nil
    end

    return { ok = true, workers = workers }
end)

lib.callback.register('gg_busjob_advanced:startRoute', function(source, routeId, modelName)
    if sessions[source] or starting[source] then
        return { ok = false, error = 'already_working' }
    end

    if type(routeId) ~= 'number' or not Config.Routes[routeId] then
        return { ok = false, error = 'invalid_route' }
    end

    if not isAtDepot(source, Config.DepotRadius) then
        return { ok = false, error = 'too_far' }
    end

    starting[source] = true
    local route = Config.Routes[routeId]
    local vehicle = findVehicle(modelName)
    local profile, identifier = getProfile(source)
    if not profile then
        starting[source] = nil
        return { ok = false, error = 'route_error' }
    end

    local level = getLevel(profile.experience)
    if level < route.level then
        starting[source] = nil
        return { ok = false, error = 'locked', level = route.level }
    end
    if not vehicle or vehicle.seats < route.seats_required or level < vehicle.level then
        starting[source] = nil
        return { ok = false, error = 'no_vehicle' }
    end

    local token = ('%s-%s-%s'):format(source, os.time(), math.random(100000, 999999))
    local plate = makePlate()
    sessions[source] = {
        identifier = identifier,
        token = token,
        routeId = routeId,
        model = vehicle.model,
        plate = plate,
        startedAt = os.time(),
        nextStop = 1,
        lastStopAt = os.time(),
        -- vigilância do turno
        penalty = 0,
        counts = { collision = 0, speeding = 0 },
        lastCollisionAt = -1000,
        lastSpeedingAt = -1000,
        speedingFor = 0,
        missing = 0,
        seated = false,
    }
    starting[source] = nil

    return {
        ok = true,
        token = token,
        plate = plate,
        model = vehicle.model,
    }
end)

lib.callback.register('gg_busjob_advanced:registerBus', function(source, token, netId)
    local session = sessions[source]
    if not session or session.token ~= token or session.vehicleNetId then
        return { ok = false, error = 'route_error' }
    end
    if type(netId) ~= 'number' or not isAtDepot(source, 100.0) then
        removeSession(source)
        return { ok = false, error = 'spawn_failed' }
    end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    local ped = GetPlayerPed(source)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return { ok = false, error = 'retry' }
    end
    if GetEntityType(vehicle) ~= 2
        or GetEntityModel(vehicle) ~= joaat(session.model)
        or GetVehicleNumberPlateText(vehicle):gsub('%s+', '') ~= session.plate then
        removeSession(source)
        return { ok = false, error = 'spawn_failed' }
    end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then
        return { ok = false, error = 'retry' }
    end

    session.vehicleNetId = netId
    session.seated = true
    session.lastBody = GetVehicleBodyHealth(vehicle)

    if Config.GiveKeys then
        local ok, err = pcall(Config.GiveKeys, source, vehicle, session.plate)
        if not ok then
            print(('[%s] Config.GiveKeys rebentou: %s'):format(GetCurrentResourceName(), tostring(err)))
        end
    else
        logShift('Config.GiveKeys não está definido: ninguém recebe a chave.')
    end

    return { ok = true }
end)

local function serviceStopInner(source, token, netId)
    local session = sessions[source]
    if not session or session.token ~= token or session.vehicleNetId ~= netId then
        return { ok = false, error = 'must_drive' }
    end

    local route = Config.Routes[session.routeId]
    local stages = route and BusStageCount(route) or 0
    if not route or session.nextStop > stages then
        return { ok = false, error = 'invalid_route' }
    end

    -- A etapa pode ser uma paragem da rota ou a entrega na garagem.
    local stageCoord = BusStageCoord(route, session.nextStop)
    local stageRadius = BusStageRadius(route, session.nextStop)
    if not stageCoord then
        return { ok = false, error = 'invalid_route' }
    end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    local ped = GetPlayerPed(source)
    if vehicle == 0 or not DoesEntityExist(vehicle)
        or GetPedInVehicleSeat(vehicle, -1) ~= ped
        or GetEntityModel(vehicle) ~= joaat(session.model) then
        return { ok = false, error = 'must_drive' }
    end
    if #(GetEntityCoords(vehicle) - stageCoord) > stageRadius
        or GetEntitySpeed(vehicle) > Config.StopSpeedLimit then
        return { ok = false, error = 'must_stop' }
    end

    local now = os.time()
    local requiredDelay = session.nextStop == 1 and Config.FirstStopDelay or Config.StopCooldown
    if BusStageIsReturn(route, session.nextStop) then
        requiredDelay = 0      -- a garagem vem logo depois do destino
    end
    local elapsedSinceLast = session.nextStop == 1 and now - session.startedAt or now - session.lastStopAt
    if elapsedSinceLast < requiredDelay then
        return { ok = false, error = 'too_early' }
    end

    local servicedStop = session.nextStop
    local isFinal = servicedStop >= stages

    -- Etapa normal: marca-a e segue para a seguinte.
    if not isFinal then
        session.lastStopAt = now
        session.nextStop = servicedStop + 1
        logShift('%s: etapa %d/%d (%s) feita na rota %d.', tostring(session.identifier),
            servicedStop, stages, BusStageKind(route, servicedStop), session.routeId)
        return {
            ok = true,
            complete = false,
            stop = servicedStop,
            totalStops = stages,
        }
    end

    -- ── Garagem: o autocarro foi entregue, calcula o pagamento ──
    -- Daqui para baixo nada apaga o autocarro nem a sessão se algo falhar:
    -- o jogador fica na garagem e pode carregar outra vez em E para receber.
    -- Trinco para dois pedidos ao mesmo tempo. Tem hora: se algo correr mal
    -- a meio, liberta-se sozinho em segundos em vez de prender o turno.
    if session.payingAt and now - session.payingAt < 10 then
        return { ok = false, error = 'too_early' }
    end
    session.payingAt = now

    local profile = profiles[session.identifier]
    local player = getPlayer(source)
    if not profile then
        profile = getProfile(source)
        player = player or getPlayer(source)
    end
    if not profile or not player then
        session.payingAt = nil
        logShift('Não consegui ler o perfil/jogador de %s no destino. O turno continua.', tostring(session.identifier))
        return { ok = false, error = 'payment_failed' }
    end

    local bonuses = Config.Bonuses
    local reward = route.rewards.money * Config.RewardMultiplier

    local condition = clamp((GetVehicleBodyHealth(vehicle) + GetVehicleEngineHealth(vehicle)) / 2000, 0, 1)
    local conditionMultiplier = math.max(Config.MinimumConditionMultiplier, condition)

    local elapsed = now - session.startedAt
    local timeScore = 1.0
    if elapsed > route.parTime then
        timeScore = clamp(1 - (elapsed - route.parTime) / (route.parTime * bonuses.timeFalloff), 0, 1)
    end

    local rawScore = 0.65 * condition + 0.35 * timeScore
    local stars = clamp(math.floor(rawScore * 5 + 0.5), 1, 5)

    local streakBefore = profile.streak
    local streakPct = math.min(bonuses.streakMax, streakBefore * bonuses.streakPerRoute)

    -- O pagamento base é inteiro; os danos e as multas descontam-se à parte.
    -- Conta o que for maior: as multas registadas durante a rota ou o desgaste final
    -- do autocarro (apanha danos que passaram entre duas verificações).
    local base = math.floor(reward)
    local damageDeduction = math.floor(reward * (1 - conditionMultiplier))
    local penalty = damageDeduction
    if Config.Penalties.enabled then
        penalty = math.max(session.penalty, damageDeduction)
    end
    local timeBonus = math.floor(reward * bonuses.timeBonusMax * timeScore)
    local streakBonus = math.floor(reward * streakPct)

    local tips = 0
    if bonuses.tips.enabled and stars >= bonuses.tips.minRating then
        for _ = 1, route.boarding do
            tips = tips + math.random(bonuses.tips.min, bonuses.tips.max)
        end
        tips = math.floor(tips * stars / 5)
    end

    local payment = base + timeBonus + streakBonus + tips - penalty
    local experience = math.floor(route.rewards.experience * (stars == 5 and bonuses.perfectExperience or 1.0))
    local previousLevel = getLevel(profile.experience)

    local paid, account, how = payPlayer(source, payment, 'advanced-bus-route')
    if not paid then
        session.payingAt = nil
        logShift('O pagamento de %d a %s falhou. O turno fica de pé: carrega outra vez em E no destino.',
            payment, tostring(session.identifier))
        return { ok = false, error = 'payment_failed' }
    end

    -- Pago. Só agora a rota fica fechada.
    session.lastStopAt = now
    session.nextStop = servicedStop + 1
    logShift('%s entregou o autocarro da rota %d: %s%d em %s (%s), %d estrelas, %ds.',
        tostring(session.identifier), session.routeId, Config.Currency, payment, account, how, stars, elapsed)

    profile.experience = profile.experience + experience
    profile.completed = profile.completed + 1
    profile.earned = profile.earned + payment
    profile.passengers = profile.passengers + route.boarding
    profile.rating_total = profile.rating_total + stars
    profile.rated = profile.rated + 1
    if stars == 5 then
        profile.perfect = profile.perfect + 1
    end
    profile.streak = streakBefore + 1
    profile.best_streak = math.max(profile.best_streak, profile.streak)
    resetDaily(profile)
    profile.daily_completed = profile.daily_completed + 1
    profile.name = getCharacterName(player)
    saveProfile(session.identifier, profile)
    addHistory(session.identifier, session.routeId, route.label, payment, penalty, stars, elapsed)

    local newLevel = getLevel(profile.experience)
    local dailyAvailable = profile.daily_completed >= Config.DailyJobsRequired and not profile.daily_claimed

    -- O autocarro fica à espera que o jogador saia (ver Config.Finish).
    removeSession(source, (Config.Finish and Config.Finish.graceSeconds or 15) * 1000)

    return {
        ok = true,
        complete = true,
        payment = payment,
        base = base,
        penalty = penalty,
        collisions = session.counts.collision,
        speeding = session.counts.speeding,
        condition = math.floor(condition * 100 + 0.5),
        timeBonus = timeBonus,
        streakBonus = streakBonus,
        streak = profile.streak,
        tips = tips,
        experience = experience,
        rating = stars,
        elapsed = elapsed,
        par = route.parTime,
        passengers = route.boarding,
        level = newLevel,
        levelUp = newLevel > previousLevel,
        dailyAvailable = dailyAvailable,
    }
end

-- Um erro de Lua aqui dentro deixava o cliente à espera para sempre.
-- Agora devolve sempre uma resposta e escreve o erro na consola.
lib.callback.register('gg_busjob_advanced:serviceStop', function(source, token, netId)
    local ok, result = pcall(serviceStopInner, source, token, netId)
    if not ok then
        print(('[%s] serviceStop falhou: %s'):format(GetCurrentResourceName(), tostring(result)))
        -- Liberta o trinco do pagamento para o jogador poder tentar outra vez.
        local session = sessions[source]
        if session then
            session.payingAt = nil
        end
        return { ok = false, error = 'payment_failed' }
    end
    return result
end)

lib.callback.register('gg_busjob_advanced:claimDaily', function(source)
    local profile, identifier = getProfile(source)
    if not profile then
        return { ok = false, error = 'route_error' }
    end
    if profile.daily_completed < Config.DailyJobsRequired or profile.daily_claimed then
        return { ok = false, error = 'daily_not_ready' }
    end
    if not payPlayer(source, Config.DailyReward.money, 'advanced-bus-daily-reward') then
        return { ok = false, error = 'payment_failed' }
    end

    local previousLevel = getLevel(profile.experience)
    profile.daily_claimed = true
    profile.experience = profile.experience + Config.DailyReward.experience
    profile.earned = profile.earned + Config.DailyReward.money
    saveProfile(identifier, profile)

    return {
        ok = true,
        payment = Config.DailyReward.money,
        experience = Config.DailyReward.experience,
        level = getLevel(profile.experience),
        levelUp = getLevel(profile.experience) > previousLevel,
        profile = profileResponse(profile),
    }
end)

-- penalize: o jogador terminou o turno de propósito, por isso a sequência volta a 0.
lib.callback.register('gg_busjob_advanced:cancelRoute', function(source, token, penalize)
    local session = sessions[source]
    if not session or session.token ~= token then
        return false
    end

    if penalize then
        local profile = profiles[session.identifier]
        if profile and profile.streak > 0 then
            profile.streak = 0
            saveProfile(session.identifier, profile)
        end
    end

    removeSession(source)
    return true
end)

RegisterNetEvent('gg_busjob_advanced:cancelOnClientStop', function(token)
    local playerSource = source
    local session = sessions[playerSource]
    if session and session.token == token then
        removeSession(playerSource)
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        local ok, err = pcall(watchSessions)
        if not ok then
            print(('[%s] watchSessions failed: %s'):format(GetCurrentResourceName(), err))
        end
    end
end)

AddEventHandler('playerDropped', function()
    starting[source] = nil
    removeSession(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end
    for source in pairs(sessions) do
        removeSession(source)
    end
end)
