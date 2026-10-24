# EHM 硬件程序（Air780E / LuatOS）

基于 Air780E（LuatOS）的 4G 短信转发与设备状态通知程序。设备收到短信后，直接通过代码中配置的 HTTP/Webhook/邮件渠道转发通知。

（设备可以到淘宝上搜，二三十块钱一个，必须要是合宙的，推荐模块版本：780EHM，官方固件版本下载101号固件，全网通支持）

## 功能特性

- 短信自动转发到钉钉、企微、飞书、邮箱、自定义 Webhook 及多种开源推送工具
- 通知渠道通过 `config.NOTIFY_CHANNEL` 单选切换，只生效一个渠道
- 设备上线、定时心跳自动通知
- 短信控制：发送 `SMS,目标号码,短信内容` 可让设备代发短信
- 来电自动接听，5 秒后自动挂断
- 通知发送队列 + 失败重试；连续失败自动重启网络
- 定时校时、定时开关飞行模式、网络指示灯

## 目录结构

| 文件 | 说明 |
| --- | --- |
| `main.lua` | 程序入口：网络初始化、短信回调、上线/心跳通知、通话处理 |
| `config.lua` | 全部配置：通知渠道选择器、各渠道参数、系统参数 |
| `util_notify.lua` | 通知格式化、渠道分发、发送队列与重试 |
| `util_codec.lua` | base64、URL 编码、HMAC-SHA256、JSON 转义 |
| `util_smtp.lua` | SMTP over TLS 邮件发送 |
| `util_mobile.lua` | SIM/网络信息、短信发送、设备信息追加 |
| `util_netled.lua` | 网络指示灯控制 |

## 运行环境

- 硬件：Air780E 系列（项目名 `780EHMZF`）
- 固件：LuatOS
- 依赖库：
  - `http`：所有 HTTP/HTTPS 渠道
  - `socket` + TLS：邮箱 SMTP 直连
  - `crypto.hmac_sha256`：钉钉/飞书加签（未使用加签可不依赖）
  - `zbuff`：读取 socket 数据的备用实现

无需部署 MQTT Broker 或服务端程序。

## 快速开始

1. 使用 Luatools 将本目录脚本烧录到设备。
2. 打开 `config.lua`，把 `NOTIFY_CHANNEL` 改成要使用的渠道名。
3. 填写该渠道对应的参数（见下方渠道表）。
4. 设备联网后会自动发送一条“设备上线”通知，用于验证配置。

```lua
-- config.lua
NOTIFY_CHANNEL = "dingtalk",   -- 只生效这一个渠道
DINGTALK_WEBHOOK = "https://oapi.dingtalk.com/robot/send?access_token=xxxxxx",
DINGTALK_SECRET = "",          -- 使用“加签”时填写，使用“自定义关键词”时留空
```

填 `"none"` 或留空可关闭通知发送。

## 通知渠道

| 渠道名 | 必填配置 | 说明 |
| --- | --- | --- |
| `dingtalk` | `DINGTALK_WEBHOOK` | 钉钉群机器人；开启加签时填 `DINGTALK_SECRET` |
| `wecom` | `WECOM_WEBHOOK` | 企业微信群机器人完整 Webhook 地址 |
| `feishu` | `FEISHU_WEBHOOK` | 飞书群机器人；开启签名校验时填 `FEISHU_SECRET` |
| `email` | `EMAIL_USER`、`EMAIL_PASSWORD`、`EMAIL_TO` | SMTP 直连，默认 465 端口 TLS |
| `webhook` | `WEBHOOK_URL` | 自定义接口，可配请求方法、请求头、请求体模板 |
| `gotify` | `GOTIFY_URL`、`GOTIFY_TOKEN` | 自建 Gotify 服务 |
| `ntfy` | `NTFY_TOPIC` | 公共实例 `https://ntfy.sh` 或自建地址 |
| `bark` | `BARK_KEY` | iOS Bark 推送 |
| `serverchan` | `SERVERCHAN_KEY` | Server酱（默认 `sctapi.ftqq.com`） |
| `pushplus` | `PUSHPLUS_TOKEN` | PushPlus 微信推送 |
| `pushdeer` | `PUSHDEER_KEY` | PushDeer |
| `telegram` | `TELEGRAM_BOT_TOKEN`、`TELEGRAM_CHAT_ID` | Telegram Bot |
| `slack` | `SLACK_WEBHOOK` | Slack Incoming Webhook |
| `discord` | `DISCORD_WEBHOOK` | Discord Webhook |
| `wxpusher` | `WXPUSHER_APP_TOKEN`、`WXPUSHER_UIDS` | WxPusher，UID 多个用逗号分隔 |

### 邮箱配置说明

```lua
EMAIL_SMTP_HOST = "smtp.qq.com",
EMAIL_SMTP_PORT = 465,
EMAIL_SMTP_SSL = true,
EMAIL_USER = "your@qq.com",
EMAIL_PASSWORD = "邮箱授权码",     -- 不是登录密码
EMAIL_FROM = "",                  -- 留空使用 EMAIL_USER
EMAIL_TO = "a@example.com,b@example.com",
```

