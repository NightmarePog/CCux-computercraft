-- ✍️ Minimal print
local function log(text)
  term.write(text .. "\n")
end

-- 📦 Load vfs.lua
local f = fs.open("/VFS/vfs.lua", "r")
local src = f.readAll()
f.close()
local vfs_loader, err = load(src, "/VFS/vfs.lua", "t", _ENV)
if not vfs_loader then error("Load error: " .. err) end
local VFS = vfs_loader()

-- 🚀 Load or Initialize
log("🔄 Loading latest snapshot...")
local fs = VFS.loadLatestSnapshot()
if not fs then
  log("❌ No snapshot found, creating new VFS...")
  fs = VFS:new()
else
  log("✅ Snapshot loaded.")
end

-- 🗂️ Create folders
log("📁 Creating /home and /home/user ...")
fs:createDir("/home")
fs:createDir("/home/user")

-- 📄 Create a file
log("📄 Creating /home/user/readme.txt ...")
fs:createFile("/home/user/readme.txt", "This is a test file.")

-- 📖 Read the file
local content, err = fs:readFile("/home/user/readme.txt")
if content then
  log("📖 Content of /home/user/readme.txt: " .. content)
else
  log("⚠️ Error reading file: " .. err)
end

-- 📋 List contents of folder
log("📂 Contents of /home:")
local list, err = fs:list("/home")
if list then
  for _, item in ipairs(list) do
    log(" - " .. item)
  end
else
  log("⚠️ Error listing folder: " .. err)
end

-- ❌ Delete the file
log("🗑️ Deleting /home/user/readme.txt ...")
fs:remove("/home/user/readme.txt")

-- ✅ Try reading the deleted file
local contentAfter, err = fs:readFile("/home/user/readme.txt")
if not contentAfter then
  log("✅ Expected error after deletion: " .. err)
end

-- 💾 Save snapshot
log("💾 Saving VFS snapshot...")
fs:saveSnapshot("/snapshots")

-- ✅ Done
log("✅ Testing complete. Waiting 5 seconds before exit...")
local t0 = os.clock()
while os.clock() - t0 < 5 do end
