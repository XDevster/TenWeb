local component = require("component")
local event = require("event")
local serial = require("serialization")
local term = require("term")
local computer = require("computer")
local m = component.modem
local gpu = component.gpu

m.open(80)

local COLOR_DEFAULT = 0xFFFFFF
local COLOR_LINK = 0x33CCFF
local COLOR_UI = 0x555555

local click_zones = {}

local function get_page(url)
  if m.isWireless() then
    m.setStrength(5)
  end

  m.broadcast(80, serial.serialize({type="DNS_REQ", host=url}))
  
  local deadline = computer.uptime() + 5
  local target_ip = nil
  while computer.uptime() < deadline do
    local _, _, _, _, _, msg = event.pull(1, "modem_message")
    local success, res = pcall(serial.unserialize, msg or "")
    if success and res and res.type == "DNS_RES" then
      target_ip = res.ip
      break
    end
  end

  if not target_ip then return "<h1>Ошибка 404</h1>\nДомен не найден в сети." end
  
  if m.isWireless() then
    m.setStrength(5)
  end
  m.broadcast(80, serial.serialize({type="GET", target=target_ip}))
  
  deadline = computer.uptime() + 5
  while computer.uptime() < deadline do
    local _, _, _, _, _, msg = event.pull(1, "modem_message")
    local success, p_res = pcall(serial.unserialize, msg or "")
    
    if success and p_res and p_res.type == "HTTP_RES" then 
      return p_res.body
    end
  end
  
  return "<h1>Ошибка 502</h1>\nСервер не отвечает."
end

local function applyCustomColor(line)
  local color_hex, clean_text = line:match("<color=(0x%x+)>(.-)</color>")
  if color_hex and clean_text then
    gpu.setForeground(tonumber(color_hex))
    return clean_text
  end
  gpu.setForeground(COLOR_DEFAULT)
  return line
end

local function renderLine(line, row)
  line = applyCustomColor(line)
  
  local h1_text = line:match("<h1>(.-)</h1>")
  if h1_text then
    gpu.set(1, row, "========== " .. h1_text:upper() .. " ==========")
    return row + 1
  end

  local h2_text = line:match("<h2>(.-)</h2>")
  if h2_text then
    gpu.set(1, row, "-> " .. h2_text .. " <-")
    return row + 1
  end

  local url, link_text = line:match('<a href="(.-)">(.-)</a>')
  if url and link_text then
    gpu.setForeground(COLOR_LINK)
    gpu.set(1, row, "[ " .. link_text .. " ]")
    table.insert(click_zones, {row = row, start_col = 1, end_col = #link_text + 4, target = url})
    return row + 1
  end

  gpu.set(1, row, line)
  return row + 1
end

local function displayPage(page_text, url)
  term.clear()
  click_zones = {}
  local row = 2
  
  for line in page_text:gmatch("[^\r\n]+") do
    row = renderLine(line, row)
  end
  
  local w, h = gpu.getResolution()
  gpu.setForeground(COLOR_UI)
  gpu.set(1, h - 2, string.rep("_", w)) 
  gpu.set(1, h - 1, " URL сайта: " .. url)
  gpu.setForeground(COLOR_DEFAULT)
end

local function viewPage(page_content, url)
  displayPage(page_content, url)
  
  while true do
    local ev, _, x, y = event.pull()
    
    if ev == "touch" then
      for _, zone in ipairs(click_zones) do
        if y == zone.row and x >= zone.start_col and x <= zone.end_col then
          return zone.target
        end
      end
      return "ASK_INPUT"
    elseif ev == "key_down" then
      return "ASK_INPUT"
    end
  end
end

term.clear()
local next_url = nil
local first_run = true

while true do
  local url = ""
  
  if next_url and next_url ~= "ASK_INPUT" then
    url = next_url
    next_url = nil
  else
    gpu.setForeground(COLOR_DEFAULT)
    local w, h = gpu.getResolution()
    
    if first_run then
      term.clear()
      io.write("URL> ")
      url = io.read()
      first_run = false
    else
      gpu.set(1, h, string.rep(" ", w))
      term.setCursor(1, h)
      io.write("Перейти на URL> ")
      url = io.read()
    end
  end
  
  if url == "exit" then 
    term.clear()
    break 
  end
  
  term.clear()
  print("Загрузка...") 
  
  local page = get_page(url)
  next_url = viewPage(page, url)
end