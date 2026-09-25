#!/bin/bash
# SysMon One v7.1.1 — monitor + diagnosis + Storage Doctor / 单文件监控诊断清理
# SPDX-License-Identifier: MIT
# No sudo. No pip packages. No telemetry. Apple Silicon deep metrics when IOReport is available.
# 双击运行；Ctrl+C 退出。实时界面按 C 进入磁盘医生，P 进入进程中心，/ 搜索进程。参数：--lang zh|en --compact --expert --doctor --clean --scan --interval 2

cd "$(dirname "$0")" 2>/dev/null || true
export TERM="${TERM:-xterm-256color}"
export PYTHONIOENCODING=utf-8

PY=""
for p in /usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
  if [ -x "$p" ]; then PY="$p"; break; fi
done
if [ -z "$PY" ] && command -v python3 >/dev/null 2>&1; then PY="$(command -v python3)"; fi

# Storage Doctor also has a pure-Bash fallback, because telling a non-technical user to install
# Python before cleaning disk space would be a rather elegant way to recreate the problem.
WANT_CLEAN=0; WANT_SCAN=0
for arg in "$@"; do
  case "$arg" in --clean|--storage) WANT_CLEAN=1;; --scan) WANT_SCAN=1;; esac
done
fmt_kb() { /usr/bin/awk -v k="${1:-0}" 'BEGIN{b=k*1024;if(b>=1099511627776)printf "%.1fTB",b/1099511627776;else if(b>=1073741824)printf "%.1fGB",b/1073741824;else if(b>=1048576)printf "%.1fMB",b/1048576;else printf "%.0fKB",b/1024}'; }
du_kb() { [ -e "$1" ] && /usr/bin/du -sk "$1" 2>/dev/null | /usr/bin/awk 'NR==1{print $1+0}' || echo 0; }
clean_dir_contents() { [ -d "$1" ] || return 0; /bin/rm -rf "$1"/* "$1"/.[!.]* "$1"/..?* 2>/dev/null || true; }
basic_storage_doctor() {
  printf '\033]0;SysMon One — Storage Doctor\007'
  printf '\n  ⚡ SysMon One v7.1.1 · Storage Doctor / 磁盘医生\n'
  printf '  ------------------------------------------------------------------------\n'
  /bin/df -h "$HOME" 2>/dev/null | /usr/bin/awk 'NR==2{printf "  Disk / 磁盘: %s used / 已用 %s · free / 可用 %s · %s\n",$2,$3,$4,$5}'
  XCODE="$HOME/Library/Developer/Xcode/DerivedData"; BREW="$HOME/Library/Caches/Homebrew"
  PIP1="$HOME/Library/Caches/pip"; PIP2="$HOME/.cache/pip"; NPM="$HOME/.npm/_cacache"; GO="$HOME/Library/Caches/go-build"
  SAFE_TOTAL=0
  printf '\n  ✓ Green safe / 绿色安全项\n'
  for spec in "Xcode DerivedData|$XCODE" "Homebrew Cache|$BREW" "pip Cache|$PIP1" "pip Cache 2|$PIP2" "npm Cache|$NPM" "Go Build Cache|$GO"; do
    label=${spec%%|*}; path=${spec#*|}; kb=$(du_kb "$path");
    if [ "$kb" -gt 0 ] 2>/dev/null; then printf '    ✓ %-22s %8s  %s\n' "$label" "$(fmt_kb "$kb")" "$path"; SAFE_TOTAL=$((SAFE_TOTAL+kb)); fi
  done
  printf '    Safe reclaim / 可安全释放: %s\n' "$(fmt_kb "$SAFE_TOTAL")"
  printf '\n  ⚠ Yellow review only / 黄色人工检查（不会自动删）\n'
  for spec in "Trash / 废纸篓|$HOME/.Trash" "Downloads / 下载|$HOME/Downloads" "iPhone/iPad Backup|$HOME/Library/Application Support/MobileSync/Backup" "Xcode Archives|$HOME/Library/Developer/Xcode/Archives" "Docker Data|$HOME/Library/Containers/com.docker.docker/Data" "Ollama Models|$HOME/.ollama/models" "HuggingFace Models|$HOME/.cache/huggingface"; do
    label=${spec%%|*}; path=${spec#*|}; kb=$(du_kb "$path");
    [ "$kb" -gt 0 ] 2>/dev/null && printf '    ⚠ %-22s %8s  %s\n' "$label" "$(fmt_kb "$kb")" "$path"
  done
  printf '\n  ✗ Protected / 受保护: Desktop, Documents, Photos, iCloud, Mail, Messages, projects\n'
  printf '    These never enter automatic deletion. / 这些不会进入自动删除路径。\n'
  printf '  ------------------------------------------------------------------------\n'
  [ "$WANT_SCAN" -eq 1 ] && return 0
  [ "$WANT_CLEAN" -eq 1 ] || return 0
  [ "$SAFE_TOTAL" -le 0 ] 2>/dev/null && { printf '  Nothing green to clean. / 没有绿色安全项可清理。\n'; return 0; }
  printf '  Clean all green safe items (%s)? [y/N] / 清理全部绿色安全项？[y/N] ' "$(fmt_kb "$SAFE_TOTAL")"
  read ans
  case "$ans" in y|Y|yes|YES)
    if /usr/bin/pgrep -x Xcode >/dev/null 2>&1; then printf '  ! Xcode is running; DerivedData skipped. / Xcode 正在运行，跳过 DerivedData。\n'; else clean_dir_contents "$XCODE"; fi
    clean_dir_contents "$BREW"; clean_dir_contents "$PIP1"; clean_dir_contents "$PIP2"; clean_dir_contents "$NPM"; clean_dir_contents "$GO"
    printf '  ✓ Cleanup complete. / 清理完成。\n';;
    *) printf '  Cancelled. / 已取消。\n';;
  esac
}

if [ -z "$PY" ] && { [ "$WANT_CLEAN" -eq 1 ] || [ "$WANT_SCAN" -eq 1 ]; }; then
  basic_storage_doctor
  exit 0
fi

# A deliberately boring fallback: every Mac still gets a useful monitor even without Python 3.
# 深层 Apple Silicon 指标需要 Python 3；没有时自动退回系统自带命令，不让用户面对一扇空白窗口。
if [ -z "$PY" ]; then
  printf '\033]0;SysMon One — Smart Basic Mode\007'
  trap 'printf "\033[?25h\033[0m\n"; exit 0' INT TERM EXIT
  printf '\033[?25l'
  FB_OS="$(/usr/bin/sw_vers -productVersion 2>/dev/null) ($( /usr/bin/sw_vers -buildVersion 2>/dev/null))"
  FB_HW="$(/usr/sbin/system_profiler SPHardwareDataType 2>/dev/null | /usr/bin/awk -F: '/Model Name|Model Identifier|Chip|Total Number of Cores|Memory/ {gsub(/^[ \t]+|[ \t]+$/,"",$2); if($2!="") printf "%s%s",(n++?" · ":""),$2}')"
  while :; do
    printf '\033[H\033[2J'
    echo "  ⚡ SysMon One v7.1.1 · Smart Basic / 智能基础模式"
    echo "  $FB_HW"
    echo "  macOS $FB_OS"
    echo "  Python 3 not found: deep IOReport/DVFS is unavailable; core diagnosis still works."
    echo "  未找到 Python 3：深层 IOReport/DVFS 不可用，但核心诊断仍然工作。"
    echo "  ─────────────────────────────────────────────────────────────────────"
    TOPTXT="$(/usr/bin/top -l 1 -n 0 2>/dev/null)"
    echo "$TOPTXT" | /usr/bin/egrep 'CPU usage|PhysMem|Load Avg' | sed 's/^/  /'
    SWAP="$(/usr/sbin/sysctl -n vm.swapusage 2>/dev/null)"
    MP="$(/usr/bin/memory_pressure 2>/dev/null | /usr/bin/awk '/System memory pressure level:/ {print $NF; exit}')"
    [ -n "$SWAP" ] && echo "  Swap: $SWAP"
    case "$MP" in 4) echo "  🔴 Memory Pressure: CRITICAL / 严重";; 2) echo "  🟡 Memory Pressure: WARN / 警告";; 1) echo "  🟢 Memory Pressure: NORMAL / 正常";; *) echo "  Memory Pressure: --";; esac
    echo
    echo "  TOP 5 CPU"
    /bin/ps -Ao pid=,pcpu=,rss=,comm= 2>/dev/null | /usr/bin/sort -k2 -nr | /usr/bin/head -5 | sed 's/^/    /'
    echo "  TOP 5 MEMORY"
    /bin/ps -Ao pid=,pcpu=,rss=,comm= 2>/dev/null | /usr/bin/sort -k3 -nr | /usr/bin/head -5 | sed 's/^/    /'
    echo
    /usr/bin/pmset -g batt 2>/dev/null | sed 's/^/  /'
    echo "  ─────────────────────────────────────────────────────────────────────"
    echo "  Tip / 提示: swap 很大但 Memory Pressure=NORMAL 时，不要仅为了清零而强杀进程。"
    echo "  Ctrl+C to exit / 退出"
    sleep 2
  done
fi

exec "$PY" - "$@" <<'PYEOF'
# -*- coding: utf-8 -*-
"""SysMon One v7.1.1 — <100KB monitor + diagnosis + conservative Storage Doctor.

Goals:
- no sudo, no pip packages, no telemetry
- Apple Silicon deep metrics through IOReport when available
- dynamic CPU/GPU DVFS discovery; unknown hardware degrades to N/A instead of crashing
- bilingual Chinese/English UI
- true Swapins/Swapouts, separate disk/network directions
- history sparklines, process hot list, battery and thermal hints
- smart pressure index, core insight, session peaks and on-demand per-process swapped/compressed scan
- cached hardware identity: Mac model, model identifier, chip, CPU/GPU cores and macOS build
"""
import argparse
import ctypes
import json
import locale
import math
import os
import platform
import re
import signal
import shutil

# The Python program itself is delivered through a shell heredoc, so sys.stdin is
# not the interactive terminal. Open /dev/tty explicitly for hotkeys/prompts.
# This keeps the project single-file while making C/Q and Storage Doctor input work.
try:
    TTY_STREAM = open("/dev/tty", "r+", buffering=1)
except Exception:
    TTY_STREAM = None

def tty_input(prompt=""):
    if TTY_STREAM is None:
        return ""
    try:
        if prompt:
            TTY_STREAM.write(prompt); TTY_STREAM.flush()
        return TTY_STREAM.readline().rstrip("\r\n")
    except Exception:
        return ""
import struct
import subprocess
import sys
import threading
import time
import unicodedata
from collections import deque
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

VERSION = "7.1.0"
ESC = "\033["
RST = ESC + "0m"; B = ESC + "1m"; DIM = ESC + "2m"
RED = ESC + "91m"; GRN = ESC + "92m"; YEL = ESC + "93m"
BLU = ESC + "94m"; MAG = ESC + "95m"; CYN = ESC + "96m"; WHT = ESC + "97m"

# ----------------------------- CLI / i18n -----------------------------
def sh(cmd, timeout=8):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ""

def apple_locale():
    s = sh(["/usr/bin/defaults", "read", "-g", "AppleLocale"], 2).strip()
    return s or (locale.getlocale()[0] or "")

ap = argparse.ArgumentParser(add_help=False)
ap.add_argument("--lang", choices=("zh", "en"))
ap.add_argument("--compact", action="store_true")
ap.add_argument("--expert", action="store_true")
ap.add_argument("--doctor", action="store_true")
ap.add_argument("--clean", "--storage", dest="clean", action="store_true")
ap.add_argument("--scan", action="store_true")
ap.add_argument("--plain", action="store_true")
ap.add_argument("--interval", type=float, default=float(os.environ.get("SYSMON_INTERVAL", "2.0")))
ap.add_argument("--frames", type=int, default=int(os.environ.get("SYSMON_FRAMES", "0")))
ap.add_argument("--help", action="store_true")
A, _unknown = ap.parse_known_args()
A.interval = min(10.0, max(0.5, A.interval))
LANG = A.lang or os.environ.get("SYSMON_LANG") or ("zh" if apple_locale().lower().startswith("zh") else "en")

TXT = {
"zh": {
 "title":"SysMon One", "subtitle":"单文件 · 免 sudo · 本地运行", "cpu":"CPU", "total":"总占用", "cluster":"簇状态",
 "gpu":"GPU", "active":"活跃", "clock":"频率", "effective":"有效频率", "voltage":"电压", "temp":"温度",
 "power":"功耗", "memory":"内存", "available":"可用", "compressed":"压缩", "swap":"Swap", "free":"空闲",
 "swapin":"换入", "swapout":"换出", "disk":"磁盘", "read":"读", "write":"写", "network":"网络",
 "down":"下载", "up":"上传", "battery":"电池", "health":"健康", "cycles":"循环", "thermal":"热状态",
 "history":"60秒趋势", "process":"高负载进程", "pid":"PID", "load":"负载", "uptime":"运行",
 "collector":"采样", "source":"数据源", "exit":"Ctrl+C 退出", "na":"N/A", "idle":"空闲", "fanless":"无风扇",
 "doctor":"环境自检", "ok":"可用", "missing":"不可用", "model":"机型", "chip":"芯片", "cores":"核心",
 "ram":"内存", "ioreport":"IOReport", "dvfs":"DVFS", "battery_present":"电池", "python":"Python",
 "help":"用法: 双击运行，或在终端执行：\n  ./SysMon-One.command [--lang zh|en] [--compact] [--expert] [--doctor] [--clean|--scan] [--interval 2]\n\n--compact  紧凑视图\n--expert   专家视图（更多传感器/能量通道）\n--doctor   仅执行兼容性自检\n--clean    Storage Doctor：扫描并可清理绿色安全项\n--scan     只扫描磁盘，不删除任何内容\n--plain    无清屏/无光标控制，便于记录输出\n\n实时热键：C 磁盘医生 · P 进程中心 · / 搜索进程 · Q 退出",
 "init":"正在发现硬件拓扑并建立计数器基线…", "procs_cpu":"CPU Top", "procs_mem":"内存 Top",
 "ac":"外接电源", "discharging":"放电", "charging":"充电", "unknown":"未知", "logical":"逻辑核",
 "note_gpu":"GPU Active 是非 OFF 驻留时间，不冒充驱动层 utilization。",
 "pressure":"实时压力", "headroom":"余量", "insight":"核心提示", "peak":"本次峰值",
 "swap_top":"Swap/压缩 Top5", "scanning":"深查中", "quit":"建议退出", "keep":"系统进程·别杀", "watch":"观察",
 "hardware":"硬件", "system":"系统", "gpucores":"GPU核", "build":"构建", "pressure_note":"压力指数是实时启发式指标，不是跑分。",
 "fan":"风扇", "process_center":"进程中心", "process_tree":"进程树", "search":"搜索", "terminate":"结束进程", "storage":"磁盘医生", "safe_free":"绿色安全项", "review":"黄色人工检查", "protected":"受保护，不会自动删除", "storage_scan":"正在扫描空间结构…", "reclaim":"可安全释放", "review_space":"建议检查", "disk_used":"磁盘占用", "largest":"大文件 Top", "apps":"应用 Top", "clean_done":"清理完成", "back":"返回监控"
},
"en": {
 "title":"SysMon One", "subtitle":"single file · no sudo · local only", "cpu":"CPU", "total":"total", "cluster":"Clusters",
 "gpu":"GPU", "active":"Active", "clock":"Clock", "effective":"Effective", "voltage":"Voltage", "temp":"Temp",
 "power":"Power", "memory":"Memory", "available":"Avail", "compressed":"Compressed", "swap":"Swap", "free":"Free",
 "swapin":"Swap-in", "swapout":"Swap-out", "disk":"Disk", "read":"Read", "write":"Write", "network":"Network",
 "down":"Down", "up":"Up", "battery":"Battery", "health":"Health", "cycles":"Cycles", "thermal":"Thermal",
 "history":"60s history", "process":"Hot processes", "pid":"PID", "load":"load", "uptime":"uptime",
 "collector":"sample", "source":"sources", "exit":"Ctrl+C exit", "na":"N/A", "idle":"idle", "fanless":"fanless",
 "doctor":"Compatibility doctor", "ok":"available", "missing":"unavailable", "model":"Model", "chip":"Chip", "cores":"Cores",
 "ram":"RAM", "ioreport":"IOReport", "dvfs":"DVFS", "battery_present":"Battery", "python":"Python",
 "help":"Usage: double-click, or run in Terminal:\n  ./SysMon-One.command [--lang zh|en] [--compact] [--expert] [--doctor] [--clean|--scan] [--interval 2]\n\n--compact  compact view\n--expert   expert view (more sensors/energy rails)\n--doctor   compatibility report only\n--clean    Storage Doctor: scan + optional green safe cleanup\n--scan     storage scan only; never deletes anything\n--plain    sequential output without cursor control\n\nLive keys: C Storage Doctor · P Process Center · / Search · Q Quit",
 "init":"Discovering hardware topology and building counter baselines…", "procs_cpu":"CPU Top", "procs_mem":"Memory Top",
 "ac":"AC", "discharging":"discharging", "charging":"charging", "unknown":"unknown", "logical":"logical",
 "note_gpu":"GPU Active is non-OFF residency, not mislabeled as driver utilization.",
 "pressure":"Live pressure", "headroom":"headroom", "insight":"Core insight", "peak":"Session peaks",
 "swap_top":"Swap/compressed Top5", "scanning":"deep scan", "quit":"quit suggested", "keep":"system · keep", "watch":"watch",
 "hardware":"Hardware", "system":"System", "gpucores":"GPU cores", "build":"build", "pressure_note":"Pressure is a live heuristic, not a benchmark score.",
 "fan":"Fan", "process_center":"Process Center", "process_tree":"Process tree", "search":"Search", "terminate":"Terminate", "storage":"Storage Doctor", "safe_free":"Green safe items", "review":"Yellow manual review", "protected":"Protected; never auto-deleted", "storage_scan":"Scanning storage structure…", "reclaim":"Safe reclaim", "review_space":"Review", "disk_used":"Disk used", "largest":"Largest files", "apps":"Largest apps", "clean_done":"Cleanup complete", "back":"Back to monitor"
}}
T = TXT[LANG]
if A.help:
    print(T["help"])
    raise SystemExit(0)

# ----------------------------- formatting -----------------------------
def hue(pct, warn=70.0, crit=90.0):
    return RED if pct >= crit else (YEL if pct >= warn else GRN)

def temp_hue(c):
    return RED if c >= 95 else (YEL if c >= 80 else GRN)

def bar(pct, width=16):
    pct = max(0.0, min(100.0, pct or 0.0)); n = int(round(width * pct / 100.0))
    return f"{hue(pct)}{'█'*n}{DIM}{'░'*(width-n)}{RST}"

def human_bytes(n):
    n = float(n or 0)
    for scale, unit in ((1e12,"TB"),(1e9,"GB"),(1e6,"MB"),(1e3,"KB")):
        if abs(n) >= scale: return f"{n/scale:.1f}{unit}"
    return f"{n:.0f}B"

def rate(n):
    return human_bytes(n) + "/s" if n and n > 0 else "0B/s"

def dwidth(text):
    """Terminal display width for plain text; CJK wide chars count as 2."""
    return sum(2 if unicodedata.east_asian_width(ch) in ("W","F") else 1 for ch in str(text))

def clip_plain(text, maxw):
    text=str(text); maxw=max(1,int(maxw))
    if dwidth(text) <= maxw: return text
    out=[]; used=0
    for ch in text:
        cw=2 if unicodedata.east_asian_width(ch) in ("W","F") else 1
        if used+cw > maxw-1: break
        out.append(ch); used+=cw
    return "".join(out)+"…"

def pad_plain(text, width):
    text=clip_plain(text,width)
    return text + " "*max(0,width-dwidth(text))

def wrap_plain(text, width, max_lines=3):
    text=str(text).strip(); width=max(8,int(width)); lines=[]
    while text and len(lines)<max_lines:
        if dwidth(text)<=width:
            lines.append(text); text=""; break
        out=[]; used=0; last_space=-1
        for i,ch in enumerate(text):
            cw=2 if unicodedata.east_asian_width(ch) in ("W","F") else 1
            if used+cw>width: break
            out.append(ch); used+=cw
            if ch.isspace(): last_space=len(out)-1
        cut=len(out)
        if last_space>=0 and cut-last_space<12: cut=last_space
        part=text[:cut].rstrip(); text=text[cut:].lstrip()
        if part: lines.append(part)
        else: break
    if text and lines:
        lines[-1]=clip_plain(lines[-1]+"…",width)
    return lines or [""]

def uptime_text(sec):
    d, r = divmod(int(max(0, sec)), 86400); h, r = divmod(r, 3600); m = r//60
    if LANG == "zh": return f"{d}天 {h}时 {m}分" if d else (f"{h}时 {m}分" if h else f"{m}分")
    return f"{d}d {h}h {m}m" if d else (f"{h}h {m}m" if h else f"{m}m")

def width():
    try:
        import shutil
        return shutil.get_terminal_size((110, 35)).columns
    except Exception: return 110

SPARK = "▁▂▃▄▅▆▇█"
def spark(values, hi=None, n=30):
    vals = list(values)[-n:]
    if not vals: return DIM + "·"*n + RST
    top = max(1e-9, float(hi if hi is not None else max(vals)))
    chars = []
    for v in vals:
        x = max(0.0, min(1.0, float(v)/top)); chars.append(SPARK[min(7, int(x*7.999))])
    return "".join(chars).rjust(n, "·")

# ----------------------------- identity/cache -----------------------------
SYSCTL_CACHE = {}
def sysctl(key, default=""):
    if key not in SYSCTL_CACHE:
        SYSCTL_CACHE[key] = sh(["/usr/sbin/sysctl", "-n", key], 3).strip() or default
    return SYSCTL_CACHE[key]

def hardware_profile():
    """Cached once at launch. Deliberately ignores serial/UUID fields."""
    d={}
    try:
        raw=sh(["/usr/sbin/system_profiler","SPHardwareDataType","SPDisplaysDataType","-json"],12)
        j=json.loads(raw) if raw else {}
        h=(j.get("SPHardwareDataType") or [{}])[0]
        g=(j.get("SPDisplaysDataType") or [{}])[0]
        d["name"]=h.get("machine_name") or h.get("_name") or "Mac"
        d["identifier"]=h.get("machine_model") or ""
        d["chip"]=h.get("chip_type") or g.get("sppci_model") or ""
        d["cores"]=h.get("number_processors") or ""
        d["memory"]=h.get("physical_memory") or ""
        try: d["gpu_cores"]=int(g.get("sppci_cores") or 0)
        except Exception: d["gpu_cores"]=0
    except Exception:
        pass
    return d

HW=hardware_profile()
SWVERS = sh(["/usr/bin/sw_vers", "-productVersion"], 3).strip()
SWBUILD = sh(["/usr/bin/sw_vers", "-buildVersion"], 3).strip()
ARCH = platform.machine()
MODEL = HW.get("identifier") or sysctl("hw.model", ARCH)
MODEL_NAME = HW.get("name") or "Mac"
CHIP = HW.get("chip") or sysctl("machdep.cpu.brand_string", "Apple Silicon" if ARCH=="arm64" else platform.processor())
GPU_CORES = HW.get("gpu_cores") or 0
try: NCPU = int(sysctl("hw.ncpu", str(os.cpu_count() or 1)))
except Exception: NCPU = os.cpu_count() or 1
try: MEMTOTAL = int(sysctl("hw.memsize", "0"))
except Exception: MEMTOTAL = 0
try: BOOT = float(re.search(r"sec = (\d+)", sysctl("kern.boottime", "")).group(1))
except Exception: BOOT = time.time()

# ----------------------------- CoreFoundation / IOReport -----------------------------
HAS_IO = False
CF = IO = None
vp = ctypes.c_void_p; u64 = ctypes.c_uint64; i64 = ctypes.c_int64; i32 = ctypes.c_int; u32 = ctypes.c_uint32
SUBS = {}; CHDEFS = {}; CFKEY_CHANNELS = None
try:
    CF = ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
    IO = ctypes.CDLL('/usr/lib/libIOReport.dylib')
    CF.CFStringCreateWithCString.restype = vp; CF.CFStringCreateWithCString.argtypes = [vp, ctypes.c_char_p, u32]
    CF.CFStringGetCStringPtr.restype = ctypes.c_char_p; CF.CFStringGetCStringPtr.argtypes = [vp, u32]
    CF.CFStringGetCString.restype = ctypes.c_bool; CF.CFStringGetCString.argtypes = [vp, ctypes.c_char_p, ctypes.c_long, u32]
    CF.CFDictionaryGetValue.restype = vp; CF.CFDictionaryGetValue.argtypes = [vp, vp]
    CF.CFArrayGetCount.restype = ctypes.c_long; CF.CFArrayGetCount.argtypes = [vp]
    CF.CFArrayGetValueAtIndex.restype = vp; CF.CFArrayGetValueAtIndex.argtypes = [vp, ctypes.c_long]
    CF.CFRelease.argtypes = [vp]
    IO.IOReportCopyChannelsInGroup.restype = vp; IO.IOReportCopyChannelsInGroup.argtypes = [vp, vp, u64, u64, u64]
    IO.IOReportCreateSubscription.restype = vp; IO.IOReportCreateSubscription.argtypes = [vp, vp, ctypes.POINTER(vp), u64, vp]
    IO.IOReportCreateSamples.restype = vp; IO.IOReportCreateSamples.argtypes = [vp, vp, vp]
    IO.IOReportCreateSamplesDelta.restype = vp; IO.IOReportCreateSamplesDelta.argtypes = [vp, vp, vp]
    for fn, rt in (("IOReportChannelGetGroup",vp),("IOReportChannelGetSubGroup",vp),("IOReportChannelGetChannelName",vp),("IOReportChannelGetUnitLabel",vp),("IOReportStateGetNameForIndex",vp)):
        getattr(IO, fn).restype = rt; getattr(IO, fn).argtypes = [vp, i32] if fn=="IOReportStateGetNameForIndex" else [vp]
    IO.IOReportChannelGetFormat.restype = i32; IO.IOReportChannelGetFormat.argtypes = [vp]
    IO.IOReportSimpleGetIntegerValue.restype = i64; IO.IOReportSimpleGetIntegerValue.argtypes = [vp, i32]
    IO.IOReportStateGetCount.restype = u64; IO.IOReportStateGetCount.argtypes = [vp]
    IO.IOReportStateGetResidency.restype = i64; IO.IOReportStateGetResidency.argtypes = [vp, i32]
    HAS_IO = True
except Exception:
    HAS_IO = False

def cfstr(s):
    return CF.CFStringCreateWithCString(None, s.encode("utf-8"), 0x08000100) if HAS_IO else None

def cstr(ref):
    if not ref or not HAS_IO: return None
    p = CF.CFStringGetCStringPtr(ref, 0x08000100)
    if p: return p.decode("utf-8", "replace")
    buf = ctypes.create_string_buffer(2048)
    return buf.value.decode("utf-8","replace") if CF.CFStringGetCString(ref,buf,2048,0x08000100) else None

if HAS_IO: CFKEY_CHANNELS = cfstr("IOReportChannels")
def chans(d):
    if not d or not HAS_IO: return []
    arr = CF.CFDictionaryGetValue(d, CFKEY_CHANNELS)
    if not arr: return []
    return [CF.CFArrayGetValueAtIndex(arr,i) for i in range(CF.CFArrayGetCount(arr))]

def names(ch):
    return (cstr(IO.IOReportChannelGetGroup(ch)), cstr(IO.IOReportChannelGetSubGroup(ch)), cstr(IO.IOReportChannelGetChannelName(ch)))

def states(ch):
    out=[]
    for i in range(IO.IOReportStateGetCount(ch)):
        out.append((cstr(IO.IOReportStateGetNameForIndex(ch,i)), IO.IOReportStateGetResidency(ch,i)))
    return out

def subscribe():
    if not HAS_IO: return
    for g in ("CPU Stats","GPU Stats","PMP","Energy Model"):
        gs=cfstr(g)
        try: d=IO.IOReportCopyChannelsInGroup(gs,None,0,0,0)
        finally:
            if gs: CF.CFRelease(gs)
        if not d: continue
        sb=vp(); s=IO.IOReportCreateSubscription(None,d,ctypes.byref(sb),0,None)
        if s:
            SUBS[g]=(s,sb); CHDEFS[g]=d
        else:
            CF.CFRelease(d)
subscribe()

def snapshot():
    return {g:IO.IOReportCreateSamples(s,sb,None) for g,(s,sb) in SUBS.items()}
def deltas(a,b):
    return {g:IO.IOReportCreateSamplesDelta(a[g],b[g],None) for g in a if a.get(g) and b.get(g)}
def release_map(m):
    if not HAS_IO: return
    for x in m.values():
        try:
            if x: CF.CFRelease(x)
        except Exception: pass

# ----------------------------- dynamic topology / DVFS -----------------------------
def natkey(s):
    return [int(x) if x.isdigit() else x for x in re.split(r"(\d+)", s or "")]

def core_cluster(name):
    m=re.match(r"^([A-Z]*CPU)(\d)", name or "")
    if not m: return "?0"
    typ="E" if m.group(1).startswith("E") else ("P" if m.group(1).startswith("P") else m.group(1)[0])
    return typ + m.group(2)

def complex_cluster(name):
    s=name or ""
    if s.startswith("ECPU"):
        d=s[4:]; return "E"+(d[0] if d and d[0].isdigit() else "0")
    if s.startswith("PCPU"):
        d=s[4:]; return "P"+(d[0] if d and d[0].isdigit() else "0")
    return s

def topology():
    cores=[]; complexes=[]; gpu_states=0
    for d in CHDEFS.values():
        for ch in chans(d):
            g,sg,nm=names(ch); fmt=IO.IOReportChannelGetFormat(ch) if HAS_IO else -1
            if g=="CPU Stats" and sg=="CPU Core Performance States" and fmt==2:
                cnt=0
                for i in range(IO.IOReportStateGetCount(ch)):
                    sn=cstr(IO.IOReportStateGetNameForIndex(ch,i)) or ""
                    m=re.match(r"V(\d+)P\d+$",sn)
                    if m: cnt=max(cnt,int(m.group(1))+1)
                cores.append((nm,core_cluster(nm),cnt))
            elif g=="CPU Stats" and sg=="CPU Complex Performance States" and fmt==2:
                cnt=0
                for i in range(IO.IOReportStateGetCount(ch)):
                    sn=cstr(IO.IOReportStateGetNameForIndex(ch,i)) or ""; m=re.match(r"V(\d+)P\d+$",sn)
                    if m: cnt=max(cnt,int(m.group(1))+1)
                complexes.append((nm,complex_cluster(nm),cnt))
            elif g=="GPU Stats" and sg=="GPU Performance States" and fmt==2:
                count=0
                for i in range(IO.IOReportStateGetCount(ch)):
                    sn=cstr(IO.IOReportStateGetNameForIndex(ch,i)) or ""
                    if re.match(r"P\d+$",sn): count += 1
                gpu_states=max(gpu_states,count)
    cores=sorted({x for x in cores},key=lambda x:natkey(x[0]))
    complexes=sorted({x for x in complexes},key=lambda x:natkey(x[1]))
    return cores,complexes,gpu_states
CORES, COMPLEXES, GPU_STATE_COUNT = topology() if HAS_IO else ([],[],0)

def read_dt_candidates():
    txt=sh(["/usr/sbin/ioreg","-p","IODeviceTree","-l","-w0"],20)
    out=[]
    for m in re.finditer(r'"voltage-states(\d+)" = <([0-9a-fA-F\s]+)>',txt):
        idx=int(m.group(1)); hx=re.sub(r"\s","",m.group(2))
        try:
            b=bytes.fromhex(hx); w=struct.unpack("<%dI"%(len(b)//4),b)
            pairs=[(w[i],w[i+1]) for i in range(0,len(w)-1,2)]
        except Exception: continue
        cpu=[]; gpu=[]
        for p,v in pairs:
            if p:
                mhz=65536.0*1000.0/p
                if 100 <= mhz <= 8000: cpu.append(mhz)
            if v:
                mhz2=v/1e6
                if 50 <= mhz2 <= 8000: gpu.append(mhz2)
        if len(cpu) >= max(2,len(pairs)//2): out.append({"id":idx,"kind":"cpu","vals":cpu})
        if len(gpu) >= max(2,len(pairs)//2): out.append({"id":idx,"kind":"gpu","vals":sorted(gpu)})
    return out
DT = read_dt_candidates() if platform.system()=="Darwin" else []

def cpu_ladder(cluster, nstates):
    cand=[x for x in DT if x["kind"]=="cpu" and len(x["vals"])==nstates]
    if not cand: return []
    cand.sort(key=lambda x:max(x["vals"]))
    return cand[0]["vals"] if cluster.startswith("E") else cand[-1]["vals"]

def gpu_ladder(nstates):
    cand=[x for x in DT if x["kind"]=="gpu" and len(x["vals"]) in (nstates,nstates+1)]
    if not cand: return []
    cand.sort(key=lambda x:(abs(len(x["vals"])-nstates),max(x["vals"])))
    return cand[0]["vals"]
CPU_LADDERS={cl:cpu_ladder(cl,n) for _nm,cl,n in COMPLEXES}
for _nm,cl,n in CORES:
    CPU_LADDERS.setdefault(cl,cpu_ladder(cl,n))
GPU_LADDER=gpu_ladder(GPU_STATE_COUNT)

# ----------------------------- Mach CPU ticks -----------------------------
LIBC=None; MACH_TASK_SELF=0
try:
    LIBC=ctypes.CDLL('/usr/lib/libSystem.B.dylib')
    LIBC.mach_host_self.restype=u32
    LIBC.host_processor_info.restype=ctypes.c_int
    LIBC.host_processor_info.argtypes=[u32,i32,ctypes.POINTER(u32),ctypes.POINTER(ctypes.POINTER(u32)),ctypes.POINTER(u32)]
    LIBC.vm_deallocate.argtypes=[u32,vp,u64]
    # mach_task_self_ is a DATA SYMBOL (mach_port_t), not a function.
    # Calling it through ctypes as if it were executable causes SIGBUS/EXC_BAD_ACCESS
    # on modern arm64 macOS. Read the exported variable instead.
    try: MACH_TASK_SELF=ctypes.c_uint32.in_dll(LIBC,'mach_task_self_').value
    except Exception: MACH_TASK_SELF=0
except Exception: pass
PROCESSOR_CPU_LOAD_INFO=2

def cpu_ticks():
    if not LIBC: return []
    cnt=u32(0); info=ctypes.POINTER(u32)(); n=u32(0)
    if LIBC.host_processor_info(LIBC.mach_host_self(),PROCESSOR_CPU_LOAD_INFO,ctypes.byref(cnt),ctypes.byref(info),ctypes.byref(n))!=0: return []
    try: return [[info[i*4+k] for k in range(4)] for i in range(n.value)]
    finally:
        try: LIBC.vm_deallocate(MACH_TASK_SELF,ctypes.cast(info,vp),n.value*4*ctypes.sizeof(u32)) if MACH_TASK_SELF else None
        except Exception: pass

# ----------------------------- fast OS counters (one subprocess per frame) -----------------------------
MARK1="__SM_VM__"; MARK2="__SM_NET__"; MARK3="__SM_DISK__"; MARK4="__SM_SWAP__"
FAST_CMD=(f"echo {MARK1}; /usr/bin/vm_stat 2>/dev/null; "
          f"echo {MARK2}; /usr/sbin/netstat -ib 2>/dev/null; "
          f"echo {MARK3}; /usr/sbin/ioreg -r -c IOBlockStorageDriver -d 1 -w0 2>/dev/null; "
          f"echo {MARK4}; /usr/sbin/sysctl -n vm.swapusage 2>/dev/null")
NET_SKIP=re.compile(r"^(lo|gif|stf|bridge|utun|awdl|llw|ap\d|en\d+\.\d+)")

def fast_counters():
    txt=sh(["/bin/sh","-c",FAST_CMD],8)
    try:
        vm,rest=txt.split(MARK2,1); net,rest=rest.split(MARK3,1); disk,swap=rest.split(MARK4,1)
    except ValueError:
        vm=net=disk=swap=""
    try: page_size=int(os.sysconf("SC_PAGE_SIZE"))
    except Exception: page_size=4096
    pages={}
    m=re.search(r"page size of (\d+) bytes",vm)
    if m: page_size=int(m.group(1))
    for line in vm.splitlines():
        m=re.match(r'"?([^":]+)"?:\s+(\d+)\.?$',line.strip())
        if m: pages[m.group(1).strip()]=int(m.group(2))
    rx=tx=0
    lines=net.splitlines()
    for line in lines[1:]:
        f=line.split()
        if len(f)<10 or NET_SKIP.match(f[0]) or not f[2].startswith("<Link"): continue
        try: rx+=int(f[6]); tx+=int(f[9])
        except Exception: pass
    vals=re.findall(r'"Bytes \(([A-Za-z]+)\)"\s*=\s*(\d+)',disk)
    rd=sum(int(v) for k,v in vals if "Read" in k); wr=sum(int(v) for k,v in vals if "Write" in k)
    m=re.search(r"total = ([\d.]+)([MG])\s+used = ([\d.]+)([MG])\s+free = ([\d.]+)([MG])",swap)
    if m:
        cv=lambda v,u:float(v)*(1e9 if u=="G" else 1e6)
        sw=(cv(m.group(1),m.group(2)),cv(m.group(3),m.group(4)),cv(m.group(5),m.group(6)))
    else: sw=(0.0,0.0,0.0)
    return pages,page_size,rx,tx,rd,wr,sw

# ----------------------------- IOReport parser -----------------------------
UNIT_J={"J":1.0,"mJ":1e-3,"uJ":1e-6,"µJ":1e-6,"nJ":1e-9}
def parse_io(dd, absolute):
    core_freq={}; complex_freq={}; vt={}; gpu={"active":0.0,"clock":0.0,"effective":0.0,"dom":"--"}; energy={}
    for d in dd.values():
        for ch in chans(d):
            g,sg,nm=names(ch); fmt=IO.IOReportChannelGetFormat(ch)
            if g=="CPU Stats" and sg=="CPU Core Performance States" and fmt==2:
                cl=core_cluster(nm); ladder=CPU_LADDERS.get(cl,[]); tot=acc=0
                for sn,res in states(ch):
                    mm=re.match(r"V(\d+)P\d+$",sn or "")
                    if mm and res>0:
                        i=int(mm.group(1))
                        if i<len(ladder): tot+=res; acc+=res*ladder[i]
                if tot: core_freq[nm]=acc/tot
            elif g=="CPU Stats" and sg=="CPU Complex Performance States" and fmt==2:
                cl=complex_cluster(nm); ladder=CPU_LADDERS.get(cl,[]); tot=acc=0
                for sn,res in states(ch):
                    mm=re.match(r"V(\d+)P\d+$",sn or "")
                    if mm and res>0:
                        i=int(mm.group(1))
                        if i<len(ladder): tot+=res; acc+=res*ladder[i]
                if tot: complex_freq[cl]=acc/tot
            elif g=="PMP" and sg=="Volt-Temp HM" and fmt==2:
                st=states(ch); total=sum(r for _s,r in st if r>0); nz=sum(r for s,r in st if r>0 and s and not s.startswith("0_"))
                best=(0,None,None)
                for sn,res in st:
                    if res<=0 or not sn: continue
                    try: v,t=[float(x) for x in sn.split("_")[:2]]
                    except Exception: continue
                    if v>0 and res>best[0]: best=(res,v,t)
                if best[1] is not None: vt[nm]=(best[1],best[2],nz/total if total else 0.0)
            elif g=="GPU Stats" and sg=="GPU Performance States" and fmt==2:
                st=states(ch); total=sum(r for _s,r in st if r>0); active=acc=0; dom=(0,"--")
                for sn,res in st:
                    if res<=0: continue
                    mm=re.match(r"P(\d+)$",sn or "")
                    if mm:
                        i=int(mm.group(1))-1
                        if 0<=i<len(GPU_LADDER): active+=res; acc+=res*GPU_LADDER[i]
                    if res>dom[0]: dom=(res,sn or "--")
                if total:
                    gpu["active"]=100.0*active/total
                    gpu["clock"]=acc/active if active else 0.0
                    gpu["effective"]=acc/total
                    gpu["dom"]=dom[1]
    for d in absolute.values():
        for ch in chans(d):
            g,sg,nm=names(ch)
            if g=="Energy Model" and IO.IOReportChannelGetFormat(ch)==1:
                energy[nm]=(IO.IOReportSimpleGetIntegerValue(ch,0), cstr(IO.IOReportChannelGetUnitLabel(ch)) or "")
    return core_freq,complex_freq,vt,gpu,energy

def power_delta(prev,cur,dt):
    out={}
    for k,(v,u) in cur.items():
        if k not in prev or u not in UNIT_J: continue
        dv=v-prev[k][0]
        if dv>=0: out[k]=dv*UNIT_J[u]/max(dt,1e-6)
    return out

def pfind(pw, token):
    token=token.upper(); return sum(v for k,v in pw.items() if token in k.upper())

# ----------------------------- AppleSMC fan reader -----------------------------
# Read-only AppleSMC access. No sudo, no fan-control writes. If Apple/OEM firmware does not
# expose fan keys, we return an empty list instead of pretending a zero RPM is meaningful.
SMC_CONN=None; SMC_IO=None
try:
    class SMCVers(ctypes.Structure):
        _fields_=[("major",ctypes.c_uint8),("minor",ctypes.c_uint8),("build",ctypes.c_uint8),("reserved",ctypes.c_uint8),("release",ctypes.c_uint16)]
    class SMCPLimit(ctypes.Structure):
        _fields_=[("version",ctypes.c_uint16),("length",ctypes.c_uint16),("cpuPLimit",ctypes.c_uint32),("gpuPLimit",ctypes.c_uint32),("memPLimit",ctypes.c_uint32)]
    class SMCInfo(ctypes.Structure):
        _fields_=[("dataSize",ctypes.c_uint32),("dataType",ctypes.c_uint32),("dataAttributes",ctypes.c_uint8)]
    class SMCData(ctypes.Structure):
        _fields_=[("key",ctypes.c_uint32),("vers",SMCVers),("pLimitData",SMCPLimit),("keyInfo",SMCInfo),("result",ctypes.c_uint8),("status",ctypes.c_uint8),("data8",ctypes.c_uint8),("data32",ctypes.c_uint32),("bytes",ctypes.c_uint8*32)]
    SMC_IO=ctypes.CDLL('/System/Library/Frameworks/IOKit.framework/IOKit')
    SMC_IO.IOServiceMatching.restype=vp; SMC_IO.IOServiceMatching.argtypes=[ctypes.c_char_p]
    SMC_IO.IOServiceGetMatchingService.restype=ctypes.c_uint32; SMC_IO.IOServiceGetMatchingService.argtypes=[ctypes.c_uint32,vp]
    SMC_IO.IOServiceOpen.restype=ctypes.c_int; SMC_IO.IOServiceOpen.argtypes=[ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.POINTER(ctypes.c_uint32)]
    SMC_IO.IOObjectRelease.argtypes=[ctypes.c_uint32]
    SMC_IO.IOConnectCallStructMethod.restype=ctypes.c_int
    SMC_IO.IOConnectCallStructMethod.argtypes=[ctypes.c_uint32,ctypes.c_uint32,vp,ctypes.c_size_t,vp,ctypes.POINTER(ctypes.c_size_t)]
    # Known AppleSMC key-data ABI. Refuse the feature rather than risking an unsafe call
    # if the local Python/ctypes layout is unexpectedly different.
    if ctypes.sizeof(SMCData)!=80: raise RuntimeError('unexpected AppleSMC ABI layout')
    svc=SMC_IO.IOServiceGetMatchingService(0,SMC_IO.IOServiceMatching(b"AppleSMC"))
    if svc:
        conn=ctypes.c_uint32(0)
        if MACH_TASK_SELF and SMC_IO.IOServiceOpen(svc,MACH_TASK_SELF,0,ctypes.byref(conn))==0: SMC_CONN=conn.value
        SMC_IO.IOObjectRelease(svc)
except Exception:
    SMC_CONN=None

def _smc4(s):
    b=s.encode('ascii','ignore')[:4].ljust(4,b' '); return struct.unpack('>I',b)[0]
def _smctype(n):
    try: return struct.pack('>I',n).decode('ascii','ignore')
    except Exception: return ''
def _smc_read(key):
    if not SMC_CONN or not SMC_IO: return None
    try:
        inp=SMCData(); out=SMCData(); inp.key=_smc4(key); inp.data8=9
        osz=ctypes.c_size_t(ctypes.sizeof(out))
        if SMC_IO.IOConnectCallStructMethod(SMC_CONN,2,ctypes.byref(inp),ctypes.sizeof(inp),ctypes.byref(out),ctypes.byref(osz))!=0: return None
        size=int(out.keyInfo.dataSize); typ=_smctype(out.keyInfo.dataType)
        if size<=0 or size>32: return None
        inp2=SMCData(); out2=SMCData(); inp2.key=inp.key; inp2.keyInfo=out.keyInfo; inp2.data8=5
        osz=ctypes.c_size_t(ctypes.sizeof(out2))
        if SMC_IO.IOConnectCallStructMethod(SMC_CONN,2,ctypes.byref(inp2),ctypes.sizeof(inp2),ctypes.byref(out2),ctypes.byref(osz))!=0: return None
        data=bytes(out2.bytes[:size])
        if typ.startswith('ui8'): return float(data[0])
        if typ.startswith('ui16') and len(data)>=2: return float(struct.unpack('>H',data[:2])[0])
        if typ.startswith('ui32') and len(data)>=4: return float(struct.unpack('>I',data[:4])[0])
        if typ.startswith('si16') and len(data)>=2: return float(struct.unpack('>h',data[:2])[0])
        if typ=='fpe2' and len(data)>=2: return struct.unpack('>H',data[:2])[0]/4.0
        if typ=='sp78' and len(data)>=2: return struct.unpack('>h',data[:2])[0]/256.0
        if typ=='flt ' and len(data)>=4:
            v=struct.unpack('>f',data[:4])[0]
            return float(v) if math.isfinite(v) else None
        # Several SMC fixed-point fan encodings use fpXY. Decode conservatively.
        if typ.startswith('fp') and len(data)>=2:
            try:
                frac=int(typ[3],16); return struct.unpack('>H',data[:2])[0]/float(1<<frac)
            except Exception: pass
    except Exception: pass
    return None

def smc_fans():
    if not SMC_CONN: return []
    n=_smc_read('FNum')
    try: n=int(n or 0)
    except Exception: n=0
    # Some firmware does not expose FNum but still exposes F0Ac.
    idxs=range(min(max(n,0),8)) if n else range(4)
    out=[]
    for i in idxs:
        ac=_smc_read(f'F{i}Ac')
        if ac is None:
            if not n and i==0: continue
            if not n: break
            continue
        mn=_smc_read(f'F{i}Mn'); mx=_smc_read(f'F{i}Mx'); tg=_smc_read(f'F{i}Tg')
        if 0 <= ac < 30000:
            out.append({'id':i,'rpm':ac,'min':mn,'max':mx,'target':tg})
    return out

# ----------------------------- slow extras / smart diagnosis -----------------------------
SLOW={"ts":0,"battery":{},"thermal":"--","fans":[],"fts":0,"mem_pressure":{},"procs":([],[]),"swap_detail":[],"swap_scan_ts":0,"swap_scan_busy":False,"swap_scan_ok":False}
def signed64(v): return v-(1<<64) if v>(1<<63) else v

def battery_info():
    batt=sh(["/usr/bin/pmset","-g","batt"],4); io=sh(["/usr/sbin/ioreg","-r","-c","AppleSmartBattery","-d","1","-w0"],5)
    d={"present":bool(re.search(r"\d+%",batt))}
    m=re.search(r"(\d+)%",batt)
    if m: d["pct"]=int(m.group(1))
    low=batt.lower(); d["state"]="charging" if "charging" in low and "discharging" not in low else ("discharging" if "discharging" in low else ("ac" if "ac power" in low else "unknown"))
    for key in ("CycleCount","MaxCapacity","AppleRawMaxCapacity","DesignCapacity","Voltage","Amperage"):
        m=re.search(r'"'+re.escape(key)+r'"\s*=\s*(\d+)',io)
        if m: d[key]=int(m.group(1))
    mx=d.get("AppleRawMaxCapacity") or d.get("MaxCapacity"); des=d.get("DesignCapacity")
    if mx and des: d["health"]=100.0*mx/des
    if d.get("Voltage") is not None and d.get("Amperage") is not None:
        amp=signed64(d["Amperage"]); d["watts"]=amp*d["Voltage"]/1e6
    return d

def thermal_info():
    s=sh(["/usr/bin/pmset","-g","therm"],4)
    m=re.search(r"CPU_Speed_Limit\s*=\s*(\d+)",s)
    if m: return f"CPU limit {m.group(1)}%"
    if "No thermal warning" in s: return "Normal"
    return "--"

def memory_pressure_info():
    s=sh(["/usr/bin/memory_pressure"],4); d={}
    m=re.search(r"System memory pressure level:\s*(\d+)",s)
    if m: d["level"]=int(m.group(1))
    m=re.search(r"System-wide memory free percentage:\s*(\d+)%",s)
    if m: d["free_pct"]=int(m.group(1))
    return d

def process_top():
    s=sh(["/bin/ps","-Ao","pid=,pcpu=,rss=,uid=,comm="],4); rows=[]
    for line in s.splitlines():
        p=line.strip().split(None,4)
        if len(p)<5: continue
        try:
            path=p[4]; rows.append((int(p[0]),float(p[1]),int(p[2])*1024,os.path.basename(path),path,int(p[3])))
        except Exception: pass
    return sorted(rows,key=lambda x:x[1],reverse=True)[:6], sorted(rows,key=lambda x:x[2],reverse=True)[:10]

def bytes_token(s):
    s=(s or "").strip().replace(",","")
    if s in ("---","--",""): return 0
    try: return int(float(s))
    except Exception: pass
    m=re.match(r"([\d.]+)\s*([KMGT]?B)",s,re.I)
    if not m: return 0
    scale={"B":1,"KB":1024,"MB":1024**2,"GB":1024**3,"TB":1024**4}.get(m.group(2).upper(),1)
    return int(float(m.group(1))*scale)

def footprint_swapped(row):
    pid,cpu,rss,name,path,uid=row
    if uid!=os.getuid() or pid==os.getpid() or not os.path.exists("/usr/bin/footprint"): return None
    text=sh(["/usr/bin/footprint","-p",str(pid),"--swapped","-f","bytes","-y"],2.5)
    if not text: return None
    header=None; total=None
    for line in text.splitlines():
        if "Swapped" in line and "Dirty" in line:
            header=re.split(r"\s{2,}",line.strip())
        elif re.search(r"\bTOTAL\s*$",line):
            total=re.split(r"\s{2,}",line.strip())
    sw=0
    if header and total:
        try:
            idx=next(i for i,x in enumerate(header) if "Swapped" in x)
            if idx < len(total): sw=bytes_token(total[idx])
        except Exception: pass
    if not sw:
        # Fallback for formatting changes: first integer immediately under a Swapped column is unavailable,
        # so do not invent it. Returning 0 keeps the ranking honest.
        sw=0
    return (pid,cpu,rss,name,path,uid,sw)

PROTECTED=("kernel_task","launchd","WindowServer","loginwindow","powerd","configd","runningboardd","trustd","logd","mds","mdworker","coreaudiod","bluetoothd","sysmond","distnoted")
def process_advice(row):
    pid,cpu,rss,name,path,uid,*rest=row
    low=name.lower(); p=(path or "").lower()
    if any(low==x.lower() or low.startswith(x.lower()+"_") for x in PROTECTED) or p.startswith(("/system/","/usr/","/sbin/","/bin/")):
        return T["keep"]
    if rss >= max(2*1024**3, MEMTOTAL*0.10 if MEMTOTAL else 2*1024**3): return T["quit"]
    if rest and rest[0] >= max(768*1024**2, MEMTOTAL*0.04 if MEMTOTAL else 768*1024**2): return T["quit"]
    return T["watch"]

def _swap_scan(candidates):
    try:
        rows=[]
        with ThreadPoolExecutor(max_workers=4) as ex:
            fut=[ex.submit(footprint_swapped,r) for r in candidates[:8] if r[5]==os.getuid()]
            for f in as_completed(fut):
                try:
                    r=f.result()
                    if r and r[-1]>0: rows.append(r)
                except Exception: pass
        SLOW["swap_detail"]=sorted(rows,key=lambda x:x[-1],reverse=True)[:5]
        SLOW["swap_scan_ok"]=bool(rows)
        SLOW["swap_scan_ts"]=time.time()
    finally:
        SLOW["swap_scan_busy"]=False

def maybe_swap_scan(swap_used,sin_rate,sout_rate):
    now=time.time(); trigger=swap_used>=1024**3 or sin_rate>=1024**2 or sout_rate>=1024**2
    if not trigger or SLOW.get("swap_scan_busy") or now-SLOW.get("swap_scan_ts",0)<30: return
    _cpu,mem=SLOW.get("procs",([],[]))
    if not mem: return
    SLOW["swap_scan_busy"]=True
    threading.Thread(target=_swap_scan,args=(mem,),daemon=True).start()

def refresh_slow(force=False):
    now=time.time()
    if force or now-SLOW["ts"]>=6:
        SLOW["procs"]=process_top(); SLOW["ts"]=now
    if force or now-SLOW.get("bts",0)>=30:
        SLOW["battery"]=battery_info(); SLOW["thermal"]=thermal_info(); SLOW["bts"]=now
    if force or now-SLOW.get("mts",0)>=15:
        SLOW["mem_pressure"]=memory_pressure_info(); SLOW["mts"]=now
    if force or now-SLOW.get("fts",0)>=5:
        SLOW["fans"]=smc_fans(); SLOW["fts"]=now

# ----------------------------- doctor -----------------------------
def doctor():
    refresh_slow(True)
    rows=[
      (T["model"],f"{MODEL_NAME} · {MODEL}"), (T["chip"],CHIP), ("macOS",f"{SWVERS or '--'} ({SWBUILD or '--'})"),
      (T["cores"],f"CPU {NCPU} {T['logical']} · GPU {GPU_CORES or '?'}"), (T["ram"],human_bytes(MEMTOTAL)),
      ("Architecture",ARCH), (T["python"],sys.version.split()[0]),
      (T["ioreport"],f"{T['ok']} ({', '.join(SUBS)})" if SUBS else T["missing"]),
      (T["dvfs"],f"CPU {sum(bool(v) for v in CPU_LADDERS.values())}/{max(1,len(CPU_LADDERS))}, GPU {'✓' if GPU_LADDER else '×'}"),
      ("footprint",T["ok"] if os.path.exists("/usr/bin/footprint") else T["missing"]),
      (T["battery_present"],T["ok"] if SLOW["battery"].get("present") else T["missing"]),
      (T["fan"],(f"{len(SLOW.get('fans') or [])} detected" if SLOW.get("fans") else (T["fanless"] if ARCH=="arm64" and "MacBook Air" in MODEL_NAME else T["missing"]))),
    ]
    print(f"\n{B}{CYN}⚡ SysMon One v{VERSION} · {T['doctor']}{RST}")
    print(DIM+"─"*68+RST)
    for k,v in rows: print(f"  {k:<16} {v}")
    print(DIM+"─"*68+RST)
    print(f"  CPU topology: {', '.join(c[0] for c in CORES) if CORES else 'N/A'}")
    print(f"  Clusters:     {', '.join(c[1] for c in COMPLEXES) if COMPLEXES else 'N/A'}")
    print(f"  DVFS tables:  {len(DT)} candidates discovered")
    print()

if A.doctor:
    doctor(); raise SystemExit(0)

# ----------------------------- Storage Doctor -----------------------------
# Philosophy: green items are reconstructible caches/diagnostics only. Yellow items are
# measured and explained but NEVER auto-deleted. Personal files remain outside the delete path.
HOME=os.path.expanduser("~")

def du_bytes(path, timeout=20):
    try:
        if not os.path.lexists(path): return 0
        if os.path.isfile(path) or os.path.islink(path): return os.path.getsize(path)
        out=sh(["/usr/bin/du","-sk",path],timeout).splitlines()
        if out:
            return int(out[-1].split()[0])*1024
    except Exception: pass
    return 0

def du_many(paths, timeout=30):
    paths=[p for p in paths if os.path.lexists(p)]
    if not paths: return []
    try:
        r=subprocess.run(["/usr/bin/du","-sk"]+paths,capture_output=True,text=True,timeout=timeout)
        rows=[]
        for line in r.stdout.splitlines():
            m=re.match(r"\s*(\d+)\s+(.+)$",line)
            if m: rows.append((int(m.group(1))*1024,m.group(2)))
        return rows
    except Exception:
        return [(du_bytes(p,4),p) for p in paths]

def path_label(path):
    p=os.path.expanduser(path)
    try:
        if p.startswith(HOME+os.sep): return "~/"+os.path.relpath(p,HOME)
    except Exception: pass
    return p

def files_by_rule(roots, exts=None, min_size=0, older_days=None, deadline=None, excludes=()):
    now=time.time(); out=[]; total=0; cutoff=now-(older_days*86400 if older_days else 0)
    exts={x.lower() for x in (exts or [])}; exabs=[os.path.abspath(os.path.expanduser(x)) for x in excludes]
    for root in roots:
        root=os.path.expanduser(root)
        if not os.path.isdir(root): continue
        for dp,dns,fns in os.walk(root,followlinks=False):
            if deadline and time.time()>deadline: return total,out
            adp=os.path.abspath(dp)
            dns[:]=[d for d in dns if not any(os.path.abspath(os.path.join(dp,d))==x or os.path.abspath(os.path.join(dp,d)).startswith(x+os.sep) for x in exabs)]
            for fn in fns:
                if deadline and time.time()>deadline: return total,out
                fp=os.path.join(dp,fn)
                try:
                    if os.path.islink(fp): continue
                    st=os.stat(fp)
                    if st.st_size<min_size: continue
                    if older_days and st.st_mtime>=cutoff: continue
                    if exts and Path(fn).suffix.lower() not in exts: continue
                    total+=st.st_size; out.append((st.st_size,fp,st.st_mtime))
                except Exception: pass
    out.sort(reverse=True,key=lambda x:x[0])
    return total,out

def process_running(name):
    try:
        r=subprocess.run(["/usr/bin/pgrep","-x",name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=2)
        return r.returncode==0
    except Exception: return False

def storage_rules(scan_details=True):
    # Explicit cache roots are excluded from generic old-cache scan to avoid double counting.
    explicit=[
      os.path.join(HOME,"Library/Caches/Homebrew"),
      os.path.join(HOME,"Library/Caches/pip"),
      os.path.join(HOME,".cache/pip"),
      os.path.join(HOME,".npm/_cacache"),
      os.path.join(HOME,"Library/Caches/go-build"),
      os.path.join(HOME,"Library/Developer/Xcode/DerivedData"),
    ]
    safe=[]
    def add_safe(key,label,path,kind="all",days=None,note="",blocked=False):
        path=os.path.expanduser(path)
        if kind=="old":
            size,_=files_by_rule([path],older_days=days or 30,deadline=time.time()+8,excludes=explicit)
        else: size=du_bytes(path,12)
        if size>0: safe.append({"key":key,"label":label,"path":path,"kind":kind,"days":days,"size":size,"note":note,"blocked":blocked})
    add_safe("xcode", "Xcode DerivedData", explicit[5], note=("请先关闭 Xcode" if LANG=="zh" else "close Xcode first"), blocked=process_running("Xcode"))
    add_safe("brew", "Homebrew Cache", explicit[0])
    add_safe("pip1", "pip Cache", explicit[1])
    add_safe("pip2", "pip Cache (~/.cache)", explicit[2])
    add_safe("npm", "npm Cache", explicit[3])
    add_safe("go", "Go Build Cache", explicit[4])
    add_safe("crash", "Crash Reports 14d+" if LANG=="en" else "崩溃报告 14天+", os.path.join(HOME,"Library/Logs/DiagnosticReports"), kind="old", days=14)
    add_safe("appcache", "App Cache 30d+" if LANG=="en" else "应用缓存 30天+", os.path.join(HOME,"Library/Caches"), kind="old", days=30)

    review=[]
    def add_review(label,path,note=""):
        path=os.path.expanduser(path); size=du_bytes(path,15)
        if size>0: review.append({"label":label,"path":path,"size":size,"note":note})
    add_review("Trash" if LANG=="en" else "废纸篓", os.path.join(HOME,".Trash"), "manual only" if LANG=="en" else "仅人工确认")
    add_review("Downloads", os.path.join(HOME,"Downloads"), "personal files" if LANG=="en" else "个人文件")
    add_review("iPhone/iPad Backups" if LANG=="en" else "iPhone/iPad 备份", os.path.join(HOME,"Library/Application Support/MobileSync/Backup"), "backup data")
    add_review("Xcode Archives", os.path.join(HOME,"Library/Developer/Xcode/Archives"), "keep for distribution/symbolication")
    add_review("Docker Data", os.path.join(HOME,"Library/Containers/com.docker.docker/Data"), "containers/images; never auto-delete")
    for label,path in [
      ("Ollama Models",os.path.join(HOME,".ollama/models")),
      ("Hugging Face Models",os.path.join(HOME,".cache/huggingface")),
      ("Hugging Face Models",os.path.join(HOME,"Library/Caches/huggingface")),
      ("LM Studio Models",os.path.join(HOME,".lmstudio/models")),
      ("LM Studio Models",os.path.join(HOME,"Library/Application Support/LM Studio/models")),
    ]: add_review(label,path,"model assets; not garbage")

    detail={"installers":[],"large":[],"apps":[],"home":[]}
    if scan_details:
        downloads=os.path.join(HOME,"Downloads")
        _it,installers=files_by_rule([downloads],exts={".dmg",".pkg",".zip",".rar",".7z",".iso",".tar",".gz",".xz"},deadline=time.time()+5)
        detail["installers"]=installers[:10]
        roots=[os.path.join(HOME,x) for x in ("Downloads","Desktop","Documents","Movies")]
        _lt,large=files_by_rule(roots,min_size=1024**3,deadline=time.time()+7)
        detail["large"]=large[:10]
        apps=[]
        for base in ("/Applications",os.path.join(HOME,"Applications")):
            try:
                apps += [os.path.join(base,x) for x in os.listdir(base) if x.endswith(".app")]
            except Exception: pass
        detail["apps"]=sorted(du_many(apps,30),reverse=True)[:10]
        hpaths=[os.path.join(HOME,x) for x in ("Downloads","Documents","Desktop","Movies","Music","Pictures")]
        detail["home"]=sorted(du_many(hpaths,25),reverse=True)
    return safe,review,detail

def _remove_all_contents(path):
    removed=0; errors=0
    if not os.path.isdir(path): return 0,0
    try: entries=list(os.scandir(path))
    except Exception: return 0,1
    for e in entries:
        try:
            try: sz=du_bytes(e.path,5)
            except Exception: sz=0
            if e.is_symlink(): os.unlink(e.path)
            elif e.is_dir(follow_symlinks=False): shutil.rmtree(e.path)
            else: os.unlink(e.path)
            removed+=sz
        except Exception: errors+=1
    return removed,errors

def _remove_old_files(path,days,excludes=()):
    removed=0; errors=0; cutoff=time.time()-days*86400
    exabs=[os.path.abspath(os.path.expanduser(x)) for x in excludes]
    if not os.path.isdir(path): return 0,0
    for dp,dns,fns in os.walk(path,topdown=False,followlinks=False):
        adp=os.path.abspath(dp)
        if any(adp==x or adp.startswith(x+os.sep) for x in exabs): continue
        for fn in fns:
            fp=os.path.join(dp,fn)
            try:
                if os.path.islink(fp): continue
                st=os.stat(fp)
                if st.st_mtime<cutoff:
                    os.unlink(fp); removed+=st.st_size
            except Exception: errors+=1
        try:
            if dp!=path and not os.listdir(dp): os.rmdir(dp)
        except Exception: pass
    return removed,errors

def clean_green(safe):
    explicit=[os.path.join(HOME,"Library/Caches/Homebrew"),os.path.join(HOME,"Library/Caches/pip"),os.path.join(HOME,".cache/pip"),os.path.join(HOME,".npm/_cacache"),os.path.join(HOME,"Library/Caches/go-build"),os.path.join(HOME,"Library/Developer/Xcode/DerivedData")]
    before=shutil.disk_usage(HOME).free; removed=0; errors=0; skipped=[]
    for item in safe:
        if item.get("blocked"):
            skipped.append(item["label"]); continue
        if item["kind"]=="old":
            ex=explicit if item["key"]=="appcache" else ()
            r,e=_remove_old_files(item["path"],item.get("days") or 30,ex)
        else: r,e=_remove_all_contents(item["path"])
        removed+=r; errors+=e
    try: after=shutil.disk_usage(HOME).free
    except Exception: after=before
    return removed,max(0,after-before),errors,skipped

def storage_report(scan_details=True):
    print(f"\n{B}{CYN}⚡ SysMon One v{VERSION} · {T['storage']}{RST}")
    print(f"{DIM}{T['storage_scan']}{RST}")
    total,used,free=shutil.disk_usage(HOME); pct=100.0*used/total if total else 0
    safe,review,detail=storage_rules(scan_details)
    safe_total=sum(x["size"] for x in safe if not x.get("blocked"))
    # Review total intentionally avoids sub-items such as installer/large-file lists, which overlap Downloads.
    review_total=sum(x["size"] for x in review)
    pressure=RED if pct>=92 else (YEL if pct>=82 else GRN)
    print(DIM+"─"*78+RST)
    print(f"  {T['disk_used']:<18} {bar(pct,24)} {pressure}{pct:5.1f}%{RST}  {human_bytes(used)} / {human_bytes(total)}")
    print(f"  {T['free']:<18} {GRN if free/total>=.15 else YEL}{human_bytes(free)}{RST}")
    print(f"  {T['reclaim']:<18} {GRN}{human_bytes(safe_total)}{RST}   {T['review_space']}: {YEL}{human_bytes(review_total)}{RST}")
    print(DIM+"─"*78+RST)
    print(f"{B}{GRN}  ✓ {T['safe_free']}{RST}")
    if not safe: print(f"    {DIM}{'没有发现明显可清理的绿色项目' if LANG=='zh' else 'No meaningful green items found.'}{RST}")
    for x in sorted(safe,key=lambda z:z['size'],reverse=True):
        mark=(YEL+"!"+RST) if x.get("blocked") else (GRN+"✓"+RST)
        note=(f" · {x['note']}" if x.get('note') else "")
        print(f"    {mark} {x['label']:<24} {human_bytes(x['size']):>9}  {DIM}{path_label(x['path'])}{note}{RST}")
    print(f"\n{B}{YEL}  ⚠ {T['review']}{RST}")
    if not review: print(f"    {DIM}{'没有发现明显的大型人工检查项' if LANG=='zh' else 'No large review items found.'}{RST}")
    for x in sorted(review,key=lambda z:z['size'],reverse=True):
        print(f"    {YEL}⚠{RST} {x['label']:<24} {human_bytes(x['size']):>9}  {DIM}{path_label(x['path'])}{RST}")
    print(f"\n{B}{RED}  ✗ {T['protected']}{RST}")
    prot=("桌面 / 文稿 / 照片图库 / iCloud Drive / 邮件 / 信息 / 项目文件" if LANG=="zh" else "Desktop / Documents / Photos Library / iCloud Drive / Mail / Messages / project files")
    print(f"    {DIM}{prot}{RST}")
    print(f"    {DIM}{'这些数据不会进入自动删除路径。' if LANG=='zh' else 'These data never enter the automatic delete path.'}{RST}")
    if scan_details:
        if detail["home"]:
            print(f"\n{B}{CYN}  HOME MAP / 用户目录{RST}")
            print("    "+"  |  ".join(f"{os.path.basename(p) or p} {human_bytes(sz)}" for sz,p in detail["home"][:6]))
        if detail["apps"]:
            print(f"\n{B}{CYN}  {T['apps']}{RST}")
            for sz,p in detail["apps"][:8]: print(f"    {human_bytes(sz):>9}  {os.path.basename(p)}")
        if detail["installers"]:
            print(f"\n{B}{CYN}  {'安装包/压缩包 Top' if LANG=='zh' else 'Installer/archive Top'}{RST}  {DIM}{'只展示，不自动删' if LANG=='zh' else 'display only'}{RST}")
            for sz,p,_ in detail["installers"][:8]: print(f"    {human_bytes(sz):>9}  {path_label(p)}")
        if detail["large"]:
            print(f"\n{B}{CYN}  {T['largest']}{RST}  {DIM}≥1GB · {'只展示' if LANG=='zh' else 'display only'}{RST}")
            for sz,p,_ in detail["large"][:8]: print(f"    {human_bytes(sz):>9}  {path_label(p)}")
    print(DIM+"─"*78+RST)
    msg=("绿色=可重建缓存/诊断文件；黄色=可能很大，但由你判断。我们不会靠把个人文件叫‘垃圾’来制造数字。" if LANG=="zh" else "Green = reconstructible caches/diagnostics. Yellow = potentially large, but your decision. Personal files are never relabeled as 'junk' to inflate a number.")
    print(f"  {DIM}{msg}{RST}\n")
    return safe,review,detail

def storage_doctor(scan_only=False, from_monitor=False):
    safe,review,detail=storage_report(True)
    if scan_only or TTY_STREAM is None:
        return
    while True:
        if LANG=="zh":
            print(f"  {B}[1]{RST} 清理全部绿色安全项   {B}[2]{RST} 重新扫描   {B}[3]{RST} {'返回监控' if from_monitor else '退出'}")
            ans=tty_input("  选择 > ").strip().lower()
        else:
            print(f"  {B}[1]{RST} Clean all green safe items   {B}[2]{RST} Rescan   {B}[3]{RST} {'Back to monitor' if from_monitor else 'Exit'}")
            ans=tty_input("  Choose > ").strip().lower()
        if ans in ("3","q",""): return
        if ans=="2": safe,review,detail=storage_report(True); continue
        if ans!="1": continue
        candidates=[x for x in safe if not x.get("blocked")]
        total=sum(x["size"] for x in candidates)
        if not candidates:
            print("  "+("没有可清理的绿色项目。" if LANG=="zh" else "No green items to clean.")); continue
        print(f"  {YEL}{'即将删除可重建缓存/诊断文件' if LANG=='zh' else 'About to delete reconstructible cache/diagnostic files'}: {human_bytes(total)}{RST}")
        confirm=tty_input("  输入 y 确认 / type y to confirm > ").strip().lower()
        if confirm not in ("y","yes"): continue
        removed,freed,errors,skipped=clean_green(candidates)
        print(f"\n  {B}{GRN}✓ {T['clean_done']}{RST}: {'处理' if LANG=='zh' else 'processed'} {human_bytes(removed)} · {'实际可用空间增加' if LANG=='zh' else 'free-space delta'} {human_bytes(freed)}")
        if errors: print(f"  {YEL}{errors} {'项因权限/占用未删除' if LANG=='zh' else 'items could not be removed due to permissions/use'}{RST}")
        if skipped: print(f"  {YEL}{'跳过' if LANG=='zh' else 'Skipped'}: {', '.join(skipped)}{RST}")
        safe,review,detail=storage_report(False)

if A.clean or A.scan:
    storage_doctor(scan_only=A.scan,from_monitor=False)
    raise SystemExit(0)

# ----------------------------- Process Center -----------------------------
def all_processes():
    text=sh(["/bin/ps","-ww","-axo","pid=,ppid=,uid=,user=,pcpu=,rss=,command="],6); rows=[]
    for line in text.splitlines():
        p=line.strip().split(None,6)
        if len(p)<7: continue
        try:
            pid,ppid,uid=int(p[0]),int(p[1]),int(p[2]); user=p[3]; cpu=float(p[4]); rss=int(p[5])*1024; cmd=p[6]
            first=cmd.split(None,1)[0] if cmd else "?"; name=os.path.basename(first) or first
            rows.append({'pid':pid,'ppid':ppid,'uid':uid,'user':user,'cpu':cpu,'rss':rss,'name':name,'cmd':cmd})
        except Exception: pass
    return rows

HARD_PROTECTED={x.lower() for x in PROTECTED}|{'kernel_task','launchd'}
def proc_is_protected(r):
    n=(r.get('name') or '').lower(); cmd=(r.get('cmd') or '').lower()
    return r.get('pid',0)<=1 or n in HARD_PROTECTED or cmd.startswith(('/system/library/','/usr/libexec/','/usr/sbin/','/sbin/'))

def proc_line(r, indent=''):
    return f"{indent}{r['pid']:>6}  CPU {r['cpu']:>6.1f}%  RAM {human_bytes(r['rss']):>8}  {clip_plain(r['name'],22)}"

def show_process_tree(user_only=True, limit=90):
    rows=all_processes(); uid=os.getuid()
    if user_only: rows=[r for r in rows if r['uid']==uid]
    by={r['pid']:r for r in rows}; ch={}
    for r in rows: ch.setdefault(r['ppid'],[]).append(r)
    for v in ch.values(): v.sort(key=lambda x:(-x['cpu'],-x['rss'],x['pid']))
    roots=[r for r in rows if r['ppid'] not in by]
    roots.sort(key=lambda x:(-x['cpu'],-x['rss'],x['pid']))
    print(f"\n{B}{CYN}  {T['process_tree']}{' · 当前用户' if LANG=='zh' and user_only else (' · current user' if user_only else '')}{RST}")
    print(f"  {'PID':>6}  {'CPU':>10}  {'RAM':>12}  {'NAME' if LANG=='en' else '进程'}")
    count=0
    def walk(r,prefix='',last=True,depth=0):
        nonlocal count
        if count>=limit or depth>8: return
        branch=('└─ ' if last else '├─ ') if depth else ''
        print(proc_line(r,prefix+branch)); count+=1
        kids=ch.get(r['pid'],[])
        np=prefix+('   ' if last else '│  ') if depth else ''
        for i,k in enumerate(kids): walk(k,np,i==len(kids)-1,depth+1)
    for i,r in enumerate(roots):
        if count>=limit: break
        walk(r,'',i==len(roots)-1,0)
    if count>=limit: print(f"  {DIM}… {'仅显示前' if LANG=='zh' else 'showing first'} {limit}{RST}")

def search_processes(keyword=None):
    if keyword is None: keyword=tty_input("  搜索名称/命令 > " if LANG=='zh' else "  Search name/command > ").strip()
    if not keyword: return []
    q=keyword.lower(); rows=[r for r in all_processes() if q in r['name'].lower() or q in r['cmd'].lower()]
    rows.sort(key=lambda x:(-x['cpu'],-x['rss']))
    print(f"\n{B}{CYN}  {T['search']}: {keyword}{RST}  {DIM}({len(rows)} matches){RST}")
    for r in rows[:30]: print('  '+proc_line(r))
    if len(rows)>30: print(f"  {DIM}… +{len(rows)-30}{RST}")
    return rows

def terminate_process_dialog(pid=None):
    rows=all_processes(); by={r['pid']:r for r in rows}
    if pid is None:
        raw=tty_input("  输入 PID > " if LANG=='zh' else "  PID > ").strip()
        if not raw.isdigit(): return
        pid=int(raw)
    r=by.get(int(pid))
    if not r:
        print("  找不到该 PID。" if LANG=='zh' else "  PID not found."); return
    print('\n  '+proc_line(r)); print(f"  {DIM}{clip_plain(r['cmd'],max(40,width()-6))}{RST}")
    if r['pid'] in (os.getpid(),os.getppid()) or proc_is_protected(r):
        print(f"  {RED}{'受保护的系统/当前进程，拒绝结束。' if LANG=='zh' else 'Protected system/current process; termination refused.'}{RST}"); return
    if r['uid']!=os.getuid():
        print(f"  {YEL}{'不是当前用户进程；免 sudo 模式不处理。' if LANG=='zh' else 'Not owned by current user; no-sudo mode will not terminate it.'}{RST}"); return
    confirm=tty_input("  正常结束这个进程？输入 y > " if LANG=='zh' else "  Send TERM? type y > ").strip().lower()
    if confirm not in ('y','yes'): return
    try: os.kill(r['pid'],signal.SIGTERM)
    except Exception as e:
        print(f"  {RED}{'结束失败' if LANG=='zh' else 'Terminate failed'}: {e}{RST}"); return
    time.sleep(1.2)
    alive=True
    try: os.kill(r['pid'],0)
    except Exception: alive=False
    if not alive:
        print(f"  {GRN}✓ {'已正常结束' if LANG=='zh' else 'Terminated normally'}{RST}"); return
    print(f"  {YEL}{'进程仍在运行。强制 Kill 可能造成未保存数据丢失。' if LANG=='zh' else 'Process is still alive. Force kill may lose unsaved data.'}{RST}")
    force=tty_input("  强制 KILL？再次输入 y > " if LANG=='zh' else "  FORCE KILL? type y again > ").strip().lower()
    if force in ('y','yes'):
        try: os.kill(r['pid'],signal.SIGKILL); print(f"  {RED}✓ {'已强制结束' if LANG=='zh' else 'Force-killed'}{RST}")
        except Exception as e: print(f"  {RED}{e}{RST}")

def process_center():
    if TTY_STREAM is None: return
    while True:
        print(f"\n{B}{CYN}⚙ SysMon One · {T['process_center']}{RST}")
        if LANG=='zh':
            print("  [1] 当前用户进程树   [2] CPU/RAM Top20   [3] 搜索进程   [4] 结束进程 PID   [0] 返回")
        else:
            print("  [1] User process tree   [2] CPU/RAM Top20   [3] Search   [4] Terminate PID   [0] Back")
        a=tty_input("  选择 > " if LANG=='zh' else "  Choose > ").strip().lower()
        if a in ('0','q',''): return
        if a=='1': show_process_tree(True); continue
        if a=='2':
            rows=all_processes()
            print(f"\n{B}{CYN}  CPU Top20{RST}")
            for r in sorted(rows,key=lambda x:x['cpu'],reverse=True)[:20]: print('  '+proc_line(r))
            print(f"\n{B}{CYN}  RAM Top20{RST}")
            for r in sorted(rows,key=lambda x:x['rss'],reverse=True)[:20]: print('  '+proc_line(r))
            continue
        if a=='3': search_processes(); continue
        if a=='4': terminate_process_dialog(); continue

# ----------------------------- history + frame -----------------------------
HCPU=deque(maxlen=max(30,int(60/A.interval))); HGPU=deque(maxlen=HCPU.maxlen); HMEM=deque(maxlen=HCPU.maxlen); HPWR=deque(maxlen=HCPU.maxlen)
PEAK={"cpu":0.0,"gpu":0.0,"mem":0.0,"power":0.0,"sout":0.0,"disk":0.0,"net":0.0,"disk_total":0.0,"net_total":0.0,"swap_total":0.0,"frames":0}

def thermal_limit():
    m=re.search(r"CPU limit (\d+)%",SLOW.get("thermal","") or "")
    return int(m.group(1)) if m else 100

def pressure_index(d):
    if not MEMTOTAL: return 0
    mem=d["used"]/MEMTOTAL; avail=d["avail"]/MEMTOTAL; comp=d["comp"]/MEMTOTAL
    sout=d["rates"]["sout"]/1e6; sin=d["rates"]["sin"]/1e6; p=0.0
    p += max(0.0,min(28.0,(mem-0.72)/0.28*28.0))
    p += max(0.0,min(18.0,(0.16-avail)/0.16*18.0))
    p += max(0.0,min(16.0,(comp-0.10)/0.35*16.0))
    p += min(24.0,8.0*math.log10(1.0+max(0.0,sout)))
    p += min(6.0,2.5*math.log10(1.0+max(0.0,sin)))
    if d["cpu"]>90: p += min(4.0,(d["cpu"]-90)/10*4.0)
    mpl=SLOW.get("mem_pressure",{}).get("level",1)
    if mpl==2: p+=15
    elif mpl>=4: p+=30
    lim=thermal_limit()
    if lim<100: p += min(12.0,(100-lim)*0.4)
    return int(max(0,min(100,round(p))))

def pressure_label(p):
    if p<25: return (GRN,"COOL" if LANG=="en" else "轻松")
    if p<50: return (CYN,"BUSY" if LANG=="en" else "忙碌")
    if p<75: return (YEL,"PRESSURE" if LANG=="en" else "有压力")
    return (RED,"HOT" if LANG=="en" else "高压")

def core_insight(d):
    st,su,sf=d["swap"]; sout=d["rates"]["sout"]; sin=d["rates"]["sin"]; lim=thermal_limit()
    ctop,mtop=SLOW.get("procs",([],[]))
    top=ctop[0] if ctop else None
    sd=SLOW.get("swap_detail") or []
    mpl=SLOW.get("mem_pressure",{}).get("level",1)
    if mpl>=4:
        who=sd[0][3] if sd else (mtop[0][3] if mtop else "")
        return RED,(f"macOS 已报告内存压力 CRITICAL。{('优先正常退出 '+who+'；' if who else '')}这是该处理的时候，不是盯着已用内存百分比发呆。" if LANG=="zh" else f"macOS reports CRITICAL memory pressure. {('Quit '+who+' normally first; ' if who else '')}this is actionable pressure, not just a scary used-RAM percentage.")
    if mpl==2:
        who=sd[0][3] if sd else (mtop[0][3] if mtop else "")
        return YEL,(f"macOS 已报告内存压力 WARN。{('先检查 '+who+'；' if who else '')}观察 Swap-out 是否持续上升。" if LANG=="zh" else f"macOS reports WARN memory pressure. {('Inspect '+who+' first; ' if who else '')}watch whether swap-out keeps rising.")
    if lim<90:
        return RED,(f"CPU 已触发明显热限频（{lim}%）。先看散热/环境，再追进程。" if LANG=="zh" else f"CPU is thermally limited to {lim}%. Check cooling/environment before blaming a process.")
    if sout>=20*1024**2:
        who=sd[0][3] if sd else (mtop[0][3] if mtop else "")
        return RED,(f"正在大量写出 Swap：{rate(sout)}。{('优先正常退出 '+who+'；' if who else '')}不要先重启，更不要乱杀系统进程。" if LANG=="zh" else f"Active swap-out is high: {rate(sout)}. {('Quit '+who+' normally first; ' if who else '')}do not randomly kill system processes.")
    if sout>=2*1024**2 or (MEMTOTAL and d["avail"]/MEMTOTAL<0.06):
        who=sd[0][3] if sd else (mtop[0][3] if mtop else "")
        return YEL,(f"内存压力正在发生。Swap-out {rate(sout)}，可先检查 {who or '内存 Top 进程'}。" if LANG=="zh" else f"Memory pressure is active. Swap-out {rate(sout)}; inspect {who or 'the top memory processes'} first.")
    if su>=max(2*1024**3,(MEMTOTAL*0.10 if MEMTOTAL else 0)) and sout<512*1024:
        return GRN,(f"Swap 存量 {human_bytes(su)} 看着吓人，但当前换出仅 {rate(sout)}：多半是历史存量，没必要为了清零去 kill。" if LANG=="zh" else f"Swap stock is {human_bytes(su)}, but current swap-out is only {rate(sout)}. This is often historical; don't kill apps just to make swap zero.")
    if d["cpu"]>=92 and top:
        return YEL,(f"CPU 接近满载，当前第一名是 {top[3]} #{top[0]}（{top[1]:.0f}%）。高负载不等于故障，确认它是不是你正在做的事。" if LANG=="zh" else f"CPU is near full load. Top process: {top[3]} #{top[0]} ({top[1]:.0f}%). High load is not automatically a fault.")
    if d["rates"]["wr"]>=250*1024**2:
        return YEL,(f"磁盘正在高速写入 {rate(d['rates']['wr'])}，如果不是拷贝/编译/下载，值得查一下。" if LANG=="zh" else f"Disk writes are high at {rate(d['rates']['wr'])}; inspect if you are not copying/building/downloading.")
    batt=SLOW.get("battery",{})
    if batt.get("state")=="discharging" and abs(batt.get("watts",0))>=25:
        return YEL,(f"电池正在以约 {abs(batt['watts']):.1f}W 放电，属于明显高耗电状态。" if LANG=="zh" else f"Battery draw is about {abs(batt['watts']):.1f}W, a clearly high-drain state.")
    return GRN,("当前没有需要你立刻处理的核心异常。别为了几个漂亮的零，把正常系统优化成事故现场。" if LANG=="zh" else "No core issue needs immediate action. Do not optimize a healthy Mac into an incident just to chase pretty zeros.")

def usage_delta(prev,cur):
    out={}
    for i,c in enumerate(cur[:NCPU]):
        if i>=len(prev): continue
        p=prev[i]; dt=sum(c)-sum(p); busy=(c[0]+c[1]+c[3])-(p[0]+p[1]+p[3])
        if dt>0: out[i]=max(0.0,min(100.0,100.0*busy/dt))
    return out

def mem_stats(pages,psize):
    g=lambda *ks:sum(pages.get(k,0) for k in ks)*psize
    comp=g("Pages occupied by compressor")
    avail=g("Pages free","Pages inactive","Pages speculative")
    active=g("Pages active","Pages wired down","Pages occupied by compressor")
    used=max(active, MEMTOTAL-avail if MEMTOTAL else active)
    if MEMTOTAL: used=min(MEMTOTAL,used)
    return used,avail,comp

def sensor_for_cluster(vt,cl):
    idx=cl[1:] or "0"; prefs=[("EACC" if cl.startswith("E") else "PACC")+idx, cl]
    for p in prefs:
        for k,v in vt.items():
            if (k or "").startswith(p): return v
    return None

def sample(prev):
    start=time.time(); a=snapshot() if SUBS else {}; ticks0=prev["ticks"]
    time.sleep(A.interval)
    b=snapshot() if SUBS else {}; dt=max(1e-3,time.time()-start); dd=deltas(a,b) if a and b else {}
    try:
        cf,xf,vt,gpu,en=parse_io(dd,b) if dd else ({},{},{},{"active":0.0,"clock":0.0,"effective":0.0,"dom":"--"},{})
    finally:
        release_map(dd); release_map(a); release_map(b)
    ticks=cpu_ticks(); use=usage_delta(ticks0,ticks); cpu=sum(use.values())/len(use) if use else 0.0
    pw=power_delta(prev.get("energy",{}),en,dt)
    pages,psize,rx,tx,rd,wr,sw=fast_counters(); used,avail,comp=mem_stats(pages,psize)
    st,su,sf=sw
    sin=pages.get("Swapins",pages.get("Swapins ",0)); sout=pages.get("Swapouts",pages.get("Swapouts ",0))
    rates={
      "rx":max(0,rx-prev["rx"])/dt, "tx":max(0,tx-prev["tx"])/dt,
      "rd":max(0,rd-prev["rd"])/dt, "wr":max(0,wr-prev["wr"])/dt,
      "sin":max(0,sin-prev["sin"])*psize/dt, "sout":max(0,sout-prev["sout"])*psize/dt,
    }
    mp=100.0*used/MEMTOTAL if MEMTOTAL else 0.0; totalp=sum(v for v in pw.values() if 0<=v<1000)
    HCPU.append(cpu); HGPU.append(gpu["active"]); HMEM.append(mp); HPWR.append(totalp)
    refresh_slow(False)
    PEAK["frames"]+=1; PEAK["cpu"]=max(PEAK["cpu"],cpu); PEAK["gpu"]=max(PEAK["gpu"],gpu["active"]); PEAK["mem"]=max(PEAK["mem"],mp)
    PEAK["power"]=max(PEAK["power"],totalp); PEAK["sout"]=max(PEAK["sout"],rates["sout"]); PEAK["disk"]=max(PEAK["disk"],rates["rd"]+rates["wr"]); PEAK["net"]=max(PEAK["net"],rates["rx"]+rates["tx"])
    PEAK["disk_total"]+=(rates["rd"]+rates["wr"])*dt; PEAK["net_total"]+=(rates["rx"]+rates["tx"])*dt; PEAK["swap_total"]+=rates["sout"]*dt
    maybe_swap_scan(su,rates["sin"],rates["sout"])
    data={"dt":dt,"cpu":cpu,"use":use,"cf":cf,"xf":xf,"vt":vt,"gpu":gpu,"pw":pw,"used":used,"avail":avail,"comp":comp,
          "swap":(st,su,sf),"rates":rates,"pages":pages,"collector_ms":(time.time()-start-dt)*1000.0}
    state={"ticks":ticks,"energy":en,"rx":rx,"tx":tx,"rd":rd,"wr":wr,"sin":sin,"sout":sout}
    return data,state

def line_cluster(cl,xf,vt):
    f=xf.get(cl,0); sv=sensor_for_cluster(vt,cl)
    if sv and sv[2]>=0.02:
        v,t,_=sv; return f"{WHT}{cl:>2}{RST} {CYN}{f:5.0f}MHz{RST}  {MAG}{v:4.0f}mV{RST}  {temp_hue(t)}{t:4.0f}°C{RST}"
    return f"{WHT}{cl:>2}{RST} {CYN}{f:5.0f}MHz{RST}  {DIM}{T['voltage']} N/A  {T['temp']} N/A{RST}"

def render(d):
    now=time.time(); la=os.getloadavg() if hasattr(os,"getloadavg") else (0,0,0); w=max(72,min(width(),140)); out=[]; add=out.append
    add(f"{B}{CYN}  ⚡ {T['title']} v{VERSION}{RST}  {DIM}{T['subtitle']}{RST}   {time.strftime('%Y-%m-%d %H:%M:%S')}")
    gpu_txt=f" · GPU {GPU_CORES}C" if GPU_CORES else ""
    add(f"{WHT}  {MODEL_NAME}{RST} {DIM}({MODEL}){RST} · {CHIP} · CPU {NCPU}C{gpu_txt} · {human_bytes(MEMTOTAL)}")
    add(f"{DIM}  macOS {SWVERS or '--'} ({SWBUILD or '--'}) · {ARCH} · {T['uptime']} {uptime_text(now-BOOT)} · {T['load']} {la[0]:.2f} {la[1]:.2f} {la[2]:.2f}{RST}")
    p=pressure_index(d); pc,pl=pressure_label(p); head=max(0,100-p); ic,msg=core_insight(d)
    add(f"{B}{CYN}  {T['pressure']}{RST} {pc}{p:3d}/100 {pl}{RST} · {T['headroom']} {GRN if head>=60 else (YEL if head>=30 else RED)}{head:3d}/100{RST}  {DIM}({T['pressure_note']}){RST}")
    add(f"{B}{MAG}  ✦ {T['insight']}{RST}")
    for mi,mline in enumerate(wrap_plain(msg,max(34,w-8),3)):
        add(f"      {ic}{mline}{RST}")
    add(DIM+"  "+"─"*(w-4)+RST)

    # CPU — one core per row. Humans like numbers when they stop fighting for the same line.
    add(f"{B}{CYN}  {T['cpu']}{RST}  {bar(d['cpu'],18)} {hue(d['cpu'])}{d['cpu']:5.1f}%{RST}   {T['total']}")
    if not A.compact:
        iomap=[c[0] for c in CORES]
        nshow=len(d["use"]) if A.expert else min(len(d["use"]),16)
        eidx=pidx=0
        for j in range(nshow):
            nm=iomap[j] if j<len(iomap) else ""; cl=core_cluster(nm)
            if cl.startswith("E"): lab=f"E{eidx}"; eidx+=1
            elif cl.startswith("P"): lab=f"P{pidx}"; pidx+=1
            else: lab=f"C{j}"
            u=d["use"].get(j,0); f=d["cf"].get(nm,0)
            freq=(f"{f:.0f}MHz" if f else "--")
            add(f"      {WHT}{lab:<3}{RST} {bar(u,12)}  {hue(u)}{u:5.1f}%{RST}   {CYN}{freq:>8}{RST}")
        if len(d["use"])>nshow: add(f"      {DIM}+{len(d['use'])-nshow} cores hidden; use --expert{RST}")
        if d["xf"]:
            add(f"{B}{CYN}  {T['cluster']}{RST}   "+"   ".join(line_cluster(cl,d["xf"],d["vt"]) for cl in sorted(d["xf"],key=natkey)))

    # GPU
    g=d["gpu"]
    add(f"{B}{CYN}  {T['gpu']}{RST}  {T['active']} {bar(g['active'],14)} {hue(g['active'])}{g['active']:5.1f}%{RST}  "
        f"{T['clock']} {CYN}{g['clock']:6.0f}MHz{RST}  {T['effective']} {CYN}{g['effective']:6.0f}MHz{RST}  {DIM}{g['dom']}{RST}")

    # memory / swap / IO
    mp=100.0*d["used"]/MEMTOTAL if MEMTOTAL else 0; st,su,sf=d["swap"]; sp=100.0*su/st if st else 0
    mpl=SLOW.get("mem_pressure",{}).get("level"); mpname=("NORMAL" if mpl==1 else ("WARN" if mpl==2 else ("CRITICAL" if mpl and mpl>=4 else "--")))
    mpc=GRN if mpl==1 else (YEL if mpl==2 else (RED if mpl and mpl>=4 else DIM))
    add(f"{B}{CYN}  {T['memory']}{RST} {bar(mp,16)} {hue(mp)}{mp:5.1f}%{RST}  {human_bytes(d['used'])}/{human_bytes(MEMTOTAL)}  "
        f"{T['available']} {human_bytes(d['avail'])}  {T['compressed']} {human_bytes(d['comp'])}  MP {mpc}{mpname}{RST}")
    add(f"{B}{CYN}  {T['swap']}{RST}   {bar(sp,16)} {hue(sp,50,80)}{sp:5.1f}%{RST}  {human_bytes(su)}/{human_bytes(st)}  "
        f"{T['swapin']} {CYN}{rate(d['rates']['sin'])}{RST}  {T['swapout']} {CYN}{rate(d['rates']['sout'])}{RST}")
    add(f"{B}{CYN}  {T['disk']}{RST}   {T['read']} {CYN}{rate(d['rates']['rd']):>11}{RST}  {T['write']} {CYN}{rate(d['rates']['wr']):>11}{RST}     "
        f"{B}{CYN}{T['network']}{RST}  {T['down']} {CYN}{rate(d['rates']['rx']):>11}{RST}  {T['up']} {CYN}{rate(d['rates']['tx']):>11}{RST}")

    # power/battery
    cpuw=pfind(d["pw"],"CPU"); gpuw=pfind(d["pw"],"GPU"); anep=pfind(d["pw"],"ANE"); dram=pfind(d["pw"],"DRAM")
    if d["pw"]:
        add(f"{B}{CYN}  {T['power']}{RST}  CPU {YEL}{cpuw:5.2f}W{RST}  GPU {YEL}{gpuw:5.2f}W{RST}  ANE {YEL}{anep:5.2f}W{RST}  DRAM {YEL}{dram:5.2f}W{RST}")
    batt=SLOW["battery"]
    if batt.get("present"):
        state=T.get(batt.get("state","unknown"),T["unknown"]); extra=[]
        if "health" in batt: extra.append(f"{T['health']} {batt['health']:.0f}%")
        if "CycleCount" in batt: extra.append(f"{T['cycles']} {batt['CycleCount']}")
        if "watts" in batt: extra.append(f"{batt['watts']:+.1f}W")
        add(f"{B}{CYN}  {T['battery']}{RST} {batt.get('pct','--')}% · {state} · "+" · ".join(extra)+f"   {T['thermal']} {SLOW['thermal']}")
    fans=SLOW.get("fans") or []
    if fans:
        ftxt=[]
        for f in fans:
            rng=(f"/{f['max']:.0f}" if f.get('max') else "")
            ftxt.append(f"F{f['id']} {f['rpm']:.0f}{rng} RPM")
        add(f"{B}{CYN}  {T['fan']}{RST}   "+" · ".join(ftxt))
    elif ARCH=="arm64" and "MacBook Air" in MODEL_NAME:
        add(f"{B}{CYN}  {T['fan']}{RST}   {DIM}{T['fanless']}{RST}")

    if not A.compact:
        add(DIM+"  "+"─"*(w-4)+RST)
        add(f"{B}{CYN}  {T['history']}{RST}  CPU {spark(HCPU,100)}  GPU {spark(HGPU,100)}  MEM {spark(HMEM,100)}")
        add(f"{B}{CYN}  {T['peak']}{RST}  CPU {PEAK['cpu']:.0f}% · GPU {PEAK['gpu']:.0f}% · MEM {PEAK['mem']:.0f}% · PWR {PEAK['power']:.1f}W · SWAP↑ {rate(PEAK['sout'])}")
        add(f"{DIM}        "+((f"本次累计: 磁盘 {human_bytes(PEAK['disk_total'])} · 网络 {human_bytes(PEAK['net_total'])} · Swap写出 {human_bytes(PEAK['swap_total'])} · 样本 {PEAK['frames']}" ) if LANG=="zh" else (f"Session data: Disk {human_bytes(PEAK['disk_total'])} · Net {human_bytes(PEAK['net_total'])} · Swap-out {human_bytes(PEAK['swap_total'])} · samples {PEAK['frames']}"))+f"{RST}")
        ctop,mtop=SLOW["procs"]
        if ctop:
            def proc_cell(r,mem=False,rank=0):
                pid,cpu,rss,name,path,uid=r
                name=clip_plain(name,12); val=human_bytes(rss) if mem else f"{cpu:.0f}%"
                pidtxt=f" #{pid}" if A.expert else ""
                return f"{rank}. {pad_plain(name,12)} {val:>7}{pidtxt}"
            def add_two_col(title, rows, mem=False):
                add(f"{B}{CYN}  {title}{RST}")
                cells=[proc_cell(r,mem,i+1) for i,r in enumerate(rows[:5])]
                col=max(30,min(38,(w-8)//2))
                for i in range(0,len(cells),2):
                    left=pad_plain(cells[i],col)
                    right=cells[i+1] if i+1<len(cells) else ""
                    add("      "+left+("  "+right if right else ""))
            add_two_col(f"TOP5 · {T['procs_cpu']}",ctop,False)
            add_two_col(f"TOP5 · {T['procs_mem']}",mtop,True)
        sd=SLOW.get("swap_detail") or []
        if SLOW.get("swap_scan_busy"):
            add(f"{B}{CYN}  {T['swap_top']}{RST}  {DIM}{T['scanning']}…{RST}")
        elif sd:
            add(f"{B}{CYN}  {T['swap_top']}{RST}")
            cells=[]
            for i,r in enumerate(sd[:5]):
                pid,cpu,rss,name,path,uid,sw=r
                name=clip_plain(name,10); advice=process_advice(r)
                cells.append(f"{i+1}. {pad_plain(name,10)} {human_bytes(sw):>7} {advice}")
            col=max(30,min(38,(w-8)//2))
            for i in range(0,len(cells),2):
                left=pad_plain(cells[i],col); right=cells[i+1] if i+1<len(cells) else ""
                add("      "+left+("  "+right if right else ""))
            note=("footprint 的 Swapped=压缩/换出的进程内存，不等同于精确磁盘 Swap。" if LANG=="zh" else "footprint Swapped = compressed/swapped process memory, not exact disk-swap bytes.")
            add(f"{DIM}      {clip_plain(note,max(30,w-6))}{RST}")

    if A.expert:
        if d["vt"]:
            sensors=[]
            for k,(v,t,active) in sorted(d["vt"].items()):
                if active>=0.02: sensors.append(f"{k}:{v:.0f}mV/{t:.0f}°C")
            if sensors: add(f"{DIM}  Sensors: "+" · ".join(sensors)+RST)
        if d["pw"]:
            add(f"{DIM}  Energy rails: "+" · ".join(f"{k}={v:.2f}W" for k,v in sorted(d["pw"].items()) if 0<=v<1000)+RST)
        add(f"{DIM}  Topology: "+", ".join(c[0]+"→"+c[1] for c in CORES)+RST)
        add(f"{DIM}  {T['note_gpu']}{RST}")

    add(DIM+"  "+"─"*(w-4)+RST)
    src="Mach + vm_stat/netstat/IOKit counters" + (" + IOReport" if SUBS else "")
    add(f"{DIM}  {T['source']}: {src} · {A.interval:.1f}s · {T['exit']} · C: {T['storage']} · P: {T['process_center']} · /: {T['search']} · Q: quit{RST}")
    return "\n".join(out)

# ----------------------------- main -----------------------------
TTY_OLD=None
def tty_enter():
    global TTY_OLD
    if A.plain or TTY_STREAM is None: return
    try:
        import termios, tty
        fd=TTY_STREAM.fileno()
        if TTY_OLD is None: TTY_OLD=termios.tcgetattr(fd)
        tty.setcbreak(fd)
    except Exception: pass

def tty_restore():
    global TTY_OLD
    if TTY_OLD is None: return
    try:
        import termios
        termios.tcsetattr(TTY_STREAM.fileno(),termios.TCSADRAIN,TTY_OLD)
    except Exception: pass

def read_key():
    if A.plain or TTY_STREAM is None: return ""
    try:
        import select
        fd=TTY_STREAM.fileno()
        r,_,_=select.select([fd],[],[],0)
        if r:
            return os.read(fd,1).decode("utf-8","ignore").lower()
    except Exception: pass
    return ""

def cleanup(*_):
    tty_restore()
    if not A.plain:
        sys.stdout.write(ESC+"?25h"+RST+"\n")
    sys.stdout.flush(); raise SystemExit(0)
signal.signal(signal.SIGINT,cleanup); signal.signal(signal.SIGTERM,cleanup)

def baseline():
    ticks=cpu_ticks(); a=snapshot() if SUBS else {}; time.sleep(0.25); b=snapshot() if SUBS else {}; dd=deltas(a,b) if a and b else {}
    try: _cf,_xf,_vt,_g,en=parse_io(dd,b) if dd else ({},{},{},{},{})
    finally: release_map(dd); release_map(a); release_map(b)
    pages,psize,rx,tx,rd,wr,_sw=fast_counters(); sin=pages.get("Swapins",0); sout=pages.get("Swapouts",0)
    refresh_slow(True)
    return {"ticks":ticks,"energy":en,"rx":rx,"tx":tx,"rd":rd,"wr":wr,"sin":sin,"sout":sout}

def main():
    if not A.plain:
        sys.stdout.write(ESC+"?25l"+ESC+"2J"+ESC+"H"+f"  ⚡ {T['title']} v{VERSION} · {T['init']}\n"); sys.stdout.flush()
    st=baseline(); n=0; tty_enter()
    while True:
        d,st=sample(st); text=render(d)
        if A.plain: print(text+"\n"+"="*90)
        else: sys.stdout.write(ESC+"H"+text+ESC+"J")
        sys.stdout.flush(); n+=1
        key=read_key()
        if key=="q": cleanup()
        if key=="c":
            tty_restore()
            if not A.plain: sys.stdout.write(ESC+"?25h"+ESC+"2J"+ESC+"H"); sys.stdout.flush()
            storage_doctor(scan_only=False,from_monitor=True)
            if not A.plain: sys.stdout.write(ESC+"?25l"+ESC+"2J"+ESC+"H"); sys.stdout.flush()
            tty_enter(); st=baseline()
        if key=="p":
            tty_restore()
            if not A.plain: sys.stdout.write(ESC+"?25h"+ESC+"2J"+ESC+"H"); sys.stdout.flush()
            process_center()
            if not A.plain: sys.stdout.write(ESC+"?25l"+ESC+"2J"+ESC+"H"); sys.stdout.flush()
            tty_enter(); st=baseline()
        if key=="/":
            tty_restore()
            if not A.plain: sys.stdout.write(ESC+"?25h"+ESC+"2J"+ESC+"H"); sys.stdout.flush()
            search_processes()
            tty_input("  按回车返回监控…" if LANG=="zh" else "  Press Enter to return…")
            if not A.plain: sys.stdout.write(ESC+"?25l"+ESC+"2J"+ESC+"H"); sys.stdout.flush()
            tty_enter(); st=baseline()
        if A.frames and n>=A.frames: break
    cleanup()

try:
    main()
except SystemExit:
    raise
except BaseException as e:
    if not A.plain: sys.stdout.write(ESC+"?25h"+RST+"\n")
    import traceback
    print("SysMon One error / 运行失败:\n"+traceback.format_exc()[-2500:])
    print("\nTry / 尝试: ./SysMon-One.command --doctor")
    try: input("Press Enter to close / 按回车关闭…")
    except Exception: pass
PYEOF
