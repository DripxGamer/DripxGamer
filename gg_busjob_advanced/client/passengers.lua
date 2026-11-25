-- Passageiros: peds locais (só o motorista os vê).
--   Esperam na paragem e entram a pé pela porta do autocarro, com a animação do jogo
--   (a porta abre, sentam-se). Nunca ocupam o lugar do condutor.
--   Nas paragens de largada saem pela porta e afastam-se a pé.
--   Se algum ficar preso (porta bloqueada, sem caminho), é sentado ou tirado à força no fim da paragem.

Passengers = {}

local cfg = Config.Passengers

-- Com Config.Debug ligado, a consola do jogo (F8) diz o que cada passageiro fez.
local function log(format, ...)
    if not Config.Debug then
        return
    end
    print(('[%s] passageiros: %s'):format(GetCurrentResourceName(),
        select('#', ...) > 0 and format:format(...) or format))
end

-- Tira o ped do cenário em que está parado. ClearPedTasks não chega: com
-- SetBlockingOfNonTemporaryEvents(true) o cenário ignora o pedido e o
-- passageiro fica especado no passeio. Era por isso que nem todos entravam.
local function wakeUp(ped)
    SetBlockingOfNonTemporaryEvents(ped, false)
    FreezeEntityPosition(ped, false)
    ClearPedTasksImmediately(ped)
end

local waiting = {}      -- à espera na paragem
local onboard = {}      -- sentados no autocarro: { ped, seat }
local leaving = {}      -- a afastar-se depois de saírem
local batch = {}        -- peds mexidos pela paragem em curso (para desfazer se falhar)
local reserved = {}     -- lugar -> ped que o vai ocupar
local jobs = {}         -- embarques e largadas em curso
local pending = {}      -- fecho forçado de cada trabalho no fim da paragem
local doorBusy          -- quem está a usar a porta neste momento (um de cada vez)
local spawnedFor
local generation = 0    -- sobe sempre que se limpa, para parar threads antigas

local function deletePed(ped)
    if ped and DoesEntityExist(ped) then
        SetEntityAsMissionEntity(ped, true, true)
        DeleteEntity(ped)
    end
end

local function deleteList(list)
    for _, ped in ipairs(list) do
        deletePed(ped)
    end
end

