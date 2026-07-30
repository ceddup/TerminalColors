# Colouring the Windows Terminal window border through DWM.
#
# Windows Terminal exposes no API to recolour an existing window, but Windows 11
# allows the border colour of any window to be set (DWMWA_BORDER_COLOR, build
# 22000+). The terminal window is located by walking up the parent process chain.
#
# The interop type is compiled on first use only, so it never slows down the
# startup of PowerShell sessions.
#
# Its name must change whenever its members do: .NET cannot redefine a type that
# is already loaded, so a session that reloads an upgraded module would otherwise
# keep the previous shape and fail on the new members.

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

    if ('TerminalColors.Win32' -as [type]) {
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
    public static class Win32
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

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int Left, Top, Right, Bottom; }

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);

        // Returned as a plain array so the PowerShell side needs no struct type.
        public static int[] GetBounds(IntPtr hwnd)
        {
            RECT r;
            if (!GetWindowRect(hwnd, out r)) { return new int[] { 0, 0, 0, 0 }; }
            return new int[] { r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top };
        }

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

function Select-TcTerminalWindow {
    <#
        .SYNOPSIS
        Picks the real terminal window among the candidates of a Windows Terminal
        process. Returns the handle, or $null.

        .DESCRIPTION
        A single Windows Terminal process exposes several windows of class
        CASCADIA_HOSTING_WINDOW_CLASS, all carrying the title of the active tab:
        the real ones, plus hidden placeholders measured at 160x28 and parked at
        -32000,-32000. Colouring a placeholder's border succeeds - DWM returns
        S_OK - and changes nothing on screen, which is why the border used to
        appear only now and then.

        So geometry comes first: anything too small to be a terminal, or parked
        off-screen, is discarded. The title only arbitrates between real windows,
        and the largest one settles any remaining tie.

        .PARAMETER Candidates
        Objects carrying Handle, Left, Top, Width, Height and Title.

        .PARAMETER Title
        Title of this session's tab. Windows Terminal mirrors the active tab's
        title onto its window, so it identifies our window among several.
    #>
    [CmdletBinding()]
    param(
        [object[]] $Candidates,
        [string] $Title
    )

    if ($null -eq $Candidates) { return $null }

    # -32000 is where Windows parks minimised and placeholder windows.
    $real = @($Candidates | Where-Object {
        $_.Width -ge 200 -and $_.Height -ge 100 -and $_.Left -gt -30000 -and $_.Top -gt -30000
    })
    if ($real.Count -eq 0) { return $null }
    if ($real.Count -eq 1) { return $real[0].Handle }

    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        $matched = @($real | Where-Object { $_.Title -eq $Title })
        if ($matched.Count -eq 1) { return $matched[0].Handle }
        if ($matched.Count -gt 1) { $real = $matched }
    }

    return (@($real | Sort-Object -Property { [long]$_.Width * [long]$_.Height } -Descending)[0]).Handle
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

    # Windows Terminal can host several windows in a single process, and it also
    # keeps hidden placeholders of the same class carrying the same title. Collect
    # their geometry so the real one can be told apart.
    # The @() is required: a single-result pipeline does not return an array.
    $candidates = @([TerminalColors.Win32]::GetProcessWindows([uint32]$terminalPid) |
        Where-Object { [TerminalColors.Win32]::GetClass($_) -eq 'CASCADIA_HOSTING_WINDOW_CLASS' } |
        ForEach-Object {
            $bounds = [TerminalColors.Win32]::GetBounds($_)
            [pscustomobject]@{
                Handle = $_
                Left   = [int]$bounds[0]
                Top    = [int]$bounds[1]
                Width  = [int]$bounds[2]
                Height = [int]$bounds[3]
                Title  = [TerminalColors.Win32]::GetTitle($_)
            }
        })

    $handle = Select-TcTerminalWindow -Candidates $candidates -Title (Get-TcWindowTitle)
    if ($null -eq $handle) {
        $script:TcWindowLookupFailedAt = Get-Date
        return [IntPtr]::Zero
    }

    $script:TcWindowHandle = $handle
    $script:TcWindowLookupFailedAt = $null
    return $handle
}

function Test-TcActiveTab {
    <#
        .SYNOPSIS
        Tells whether this session's tab is the one the window is showing.
        Returns $true, $false, or $null when it cannot be determined.

        .DESCRIPTION
        The border belongs to the window, not to the tab, so only the visible tab
        may drive it. Without this check every tab writes the border on its first
        prompt - and since those prompts race each other while a window opens, a
        colourless tab resetting the border can win, leaving a grey border on a
        window whose visible tab belongs to a project.

        Windows Terminal mirrors the active tab's title onto the window title, and
        we set our own tab title, so comparing the two answers the question. When
        the title is not usable ([-NoTitle], [suppressApplicationTitle], window not
        located) the answer is $null and the caller keeps its previous behaviour
        rather than silently dropping the border.
    #>
    [CmdletBinding()]
    param()

    # Our own console title, plus the titles we set just before it: Windows
    # Terminal propagates a title change to the window asynchronously.
    $candidates = @(@(Get-TcWindowTitle) + @($script:TcAppliedTitles))
    if (@($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) { return $null }

    $hwnd = Get-TcTerminalWindowHandle
    if ($hwnd -eq [IntPtr]::Zero) { return $null }

    $windowTitle = ''
    try { $windowTitle = [TerminalColors.Win32]::GetTitle($hwnd) } catch { return $null }

    return (Test-TcTitleMatchesWindow -WindowTitle $windowTitle -Candidates $candidates)
}

function Test-TcTitleMatchesWindow {
    <#
        .SYNOPSIS
        Decision behind Test-TcActiveTab, kept separate so it can be reasoned
        about and tested on its own.

        Returns $null when the window title tells us nothing.
    #>
    [CmdletBinding()]
    param(
        [string] $WindowTitle,
        [string[]] $Candidates
    )

    if ([string]::IsNullOrWhiteSpace($WindowTitle)) { return $null }

    $usable = @($Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($usable.Count -eq 0) { return $null }

    return ($usable -contains $WindowTitle)
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

    $hr = [TerminalColors.Win32]::SetAttributeColor($hwnd, $script:TcDwmaBorderColor, $colorRef)
    if ($IncludeCaption) {
        [void][TerminalColors.Win32]::SetAttributeColor($hwnd, $script:TcDwmaCaptionColor, $colorRef)
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

    $hr = [TerminalColors.Win32]::SetAttributeColor($hwnd, $script:TcDwmaBorderColor, $script:TcDwmColorDefault)
    if ($IncludeCaption) {
        [void][TerminalColors.Win32]::SetAttributeColor($hwnd, $script:TcDwmaCaptionColor, $script:TcDwmColorDefault)
    }
    return ($hr -eq 0)
}
