_G.ErrorHandler = {}
local lastErrorCode = nil
local ErrorMessages = { -- I am pretty sure errors like "Cannot allocate memory" will never be used, I might clean it a bit later, I just coppied some Unix Error Codes
    [0] = "Success",
    [1] = "Operation not permitted",
    [2] = "No such file or directory",
    [3] = "No such process",
    [4] = "Interrupted system call",
    [5] = "Input/output error",
    [6] = "No such device or address",
    [7] = "Argument list too long",
    [8] = "Exec format error",
    [9] = "Bad file descriptor",
    [10] = "No child processes",
    [11] = "Resource temporarily unavailable",
    [12] = "Cannot allocate memory",
    [13] = "Permission denied",
    [14] = "Bad address",
    [15] = "Block device required",
    [16] = "Device or resource busy",
    [17] = "File exists",
    [18] = "Invalid cross-device link",
    [19] = "No such device",
    [20] = "Not a directory",
    [21] = "Is a directory",
    [22] = "Invalid argument",
    [23] = "Too many open files in system",
    [24] = "Too many open files",
    [25] = "Inappropriate ioctl for device",
    [26] = "Text file busy",
    [27] = "File too large",
    [28] = "No space left on device",
    [29] = "Illegal seek",
    [30] = "Read-only file system",
    [31] = "Too many links",
    [32] = "Broken pipe",
    [33] = "Numerical argument out of domain",
    [34] = "Numerical result out of range",
    [35] = "Resource deadlock avoided",
    [36] = "File name too long",
    [37] = "No locks available",
    [38] = "Function not implemented",
    [39] = "Directory not empty",
    [40] = "Too many levels of symbolic links",
    [42] = "No message of desired type",
    [43] = "Identifier removed",
    [44] = "Channel number out of range",
    [45] = "Level 2 not synchronized",
    [46] = "Level 3 halted",
    [47] = "Level 3 reset",
    [48] = "Link number out of range",
    [49] = "Protocol driver not attached",
    [50] = "No CSI structure available",
    [51] = "The name is already in use",
    [52] = "No record locks available",
    [53] = "The operation was canceled",
    [54] = "Connection reset by peer",
    [55] = "No route to host",
    [56] = "Operation already in progress",
    [57] = "Operation now in progress",
    [59] = "Message too long",
    [60] = "Protocol error",
    [61] = "No buffer space available",
    [62] = "Transport endpoint is not connected",
    [63] = "Network is down",
    [64] = "Network is unreachable",
    [65] = "Network dropped connection on reset",
    [66] = "Software caused connection abort",
    [67] = "Connection reset by peer",
    [68] = "No route to host",
    [69] = "Operation already in progress",
    [70] = "Operation now in progress",
    [71] = "Network is down",
    [72] = "Network is unreachable",
    [73] = "Network dropped connection on reset",
    [74] = "Software caused connection abort",
    [75] = "Connection reset by peer",
    [76] = "No route to host",
    [77] = "Operation already in progress",
    [78] = "Operation now in progress",
    [79] = "Error message dosen't exist"
}
function ErrorHandler.errorCode(errorCode)
    lastErrorCode = errorCode
end

function ErrorHandler.getLastErrorCode()
    return lastErrorCode
end

function ErrorHandler.getErrorMessage(errorCode)
        if not errorCode then
            if 78 <= lastErrorCode then
                return ErrorMessages[79]
            end
            return ErrorMessages[lastErrorCode]
        else
            if 78 <= errorCode then
                return ErrorMessages[79]
            end
            return ErrorMessages[errorCode]
        end  
end
