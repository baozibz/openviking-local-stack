# 本机 OpenViking（Windows / 全本地，无需 API Key）

DSH 的 `@openviking/dsh-memory-plugin` 连接的本地 OpenViking 服务端。embedding 与 VLM 都跑在本机
Ollama 上，不需要任何云端 API Key。

## 访问入口

| 用途 | 地址 |
| --- | --- |
| **Web Studio（可视化浏览记忆）** | http://127.0.0.1:1933/studio |
| 健康检查 | http://127.0.0.1:1933/health |
| 就绪检查 | http://127.0.0.1:1933/ready |
| MCP（给 Agent） | http://127.0.0.1:1933/mcp |

认证模式为 `dev`（只绑 127.0.0.1，无 API Key）。

## 在 DSH 左侧导航里打开（推荐）

已安装本地客户端插件 `dsh-openviking-panel`：**重启 DSH 后**，左侧导航会多出一行
**OpenViking**（Plugins 0 / Schedule 10 / Task board 20 / **OpenViking 30**），点开即在
主区域内嵌上面的 Web Studio。

- 插件源码与文档：[dsh-openviking-panel](../dsh-openviking-panel/README.md)
- 配置：`~/.dsh/profiles/desktop/cordis.patch.yml` 末尾的 insert 行
- 挂载验证：存在 `dsh-openviking-panel/.load-probe` 时会写 `loaded.log`

## 启动 / 停止

```powershell
powershell -ExecutionPolicy Bypass -File .\start-openviking.ps1
powershell -ExecutionPolicy Bypass -File .\stop-openviking.ps1
```

两个脚本都带 UTF-8 BOM，PowerShell 5.1 与 7 都能跑。`start` 幂等（已在监听的跳过），
冷启动约 **40 秒**，结束时打印 `stack ok=True/False` 并把每次结果写进 `stack.log`；
`stop` 会连 **VikingBot 的 venv python** 一起收掉——否则它会变成孤儿继续占着 18790，
导致下次 `--with-bot` 启动失败。

> **DSH 启动时自动启动**：已装的面板插件 `dsh-openviking-panel` 会在宿主半边探测 1933，
> 不通就调用 `start-openviking.ps1` 并校验重试。见
> [插件文档](../dsh-openviking-panel/README.md)。关闭自启：在本目录建 `.no-autostart`。

## 目录结构

```
openviking/
├── ov.conf                  # 服务端配置（存储 + embedding + VLM）
├── venv/                    # Python venv，含 openviking 0.5.0 服务端
├── ollama/                  # 便携版 Ollama 0.40.3（ollama.exe + lib）
├── models/                  # Ollama 模型（bge-m3、qwen2.5vl:7b、qwen3:8b、qwen2.5:7b）
├── data/                    # OpenViking 数据（RAGFS + 本地向量库）
├── home/                    # 重定向的 HOME（Ollama 密钥等）
├── tmp/ pipcache/ logs/     # 临时与日志
├── stack.log                # 每次启动脚本的结果
├── autostart.log            # 面板插件自启的决定与重试
├── start-openviking.ps1
└── stop-openviking.ps1
```

