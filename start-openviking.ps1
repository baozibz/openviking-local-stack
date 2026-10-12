# 启动 OpenViking（本地 Ollama 版）
# 用法: powershell -ExecutionPolicy Bypass -File .\start-openviking.ps1
#
# 幂等：已经在监听的组件会跳过。退出码 0 表示三个端口最终都在监听，1 表示有组件没起来。
# 该脚本也被 dsh-openviking-panel 的宿主半边在 DSH 启动时调用。

$root = $PSScriptRoot
$ErrorActionPreference = "Continue"

# 毫秒级 TCP 探测。不要用 Test-NetConnection：它每次要 1~5 秒，几十次循环会让脚本
# 跑成好几分钟，而且会被调用方当成“启动失败”。
function Test-Port {
    param([int]$Port, [int]$TimeoutMs = 500)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        try { $client.Close() } catch { }
    }
}

function Wait-Port {
    param([int]$Port, [int]$Seconds = 60)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Port $Port 300) { return $true }
        Start-Sleep -Milliseconds 400
    }
    return (Test-Port $Port 300)
}

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date).ToString("s"), $Message
    Write-Host $Message
    try { Add-Content -Path "$root\stack.log" -Value $line -Encoding UTF8 } catch { }
}

# 1) Ollama（embedding + VLM）。HOME 重定向到工作区，避免写 C:\Users\<user>\.ollama
if (-not (Test-Port 11434)) {
    Write-Log "[1/2] 启动 Ollama ..."
    $env:USERPROFILE = "$root\home"
    $env:HOME        = "$root\home"
    $env:OLLAMA_MODELS = "$root\models"
    $env:OLLAMA_HOST   = "127.0.0.1:11434"
    $env:OLLAMA_KEEP_ALIVE = "10m"
    # 8GB 显存要同时容纳三个模型：VLM qwen3.5:9b(16K ctx) + bge-m3 + query_planner，
    # fp16 KV 下合计 ~8.28GB 会超，导致模型互相驱逐（planner 一调用就被卸掉）。
    # q8_0 的 KV 基本无损，把 VLM 的 KV 减半后三者可以共存。
    $env:OLLAMA_FLASH_ATTENTION = "1"
    $env:OLLAMA_KV_CACHE_TYPE   = "q8_0"
    # 国内直连 registry.ollama.ai 会连上 Cloudflare 的 IPv6 后卡死（连接建立但零吞吐，
    # 日志反复刷进度、磁盘不增长）。走本机 Clash 代理就正常，实测 ~13-22 MB/s。
    # 只有在代理确实在监听时才设置，免得没开 Clash 时反而把下载弄坏。
    if (Test-Port 7890 300) {
        $env:HTTPS_PROXY = "http://127.0.0.1:7890"
        $env:HTTP_PROXY  = "http://127.0.0.1:7890"
        $env:NO_PROXY    = "127.0.0.1,localhost"
        Write-Log "[1/2] 已启用 Clash 代理 127.0.0.1:7890（下载模型用）"
    } else {
        Write-Log "[1/2] Clash 代理 7890 未监听，直连下载（可能卡住）"
    }
    Start-Process -FilePath "$root\ollama\ollama.exe" -ArgumentList "serve" -WindowStyle Hidden
    if (-not (Wait-Port 11434 45)) { Write-Log "[1/2] Ollama 启动失败：11434 未监听" }
} else {
    Write-Log "[1/2] Ollama 已在运行"
}

# 2) OpenViking 服务端 + VikingBot（Web Studio 在 http://127.0.0.1:1933/studio，Bot 网关 18790）
if (-not (Test-Port 1933)) {
    Write-Log "[2/2] 启动 OpenViking Server + VikingBot ..."
    $env:TMP = "$root\tmp"
    $env:TEMP = "$root\tmp"
    $env:PYTHONUTF8 = "1"                 # VikingBot 横幅含 emoji，GBK 控制台会炸
    $env:PYTHONIOENCODING = "utf-8"
    $env:OPENVIKING_CONFIG_FILE = "$root\ov.conf"   # 让 vikingbot 子进程也找到这份配置
    Start-Process -FilePath "$root\venv\Scripts\openviking-server.exe" `
        -ArgumentList "--config", "$root\ov.conf", "--with-bot" -WindowStyle Hidden
    if (-not (Wait-Port 1933 120)) { Write-Log "[2/2] OpenViking Server 启动失败：1933 未监听" }
} else {
    Write-Log "[2/2] OpenViking Server 已在运行"
}

$ok = (Test-Port 1933) -and (Test-Port 11434)
Write-Log ("stack ok={0} (1933={1} 11434={2} 18790={3})" -f $ok, (Test-Port 1933), (Test-Port 11434), (Test-Port 18790))

# 预热 query_planner。它是 0.8B 小模型，冷加载约 36 秒；OpenViking 的意图分析超时
# (retrieval.recall_intent_timeout_s，已设为 60s) 一旦超时就会静默降级为"不扩展查询"，
# 所以启动后主动把它加载进显存并保活，第一次 recall 就不用等冷加载。
if ($ok) {
    try {
        $body = '{"model":"guoxuter/ov_intent_analysis_sft:v7_q8","prompt":"","stream":false,"keep_alive":"10m"}'
        Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/generate" -Method Post `
            -ContentType "application/json" -Body $body -TimeoutSec 180 | Out-Null
        Write-Log "[warmup] query_planner 已预加载并保活 10 分钟"
    } catch {
        Write-Log "[warmup] query_planner 预热失败（不影响启动）：$($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "Web Studio : http://127.0.0.1:1933/studio"
Write-Host "健康检查   : http://127.0.0.1:1933/health"
Write-Host "Bot 网关   : http://127.0.0.1:18790"
Write-Host "ov CLI     : 见 README.md（需要设置 LANG 环境变量）"

exit ([int](-not $ok))
