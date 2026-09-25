@echo off
setlocal
chcp 65001 >nul 2>&1
set "SM_ARGS=%*"
title SysMon One v7.1.1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$s=Get-Content -Raw -LiteralPath '%~f0'; $m='#__POWERSHELL_BELOW__'; $i=$s.LastIndexOf($m); if($i -lt 0){exit 2}; $code=$s.Substring($i+$m.Length); & ([ScriptBlock]::Create($code))"
exit /b %errorlevel%
#__POWERSHELL_BELOW__
$ErrorActionPreference='SilentlyContinue'
[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false)
$Host.UI.RawUI.WindowTitle='SysMon One v7.1.1'
$Version='7.1.1'
$rawArgs=$env:SM_ARGS
$Lang=if($rawArgs -match '--lang\s+en'){'en'}elseif($rawArgs -match '--lang\s+zh'){'zh'}elseif((Get-Culture).Name -like 'zh*'){'zh'}else{'en'}
$Interval=2.0
if($rawArgs -match '--interval\s+([0-9.]+)'){ $Interval=[Math]::Min(10,[Math]::Max(.7,[double]$Matches[1])) }
$Plain=$rawArgs -match '--plain'

function T([string]$zh,[string]$en){ if($Lang -eq 'zh'){$zh}else{$en} }
function FmtBytes([double]$n){
  if($n -ge 1TB){'{0:N1}TB' -f ($n/1TB)} elseif($n -ge 1GB){'{0:N1}GB' -f ($n/1GB)} elseif($n -ge 1MB){'{0:N1}MB' -f ($n/1MB)} elseif($n -ge 1KB){'{0:N1}KB' -f ($n/1KB)} else {'{0:N0}B' -f $n}
}
function Rate([double]$n){ if($n -le 0){'0B/s'}else{"$(FmtBytes $n)/s"} }
function Bar([double]$p,[int]$w=16){ $p=[Math]::Max(0,[Math]::Min(100,$p)); $n=[Math]::Round($w*$p/100); ('█'*$n)+('░'*($w-$n)) }
function Clip([string]$s,[int]$n){ if(!$s){return ''}; if($s.Length -le $n){$s}else{$s.Substring(0,[Math]::Max(1,$n-1))+'…'} }
function Pause-Line(){ [void](Read-Host (T '按回车继续' 'Press Enter to continue')) }

