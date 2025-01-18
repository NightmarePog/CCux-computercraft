local userManager = require("/lib/UserManager")
local config = require("/conf/sysConfig")
local lang = require("/lang/"..config["lang"])

function main()
    while true do
        local usersFile = fs.open("/usr/users.lua","r")
            if not usersFile then 
                error(lang.userFileNotFound)
                return
            end
        local users = textutils.unserialize(usersFile.readAll())
        if not users then
            print("please create a new profile")
            print("username: ")
            local username = read()
            print("password: ")
            local password = read("*")
            userManager.createUser(username, password, "sudo")
            print("account created sucesfully!")
            print("press any key to continue...")
            os.pullEvent("key")
        else
            term.write("login: ")
            local login = read()
            term.write("password: ")
            local password = read("*")
            if userManager.Login(login, password) then
                _G.user = login
                shell.run("/core/YuuShell")
                break
            else
                sleep(2)
                term.setTextColor(colors.red)
                print("incorrect username or password")
                term.setTextColor(colors.white)
            end

        end
    end



end

term.clear()
term.setCursorPos(1,1)
main()
