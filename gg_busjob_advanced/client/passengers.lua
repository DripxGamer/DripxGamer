-- Passageiros: peds locais (só o motorista os vê).
--   Esperam na paragem e entram a pé pela porta do autocarro, com a animação do jogo
--   (a porta abre, sentam-se). Nunca ocupam o lugar do condutor.
--   Nas paragens de largada saem pela porta e afastam-se a pé.
--   Se algum ficar preso (porta bloqueada, sem caminho), é sentado ou tirado à força no fim da paragem.

Passengers = {}

local cfg = Config.Passengers

local waiting = {}      -- à espera na paragem
local onboard = {}      -- sentados no autocarro: { ped, seat }
local leaving = {}      -- a afastar-se depois de saírem
local batch = {}        -- peds mexidos pela paragem em curso (para desfazer se falhar)
local reserved = {}     -- lugar -> ped que o vai ocupar
local jobs = {}         -- embarques e largadas em curso
local pending = {}      -- fecho forçado de cada trabalho no fim da paragem
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
    return vector3(outside.x, outside.y, ground), right
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

local function pickSeat(bus)
    for _, seat in ipairs(seatOrder(bus)) do
        if not reserved[seat] and IsVehicleSeatFree(bus, seat) then
            return seat
        end
    end
end

-- Passageiro sentado: fica quieto, não voa pelo para-brisas e não sai sozinho.
local function settle(ped, seat)
    SetPedConfigFlag(ped, 32, false)
    SetPedCanBeDraggedOut(ped, false)
    SetPedCombatAttributes(ped, 3, false)
    SetPedKeepTask(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    onboard[#onboard + 1] = { ped = ped, seat = seat }
end

-- Último recurso: senta-o à força.
local function warpIn(ped, bus, seat)
    FreezeEntityPosition(ped, false)
    ClearPedTasksImmediately(ped)
    ResetEntityAlpha(ped)
    SetPedIntoVehicle(ped, bus, seat)
    settle(ped, seat)
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
    spawnedFor = nil
end

-- Começo de uma paragem: limpa o registo do que esta paragem vai mexer.
function Passengers.beginStop()
    batch = {}
    pending = {}
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

-- Quantos lugares (sem contar o do condutor) estão livres neste momento.
function Passengers.freeSeats(bus)
    if not bus or not DoesEntityExist(bus) then
        return 0
    end
    local free = 0
    for _, seat in ipairs(seatOrder(bus)) do
        if not reserved[seat] and IsVehicleSeatFree(bus, seat) then
            free = free + 1
        end
    end
    return free
end

-- Há alguém ainda a entrar ou a sair?
function Passengers.busy()
    return next(jobs) ~= nil
end

-- Embarque: cada passageiro caminha até à porta e entra com a animação do jogo.
-- `duration` é o máximo da paragem em ms; quem ainda não entrou 0,7 s antes do fim é sentado à força.
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
    local states = {}
    for index, ped in ipairs(mine) do
        states[index] = { ped = ped, at = startedAt + (index - 1) * cfg.stagger }
    end

    -- Fecho forçado: usado no fim da paragem e quando o tempo acaba.
    local function finish(vehicle)
        vehicle = vehicle or bus
        if token ~= generation then
            return
        end
        for _, state in ipairs(states) do
            if not state.done and DoesEntityExist(state.ped) then
                state.done = true
                if state.seat and vehicle and DoesEntityExist(vehicle) then
                    warpIn(state.ped, vehicle, state.seat)
                else
                    fadeAndDelete({ state.ped }, token)
                end
            end
        end
        endJob(job)
    end
    pending[#pending + 1] = finish

    CreateThread(function()
        local deadline = startedAt + duration - 700
        local door = entrance(bus)
        -- Quanto tempo se espera por um lugar livre antes de desistir
        -- (os passageiros que saem nesta paragem ainda estão a sair).
        local seatWait = cfg.seatWait or 3500

        while GetGameTimer() < deadline and token == generation and DoesEntityExist(bus) do
            local waitingOn = 0
            for _, state in ipairs(states) do
                local ped = state.ped
                if not state.done and DoesEntityExist(ped) then
                    waitingOn = waitingOn + 1
                    if not state.started then
                        if GetGameTimer() >= state.at then
                            state.seat = cfg.seated and pickSeat(bus) or nil
                            if state.seat then
                                state.started = true
                                reserved[state.seat] = ped
                                FreezeEntityPosition(ped, false)
                                ClearPedTasksImmediately(ped)
                                TaskEnterVehicle(ped, bus, duration, state.seat, cfg.walkSpeed, 1, 0)
                            elseif not cfg.seated or GetGameTimer() >= state.at + seatWait then
                                -- autocarro cheio: vai até à porta e desvanece-se
                                state.started = true
                                FreezeEntityPosition(ped, false)
                                ClearPedTasksImmediately(ped)
                                TaskFollowNavMeshToCoord(ped, door.x, door.y, door.z, cfg.walkSpeed, 6000, 1.0, 0, 0.0)
                            end
                        end
                    elseif state.seat then
                        if IsPedInVehicle(ped, bus, false) then
                            state.done = true
                            settle(ped, state.seat)
                        end
                    elseif distance2d(GetEntityCoords(ped), door) < 1.8 then
                        state.done = true
                        fadeAndDelete({ ped }, token)
                    end
                end
            end
            if waitingOn == 0 then
                break
            end
            Wait(100)
        end

        finish(bus)
    end)

    return #mine
end

-- Largada: `fraction` (0 a 1) dos passageiros sentados saem e afastam-se a pé.
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
    local remaining = #chosen

    local function oneDone()
        remaining = remaining - 1
        if remaining <= 0 then
            endJob(job)
        end
    end

    -- Fecho forçado no fim da paragem: a paragem nunca fica à espera de uma
    -- animação encravada. Quem ainda está dentro leva uma ordem de saída
    -- imediata e o próprio temporizador dele trata do resto (sair e desvanecer).
    pending[#pending + 1] = function(vehicle)
        vehicle = vehicle or bus
        if token ~= generation then
            return
        end
        for _, entry in ipairs(chosen) do
            local ped = entry.ped
            if DoesEntityExist(ped) and vehicle and DoesEntityExist(vehicle)
                and IsPedInVehicle(ped, vehicle, true) then
                TaskLeaveVehicle(ped, vehicle, 16)      -- 16 = sai de imediato
            end
            reserved[entry.seat] = nil
        end
        remaining = 0
        endJob(job)
    end

    for index, entry in ipairs(chosen) do
        local ped = entry.ped
        leaving[#leaving + 1] = ped
        batch[#batch + 1] = ped

        SetTimeout((index - 1) * cfg.stagger, function()
            if token ~= generation or not DoesEntityExist(ped) then
                reserved[entry.seat] = nil
                oneDone()
                return
            end

            -- sai com a animação do jogo e a porta a abrir
            if DoesEntityExist(bus) and IsPedInVehicle(ped, bus, false) then
                TaskLeaveVehicle(ped, bus, 0)
                local limit = GetGameTimer() + cfg.exitTimeout
                while IsPedInVehicle(ped, bus, true) and GetGameTimer() < limit
                    and token == generation and DoesEntityExist(ped) and DoesEntityExist(bus) do
                    Wait(100)
                end
                if token == generation and DoesEntityExist(ped) and DoesEntityExist(bus)
                    and IsPedInVehicle(ped, bus, true) then
                    TaskLeaveVehicle(ped, bus, 16)    -- ficou preso: sai de imediato
                    Wait(300)
                end
            end
            reserved[entry.seat] = nil
            oneDone()
            if token ~= generation or not DoesEntityExist(ped) then
                return
            end

            -- afasta-se do autocarro para o lado por onde saiu
            if DoesEntityExist(bus) then
                local _, right, _, busPosition = GetEntityMatrix(bus)
                local here = GetEntityCoords(ped)
                local side = ((here.x - busPosition.x) * right.x + (here.y - busPosition.y) * right.y) >= 0 and 1.0 or -1.0
                local away = here + right * (side * cfg.alightWalk)
                TaskFollowNavMeshToCoord(ped, away.x, away.y, here.z, cfg.alightSpeed, 8000, 1.0, 0, 0.0)
            end
            Wait(cfg.alightLinger)
            fadeAndDelete({ ped }, token)
        end)
    end

    -- Rede de segurança: se alguém nunca sair, a paragem não fica presa.
    SetTimeout(duration, function()
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
