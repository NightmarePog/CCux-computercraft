local sha256 = require("/lib/sha256")

local rsa = {}

function rsa.generate_key(password)
    local key = {}
    local hash = 0
    for i = 1, #password do
        hash = hash + string.byte(password, i)
    end
    for i = 1, 128 do
        key[i] = (hash + i) % 256
    end
    return key
end

function rsa.encrypt(data, key)
    local encrypted = {}
    for i = 1, #data do
        local byte = string.byte(data, i)
        local enc_byte = (byte + key[(i - 1) % #key + 1]) % 256
        table.insert(encrypted, enc_byte)
    end
    return encrypted
end

function rsa.decrypt(encrypted_data, key)
    local decrypted = ""
    for i = 1, #encrypted_data do
        local enc_byte = encrypted_data[i]
        local dec_byte = (enc_byte - key[(i - 1) % #key + 1]) % 256
        decrypted = decrypted .. string.char(dec_byte)
    end
    return decrypted
end

function rsa.encrypt_file(filename, password)
    local file = fs.open(filename, "r")
    if not file then return nil end
    local data = file.readAll()
    file.close()

    local key = rsa.generate_key(password)
    local encrypted_data = rsa.encrypt(data, key)

    local encrypted_file = fs.open(filename, "w")
    encrypted_file.write("THIS FILE IS ENCRYPTED\n")
    
    local hashed_password = sha256.hash(password)
    encrypted_file.write(hashed_password .. "\n")

    for _, byte in ipairs(encrypted_data) do
        encrypted_file.write(string.char(byte))
    end
    encrypted_file.close()
end

function rsa.decrypt_file(filename, password)
    local file = fs.open(filename, "r")
    if not file then return nil end
    local first_line = file.readLine()
    if first_line ~= "THIS FILE IS ENCRYPTED" then
        file.close()
        return nil
    end

    local hashed_password = file.readLine()
    local expected_hash = sha256.hash(password)
    
    if hashed_password ~= expected_hash then
        file.close()
        return nil
    end

    local encrypted_data = {}
    while true do
        local byte = file.read()
        if byte == nil then break end
        table.insert(encrypted_data, string.byte(byte))
    end
    file.close()

    local decrypted_data = rsa.decrypt(encrypted_data, rsa.generate_key(password))
    
    local decrypted_file = fs.open(filename, "w")
    decrypted_file.write(decrypted_data)
    decrypted_file.close()
end

return rsa
