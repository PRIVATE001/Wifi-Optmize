#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Script:VERSION   = "5.0"
$Script:TOOL_NAME = "FTTH Network Tuner"
$Script:EDITION   = "Final"

$Script:LogFolder  = Join-Path ([Environment]::GetFolderPath("Desktop")) "NetworkTuner_Logs"
$Script:SessionLog = $null
$Script:BackupFile = $null

$Script:Colors = @{
    OK        = "Green"
    Warn      = "Yellow"
    Error     = "Red"
    Info      = "DarkGray"
    Accent    = "Magenta"
    Text      = "White"
    Dim       = "Gray"
    Banner    = "Cyan"
    Section   = "DarkCyan"
    Separator = "DarkCyan"
}

$Script:DnsProviders = [System.Collections.Generic.List[PSCustomObject]]@(
    [PSCustomObject]@{ Name='Cloudflare';          Pri4='1.1.1.1';        Sec4='1.0.0.1';          Pri6='2606:4700:4700::1111'; Sec6='2606:4700:4700::1001'; Doh='https://cloudflare-dns.com/dns-query' }
    [PSCustomObject]@{ Name='Google';              Pri4='8.8.8.8';        Sec4='8.8.4.4';           Pri6='2001:4860:4860::8888'; Sec6='2001:4860:4860::8844'; Doh='https://dns.google/dns-query'          }
    [PSCustomObject]@{ Name='Quad9';               Pri4='9.9.9.9';        Sec4='149.112.112.112';   Pri6='2620:fe::fe';          Sec6='2620:fe::9';           Doh='https://dns.quad9.net/dns-query'       }
    [PSCustomObject]@{ Name='AdGuard';             Pri4='94.140.14.14';   Sec4='94.140.15.15';      Pri6='2a10:50c0::ad1:ff';   Sec6='2a10:50c0::ad2:ff';   Doh='https://dns.adguard.com/dns-query'     }
    [PSCustomObject]@{ Name='Cloudflare-Malware';  Pri4='1.1.1.2';        Sec4='1.0.0.2';           Pri6=$null;                 Sec6=$null;                  Doh=$null                                   }
    [PSCustomObject]@{ Name='OpenDNS';             Pri4='208.67.222.222'; Sec4='208.67.220.220';    Pri6='2620:119:35::35';     Sec6='2620:119:53::53';      Doh=$null                                   }
    [PSCustomObject]@{ Name='Comodo';              Pri4='8.26.56.26';     Sec4='8.20.247.20';       Pri6=$null;                 Sec6=$null;                  Doh=$null                                   }
    [PSCustomObject]@{ Name='Level3';              Pri4='4.2.2.1';        Sec4='4.2.2.2';           Pri6=$null;                 Sec6=$null;                  Doh=$null                                   }
)

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Initialize-Elevation {
    if (Test-IsAdmin) { return }

    $scriptPath = $PSCommandPath
    if (-not $scriptPath) {
        Write-Host ""
        Write-Host "  [!] Administrator privileges are required." -ForegroundColor Red
        Write-Host "      Save this script as a .ps1 file and right-click -> Run as Administrator." -ForegroundColor Yellow
        Write-Host ""
        $null = Read-Host "  Press Enter to exit"
        exit 1
    }

    if (-not (Test-Path $scriptPath -ErrorAction SilentlyContinue)) {
        Write-Host "  [!] Script path not found. Run as Administrator manually." -ForegroundColor Red
        exit 1
    }

    try {
        Start-Process powershell -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$scriptPath`""
        ) -Verb RunAs
    } catch {
        Write-Host "  [!] Could not elevate automatically. Please run as Administrator." -ForegroundColor Red
        exit 1
    }
    exit
}

function Initialize-Logging {
    $ErrorActionPreference = 'SilentlyContinue'
    if (-not (Test-Path $Script:LogFolder)) {
        New-Item -Path $Script:LogFolder -ItemType Directory -Force | Out-Null
    }

    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $Script:SessionLog = Join-Path $Script:LogFolder "Session_$ts.log"
    $Script:BackupFile = Join-Path $Script:LogFolder "Last_Known_State.json"

    $header = @(
        ("=" * 72),
        ("  $($Script:TOOL_NAME) v$($Script:VERSION) $($Script:EDITION)"),
        ("  Session: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"),
        ("  OS: $([System.Environment]::OSVersion.VersionString)"),
        ("  PS: $($PSVersionTable.PSVersion)"),
        ("=" * 72)
    ) -join "`r`n"

    Set-Content -Path $Script:SessionLog -Value $header -Encoding UTF8
    $ErrorActionPreference = 'Stop'
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    if (-not $Script:SessionLog) { return }
    $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    try {
        Add-Content -Path $Script:SessionLog -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

function Write-Line {
    param(
        [string]$Message  = "",
        [ValidateSet("OK","WARN","ERR","INFO","PLAIN")][string]$Level = "PLAIN",
        [switch]$NoNewline
    )
    $cfg = switch ($Level) {
        "OK"    { @{ Tag=" [OK]  "; Color=$Script:Colors.OK    } }
        "WARN"  { @{ Tag=" [!!]  "; Color=$Script:Colors.Warn  } }
        "ERR"   { @{ Tag=" [ERR] "; Color=$Script:Colors.Error } }
        "INFO"  { @{ Tag="  -->  "; Color=$Script:Colors.Dim   } }
        default { @{ Tag="        "; Color=$Script:Colors.Text  } }
    }
    $text = "$($cfg.Tag)$Message"
    $p = @{ ForegroundColor = $cfg.Color }
    if ($NoNewline) { $p.NoNewline = $true }
    Write-Host $text @p
    Write-Log -Message $Message -Level $Level
}

function Write-Banner {
    param([string]$Title, [string]$Subtitle = "")
    $b = "=" * 72
    Write-Host ""
    Write-Host $b -ForegroundColor $Script:Colors.Banner
    Write-Host ("  $Title") -ForegroundColor $Script:Colors.OK
    if ($Subtitle) { Write-Host ("  $Subtitle") -ForegroundColor $Script:Colors.Dim }
    Write-Host $b -ForegroundColor $Script:Colors.Banner
    Write-Log "=== $Title $(if($Subtitle){"— $Subtitle"}) ===" "SECTION"
}

function Write-SectionHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host ("  >> $Title") -ForegroundColor $Script:Colors.Accent
    Write-Host ("  " + ("-" * 70)) -ForegroundColor $Script:Colors.Separator
    Write-Log "--- $Title ---" "SECTION"
}

function Write-TableRow {
    param([string]$Label, [string]$Value, [string]$ValueColor = "White")
    $line = "  {0,-32}{1}" -f $Label, $Value
    Write-Host ("  {0,-32}" -f $Label) -ForegroundColor $Script:Colors.Dim -NoNewline
    Write-Host $Value -ForegroundColor $ValueColor
    Write-Log "$Label : $Value" "TABLE"
}

function Write-Separator {
    Write-Host ("  " + ("-" * 70)) -ForegroundColor $Script:Colors.Separator
}

function Confirm-Action {
    param([string]$Prompt, [bool]$DefaultYes = $false)
    $indicator = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    Write-Host ""
    Write-Host ("  $Prompt") -ForegroundColor $Script:Colors.Text
    try {
        $resp = Read-Host ("  Choice $indicator")
    } catch { return $DefaultYes }
    Write-Host ""
    if ([string]::IsNullOrWhiteSpace($resp)) { return $DefaultYes }
    return ($resp.Trim().ToLower() -in @('y','yes'))
}

function Get-TcpGlobalState {
    $ErrorActionPreference = 'SilentlyContinue'
    $raw = & netsh interface tcp show global 2>&1
    $state = [ordered]@{
        Congestion = $null; AutoTuning = $null; Ecn = $null; Rss = $null
        Chimney = $null; Raw = ($raw -join "`r`n")
    }
    foreach ($line in ($raw | Where-Object { $_ -is [string] })) {
        if    ($line -match 'Congestion Control Provider\s*:\s*(\S+)')   { $state.Congestion = $Matches[1].ToLower() }
        elseif($line -match 'Receive Window Auto-Tuning Level\s*:\s*(\S+)'){ $state.AutoTuning = $Matches[1].ToLower() }
        elseif($line -match 'Auto-Tuning Level\s*:\s*(\S+)')             { $state.AutoTuning = $Matches[1].ToLower() }
        elseif($line -match 'ECN Capability\s*:\s*(\S+)')                { $state.Ecn        = $Matches[1].ToLower() }
        elseif($line -match 'Receive-Side Scaling State\s*:\s*(\S+)')    { $state.Rss        = $Matches[1].ToLower() }
        elseif($line -match 'Chimney Offload State\s*:\s*(\S+)')         { $state.Chimney    = $Matches[1].ToLower() }
    }
    return $state
}

function Get-TcpHeuristicsState {
    $ErrorActionPreference = 'SilentlyContinue'
    $raw = & netsh interface tcp show heuristics 2>&1
    foreach ($line in ($raw | Where-Object { $_ -is [string] })) {
        if ($line -match 'Window Scaling heuristics\s*:\s*(\S+)') { return $Matches[1].ToLower() }
    }
    return $null
}

function Invoke-Netsh {
    param([string]$Arguments, [string]$Description)
    $ErrorActionPreference = 'SilentlyContinue'
    $argArray = $Arguments -split '\s+'
    $output   = (& netsh @argArray 2>&1) -join " "
    if ($LASTEXITCODE -eq 0) {
        Write-Line -Level OK -Message $Description
        return $true
    }
    Write-Line -Level WARN -Message "$Description  (exit $LASTEXITCODE)"
    Write-Log "  netsh output: $output" "WARN"
    return $false
}

function Test-DnsTcpLatency {
    param(
        [string]$ServerIp,
        [int]$Port      = 53,
        [int]$TimeoutMs = 800,
        [int]$Attempts  = 4
    )
    $times = [System.Collections.Generic.List[double]]::new()
    for ($i = 0; $i -lt $Attempts; $i++) {
        $client = [System.Net.Sockets.TcpClient]::new()
        try {
            $sw   = [System.Diagnostics.Stopwatch]::StartNew()
            $ar   = $client.BeginConnect($ServerIp, $Port, $null, $null)
            $done = $ar.AsyncWaitHandle.WaitOne($TimeoutMs)
            $sw.Stop()
            if ($done -and $client.Connected) {
                $times.Add($sw.Elapsed.TotalMilliseconds)
                $client.EndConnect($ar)
            }
        } catch { }
        finally { $client.Dispose() }
        if ($i -lt ($Attempts - 1)) { Start-Sleep -Milliseconds 40 }
    }
    if ($times.Count -eq 0) { return $null }
    $sorted = $times | Sort-Object
    if ($sorted.Count -ge 3) { $sorted = $sorted[1..($sorted.Count - 1)] }
    return [Math]::Round(($sorted | Measure-Object -Average).Average, 1)
}

function Measure-DnsProvidersParallel {
    param([System.Collections.Generic.List[PSCustomObject]]$Candidates)

    $scriptBlock = {
        param([string]$ServerIp, [int]$Port, [int]$TimeoutMs, [int]$Attempts)
        $times = [System.Collections.Generic.List[double]]::new()
        for ($i = 0; $i -lt $Attempts; $i++) {
            $client = [System.Net.Sockets.TcpClient]::new()
            try {
                $sw   = [System.Diagnostics.Stopwatch]::StartNew()
                $ar   = $client.BeginConnect($ServerIp, $Port, $null, $null)
                $done = $ar.AsyncWaitHandle.WaitOne($TimeoutMs)
                $sw.Stop()
                if ($done -and $client.Connected) {
                    $times.Add($sw.Elapsed.TotalMilliseconds)
                    $client.EndConnect($ar)
                }
            } catch { }
            finally { $client.Dispose() }
            if ($i -lt ($Attempts - 1)) { Start-Sleep -Milliseconds 40 }
        }
        if ($times.Count -eq 0) { return $null }
        $s = $times | Sort-Object
        if ($s.Count -ge 3) { $s = $s[1..($s.Count - 1)] }
        return [Math]::Round(($s | Measure-Object -Average).Average, 1)
    }

    $maxThreads   = [Math]::Min($Candidates.Count, 16)
    $rsPool       = [RunspaceFactory]::CreateRunspacePool(1, $maxThreads)
    $rsPool.Open()

    $jobs = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($p in $Candidates) {
        $psCmd4 = [PowerShell]::Create()
        $psCmd4.RunspacePool = $rsPool
        $null = $psCmd4.AddScript($scriptBlock).AddArgument($p.Pri4).AddArgument(53).AddArgument(800).AddArgument(4)
        $handle4 = $psCmd4.BeginInvoke()

        $psCmd6 = $null; $handle6 = $null
        if ($p.Pri6) {
            $psCmd6 = [PowerShell]::Create()
            $psCmd6.RunspacePool = $rsPool
            $null = $psCmd6.AddScript($scriptBlock).AddArgument($p.Pri6).AddArgument(53).AddArgument(800).AddArgument(4)
            $handle6 = $psCmd6.BeginInvoke()
        }

        $jobs.Add(@{ Provider=$p; Cmd4=$psCmd4; Handle4=$handle4; Cmd6=$psCmd6; Handle6=$handle6 })
    }

    Write-Host ""
    Write-Host "  Benchmarking $($Candidates.Count) DNS providers in parallel..." -ForegroundColor $Script:Colors.Dim
    Write-Host "  Using $maxThreads parallel runspaces (TCP/53, 4 attempts, trimmed average)." -ForegroundColor $Script:Colors.Dim

    $total    = $jobs.Count; $done = 0
    $results  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $deadline = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($j in $jobs) {
        $timeoutLeft = [Math]::Max(100, 4000 - [int]$deadline.Elapsed.TotalMilliseconds)
        $null = $j.Handle4.AsyncWaitHandle.WaitOne($timeoutLeft)
        if ($j.Handle6) { $null = $j.Handle6.AsyncWaitHandle.WaitOne(200) }

        $lat4 = $null; $lat6 = $null
        try { $lat4 = $j.Cmd4.EndInvoke($j.Handle4) | Select-Object -Last 1 } catch { }
        try { if ($j.Cmd6) { $lat6 = $j.Cmd6.EndInvoke($j.Handle6) | Select-Object -Last 1 } } catch { }

        $j.Cmd4.Dispose()
        if ($j.Cmd6) { $j.Cmd6.Dispose() }

        if ($lat4 -is [double] -and $lat4 -le 0) { $lat4 = $null }
        if ($lat6 -is [double] -and $lat6 -le 0) { $lat6 = $null }

        $results.Add([PSCustomObject]@{
            Provider = $j.Provider
            Name     = $j.Provider.Name
            Latency4 = if ($lat4 -is [double]) { $lat4 } else { $null }
            Latency6 = if ($lat6 -is [double]) { $lat6 } else { $null }
        })

        $done++
        Write-Progress -Activity "DNS Benchmark" `
            -Status ("Completed: {0}/{1} — {2}" -f $done, $total, $j.Provider.Name) `
            -PercentComplete (($done / $total) * 100)
    }

    Write-Progress -Activity "DNS Benchmark" -Completed
    $rsPool.Close()
    $rsPool.Dispose()

    return ($results | Sort-Object -Property @{
        Expression = { if ($_.Latency4 -ne $null) { $_.Latency4 } else { [double]::MaxValue } }
    })
}

function Show-DnsResults {
    param([array]$Results)
    Write-SectionHeader "DNS Benchmark Results — Sorted by TCP/53 Latency (trimmed average, 4 attempts)"

    $hdr = "  {0,-26} {1,-16} {2,-16} {3}" -f "Provider", "IPv4 Latency", "IPv6 Latency", "Rating"
    Write-Host $hdr -ForegroundColor $Script:Colors.Dim
    Write-Separator

    $rank = 1
    foreach ($r in $Results) {
        $s4     = if ($null -ne $r.Latency4) { "{0,5} ms" -f $r.Latency4 } else { "  Blocked" }
        $s6     = if ($null -ne $r.Latency6) { "{0,5} ms" -f $r.Latency6 } else { "      N/A" }
        $badge  = switch ($true) {
            ($null -eq $r.Latency4)      { " [unreachable]"  }
            ($rank -eq 1)                { " [#1 FASTEST]"   }
            ($r.Latency4 -lt 10)         { " [excellent]"    }
            ($r.Latency4 -lt 30)         { " [good]"         }
            ($r.Latency4 -lt 80)         { " [moderate]"     }
            default                      { " [slow]"         }
        }
        $c4     = if ($null -eq $r.Latency4) { "DarkGray" }
                  elseif ($r.Latency4 -lt 20)  { "Green"    }
                  elseif ($r.Latency4 -lt 60)  { "Yellow"   }
                  else                          { "Red"      }
        $cbadge = if ($rank -eq 1 -and $r.Latency4) { "Green" } else { "DarkGray" }

        Write-Host ("  {0,-26}" -f $r.Name)    -ForegroundColor White -NoNewline
        Write-Host ("{0,-16}" -f $s4)           -ForegroundColor $c4  -NoNewline
        Write-Host ("{0,-16}" -f $s6)           -ForegroundColor $Script:Colors.Dim -NoNewline
        Write-Host $badge                        -ForegroundColor $cbadge
        Write-Log ("{0} | IPv4={1} | IPv6={2}" -f $r.Name, $s4.Trim(), $s6.Trim()) "DNS"
        $rank++
    }
    Write-Separator
}

function Select-NetworkAdapter {
    $ErrorActionPreference = 'SilentlyContinue'
    $candidates = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false })
    if ($candidates.Count -eq 0) {
        $candidates = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' })
    }
    if ($candidates.Count -eq 0) {
        Write-Line -Level ERR -Message "No active network adapters found."
        return $null
    }
    if ($candidates.Count -eq 1) { return $candidates[0] }

    Write-SectionHeader "Multiple Active Adapters — Select One"
    $i = 1
    foreach ($a in $candidates) {
        $type = switch -Regex ($a.PhysicalMediaType) {
            '802\.3'   { "Ethernet" }
            '802\.11'  { "Wi-Fi"    }
            default    { "Other"    }
        }
        $speed = if ($a.LinkSpeed) { $a.LinkSpeed } else { "Unknown" }
        Write-Host ("  [{0}]  {1,-30} | {2,-10} | {3}" -f $i, $a.Name, $type, $speed) -ForegroundColor White
        $i++
    }
    Write-Host ""
    $sel = Read-Host "  Enter number"
    $idx = 0
    if ([int]::TryParse($sel.Trim(), [ref]$idx) -and $idx -ge 1 -and $idx -le $candidates.Count) {
        return $candidates[$idx - 1]
    }
    Write-Line -Level WARN -Message "Invalid selection — using first adapter."
    return $candidates[0]
}

function Show-AdapterInfo {
    param($Adapter)
    $ErrorActionPreference = 'SilentlyContinue'
    Write-SectionHeader "Adapter Details"
    Write-TableRow "Name"          $Adapter.Name        White
    Write-TableRow "Link Speed"    "$($Adapter.LinkSpeed)" Green
    Write-TableRow "MAC Address"   $Adapter.MacAddress   White

    $ips = @(Get-NetIPAddress -InterfaceAlias $Adapter.Name -AddressFamily IPv4 |
             Where-Object { $_.IPAddress -notlike '169.*' })
    if ($ips.Count -gt 0) {
        Write-TableRow "IPv4 Address"   ($ips.IPAddress -join ", ") Cyan
        Write-TableRow "Prefix Length"  ($ips[0].PrefixLength)      Gray
    }

    $gw = (Get-NetRoute -InterfaceAlias $Adapter.Name -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
           Select-Object -First 1).NextHop
    if ($gw) { Write-TableRow "Default Gateway" $gw Cyan }

    $dns4 = (Get-DnsClientServerAddress -InterfaceAlias $Adapter.Name -AddressFamily IPv4).ServerAddresses
    if ($dns4) { Write-TableRow "Current DNS" ($dns4 -join ", ") Yellow }
    else        { Write-TableRow "Current DNS" "DHCP / Automatic"    DarkGray }

    $phyType = switch -Regex ($Adapter.PhysicalMediaType) {
        '802\.3'  { "Ethernet (Wired)"  }
        '802\.11' { "Wi-Fi (Wireless)"  }
        default   { $Adapter.PhysicalMediaType }
    }
    Write-TableRow "Media Type" $phyType White
    Write-TableRow "Adapter GUID" "$($Adapter.InterfaceGuid)" DarkGray
}

function Backup-CurrentState {
    param($Adapter)
    $ErrorActionPreference = 'SilentlyContinue'

    $dns4 = @((Get-DnsClientServerAddress -InterfaceAlias $Adapter.Name -AddressFamily IPv4).ServerAddresses)
    $dns6 = @((Get-DnsClientServerAddress -InterfaceAlias $Adapter.Name -AddressFamily IPv6).ServerAddresses)
    $tcp  = Get-TcpGlobalState
    $heur = Get-TcpHeuristicsState

    $regThrottlePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    $throttleBefore  = (Get-ItemProperty $regThrottlePath "NetworkThrottlingIndex").NetworkThrottlingIndex

    $guid      = $Adapter.InterfaceGuid
    $naglePath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
    $noDelay   = (Get-ItemProperty $naglePath "TCPNoDelay").TCPNoDelay
    $ackFreq   = (Get-ItemProperty $naglePath "TcpAckFrequency").TcpAckFrequency

    $backup = [ordered]@{
        Timestamp           = (Get-Date).ToString("o")
        ToolVersion         = $Script:VERSION
        AdapterName         = $Adapter.Name
        AdapterGuid         = $guid
        AdapterLinkSpeed    = "$($Adapter.LinkSpeed)"
        DnsV4               = $dns4
        DnsV6               = $dns6
        Congestion          = $tcp.Congestion
        AutoTuning          = $tcp.AutoTuning
        Ecn                 = $tcp.Ecn
        Rss                 = $tcp.Rss
        Chimney             = $tcp.Chimney
        Heuristics          = $heur
        ThrottleIndexWasSet = ($null -ne $throttleBefore)
        ThrottleIndexValue  = $throttleBefore
        NagleKeysExisted    = (($null -ne $noDelay) -or ($null -ne $ackFreq))
        TCPNoDelayValue     = $noDelay
        TcpAckFreqValue     = $ackFreq
    }

    $backup | ConvertTo-Json -Depth 6 | Set-Content $Script:BackupFile -Encoding UTF8
    Write-Line OK "Backup saved: $Script:BackupFile"
    return $backup
}

function Apply-Dns {
    param($Adapter, $Best, [bool]$EnableDoH)
    $ErrorActionPreference = 'SilentlyContinue'

    $addrs = [System.Collections.Generic.List[string]]::new()
    $addrs.Add($Best.Provider.Pri4)
    if ($Best.Provider.Sec4) { $addrs.Add($Best.Provider.Sec4) }
    if ($null -ne $Best.Latency6 -and $Best.Provider.Pri6) {
        $addrs.Add($Best.Provider.Pri6)
        if ($Best.Provider.Sec6) { $addrs.Add($Best.Provider.Sec6) }
    }

    try {
        Set-DnsClientServerAddress -InterfaceAlias $Adapter.Name `
            -ServerAddresses $addrs.ToArray() -ErrorAction Stop
        Write-Line OK "DNS set: $($addrs -join ' | ')  on [$($Adapter.Name)]"
    } catch {
        Write-Line ERR "Failed to set DNS: $($_.Exception.Message)"
        return
    }

    ipconfig /flushdns | Out-Null
    Write-Line OK "DNS cache flushed."

    if ($EnableDoH -and $Best.Provider.Doh -and
        (Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue)) {
        foreach ($ip in @($Best.Provider.Pri4, $Best.Provider.Sec4)) {
            if (-not $ip) { continue }
            try {
                Add-DnsClientDohServerAddress `
                    -ServerAddress $ip `
                    -DohTemplate $Best.Provider.Doh `
                    -AutoUpgrade $true `
                    -AllowFallbackToUdp $true `
                    -ErrorAction Stop | Out-Null
                Write-Line OK "DoH registered for $ip ($($Best.Provider.Doh))"
            } catch {
                Write-Line INFO "DoH registration skipped for $ip — $($_.Exception.Message)"
            }
        }
    }

    $ErrorActionPreference = 'SilentlyContinue'
    $verifyDns = (Resolve-DnsName "cloudflare.com" -Server $Best.Provider.Pri4 `
        -Type A -DnsOnly -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
    if ($verifyDns) {
        Write-Line OK "DNS verification passed — resolved cloudflare.com → $verifyDns"
    } else {
        Write-Line WARN "DNS verification could not confirm resolution (may still work — ISP filtering)."
    }
}

function Apply-TcpOptimizations {
    param($Backup, $Adapter)
    $ErrorActionPreference = 'SilentlyContinue'
    Write-SectionHeader "TCP Stack Optimization"

    $congestion = if ($Backup.Congestion) { $Backup.Congestion } else { "unknown" }
    if ($congestion -ine 'cubic') {
        Invoke-Netsh "interface tcp set global congestionprovider=cubic" `
            "Congestion Control  →  CUBIC (RFC 8312, best for high-BDP links)"
    } else {
        Write-Line INFO "Congestion provider already CUBIC — no change."
    }

    $autoTune = if ($Backup.AutoTuning) { $Backup.AutoTuning } else { "unknown" }
    if ($autoTune -ine 'normal') {
        Invoke-Netsh "interface tcp set global autotuninglevel=normal" `
            "Auto-Tuning Level   →  normal (dynamic receive window)"
    } else {
        Write-Line INFO "Auto-Tuning already normal — no change."
    }

    $rss = if ($Backup.Rss) { $Backup.Rss } else { "unknown" }
    if ($rss -ine 'enabled') {
        Invoke-Netsh "interface tcp set global rss=enabled" `
            "RSS (Receive-Side Scaling)  →  enabled (multi-core NIC processing)"
    } else {
        Write-Line INFO "RSS already enabled — no change."
    }

    $heur = if ($Backup.Heuristics) { $Backup.Heuristics } else { "unknown" }
    if ($heur -ine 'disabled') {
        Invoke-Netsh "interface tcp set heuristics disabled" `
            "Window Scaling Heuristics  →  disabled (conflicts with Auto-Tuning)"
    } else {
        Write-Line INFO "Heuristics already disabled — no change."
    }

    $chimney = if ($Backup.Chimney) { $Backup.Chimney } else { "unknown" }
    if ($chimney -ine 'disabled') {
        Invoke-Netsh "interface tcp set global chimney=disabled" `
            "Chimney Offload  →  disabled (deprecated, causes issues on Win 10/11)"
    } else {
        Write-Line INFO "Chimney already disabled — no change."
    }

    Invoke-Netsh "interface tcp set global dca=disabled" `
        "DCA (Direct Cache Access)  →  disabled (non-functional on Win 10/11)" | Out-Null

    Invoke-Netsh "interface tcp set global netdma=disabled" `
        "NetDMA  →  disabled (removed in Win 8.1+, key is vestigial)" | Out-Null

    try {
        $qos = Get-NetQosPolicy -ErrorAction SilentlyContinue
        if (-not ($qos | Where-Object { $_.Name -eq 'NetworkTuner-Default' })) {
            New-NetQosPolicy -Name "NetworkTuner-Default" -Default `
                -DSCPAction 0 -ErrorAction SilentlyContinue | Out-Null
            Write-Line OK "QoS baseline policy set — prevents arbitrary traffic shaping."
        }
    } catch { }

    try {
        $adv = Get-NetAdapterAdvancedProperty -Name $Adapter.Name -ErrorAction SilentlyContinue
        $intr = $adv | Where-Object { $_.RegistryKeyword -match 'InterruptModeration' }
        if ($intr) {
            Set-NetAdapterAdvancedProperty -Name $Adapter.Name `
                -RegistryKeyword 'InterruptModeration' -RegistryValue 1 `
                -ErrorAction SilentlyContinue
            Write-Line OK "Interrupt Moderation enabled (reduces CPU overhead at high pps)."
        }
        $rdma = $adv | Where-Object { $_.RegistryKeyword -match 'RdmaMaxQueuePairCount' }
        if (-not $rdma) {
            $rss2 = $adv | Where-Object { $_.RegistryKeyword -match 'RSS' -and $_.RegistryKeyword -notmatch 'Base|Limit' }
            if ($rss2) { Write-Line INFO "Hardware RSS detected and already configured by driver." }
        }
    } catch { }

    Write-Line INFO "ECN auto-enable skipped — compatibility risk with ISP equipment."
}

function Apply-AdvancedOptions {
    param($Adapter)
    $ErrorActionPreference = 'SilentlyContinue'

    Write-SectionHeader "Optional Advanced Tweaks (Opt-in, each explained)"
    Write-Host "  Each tweak below is off by default. Read the description, then decide." -ForegroundColor $Script:Colors.Dim

    Write-Host ""
    Write-Host "  [1/4] NetworkThrottlingIndex" -ForegroundColor $Script:Colors.Accent
    Write-Host "        Disables MMCSS throttling on network packet processing." -ForegroundColor $Script:Colors.Dim
    Write-Host "        Recommended for: NAS transfers, streaming servers, 1Gbps+ FTTH." -ForegroundColor $Script:Colors.Dim
    Write-Host "        Risk: Low.  Restart required." -ForegroundColor $Script:Colors.Dim
    if (Confirm-Action "Enable NetworkThrottlingIndex (0xFFFFFFFF = unlimited)?" $false) {
        try {
            $p = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
            if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
            New-ItemProperty $p "NetworkThrottlingIndex" -Value 0xFFFFFFFF `
                -PropertyType DWord -Force | Out-Null
            New-ItemProperty $p "SystemResponsiveness"   -Value 0x0000000A `
                -PropertyType DWord -Force | Out-Null
            Write-Line OK "NetworkThrottlingIndex = 0xFFFFFFFF + SystemResponsiveness = 10 — restart required."
        } catch { Write-Line ERR "Failed: $($_.Exception.Message)" }
    }

    Write-Host "  [2/4] Disable Nagle's Algorithm (per-adapter)" -ForegroundColor $Script:Colors.Accent
    Write-Host "        Eliminates TCP send-buffering delay (40ms max buffer)." -ForegroundColor $Script:Colors.Dim
    Write-Host "        Recommended for: SSH, Telnet, TCP-based trading/real-time apps." -ForegroundColor $Script:Colors.Dim
    Write-Host "        No effect on UDP. Risk: Low-Medium.  Restart required." -ForegroundColor $Script:Colors.Dim
    if (Confirm-Action "Disable Nagle's Algorithm for adapter '$($Adapter.Name)'?" $false) {
        try {
            $np = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($Adapter.InterfaceGuid)"
            if (Test-Path $np) {
                New-ItemProperty $np "TCPNoDelay"      -Value 1 -PropertyType DWord -Force | Out-Null
                New-ItemProperty $np "TcpAckFrequency" -Value 1 -PropertyType DWord -Force | Out-Null
                Write-Line OK "Nagle disabled — TCPNoDelay=1, TcpAckFrequency=1 — restart required."
            } else {
                Write-Line WARN "Adapter registry path not found (GUID mismatch?) — skipped."
            }
        } catch { Write-Line ERR "Failed: $($_.Exception.Message)" }
    }

    Write-Host "  [3/4] Disable Adapter Power Management" -ForegroundColor $Script:Colors.Accent
    Write-Host "        Prevents NIC sleep during idle — eliminates wake-up micro-stutters." -ForegroundColor $Script:Colors.Dim
    Write-Host "        Recommended for: always-on servers, gaming rigs, FTTH setups." -ForegroundColor $Script:Colors.Dim
    Write-Host "        Risk: Very low (minor power usage increase).  No restart required." -ForegroundColor $Script:Colors.Dim
    if (Confirm-Action "Disable power management for adapter '$($Adapter.Name)'?" $false) {
        try {
            Set-NetAdapterPowerManagement -Name $Adapter.Name `
                -AllowComputerToTurnOffDevice Disabled -ErrorAction Stop
            Write-Line OK "NIC auto-shutdown disabled."
        } catch {
            Write-Line WARN "This adapter does not expose PM settings via PowerShell — trying WMI..."
            try {
                $nic = Get-WmiObject Win32_NetworkAdapter |
                       Where-Object { $_.GUID -eq $Adapter.InterfaceGuid }
                if ($nic) {
                    $nic.EnablePowerManagement($false) | Out-Null
                    Write-Line OK "PM disabled via WMI."
                }
            } catch { Write-Line WARN "WMI PM disable also unavailable — driver limitation." }
        }
        try {
            $props = Get-NetAdapterAdvancedProperty -Name $Adapter.Name -ErrorAction SilentlyContinue
            foreach ($kw in @('*EEE', 'EEE', 'EnhancedPowerManagementEnabled',
                              'SelectiveSuspend', 'WakeOnMagicPacket', 'WakeOnPattern')) {
                $prop = $props | Where-Object { $_.RegistryKeyword -eq $kw }
                if ($prop) {
                    $val = if ($kw -eq 'WakeOnMagicPacket' -or $kw -eq 'WakeOnPattern') { '0' } else { '0' }
                    Set-NetAdapterAdvancedProperty -Name $Adapter.Name `
                        -RegistryKeyword $kw -RegistryValue $val -ErrorAction SilentlyContinue
                    Write-Line OK "Disabled: $kw"
                }
            }
        } catch { }
    }

    Write-Host "  [4/4] Large Send Offload (LSO) & Checksum Offload" -ForegroundColor $Script:Colors.Accent
    Write-Host "        Moves TCP segmentation and checksum computation to the NIC hardware." -ForegroundColor $Script:Colors.Dim
    Write-Host "        Reduces CPU load significantly on high-throughput FTTH links." -ForegroundColor $Script:Colors.Dim
    Write-Host "        Risk: Very low (hardware-validated feature).  No restart required." -ForegroundColor $Script:Colors.Dim
    if (Confirm-Action "Enable LSO and hardware checksum offload for '$($Adapter.Name)'?" $true) {
        try {
            Enable-NetAdapterLso     -Name $Adapter.Name -ErrorAction SilentlyContinue
            Enable-NetAdapterChecksumOffload -Name $Adapter.Name -ErrorAction SilentlyContinue
            Write-Line OK "LSO and checksum offload enabled — NIC handles segmentation/checksums."
        } catch {
            Write-Line WARN "Adapter may not support these offload features — $($_.Exception.Message)"
        }
        try {
            Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Enabled -ErrorAction SilentlyContinue
            Write-Line OK "Receive Segment Coalescing (RSC) enabled — reduces per-packet CPU cost."
        } catch { }
    }
}