- 目前支持 **465 端口隐式 TLS**；`EMAIL_SMTP_SSL = false` 时走明文 25 端口，一般仅内网中继可用。
- QQ 邮箱、163 邮箱需先在邮箱设置中开启 SMTP 服务并生成授权码。

### 自定义 Webhook 模板

`WEBHOOK_BODY_TEMPLATE` 支持以下变量：

| 变量 | 含义 |
| --- | --- |
| `${msg}` | 原始通知文本 |
| `${msg_json}` | JSON 转义后的通知文本（放在 JSON 字符串内使用） |
| `${title}` | 通知标题 |
| `${title_json}` | JSON 转义后的通知标题 |
| `${imei}` | 设备 IMEI |
| `${time}` | 通知时间 |

默认模板：

```lua
WEBHOOK_BODY_TEMPLATE = '{"text":"${msg_json}"}'
```

如需鉴权，可增加请求头：

```lua
WEBHOOK_HEADERS = { ["Authorization"] = "Bearer your-token" },
```

`WEBHOOK_METHOD` 支持 `POST` / `PUT` / `GET`。Mattermost、Rocket.Chat 等自建服务可直接用该渠道对接。

## 通知触发场景

| 场景 | 触发条件 | 标题 |
| --- | --- | --- |
| 短信转发 | 收到任意短信 | `短信通知` |
| 设备上线 | 联网、获取 IMEI、校时完成后 | `设备上线` |
| 心跳上报 | 每 `REPORT_INTERVAL` 毫秒 | `设备心跳` |

通知正文会自动附加设备运行信息：开机时长、运营商、信号强度、频段、电压。

## 短信控制

向设备 SIM 卡发送以下格式短信：

```
SMS,13800138000,要发送的内容
```

设备会向目标号码代发短信，同时该短信本身也会按当前通知渠道转发。

## 系统配置

| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `NOTIFY_HTTP_TIMEOUT` | `15000` | 单次 HTTP 请求超时（毫秒） |
| `NOTIFY_MAX_RETRY` | `20` | 通知发送最大重试次数 |
| `FLYMODE_INTERVAL` | 12 小时 | 定时开关飞行模式，填 0 关闭 |
| `SNTP_INTERVAL` | 6 小时 | 定时校时，填 0 关闭 |
| `REPORT_INTERVAL` | 5 分钟 | 心跳通知间隔，填 0 关闭 |
| `PIN_CODE` | 空 | SIM 卡 PIN 码 |
| `LOG_DEBUG_ENABLED` | `true` | 是否输出调试日志 |
| `POETRY_LOG_MODE` | `false` | 关闭日志后是否用诗句伪装 info 日志 |

## 发送与重试机制

1. 通知先进入队列，由后台任务串行发送，避免并发占用网络。
2. HTTP 返回非 2xx，或接口业务码异常（如钉钉 `errcode != 0`、飞书 `code != 0`）时判定失败。
3. 失败后 1 秒重试，超过 `NOTIFY_MAX_RETRY` 次丢弃该条通知。
4. 每连续失败 5 次，自动开关一次飞行模式尝试恢复网络。
5. 网络未就绪时消息保留在队列中，不消耗重试次数。

## 日志与排查

关键日志标签：

- `util_notify.is_ready`：渠道配置是否完整
- `util_notify.add`：通知入队
- `util_notify.poll`：队列处理与重试
- `notify.send`：实际发送结果，失败时会打印响应码和响应体

常见问题：

| 现象 | 排查方向 |
| --- | --- |
| 开机没有上线通知 | 查看 `util_notify.is_ready` 日志，确认渠道参数是否填写完整 |
| 钉钉报 `errcode 310000` | 加签密钥不正确，或机器人安全设置与代码中的模式不一致 |
| 飞书报 `code 19021` | 签名校验失败，检查 `FEISHU_SECRET` 与时间戳 |
| 邮箱认证失败 | 密码需填授权码；确认已开启 SMTP 服务且使用 465 端口 |
| HTTP 返回 `-4` | 连接失败：未联网、域名错误或网络不可用 |
| HTTP 返回 `-8` | 请求超时：弱网环境可适当增大 `NOTIFY_HTTP_TIMEOUT` |
| Telegram 无响应 | 设备网络无法访问 Telegram API，需更换渠道或自建代理 |

## 扩展新渠道

1. 在 `config.lua` 增加该渠道所需参数。
2. 在 `util_notify.lua` 的 `builders` 表中新增一个构造器，返回：

```lua
return {
    url = "https://example.com/api/send",
    method = "POST",
    headers = JSON_HEADERS,
    body = json.encode({ text = ctx.text }),
    -- 可选：业务返回码校验
    ok_field = "code",
    ok_value = 0,
}
```

3. 在 `NOTIFY_CHANNEL` 的注释可选值列表和 README 渠道表中补充渠道名。