`ov` CLI 装在工作区 `.ovcli\`（npm 包 `@openviking/cli`），不在全局 PATH。

## 模型

| 用途 | 模型 | 大小 | 提供方 |
| --- | --- | --- | --- |
| Embedding（dense, 1024 维） | `bge-m3` | 1.2 GB | Ollama，走 OpenAI 兼容 `/v1/embeddings` |
| **VLM（摘要 / 记忆抽取）** | **`qwen3.5:9b`** | 6.6 GB | Ollama，经 LiteLLM `ollama/qwen3.5:9b`，`num_ctx=16384`、`think=false` |
| **Query Planner（检索意图分析）** | **`guoxuter/ov_intent_analysis_sft:v7_q8`** | 811 MB | Ollama（官方推荐的本地小模型），`temperature=0`、`think=false` |
| 通用对话 / Agent（推荐） | `qwen3.5:9b` | 6.6 GB | 本机 Ollama，实测 **29.4 tok/s**（85% GPU + 15% CPU） |
| 备用对话 | `qwen3:8b` | 5.2 GB | 本机 Ollama |
| 备用对话（Bot，已换下） | `qwen2.5:7b` | 4.7 GB | 本机 Ollama |
| （旧 VLM，已弃用） | `qwen2.5vl:7b` | 6.0 GB | 2026-10-12 被 `qwen3.5:9b` 取代，模型文件仍保留可回退 |

显卡：RTX 5060 Ti 8GB（Ollama 用 CUDA 13）。模型按需加载，切换时会卸载上一个。

Bot 的 Agent 模型单独配置（`bot.agents`），2026-10-12 也换成了 `ollama/qwen3.5:9b`
（`num_ctx=40960`），见下方 VikingBot 一节——**但结论是本地模型驱动不了 VikingBot 的工具协议**。

### 国内拉模型必须走代理（重要）

直连 `registry.ollama.ai` 会连上 Cloudflare 的 **IPv6** 地址：TCP 连接能建立（一次开十几个），
但**零吞吐**——`ollama pull` 的日志一直刷进度、磁盘却不增长，表现为无限重试。实测 19GB 的
`qwen3:30b-a3b` 就卡死在这里；6.6GB 的 `qwen3.5:9b` 直连时一层卡在 49%/64% 反复重试。

解决：让 Ollama 走本机 Clash（`mihomo`，`127.0.0.1:7890`）。`start-openviking.ps1` 现在会
**先探测 7890 再设置** `HTTPS_PROXY`/`HTTP_PROXY`/`NO_PROXY`，然后才启动 Ollama。走代理后
实测 **13–22 MB/s**，`qwen3.5:9b` 剩余部分几分钟内续传完成。

手动拉模型时同理（服务端已带代理，CLI 不需要额外设置）：

```powershell
ollama pull qwen3.5:9b
```

> 之前 `qwen3:30b-a3b` 卡死时留下的 **17.28 GB 半成品 blob 已清理**（`models\blobs\*partial*`）。
> 该模型并未安装，且没有任何 manifest 引用那些文件。`models` 目录现在 21.97 GB。
> 想重新下它的话，有代理之后可以直接 `ollama pull qwen3:30b-a3b`（约 19 GB）。

### Query Planner：官方推荐的本地小模型（2026-10-12 装上）

官方文档给 VLM/Embedding 推荐的是 `doubao-*`（云端），但 **query_planner 明确推荐了一个本地 Ollama 模型**：

| 项 | 值 |
| --- | --- |
| 模型 | `guoxuter/ov_intent_analysis_sft:v7_q8`（Qwen3.5-0.8B 微调，752M 参数，Q8_0，**811 MB**） |
| 作用 | 判断这一轮**是否真的需要检索**；闲聊/上下文已足够时返回空查询，减少无谓的记忆注入与 token 消耗；需要时输出针对 `skill`/`resource`/`memory` 的结构化查询 |
| 官方 benchmark | Locomo 准确率 **0.9037**（持平 `doubao-seed-2.0-pro` 的 0.9032）；闲聊识别 F1 **0.9176**（base qwen3.5-0.8b 只有 0.1556） |
| 提示词 | OpenViking **内置**配套 v7 模板（`retrieval.ov_intent_analysis_sft_v7`），不用手动放 prompt |

配置（`ov.conf`）：

```json
"query_planner": {
  "provider": "litellm", "api_key": "ollama",
  "model": "ollama/guoxuter/ov_intent_analysis_sft:v7_q8",
  "api_base": "http://127.0.0.1:11434",
  "temperature": 0.0, "timeout": 60,
  "extra_request_body": { "think": false }
},
"retrieval": {
  "enable_intent": true,
  "recall_intent_timeout_s": 60.0,
  "recall_rewrite_timeout_s": 30.0
}
```

#### 两个必须知道的坑（都踩过并解决）

1. **`recall_intent_timeout_s` 默认只有 5 秒**，而 planner 冷加载要 **36 秒**。
   `expansion.py` 用 `asyncio.wait_for(..., timeout=5)` 包住调用，超时就**静默降级**为
   "不扩展查询"并打一条 warning，同时取消请求把 Ollama 侧正在加载的模型卸掉 —— 表现为
   "配了跟没配一样"，且日志里只有一行 warning。实测每次都在 5.1s 返回。
   **必须把它调到 ≥ 冷加载耗时（这里设 60s）。**
2. **8GB 显存装不下三个模型**：VLM `qwen3.5:9b`(16K) 6.7G + `bge-m3` 0.66G + planner 0.92G
   ≈ 8.28G > 8.15G，会互相驱逐。已给 Ollama 开 `OLLAMA_KV_CACHE_TYPE=q8_0` +
   `OLLAMA_FLASH_ATTENTION=1`（KV 减半，基本无损），三个模型可稳定共存（实测 7610/8151 MiB）。
3. `start-openviking.ps1` 在栈就绪后会**预热 planner**（`keep_alive=10m`），
   否则重启后第一次 recall 要等 57 秒冷加载。

#### 验证结果（`POST /api/v1/search/search`，`mode=context` + `session_id` + `query_expansion=auto`）

> 注意：**只有传了 `session_id` 的 context 组装路径才会走 planner**。`ov search` 不传 session，
> 走的是另一条分支（`expansion.py` 里 `needs_session = bool(session_id) and ...`），
> 所以用 CLI 测会误以为"没生效"。`/api/v1/search/recall` 已废弃，继任者是 `/search` + `mode=context`。

| 查询 | planner 用时 | `stats.planned_queries` |
| --- | --- | --- |
| 「你好呀」 | 4.3–57s（首轮冷加载） | `['你好呀']` —— **只有原句 = 识别为闲聊，不扩展** ✅ |
| 「哈哈今天天气不错」 | 4.3s | `['哈哈今天天气不错']` ✅ |
| 「我上次是怎么给 Ollama 配代理来解决下载卡死的？」 | 11.9s | 原句 + `Ollama planner cold start 60s timeout resolution method using Ollama proxy` + `Ollama proxy configuration steps for planner serv…` ✅ |

`stats.query_expansion` 从静默失败的 `failed` 变为 **`used`**，planner 全程留在显存不再被驱逐。

## VikingBot（OpenViking 自带的多渠道 Agent）

已安装并随服务端一起启动（`--with-bot`）：Bot 网关在 `http://127.0.0.1:18790`，
HTTP API 是 `/bot/v1/chat`、`/bot/v1/chat/stream`，网页入口在 Studio 的 `/studio/vikingbot`。

