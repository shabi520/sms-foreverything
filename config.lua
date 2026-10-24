return {
    -- ==================== 通知渠道选择 ====================
    -- 选择器：只生效这里填写的一个渠道，其它渠道的配置会被忽略
    -- 可选值：
    --   "dingtalk"   钉钉群机器人
    --   "wecom"      企业微信群机器人
    --   "feishu"     飞书群机器人
    --   "email"      邮箱（SMTP 直连）
    --   "webhook"    自定义 Webhook（Mattermost/Rocket.Chat/自建服务等）
    --   "gotify"     Gotify
    --   "ntfy"       ntfy
    --   "bark"       Bark（iOS）
    --   "serverchan" Server酱
    --   "pushplus"   PushPlus
    --   "pushdeer"   PushDeer
    --   "telegram"   Telegram Bot
    --   "slack"      Slack Webhook
    --   "discord"    Discord Webhook
    --   "wxpusher"   WxPusher
    -- 填 "none" 或留空则关闭通知发送
    NOTIFY_CHANNEL = "dingtalk",
    -- 单次 HTTP 请求超时（毫秒）
    NOTIFY_HTTP_TIMEOUT = 15000,
    -- 发送失败最大重试次数
    NOTIFY_MAX_RETRY = 20,

    -- ---------------- 钉钉群机器人 ----------------
    -- 机器人 Webhook 完整地址，例如：
    -- https://oapi.dingtalk.com/robot/send?access_token=xxxxxx
    DINGTALK_WEBHOOK = "",
    -- 加签密钥（机器人安全设置选择"加签"时填写；选择"自定义关键词"时留空）
    DINGTALK_SECRET = "",

    -- ---------------- 企业微信群机器人 ----------------
    -- 机器人 Webhook 完整地址，例如：
    -- https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxxxxx
    WECOM_WEBHOOK = "",

    -- ---------------- 飞书群机器人 ----------------
    -- 机器人 Webhook 完整地址，例如：
    -- https://open.feishu.cn/open-apis/bot/v2/hook/xxxxxx
    FEISHU_WEBHOOK = "",
    -- 签名校验密钥（机器人安全设置开启"签名校验"时填写）
    FEISHU_SECRET = "",

    -- ---------------- 邮箱（SMTP 直连） ----------------
    -- 支持 465 端口隐式 TLS，例如 QQ 邮箱 smtp.qq.com、163 邮箱 smtp.163.com
    EMAIL_SMTP_HOST = "smtp.qq.com",
    EMAIL_SMTP_PORT = 465,
    -- true 使用 SSL/TLS（465 端口），false 为明文（25 端口，一般仅内网中继可用）
    EMAIL_SMTP_SSL = true,
    -- 登录账号（完整邮箱地址）
    EMAIL_USER = "",
    -- 登录密码，QQ/163 邮箱请填写"授权码"而不是登录密码
    EMAIL_PASSWORD = "",
    -- 发件人地址，留空则使用 EMAIL_USER
    EMAIL_FROM = "",
    -- 收件人，多个地址用英文逗号分隔
    EMAIL_TO = "",
    -- 邮件标题前缀
    EMAIL_SUBJECT_PREFIX = "[EHM] ",

    -- ---------------- 自定义 Webhook ----------------
    WEBHOOK_URL = "",
    -- 请求方法：POST / PUT / GET
    WEBHOOK_METHOD = "POST",
    WEBHOOK_CONTENT_TYPE = "application/json",
    -- 额外请求头，例如 { ["Authorization"] = "Bearer xxx" }
    WEBHOOK_HEADERS = {},
    -- 请求体模板，可用变量：
    -- ${msg} 原始文本  ${msg_json} JSON 转义后的文本
    -- ${title} 标题    ${title_json} JSON 转义后的标题
    -- ${imei} 设备IMEI ${time} 时间
    WEBHOOK_BODY_TEMPLATE = '{"text":"${msg_json}"}',

    -- ---------------- Gotify ----------------
    -- 服务地址，例如 https://gotify.example.com
    GOTIFY_URL = "",
    -- 应用 Token
    GOTIFY_TOKEN = "",
    GOTIFY_PRIORITY = 5,

    -- ---------------- ntfy ----------------
    -- 服务地址，公共实例为 https://ntfy.sh，也可填自建地址
    NTFY_URL = "https://ntfy.sh",
    NTFY_TOPIC = "",
    -- 自建服务开启鉴权时填写（访问令牌）
    NTFY_TOKEN = "",
    -- 优先级：min / low / default / high / max 或 1-5
    NTFY_PRIORITY = "default",

    -- ---------------- Bark（iOS 推送） ----------------
    -- 服务地址，官方为 https://api.day.app，也可填自建地址
    BARK_URL = "https://api.day.app",
    BARK_KEY = "",
    -- 提示音，例如 "alarm"，留空使用默认
    BARK_SOUND = "",

    -- ---------------- Server酱 ----------------
    -- 服务地址，Server酱³ 为 https://sctapi.ftqq.com
    -- 使用旧版 SCKEY 时改为 https://sc.ftqq.com
    SERVERCHAN_URL = "https://sctapi.ftqq.com",
    SERVERCHAN_KEY = "",

    -- ---------------- PushPlus ----------------
    PUSHPLUS_TOKEN = "",

    -- ---------------- PushDeer ----------------
    PUSHDEER_URL = "https://api2.pushdeer.com",
    PUSHDEER_KEY = "",

    -- ---------------- Telegram Bot ----------------
    TELEGRAM_BOT_TOKEN = "",
    -- 聊天 ID，可以是用户 ID 或群组 ID（例如 "-1001234567890"）
    TELEGRAM_CHAT_ID = "",

    -- ---------------- Slack ----------------
    SLACK_WEBHOOK = "",

    -- ---------------- Discord ----------------
    DISCORD_WEBHOOK = "",

    -- ---------------- WxPusher ----------------
    WXPUSHER_APP_TOKEN = "",
    -- 接收用户 UID，多个用英文逗号分隔
    WXPUSHER_UIDS = "",

    -- ==================== 系统配置 ====================
    -- 定时开关飞行模式间隔, 单位毫秒, 设置为 0 关闭
    FLYMODE_INTERVAL = 1000 * 60 * 60 * 12,
    -- 定时同步时间间隔, 单位毫秒, 设置为 0 关闭
    SNTP_INTERVAL = 1000 * 60 * 60 * 6,
    -- 定时上报间隔, 单位毫秒, 设置为 0 关闭
    REPORT_INTERVAL = 1000 * 60 * 5,

    -- SIM 卡 pin 码
    PIN_CODE = "",

    -- 日志配置
    -- 启用调试日志
    LOG_DEBUG_ENABLED = true,
    -- 伪装日志模式，设为true时在日志关闭模式下显示李白的静夜思
    POETRY_LOG_MODE = false,
}
