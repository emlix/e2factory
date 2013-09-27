--- Errno translation.
-- @module generic.errno

-- Copyright (C) 2013 emlix GmbH, see file AUTHORS
--
-- This file is part of e2factory, the emlix embedded build system.
-- For more information see http://www.e2factory.org
--
-- e2factory is a registered trademark of emlix GmbH.
--
-- e2factory is free software: you can redistribute it and/or modify it under
-- the terms of the GNU General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- This program is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
-- more details.

local errno = {}

local strict = require("strict")
local err = require("err")

local def_to_num = {}
 -- awk '/^#define\tE/ { printf("def_to_num[\"%s\"] = %s\n", $2, $3)}'
 -- < /usr/include/asm-generic/errno-base.h
def_to_num["EPERM"] = 1
def_to_num["ENOENT"] = 2
def_to_num["ESRCH"] = 3
def_to_num["EINTR"] = 4
def_to_num["EIO"] = 5
def_to_num["ENXIO"] = 6
def_to_num["E2BIG"] = 7
def_to_num["ENOEXEC"] = 8
def_to_num["EBADF"] = 9
def_to_num["ECHILD"] = 10
def_to_num["EAGAIN"] = 11
def_to_num["ENOMEM"] = 12
def_to_num["EACCES"] = 13
def_to_num["EFAULT"] = 14
def_to_num["ENOTBLK"] = 15
def_to_num["EBUSY"] = 16
def_to_num["EEXIST"] = 17
def_to_num["EXDEV"] = 18
def_to_num["ENODEV"] = 19
def_to_num["ENOTDIR"] = 20
def_to_num["EISDIR"] = 21
def_to_num["EINVAL"] = 22
def_to_num["ENFILE"] = 23
def_to_num["EMFILE"] = 24
def_to_num["ENOTTY"] = 25
def_to_num["ETXTBSY"] = 26
def_to_num["EFBIG"] = 27
def_to_num["ENOSPC"] = 28
def_to_num["ESPIPE"] = 29
def_to_num["EROFS"] = 30
def_to_num["EMLINK"] = 31
def_to_num["EPIPE"] = 32
def_to_num["EDOM"] = 33
def_to_num["ERANGE"] = 34