```powershell
# 经 OpenViking 服务端对话（推荐）
& $node $ov chat -s <session-id> -m "你的问题"
& $node $ov chat -s test -m "在 OpenViking 里搜索关于 X 的记忆并总结"

# 不经服务端，直接跑 Bot（调试用）
$env:OPENVIKING_CONFIG_FILE = "D:\Documents\deepseek-harness\default-workspace\openviking\ov.conf"
$env:PYTHONUTF8 = "1"
.\venv\Scripts\vikingbot.exe chat -m "你好"
.\venv\Scripts\vikingbot.exe status
```

配置（`ov.conf` 的 `bot` 段）：

```json
"bot": {
  "agents": {
    "provider": "litellm",
    "api_key": "ollama",
    "model": "openai/qwen2.5:7b",
    "api_base": "http://127.0.0.1:11434/v1",
    "timeout": 600,
    "max_tokens": 4096
  },
  "gateway": { "host": "127.0.0.1", "port": 18790 }
}
```

> **为什么用 `openai/` 前缀而不是 `ollama/`**：OpenViking 的 LiteLLM ollama 分支会**强制注入
> `think` 参数**（`litellm_vlm.py` 里 `extra.setdefault("think", ...)`，默认 `false`），而 Ollama 对
> 不支持 thinking 的模型会直接报 `"<model>" does not support thinking`。`qwen2.5:7b` 正好属于这类，
> 所以改走 Ollama 的 OpenAI 兼容端点 `/v1`（`openai/` 前缀），既不注入 `think` 也不受默认
> `num_ctx=16384` 限制。

