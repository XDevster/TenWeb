local component = require("component")
local event = require("event")
local serial = require("serialization")
local term = require("term")
local computer = require("computer")
local m = component.modem

m.open(80)

local COLOR_GOOD = 0x00FF66 
local COLOR_WARN = 0xFFCC00
local COLOR_BAD = 0xFF3333
local COLOR_RESET = 0xFFFFFF

local function ping(url)
  m.broadcast(80, serial.serialize({type="DNS_REQ", host=url}))
  
  local deadline = computer.uptime() + 2
  local target_ip = nil
  
  while computer.uptime() < deadline do
    local _, _, _, _, _, msg = event.pull(0.2, "modem_message")
    local success, res = pcall(serial.unserialize, msg or "")
    if success and res and res.type == "DNS_RES" then
      target_ip = res.ip
      break
    end
  end

  if not target_ip then 
    print("Не удалось разрешить домен: DNS не отвечает или сайта нет.")
    return
  end

  print("Пингуем " .. url .. " [" .. tostring(target_ip) .. "]:")
  print("--------------------------------------------------")

  local packets_sent = 4
  local packets_received = 0
  
  for i = 1, packets_sent do
    local start_time = computer.uptime()
    
    m.broadcast(80, serial.serialize({type="GET", target=target_ip}))
    
    local received = false
    local timeout = start_time + 2
    
    while computer.uptime() < timeout do
      local _, _, _, _, _, msg = event.pull(0.1, "modem_message")
      local success, p_res = pcall(serial.unserialize, msg or "")
      
      if success and p_res and (p_res.type == "HTTP_RES" or p_res.type == "PONG") then
        local end_time = computer.uptime()
        local rtt = math.floor((end_time - start_time) * 1000)
        
        packets_received = packets_received + 1
        received = true
        
        local gpu = component.gpu
        if rtt < 50 then
          gpu.setForeground(COLOR_GOOD)
          print(string.format("Ответ от %s: время=%dмс связь=ОТЛИЧНАЯ", url, rtt))
        elseif rtt >= 50 and rtt < 150 then
          gpu.setForeground(COLOR_WARN)
          print(string.format("Ответ от %s: время=%dмс связь=НОРМАЛЬНАЯ", url, rtt))
        else
          gpu.setForeground(COLOR_BAD)
          print(string.format("Ответ от %s: время=%dмс связь=ПЛОХАЯ (ЗАДЕРЖКИ)", url, rtt))
        end
        gpu.setForeground(COLOR_RESET)
        
        break
      end
    end
    
    if not received then
      component.gpu.setForeground(COLOR_BAD)
      print("Запрос пакет " .. i .. ": Превышен интервал ожидания для запроса.")
      component.gpu.setForeground(COLOR_RESET)
    end
    
    os.sleep(0.5) -- Небольшая пауза между пакетами, чтобы не спамить сеть
  end

  print("--------------------------------------------------")
  local lost = packets_sent - packets_received
  print(string.format("Статистика: Отправлено = %d, Получено = %d, Потеряно = %d (%.0f%% потерь)", 
    packets_sent, packets_received, lost, (lost / packets_sent) * 100))
end

term.clear()
print("=== СЕТЕВАЯ УТИЛИТА PING ===")
io.write("Введите адрес сайта для проверки: ")
local host = io.read()

if host and host ~= "" then
  ping(host)
else
  print("Адрес не введен.")
end