local panic = require("/core/panic")
local config = require("/conf/sysConfig")
local lang = require("/lang/"..config["lang"])
function YuuShell()
    local x, y = 1,3
    local user = _G.user
    local programs = shell.programs()
    local selectedAutoComplete = 1
    local guiX, guiY = term.getSize()
    if not user then user = os.getComputerID() end
    local currectLine = ""
    -- os.pullEventRaw() -- DO NOT UNCOMMENT UNTIL YOU ARE SURE WHAT YOU ARE DOING
    function GetAutoComplete(param)
        local matches = {}
        for _, item in ipairs(programs) do
            if item:sub(1, #param) == param then
                table.insert(matches, item)
            end
        end
        return matches    
    end

    function autocomplete(param, key)
        term.write("                                                                        ")
        term.setCursorPos(x,y)
        if key then
            if keys.getName(key) == "up" then selectedAutoComplete = selectedAutoComplete+1
            elseif keys.getName(key) == "down" then selectAutoComplete = selectAutoComplete-1 end
        end
        if currectLine:gsub("%s+", "") == nil or currectLine:gsub("%s+", "") == "" then return nil end
        local tableWithParam = GetAutoComplete(param)
        if tableWithParam[1] == nil then return "" end
        local tableWithParam = GetAutoComplete(param)
        term.setCursorPos(x,y)
        local partOfSuggested = string.sub(tableWithParam[(selectedAutoComplete%#tableWithParam+1)], #param+1)
        term.setCursorPos(x,y)
        term.setBackgroundColor(colors.lightGray)
        term.write(partOfSuggested)
        term.setCursorPos(x,y)
        term.setBackgroundColor(colors.black)
        if key then
            if keys.getName(key) == "tab" then
                term.write(partOfSuggested)
                x = x+#partOfSuggested
                currectLine = currectLine..partOfSuggested
                term.setCursorPos(x,y)
            end
        end    
    end
    function shellInfo()
        term.setTextColour(colors.purple)
        term.write(user.."@"..shell.dir()..">" )
        term.setTextColour(colors.white)
        x,y = term.getCursorPos()
    end
    function execute(param)
        y = y+1
        x = 1
        term.setCursorPos(x,y)
        shell.run(currectLine)
        currectLine = ""
        shellInfo()
    end
    function removeChar()
        if currectLine == "" then return 0 end
        x = x-1
        term.setCursorPos(x,y)
        term.write(" ")
        term.setCursorPos(x,y)
        currectLine = currectLine:sub(1, -2)
    end

    function keyMacros(param)
        if keys.getName(param) == "backspace" then
            removeChar()
        elseif keys.getName(param) == "enter" then
            execute(param)    
        end
    end
        
    function WriteKey()
        while true do
            local event, param = os.pullEvent()
            
            if event == "char" then
                x = x+1
                term.write(param)
                term.setCursorPos(x,y)
                currectLine = currectLine..param
                autocomplete(currectLine)
    --            term.setCursorPos(6,6)
                    
            elseif event == "key" then
    --            term.setCursorPos(5,5)
    --            term.write(param)
    --            term.setCursorPos(x,y)
                keyMacros(param)
                autocomplete(currectLine,param)

    --            autocomplete(currectLine, param)    
            end
        end
    end

    function main()
        term.clear()
        term.setCursorPos(1,1)
        term.write(lang.ShellMotd)
        term.setCursorPos(1,2)
        term.write(string.rep("-",guiX))
            term.setCursorPos(1,3)
        shellInfo()
        term.setCursorBlink(true)
        WriteKey()
        
    end
    main()
end
local success, result = pcall(YuuShell)

if not success then
    panic.panic(result)
end
-- meow :3
-- meow meow :3
-- :3 :3
