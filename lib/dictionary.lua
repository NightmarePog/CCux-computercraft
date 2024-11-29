-- TODO create links

_G.dictionary = {}
local errorHandler = require("/lib/errorHandler")
function dictionary.GetChildrens(parent)
    list = {}
    if not fs.isDir(parent) then
        errorHandler.errorCode(20)
        return errorHandler.getLastErrorCode()
    end
    errorHandler.errorCode(0)
    return fs.list(parent)
end

function dictionary.GetDictionaryChildren(parent)
    if not fs.isDir(parent) then
        errorHandler.errorCode(20)
        return errorHandler.getLastErrorCode()
    end
    local Childrens = {}
    for index, value in ipairs(parent) do
        if fs.isDir(value) then
            table.insert(list, value)
        end
    end
    return Childrens
end

local function getDescendants(parent)
    if not fs.isDir(parent) then
        errorHandler.errorCode(20)
        return errorHandler.getLastErrorCode()
    end

    local files = {}

    local items = fs.list(parent)
    if items then
        for _, item in ipairs(items) do
            local fullPath = parent .. "/" .. item
            if fs.isDir(fullPath) then
                local subFiles = getDescendants(fullPath)
                for _, subFile in ipairs(subFiles) do
                    table.insert(files, subFile)
                end
            elseif fs.isFile(fullPath) then
                table.insert(files, fullPath)
            end
        end
    else
        return nil
    end

    return files
end