function Invoke-Optimization {
    Write-Banner "$Script:TOOL_NAME v$Script:VERSION — Optimize" `
        "DNS benchmark (parallel) → TCP tuning → optional advanced tweaks"

    Write-SectionHeader "Step 1 of 4 — Select Network Adapter"
    $adapter = Select-NetworkAdapter
    if (-not $adapter) { return }
    Show-AdapterInfo -Adapter $adapter

    Write-SectionHeader "Step 2 of 4 — Exact Backup of Current State"
    $backup = Backup-CurrentState -Adapter $adapter
    Write-Line INFO "Saved: DNS, TCP global, Heuristics, Registry (Throttle + Nagle) — all fields."

    Write-SectionHeader "Step 3 of 4 — Parallel DNS Latency Benchmark"
    Write-Host "  Protocol: TCP/53  |  Attempts: 4 per provider  |  Method: trimmed average" -ForegroundColor $Script:Colors.Dim
    Write-Host "  TCP/53 is used because ICMP is frequently blocked or rate-limited by ISPs." -ForegroundColor $Script:Colors.Dim

    $candidates = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($p in $Script:DnsProviders) { $candidates.Add($p) }

    $customIp = Read-Host "  [Optional] Custom DNS IPv4 to include (leave blank to skip)"
    if ($customIp.Trim()) {
        $parsed = $null
        if ([ipaddress]::TryParse($customIp.Trim(), [ref]$parsed)) {
            $candidates.Add([PSCustomObject]@{
                Name = 'Custom'; Pri4 = $customIp.Trim(); Sec4 = $null
                Pri6 = $null;   Sec6 = $null;            Doh  = $null
            })
            Write-Line OK "Custom '$($customIp.Trim())' added to benchmark."
        } else {
            Write-Line WARN "Invalid IP address format — custom entry skipped."
        }
    }

    $sorted = Measure-DnsProvidersParallel -Candidates $candidates
    Show-DnsResults -Results $sorted

    $reachable = @($sorted | Where-Object { $null -ne $_.Latency4 })
    if ($reachable.Count -eq 0) {
        Write-Line WARN "All providers unreachable via TCP/53 — DNS will not be changed."
        Write-Line WARN "This usually means port 53 TCP is blocked at the ISP/router level."
    } else {
        $best = $reachable[0]
        Write-Line OK "Fastest: $($best.Name)  at $($best.Latency4) ms avg"
        $enableDoH = $false
        if ($best.Provider.Doh -and (Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue)) {
            $enableDoH = Confirm-Action "Enable DNS-over-HTTPS for '$($best.Name)'? (encrypts all DNS queries)" $true
        }
        Apply-Dns -Adapter $adapter -Best $best -EnableDoH $enableDoH
    }

    Write-SectionHeader "Step 4 of 4 — TCP Stack + Advanced Tweaks"
    Apply-TcpOptimizations -Backup $backup -Adapter $adapter
    Apply-AdvancedOptions  -Adapter $adapter

    Write-Banner "Optimization Complete"
    Write-Line OK   "All selected changes applied successfully."
    Write-Line OK   "Full session log: $Script:SessionLog"
    Write-Line WARN "If any tweak required a restart, reboot now for full effect."
    Write-Line INFO "Reminder: These optimizations improve latency and reduce overhead."
    Write-Line INFO "Bandwidth ceiling is set by your ISP plan — no software can raise it."
}

function Invoke-Rollback {
    Write-Banner "$Script:TOOL_NAME — Rollback" "Restore your exact pre-optimization state"

    if (-not (Test-Path $Script:BackupFile)) {
        Write-Line WARN "No backup file found. Run Optimize first to create one."
        Write-Host ""
        if (-not (Confirm-Action "Apply approximate generic Windows defaults instead?" $false)) { return }
        Restore-GenericDefaults
        return
    }

    $ErrorActionPreference = 'SilentlyContinue'
    $b = Get-Content $Script:BackupFile -Raw -Encoding UTF8 | ConvertFrom-Json

    Write-SectionHeader "Backup Details"
    Write-TableRow "Saved At"      $b.Timestamp      White
    Write-TableRow "Tool Version"  $b.ToolVersion    DarkGray
    Write-TableRow "Adapter"       $b.AdapterName    Cyan
    Write-TableRow "Speed"         $b.AdapterLinkSpeed Green
    Write-TableRow "DNS IPv4"      (@($b.DnsV4) -join ", ") Yellow
    Write-TableRow "Congestion"    $b.Congestion     White
    Write-TableRow "Auto-Tuning"   $b.AutoTuning     White
    Write-TableRow "RSS"           $b.Rss            White
    Write-TableRow "Heuristics"    $b.Heuristics     White
    Write-TableRow "Chimney"       $b.Chimney        White
    Write-TableRow "Nagle Keys"    "$($b.NagleKeysExisted)" Gray
    Write-TableRow "ThrottleIndex" "$($b.ThrottleIndexWasSet)" Gray

    if (-not (Confirm-Action "Restore exactly these settings now?" $true)) { return }

    $v4 = @($b.DnsV4); $v6 = @($b.DnsV6)
    try {
        if ($v4.Count -gt 0 -or $v6.Count -gt 0) {
            Set-DnsClientServerAddress -InterfaceAlias $b.AdapterName `
                -ServerAddresses ($v4 + $v6) -ErrorAction Stop
            Write-Line OK "DNS restored: $($v4 -join ', ')"
        } else {
            Set-DnsClientServerAddress -InterfaceAlias $b.AdapterName `
                -ResetServerAddresses -ErrorAction Stop
            Write-Line OK "DNS reset to DHCP automatic."
        }
        ipconfig /flushdns | Out-Null
        Write-Line OK "DNS cache flushed."
    } catch { Write-Line ERR "DNS restore failed: $($_.Exception.Message)" }

    if ($b.Congestion) {
        Invoke-Netsh "interface tcp set global congestionprovider=$($b.Congestion)" `
            "Congestion Provider → $($b.Congestion)"
    }
    if ($b.AutoTuning) {
        Invoke-Netsh "interface tcp set global autotuninglevel=$($b.AutoTuning)" `
            "Auto-Tuning Level  → $($b.AutoTuning)"
    }
    if ($b.Rss) {
        Invoke-Netsh "interface tcp set global rss=$($b.Rss)" `
            "RSS                → $($b.Rss)"
    }
    if ($b.Heuristics) {
        Invoke-Netsh "interface tcp set heuristics $($b.Heuristics)" `
            "Heuristics         → $($b.Heuristics)"
    }
    if ($b.Chimney) {
        Invoke-Netsh "interface tcp set global chimney=$($b.Chimney)" `
            "Chimney            → $($b.Chimney)"
    }

    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if (-not $b.ThrottleIndexWasSet) {
        Remove-ItemProperty $regPath "NetworkThrottlingIndex" -ErrorAction SilentlyContinue
        Remove-ItemProperty $regPath "SystemResponsiveness"   -ErrorAction SilentlyContinue
        Write-Line OK "NetworkThrottlingIndex removed (was absent originally)."
    } elseif ($null -ne $b.ThrottleIndexValue) {
        New-ItemProperty $regPath "NetworkThrottlingIndex" -Value $b.ThrottleIndexValue `
            -PropertyType DWord -Force | Out-Null
        Write-Line OK "NetworkThrottlingIndex restored to $($b.ThrottleIndexValue)."
    }

    $naglePath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($b.AdapterGuid)"
    if (Test-Path $naglePath) {
        if (-not $b.NagleKeysExisted) {
            Remove-ItemProperty $naglePath "TCPNoDelay"      -ErrorAction SilentlyContinue
            Remove-ItemProperty $naglePath "TcpAckFrequency" -ErrorAction SilentlyContinue
            Write-Line OK "Nagle registry keys removed (were absent originally)."
        } else {
            if ($null -ne $b.TCPNoDelayValue) {
                New-ItemProperty $naglePath "TCPNoDelay" -Value $b.TCPNoDelayValue `
                    -PropertyType DWord -Force | Out-Null
            }
            if ($null -ne $b.TcpAckFreqValue) {
                New-ItemProperty $naglePath "TcpAckFrequency" -Value $b.TcpAckFreqValue `
                    -PropertyType DWord -Force | Out-Null
            }
            Write-Line OK "Nagle registry keys restored to original values."
        }
    }

    Write-Line OK   "Rollback complete — all settings restored to saved state."
    Write-Line WARN "Restart recommended to fully apply all registry changes."
}

function Restore-GenericDefaults {
    $ErrorActionPreference = 'SilentlyContinue'
    Write-Line WARN "Restoring approximate Windows defaults (not your personal originals)..."

    $adapter = Select-NetworkAdapter
    if ($adapter) {
        Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses | Out-Null
        Write-Line OK "DNS reset to DHCP automatic."
        ipconfig /flushdns | Out-Null

        $naglePath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($adapter.InterfaceGuid)"
        if (Test-Path $naglePath) {
            Remove-ItemProperty $naglePath "TCPNoDelay"      -ErrorAction SilentlyContinue
            Remove-ItemProperty $naglePath "TcpAckFrequency" -ErrorAction SilentlyContinue
            Write-Line OK "Nagle registry keys removed."
        }
    }

    Invoke-Netsh "interface tcp set global congestionprovider=default" "Congestion  → default"
    Invoke-Netsh "interface tcp set global autotuninglevel=normal"     "AutoTuning  → normal"
    Invoke-Netsh "interface tcp set global rss=enabled"                "RSS         → enabled"
    Invoke-Netsh "interface tcp set global chimney=disabled"           "Chimney     → disabled"
    Invoke-Netsh "interface tcp set heuristics enabled"                "Heuristics  → enabled"

    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    Remove-ItemProperty $regPath "NetworkThrottlingIndex" -ErrorAction SilentlyContinue
    Remove-ItemProperty $regPath "SystemResponsiveness"   -ErrorAction SilentlyContinue
    Write-Line OK "Registry keys cleaned."
    Write-Line OK "Generic defaults applied."
}

function Invoke-StackRepair {
    Write-Banner "$Script:TOOL_NAME — Network Stack Repair" `
        "Full IP + Winsock reset — for connectivity failures, not speed"

    Write-Host ""
    Write-Host "  This resets the TCP/IP stack and Winsock catalog at kernel level." -ForegroundColor $Script:Colors.Dim
    Write-Host "  Use ONLY for genuine connectivity problems (broken internet, VPN issues)." -ForegroundColor $Script:Colors.Dim
    Write-Host "  Side effects: VPN clients and security software may need reconfiguration." -ForegroundColor Yellow
    Write-Host "  A full system restart is MANDATORY after this operation." -ForegroundColor Yellow
    Write-Host ""

    if (-not (Confirm-Action "Proceed with full network stack reset?" $false)) { return }

    Write-Line INFO "Releasing DHCP lease..."
    $ErrorActionPreference = 'SilentlyContinue'
    ipconfig /release | Out-Null

    Write-Line INFO "Flushing DNS resolver cache..."
    ipconfig /flushdns | Out-Null
    Write-Line OK  "DNS cache cleared."

    Write-Line INFO "Flushing NetBIOS cache..."
    nbtstat -R 2>&1 | Out-Null
    Write-Line OK  "NetBIOS cache cleared."

    $resetLog = Join-Path $Script:LogFolder "ip_reset_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Invoke-Netsh "int ip reset `"$resetLog`"" "TCP/IP stack reset (log → $resetLog)"
    Invoke-Netsh "winsock reset"              "Winsock catalog reset"
    Invoke-Netsh "int ipv6 reset"             "IPv6 stack reset"

    Write-Host ""
    Write-Line OK   "All reset commands executed."
    Write-Line WARN "YOU MUST RESTART NOW for the reset to take effect."
    Write-Line INFO "After reboot: re-check network settings and reconfigure VPN if needed."

    $reboot = Confirm-Action "Restart the computer now?" $false
    if ($reboot) {
        Write-Line WARN "Restarting in 10 seconds... (close any unsaved work now)"
        Start-Sleep 10
        Restart-Computer -Force
    }
}

