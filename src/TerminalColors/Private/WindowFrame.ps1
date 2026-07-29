# Colouring the Windows Terminal window border through DWM.
#
# Windows Terminal exposes no API to recolour an existing window, but Windows 11
# allows the border colour of any window to be set (DWMWA_BORDER_COLOR, build
# 22000+). The terminal window is located by walking up the parent process chain.
#
# The interop type is compiled on first use only, so it never slows down the
# startup of PowerShell sessions.

$script:TcWindowHandle = [IntPtr]::Zero
$script:TcInteropReady = $false
$script:TcInteropFailed = $false

# Looking the window up enumerates every process (a CIM query, ~150 ms). On
# failure we back off, otherwise every directory change would pay that cost for
# nothing on a machine where the window stays unfindable.
$script:TcWindowLookupFailedAt = $null
$script:TcWindowLookupRetrySeconds = 30

$script:TcDwmaBorderColor = 34
$script:TcDwmaCaptionColor = 35
$script:TcDwmColorDefault = [int]-1        # 0xFFFFFFFF

function Initialize-TcInterop {
    [CmdletBinding()]
    param()

    if ($script:TcInteropReady) { return $true }
    if ($script:TcInteropFailed) { return $false }

    if ('TerminalColors.Native' -as [type]) {
        $script:TcInteropReady = $true
        return $true
    }

    $source = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace TerminalColors
{
    public static class Native
    {
        [DllImport("dwmapi.dll", PreserveSig = true)]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

        private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr hwnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int GetClassName(IntPtr hwnd, StringBuilder buffer, int size);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hwnd, StringBuilder buffer, int size);

        public static int SetAttributeColor(IntPtr hwnd, int attribute, int colorRef)
        {
            int value = colorRef;
            return DwmSetWindowAttribute(hwnd, attribute, ref value, 4);
        }

        public static string GetClass(IntPtr hwnd)
        {
            StringBuilder sb = new StringBuilder(256);
            GetClassName(hwnd, sb, sb.Capacity);
            return sb.ToString();
        }

        public static string GetTitle(IntPtr hwnd)
        {
            StringBuilder sb = new StringBuilder(1024);
            GetWindowText(hwnd, sb, sb.Capacity);
            return sb.ToString();
        }

        public static IntPtr[] GetProcessWindows(uint processId)
        {
            List<IntPtr> result = new List<IntPtr>();
            EnumWindows(delegate(IntPtr hwnd, IntPtr lParam)
            {
                uint pid;
                GetWindowThreadProcessId(hwnd, out pid);
                if (pid == processId && IsWindowVisible(hwnd))
                {
                    result.Add(hwnd);
                }
                return true;
            }, IntPtr.Zero);
            return result.ToArray();
        }
    }
}
'@

    try {
        Add-Type -TypeDefinition $source -ErrorAction Stop
        $script:TcInteropReady = $true
        return $true
    } catch {
        Write-Verbose "TerminalColors: interop unavailable ($($_.Exception.Message))"
        $script:TcInteropFailed = $true
        return $false
    }
}

function Get-TcParentProcessMap {
    <#
        .SYNOPSIS
        PID -> @{ Parent; Name } table, built with a single CIM query.
    #>
    [CmdletBinding()]
    param()

    $map = @{}
    try {
        $processes = Get-CimInstance -ClassName Win32_Process -Property ProcessId, ParentProcessId, Name -ErrorAction Stop
    } catch {
        try {
            $processes = Get-WmiObject -Class Win32_Process -Property ProcessId, ParentProcessId, Name -ErrorAction Stop
        } catch {
            Write-Verbose "TerminalColors: could not enumerate processes ($($_.Exception.Message))"
            return $map
        }
    }

    foreach ($p in $processes) {
        $map[[int]$p.ProcessId] = @{ Parent = [int]$p.ParentProcessId; Name = [string]$p.Name }
    }
    return $map
}

