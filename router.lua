local component = require("component")
local event = require("event")
local m = component.modem
local tunnel = component.tunnel
m.open(80)

print("--- ROUTER ---")
while true do
  local _, recvAddr, sender, port, _, msg = event.pull("modem_message")
  
  if recvAddr == tunnel.address then
    m.broadcast(80, msg)
  else
    tunnel.send(msg)
    m.broadcast(80, msg)
    print("Пакет отправлен")
  end
end