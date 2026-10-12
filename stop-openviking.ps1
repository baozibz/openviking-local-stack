# 停止 OpenViking / VikingBot / Ollama
# 用法: powershell -ExecutionPolicy Bypass -File .\stop-openviking.ps1
#
# VikingBot 是服务端子进程，杀掉服务端后它可能变成孤儿并继续占着 18790，
# 下一次 --with-bot 启动就会失败。所以这里连它一起收掉（只匹配本工作区 venv 里的 python）。

$root = $PSScriptRoot

Write-Host "停止 OpenViking Server ..."
Get-CimInstance Win32_Process -Filter "Name='openviking-server.exe'" -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Write-Host "停止 VikingBot (venv python) ..."
Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -like "*openviking\venv*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Write-Host "停止 Ollama ..."
Get-Process ollama -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

Start-Sleep -Seconds 1
$left = @(1933, 11434, 18790) | Where-Object {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $c.BeginConnect("127.0.0.1", $_, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(400)) { $false } else { $c.EndConnect($iar); $true }
    } catch { $false } finally { try { $c.Close() } catch { } }
}
if ($left.Count -gt 0) { Write-Host "仍在监听: $($left -join ', ')" } else { Write-Host "完成：1933 / 11434 / 18790 均已释放" }