-- /usr/include/asm-generic/errno.h
def_to_num["EDEADLK"] = 35
def_to_num["ENAMETOOLONG"] = 36
def_to_num["ENOLCK"] = 37
def_to_num["ENOSYS"] = 38
def_to_num["ENOTEMPTY"] = 39
def_to_num["ELOOP"] = 40
def_to_num["EWOULDBLOCK"] = def_to_num.EAGAIN
def_to_num["ENOMSG"] = 42
def_to_num["EIDRM"] = 43
def_to_num["ECHRNG"] = 44
def_to_num["EL2NSYNC"] = 45
def_to_num["EL3HLT"] = 46
def_to_num["EL3RST"] = 47
def_to_num["ELNRNG"] = 48
def_to_num["EUNATCH"] = 49
def_to_num["ENOCSI"] = 50
def_to_num["EL2HLT"] = 51
def_to_num["EBADE"] = 52
def_to_num["EBADR"] = 53
def_to_num["EXFULL"] = 54
def_to_num["ENOANO"] = 55
def_to_num["EBADRQC"] = 56
def_to_num["EBADSLT"] = 57
def_to_num["EDEADLOCK"] = def_to_num.EDEADLK
def_to_num["EBFONT"] = 59
def_to_num["ENOSTR"] = 60
def_to_num["ENODATA"] = 61
def_to_num["ETIME"] = 62
def_to_num["ENOSR"] = 63
def_to_num["ENONET"] = 64
def_to_num["ENOPKG"] = 65
def_to_num["EREMOTE"] = 66
def_to_num["ENOLINK"] = 67
def_to_num["EADV"] = 68
def_to_num["ESRMNT"] = 69
def_to_num["ECOMM"] = 70
def_to_num["EPROTO"] = 71
def_to_num["EMULTIHOP"] = 72
def_to_num["EDOTDOT"] = 73
def_to_num["EBADMSG"] = 74
def_to_num["EOVERFLOW"] = 75
def_to_num["ENOTUNIQ"] = 76
def_to_num["EBADFD"] = 77
def_to_num["EREMCHG"] = 78
def_to_num["ELIBACC"] = 79
def_to_num["ELIBBAD"] = 80
def_to_num["ELIBSCN"] = 81
def_to_num["ELIBMAX"] = 82
def_to_num["ELIBEXEC"] = 83
def_to_num["EILSEQ"] = 84
def_to_num["ERESTART"] = 85
def_to_num["ESTRPIPE"] = 86
def_to_num["EUSERS"] = 87
def_to_num["ENOTSOCK"] = 88
def_to_num["EDESTADDRREQ"] = 89
def_to_num["EMSGSIZE"] = 90
def_to_num["EPROTOTYPE"] = 91
def_to_num["ENOPROTOOPT"] = 92
def_to_num["EPROTONOSUPPORT"] = 93
def_to_num["ESOCKTNOSUPPORT"] = 94
def_to_num["EOPNOTSUPP"] = 95
def_to_num["EPFNOSUPPORT"] = 96
def_to_num["EAFNOSUPPORT"] = 97
def_to_num["EADDRINUSE"] = 98
def_to_num["EADDRNOTAVAIL"] = 99
def_to_num["ENETDOWN"] = 100
def_to_num["ENETUNREACH"] = 101
def_to_num["ENETRESET"] = 102
def_to_num["ECONNABORTED"] = 103
def_to_num["ECONNRESET"] = 104
def_to_num["ENOBUFS"] = 105
def_to_num["EISCONN"] = 106
def_to_num["ENOTCONN"] = 107
def_to_num["ESHUTDOWN"] = 108
def_to_num["ETOOMANYREFS"] = 109
def_to_num["ETIMEDOUT"] = 110
def_to_num["ECONNREFUSED"] = 111
def_to_num["EHOSTDOWN"] = 112
def_to_num["EHOSTUNREACH"] = 113
def_to_num["EALREADY"] = 114
def_to_num["EINPROGRESS"] = 115
def_to_num["ESTALE"] = 116
def_to_num["EUCLEAN"] = 117
def_to_num["ENOTNAM"] = 118
def_to_num["ENAVAIL"] = 119
def_to_num["EISNAM"] = 120
def_to_num["EREMOTEIO"] = 121
def_to_num["EDQUOT"] = 122
def_to_num["ENOMEDIUM"] = 123
def_to_num["EMEDIUMTYPE"] = 124
def_to_num["ECANCELED"] = 125
def_to_num["ENOKEY"] = 126
def_to_num["EKEYEXPIRED"] = 127
def_to_num["EKEYREVOKED"] = 128
def_to_num["EKEYREJECTED"] = 129
def_to_num["EOWNERDEAD"] = 130
def_to_num["ENOTRECOVERABLE"] = 131

--- Given a numeric error code (errno), translate it the corresponding
-- define string. Example: errno.errnum2def(1) => "EPERM".
-- @param errnum Error (errno) number;
-- @return Corresponding define name as a string, or false on error.
-- @return Error object on failure (errnum was out of range).
function errno.errnum2def(errnum)
    for k,v in pairs(def_to_num) do
        if v == errnum then
            return k
        end
    end

    return false, err.new("invalid errnum")
end

--- Translate errno define name to its errno number.
-- Example: errno.def2errnum("EPERM") => 1.
-- @param errdef Errno define as a string.
-- @return Corresponding errno number or false on error.
-- @return Error object on failure.
function errno.def2errnum(errdef)
    local d = def_to_num[errdef]

    if not d then
        return false, err.new("unknown definition")
    end

    return d
end

return strict.lock(errno)

-- vim:sw=4:sts=4:et:
