# Windows 导表入口；-Check 仅校验。路径以本脚本为准，结果追加到共用日志，不依赖当前目录。
param([switch]$Check)

$ErrorActionPreference = 'Stop'
$exportScript = Join-Path $PSScriptRoot 'export.py'
$logFile = Join-Path $PSScriptRoot '导表运行日志.txt'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$logWriter = [System.IO.StreamWriter]::new($logFile, $true, $utf8)
$logWriter.AutoFlush = $true
$exportExitCode = 1

# 同时写控制台和 UTF-8 日志，失败详情也保留在同一位置。
function Write-ExportLog([string]$Message) {
    Write-Host $Message
    $script:logWriter.WriteLine($Message)
}

# 直接启动 Python 并分别异步读取标准输出和错误，避免管道编码及输出缓冲区阻塞。
function Invoke-PythonProcess([string]$Executable, [string]$Arguments) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.Arguments = $Arguments
    $startInfo.WorkingDirectory = $PSScriptRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $script:utf8
    $startInfo.StandardErrorEncoding = $script:utf8
    $startInfo.EnvironmentVariables['PYTHONUTF8'] = '1'
    $startInfo.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = $stdout.GetAwaiter().GetResult()
            ErrorOutput = $stderr.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}

# 优先查找系统 Python，再查找 Codex 和 uv 环境；实际启动确认版本至少为 3.10，跳过商店占位程序。
function Find-ExportPython {
    $candidates = @()
    foreach ($name in @('py', 'python', 'python3')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command -and $command.Source -notlike '*\Microsoft\WindowsApps\*') {
            $prefix = if ($name -eq 'py') { '-3 ' } else { '' }
            $candidates += [pscustomobject]@{ Path = $command.Source; Prefix = $prefix }
        }
    }
    foreach ($relativePath in @(
        '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe',
        '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\bin\python.exe'
    )) {
        $candidatePath = Join-Path $env:USERPROFILE $relativePath
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            $candidates += [pscustomobject]@{ Path = $candidatePath; Prefix = '' }
        }
    }
    $uvDirectory = Join-Path $env:USERPROFILE '.local\share\uv\python'
    $uvInstalls = Get-ChildItem -LiteralPath $uvDirectory -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    foreach ($installation in $uvInstalls) {
        $candidatePath = Join-Path $installation.FullName 'python.exe'
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            $candidates += [pscustomobject]@{ Path = $candidatePath; Prefix = '' }
        }
    }
    foreach ($candidate in $candidates) {
        try {
            $probe = Invoke-PythonProcess $candidate.Path ($candidate.Prefix + '-c "import sys; print(sys.executable); sys.exit(0 if sys.version_info >= (3, 10) else 1)"')
            if ($probe.ExitCode -eq 0) {
                return $candidate
            }
        }
        catch {
            # 不可启动的候选环境不影响继续寻找其余 Python。
            continue
        }
    }
    throw '找不到 Python 3.10 或更新版本。请安装 Python 并勾选加入 PATH，或使用本机 Codex Python 环境。'
}

# 每次运行追加独立记录；沿用 export.py 的校验与导出逻辑，不另写一套导表规则。
try {
    Write-ExportLog ''
    Write-ExportLog ('=' * 60)
    Write-ExportLog ('运行时间：' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-ExportLog ('项目目录：' + (Split-Path -Parent $PSScriptRoot))
    $mode = if ($Check) { '只校验，不写入数据' } else { '校验并导出' }
    Write-ExportLog ('运行方式：Windows 一键导表（' + $mode + '）')
    if (-not (Test-Path -LiteralPath $exportScript -PathType Leaf)) {
        throw ('找不到导表脚本：' + $exportScript)
    }
    $python = Find-ExportPython
    Write-ExportLog ('Python：' + $python.Path + ' ' + $python.Prefix.Trim())
    $arguments = $python.Prefix + '-u "' + $exportScript + '"'
    if ($Check) { $arguments += ' --check' }
    $result = Invoke-PythonProcess $python.Path $arguments
    if ($result.Output) { Write-ExportLog $result.Output.TrimEnd() }
    if ($result.ErrorOutput) { Write-ExportLog $result.ErrorOutput.TrimEnd() }
    $exportExitCode = $result.ExitCode
    if ($exportExitCode -eq 0) {
        if ($Check) {
            Write-ExportLog '校验通过，未写入数据。'
        }
        else {
            Write-ExportLog '导表成功。导出后的配置会在下次启动游戏时读取。'
        }
    }
    else {
        Write-ExportLog '导表失败。请按以上错误修正表格或文件，再重新运行。'
    }
}
catch {
    Write-ExportLog ('导表失败：' + $_.Exception.Message)
    $exportExitCode = 1
}
finally {
    Write-ExportLog ('结束时间：' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-ExportLog ('退出码：' + $exportExitCode)
    Write-ExportLog ('日志位置：' + $logFile)
    $logWriter.Dispose()
}
exit $exportExitCode
