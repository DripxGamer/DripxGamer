local depotPed
local depotBlip
local stopBlip
local exitBlip
local routeState
local terminalOpen = false
local starting = false
local serviceActive = false
local activePrompt
local pendingToken
local routesPayload
local depotVector = vector3(Config.Depot.coords.x, Config.Depot.coords.y, Config.Depot.coords.z)

local SOUNDS = {
    click = { 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    nav = { 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    back = { 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    success = { 'PURCHASE', 'HUD_LIQUOR_STORE_SOUNDSET' },
    levelup = { 'RANK_UP', 'HUD_AWARDS' },
    penalty = { 'CHECKPOINT_MISSED', 'HUD_MINI_GAME_SOUNDSET' },
    warning = { 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET' },
}

-- ─────────────────────────────────────────────────────────────
--  Ponte com a interface
-- ─────────────────────────────────────────────────────────────
local function nui(action, data)
    SendNUIMessage({ action = action, data = data })
end

local function uiInit()
    nui('init', {
        locale = GetLocaleTable(),
        lang = Config.Locale,
        config = {
            currency = Config.Currency,
            speedUnit = Config.SpeedUnit,
            backdrop = Config.UI.backdrop,
            accent = Config.UI.accent,
            theme = Config.UI.theme,
            hudSide = Config.UI.hudSide,
            ticketSeconds = Config.UI.ticketSeconds,
            cancelKey = Config.CancelKeyLabel,
            speedLimit = (Config.Penalties.enabled and Config.Penalties.speeding.enabled)
                and math.floor(Config.Penalties.speeding.limit * (Config.SpeedUnit == 'mph' and 2.236936 or 3.6) + 0.5) or 0,
            dailyRequired = Config.DailyJobsRequired,
            dailyReward = Config.DailyReward,
            badges = Config.Badges,
        },
    })
end

local function playSound(name)
    local sound = SOUNDS[name]
    if sound then
        PlaySoundFrontend(-1, sound[1], sound[2], true)
    end
end

local function notify(key, kind, ...)
    nui('toast', { kind = kind or 'info', title = _U('title'), text = _U(key, ...) })
end

local function notifyError(key, level)
    if key == 'locked' then
        notify('locked', 'error', level)
    else
        notify(key or 'route_error', 'error')
    end
end

local function setPrompt(prompt)
    local signature = prompt and (prompt.text .. (prompt.sub or '') .. (prompt.warn and '!' or '')) or nil
    if signature == activePrompt then
        return
    end
    activePrompt = signature

    if prompt then
        nui('prompt:show', prompt)
    else
        nui('prompt:hide')
    end
end

-- As etapas vêm de shared.lua, para o cliente e o servidor contarem a rota igual.
-- A última paragem é sempre o destino (descem todos) e, depois dela, falta entregar
-- o autocarro na garagem: é lá que a rota fecha e o pagamento entra.
local stopKind = BusStageKind
local stageCount = BusStageCount
local stageCoord = BusStageCoord
local stageRadius = BusStageRadius

local NO_PASSENGERS = { npc_positions = {} }

local KIND_STYLE = {
    pickup = { sprite = 1, colour = 5, blip = 'blip_stop', prompt = 'prompt_board' },
    dropoff = { sprite = 1, colour = 5, blip = 'blip_dropoff', prompt = 'prompt_alight' },
    destination = { sprite = 1, colour = 5, blip = 'blip_destination', prompt = 'prompt_destination' },
    ['return'] = { sprite = 50, colour = 5, blip = 'blip_return', prompt = 'prompt_return' },
}

-- ─────────────────────────────────────────────────────────────
--  Dados para o terminal
-- ─────────────────────────────────────────────────────────────
local function getRoutesPayload()
    if routesPayload then
        return routesPayload
    end

    routesPayload = {}
    for id, route in ipairs(Config.Routes) do
        local stops = {}
        for index, stop in ipairs(route.stops) do
            stops[index] = {
                x = stop.stop_coord.x,
                y = stop.stop_coord.y,
                boarding = stopKind(route, index) == 'pickup' and #stop.npc_positions or 0,
            }
        end

        routesPayload[id] = {
            id = id,
            garage = Config.Return.enabled
                and { x = Config.Return.coords.x, y = Config.Return.coords.y } or nil,
            label = route.label,
            area = route.area,
            level = route.level,
            seats = route.seats_required,
            money = math.floor(route.rewards.money * Config.RewardMultiplier),
            xp = route.rewards.experience,
            length = route.length,
            par = route.parTime,
            boarding = route.boarding,
            image = route.image,
            stops = stops,
        }
    end
    return routesPayload
end

local function getVehiclesPayload()
    local vehicles = {}
    for index, vehicle in ipairs(Config.Vehicles) do
        local key = 'vehicle_' .. vehicle.model
        local label = _U(key)
        vehicles[index] = {
            model = vehicle.model,
            label = label ~= key and label or vehicle.label,
            seats = vehicle.seats,
            level = vehicle.level,
        }
    end
    return vehicles
end

local function activeShiftPayload()
    if not routeState then
        return nil
    end
    return {
        routeId = routeState.routeId,
        label = routeState.route.label,
        nextStop = routeState.nextStop,
        total = stageCount(routeState.route),
    }
end

-- ─────────────────────────────────────────────────────────────
--  Rota
-- ─────────────────────────────────────────────────────────────
local function getSpawnPoint()
    for _, coords in ipairs(Config.Depot.spawns) do
        if not IsAnyVehicleNearPoint(coords.x, coords.y, coords.z, 3.5) then
            return coords
        end
    end
end

local function removeStopBlip()
    if stopBlip and DoesBlipExist(stopBlip) then
        RemoveBlip(stopBlip)
    end
    stopBlip = nil
end

-- A etapa atual como se fosse uma paragem. A garagem não tem passageiros.
local RETURN_STAGE = { npc_positions = {} }
local function currentStop()
    if not routeState then
        return nil
    end
    local route, index = routeState.route, routeState.nextStop
    if BusStageIsReturn(route, index) then
        RETURN_STAGE.stop_coord = Config.Return.coords
        return RETURN_STAGE
    end
    return route.stops[index]
end

local function setNextStop()
    removeStopBlip()
    local stop = currentStop()
    if not stop then
        return
    end

    -- Um único traçado no mapa: o do blip da paragem. Antes marcava-se também um
    -- ponto de destino com SetNewWaypoint, e o jogo desenhava duas linhas por cima
    -- uma da outra (a roxa do destino e a amarela da rota).
    local style = KIND_STYLE[stopKind(routeState.route, routeState.nextStop)]
    stopBlip = AddBlipForCoord(stop.stop_coord.x, stop.stop_coord.y, stop.stop_coord.z)
    SetBlipSprite(stopBlip, style.sprite)
    SetBlipColour(stopBlip, style.colour)
    SetBlipScale(stopBlip, 0.9)
    SetBlipRoute(stopBlip, true)
    SetBlipRouteColour(stopBlip, style.colour)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(_U(style.blip, routeState.nextStop, stageCount(routeState.route)))
    EndTextCommandSetBlipName(stopBlip)
end

-- Portas da paragem. Só as de Config.Passengers.doors, e nunca os índices 4 e 5,
-- que no GTA são o capô e a mala: era por isso que a bagageira abria com a porta.
local ENTRANCE_DOORS = {}
for _, index in ipairs(Config.Passengers.doors or { 1 }) do
    index = tonumber(index)
    if index and index >= 0 and index <= 3 then
        ENTRANCE_DOORS[#ENTRANCE_DOORS + 1] = index
    end
end

local function setEntranceDoors(bus, open)
    if not DoesEntityExist(bus) then
        return
    end

    local doors = {}
    for _, index in ipairs(ENTRANCE_DOORS) do
        if GetIsDoorValid(bus, index) then
            doors[#doors + 1] = index
        end
    end

    for _, index in ipairs(doors) do
        if open then
            SetVehicleDoorOpen(bus, index, false, false)
        else
            SetVehicleDoorShut(bus, index, false)
        end
    end
end

-- Durante o turno ninguém consegue tirar o motorista do autocarro.
local function protectDriver(on)
    local ped = PlayerPedId()
    SetPedCanBeDraggedOut(ped, not on)
    SetPedStayInVehicleWhenJacked(ped, on)
end

local function deleteBus(bus)
    if bus and DoesEntityExist(bus) then
        SetEntityAsMissionEntity(bus, true, true)
        DeleteVehicle(bus)
    end
end

-- Marca o autocarro no mapa enquanto o motorista está fora dele.
local function removeExitBlip()
    if exitBlip and DoesBlipExist(exitBlip) then
        RemoveBlip(exitBlip)
    end
    exitBlip = nil
end

local function showExitBlip(bus)
    if exitBlip or not bus or not DoesEntityExist(bus) then
        return
    end
    exitBlip = AddBlipForEntity(bus)
    SetBlipSprite(exitBlip, 513)
    SetBlipColour(exitBlip, 5)
    SetBlipScale(exitBlip, 0.9)
    SetBlipFlashes(exitBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(_U('exit_title'))
    EndTextCommandSetBlipName(exitBlip)
end

local function clearRoute()
    local bus = routeState and routeState.bus
    routeState = nil
    protectDriver(false)
    removeStopBlip()
    removeExitBlip()
    Passengers.clearAll()
    nui('service:stop', { completed = false })
    nui('exit:stop')
    nui('hud:stop')
    deleteBus(bus)
end

-- `penalize` = o jogador desistiu de propósito (perde a sequência).
-- Se o autocarro se perdeu sozinho, a sequência fica intacta.
local function cancelRoute(showNotification, penalize, messageKey)
    local current = routeState
    if not current then
        return
    end

    if penalize == nil then
        penalize = true
    end

    lib.callback.await('gg_busjob_advanced:cancelRoute', false, current.token, penalize)
    clearRoute()
    if showNotification then
        notify(messageKey or 'route_cancelled', 'warning')
    end
end

-- Turno terminado com sucesso: o jogador sai do autocarro e o bilhete aparece no ecrã.
local function finishRoute(result)
    local current = routeState
    local bus = current.bus
    routeState = nil
    protectDriver(false)
    removeStopBlip()
    removeExitBlip()
    nui('exit:stop')
    nui('hud:stop')
    nui('ticket', {
        label = current.route.label,
        routeId = current.routeId,
        result = result,
    })
    playSound(result.levelUp and 'levelup' or 'success')

    CreateThread(function()
        if not bus or not DoesEntityExist(bus) then
            Passengers.clearAll()
            return
        end

        SetVehicleIndicatorLights(bus, 0, false)
        SetVehicleIndicatorLights(bus, 1, false)
        SetVehicleHandbrake(bus, false)

        -- Entregar o autocarro: o motorista desce e o autocarro é recolhido.
        -- Nunca se apaga com ele lá dentro, mas também não fica à espera eternamente.
        if IsPedInVehicle(PlayerPedId(), bus, true) then
            notify('shift_done_leave', 'info')
            setEntranceDoors(bus, true)
            TaskLeaveVehicle(PlayerPedId(), bus, 0)

            local deadline = GetGameTimer() + (Config.Finish.leaveSeconds * 1000)
            local nudge = GetGameTimer() + 3000
            while GetGameTimer() < deadline do
                if not DoesEntityExist(bus) then
                    Passengers.clearAll()
                    return
                end
                if not IsPedInVehicle(PlayerPedId(), bus, true) then
                    break
                end
                -- Se alguma coisa cancelar a saída, volta a pedi-la.
                if GetGameTimer() >= nudge then
                    nudge = GetGameTimer() + 3000
                    TaskLeaveVehicle(PlayerPedId(), bus, 0)
                end
                Wait(100)
            end
        end

        Wait(700)
        Passengers.clearAll()
        if not DoesEntityExist(bus) then
            return
        end

        -- Desvanece e desaparece, em vez de sumir de repente.
        setEntranceDoors(bus, false)
        for alpha = 255, 0, -45 do
            if not DoesEntityExist(bus) then
                return
            end
            SetEntityAlpha(bus, alpha, false)
            Wait(60)
        end
        deleteBus(bus)
    end)
end

local function startRouteInner(routeId, model)
    local route = Config.Routes[routeId]
    if not route then
        return false, 'invalid_route'
    end

    local spawn = getSpawnPoint()
    if not spawn then
        return false, 'spawn_blocked'
    end

    local result = lib.callback.await('gg_busjob_advanced:startRoute', false, routeId, model)
    if not result or not result.ok then
        return false, result and result.error or 'route_error', result and result.level
    end
    pendingToken = result.token

    local modelHash = joaat(result.model)
    lib.requestModel(modelHash)
    local bus = CreateVehicle(modelHash, spawn.x, spawn.y, spawn.z, spawn.w, true, true)
    if bus == 0 or not DoesEntityExist(bus) then
        lib.callback.await('gg_busjob_advanced:cancelRoute', false, result.token, false)
        pendingToken = nil
        return false, 'spawn_failed'
    end

    SetEntityAsMissionEntity(bus, true, true)
    SetVehicleOnGroundProperly(bus)
    SetVehicleNumberPlateText(bus, result.plate)
    SetVehicleEngineOn(bus, true, true, false)
    if GetResourceState('ox_fuel') == 'started' then
        Entity(bus).state.fuel = 100.0
    else
        SetVehicleFuelLevel(bus, 100.0)
    end
    SetVehicleDirtLevel(bus, 0.0)
    SetVehicleDoorsLocked(bus, 1)                         -- destrancado
    SetVehicleDoorsLockedForAllPlayers(bus, false)
    TaskWarpPedIntoVehicle(PlayerPedId(), bus, -1)
    SetModelAsNoLongerNeeded(modelHash)

    local netId = NetworkGetNetworkIdFromEntity(bus)
    SetNetworkIdCanMigrate(netId, true)

    local registered
    for _ = 1, 10 do
        Wait(300)
        registered = lib.callback.await('gg_busjob_advanced:registerBus', false, result.token, netId)
        if registered and registered.ok then
            break
        end
        if not registered or registered.error ~= 'retry' then
            break
        end
    end

    if not registered or not registered.ok then
        lib.callback.await('gg_busjob_advanced:cancelRoute', false, result.token, false)
        pendingToken = nil
        deleteBus(bus)
        return false, 'spawn_failed'
    end

    pendingToken = nil
    protectDriver(true)
    -- Chave do autocarro: o servidor já a deu; isto repete-a do lado do cliente para os sistemas
    -- de chaves que só reagem aqui (qb-vehiclekeys e compatíveis).
    TriggerEvent('vehiclekeys:client:SetOwner', result.plate)
    SetVehicleEngineOn(bus, true, true, false)
    routeState = {
        token = result.token,
        route = route,
        routeId = routeId,
        nextStop = 1,
        bus = bus,
        netId = netId,
        passengers = 0,
        startedAt = GetGameTimer(),
        penalty = 0,
        collisions = 0,
        speeding = 0,
    }
    return true
end

-- Devolve: ok, errorKey, extra
local function beginRoute(routeId, model)
    if routeState or starting then
        return false, 'already_working'
    end

    starting = true
    pendingToken = nil
    local called, ok, errorKey, extra = pcall(startRouteInner, routeId, model)
    starting = false

    if not called then
        print(('[%s] Failed to start route: %s'):format(GetCurrentResourceName(), ok))
        if pendingToken then
            lib.callback.await('gg_busjob_advanced:cancelRoute', false, pendingToken, false)
            pendingToken = nil
        end
        return false, 'route_error'
    end

    if not ok then
        return false, errorKey, extra
    end

    local route = routeState.route
    local stops = {}
    for index = 1, stageCount(route) do
        local kind = stopKind(route, index)
        local stop = route.stops[index]
        stops[index] = { boarding = kind == 'pickup' and #stop.npc_positions or 0, kind = kind }
    end

    uiInit()
    nui('hud:start', {
        routeId = routeState.routeId,
        label = route.label,
        level = route.level,
        money = math.floor(route.rewards.money * Config.RewardMultiplier),
        par = route.parTime,
        stops = stops,
    })
    setNextStop()
    notify('route_started', 'success', route.label)
    return true
end

-- ─────────────────────────────────────────────────────────────
--  Paragem
-- ─────────────────────────────────────────────────────────────
local function serviceCurrentStop()
    local ped = PlayerPedId()
    local current = routeState
    local bus = current and current.bus

    if not current or not bus or not DoesEntityExist(bus) or GetPedInVehicleSeat(bus, -1) ~= ped then
        notify('must_drive', 'error')
        return
    end
    if GetEntitySpeed(bus) > Config.StopSpeedLimit then
        notify('must_stop', 'error')
        return
    end

    local stopIndex = current.nextStop
    local total = stageCount(current.route)
    local stop = current.route.stops[stopIndex]
    local kind = stopKind(current.route, stopIndex)
    local isGarage = kind == 'return'
    local boarding = kind == 'pickup' and #stop.npc_positions or 0
    local alighting = 0
    if not isGarage and boarding == 0 then
        alighting = kind == 'destination' and current.passengers or math.ceil(current.passengers / 2)
    end

    serviceActive = true
    setPrompt(nil)

    -- ① A paragem é confirmada no servidor ANTES de qualquer animação.
    --    Assim nada do que os passageiros façam (ou não consigam fazer) pode roubar
    --    a paragem nem o pagamento, e se o servidor recusar não se perde nada:
    --    basta carregar outra vez em E.
    local result = lib.callback.await('gg_busjob_advanced:serviceStop', false, current.token, current.netId)
    if not result or not result.ok then
        serviceActive = false
        notifyError(result and result.error)
        return
    end
    if routeState ~= current or not DoesEntityExist(bus) then
        serviceActive = false
        return
    end

    -- ② Daqui para a frente a etapa já está ganha. Só falta a parte que se vê.
    --    A garagem não tem passageiros nem portas: é entregar e acabou.
    if result.complete then
        serviceActive = false
        nui('service:stop', { completed = true })
        finishRoute(result)
        return
    end

    notify('stop_arrived', 'success', result.stop, result.totalStops)

    -- Só as portas do lado do passeio abrem; a do condutor fica fechada.
    setEntranceDoors(bus, true)
    SetVehicleIndicatorLights(bus, 0, true)
    SetVehicleIndicatorLights(bus, 1, true)
    SetVehicleHandbrake(bus, true)      -- travão de mão: o autocarro não pode fugir sozinho

    -- A paragem dura o que precisar para a gente que entra ou sai.
    local people = math.max(boarding, alighting, 1)
    local duration = math.min(Config.StopServiceTime,
        Config.StopServiceMin + people * Config.StopServicePer)
    nui('service:start', {
        duration = duration,
        mode = boarding > 0 and 'board' or 'alight',
        count = boarding > 0 and boarding or alighting,
        stop = stopIndex,
        total = total,
    })

    Passengers.beginStop()
    local freed = 0
    if boarding > 0 then
        -- Numa paragem de recolha também sai quem ia para ali. Assim libertam-se
        -- lugares para quem vai entrar, em vez de os novos se desvanecerem à porta.
        -- Sai sempre o mínimo configurado e, se faltarem lugares, sai mais gente.
        local release = Config.Passengers.alightAtPickup or 0
        local onboard = Passengers.count()
        if release > 0 and onboard > 0 and stopIndex > 1 then
            local shortfall = boarding - Passengers.freeSeats(bus)
            local leave = math.min(onboard, boarding, math.max(release, shortfall))
            if leave > 0 then
                freed = Passengers.alight(bus, leave / onboard, duration)
            end
        end
        Passengers.board(bus, duration)
    else
        Passengers.alight(bus, current.passengers > 0 and alighting / current.passengers or 1.0, duration)
    end

    local startedAt = GetGameTimer()
    while GetGameTimer() - startedAt < duration do
        Wait(0)
        DisableControlAction(0, 71, true)
        DisableControlAction(0, 72, true)
        DisableControlAction(0, 75, true)

        -- Acaba logo que todos entraram ou saíram (mas nunca antes do tempo mínimo).
        if GetGameTimer() - startedAt >= Config.StopServiceMin and not Passengers.busy() then
            break
        end

        -- Se alguma coisa tirar o motorista do lugar durante a paragem, volta a sentá-lo.
        if DoesEntityExist(bus) and GetPedInVehicleSeat(bus, -1) ~= ped then
            TaskWarpPedIntoVehicle(ped, bus, -1)
        end

        -- X salta a animação. Não se perde nada: a paragem já está confirmada.
        if IsControlJustPressed(0, Config.CancelKey)
            or routeState ~= current
            or not DoesEntityExist(bus) then
            break
        end
    end

    Passengers.settleStop(bus)

    if DoesEntityExist(bus) then
        setEntranceDoors(bus, false)
        SetVehicleIndicatorLights(bus, 0, false)
        SetVehicleIndicatorLights(bus, 1, false)
        SetVehicleHandbrake(bus, false)
    end
    serviceActive = false
    nui('service:stop', { completed = true })

    if routeState ~= current then
        return
    end

    if boarding > 0 then
        current.passengers = math.max(0, current.passengers + boarding - freed)
    else
        current.passengers = math.max(0, current.passengers - alighting)
    end
    current.nextStop = result.stop + 1
    setNextStop()

    local nextKind = stopKind(current.route, current.nextStop)
    if boarding > 0 and nextKind ~= 'pickup' then
        -- Último embarque feito: avisa que agora é entregar.
        notify('all_aboard', 'info')
    elseif nextKind == 'return' then
        -- Passageiros todos entregues: falta levar o autocarro à garagem.
        notify('return_to_garage', 'info')
    end
end

-- ─────────────────────────────────────────────────────────────
--  Terminal
-- ─────────────────────────────────────────────────────────────
local function openTerminal()
    if terminalOpen or starting then
        return
    end

    local profile = lib.callback.await('gg_busjob_advanced:getProfile', false)
    if not profile or not profile.ok then
        notify('route_error', 'error')
        return
    end

    terminalOpen = true
    setPrompt(nil)
    SetNuiFocus(true, true)
    if Config.UI.blur then
        TriggerScreenblurFadeIn(250.0)
    end

    uiInit()
    nui('terminal:open', {
        profile = profile,
        routes = getRoutesPayload(),
        vehicles = getVehiclesPayload(),
        depot = { x = Config.Depot.coords.x, y = Config.Depot.coords.y },
        active = activeShiftPayload(),
    })
    playSound('click')
end

local function closeTerminal()
    if not terminalOpen then
        return
    end

    terminalOpen = false
    SetNuiFocus(false, false)
    if Config.UI.blur then
        TriggerScreenblurFadeOut(250.0)
    end
    nui('terminal:close')
end

RegisterNUICallback('ready', function(_, cb)
    uiInit()
    cb(1)
end)

RegisterNUICallback('close', function(_, cb)
    closeTerminal()
    cb(1)
end)

RegisterNUICallback('sound', function(data, cb)
    playSound(data and data.name)
    cb(1)
end)

RegisterNUICallback('startRoute', function(data, cb)
    local ok, errorKey, extra = beginRoute(tonumber(data and data.routeId), data and data.model)
    if ok then
        closeTerminal()
    else
        notifyError(errorKey, extra)
    end
    cb({ ok = ok, error = errorKey })
end)

RegisterNUICallback('endRoute', function(_, cb)
    cancelRoute(true, true)
    local profile = lib.callback.await('gg_busjob_advanced:getProfile', false)
    cb({ ok = true, profile = profile })
end)

RegisterNUICallback('claimDaily', function(_, cb)
    local result = lib.callback.await('gg_busjob_advanced:claimDaily', false)
    if not result or not result.ok then
        notifyError(result and result.error)
        cb({ ok = false })
        return
    end

    notify('daily_claimed', 'success',
        ('%s%s'):format(Config.Currency, result.payment), result.experience)
    if result.levelUp then
        notify('level_up', 'success', result.level)
        playSound('levelup')
    else
        playSound('success')
    end
    cb({ ok = true, profile = result.profile })
end)

RegisterNUICallback('getRanking', function(_, cb)
    cb(lib.callback.await('gg_busjob_advanced:getRanking', false) or { ok = false })
end)

RegisterNUICallback('getWorkers', function(_, cb)
    cb(lib.callback.await('gg_busjob_advanced:getWorkers', false) or { ok = false })
end)

RegisterNUICallback('getHistory', function(_, cb)
    cb(lib.callback.await('gg_busjob_advanced:getHistory', false) or { ok = false })
end)

-- ─────────────────────────────────────────────────────────────
--  Avisos do servidor: multas, contagem de saída, turno falhado
-- ─────────────────────────────────────────────────────────────
RegisterNetEvent('gg_busjob_advanced:penalty', function(data)
    local current = routeState
    if not current or type(data) ~= 'table' then
        return
    end

    current.penalty = tonumber(data.total) or current.penalty
    current.collisions = tonumber(data.collisions) or current.collisions
    current.speeding = tonumber(data.speeding) or current.speeding

    local amount = tonumber(data.amount) or 0
    local text
    if amount > 0 then
        local value = ('%s%s'):format(Config.Currency, amount)
        text = data.kind == 'speeding' and _U('penalty_speeding', value) or _U('penalty_collision', value)
    elseif data.kind == 'collision' then
        text = _U('penalty_capped')
    end

    if text then
        nui('toast', { kind = 'warning', title = _U('title'), text = text })
        playSound('penalty')
    end
end)

RegisterNetEvent('gg_busjob_advanced:exitTimer', function(seconds)
    local current = routeState
    if not current then
        return
    end

    if seconds then
        nui('exit:start', { seconds = tonumber(seconds) or 45 })
        showExitBlip(current.bus)
        playSound('warning')
    else
        nui('exit:stop')
        removeExitBlip()
    end
end)

RegisterNetEvent('gg_busjob_advanced:routeFailed', function(reason)
    if not routeState then
        return
    end
    clearRoute()
    notify(reason == 'vehicle_lost' and 'route_failed_lost' or 'route_failed_left', 'error')
end)

-- ─────────────────────────────────────────────────────────────
--  Terminal físico (ped e blip)
-- ─────────────────────────────────────────────────────────────
local function createDepot()
    local model = joaat(Config.Depot.ped)
    lib.requestModel(model)
    local coords = Config.Depot.coords
    depotPed = CreatePed(0, model, coords.x, coords.y, coords.z - 1.0, coords.w, false, false)
    SetEntityAsMissionEntity(depotPed, true, true)
    SetEntityInvincible(depotPed, true)
    FreezeEntityPosition(depotPed, true)
    SetBlockingOfNonTemporaryEvents(depotPed, true)
    TaskStartScenarioInPlace(depotPed, Config.Depot.scenario, 0, true)
    SetModelAsNoLongerNeeded(model)

    if Config.Depot.blip.enabled then
        depotBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(depotBlip, Config.Depot.blip.sprite)
        SetBlipColour(depotBlip, Config.Depot.blip.color)
        SetBlipScale(depotBlip, Config.Depot.blip.scale)
        SetBlipAsShortRange(depotBlip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(_U('depot'))
        EndTextCommandSetBlipName(depotBlip)
    end
end

local function drawStopMarker(stopCoords, kind, radius)
    radius = radius or Config.StopRadius
    local color = Config.UI.dropoffColor
    if kind == 'pickup' then
        color = Config.UI.markerColor
    elseif kind == 'return' then
        color = Config.UI.garageColor or Config.UI.dropoffColor
    end
    DrawMarker(
        1, stopCoords.x, stopCoords.y, stopCoords.z - 1.0,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        radius, radius, 1.0,
        color[1], color[2], color[3], 45,
        false, false, 2, false, nil, nil, false
    )
    DrawMarker(
        0, stopCoords.x, stopCoords.y, stopCoords.z + 3.2,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        1.1, 1.1, 1.1,
        color[1], color[2], color[3], 210,
        true, false, 2, true, nil, nil, false
    )
end

-- ─────────────────────────────────────────────────────────────
--  Ciclos
-- ─────────────────────────────────────────────────────────────
CreateThread(function()
    createDepot()

    while true do
        local waitTime = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local prompt

        if not terminalOpen and not serviceActive and not starting then
            if #(coords - depotVector) <= Config.InteractionDistance then
                waitTime = 0
                prompt = { key = Config.KeyLabel, text = _U('prompt_terminal'), sub = _U('depot') }
                if IsControlJustReleased(0, Config.Key) then
                    openTerminal()
                    prompt = nil
                end
            end
        end

        if routeState and not serviceActive then
            if not DoesEntityExist(routeState.bus) then
                -- Pode ser só a rede a demorar: desiste depois de 3 ciclos seguidos.
                routeState.busMissing = (routeState.busMissing or 0) + 1
                if routeState.busMissing >= 3 then
                    cancelRoute(true, false, 'route_failed_lost')
                end
            else
                routeState.busMissing = 0
                waitTime = math.min(waitTime, 500)
                local stop = currentStop()
                local kind = stopKind(routeState.route, routeState.nextStop)
                local stopCoords = stop.stop_coord
                local stopDistance = #(coords - stopCoords)

                Passengers.update(routeState.nextStop, kind == 'pickup' and stop or NO_PASSENGERS, stopDistance)

                if stopDistance < 65.0 then
                    waitTime = 0
                    drawStopMarker(stopCoords, kind, stageRadius(routeState.route, routeState.nextStop))
                end

                if stopDistance <= stageRadius(routeState.route, routeState.nextStop)
                    and GetPedInVehicleSeat(routeState.bus, -1) == ped then
                    waitTime = 0
                    if GetEntitySpeed(routeState.bus) <= Config.StopSpeedLimit then
                        prompt = {
                            key = Config.KeyLabel,
                            text = _U(KIND_STYLE[kind].prompt),
                            sub = _U('prompt_stop_n', routeState.nextStop, stageCount(routeState.route)),
                        }
                        if IsControlJustReleased(0, Config.Key) then
                            prompt = nil
                            serviceCurrentStop()
                        end
                    else
                        prompt = { text = _U('must_stop'), warn = true }
                    end
                end
            end
        end

        if IsPauseMenuActive() then
            prompt = nil
        end
        setPrompt(prompt)
        Wait(waitTime)
    end
end)

-- Painel da rota: velocidade, distância, passageiros, estado do autocarro.
CreateThread(function()
    while true do
        local current = routeState
        if current and DoesEntityExist(current.bus) then
            local bus = current.bus
            local multiplier = Config.SpeedUnit == 'mph' and 2.236936 or 3.6
            local health = math.max(0.0, math.min(1.0,
                (GetVehicleBodyHealth(bus) + GetVehicleEngineHealth(bus)) / 2000))
            local stop = currentStop()
            local distance = stop and #(GetEntityCoords(bus) - stop.stop_coord) or 0.0

            -- Mesma conta do servidor: conta o que for maior entre as multas e o desgaste.
            local reward = current.route.rewards.money * Config.RewardMultiplier
            local cap = reward * (1 - Config.MinimumConditionMultiplier)
            local damage = reward * (1 - math.max(Config.MinimumConditionMultiplier, health))
            local deduction = damage
            if Config.Penalties.enabled then
                deduction = math.max(current.penalty, damage)
            end
            deduction = math.min(cap, deduction)

            nui('hud:tick', {
                speed = math.floor(GetEntitySpeed(bus) * multiplier + 0.5),
                health = math.floor(health * 100 + 0.5),
                distance = math.floor(distance),
                elapsed = (GetGameTimer() - current.startedAt) // 1000,
                passengers = current.passengers,
                stop = current.nextStop,
                estimate = math.floor(reward - deduction),
                penalty = math.floor(deduction),
                collisions = current.collisions,
                speeding = current.speeding,
            })
            Wait(150)
        else
            Wait(500)
        end
    end
end)

RegisterCommand('busjob', function()
    if #(GetEntityCoords(PlayerPedId()) - depotVector) <= Config.InteractionDistance then
        openTerminal()
    else
        notify('too_far', 'error')
    end
end, false)

RegisterCommand('buscancel', function()
    cancelRoute(true, true)
end, false)

-- Diagnóstico: escreve o estado do turno na consola do jogo (F8).
RegisterCommand('busjobinfo', function()
    local resource = GetCurrentResourceName()
    if not routeState then
        print(('[%s] Sem turno a decorrer.'):format(resource))
        return
    end

    local bus = routeState.bus
    local alive = bus and DoesEntityExist(bus)
    print(('[%s] rota %d "%s" | paragem %d/%d (%s) | passageiros %d (sentados %d, lugares livres %d)')
        :format(resource, routeState.routeId, routeState.route.label,
            routeState.nextStop, stageCount(routeState.route),
            stopKind(routeState.route, routeState.nextStop),
            routeState.passengers, Passengers.count(),
            alive and Passengers.freeSeats(bus) or 0))
    print(('[%s] autocarro: existe=%s netId=%s ao volante=%s | multas $%d | a servir=%s')
        :format(resource, tostring(alive), tostring(routeState.netId),
            tostring(alive and GetPedInVehicleSeat(bus, -1) == PlayerPedId()),
            routeState.penalty, tostring(serviceActive)))
end, false)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    SetNuiFocus(false, false)
    TriggerScreenblurFadeOut(0.0)
    if routeState then
        TriggerServerEvent('gg_busjob_advanced:cancelOnClientStop', routeState.token)
    end
    Passengers.clearAll()
    if depotPed and DoesEntityExist(depotPed) then
        DeleteEntity(depotPed)
    end
    if depotBlip and DoesBlipExist(depotBlip) then
        RemoveBlip(depotBlip)
    end
    clearRoute()
end)