local function pickModels(count)
    local pool = {}
    for index, model in ipairs(cfg.models) do
        pool[index] = model
    end

    local picked = {}
    for _ = 1, count do
        if #pool == 0 then
            break
        end
        picked[#picked + 1] = table.remove(pool, math.random(#pool))
    end
    return picked
end

local function fadeAndDelete(list, token)
    CreateThread(function()
        for alpha = 200, 0, -50 do
            if token ~= generation then
                deleteList(list)    -- a paragem foi desfeita ou a rota acabou: não deixa ninguém para trás
                return
            end
            for _, ped in ipairs(list) do
                if DoesEntityExist(ped) then
                    SetEntityAlpha(ped, alpha, false)
                end
            end
            Wait(80)
        end
        deleteList(list)
    end)
end

local function distance2d(a, b)
    return #(vector2(a.x, a.y) - vector2(b.x, b.y))
end

-- Ponto no passeio junto à porta da frente do lado direito.
-- Só serve de alvo para quem não tem lugar. Devolve também o vetor "direita" do autocarro.
local function entrance(bus)
    local forward, right, _, position = GetEntityMatrix(bus)
    local along = forward

    local point
    local bone = GetEntityBoneIndexByName(bus, cfg.doorBone)
    if bone and bone ~= -1 then
        point = GetWorldPositionOfEntityBone(bus, bone)
    else
        local _, max = GetModelDimensions(GetEntityModel(bus))
        point = position + forward * (max.y * 0.55) + right * max.x
    end

    local ground = position.z - GetEntityHeightAboveGround(bus)
    local outside = point + right * cfg.doorOffset
    return vector3(outside.x, outside.y, ground), right, along
end

-- Lugares dos passageiros, nunca o -1 (condutor). Os pares ficam do lado direito (o da porta de
-- entrada, junto ao passeio); só depois se usam os do lado esquerdo.
local function seatOrder(bus)
    local last = GetVehicleModelNumberOfSeats(GetEntityModel(bus)) - 2
    local order = {}
    for seat = 0, last, 2 do
        order[#order + 1] = seat
    end
    for seat = 1, last, 2 do
        order[#order + 1] = seat
    end
    return order
end

-- O lugar da porta fica sempre livre: é por ele que toda a gente entra e sai.
local function pickSeat(bus)
    local doorSeat = cfg.boardSeat or 0
    for _, seat in ipairs(seatOrder(bus)) do
        if seat ~= doorSeat and not reserved[seat] and IsVehicleSeatFree(bus, seat) then
            return seat
        end
    end
end

-- Passageiro sentado: fica quieto, não voa pelo para-brisas e não sai sozinho.
local function settle(ped, seat)
    SetPedConfigFlag(ped, 32, false)
    SetPedConfigFlag(ped, 184, true)      -- não se arrasta para outro lugar
    SetPedCanBeDraggedOut(ped, false)
    SetPedCombatAttributes(ped, 3, false)
    SetPedKeepTask(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    onboard[#onboard + 1] = { ped = ped, seat = seat }
end

-- Último recurso, quando o jogo não consegue mesmo meter o passageiro pela porta.
-- Em vez de o atirar da rua para o banco à vista de toda a gente, ele apaga-se por
-- um instante à porta e aparece já sentado. Nunca se vê ninguém a teletransportar-se.
local function seatQuietly(ped, bus, seat)
    if not DoesEntityExist(ped) or not DoesEntityExist(bus) then
        return
    end
    local token = generation
    SetEntityAlpha(ped, 0, false)
    FreezeEntityPosition(ped, false)
    ClearPedTasksImmediately(ped)
    SetPedIntoVehicle(ped, bus, seat)
    settle(ped, seat)

    CreateThread(function()
        for alpha = 0, 255, 51 do
            if token ~= generation or not DoesEntityExist(ped) then
                return
            end
            SetEntityAlpha(ped, alpha, false)
            Wait(45)
        end
        if DoesEntityExist(ped) then
            ResetEntityAlpha(ped)
        end
    end)
end

local function startJob()
    local job = {}
    jobs[job] = true
    return job
end

local function endJob(job)
    jobs[job] = nil
end

function Passengers.clear()
    deleteList(waiting)
    waiting = {}
    spawnedFor = nil
end

-- Remove tudo: à espera, dentro do autocarro e a afastar-se.
function Passengers.clearAll()
    generation = generation + 1
    deleteList(waiting)
    for _, entry in ipairs(onboard) do
        deletePed(entry.ped)
    end
    deleteList(leaving)
    deleteList(batch)
    waiting, onboard, leaving, batch, reserved, jobs, pending = {}, {}, {}, {}, {}, {}, {}
    doorBusy = nil
    spawnedFor = nil
end

-- Começo de uma paragem: limpa o registo do que esta paragem vai mexer.
function Passengers.beginStop()
    batch = {}
    pending = {}
    doorBusy = nil
end

-- Fim da paragem: quem ficou a meio é resolvido já (sentado ou posto fora),
-- para a paragem nunca ficar presa à espera de uma animação encravada.
function Passengers.settleStop(bus)
    local finishers = pending
    pending = {}
    for _, finish in ipairs(finishers) do
        pcall(finish, bus)
    end
    jobs = {}
end

function Passengers.spawn(stopIndex, stop)
    Passengers.clear()
    spawnedFor = stopIndex

    local models = pickModels(#stop.npc_positions)
    for index, position in ipairs(stop.npc_positions) do
        local model = joaat(models[index] or models[1] or 'a_m_y_business_01')
        if pcall(lib.requestModel, model, 3000) then
            local ped = CreatePed(4, model, position.x, position.y, position.z - 1.0, position.w, false, false)
            if ped ~= 0 then
                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedFleeAttributes(ped, 0, false)
                SetEntityInvincible(ped, true)
                SetPedCanRagdoll(ped, false)
                TaskStartScenarioInPlace(ped, cfg.scenario, 0, true)
                FreezeEntityPosition(ped, true)
                waiting[#waiting + 1] = ped
            end
            SetModelAsNoLongerNeeded(model)
        end
    end
end

-- Chamado em cada ciclo da rota: faz aparecer/desaparecer os passageiros conforme a distância.
function Passengers.update(stopIndex, stop, distance)
    if not cfg.enabled then
        return
    end

    if spawnedFor and spawnedFor ~= stopIndex then
        Passengers.clear()
    end

    if spawnedFor == stopIndex then
        if distance > cfg.despawnDistance then
            Passengers.clear()
        end
        return
    end

    if #stop.npc_positions > 0 and distance <= cfg.spawnDistance then
        Passengers.spawn(stopIndex, stop)
    end
end

-- Quantos passageiros estão sentados (só os que se veem; o número da rota pode ser maior).
function Passengers.count()
    return #onboard
end

-- Quantos lugares estão livres: sem o do condutor e sem o da porta,
-- que fica sempre vago porque é por ele que se entra e se sai.
function Passengers.freeSeats(bus)
    if not bus or not DoesEntityExist(bus) then
        return 0
    end
    local doorSeat = cfg.boardSeat or 0
    local free = 0
    for _, seat in ipairs(seatOrder(bus)) do
        if seat ~= doorSeat and not reserved[seat] and IsVehicleSeatFree(bus, seat) then
            free = free + 1
        end
    end
    return free
end

-- Há alguém ainda a entrar ou a sair?
function Passengers.busy()
    return next(jobs) ~= nil
end

-- ─────────────────────────────────────────────────────────────
--  Entrar e sair SEMPRE pela porta
--
--  O problema de antes: pedia-se ao jogo para meter o passageiro num lugar
--  lá atrás. Esse lugar corresponde a uma porta que o autocarro não tem, e o
--  jogo resolve o assunto da maneira dele: teletransporta o ped para o banco.
--
--  Agora ninguém entra por outro lado senão o lugar da frente do lado do
--  passeio (`boardSeat`, o 0), que é o que o jogo liga à porta da frente.
--  Um de cada vez: os outros esperam no passeio, como numa fila. Quando o
--  passageiro já está DENTRO, muda-se de lugar — isso não se vê da rua.
--  Para sair faz-se o inverso: volta ao lugar da porta e só depois sai a pé.
-- ─────────────────────────────────────────────────────────────

local DOOR_SEAT = cfg.boardSeat or 0

local function doorFree()
    return doorBusy == nil or not DoesEntityExist(doorBusy)
end

-- Lugar real onde o jogo sentou o ped (às vezes não é o que pedimos).
local function seatOf(bus, ped)
    local last = GetVehicleModelNumberOfSeats(GetEntityModel(bus)) - 2
    for seat = -1, last do
        if GetPedInVehicleSeat(bus, seat) == ped then
            return seat
        end
    end
end

-- Embarque. Cada passageiro caminha até à porta e entra com a animação do jogo.
-- Quem o jogo não conseguir meter dentro vai até à porta e desvanece-se:
-- nunca aparece sentado do nada.
function Passengers.board(bus, duration)
    local mine = waiting
    waiting = {}
    for _, ped in ipairs(mine) do
        batch[#batch + 1] = ped
    end
    if #mine == 0 then
        return 0
    end

    local token = generation
    local startedAt = GetGameTimer()
    local job = startJob()
    local enterTimeout = cfg.enterTimeout or 9000
    local retries = cfg.enterRetries or 1
    local seatWait = cfg.seatWait or 3500

    local states = {}
    for index, ped in ipairs(mine) do
        states[index] = { ped = ped, order = index }
    end

    local function release(state)
        if state.final and reserved[state.final] == state.ped then
            reserved[state.final] = nil
        end
        state.final = nil
        if doorBusy == state.ped then
            doorBusy = nil
        end
    end

    local function close(state, fade)
        if state.done then
            return
        end
        state.done = true
        release(state)
        if fade and DoesEntityExist(state.ped) then
            ClearPedTasks(state.ped)
            fadeAndDelete({ state.ped }, token)
        end
    end

    local function finish(vehicle)
        vehicle = vehicle or bus
        if token == generation then
            for _, state in ipairs(states) do
                if not state.done and DoesEntityExist(state.ped) then
                    -- Ficou a meio quando a paragem acabou. Se ainda tem lugar,
                    -- senta-se sem se ver; senão, desaparece à porta.
                    local seat = state.final
                    if seat == nil and vehicle and DoesEntityExist(vehicle) then
                        seat = pickSeat(vehicle)
                    end
                    if cfg.seatQuietly ~= false and seat and vehicle and DoesEntityExist(vehicle)
                        and IsVehicleSeatFree(vehicle, seat) then
                        log('um passageiro ficou a meio da entrada; senta-se sem se ver')
                        state.done = true
                        if doorBusy == state.ped then
                            doorBusy = nil
                        end
                        reserved[seat] = state.ped
                        state.final = seat
                        seatQuietly(state.ped, vehicle, seat)
                    else
                        close(state, true)
                    end
                end
            end
        end
        endJob(job)
    end
    pending[#pending + 1] = finish

    CreateThread(function()
        local door, _, along = entrance(bus)
        local deadline = startedAt + duration - 500

        -- Lugar na bicha: cada um encosta-se um pouco mais atrás, junto à porta.
        local function queueSpot(index)
            local back = along * (-0.95 * (index - 1))
            return vector3(door.x + back.x, door.y + back.y, door.z)
        end

        while token == generation and DoesEntityExist(bus) do
            local now = GetGameTimer()
            local left = 0

            for _, state in ipairs(states) do
                if not state.done then
                    if not DoesEntityExist(state.ped) then
                        close(state, false)
                    else
                        left = left + 1
                        local ped = state.ped

                        if not state.phase then
                            -- Toda a gente caminha ao mesmo tempo até junto da porta.
                            -- Só a entrada em si é que é um de cada vez.
                            state.phase = 'queue'
                            state.limit = now + 12000
                            local spot = queueSpot(state.order)
                            wakeUp(ped)
                            TaskFollowNavMeshToCoord(ped, spot.x, spot.y, spot.z, cfg.walkSpeed, 10000, 0.6, 0, 0.0)

                        elseif state.phase == 'queue' then
                            local near = distance2d(GetEntityCoords(ped), door) < (cfg.queueRadius or 4.5)
                            if doorFree() and (near or now >= state.limit) then
                                local final = pickSeat(bus)
                                if final then
                                    state.final = final
                                    state.away = distance2d(GetEntityCoords(ped), door)
                                    reserved[final] = ped
                                    state.phase = 'door'
                                    state.tries = 1
                                    state.limit = now + enterTimeout
                                    doorBusy = ped
                                    if not near then
                                        log('um passageiro não chegou à porta a tempo (ficou a %.1f m); entra na mesma', state.away)
                                    end
                                    wakeUp(ped)
                                    TaskEnterVehicle(ped, bus, -1, DOOR_SEAT, cfg.walkSpeed, 1, 0)
                                elseif now >= startedAt + seatWait then
                                    -- Autocarro cheio: fica à porta e desvanece-se.
                                    state.phase = 'fade'
                                    state.limit = now + 4000
                                end
                            end

                        elseif state.phase == 'door' then
                            if IsPedInVehicle(ped, bus, false) then
                                -- Se entrou estando longe da porta, foi o jogo que o
                                -- teletransportou. Fica registado para se poder afinar.
                                if state.away and state.away > 3.5 then
                                    log('o jogo meteu um passageiro dentro a %.1f m da porta (teletransporte do motor)', state.away)
                                end
                                -- Já está dentro. Só agora muda de lugar: da rua não se vê.
                                local seat = state.final
                                if seat and seat ~= DOOR_SEAT and IsVehicleSeatFree(bus, seat) then
                                    SetPedIntoVehicle(ped, bus, seat)
                                end
                                seat = seatOf(bus, ped) or seat or DOOR_SEAT
                                if state.final and state.final ~= seat and reserved[state.final] == ped then
                                    reserved[state.final] = nil
                                end
                                reserved[seat] = ped
                                state.final = seat
                                state.done = true
                                doorBusy = nil
                                settle(ped, seat)
                            elseif now >= state.limit then
                                state.tries = state.tries + 1
                                if state.tries <= retries + 1 then
                                    ClearPedTasks(ped)
                                    TaskEnterVehicle(ped, bus, -1, DOOR_SEAT, cfg.walkSpeed, 1, 0)
                                    state.limit = now + enterTimeout
                                else
                                    -- O jogo não o deixou entrar. Se ainda há lugar, entra na
                                    -- mesma: apaga-se à porta e aparece sentado. Só desaparece
                                    -- de vez se o autocarro estiver mesmo cheio.
                                    local seat = state.final or pickSeat(bus)
                                    if cfg.seatQuietly ~= false and seat and IsVehicleSeatFree(bus, seat) then
                                        log('um passageiro não conseguiu entrar em %d tentativas; senta-se sem se ver', state.tries - 1)
                                        state.done = true
                                        state.final = seat
                                        reserved[seat] = ped
                                        if doorBusy == ped then
                                            doorBusy = nil
                                        end
                                        seatQuietly(ped, bus, seat)
                                    else
                                        log('um passageiro não conseguiu entrar e o autocarro está cheio; desaparece à porta')
                                        release(state)
                                        state.phase = 'fade'
                                        state.limit = now + 5000
                                        wakeUp(ped)
                                        TaskFollowNavMeshToCoord(ped, door.x, door.y, door.z, cfg.walkSpeed, 6000, 1.0, 0, 0.0)
                                    end
                                end
                            end

                        elseif distance2d(GetEntityCoords(ped), door) < 1.8 or now >= state.limit then
                            close(state, true)
                        end
                    end
                end
            end

            if left == 0 or GetGameTimer() >= deadline then
                break
            end
            Wait(100)
        end

        finish(bus)
    end)

    return #mine
end

-- Largada: `fraction` (0 a 1) dos passageiros sentados saem e afastam-se a pé.
-- Saem um de cada vez, também pela porta: primeiro voltam ao lugar da frente
-- (dentro do autocarro, não se vê) e só depois saem com a animação do jogo.
function Passengers.alight(bus, fraction, duration)
    local still = {}
    for _, ped in ipairs(leaving) do
        if DoesEntityExist(ped) then
            still[#still + 1] = ped
        end
    end
    leaving = still

    local total = #onboard
    local count = math.min(total, math.ceil(total * math.min(fraction, 1.0) - 0.0001))
    if count <= 0 then
        return 0
    end

    -- escolhe ao acaso quem sai
    local order = {}
    for index = 1, total do
        order[index] = index
    end
    for index = total, 2, -1 do
        local swap = math.random(index)
        order[index], order[swap] = order[swap], order[index]
    end

    local picked, chosen, staying = {}, {}, {}
    for index = 1, count do
        picked[order[index]] = true
    end
    for index, entry in ipairs(onboard) do
        if picked[index] then
            chosen[#chosen + 1] = entry
        else
            staying[#staying + 1] = entry
        end
    end
    onboard = staying

    local token = generation
    local job = startJob()
    local exitTimeout = cfg.exitTimeout or 6000

    local states = {}
    for index, entry in ipairs(chosen) do
        states[index] = { ped = entry.ped, seat = entry.seat }
        leaving[#leaving + 1] = entry.ped
        batch[#batch + 1] = entry.ped
    end

    local function done(state, fade)
        if state.done then
            return
        end
        state.done = true
        if state.seat and reserved[state.seat] == state.ped then
            reserved[state.seat] = nil
        end
        if doorBusy == state.ped then
            doorBusy = nil
        end
        if fade and DoesEntityExist(state.ped) then
            fadeAndDelete({ state.ped }, token)
        end
    end

    local function finish()
        if token == generation then
            for _, state in ipairs(states) do
                -- Quem ficou preso lá dentro desvanece-se; não é atirado para fora.
                done(state, not state.walking)
            end
        end
        endJob(job)
    end
    pending[#pending + 1] = finish

    CreateThread(function()
        local startedAt = GetGameTimer()
        local deadline = startedAt + duration - 300

        while token == generation do
            local now = GetGameTimer()
            local left = 0

            for _, state in ipairs(states) do
                if not state.done then
                    if not DoesEntityExist(state.ped) or not DoesEntityExist(bus) then
                        done(state, false)
                    else
                        left = left + 1
                        local ped = state.ped

                        if not state.phase then
                            if doorFree() then
                                state.phase = 'out'
                                state.limit = now + exitTimeout
                                doorBusy = ped
                                -- volta ao lugar da porta, por dentro
                                if IsPedInVehicle(ped, bus, false) and state.seat ~= DOOR_SEAT
                                    and IsVehicleSeatFree(bus, DOOR_SEAT) then
                                    SetPedIntoVehicle(ped, bus, DOOR_SEAT)
                                end
                                SetBlockingOfNonTemporaryEvents(ped, false)
                                ClearPedTasks(ped)
                                TaskLeaveVehicle(ped, bus, 0)
                            end

                        elseif state.phase == 'out' then
                            if not IsPedInVehicle(ped, bus, true) then
                                -- Já está na rua: afasta-se e desvanece-se.
                                state.walking = true
                                doorBusy = nil
                                if state.seat and reserved[state.seat] == ped then
                                    reserved[state.seat] = nil
                                end
                                local _, right, _, busPosition = GetEntityMatrix(bus)
                                local here = GetEntityCoords(ped)
                                local side = ((here.x - busPosition.x) * right.x + (here.y - busPosition.y) * right.y) >= 0 and 1.0 or -1.0
                                local away = here + right * (side * cfg.alightWalk)
                                TaskFollowNavMeshToCoord(ped, away.x, away.y, here.z, cfg.alightSpeed, 8000, 1.0, 0, 0.0)
                                local who = state
                                SetTimeout(cfg.alightLinger, function()
                                    if token == generation then
                                        done(who, true)
                                    end
                                end)
                                state.phase = 'away'
                            elseif now >= state.limit then
                                -- A porta não o deixou sair: segunda tentativa, mesma animação.
                                if not state.retried then
                                    state.retried = true
                                    state.limit = now + exitTimeout
                                    ClearPedTasks(ped)
                                    TaskLeaveVehicle(ped, bus, 0)
                                else
                                    log('um passageiro não conseguiu sair pela porta; desaparece lá dentro')
                                    done(state, true)
                                end
                            end
                        end
                    end
                end
            end

            if left == 0 then
                break
            end
            if GetGameTimer() >= deadline then
                finish()
                return
            end
            Wait(100)
        end

        endJob(job)
    end)

    return count
end

-- A paragem foi confirmada pelo servidor: o que aconteceu fica como está.
function Passengers.commit()
    batch = {}
    pending = {}
end

-- A paragem não foi concluída: desfaz o que ela fez. Quem ia entrar volta ao passeio.
function Passengers.abort()
    generation = generation + 1
    local undone = {}
    for _, ped in ipairs(batch) do
        undone[ped] = true
        deletePed(ped)
    end
    local staying = {}
    for _, entry in ipairs(onboard) do
        if not undone[entry.ped] then
            staying[#staying + 1] = entry
        end
    end
    onboard = staying
    for seat, ped in pairs(reserved) do
        if undone[ped] then
            reserved[seat] = nil
        end
    end
    deleteList(waiting)
    waiting = {}
    batch = {}
    jobs = {}
    pending = {}
    spawnedFor = nil
end