# ---------- static identity ----------
$CS=Get-CimInstance Win32_ComputerSystem
$CPUInfo=Get-CimInstance Win32_Processor | Select-Object -First 1
$OS=Get-CimInstance Win32_OperatingSystem
$GPUs=@(Get-CimInstance Win32_VideoController | Where-Object {$_.Name})
$Logical=[int]($CS.NumberOfLogicalProcessors)
if($Logical -le 0){$Logical=[Environment]::ProcessorCount}
$TotalRAM=[double]$CS.TotalPhysicalMemory
$Boot=if($OS.LastBootUpTime -is [datetime]){[datetime]$OS.LastBootUpTime}else{[Management.ManagementDateTimeConverter]::ToDateTime([string]$OS.LastBootUpTime)}
$Drive=(Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'")
$GPUName=if($GPUs.Count){($GPUs|ForEach-Object{$_.Name}) -join ' + '}else{'N/A'}

# ---------- sensors ----------
function Get-Fans {
  $out=@()
  foreach($ns in @('root\LibreHardwareMonitor','root\OpenHardwareMonitor')){
    try{
      $s=Get-CimInstance -Namespace $ns -ClassName Sensor -ErrorAction Stop | Where-Object {$_.SensorType -eq 'Fan' -and $_.Value -ne $null}
      foreach($x in $s){$out += [pscustomobject]@{Name=$x.Name; RPM=[double]$x.Value; Source=($ns.Split('\')[-1])}}
      if($out.Count){return $out}
    }catch{}
  }
  try{
    $f=Get-CimInstance Win32_Fan
    foreach($x in $f){
      $rpm=0
      if($x.DesiredSpeed){$rpm=[double]$x.DesiredSpeed}
      elseif($x.VariableSpeed -and $x.Speed){$rpm=[double]$x.Speed}
      if($rpm -gt 0){$out += [pscustomobject]@{Name=$(if($x.Name){$x.Name}else{'Fan'}); RPM=$rpm; Source='Win32_Fan'}}
    }
  }catch{}
  return $out
}
function Get-Temperatures {
  $out=@()
  foreach($ns in @('root\LibreHardwareMonitor','root\OpenHardwareMonitor')){
    try{
      $s=Get-CimInstance -Namespace $ns -ClassName Sensor -ErrorAction Stop | Where-Object {$_.SensorType -eq 'Temperature' -and $_.Value -ne $null}
      foreach($x in $s){$out += [pscustomobject]@{Name=$x.Name; C=[double]$x.Value}}
      if($out.Count){return $out}
    }catch{}
  }
  try{
    $z=Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature
    foreach($x in $z){ if($x.CurrentTemperature){$out += [pscustomobject]@{Name=$x.InstanceName; C=([double]$x.CurrentTemperature/10-273.15)}} }
  }catch{}
  return $out
}

# ---------- process data ----------
function Get-PerfProcesses {
  $rows=@()
  try{
    $pp=Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | Where-Object {$_.IDProcess -gt 0 -and $_.Name -notin @('_Total','Idle')}
    foreach($p in $pp){
      $cpu=([double]$p.PercentProcessorTime)/[Math]::Max(1,$Logical)
      $rows += [pscustomobject]@{PID=[int]$p.IDProcess; Name=[string]$p.Name; CPU=[Math]::Min(999,$cpu); RAM=[double]$p.WorkingSetPrivate}
    }
  }catch{}
  return $rows
}
function Get-ProcessRows {
  $perf=@{}; foreach($p in (Get-PerfProcesses)){$perf[$p.PID]=$p}
  $rows=@()
  foreach($p in (Get-CimInstance Win32_Process)){
    $q=$perf[[int]$p.ProcessId]
    $rows += [pscustomobject]@{
      PID=[int]$p.ProcessId; PPID=[int]$p.ParentProcessId; Name=[string]$p.Name;
      CPU=if($q){[double]$q.CPU}else{0}; RAM=if($q){[double]$q.RAM}else{[double]$p.WorkingSetSize};
      Command=if($p.CommandLine){[string]$p.CommandLine}else{[string]$p.ExecutablePath}
    }
  }
  return $rows
}
$HardProtected=@('system','registry','memory compression','secure system','smss.exe','csrss.exe','wininit.exe','services.exe','lsass.exe','winlogon.exe','svchost.exe','dwm.exe','fontdrvhost.exe')
function Is-Protected($r){ if($r.PID -le 4){return $true}; return ($HardProtected -contains $r.Name.ToLower()) }
function ProcLine($r,[string]$prefix=''){ '{0}{1,6}  CPU {2,6:N1}%  RAM {3,8}  {4}' -f $prefix,$r.PID,$r.CPU,(FmtBytes $r.RAM),(Clip $r.Name 25) }

function Show-ProcessTree {
  $rows=@(Get-ProcessRows); $by=@{}; $ch=@{}
  foreach($r in $rows){$by[$r.PID]=$r; if(!$ch.ContainsKey($r.PPID)){$ch[$r.PPID]=New-Object System.Collections.ArrayList}; [void]$ch[$r.PPID].Add($r)}
  $roots=@($rows|Where-Object{-not $by.ContainsKey($_.PPID)}|Sort-Object CPU -Descending)
  Write-Host "`n  $(T '进程树' 'Process tree')" -ForegroundColor Cyan
  $script:TreeCount=0
  function Walk($r,[string]$prefix,[bool]$last,[int]$depth){
    if($script:TreeCount -ge 90 -or $depth -gt 7){return}
    $branch=if($depth -eq 0){''}elseif($last){'└─ '}else{'├─ '}
    Write-Host ('  '+(ProcLine $r ($prefix+$branch)))
    $script:TreeCount++
    $kids=@(); if($ch.ContainsKey($r.PID)){$kids=@($ch[$r.PID]|Sort-Object CPU -Descending)}
    $np=if($depth -eq 0){''}elseif($last){$prefix+'   '}else{$prefix+'│  '}
    for($i=0;$i -lt $kids.Count;$i++){Walk $kids[$i] $np ($i -eq $kids.Count-1) ($depth+1)}
  }
  for($i=0;$i -lt $roots.Count;$i++){if($script:TreeCount -ge 90){break}; Walk $roots[$i] '' ($i -eq $roots.Count-1) 0}
  if($script:TreeCount -ge 90){Write-Host '  … first 90 rows / 仅显示前90行' -ForegroundColor DarkGray}
}
function Search-Processes([string]$q=''){
  if(!$q){$q=Read-Host (T '搜索进程名称/命令' 'Search process name/command')}
  if(!$q){return}
  $rows=@(Get-ProcessRows|Where-Object{$_.Name -like "*$q*" -or $_.Command -like "*$q*"}|Sort-Object CPU -Descending)
  Write-Host "`n  $(T '搜索结果' 'Search results'): $q ($($rows.Count))" -ForegroundColor Cyan
  foreach($r in ($rows | Select-Object -First 30)){Write-Host ('  '+(ProcLine $r))}
  if($rows.Count -gt 30){Write-Host "  … +$($rows.Count-30)" -ForegroundColor DarkGray}
}
function Terminate-PID {
  $raw=Read-Host (T '输入要结束的 PID' 'PID to terminate')
  if($raw -notmatch '^\d+$'){return}; $pidn=[int]$raw
  $r=Get-ProcessRows|Where-Object{$_.PID -eq $pidn}|Select-Object -First 1
  if(!$r){Write-Host (T '找不到该 PID。' 'PID not found.') -ForegroundColor Yellow; return}
  Write-Host ('  '+(ProcLine $r)) -ForegroundColor Yellow
  if(Is-Protected $r){Write-Host (T '受保护的系统关键进程，拒绝结束。' 'Protected critical process; refused.') -ForegroundColor Red; return}
  $p=Get-Process -Id $pidn -ErrorAction SilentlyContinue
  if(!$p){return}
  $yes=Read-Host (T '先请求应用正常关闭？输入 y' 'Request graceful close first? type y')
  if($yes -notin @('y','Y','yes','YES')){return}
  $closed=$false
  try{ if($p.MainWindowHandle -ne 0){$closed=$p.CloseMainWindow(); Start-Sleep -Milliseconds 1200} }catch{}
  $p=Get-Process -Id $pidn -ErrorAction SilentlyContinue
  if(!$p){Write-Host (T '✓ 已正常关闭' '✓ Closed normally') -ForegroundColor Green; return}
  Write-Host (T '进程仍在运行。强制结束可能丢失未保存数据。' 'Still running. Force termination may lose unsaved data.') -ForegroundColor Yellow
  $force=Read-Host (T '强制 Kill？再次输入 y' 'Force kill? type y again')
  if($force -in @('y','Y','yes','YES')){try{Stop-Process -Id $pidn -Force -ErrorAction Stop; Write-Host (T '✓ 已强制结束' '✓ Force-killed') -ForegroundColor Red}catch{Write-Host $_.Exception.Message -ForegroundColor Red}}
}
function Process-Center {
  while($true){
    Clear-Host; Write-Host "⚙ SysMon One · $(T '进程中心' 'Process Center')" -ForegroundColor Cyan
    Write-Host (T '[1] 进程树  [2] CPU/RAM Top20  [3] 搜索  [4] Kill PID  [0] 返回' '[1] Process tree  [2] CPU/RAM Top20  [3] Search  [4] Kill PID  [0] Back')
    $a=Read-Host (T '选择' 'Choose')
    if($a -eq '0' -or !$a){return}
    if($a -eq '1'){Show-ProcessTree; Pause-Line}
    elseif($a -eq '2'){
      $r=@(Get-ProcessRows)
      Write-Host "`n  CPU Top20" -ForegroundColor Cyan; foreach($x in ($r | Sort-Object CPU -Descending | Select-Object -First 20)){Write-Host ('  '+(ProcLine $x))}
      Write-Host "`n  RAM Top20" -ForegroundColor Cyan; foreach($x in ($r | Sort-Object RAM -Descending | Select-Object -First 20)){Write-Host ('  '+(ProcLine $x))}; Pause-Line
    }
    elseif($a -eq '3'){Search-Processes; Pause-Line}
    elseif($a -eq '4'){Terminate-PID; Pause-Line}
  }
}

# ---------- Storage Doctor ----------
function Get-DirSize([string]$p){
  if(!(Test-Path -LiteralPath $p)){return 0}
  try{ return [double]((Get-ChildItem -LiteralPath $p -Force -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) }catch{return 0}
}
function Storage-Doctor {
  Clear-Host; Write-Host "⚡ SysMon One v$Version · $(T '磁盘医生' 'Storage Doctor')" -ForegroundColor Cyan
  $ld=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"; $used=[double]$ld.Size-[double]$ld.FreeSpace; $pct=100*$used/[double]$ld.Size
  Write-Host ("  {0} {1}  {2:N1}%  {3}/{4}" -f (T '系统盘' 'System drive'),(Bar $pct 24),$pct,(FmtBytes $used),(FmtBytes $ld.Size))
  $safe=@(
    @{N='User Temp';P=$env:TEMP},
    @{N='CrashDumps';P="$env:LOCALAPPDATA\CrashDumps"},
    @{N='D3D Shader Cache';P="$env:LOCALAPPDATA\D3DSCache"},
    @{N='pip Cache';P="$env:LOCALAPPDATA\pip\Cache"},
    @{N='npm Cache';P="$env:LOCALAPPDATA\npm-cache"}
  )
  $sum=0; Write-Host "`n  ✓ $(T '绿色：可重建缓存' 'Green: reconstructible caches')" -ForegroundColor Green
  foreach($x in $safe){$sz=Get-DirSize $x.P; if($sz -gt 0){$sum+=$sz; Write-Host ('    ✓ {0,-20} {1,9}  {2}' -f $x.N,(FmtBytes $sz),$x.P)}}
  Write-Host "    $(T '可安全释放' 'Safe reclaim'): $(FmtBytes $sum)" -ForegroundColor Green
  Write-Host "`n  ⚠ $(T '黄色：只检查，不自动删除' 'Yellow: review only, never auto-delete')" -ForegroundColor Yellow
  $review=@(
    @{N='Downloads';P="$env:USERPROFILE\Downloads"},
    @{N='Docker';P="$env:LOCALAPPDATA\Docker"},
    @{N='Ollama Models';P="$env:USERPROFILE\.ollama\models"},
    @{N='HuggingFace';P="$env:USERPROFILE\.cache\huggingface"},
    @{N='NuGet packages';P="$env:USERPROFILE\.nuget\packages"}
  )
  foreach($x in $review){$sz=Get-DirSize $x.P; if($sz -gt 0){Write-Host ('    ⚠ {0,-20} {1,9}  {2}' -f $x.N,(FmtBytes $sz),$x.P)}}
  Write-Host "`n  ✗ $(T '受保护：桌面、文档、图片、OneDrive、个人项目不会自动删除。' 'Protected: Desktop, Documents, Pictures, OneDrive and personal projects are never auto-deleted.')" -ForegroundColor Red
  if($sum -le 0){Pause-Line; return}
  $a=Read-Host (T '清理全部绿色项？输入 y；其他键返回' 'Clean all green items? type y; anything else returns')
  if($a -notin @('y','Y','yes','YES')){return}
  foreach($x in $safe){
    if(Test-Path -LiteralPath $x.P){Get-ChildItem -LiteralPath $x.P -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue}
  }
  Write-Host (T '✓ 清理完成。占用中的文件会自动跳过。' '✓ Cleanup complete. Files in use were skipped.') -ForegroundColor Green; Pause-Line
}

# ---------- live snapshot ----------
$Peak=@{CPU=0;RAM=0;GPU=0;Disk=0;Net=0}
$FanCache=@(); $FanTS=[datetime]::MinValue; $TopCache=@(); $TopTS=[datetime]::MinValue
function Live-Snapshot {
  $proc=@(Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor); $total=$proc|Where-Object{$_.Name -eq '_Total'}|Select-Object -First 1
  $cores=@($proc|Where-Object{$_.Name -ne '_Total'}|Sort-Object {[int]($_.Name -replace '\D','')})
  $osnow=Get-CimInstance Win32_OperatingSystem; $free=[double]$osnow.FreePhysicalMemory*1KB; $used=$TotalRAM-$free; $memp=if($TotalRAM){100*$used/$TotalRAM}else{0}
  $pf=@(Get-CimInstance Win32_PageFileUsage); $pfa=[double](($pf|Measure-Object AllocatedBaseSize -Sum).Sum)*1MB; $pfu=[double](($pf|Measure-Object CurrentUsage -Sum).Sum)*1MB
  $disk=Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk|Where-Object{$_.Name -eq '_Total'}|Select-Object -First 1
  $net=@(Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface); $rx=[double](($net|Measure-Object BytesReceivedPersec -Sum).Sum); $tx=[double](($net|Measure-Object BytesSentPersec -Sum).Sum)
  $gpu=0; try{$ge=Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine; if($ge){$gpu=[double](($ge|Measure-Object UtilizationPercentage -Maximum).Maximum)}}catch{}
  if(((Get-Date)-$script:TopTS).TotalSeconds -ge 4){$script:TopCache=@(Get-PerfProcesses); $script:TopTS=Get-Date}
  if(((Get-Date)-$script:FanTS).TotalSeconds -ge 5){$script:FanCache=@(Get-Fans); $script:FanTS=Get-Date}
  return [pscustomobject]@{CPU=[double]$total.PercentProcessorTime; Cores=$cores; Used=$used; Free=$free; MemPct=$memp; PFUsed=$pfu; PFAlloc=$pfa; Read=[double]$disk.DiskReadBytesPersec; Write=[double]$disk.DiskWriteBytesPersec; RX=$rx; TX=$tx; GPU=$gpu; Fans=$script:FanCache; Procs=$script:TopCache}
}
function Insight($d){
  $topMem=$d.Procs|Sort-Object RAM -Descending|Select-Object -First 1; $topCpu=$d.Procs|Sort-Object CPU -Descending|Select-Object -First 1
  if($d.MemPct -ge 94 -and $d.PFUsed -ge 1GB){return (T "内存非常紧张，优先检查 $($topMem.Name)（$(FmtBytes $topMem.RAM)）。" "Memory is very tight. Inspect $($topMem.Name) ($(FmtBytes $topMem.RAM)) first.")}
  if($d.CPU -ge 92){return (T "CPU 接近满载，当前第一名 $($topCpu.Name) $([Math]::Round($topCpu.CPU))%。先确认它是不是你正在做的事。" "CPU is near full load. Top process: $($topCpu.Name) $([Math]::Round($topCpu.CPU))%. Confirm it is expected work.")}
  if($d.Write -ge 250MB){return (T "磁盘持续高速写入 $(Rate $d.Write)。如果不是拷贝/下载/编译，值得检查。" "Disk writes are high at $(Rate $d.Write). Inspect if you are not copying/downloading/building.")}
  if($d.PFUsed -ge 4GB -and $d.MemPct -lt 85){return (T "分页文件已用 $(FmtBytes $d.PFUsed)，但当前内存仍有余量。不要只为了数字好看去 Kill。" "Pagefile uses $(FmtBytes $d.PFUsed), but RAM still has headroom. Do not kill apps just to prettify a number.")}
  return (T '当前没有需要立刻处理的核心异常。' 'No core issue needs immediate action.')
}
function Render($d){
  $upt=(Get-Date)-$Boot; $diskFree=[double]$Drive.FreeSpace; $diskSize=[double]$Drive.Size
  $Peak.CPU=[Math]::Max($Peak.CPU,$d.CPU); $Peak.RAM=[Math]::Max($Peak.RAM,$d.MemPct); $Peak.GPU=[Math]::Max($Peak.GPU,$d.GPU); $Peak.Disk=[Math]::Max($Peak.Disk,$d.Read+$d.Write); $Peak.Net=[Math]::Max($Peak.Net,$d.RX+$d.TX)
  if(!$Plain){Clear-Host}
  Write-Host "⚡ SysMon One v$Version  · Windows · no install · local only     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
  Write-Host "  $($CS.Manufacturer) $($CS.Model) · $($CPUInfo.Name) · CPU $Logical logical · RAM $(FmtBytes $TotalRAM)"
  Write-Host "  $($OS.Caption) · $($OS.Version) build $($OS.BuildNumber) · $($OS.OSArchitecture) · uptime $([int]$upt.TotalDays)d $($upt.Hours)h $($upt.Minutes)m"
  Write-Host "  GPU: $(Clip $GPUName 100)" -ForegroundColor DarkGray
  Write-Host "  ✦ $(T '核心提示' 'Core insight'): $(Insight $d)" -ForegroundColor Magenta
  Write-Host ('  '+'─'*76) -ForegroundColor DarkGray
  Write-Host ("  CPU    {0} {1,5:N1}%  $(T '总占用' 'total')" -f (Bar $d.CPU 18),$d.CPU) -ForegroundColor Green
  $i=0; foreach($c in ($d.Cores | Select-Object -First 16)){$u=[double]$c.PercentProcessorTime; Write-Host ("      C{0,-2} {1} {2,6:N1}%" -f $i,(Bar $u 12),$u); $i++}
  Write-Host ("  GPU    {0} {1,5:N1}%  $(T '引擎峰值' 'engine peak')" -f (Bar $d.GPU 16),$d.GPU)
  Write-Host ("  RAM    {0} {1,5:N1}%  {2}/{3}  $(T '可用' 'free') {4}" -f (Bar $d.MemPct 16),$d.MemPct,(FmtBytes $d.Used),(FmtBytes $TotalRAM),(FmtBytes $d.Free))
  $pfp=if($d.PFAlloc){100*$d.PFUsed/$d.PFAlloc}else{0}; Write-Host ("  Page   {0} {1,5:N1}%  {2}/{3}" -f (Bar $pfp 16),$pfp,(FmtBytes $d.PFUsed),(FmtBytes $d.PFAlloc))
  Write-Host ("  Disk   R {0,11}  W {1,11}     Network ↓ {2,11}  ↑ {3,11}" -f (Rate $d.Read),(Rate $d.Write),(Rate $d.RX),(Rate $d.TX))
  if($d.Fans.Count){Write-Host ('  Fans   '+(($d.Fans|ForEach-Object{"$($_.Name) $([Math]::Round($_.RPM)) RPM [$($_.Source)]"}) -join ' · ')) -ForegroundColor Cyan}else{Write-Host (T '  Fans   N/A（很多 OEM 不向 Windows 标准接口暴露风扇；若运行 LibreHardwareMonitor 会自动读取）' '  Fans   N/A (many OEMs do not expose fans through standard Windows APIs; LibreHardwareMonitor sensors are auto-detected if present)') -ForegroundColor DarkGray}
  Write-Host ('  '+'─'*76) -ForegroundColor DarkGray
  Write-Host "  $(T '本次峰值' 'Session peaks'): CPU $([Math]::Round($Peak.CPU))% · GPU $([Math]::Round($Peak.GPU))% · RAM $([Math]::Round($Peak.RAM))% · Disk $(Rate $Peak.Disk) · Net $(Rate $Peak.Net)" -ForegroundColor Cyan
  Write-Host "  TOP5 CPU" -ForegroundColor Cyan; $n=1; foreach($p in ($d.Procs | Sort-Object CPU -Descending | Select-Object -First 5)){Write-Host ('    {0}. {1,-24} {2,6:N1}%  {3,8}  PID {4}' -f $n,(Clip $p.Name 24),$p.CPU,(FmtBytes $p.RAM),$p.PID);$n++}
  Write-Host "  TOP5 RAM" -ForegroundColor Cyan; $n=1; foreach($p in ($d.Procs | Sort-Object RAM -Descending | Select-Object -First 5)){Write-Host ('    {0}. {1,-24} {2,8}  CPU {3,5:N1}%  PID {4}' -f $n,(Clip $p.Name 24),(FmtBytes $p.RAM),$p.CPU,$p.PID);$n++}
  Write-Host ('  '+'─'*76) -ForegroundColor DarkGray
  Write-Host (T '  C 磁盘医生 · P 进程中心 · / 搜索进程 · Q 退出' '  C Storage Doctor · P Process Center · / Search process · Q Quit') -ForegroundColor DarkGray
}

if($rawArgs -match '--doctor'){
  Write-Host "SysMon One v$Version · Windows Doctor" -ForegroundColor Cyan
  Write-Host "Model: $($CS.Manufacturer) $($CS.Model)"; Write-Host "CPU: $($CPUInfo.Name)"; Write-Host "RAM: $(FmtBytes $TotalRAM)"; Write-Host "GPU: $GPUName"; Write-Host "OS: $($OS.Caption) $($OS.Version) build $($OS.BuildNumber)"; $f=Get-Fans; Write-Host "Fans: $(if($f.Count){$f.Count}else{'N/A'})"; exit
}
if($rawArgs -match '--clean|--storage'){Storage-Doctor; exit}

while($true){
  $d=Live-Snapshot; Render $d
  $until=(Get-Date).AddSeconds($Interval)
  while((Get-Date) -lt $until){
    Start-Sleep -Milliseconds 80
    if([Console]::KeyAvailable){
      $k=[Console]::ReadKey($true).KeyChar.ToString().ToLower()
      if($k -eq 'q'){exit}
      if($k -eq 'c'){Storage-Doctor; break}
      if($k -eq 'p'){Process-Center; break}
      if($k -eq '/') {Clear-Host; Search-Processes; Pause-Line; break}
    }
  }
}
