local colorMap = {
    black = colors.black,
    red = colors.red,
    green = colors.green,
    yellow = colors.yellow,
    blue = colors.blue,
    magenta = colors.magenta,
    cyan = colors.cyan,
    white = colors.white,
}

local function readManual(command)
    local path = "/man/" .. command .. ".man"
    local file = fs.open(path, "r")

    if not file then
        print("Manual for command '" .. command .. "' not found.")
        return
    end

    local content = file.readAll()
    file.close()

    for line in content:gmatch("[^\n]+") do
        local segments = {}
        for colorName, text in line:gmatch("<(%w+)>(.-)</>") do
            local color = colorMap[colorName]
            if color then
                table.insert(segments, {color = color, text = text})
            else
                print("Error: Unknown color '" .. colorName .. "'.")
            end
        end

        for _, segment in ipairs(segments) do
            term.setTextColor(segment.color)
            write(segment.text)
        end
    print()
    end

    term.setTextColor(colors.white)
end

local command = arg[1]

if command then
    readManual(command)
else
    print("Usage: man <command>")
end
