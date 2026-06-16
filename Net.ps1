#requires -Version 5.1
<#
===================================================================================
  FTTH NETWORK TUNER — REALISTIC EDITION  (v3.0 — 2026)
===================================================================================
  فلسفة هذا السكربت:
   - كل تعديل هنا له سبب تقني معروف وموثّق (تم التحقق منه)، وليس "خرافة تفعيل سحري".
   - أي تعديل غير مؤكد الفائدة أو متعارض عليه يبقى اختياري (Opt-in) وبتحذير واضح،
     لا يتم تطبيقه تلقائياً.
   - يتم أخذ نسخة احتياطية حقيقية من القيم الحالية قبل أي تغيير، بحيث يكون
     الاسترجاع (Rollback) دقيقاً لحالتك أنت، لا مجرد "افتراضيات عامة".
   - كل أمر netsh يتم التحقق من نتيجته (Exit Code) فعلياً قبل الإعلان عن نجاحه.

  مصادر التصميم (للمراجعة، وليست استشهادات حرفية):
   - مشكلة NetworkThrottlingIndex/MMCSS: موضّحة من فرق Sysinternals ومجتمعات الويندوز
     (يحد من معالجة الشبكة لغير الوسائط المتعددة عند تفعيل MMCSS، وقد يحدّ السرعة
     على روابط الجيجابت — يتطلب إعادة تشغيل).
   - Nagle's Algorithm (TcpAckFrequency/TCPNoDelay): موضوع مثير للجدل في مجتمعات
     المبرمجين (Reddit/منتديات Steam)، رأي خبراء الشبكات أنه يفضّل تعديله على مستوى
     التطبيق لا النظام، ولا تأثير له على الألعاب التي تستخدم UDP. لذلك هو اختياري
     بالكامل هنا مع تحذير صريح.
   - بنية أوامر netsh (congestionprovider / autotuninglevel / rss / ecncapability /
     heuristics) موثّقة من Microsoft Learn ومجتمع netsh. لاحظ أن "heuristics" أمر
     مستقل بذاته (netsh interface tcp set heuristics) ولا يُكتب تحت "set global"
     كما كان في نسخ سابقة من سكربتات مشابهة — هذا خطأ تركيبي شائع تم تجنّبه هنا.
===================================================================================
#>

# -----------------------------------------------------------------------------
# 0) ترميز الطرفية (لعرض النص العربي بشكل صحيح)
# -----------------------------------------------------------------------------
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() } catch {}