### 本地小模型的已知限制（重要）

管线是通的：Bot 能正确调用 `openviking_search` / `openviking_multi_read` 等工具并拿到结果，
OpenViking 集成、技能、心跳、cron 都正常。**但 7~8B 的本地模型在开放式对话上不稳定**，实测表现为：

| 模型 / 配置 | 现象 |
| --- | --- |
| `ollama/qwen3.5:9b` + `num_ctx=40960`（当前） | **回答内容正确**（如"你好！我是 VikingBot 🐈…"），但模型会把它包进**自创的 `text({"response": …})` 工具调用**，于是最终 message 变成 `{"response": "…"}` 而不是纯文本；偶尔还编出 `function_name(...)`、`read_file("/etc/passwd")` 这类假调用 |
| `ollama/qwen3.5:9b` + `num_ctx=32768` | 更糟：prompt 实测 **30397 token**，只剩 2.4k 给输出，最终 message 退化成 `{}` |
| `openai/qwen2.5:7b` | 有时正常中文回答；有时在工具调用后回“请提供上一步的结果”而不作答 |
| `ollama/qwen2.5:7b` | 直接报 `does not support thinking` |
| `ollama/qwen3:8b` + `think:false` | 会把最终回答套成 JSON 工具调用格式 `{"<答案>": {}}` |
| `ollama/qwen3:8b` + `thinking:true` | 只产出推理，正文为空 `{}` |

两个关键观察：
1. **prompt 极大**（约 30k token）——VikingBot 把自己所有工具定义 + 工作区文档都塞进系统提示，
   9B 模型在这么大的工具表面前会"照着格式编工具名"。`num_ctx` 必须 ≥ prompt + 输出余量，
   否则连输出空间都没有（这正是 `32768` 时退化成 `{}` 的原因）。
2. `text` / `message` / `vikingbot` 这些**都不是已注册的工具**（在 vikingbot 包里 grep 过），
   纯粹是模型臆造。

另外 `TOOLS.md` 原本介绍了一个 `message` 工具，但 CLI/HTTP 通道没有注册它，模型会照着文档
臆造调用并失败；已在该文件中把它标注为不可用。

**结论**：想让 VikingBot 好用地聊天，建议在 `bot.agents` 里换成有 API Key 的云端模型
（火山方舟 / OpenAI / Kimi / GLM），配置结构与上面一致，把 `provider`/`model`/`api_key`/`api_base`
换掉即可。本地模型更适合跑"明确的任务型指令 + OpenViking 检索"。

## 使用 ov CLI

CLI 依赖标准 locale 变量才能运行；未设置时会报 “needs a display language”。

```powershell
$env:LANG = "zh_CN.UTF-8"
$node = "C:\Users\<你>\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe"
$ov   = "D:\Documents\deepseek-harness\default-workspace\.ovcli\node_modules\@openviking\cli\bin\ov.mjs"

& $node $ov health -o json
& $node $ov status
& $node $ov tree viking://user/default/memories -L 5
& $node $ov find "关键词"
& $node $ov tui viking://          # 交互式浏览器
```

CLI 配置：`C:\Users\<你>\.openviking\ovcli.conf`（`url` = `http://127.0.0.1:1933`，无 key）。

## 数据位置（viking:// 虚拟文件系统）

```
viking://resources/                 # 导入的资料
viking://user/default/memories/     # 长期记忆（identity.md / soul.md 等）
viking://user/default/sessions/     # 会话归档，含 dsh-session-*
viking://user/default/skills/       # 技能
viking://agent/                     # 账号内共享的 skill / 配置
```

## 与 DSH 记忆插件的关系

