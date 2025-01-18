local panic = {}

function panic.panic(error)
    term.setBackgroundColor(colors.red)
    term.clear()
    term.setTextColor(colors.white)
    print("SYSTEM PANIC")
    term.setCursorPos(1,3)
    print("Critical error occured")
    print("Error: ",error)
    print("")
    print("please report this error")
    print("Press Enter to contienue")
    while true do
        local event, param = os.pullEvent()
        if event == "key" and param == keys.enter then
            os.reboot()
        end
    end
end

return(panic)