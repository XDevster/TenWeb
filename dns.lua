local component = require("component")
local event = require("event")
local serial = require("serialization")
local fs = require("filesystem")
local term = require("term")

-- Берем модем напрямую
local m = component.proxy(component.list("modem")())
m.open(80)

local config_path = "/etc/dns.cfg"
local dns_table = {}

-- Загрузка конфига
if fs.exists(config_path) then
  local f = io.open(config_path, "r")
  dns_table = serial.unserialize(f:read("*a")) or {}
  f:close()
end

-- Функция сохранения таблицы в файл
local function save_dns()
  local f = io.open(config_path, "w")
  f:write(serial.serialize(dns_table))
  f:close()
end

term.clear()
print("--- DNS ---")
print("Доступные команды: add, del, list, clear, exit\n")

-- Функция обработки сетевых запросов
local function handleMessage(_, _, sender, port, _, msg)
  local success, data = pcall(serial.unserialize, msg or "")
  
  if success and data and data.type == "DNS_REQ" then
    local ip = dns_table[data.host]
    if ip then
      m.send(sender, 80, serial.serialize({type="DNS_RES", ip=ip}))
      print(string.format("[СЕТЬ] %s -> %s (Отправлено на %s)", tostring(data.host), tostring(ip), sender:sub(1,4)))
    else
      print(string.format("[СЕТЬ] %s -> НЕ НАЙДЕНО", tostring(data.host)))
    end
  end
end

-- Регистрируем слушателя
event.listen("modem_message", handleMessage)

-- Нормальная консоль для команд
while true do
  term.write("DNS> ", false)
  local input = term.read(nil, nil, nil, "")
  if input then
    -- Убираем лишние пробелы по краям и делим строку на аргументы
    input = input:gsub("^%s*(.-)%s*$", "%1")
    local args = {}
    for word in input:gmatch("%S+") do table.insert(args, word) end
    
    local cmd = args[1]
    
    if cmd == "add" then
      local host = args[2]
      local ip = args[3]
      if host and ip then
        dns_table[host] = ip
        save_dns()
        print(string.format("Успешно привязано: %s => %s", host, ip))
      else
        print("Ошибка! Используй: add [домен] [адрес_модема]")
      end
      
    elseif cmd == "del" then
      local host = args[2]
      if host then
        if dns_table[host] then
          dns_table[host] = nil
          save_dns()
          print(string.format("Домен %s успешно удален.", host))
        else
          print("Ошибка: такого домена нет в базе.")
        end
      else
        print("Ошибка! Используй: del [домен]")
      end
      
    elseif cmd == "list" then
      print("\n--- Список зарегистрированных доменов ---")
      local count = 0
      for k, v in pairs(dns_table) do
        print(string.format(" %s  =>  %s", k, v))
        count = count + 1
      end
      if count == 0 then print(" База данных пуста.") end
      print("-----------------------------------------\n")
      
    elseif cmd == "clear" then
      dns_table = {}
      save_dns()
      print("База данных полностью очищена.")
      
    elseif cmd == "exit" then
      event.ignore("modem_message", handleMessage)
      print("DNS-сервер остановлен.")
      break
      
    elseif input ~= "" then
      print("Неизвестная команда! Доступные: add, del, list, clear, exit")
    end
  end
end