function Get-TcTerminalWindowHandle {
    <#
        .SYNOPSIS
        Handle of the Windows Terminal window hosting the current session. The
        result is cached for the lifetime of the session.
    #>
    [CmdletBinding()]
    param([switch] $Refresh)

    if (-not $Refresh -and $script:TcWindowHandle -ne [IntPtr]::Zero) { return $script:TcWindowHandle }
    if (-not (Test-TcWindowsTerminal)) { return [IntPtr]::Zero }

    if (-not $Refresh -and $script:TcWindowLookupFailedAt) {
        if (((Get-Date) - $script:TcWindowLookupFailedAt).TotalSeconds -lt $script:TcWindowLookupRetrySeconds) {
            return [IntPtr]::Zero
        }
    }

    if (-not (Initialize-TcInterop)) {
        $script:TcWindowLookupFailedAt = Get-Date
        return [IntPtr]::Zero
    }

    # 1. Walk up the parent chain to WindowsTerminal.exe
    $map = Get-TcParentProcessMap
    $terminalPid = 0
    $current = $PID
    for ($depth = 0; $depth -lt 12; $depth++) {
        if (-not $map.ContainsKey($current)) { break }
        $entry = $map[$current]
        if ($entry.Name -match '^WindowsTerminal(Preview)?\.exe$') { $terminalPid = $current; break }
        if ($entry.Parent -le 0 -or $entry.Parent -eq $current) { break }
        $current = $entry.Parent
    }

    # 2. Fallback: a single Windows Terminal process is running
    if ($terminalPid -eq 0) {
        $candidates = @(Get-Process -Name 'WindowsTerminal', 'WindowsTerminalPreview' -ErrorAction SilentlyContinue)
        if ($candidates.Count -eq 1) { $terminalPid = $candidates[0].Id }
    }

    if ($terminalPid -eq 0) {
        Write-Verbose 'TerminalColors: Windows Terminal process not found.'
        $script:TcWindowLookupFailedAt = Get-Date
        return [IntPtr]::Zero
    }

    # Windows Terminal can host several windows in a single process: ours is
    # identified by the title, which we have just set.
    # The @() is required: a single-result pipeline does not return an array.
    $windows = @([TerminalColors.Native]::GetProcessWindows([uint32]$terminalPid) |
        Where-Object { [TerminalColors.Native]::GetClass($_) -eq 'CASCADIA_HOSTING_WINDOW_CLASS' })

    if ($windows.Count -eq 0) {
        $script:TcWindowLookupFailedAt = Get-Date
        return [IntPtr]::Zero
    }

    $handle = $windows[0]
    if ($windows.Count -gt 1) {
        $title = Get-TcWindowTitle
        if (-not [string]::IsNullOrWhiteSpace($title)) {
            $matched = @($windows | Where-Object { [TerminalColors.Native]::GetTitle($_) -like "*$title*" })
            if ($matched.Count -gt 0) { $handle = $matched[0] }
        }
    }

    $script:TcWindowHandle = $handle
    $script:TcWindowLookupFailedAt = $null
    return $handle
}

function Set-TcWindowBorderColor {
    <#
        .SYNOPSIS
        Colours the terminal window's border. Returns $true on success
        (HRESULT S_OK).
    #>
    [CmdletBinding()]
    param(
        [hashtable] $Rgb,
        [switch] $IncludeCaption
    )

    $hwnd = Get-TcTerminalWindowHandle
    if ($hwnd -eq [IntPtr]::Zero) { return $false }

    # COLORREF = 0x00BBGGRR
    $colorRef = ([int]$Rgb.R) -bor (([int]$Rgb.G) -shl 8) -bor (([int]$Rgb.B) -shl 16)

    $hr = [TerminalColors.Native]::SetAttributeColor($hwnd, $script:TcDwmaBorderColor, $colorRef)
    if ($IncludeCaption) {
        [void][TerminalColors.Native]::SetAttributeColor($hwnd, $script:TcDwmaCaptionColor, $colorRef)
    }

    if ($hr -ne 0) {
        Write-Verbose ('TerminalColors: DwmSetWindowAttribute returned 0x{0:X8}' -f $hr)
        return $false
    }
    return $true
}

function Reset-TcWindowBorderColor {
    [CmdletBinding()]
    param([switch] $IncludeCaption)

    if (-not $script:TcInteropReady -and -not (Test-TcWindowsTerminal)) { return $false }
    $hwnd = Get-TcTerminalWindowHandle
    if ($hwnd -eq [IntPtr]::Zero) { return $false }

    $hr = [TerminalColors.Native]::SetAttributeColor($hwnd, $script:TcDwmaBorderColor, $script:TcDwmColorDefault)
    if ($IncludeCaption) {
        [void][TerminalColors.Native]::SetAttributeColor($hwnd, $script:TcDwmaCaptionColor, $script:TcDwmColorDefault)
    }
    return ($hr -eq 0)
}
