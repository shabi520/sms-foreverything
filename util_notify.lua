--- 通知转发模块：按 config.NOTIFY_CHANNEL 选择一个渠道发送，失败自动排队重试
local util_mobile = require "util_mobile"
local util_codec = require "util_codec"
local util_smtp = require "util_smtp"
local config = require "config"

local util_notify = {}

-- 引用全局日志输出函数
local function log_output(level, tag, ...)
    if _G.LOG_DEBUG_ENABLED then
        log[level](tag, ...)
    else
        if level == "info" then
            if config.POETRY_LOG_MODE then
                local verses = {
                    "床前明月光",
                    "疑是地上霜",
                    "举头望明月",
                    "低头思故乡"
                }
                local random_verse = verses[math.random(1, #verses)]
                log.error("李白", random_verse)
            end
        elseif level == "debug" then
            -- debug 信息不显示
        else
            log[level](tag, ...)
        end
    end
end

-- 消息队列
local msg_queue = {}
local msg_count = 0
local error_count = 0

local JSON_HEADERS = { ["Content-Type"] = "application/json; charset=utf-8" }

local TYPE_NAMES = {
    sms = "短信",
    status = "状态",
    heartbeat = "心跳",
}

local FIELD_LABELS = {
    type = "类型",
    status = "状态",
    sender = "发件号码",
    phone = "号码",
    content = "内容",
    time = "时间",
    imei = "IMEI",
    version = "版本",
    rsrp = "信号",
    oper = "运营商",
    network = "网络",
}

local FIELD_ORDER = {
    "type", "status", "sender", "phone", "content",
    "time", "imei", "version", "rsrp", "oper", "network",
}

local function non_empty(value)
    return type(value) == "string" and value ~= ""
end

local function trim_trailing_slash(url)
    if type(url) ~= "string" then
        return ""
    end
    return (url:gsub("/+$", ""))
end

local function split_list(text)
    local list = {}
    for item in tostring(text or ""):gmatch("[^,%s]+") do
        list[#list + 1] = item
    end
    return list
end

--- 将通知内容格式化为标题 + 可读文本
-- @param msg table 或 JSON 字符串
-- @return 标题, 文本
local function format_message(msg)
    if type(msg) == "string" then
        local ok, decoded = pcall(json.decode, msg)
        if ok and type(decoded) == "table" then
            msg = decoded
        end
    end

    if type(msg) ~= "table" then
        return "设备通知", tostring(msg)
    end

    local title = "设备通知"
    if msg.type == "status" then
        title = (msg.status == "online") and "设备上线" or "设备状态"
    elseif msg.type == "sms" then
        title = "短信通知"
    elseif msg.type == "heartbeat" then
        title = "设备心跳"
    end

    local lines = {}
    for _, key in ipairs(FIELD_ORDER) do
        local value = msg[key]
        if value ~= nil and value ~= "" then
            if key == "type" then
                value = TYPE_NAMES[value] or value
            end
            lines[#lines + 1] = (FIELD_LABELS[key] or key) .. ": " .. tostring(value)
        end
    end

    return title, table.concat(lines, "\n")
end

--- 发送 HTTP 请求，兼容新旧固件的 http.request 返回形式
local function http_request(method, url, headers, body, timeout)
    local ok, result, h, b = pcall(http.request, method, url, headers, body, { timeout = timeout })
    local type_result = type(result)

    if ok and (type_result == "table" or type_result == "userdata") then
        if type(result.wait) == "function" then
            local wait_ok, code, h, b = pcall(result.wait, result)
            if wait_ok then
                return code, h, b
            end
            return -1, nil, tostring(code)
        end
    elseif ok and type_result == "number" then
        return result, h, b
    end

    -- 兼容旧固件：第 5 个参数直接传超时毫秒
    local ok2, result2, h2, b2 = pcall(http.request, method, url, headers, body, timeout)
    local type_result2 = type(result2)

    if ok2 and (type_result2 == "table" or type_result2 == "userdata") then
        if type(result2.wait) == "function" then
            local wait_ok, code, h, b = pcall(result2.wait, result2)
            if wait_ok then
                return code, h, b
            end
            return -1, nil, tostring(code)
        end
    elseif ok2 and type_result2 == "number" then
        return result2, h2, b2
    end

    return -1, nil, tostring(ok and result or (ok2 and result2 or "http.request 调用失败"))
end

--- 各渠道请求构造器，返回 desc 或 nil, 错误信息
local builders = {}

-- 钉钉群机器人
builders.dingtalk = function(ctx)
    if not non_empty(config.DINGTALK_WEBHOOK) then
        return nil, "DINGTALK_WEBHOOK 未配置"
    end

    local url = config.DINGTALK_WEBHOOK
    if non_empty(config.DINGTALK_SECRET) then
        local timestamp = tostring(os.time() * 1000)
        local sign, err = util_codec.hmac_sha256_base64(
            timestamp .. "\n" .. config.DINGTALK_SECRET,
            config.DINGTALK_SECRET
        )
        if not sign then
            return nil, err or "钉钉加签失败"
        end
        url = url .. (url:find("?", 1, true) and "&" or "?")
            .. "timestamp=" .. timestamp .. "&sign=" .. util_codec.url_encode(sign)
    end

    return {
        url = url,
        headers = JSON_HEADERS,
        body = json.encode({ msgtype = "text", text = { content = ctx.text } }),
        ok_field = "errcode",
        ok_value = 0,
    }
end

-- 企业微信群机器人
builders.wecom = function(ctx)
    if not non_empty(config.WECOM_WEBHOOK) then
        return nil, "WECOM_WEBHOOK 未配置"
    end

    return {
        url = config.WECOM_WEBHOOK,
        headers = JSON_HEADERS,
        body = json.encode({ msgtype = "text", text = { content = ctx.text } }),
        ok_field = "errcode",
        ok_value = 0,
    }
end

-- 飞书群机器人
builders.feishu = function(ctx)
    if not non_empty(config.FEISHU_WEBHOOK) then
        return nil, "FEISHU_WEBHOOK 未配置"
    end

    local payload = {
        msg_type = "text",
        content = { text = ctx.text },
    }

    if non_empty(config.FEISHU_SECRET) then
        local timestamp = tostring(os.time())
        local sign, err = util_codec.hmac_sha256_base64("", timestamp .. "\n" .. config.FEISHU_SECRET)
        if not sign then
            return nil, err or "飞书加签失败"
        end
        payload.timestamp = timestamp
        payload.sign = sign
    end

    return {
        url = config.FEISHU_WEBHOOK,
        headers = JSON_HEADERS,
        body = json.encode(payload),
        ok_field = "code",
        ok_value = 0,
    }
end

-- 邮箱（SMTP 直连）
builders.email = function(ctx)
    if not non_empty(config.EMAIL_SMTP_HOST) then
        return nil, "EMAIL_SMTP_HOST 未配置"
    end
    if not non_empty(config.EMAIL_USER) or not non_empty(config.EMAIL_PASSWORD) then
        return nil, "EMAIL_USER / EMAIL_PASSWORD 未配置"
    end

    local to = split_list(config.EMAIL_TO)
    if #to == 0 then
        return nil, "EMAIL_TO 未配置"
    end

    local from = non_empty(config.EMAIL_FROM) and config.EMAIL_FROM or config.EMAIL_USER
    return {
        kind = "smtp",
        host = config.EMAIL_SMTP_HOST,
        port = tonumber(config.EMAIL_SMTP_PORT) or 465,
        ssl = config.EMAIL_SMTP_SSL ~= false,
        user = config.EMAIL_USER,
        password = config.EMAIL_PASSWORD,
        from = from,
        to = to,
        subject = tostring(config.EMAIL_SUBJECT_PREFIX or "") .. ctx.title,
        content = ctx.text,
    }
end

-- 自定义 Webhook
builders.webhook = function(ctx)
    if not non_empty(config.WEBHOOK_URL) then
        return nil, "WEBHOOK_URL 未配置"
    end

    local headers = {}
    for key, value in pairs(config.WEBHOOK_HEADERS or {}) do
        headers[key] = tostring(value)
    end
    if not headers["Content-Type"] then
        headers["Content-Type"] = config.WEBHOOK_CONTENT_TYPE or "application/json"
    end

    local body = config.WEBHOOK_BODY_TEMPLATE or '{"text":"${msg_json}"}'
    body = body:gsub("%${msg_json}", function() return util_codec.json_escape(ctx.text) end)
    body = body:gsub("%${title_json}", function() return util_codec.json_escape(ctx.title) end)
    body = body:gsub("%${msg}", function() return ctx.text end)
    body = body:gsub("%${title}", function() return ctx.title end)
    body = body:gsub("%${imei}", function() return ctx.imei or "" end)
    body = body:gsub("%${time}", function() return ctx.time or "" end)

    return {
        url = config.WEBHOOK_URL,
        method = config.WEBHOOK_METHOD or "POST",
        headers = headers,
        body = body,
    }
end

-- Gotify
builders.gotify = function(ctx)
    if not non_empty(config.GOTIFY_URL) or not non_empty(config.GOTIFY_TOKEN) then
        return nil, "GOTIFY_URL / GOTIFY_TOKEN 未配置"
    end

    local url = trim_trailing_slash(config.GOTIFY_URL) ..
        "/message?token=" .. util_codec.url_encode(config.GOTIFY_TOKEN)

    return {
        url = url,
        headers = JSON_HEADERS,
        body = json.encode({
            title = ctx.title,
            message = ctx.text,
            priority = tonumber(config.GOTIFY_PRIORITY) or 5,
        }),
    }
end

-- ntfy
builders.ntfy = function(ctx)
    if not non_empty(config.NTFY_TOPIC) then
        return nil, "NTFY_TOPIC 未配置"
    end

    local base = trim_trailing_slash(config.NTFY_URL or "https://ntfy.sh")
    local headers = {
        ["Content-Type"] = "text/plain; charset=utf-8",
        ["Priority"] = tostring(config.NTFY_PRIORITY or "default"),
    }
    if non_empty(config.NTFY_TOKEN) then
        headers["Authorization"] = "Bearer " .. config.NTFY_TOKEN
    end

    return {
        url = base .. "/" .. util_codec.url_encode(config.NTFY_TOPIC),
        headers = headers,
        body = ctx.title .. "\n" .. ctx.text,
    }
end

-- Bark
builders.bark = function(ctx)
    if not non_empty(config.BARK_KEY) then
        return nil, "BARK_KEY 未配置"
    end

    local base = trim_trailing_slash(config.BARK_URL or "https://api.day.app")
    local payload = {
        title = ctx.title,
        body = ctx.text,
        group = "EHM",
    }
    if non_empty(config.BARK_SOUND) then
        payload.sound = config.BARK_SOUND
    end

    return {
        url = base .. "/" .. util_codec.url_encode(config.BARK_KEY),
        headers = JSON_HEADERS,
        body = json.encode(payload),
        ok_field = "code",
        ok_value = 200,
    }
end

-- Server酱
builders.serverchan = function(ctx)
    if not non_empty(config.SERVERCHAN_KEY) then
        return nil, "SERVERCHAN_KEY 未配置"
    end

    local base = trim_trailing_slash(config.SERVERCHAN_URL or "https://sctapi.ftqq.com")
    local body = "title=" .. util_codec.url_encode(ctx.title) ..
        "&desp=" .. util_codec.url_encode(ctx.text)

    return {
        url = base .. "/" .. config.SERVERCHAN_KEY .. ".send",
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        body = body,
        ok_field = "code",
        ok_value = 0,
    }
end

-- PushPlus
builders.pushplus = function(ctx)
    if not non_empty(config.PUSHPLUS_TOKEN) then
        return nil, "PUSHPLUS_TOKEN 未配置"
    end

    return {
        url = "https://www.pushplus.plus/send",
        headers = JSON_HEADERS,
        body = json.encode({
            token = config.PUSHPLUS_TOKEN,
            title = ctx.title,
            content = ctx.text,
            template = "txt",
        }),
        ok_field = "code",
        ok_value = 200,
    }
end

-- PushDeer
builders.pushdeer = function(ctx)
    if not non_empty(config.PUSHDEER_KEY) then
        return nil, "PUSHDEER_KEY 未配置"
    end

    local base = trim_trailing_slash(config.PUSHDEER_URL or "https://api2.pushdeer.com")
    local url = base .. "/message/push?pushkey=" .. util_codec.url_encode(config.PUSHDEER_KEY) ..
        "&text=" .. util_codec.url_encode(ctx.title) ..
        "&desp=" .. util_codec.url_encode(ctx.text) ..
        "&type=text"

    return {
        url = url,
        method = "POST",
        headers = {},
        body = "",
        ok_field = "code",
        ok_value = 0,
    }
end

-- Telegram Bot
builders.telegram = function(ctx)
    if not non_empty(config.TELEGRAM_BOT_TOKEN) or not non_empty(config.TELEGRAM_CHAT_ID) then
        return nil, "TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID 未配置"
    end

    return {
        url = "https://api.telegram.org/bot" .. config.TELEGRAM_BOT_TOKEN .. "/sendMessage",
        headers = JSON_HEADERS,
        body = json.encode({
            chat_id = config.TELEGRAM_CHAT_ID,
            text = ctx.title .. "\n" .. ctx.text,
            disable_web_page_preview = true,
        }),
        ok_field = "ok",
        ok_value = true,
    }
end

-- Slack
builders.slack = function(ctx)
    if not non_empty(config.SLACK_WEBHOOK) then
        return nil, "SLACK_WEBHOOK 未配置"
    end

    return {
        url = config.SLACK_WEBHOOK,
        headers = JSON_HEADERS,
        body = json.encode({ text = "*" .. ctx.title .. "*\n" .. ctx.text }),
    }
end

-- Discord
builders.discord = function(ctx)
    if not non_empty(config.DISCORD_WEBHOOK) then
        return nil, "DISCORD_WEBHOOK 未配置"
    end

    return {
        url = config.DISCORD_WEBHOOK,
        headers = JSON_HEADERS,
        body = json.encode({ content = "**" .. ctx.title .. "**\n" .. ctx.text }),
    }
end

-- WxPusher
builders.wxpusher = function(ctx)
    if not non_empty(config.WXPUSHER_APP_TOKEN) then
        return nil, "WXPUSHER_APP_TOKEN 未配置"
    end

    local uids = split_list(config.WXPUSHER_UIDS)
    if #uids == 0 then
        return nil, "WXPUSHER_UIDS 未配置"
    end

    return {
        url = "https://wxpusher.zjiecode.com/api/send/message",
        headers = JSON_HEADERS,
        body = json.encode({
            appToken = config.WXPUSHER_APP_TOKEN,
            content = ctx.text,
            summary = ctx.title,
            contentType = 1,
            uids = uids,
        }),
        ok_field = "code",
        ok_value = 1000,
    }
end

--- 获取当前选择的通知渠道
-- @return 渠道名, 构造器 或 nil
local function active_channel()
    local name = config.NOTIFY_CHANNEL
    if not non_empty(name) or name == "none" then
        return nil
    end

    local builder = builders[name]
    if not builder then
        return nil
    end

    return name, builder
end

--- 发送一条构造好的请求
local function send_desc(desc)
    if desc.kind == "smtp" then
        local ok, err = util_smtp.send(desc)
        if not ok then
            log_output("error", "notify.send", "邮件发送失败", tostring(err))
        end
        return ok
    end

    local code, _, body = http_request(
        desc.method or "POST",
        desc.url,
        desc.headers or {},
        desc.body or "",
        tonumber(config.NOTIFY_HTTP_TIMEOUT) or 15000
    )

    if type(code) ~= "number" or code < 200 or code >= 300 then
        log_output("error", "notify.send", "HTTP通知失败", tostring(desc.url), "code:", tostring(code), body)
        return false
    end

    -- 校验接口业务返回码，例如钉钉 errcode、飞书 code
    if desc.ok_field then
        local ok, data = pcall(json.decode, body or "")
        if ok and type(data) == "table" then
            local value = data[desc.ok_field]
            if value ~= nil and value ~= desc.ok_value then
                log_output("error", "notify.send", "接口返回错误", desc.ok_field, tostring(value), body)
                return false
            end
        end
    end

    log_output("info", "notify.send", "通知发送成功", tostring(desc.url))
    return true
end

--- 检查当前渠道是否已正确配置
function util_notify.is_ready()
    local name, builder = active_channel()
    if not name then
        return false
    end

    local desc, err = builder({
        title = "通知渠道检测",
        text = "通知渠道检测",
        imei = util_mobile.getImei(),
        time = os.date(),
    })

    if not desc then
        log_output("warn", "util_notify.is_ready", "通知渠道配置不完整", name, tostring(err))
        return false
    end

    return true
end

--- 添加通知到发送队列
-- @param msg table 或字符串，建议传 table
-- @param id 消息唯一标识(可选)
function util_notify.add(msg, id)
    msg_count = msg_count + 1

    if id == nil or id == "" then
        id = "msg-t" .. os.time() .. "c" .. msg_count .. "r" .. math.random(9999)
    end

    local title, text = format_message(msg)
    text = text .. util_mobile.appendDeviceInfo()

    msg_queue[#msg_queue + 1] = {
        id = id,
        title = title,
        text = text,
        imei = util_mobile.getImei() or "",
        time = os.date(),
        retry = 0,
    }

    sys.publish("NEW_MSG")
    log_output("debug", "util_notify.add", "加入通知队列", title, "队列长度:", #msg_queue)
end

--- 发送队列中的一条通知
local function send_item(item)
    local name, builder = active_channel()
    if not name then
        log_output("error", "util_notify.send_item",
            "未选择有效的通知渠道，请检查 config.NOTIFY_CHANNEL")
        return true
    end

    local desc, err = builder({
        title = item.title,
        text = item.text,
        imei = item.imei,
        time = item.time,
    })

    if not desc then
        log_output("error", "util_notify.send_item", "通知渠道配置不完整", name, tostring(err))
        return true
    end

    return send_desc(desc)
end

--- 网络是否已就绪
local function network_ready()
    if not _G.socket or not socket.adapter or not socket.dft then
        return true
    end
    return socket.adapter(socket.dft()) and true or false
end

--- 轮询消息队列，发送成功则出队，失败则等待下次重试
local function poll()
    if #msg_queue == 0 then
        sys.waitUntil("NEW_MSG", 1000 * 10)
        return
    end

    local item = table.remove(msg_queue, 1)

    log_output("info", "util_notify.poll", "处理通知", item.title, "重试次数:", item.retry)

    local max_retry = tonumber(config.NOTIFY_MAX_RETRY) or 20
    if item.retry > max_retry then
        log_output("warn", "util_notify.poll", "超过最大重试次数, 放弃发送", item.title)
        return
    end

    if not network_ready() then
        log_output("warn", "util_notify.poll", "网络未就绪, 等待重连")
        table.insert(msg_queue, 1, item)
        sys.wait(1000)
        return
    end

    if send_item(item) then
        error_count = 0
        return
    end

    error_count = error_count + 1
    item.retry = item.retry + 1
    table.insert(msg_queue, 1, item)

    log_output("info", "util_notify.poll", "发送失败, 等待重发", "重试次数:", item.retry,
        "连续失败次数:", error_count)
    sys.wait(1000)

    -- 每连续失败 5 次, 开关飞行模式尝试恢复网络
    if error_count % 5 == 0 then
        log_output("warn", "util_notify.poll", "连续失败次数过多, 开关飞行模式")
        mobile.flymode(0, true)
        mobile.flymode(0, false)
        sys.wait(5000)
    end
end

sys.taskInit(function()
    while true do
        poll()
        sys.wait(100)
    end
end)

return util_notify