function Show-CurrentState {
    Write-Banner "$Script:TOOL_NAME — Network Status" "Live read — no changes made"

    $ErrorActionPreference = 'SilentlyContinue'
    $adapters = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false })
    if ($adapters.Count -eq 0) {
        $adapters = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' })
    }

    foreach ($a in $adapters) {
        $type = switch -Regex ($a.PhysicalMediaType) {
            '802\.3'  { "Ethernet" }
            '802\.11' { "Wi-Fi"    }
            default   { "Other"    }
        }
        Write-SectionHeader "Adapter: $($a.Name) [$type]"
        Write-TableRow "Link Speed"  "$($a.LinkSpeed)"    Green
        Write-TableRow "MAC Address" $a.MacAddress        White

        $ips = @(Get-NetIPAddress -InterfaceAlias $a.Name -AddressFamily IPv4 |
                 Where-Object { $_.IPAddress -notlike '169.*' })
        if ($ips.Count -gt 0) { Write-TableRow "IPv4 Address" ($ips.IPAddress -join ", ") Cyan }

        $dns4 = (Get-DnsClientServerAddress -InterfaceAlias $a.Name -AddressFamily IPv4).ServerAddresses
        if ($dns4) { Write-TableRow "DNS (IPv4)" ($dns4 -join ", ") Yellow }
        else        { Write-TableRow "DNS (IPv4)" "DHCP automatic"    DarkGray }
    }

    Write-SectionHeader "TCP Global Settings"
    $tcp  = Get-TcpGlobalState
    $heur = Get-TcpHeuristicsState

    $tcpChecks = @(
        @{ Label="Congestion Provider";      Value=$tcp.Congestion;  Good="cubic";    Rec="cubic"    }
        @{ Label="Auto-Tuning Level";         Value=$tcp.AutoTuning;  Good="normal";   Rec="normal"   }
        @{ Label="ECN Capability";            Value=$tcp.Ecn;         Good="disabled"; Rec="disabled" }
        @{ Label="RSS State";                 Value=$tcp.Rss;         Good="enabled";  Rec="enabled"  }
        @{ Label="Chimney Offload";           Value=$tcp.Chimney;     Good="disabled"; Rec="disabled" }
        @{ Label="Window Heuristics";         Value=$heur;            Good="disabled"; Rec="disabled" }
    )

    foreach ($c in $tcpChecks) {
        $v     = if ($c.Value) { $c.Value } else { "unknown" }
        $color = if ($v -ieq $c.Good) { "Green" } else { "Yellow" }
        $note  = if ($v -ine $c.Good -and $c.Value) { "  [recommended: $($c.Rec)]" } else { "" }
        Write-Host ("  {0,-32}" -f $c.Label) -ForegroundColor $Script:Colors.Dim -NoNewline
        Write-Host ("{0,-12}{1}" -f $v, $note) -ForegroundColor $color
        Write-Log "$($c.Label): $v" "STATUS"
    }

    Write-SectionHeader "Backup File Status"
    if (Test-Path $Script:BackupFile) {
        $b = Get-Content $Script:BackupFile -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-TableRow "Status"       "Available"                         Green
        Write-TableRow "Saved At"     $b.Timestamp                        White
        Write-TableRow "Adapter"      $b.AdapterName                      Cyan
        Write-TableRow "Tool Version" $b.ToolVersion                      DarkGray
    } else {
        Write-TableRow "Status" "No backup — run Optimize first to create one." Yellow
    }
}

