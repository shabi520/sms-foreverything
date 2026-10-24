--- SMTP 邮件发送（基于 socket + TLS，仅支持串行调用）
local util_codec = require "util_codec"

local util_smtp = {}

local ctrl = nil
-- socket 事件状态，回调中只做标记，业务逻辑在主任务中轮询
local ev = {
    online = false,
    closed = false,
    data = false,
}

local function socket_cb(netc, event, param)
    if event == socket.ON_LINE then
        ev.online = (param == 0)
    elseif event == socket.EVENT then
        ev.data = true
    elseif event == socket.CLOSED then
        ev.closed = true
    end
end

local function now_ms()
    return mcu.ticks()
end

local function close_socket()
    if ctrl then
        pcall(socket.close, ctrl)
        ctrl = nil
    end
end

local function abort(msg)
    close_socket()
    return false, msg
end

--- 读取 socket 中已缓存的数据
local function read_available()
    if socket.read then
        local ok, data = socket.read(ctrl, 4096)
        if ok and type(data) == "string" and #data > 0 then
            return data
        end
        return nil
    end

    if _G.zbuff then
        local buff = zbuff.create(4096)
        local ok, len = socket.rx(ctrl, buff)
        if ok and len and len > 0 then
            return buff:toStr(0, len)
        end
    end

    return nil
end

--- 等待并读取一段数据
local function sock_read(timeout)
    local deadline = now_ms() + timeout
    while now_ms() < deadline do
        if ev.data then
            ev.data = false
            local data = read_available()
            if data then
                return data
            end
        end
        if ev.closed then
            return nil, "连接已关闭"
        end
        sys.wait(50)
    end
    return nil, "读取超时"
end

--- 写入数据（分片发送，避免发送缓冲区溢出）
local function sock_write(data)
    local sent = 0
    local total = #data
    while sent < total do
        local chunk = data:sub(sent + 1, math.min(sent + 512, total))
        local ok, full = socket.tx(ctrl, chunk)
        if not ok then
            return false, "发送数据失败"
        end
        if full then
            return false, "发送缓冲区已满"
        end
        sent = sent + #chunk
        sys.wait(20)
    end
    return true
end

--- 解析 SMTP 响应码，支持多行响应
local function parse_reply(buf)
    local pos = 1
    while true do
        local s, e, code, sep = string.find(buf, "(%d%d%d)([ -])\r?\n", pos)
        if not s or s ~= pos then
            return nil
        end
        if sep == " " then
            return tonumber(code)
        end
        pos = e + 1
    end
end

--- 读取完整 SMTP 响应
local function read_reply(timeout)
    local buf = ""
    local deadline = now_ms() + timeout
    while now_ms() < deadline do
        local data = sock_read(deadline - now_ms())
        if not data then
            break
        end
        buf = buf .. data
        local code = parse_reply(buf)
        if code then
            return code, buf
        end
    end
    return nil, buf
end

--- 发送一条 SMTP 命令并校验响应码
local function smtp_cmd(cmd_text, expect)
    local ok, err = sock_write(cmd_text .. "\r\n")
    if not ok then
        return nil, err
    end

    local code, reply = read_reply(20000)
    if not code then
        return nil, "响应超时: " .. tostring(reply or "")
    end
    if expect and code ~= expect then
        return nil, string.format("响应异常: %d %s", code, tostring(reply or ""))
    end
    return code, reply
end

--- 建立连接（TLS 握手由底层完成）
local function smtp_connect(host, port, use_tls, timeout)
    ev.online, ev.closed, ev.data = false, false, false

    ctrl = socket.create(nil, socket_cb)
    if not ctrl then
        return false, "socket 创建失败"
    end

    pcall(socket.debug, ctrl, false)

    local cfg_ok = socket.config(ctrl, nil, false, use_tls and true or false)
    if cfg_ok == false then
        return abort("socket 配置失败")
    end

    local ok, linked = socket.connect(ctrl, host, port)
    if not ok then
        return abort("连接 " .. tostring(host) .. ":" .. tostring(port) .. " 失败")
    end
    if linked then
        ev.online = true
    end

    local deadline = now_ms() + timeout
    while not ev.online and not ev.closed and now_ms() < deadline do
        sys.wait(100)
    end

    if not ev.online then
        return abort("连接超时或被服务器关闭")
    end
    return true
end

local function wrap_base64(data, width)
    local lines = {}
    for i = 1, #data, width do
        lines[#lines + 1] = data:sub(i, i + width - 1)
    end
    return table.concat(lines, "\r\n")
end

--- 构造邮件内容（主题和正文均使用 base64，避免中文乱码）
local function build_mail(opts)
    local rcpt = {}
    for _, addr in ipairs(opts.to) do
        rcpt[#rcpt + 1] = "<" .. addr .. ">"
    end

    local lines = {
        "From: <" .. opts.from .. ">",
        "To: " .. table.concat(rcpt, ", "),
        "Subject: =?UTF-8?B?" .. util_codec.base64_encode(opts.subject) .. "?=",
        "MIME-Version: 1.0",
        "Content-Type: text/plain; charset=UTF-8",
        "Content-Transfer-Encoding: base64",
        "",
        wrap_base64(util_codec.base64_encode(opts.content), 76),
    }
    return table.concat(lines, "\r\n")
end

--- 发送邮件
-- @param opts 配置表：
--   host/port/ssl/user/password/from/to(数组)/subject/content
-- @return true成功, false失败, 错误信息
function util_smtp.send(opts)
    if not _G.socket or not _G.sys then
        return false, "固件缺少 socket/sys 库"
    end
    if type(opts) ~= "table" or type(opts.to) ~= "table" or #opts.to == 0 then
        return false, "邮件参数错误"
    end

    local ok, err = smtp_connect(opts.host, opts.port, opts.ssl, 30000)
    if not ok then
        return false, err
    end

    -- 服务器欢迎信息
    local code, reply = read_reply(30000)
    if not code then
        return abort("读取欢迎信息超时")
    end
    if code ~= 220 then
        return abort("服务器拒绝连接: " .. tostring(code) .. " " .. tostring(reply or ""))
    end

    -- EHLO
    code, reply = smtp_cmd("EHLO luatos", 250)
    if not code then
        return abort(reply)
    end

    -- AUTH LOGIN
    code, reply = smtp_cmd("AUTH LOGIN", 334)
    if not code then
        return abort(reply)
    end
    code, reply = smtp_cmd(util_codec.base64_encode(opts.user), 334)
    if not code then
        return abort(reply)
    end
    code, reply = smtp_cmd(util_codec.base64_encode(opts.password), 235)
    if not code then
        return abort(reply)
    end

    -- 发件人与收件人
    code, reply = smtp_cmd("MAIL FROM:<" .. opts.from .. ">", 250)
    if not code then
        return abort(reply)
    end

    for _, addr in ipairs(opts.to) do
        code, reply = smtp_cmd("RCPT TO:<" .. addr .. ">")
        if not code or (code ~= 250 and code ~= 251) then
            return abort("收件人被拒绝 " .. addr .. ": " .. tostring(reply or ""))
        end
    end

    -- 邮件内容
    code, reply = smtp_cmd("DATA", 354)
    if not code then
        return abort(reply)
    end

    ok, err = sock_write(build_mail(opts) .. "\r\n.\r\n")
    if not ok then
        return abort(err)
    end

    code, reply = read_reply(30000)
    if code ~= 250 then
        return abort("邮件提交失败: " .. tostring(code) .. " " .. tostring(reply or ""))
    end

    smtp_cmd("QUIT", 221)
    close_socket()

    return true
end

return util_smtp
