local component = require("component")
local event = require("event")
local serial = require("serialization")
local fs = require("filesystem")

local m = component.isAvailable("modem") and component.modem or nil
local t = component.isAvailable("tunnel") and component.tunnel or nil

if m then m.open(80) end

if not fs.exists("/www") then 
  fs.makeDirectory("/www") 
end

if not fs.exists("/www/index.html") then
  local f = io.open("/www/index.html", "w")
  f:write("Basic web page. /www/index.html")
  f:close()
end

local MY_IP = "???"
if m then 
  MY_IP = m.address:sub(1,3)
elseif t then 
  MY_IP = t.address:sub(1,3) 
end

print("--- Web Server ---")
print("IP: " .. MY_IP)
print("Папка сайта: /www/index.html")
print("Жду запросы...")

while true do
  local _, recvAddr, sender, port, dist, msg = event.pull("modem_message")
  local success, data = pcall(serial.unserialize, msg or "")

  if success and type(data) == "table" and data.type == "GET" then
    if tostring(data.target) == MY_IP then
      print("\n[!] Запрос от: " .. tostring(sender):sub(1,4))
      print(" -> Читаю /www/index.html...")
      
      local file = io.open("/www/index.html", "r")
      local html_content = file:read("*a")
      file:close()

      print(" -> Отправляю страницу (" .. string.len(html_content) .. " байт)...")

      local response = serial.serialize({
        type = "HTTP_RES",
        body = html_content
      })

      if t and recvAddr == t.address then
        t.send(response)
      elseif m then
        m.broadcast(80, response)
      end
    end
  end
end