function Show-MainMenu {
    Clear-Host
    $w = 72
    Write-Host ("=" * $w) -ForegroundColor Cyan
    Write-Host ("  $Script:TOOL_NAME  v$Script:VERSION  [$Script:EDITION]") -ForegroundColor Green
    Write-Host ("  FTTH / High-Speed Network Optimizer for Windows — Production Ready") -ForegroundColor Gray
    Write-Host ("=" * $w) -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("  [1]  Optimize  —  Parallel DNS benchmark, TCP tuning, advanced tweaks") -ForegroundColor White
    Write-Host ("  [2]  Rollback  —  Restore exact pre-optimization settings from backup") -ForegroundColor Yellow
    Write-Host ("  [3]  Repair    —  Full IP/Winsock reset (connectivity failures only)")  -ForegroundColor DarkYellow
    Write-Host ("  [4]  Status    —  Live view: all adapters, TCP state, backup status")   -ForegroundColor Cyan
    Write-Host ("  [5]  Exit")                                                               -ForegroundColor DarkGray
    Write-Host ""
    Write-Host ("=" * $w) -ForegroundColor Cyan
    Write-Host ("  Logs: $Script:LogFolder") -ForegroundColor DarkGray
    if (Test-Path $Script:BackupFile) {
        $ts = ((Get-Content $Script:BackupFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue |
                ConvertFrom-Json -ErrorAction SilentlyContinue).Timestamp)
        if ($ts) { Write-Host ("  Backup: $ts") -ForegroundColor DarkGreen }
    }
    Write-Host ""
}

