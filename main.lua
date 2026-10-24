PROJECT = "780EHMZF"
VERSION = "001.000.003"

-- 全局日志开关，设为false可关闭详细运行日志，保护敏感信息
LOG_DEBUG_ENABLED = true

-- 设置日志级别
if LOG_DEBUG_ENABLED then
    log.setLevel("DEBUG")
    -- 日志输出函数，用于正常模式
    function log_output(level, tag, ...)
        log[level](tag, ...)
    end
else
    log.setLevel("ERROR") -- 只记录错误日志
    -- 伪装日志输出函数，显示李白的静夜思
    function log_output(level, tag, ...)
        if level == "info" then
            -- 动态加载config模块以避免初始化顺序问题
            local config_module = require "config"
            if config_module.POETRY_LOG_MODE then
                local verses = {
                    "床前明月光",
                    "疑是地上霜",
                    "举头望明月",
                    "低头思故乡"
                }
                -- 随机显示一句诗
                local random_verse = verses[math.random(1, #verses)]
                log.error("李白", random_verse)  -- 使用error级别确保在低日志级别下也能显示
            else
                -- 如果不启用诗歌模式，则不显示任何内容
            end
        elseif level == "debug" then
            -- debug信息完全不显示
        else
            log[level](tag, ...)  -- 其他级别（如error, warn）正常显示
        end
    end
end

log_output("info", "main", PROJECT, VERSION)
if LOG_DEBUG_ENABLED then
    log_output("info", "main", "开机原因", pm.lastReson())
end

sys = require "sys"
sysplus = require "sysplus"

-- 添加硬狗防止程序卡死
wdt.init(9000)
sys.timerLoopStart(wdt.feed, 3000)

-- 确保移动网络模块已加载
sys.taskInit(function()
    log_output("info", "main", "开始尝试读取设备IMEI...")
    -- 等待一小段时间确保移动网络模块初始化
    sys.wait(2000)
    
    -- 尝试多次读取IMEI，增加成功率
    for i = 1, 3 do
        log_output("info", "main", "读取IMEI尝试第", i, "次")
        
        -- 获取IMEI
        local imei = util_mobile.getImei()
        log_output("info", "main", "设备IMEI读取结果:", imei or "无法获取")
        
        -- 如果成功获取到IMEI，则跳出循环
        if imei and imei ~= "" and imei ~= "Unknown" then
            break
        end
        
        -- 每次尝试间隔1秒
        if i < 3 then
            sys.wait(1000)
        end
    end
end)

-- 设置电平输出 3.3V
-- pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)

-- 设置 DNS
socket.setDNS(nil, 1, "119.29.29.29")
socket.setDNS(nil, 2, "223.5.5.5")

-- SIM 自动恢复, 周期性获取小区信息, 网络遇到严重故障时尝试自动恢复等功能
mobile.setAuto(10000, 300000, 8, true, 120000)

-- 开启 IPv6
-- mobile.ipv6(true)

-- 初始化 fskv
log_output("info", "main", "fskv.init", fskv.init())

-- 加载模块
config = require "config"
util_netled = require "util_netled"
util_mobile = require "util_mobile"
util_notify = require "util_notify"



-- 短信接收回调
sms.setNewSmsCb(function(sender_number, sms_content, m)
    local time = string.format("%d-%02d-%02d %02d:%02d:%02d", m.year + 2000, m.mon, m.day, m.hour, m.min, m.sec)
    log_output("info", "smsCallback", time, sender_number, sms_content)

    -- 短信控制
    local is_sms_ctrl = false
    local receiver_number, sms_content_to_be_sent = sms_content:match("^SMS,(+?%d+),(.+)$")
    receiver_number, sms_content_to_be_sent = receiver_number or "", sms_content_to_be_sent or ""
    if sms_content_to_be_sent ~= "" and receiver_number ~= "" and #receiver_number >= 5 and #receiver_number <= 20 then
        sms.send(receiver_number, sms_content_to_be_sent)
        is_sms_ctrl = true
    end

    -- 加入通知队列，由 config.NOTIFY_CHANNEL 指定的渠道发送
    local notification = {
        type = "sms",
        sender = sender_number,
        content = sms_content,
        time = time,
        imei = util_mobile.getImei()
    }
    util_notify.add(notification)
end)
-- "发件号码: " .. sender_number,"#SMS" .. (is_sms_ctrl and " #CTRL" or ""),"发件时间: " .. time,

sys.taskInit(function()
    -- 等待网络环境准备就绪
    sys.waitUntil("IP_READY", 1000 * 60 * 5)

    util_netled.init()

    -- 确保获取到正确的IMEI
    local imei = nil
    local max_imei_attempts = 10
    local imei_attempt = 0
    while not imei and imei_attempt < max_imei_attempts do
        imei = util_mobile.getImei()
        log_output("info", "main", "获取IMEI尝试", imei_attempt + 1, "结果:", imei or "无法获取")
        if imei and imei ~= "" and imei ~= "Unknown" then
            break
        end
        imei_attempt = imei_attempt + 1
        sys.wait(1000)
    end

    if not imei or imei == "" or imei == "Unknown" then
        log_output("warn", "main", "无法获取设备IMEI，仍继续运行")
        imei = "Unknown"
    else
        log_output("info", "main", "设备IMEI获取成功:", imei)
    end

    -- 先同步时间再发送设备上线通知
    if os.time() < 1714500000 then
        log_output("info", "main", "检测到时间未同步，开始同步时间...")
        socket.sntp()
        -- 等待时间同步完成，最多等待10秒
        for i = 1, 20 do
            if os.time() >= 1714500000 then
                log_output("info", "main", "时间同步成功，当前时间:", os.date())
                break
            end
            sys.wait(500) -- 等待500毫秒后再次检查
        end
    end

    -- 通知渠道配置完整后发送设备上线通知
    if util_notify.is_ready() then
        log_output("info", "main", "发送设备上线通知", "IMEI:", imei, "时间:", os.date())
        util_notify.add({
            type = "status",
            status = "online",
            imei = imei,
            time = os.date(),
            version = VERSION
        })
    else
        log_output("warn", "main",
            "通知渠道未配置或配置不完整，跳过设备上线通知，请检查 config.NOTIFY_CHANNEL 及对应参数")
    end
end)

-- 定时同步时间
function sync_time()
    log_output("info", "main", "开始同步时间...")
    local start_time = os.time()
    socket.sntp()
    -- 不使用sys.wait()，因为可能在非协程环境中调用
    log_output("info", "main", "时间同步请求已发送，等待系统更新时间...")
    -- 时间同步是异步的，系统会在收到时间后自动更新
end

-- 开机时同步时间
if os.time() < 1714500000 then
    sync_time()
end

-- 定时同步时间
if type(config.SNTP_INTERVAL) == "number" and config.SNTP_INTERVAL >= 1000 * 60 then
    sys.timerLoopStart(sync_time, config.SNTP_INTERVAL)
end

-- 定时查询流量
if type(config.QUERY_TRAFFIC_INTERVAL) == "number" and config.QUERY_TRAFFIC_INTERVAL >= 1000 * 60 then
    sys.timerLoopStart(util_mobile.queryTraffic, config.QUERY_TRAFFIC_INTERVAL)
end

-- 定时上报
if type(config.REPORT_INTERVAL) == "number" and config.REPORT_INTERVAL >= 1000 * 300 then
    sys.timerLoopStart(function() 
        local report_data = {
            type = "heartbeat",
            imei = util_mobile.getImei(),
            time = os.date(),
            rsrp = mobile.rsrp(),
            oper = util_mobile.getOper(true)
        }
        util_notify.add(report_data) 
    end, config.REPORT_INTERVAL)
end

-- 开机等待 5 秒仍未联网, 再进行 pin 验证
sys.taskInit(function()
    if not sys.waitUntil("IP_READY", 1000 * 5) then
        util_mobile.pinVerify(config.PIN_CODE)
    end
end)

-- 定时开关飞行模式
if type(config.FLYMODE_INTERVAL) == "number" and config.FLYMODE_INTERVAL >= 1000 * 60 then
    sys.timerLoopStart(function()
        mobile.flymode(0, true)
        mobile.flymode(0, false)
    end, config.FLYMODE_INTERVAL)
end

-- 通话相关
-- SIM卡ID，假设为0，如果不同，请根据实际情况调整
sim_id = 0
is_calling = false

-- 处理通话状态变化
sys.subscribe("CC_IND", function(status)
    if cc == nil then return end

    if status == "INCOMINGCALL" then
        -- 来电事件, 期间会重复触发
        if is_calling then return end
        is_calling = true

        log.info("cc_status", "INCOMINGCALL", "来电事件", cc.lastNum())

        -- 接听电话并启动定时器挂断
        local success = cc.accept(sim_id)
        if success then
            log.info("cc_status", "接听电话成功")
            sys.timerStart(function()
                log.info("cc_status", "尝试挂断电话")
                if cc == nil then
                    log.error("cc_status", "cc模块不可用，无法挂断电话")
                    is_calling = false
                    return
                end
                local hangup_success = cc.hangUp()  -- 不传递sim_id参数
                if hangup_success then
                    log.info("cc_status", "挂断电话成功")
                else
                    log.error("cc_status", "挂断电话失败")
                end
                is_calling = false
            end, 5000)  -- 5秒后挂断
        else
            log.error("cc_status", "接听电话失败")
            is_calling = false
        end

        return
    end

    if status == "CONNECTED" then
        -- 通话已接通
        log.info("cc_status", "CONNECTED", "通话已接通", cc.lastNum())
        return
    end

    if status == "DISCONNECTED" then
        -- 挂断事件
        is_calling = false
        log.info("cc_status", "DISCONNECTED", "挂断事件", cc.lastNum())
        return
    end

    log.info("cc_status", status)
end)

sys.run()