# -----------------------------------------------------------------------------
# 1) رفع الصلاحيات تلقائياً (مع معالجة حالة تشغيل السكربت عبر iex/سطر مباشر)
# -----------------------------------------------------------------------------
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Definition }

    if (-not $scriptPath -or -not (Test-Path $scriptPath)) {
        Write-Host "تعذّر إعادة التشغيل برفع الصلاحيات تلقائياً لأن السكربت لا يعمل من ملف .ps1 فعلي" -ForegroundColor Red
        Write-Host "(مثلاً تم تشغيله عبر iex من سطر واحد). الرجاء حفظه كملف .ps1 وتشغيله يدوياً كمسؤول." -ForegroundColor Yellow
        Read-Host "اضغط Enter للخروج"
        exit 1
    }

    Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$scriptPath`"") -Verb RunAs
    exit
}

Clear-Host

# -----------------------------------------------------------------------------
# 2) إعداد مجلد ومسارات السجلّات + ملف النسخة الاحتياطية
# -----------------------------------------------------------------------------
$Script:LogFolder  = Join-Path ([Environment]::GetFolderPath("Desktop")) "Network_Tuner_Logs"
if (-not (Test-Path $Script:LogFolder)) { New-Item -Path $Script:LogFolder -ItemType Directory -Force | Out-Null }

$Script:SessionLog = Join-Path $Script:LogFolder "Session_Log.txt"
$Script:BackupFile = Join-Path $Script:LogFolder "Last_Known_State.json"

"=== جلسة جديدة: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -Path $Script:SessionLog -Encoding UTF8

# -----------------------------------------------------------------------------
# 3) دوال الطباعة والتسجيل
# -----------------------------------------------------------------------------
function Write-Line {
    param(
        [string]$Message = "",
        [ValidateSet("INFO","OK","WARN","ERR","TITLE","PLAIN")][string]$Level = "PLAIN",
        [switch]$NoNewline
    )
    $colors = @{ INFO="Gray"; OK="Green"; WARN="Yellow"; ERR="Red"; TITLE="Cyan"; PLAIN="White" }
    $tags   = @{ INFO="   "; OK="[OK] "; WARN="[!]  "; ERR="[X]  "; TITLE=""; PLAIN="" }
    $text = "$($tags[$Level])$Message"

    if ($NoNewline) {
        Write-Host $text -ForegroundColor $colors[$Level] -NoNewline
        Add-Content -Path $Script:SessionLog -Value $text -NoNewline -Encoding UTF8
    } else {
        Write-Host $text -ForegroundColor $colors[$Level]
        Add-Content -Path $Script:SessionLog -Value $text -Encoding UTF8
    }
}

function Write-Banner {
    param([string]$Title)
    $line = "=" * 75
    Write-Host $line -ForegroundColor Cyan
    Write-Host ("  " + $Title) -ForegroundColor Green
    Write-Host $line -ForegroundColor Cyan
}

function Confirm-Action {
    param([string]$Prompt, [bool]$DefaultYes = $false)
    $suffix = if ($DefaultYes) { "(Y/n)" } else { "(y/N)" }
    $resp = Read-Host "$Prompt $suffix"
    if ([string]::IsNullOrWhiteSpace($resp)) { return $DefaultYes }
    return ($resp.Trim().ToLower() -in @('y','yes','نعم'))
}

# -----------------------------------------------------------------------------
# 4) قائمة مزودي DNS (مع قوالب DoH الحقيقية لكل مزود)
# -----------------------------------------------------------------------------
$Script:DnsProviders = @(
    [PSCustomObject]@{ Name='Cloudflare'; Pri4='1.1.1.1';      Sec4='1.0.0.1';        Pri6='2606:4700:4700::1111'; Sec6='2606:4700:4700::1001'; Doh='https://cloudflare-dns.com/dns-query' }
    [PSCustomObject]@{ Name='Google';     Pri4='8.8.8.8';      Sec4='8.8.4.4';        Pri6='2001:4860:4860::8888'; Sec6='2001:4860:4860::8844'; Doh='https://dns.google/dns-query' }
    [PSCustomObject]@{ Name='Quad9';      Pri4='9.9.9.9';      Sec4='149.112.112.112';Pri6='2620:fe::fe';          Sec6='2620:fe::9';           Doh='https://dns.quad9.net/dns-query' }
    [PSCustomObject]@{ Name='AdGuard';    Pri4='94.140.14.14'; Sec4='94.140.15.15';   Pri6='2a10:50c0::ad1:ff';    Sec6='2a10:50c0::ad2:ff';    Doh='https://dns.adguard.com/dns-query' }
)

# -----------------------------------------------------------------------------
# 5) أداة قياس زمن استجابة DNS الحقيقية: اتصال TCP على البورت 53
#    (أدق وأكثر موثوقية من ICMP ping، لأن كثيراً من الشبكات تحجب ICMP بينما
#     تترك بورت DNS مفتوحاً — وهذا هو البورت الذي يُستخدم فعلياً لاستعلامات DNS)
# -----------------------------------------------------------------------------
function Test-DnsTcpLatency {
    param([string]$ServerIp, [int]$Port = 53, [int]$TimeoutMs = 1000, [int]$Attempts = 3)
    $times = @()
    for ($i = 0; $i -lt $Attempts; $i++) {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $task = $client.BeginConnect($ServerIp, $Port, $null, $null)
            $done = $task.AsyncWaitHandle.WaitOne($TimeoutMs)
            if ($done -and $client.Connected) {
                $sw.Stop()
                $times += $sw.Elapsed.TotalMilliseconds
                $client.EndConnect($task)
            }
        } catch {
        } finally {
            $client.Close()
        }
    }
    if ($times.Count -eq 0) { return $null }
    return [Math]::Round((($times | Measure-Object -Average).Average), 1)
}

# -----------------------------------------------------------------------------
# 6) تنفيذ أوامر netsh مع التحقق الحقيقي من نتيجة التنفيذ (Exit Code)
# -----------------------------------------------------------------------------
function Invoke-Netsh {
    param([string]$Arguments, [string]$Description)
    $argArray = $Arguments -split '\s+'
    $output = & netsh @argArray 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Line -Level OK -Message $Description
        return $true
    } else {
        Write-Line -Level WARN -Message "$Description -> فشل التنفيذ (exit code $LASTEXITCODE)"
        Add-Content -Path $Script:SessionLog -Value "    تفاصيل: $output" -Encoding UTF8
        return $false
    }
}

# -----------------------------------------------------------------------------
# 7) قراءة إعدادات TCP العامة الحالية (Parsing حقيقي لمخرجات netsh)
# -----------------------------------------------------------------------------
function Get-TcpGlobalState {
    $raw = & netsh interface tcp show global 2>&1
    $state = [ordered]@{
        Congestion = $null
        AutoTuning = $null
        Ecn        = $null
        Rss        = $null
        Raw        = ($raw -join "`r`n")
    }
    foreach ($line in $raw) {
        if ($line -match 'Congestion Control Provider\s*:\s*(\S+)')   { $state.Congestion = $matches[1] }
        elseif ($line -match 'Auto-Tuning Level\s*:\s*(\S+)')          { $state.AutoTuning = $matches[1] }
        elseif ($line -match 'ECN Capability\s*:\s*(\S+)')             { $state.Ecn        = $matches[1] }
        elseif ($line -match 'Receive-Side Scaling State\s*:\s*(\S+)') { $state.Rss        = $matches[1] }
    }
    return $state
}

function Get-TcpHeuristicsState {
    $raw = & netsh interface tcp show heuristics 2>&1
    foreach ($line in $raw) {
        if ($line -match 'Window Scaling heuristics\s*:\s*(\S+)') { return $matches[1] }
    }
    return $null
}

# -----------------------------------------------------------------------------
# 8) اكتشاف واختيار واجهة الشبكة النشطة (سلكي أو لاسلكي، تستثني الواجهات الافتراضية)
# -----------------------------------------------------------------------------
function Select-NetworkAdapter {
    $candidates = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
    if (-not $candidates) {
        $candidates = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    }
    if (-not $candidates) {
        Write-Line -Level ERR -Message "لا توجد أي واجهة شبكة نشطة (سلكية أو لاسلكية) على هذا الجهاز."
        return $null
    }

    if (@($candidates).Count -eq 1) {
        return $candidates
    }

    Write-Banner "تم العثور على أكثر من واجهة شبكة نشطة — اختر واحدة"
    $i = 1
    foreach ($a in $candidates) {
        $type = if ($a.PhysicalMediaType -eq '802.3') { 'سلكي/Ethernet' }
                elseif ($a.PhysicalMediaType -match '802.11') { 'لاسلكي/Wi-Fi' }
                else { $a.PhysicalMediaType }
        Write-Host (" [{0}] {1,-25} | {2,-15} | السرعة: {3}" -f $i, $a.Name, $type, $a.LinkSpeed)
        $i++
    }
    $sel = Read-Host "أدخل رقم الواجهة"
    $idx = 0
    if ([int]::TryParse($sel, [ref]$idx) -and $idx -ge 1 -and $idx -le @($candidates).Count) {
        return @($candidates)[$idx - 1]
    }
    Write-Line -Level WARN -Message "اختيار غير صالح — سيتم استخدام أول واجهة بالقائمة."
    return @($candidates)[0]
}

# -----------------------------------------------------------------------------
# 9) النسخ الاحتياطي الحقيقي للحالة الحالية قبل أي تعديل
# -----------------------------------------------------------------------------
function Backup-CurrentState {
    param($Adapter)

    $dns4 = (Get-DnsClientServerAddress -InterfaceAlias $Adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
    $dns6 = (Get-DnsClientServerAddress -InterfaceAlias $Adapter.Name -AddressFamily IPv6 -ErrorAction SilentlyContinue).ServerAddresses
    $tcp  = Get-TcpGlobalState
    $heur = Get-TcpHeuristicsState

    $regThrottlePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    $throttleBefore  = (Get-ItemProperty -Path $regThrottlePath -Name "NetworkThrottlingIndex" -ErrorAction SilentlyContinue).NetworkThrottlingIndex

    $nagleGuid = $Adapter.InterfaceGuid
    $naglePath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$nagleGuid"
    $tcpNoDelayBefore = (Get-ItemProperty -Path $naglePath -Name "TCPNoDelay" -ErrorAction SilentlyContinue).TCPNoDelay
    $tcpAckFreqBefore = (Get-ItemProperty -Path $naglePath -Name "TcpAckFrequency" -ErrorAction SilentlyContinue).TcpAckFrequency

    $backup = [ordered]@{
        Timestamp        = (Get-Date).ToString("o")
        AdapterName      = $Adapter.Name
        AdapterGuid      = $nagleGuid
        DnsV4            = @($dns4)
        DnsV6            = @($dns6)
        Congestion       = $tcp.Congestion
        AutoTuning       = $tcp.AutoTuning
        Ecn              = $tcp.Ecn
        Rss              = $tcp.Rss
        Heuristics       = $heur
        ThrottleIndexWasSet = ($null -ne $throttleBefore)
        ThrottleIndexValue  = $throttleBefore
        NagleKeysExisted = (($null -ne $tcpNoDelayBefore) -or ($null -ne $tcpAckFreqBefore))
        TCPNoDelayValue  = $tcpNoDelayBefore
        TcpAckFreqValue  = $tcpAckFreqBefore
    }

    $backup | ConvertTo-Json -Depth 5 | Set-Content -Path $Script:BackupFile -Encoding UTF8
    Write-Line -Level OK -Message "تم حفظ نسخة دقيقة من إعداداتك الحالية في: $Script:BackupFile"
    return $backup
}

# -----------------------------------------------------------------------------
# 10) التحسين (Option 1)
# -----------------------------------------------------------------------------
function Invoke-Optimization {
    Write-Banner "الخطوة 1 من 4 — تحديد واجهة الشبكة"
    $adapter = Select-NetworkAdapter
    if (-not $adapter) { return }
    Write-Line -Level OK -Message "تم اختيار: $($adapter.Name)  ($($adapter.LinkSpeed))"

    Write-Banner "الخطوة 2 من 4 — أخذ نسخة احتياطية من إعداداتك الحالية"
    $backup = Backup-CurrentState -Adapter $adapter

    Write-Banner "الخطوة 3 من 4 — قياس زمن استجابة DNS الحقيقي (TCP/53، لا يعتمد على ICMP)"
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $Script:DnsProviders) { $candidates.Add($p) }

    if (Confirm-Action "هل تريد إضافة مزوّد DNS مخصص لاختباره أيضاً؟" $false) {
        $customIp = Read-Host "أدخل عنوان IPv4 للمزوّد المخصص"
        if ($customIp -as [ipaddress]) {
            $candidates.Add([PSCustomObject]@{ Name='Custom'; Pri4=$customIp; Sec4=$customIp; Pri6=$null; Sec6=$null; Doh=$null })
        }
    }

    $results = @()
    $n = $candidates.Count; $c = 0
    foreach ($p in $candidates) {
        $c++
        Write-Progress -Activity "قياس سرعة DNS" -Status $p.Name -PercentComplete (($c/$n)*100)
        $lat4 = Test-DnsTcpLatency -ServerIp $p.Pri4
        $lat6 = if ($p.Pri6) { Test-DnsTcpLatency -ServerIp $p.Pri6 } else { $null }
        $results += [PSCustomObject]@{ Provider=$p; Name=$p.Name; Latency4=$lat4; Latency6=$lat6 }
    }
    Write-Progress -Activity "قياس سرعة DNS" -Completed

    $sorted = $results | Sort-Object -Property @{Expression={ if ($_.Latency4) {$_.Latency4} else {[double]::MaxValue} }}

    Write-Host ""
    Write-Line -Level TITLE -Message "نتائج القياس (الأسرع أولاً، بالمللي ثانية):"
    Write-Host ("-" * 75) -ForegroundColor Cyan
    foreach ($r in $sorted) {
        $s4 = if ($r.Latency4) { "$($r.Latency4) ms" } else { "غير متوفر/محجوب" }
        $s6 = if ($r.Latency6) { "$($r.Latency6) ms" } else { "غير متوفر" }
        Write-Host (" {0,-12} | IPv4: {1,-18} | IPv6: {2}" -f $r.Name, $s4, $s6)
    }
    Write-Host ("-" * 75) -ForegroundColor Cyan

    $reachable = $sorted | Where-Object { $_.Latency4 }
    if (-not $reachable) {
        Write-Line -Level WARN -Message "كل المزودين لم يستجيبوا — قد يكون هناك حجب على الشبكة. سيتم تجاهل تغيير DNS والاحتفاظ بإعداداتك الحالية."
    } else {
        $best = $reachable[0]
        Write-Line -Level OK -Message "الأفضل استجابة: $($best.Name)"
        try {
            $addrs = @($best.Provider.Pri4, $best.Provider.Sec4)
            if ($best.Latency6) { $addrs += @($best.Provider.Pri6, $best.Provider.Sec6) }
            Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $addrs -ErrorAction Stop
            Write-Line -Level OK -Message "تم تطبيق DNS الجديد على '$($adapter.Name)'."

            if ($best.Provider.Doh -and (Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue)) {
                if (Confirm-Action "هل تريد تفعيل DNS-over-HTTPS (تشفير استعلامات DNS) لهذا المزوّد إن كان النظام يدعمه؟" $true) {
                    foreach ($ip in @($best.Provider.Pri4, $best.Provider.Sec4)) {
                        try {
                            Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $best.Provider.Doh -AutoUpgrade $true -AllowFallbackToUdp $true -ErrorAction Stop | Out-Null
                        } catch { }
                    }
                    Write-Line -Level OK -Message "تم محاولة تفعيل DoH (سيتم تجاهلها بهدوء إن لم يدعمها نظامك)."
                }
            }
        } catch {
            Write-Line -Level ERR -Message "فشل تطبيق DNS تلقائياً: $($_.Exception.Message)"
        }
    }

    Write-Banner "الخطوة 4 من 4 — ضبط TCP الآمن + خيارات متقدمة (اختيارية)"

    # --- إعدادات آمنة ومبرّرة فقط — يتم تغييرها فقط إن لم تكن مضبوطة بالفعل ---
    if ($backup.Congestion -and $backup.Congestion -ne 'cubic') {
        Invoke-Netsh -Arguments "interface tcp set global congestionprovider=cubic" -Description "ضبط Congestion Provider إلى cubic"
    } else {
        Write-Line -Level INFO -Message "Congestion Provider مضبوط بالفعل بشكل مناسب (cubic) — لا حاجة للتغيير."
    }

    if ($backup.AutoTuning -and $backup.AutoTuning -ne 'normal') {
        Invoke-Netsh -Arguments "interface tcp set global autotuninglevel=normal" -Description "ضبط TCP Auto-Tuning Level إلى normal"
    } else {
        Write-Line -Level INFO -Message "TCP Auto-Tuning Level مضبوط بالفعل (normal) — لا حاجة للتغيير."
    }

    if ($backup.Rss -and $backup.Rss -ne 'enabled') {
        Invoke-Netsh -Arguments "interface tcp set global rss=enabled" -Description "تفعيل Receive-Side Scaling (توزيع معالجة الشبكة على أنوية المعالج)"
    } else {
        Write-Line -Level INFO -Message "Receive-Side Scaling مفعّل بالفعل — لا حاجة للتغيير."
    }

    if ($backup.Heuristics -eq 'enabled') {
        Invoke-Netsh -Arguments "interface tcp set heuristics disabled" -Description "تعطيل TCP Window-Scaling Heuristics (قد يتعارض مع Auto-Tuning)"
    } else {
        Write-Line -Level INFO -Message "TCP Heuristics معطّل بالفعل (الوضع الافتراضي بويندوز 8.1 وما فوق) — لا حاجة للتغيير."
    }

    Write-Line -Level INFO -Message "تم تجاهل تعديل DCA/NetDMA عمداً — هذه الإعدادات قديمة/غير فعّالة على ويندوز 10/11 الحديث."
    Write-Line -Level INFO -Message "تم تجاهل فرض تفعيل ECN تلقائياً — قد يسبب مشاكل توافق مع بعض الراوترات الرخيصة."

    Write-Host ""
    Write-Line -Level TITLE -Message "تخصيصات متقدمة اختيارية (موصى بقراءة التحذير قبل الموافقة):"

    if (Confirm-Action "تعطيل تحديد سرعة الشبكة الخاص بـ MMCSS (NetworkThrottlingIndex) — مفيد فقط عند تشغيل برامج وسائط/بث أثناء استخدام الشبكة بكثافة، يتطلب إعادة تشغيل" $false) {
        try {
            $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
            if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
            # القيمة -1 تساوي 0xFFFFFFFF كنمط بتات 32-bit (يُمنع تمرير 0xffffffff مباشرة لأنها تتجاوز Int32)
            New-ItemProperty -Path $path -Name "NetworkThrottlingIndex" -Value (-1) -PropertyType DWord -Force | Out-Null
            Write-Line -Level OK -Message "تم تعطيل NetworkThrottlingIndex (يتطلب إعادة تشغيل للتفعيل الكامل)."
        } catch {
            Write-Line -Level ERR -Message "فشل تعديل NetworkThrottlingIndex: $($_.Exception.Message)"
        }
    }

    if (Confirm-Action "تعطيل خوارزمية Nagle لهذا الكرت (تجريبي/مثير للجدل — يفيد فقط تطبيقات TCP الحساسة للزمن، لا تأثير على ألعاب UDP، يتطلب إعادة تشغيل)" $false) {
        try {
            $naglePath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($adapter.InterfaceGuid)"
            if (Test-Path $naglePath) {
                New-ItemProperty -Path $naglePath -Name "TCPNoDelay" -Value 1 -PropertyType DWord -Force | Out-Null
                New-ItemProperty -Path $naglePath -Name "TcpAckFrequency" -Value 1 -PropertyType DWord -Force | Out-Null
                Write-Line -Level OK -Message "تم تعطيل Nagle لهذا الكرت (يتطلب إعادة تشغيل)."
            } else {
                Write-Line -Level WARN -Message "تعذّر تحديد مسار الريجستري الخاص بهذا الكرت — تم تجاهل هذه الخطوة."
            }
        } catch {
            Write-Line -Level ERR -Message "فشل تعديل إعدادات Nagle: $($_.Exception.Message)"
        }
    }

    if (Confirm-Action "تعطيل ميزات توفير الطاقة لكرت الشبكة (تمنع تجمّد/تأخر مؤقت عند الخمول، مفيد للأجهزة المحمولة بشكل خاص)" $false) {
        try {
            Set-NetAdapterPowerManagement -Name $adapter.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction Stop
            Write-Line -Level OK -Message "تم تعطيل إيقاف الكرت التلقائي لتوفير الطاقة."
        } catch {
            Write-Line -Level WARN -Message "هذا الكرت لا يدعم تعديل إعدادات توفير الطاقة عبر PowerShell (طبيعي لبعض الكروت)."
        }
        try {
            $eee = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Energy Efficient|Green Ethernet' }
            if ($eee) {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $eee.DisplayName -DisplayValue "Disabled" -ErrorAction Stop
                Write-Line -Level OK -Message "تم تعطيل Energy Efficient Ethernet."
            }
        } catch { }
    }

    Write-Host ""
    Write-Banner "تم الانتهاء"
    Write-Line -Level OK -Message "السجلّ الكامل محفوظ في: $Script:LogFolder"
    Write-Line -Level WARN -Message "إن فعّلت أي خيار يتطلب 'إعادة تشغيل' أعلاه، يُفضّل إعادة تشغيل الجهاز الآن لتطبيقه فعلياً."
    Write-Line -Level INFO -Message "ملاحظة واقعية: هذه التعديلات تحسّن الاستجابة/الكمون (latency) في حالات محدّدة، ولا تضمن"
    Write-Line -Level INFO -Message "زيادة 'سرعة الإنترنت' الفعلية إن كان عنق الزجاجة عند مزوّد الخدمة نفسه لا عند نظامك."
}

# -----------------------------------------------------------------------------
# 11) الاسترجاع (Option 2) — يستخدم النسخة الاحتياطية الحقيقية إن وُجدت
# -----------------------------------------------------------------------------
function Invoke-Rollback {
    Write-Banner "استرجاع الإعدادات"

    if (-not (Test-Path $Script:BackupFile)) {
        Write-Line -Level WARN -Message "لا توجد نسخة احتياطية محفوظة من تشغيل سابق لهذا السكربت."
        if (-not (Confirm-Action "هل تريد استرجاع 'إعدادات ويندوز الافتراضية العامة' بدلاً من ذلك؟ (تقريبية، ليست بالضرورة إعداداتك الأصلية)" $false)) { return }
        Restore-GenericDefaults
        return
    }

    $b = Get-Content $Script:BackupFile -Raw | ConvertFrom-Json
    Write-Line -Level INFO -Message "تم العثور على نسخة محفوظة بتاريخ: $($b.Timestamp)"
    Write-Line -Level INFO -Message "الواجهة: $($b.AdapterName)"
    if (-not (Confirm-Action "هل تريد استرجاع هذه الإعدادات بالضبط؟" $true)) { return }

    if (@($b.DnsV4).Count -gt 0 -or @($b.DnsV6).Count -gt 0) {
        try {
            Set-DnsClientServerAddress -InterfaceAlias $b.AdapterName -ServerAddresses (@($b.DnsV4) + @($b.DnsV6)) -ErrorAction Stop
            Write-Line -Level OK -Message "تمت استعادة عناوين DNS الأصلية."
        } catch { Write-Line -Level ERR -Message "فشل استرجاع DNS: $($_.Exception.Message)" }
    } else {
        try {
            Set-DnsClientServerAddress -InterfaceAlias $b.AdapterName -ResetServerAddresses -ErrorAction Stop
            Write-Line -Level OK -Message "تمت إعادة DNS إلى الوضع التلقائي (DHCP) كما كان."
        } catch { Write-Line -Level ERR -Message "فشل إعادة ضبط DNS: $($_.Exception.Message)" }
    }

    if ($b.Congestion) { Invoke-Netsh -Arguments "interface tcp set global congestionprovider=$($b.Congestion)" -Description "استرجاع Congestion Provider إلى ($($b.Congestion))" }
    if ($b.AutoTuning) { Invoke-Netsh -Arguments "interface tcp set global autotuninglevel=$($b.AutoTuning)" -Description "استرجاع Auto-Tuning Level إلى ($($b.AutoTuning))" }
    if ($b.Rss)        { Invoke-Netsh -Arguments "interface tcp set global rss=$($b.Rss)" -Description "استرجاع Receive-Side Scaling إلى ($($b.Rss))" }
    if ($b.Heuristics) { Invoke-Netsh -Arguments "interface tcp set heuristics $($b.Heuristics)" -Description "استرجاع TCP Heuristics إلى ($($b.Heuristics))" }

    $regThrottlePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if (-not $b.ThrottleIndexWasSet) {
        Remove-ItemProperty -Path $regThrottlePath -Name "NetworkThrottlingIndex" -ErrorAction SilentlyContinue
    } elseif ($null -ne $b.ThrottleIndexValue) {
        New-ItemProperty -Path $regThrottlePath -Name "NetworkThrottlingIndex" -Value $b.ThrottleIndexValue -PropertyType DWord -Force | Out-Null
    }

    $naglePath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($b.AdapterGuid)"
    if (Test-Path $naglePath) {
        if (-not $b.NagleKeysExisted) {
            Remove-ItemProperty -Path $naglePath -Name "TCPNoDelay" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $naglePath -Name "TcpAckFrequency" -ErrorAction SilentlyContinue
        } else {
            if ($null -ne $b.TCPNoDelayValue) { New-ItemProperty -Path $naglePath -Name "TCPNoDelay" -Value $b.TCPNoDelayValue -PropertyType DWord -Force | Out-Null }
            if ($null -ne $b.TcpAckFreqValue) { New-ItemProperty -Path $naglePath -Name "TcpAckFrequency" -Value $b.TcpAckFreqValue -PropertyType DWord -Force | Out-Null }
        }
    }

    Write-Line -Level OK -Message "تم الاسترجاع إلى الحالة المحفوظة بدقة. يُفضّل إعادة التشغيل لتطبيق كل القيم بشكل كامل."
}

function Restore-GenericDefaults {
    Write-Line -Level WARN -Message "جاري استرجاع إعدادات ويندوز الافتراضية العامة (وليست إعداداتك الشخصية)..."
    $adapter = Select-NetworkAdapter
    if ($adapter) {
        Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses -ErrorAction SilentlyContinue
    }
    Invoke-Netsh -Arguments "interface tcp set global congestionprovider=default" -Description "Congestion Provider -> default"
    Invoke-Netsh -Arguments "interface tcp set global autotuninglevel=normal" -Description "Auto-Tuning Level -> normal"
    Invoke-Netsh -Arguments "interface tcp set global rss=enabled" -Description "RSS -> enabled"
    Invoke-Netsh -Arguments "interface tcp set heuristics enabled" -Description "Heuristics -> enabled"
    $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    Remove-ItemProperty -Path $path -Name "NetworkThrottlingIndex" -ErrorAction SilentlyContinue
    Write-Line -Level OK -Message "تم استرجاع الإعدادات العامة."
}

# -----------------------------------------------------------------------------
# 12) إصلاح/إعادة ضبط طبقة الشبكة بالكامل (Option 3) — منفصل عمداً عن التحسين
#     لأنه إجراء "إصلاح أعطال" لا "تحسين سرعة"، وله أثر جانبي (يحتاج إعادة تشغيل
#     وقد يؤثر على VPN/برامج أمنية مؤقتاً حتى إعادة التشغيل).
# -----------------------------------------------------------------------------
function Invoke-StackRepair {
    Write-Banner "إصلاح وإعادة ضبط طبقة الشبكة بالكامل"
    Write-Line -Level WARN -Message "هذا إجراء إصلاح أعطال (Corruption Repair) لا تحسين سرعة. يحتاج إعادة تشغيل،"
    Write-Line -Level WARN -Message "وقد يتطلب إعادة ضبط أي VPN/برنامج أمني بعد إعادة التشغيل."
    if (-not (Confirm-Action "هل تريد الاستمرار؟" $false)) { return }

    Write-Line -Level INFO -Message "تفريغ ذاكرة DNS المؤقتة..." -NoNewline
    ipconfig /flushdns | Out-Null
    Write-Line -Level OK -Message " تم."

    Invoke-Netsh -Arguments "int ip reset" -Description "إعادة ضبط بروتوكول IP"
    Invoke-Netsh -Arguments "winsock reset" -Description "إعادة ضبط Winsock"

    Write-Line -Level WARN -Message "يجب إعادة تشغيل الجهاز الآن ليصبح الإصلاح فعّالاً بالكامل."
}

# -----------------------------------------------------------------------------
# 13) القائمة الرئيسية
# -----------------------------------------------------------------------------
Write-Banner "FTTH NETWORK TUNER — REALISTIC EDITION (v3.0 / 2026)"
Write-Host " [1] تشغيل التحسين (قياس DNS حقيقي + ضبط TCP آمن + تخصيصات اختيارية)" -ForegroundColor White
Write-Host " [2] استرجاع آخر نسخة محفوظة من إعداداتك (Rollback)" -ForegroundColor Yellow
Write-Host " [3] إصلاح/إعادة ضبط طبقة الشبكة بالكامل (لمشاكل الاتصال، لا للسرعة)" -ForegroundColor DarkYellow
Write-Host " [4] خروج" -ForegroundColor Red
Write-Host ("=" * 75) -ForegroundColor Cyan

$choice = Read-Host "اختر رقماً (1-4)"
switch ($choice) {
    '1' { Invoke-Optimization }
    '2' { Invoke-Rollback }
    '3' { Invoke-StackRepair }
    default { exit }
}

Read-Host "`nانتهى التنفيذ. اضغط Enter للخروج"