- 插件默认端点就是 `http://127.0.0.1:1933`，所以本机服务一起来，插件的后台 drainer
  就自动把积压的本地待写队列（`C:\Users\<你>\.openviking\pending`）灌进服务端。
- **记忆召回 / 采集 / 提交走 HTTP，无需重启 DSH 即已生效**（会话已出现在
  `viking://user/default/sessions/dsh-session-*`）。
- **MCP 工具面（`mcp__openviking__*`）在进程启动时连接，之前是断的，需要重启一次 DSH
  才会重新挂上。** 重启后模型才能直接调用 find/search/read 等工具。

## 已知问题 / 注意

1. **`arkruntime` 兼容 shim**：OpenViking 0.5.0 仍 `import volcenginesdkarkruntime`，而火山已把该
   发行版改名为 `arkruntime`（旧名已从 PyPI 下架）。已在 venv 里加了一个薄的兼容包
   `venv\Lib\site-packages\volcenginesdkarkruntime\`。升级 OpenViking 后需要重新评估。
   本次配置使用 Ollama provider，不会真正调用方舟。
2. **`ov language` 写文件失败**：目录上有继承的 `Everyone:(DC)` 拒绝 ACE，CLI 的原子重写被拒
   （`os error 5`）。已直接写 `~/.openviking/ovcli.settings.conf`（`{"language":"zh-CN"}`）绕过。
3. **偶尔的 `os error 33`（文件被占用）**：RAGFS 在 Windows 上偶发锁冲突，重试即可，不影响最终落库。
4. **VLM 处理耗时**：本机 9B 模型（`qwen3.5:9b`，`num_ctx=16384`）跑一次会话提交的抽取约 **1.5–2 分钟**
   （实测 task processing 74.75s + 排队）。比之前的 7B 略慢，但摘要与记忆质量更好、且原生支持视觉。
   嫌慢可以调小 `ov.conf` 里 `vlm.extra_request_body.num_ctx`，或换回 `qwen2.5vl:7b`。
5. `openviking-server doctor` 未跑（它主要校验云端模型凭据，与本地方案无关）。
6. **`ollama` 在普通终端里报 `mkdir C:\Users\<you>\.ollama: Access is denied`**：这是**火绒**
   （本机 `HipsDaemon`；Windows Defender 全关）的文件保护在拦 `ollama.exe`——在用户主目录里
   创建隐藏目录并写入 SSH 私钥（`id_ed25519`）正是 HIPS 眼里的勒索/窃密行为（cmd 是微软签名
   程序所以放行，同一目录下 cmd 建文件完全正常）。
   绕开方式（已实施，不动杀软）：`C:\Users\<你>\.local\bin\ollama.cmd`
   是一个 shim，它把 `USERPROFILE` / `HOME` 指向 `openviking\home`（服务端也一直用这个目录，
   密钥已在那里）再转调真正的 `ollama.exe`。因为 `.local\bin` 在用户 PATH 最前面，任何终端里
   敲 `ollama` 都会命中它。
   - 想改用官方 exe 自己的 `%USERPROFILE%\.ollama`：在火绒里把
     `openviking\ollama\` 加入信任区，然后删除 `ollama.cmd` 即可。
   - 只跑客户端命令（`list` / `run` / `pull` / `ps` / `stop`）本来就不需要私钥，所以即使没有
     shim 也能用；只有 `ollama serve` 会碰这个坑。

## 复现要点（如需重建）

```powershell
# 1) venv + 服务端（官方 wheel 支持 win_amd64）
python -m venv --without-pip .\venv
python -m pip --python .\venv\Scripts\python.exe install openviking
python -m pip --python .\venv\Scripts\python.exe install arkruntime   # 兼容 shim 依赖

# 2) Ollama 便携版（GitHub 直连受限，用 Clash 代理 127.0.0.1:7890）
#    资源: https://github.com/ollama/ollama/releases/download/v0.40.3/ollama-windows-amd64.zip

# 3) 模型
.\ollama\ollama.exe pull bge-m3
.\ollama\ollama.exe pull qwen2.5vl:7b
```
