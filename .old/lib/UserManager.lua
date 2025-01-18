local sha256 = require("/lib/sha256")
local userManager = {}
local config = require("/conf/sysConfig")
local lang = require("/lang/"..config["lang"])

-- TODO remake for error API usage




function userManager.createUser(user,password, permissions)
if not user or not password or not permissions then 
    error(lang.notEnoughParameters..user..password..permissions) 
end
local encryptedPassword = sha256.hash(password)
updateJSON({
        ["user"] = user,
        ["password"] = encryptedPassword,
        ["permissions"] = permissions
    }
)
end

function userManager.deleteUser(user,password)
    if not user or not password then
        error(lang.notEnoughParameters)
        return
    end
        local usersFile = fs.open("/usr/users.lua","r")
        if not usersFile then 
            error(lang.userFileNotFound)
            return
        end
    local users = textutils.unserialize(usersFile.readAll())
    usersFile.close()
    if not findUser(users, user) then
        return
    end
    local toDeleteUser = findUser(users, user)
    if sha256.hash(password) ~= users[toDeleteUser].password then
        error(lang.InnorectPassword)
        return
    end 
    users[toDeleteUser] = nil
    local packedWithDeletedUser = textutils.serialize(users)
    local file = fs.open("usr/users.lua","w")
    file.write(packedWithDeletedUser)
    file.close()
end
function userManager.Login(user,password)
    if not user or not password then
        error(lang.notEnoughParameters)
        return
    end
    local usersFile = fs.open("usr/users.lua","r")
    if not usersFile then 
        error(lang.userFileNotFound)
        return
    end
    local file = usersFile.readAll()
    local users = textutils.unserialize(file)
    usersFile.close()
    if not findUser(users, user) then
        return
    end
    local loginingAs = findUser(users,user)
    if sha256.hash(password) == users[loginingAs].password then
        return true
    end
end


function findUser(usersTable, user)
    for i, v in pairs(usersTable) do
        if v.user == user then
            return i
        end
    end
    
end

function updateJSON(variableData)
    local filename = "/usr/users.lua"

    local file = fs.open(filename, "r")
    if not file then
        return
    end

    local content = file.readAll()
    file.close()

    local users = textutils.unserialize(content) or {}

    table.insert(users, variableData)

    local updatedContent = textutils.serialize(users)

    file = fs.open(filename, "w")
    file.write(updatedContent)
    file.close()
end





return userManager
