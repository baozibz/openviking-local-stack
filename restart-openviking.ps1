# 重启 OpenViking / VikingBot / Ollama
# 用法: powershell -ExecutionPolicy Bypass -File .\restart-openviking.ps1
#
# 等价于 stop-openviking.ps1 之后再 start-openviking.ps1，但把它做成一条命令，并且
# **等端口真正释放**再启动：否则新进程可能抢不到端口，或者 Ollama 因为单实例锁没退干净而失败。
#
# 典型用途：改了 ov.conf（vlm / query_planner / retrieval / embedding）后让它生效。
# 配置是**启动时读取**的，运行期不会重新加载，所以必须重启服务端。
#
# 退出码沿用 start-openviking.ps1 的语义：0 = 1933/11434/18790 最终都在监听，1 = 有组件没起来。

$root = $PSScriptRoot
$ErrorActionPreference = "Continue"

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

Write-Host "[1/3] 停止 ..."
& "$root\stop-openviking.ps1"

Write-Host "[2/3] 等待端口释放 ..."
foreach ($port in 1933, 11434, 18790) {
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline -and (Test-Port $port 300)) {
        Start-Sleep -Milliseconds 400
    }
    if (Test-Port $port 300) { Write-Host "  警告：$port 仍在监听，继续尝试启动" }
}

Write-Host "[3/3] 启动 ..."
& "$root\start-openviking.ps1"

# start-openviking.ps1 结尾自己会 exit，正常情况这里不会执行；
# 保留是为了防止将来那个脚本改成 return 之后退出码丢失。
$ok = (Test-Port 1933) -and (Test-Port 11434) -and (Test-Port 18790)
exit ([int](-not $ok))
