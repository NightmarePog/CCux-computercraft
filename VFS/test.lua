local VFS = require("vfs")
local fs = VFS:new()

-- 🗂️ Vytvoř složky
print("Vytvářím /home a /home/user ...")
fs:createDir("/home")
fs:createDir("/home/user")

-- 📄 Vytvoř soubor
print("Vytvářím /home/user/readme.txt ...")
fs:createFile("/home/user/readme.txt", "Toto je testovací soubor.")

-- 📖 Čtení souboru
local content, err = fs:readFile("/home/user/readme.txt")
if content then
  print("Obsah /home/user/readme.txt:", content)
else
  print("Chyba při čtení:", err)
end

-- 📋 Výpis obsahu složky
print("Obsah /home:")
local list, err = fs:list("/home")
if list then
  for _, item in ipairs(list) do
    print(" - " .. item)
  end
else
  print("Chyba při list:", err)
end

-- ❌ Mazání souboru
print("Mažu /home/user/readme.txt ...")
fs:remove("/home/user/readme.txt")

-- ✅ Zkus znovu načíst smazaný soubor
local contentAfter, err = fs:readFile("/home/user/readme.txt")
if not contentAfter then
  print("Očekávaná chyba po mazání:", err)
end

-- ✅ Hotovo
print("Testování dokončeno.")
