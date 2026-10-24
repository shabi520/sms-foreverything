--- 通用编码/签名工具：base64、URL 编码、HMAC-SHA256、JSON 字符串转义
local util_codec = {}

local crypto_lib = _G.crypto
local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

--- 十六进制字符串转二进制
-- @param hex 十六进制字符串
-- @return 二进制字符串
function util_codec.hex_to_bin(hex)
    if type(hex) ~= "string" then
        return ""
    end
    return (hex:gsub("%x%x", function(cc)
        return string.char(tonumber(cc, 16))
    end))
end

--- base64 编码（优先使用固件 crypto 库，缺失时使用纯 Lua 实现）
-- @param data 待编码字符串
-- @return base64 字符串
function util_codec.base64_encode(data)
    data = tostring(data or "")

    if crypto_lib and crypto_lib.base64_encode then
        local ok, result = pcall(crypto_lib.base64_encode, data)
        if ok and type(result) == "string" then
            return result
        end
    end

    local out = {}
    local i = 1
    while i + 2 <= #data do
        local a, b, c = data:byte(i), data:byte(i + 1), data:byte(i + 2)
        local n = a * 65536 + b * 256 + c
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64_CHARS:sub(c1 + 1, c1 + 1) .. B64_CHARS:sub(c2 + 1, c2 + 1)
            .. B64_CHARS:sub(c3 + 1, c3 + 1) .. B64_CHARS:sub(c4 + 1, c4 + 1)
        i = i + 3
    end

    local remain = #data - (i - 1)
    if remain == 1 then
        local n = data:byte(i) * 65536
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        out[#out + 1] = B64_CHARS:sub(c1 + 1, c1 + 1) .. B64_CHARS:sub(c2 + 1, c2 + 1) .. "=="
    elseif remain == 2 then
        local n = data:byte(i) * 65536 + data:byte(i + 1) * 256
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        out[#out + 1] = B64_CHARS:sub(c1 + 1, c1 + 1) .. B64_CHARS:sub(c2 + 1, c2 + 1)
            .. B64_CHARS:sub(c3 + 1, c3 + 1) .. "="
    end

    return table.concat(out)
end

--- URL 编码
-- @param str 原始字符串
-- @return 编码后的字符串
function util_codec.url_encode(str)
    return (tostring(str or ""):gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

--- HMAC-SHA256 后做 base64（钉钉/飞书加签使用）
-- @param data 待签名数据
-- @param key 密钥
-- @return base64 签名结果, 错误信息
function util_codec.hmac_sha256_base64(data, key)
    if not (crypto_lib and crypto_lib.hmac_sha256) then
        return nil, "固件缺少 crypto.hmac_sha256"
    end

    local ok, hex = pcall(crypto_lib.hmac_sha256, tostring(data or ""), tostring(key or ""))
    if not ok or type(hex) ~= "string" then
        return nil, "HMAC-SHA256 计算失败"
    end

    return util_codec.base64_encode(util_codec.hex_to_bin(hex))
end

--- JSON 字符串转义（不含首尾双引号）
-- @param str 原始字符串
-- @return 转义后的字符串
function util_codec.json_escape(str)
    local text = tostring(str or "")

    local ok, encoded = pcall(json.encode, text)
    if ok and type(encoded) == "string" and #encoded >= 2 then
        return encoded:sub(2, -2)
    end

    local escaped = text:gsub("\\", "\\\\")
    escaped = escaped:gsub('"', '\\"')
    escaped = escaped:gsub("\r", "\\r")
    escaped = escaped:gsub("\n", "\\n")
    return escaped
end

return util_codec