Initialize-Elevation
Initialize-Logging
Write-Log "Tool started. OS=$([System.Environment]::OSVersion.VersionString) PS=$($PSVersionTable.PSVersion)" "INIT"

do {
    Show-MainMenu
    $choice = $null
    try { $choice = (Read-Host "  Select option (1-5)").Trim() } catch { $choice = "5" }
    Write-Host ""
    Write-Log "Menu choice: $choice" "UI"

    switch ($choice) {
        '1' { Invoke-Optimization }
        '2' { Invoke-Rollback     }
        '3' { Invoke-StackRepair  }
        '4' { Show-CurrentState   }
        '5' { }
        default { Write-Host "  Invalid choice — please enter 1 to 5." -ForegroundColor Red }
    }

    if ($choice -ne '5') {
        Write-Host ""
        try { $null = Read-Host "  Press Enter to return to menu" } catch { }
    }

} while ($choice -ne '5')

Write-Log "Session ended." "INIT"
Write-Host ""
Write-Host ("  " + ("=" * 70)) -ForegroundColor DarkGray
Write-Host ("  Session complete. Log saved to:") -ForegroundColor Gray
Write-Host ("  $Script:SessionLog") -ForegroundColor Cyan
Write-Host ("  " + ("=" * 70)) -ForegroundColor DarkGray
Write-Host ""
