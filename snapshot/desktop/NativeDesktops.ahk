#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook True

desktopDll := A_ScriptDir "\VirtualDesktopAccessor.dll"
desktopModule := DllCall("LoadLibraryW", "Str", desktopDll, "Ptr")
if !desktopModule
    throw OSError()

desktopRules := Map()
desktopRules.CaseSense := "Off"
desktopRules.Set(
    "TONEX.exe", 1,
    "Ableton Live 12 Suite.exe", 0,
    "chrome.exe", 2,
    "ChatGPT.exe", 3,
    "SystemSettings.exe", 9,
    "SndVol.exe", 9,
    "Focusrite Control.exe", 9,
    "Focusrite Control 2.exe", 9,
    "fsquirt.exe", 9
)

SetTimer RouteAppWindows, 750
RouteAppWindows()

RouteAppWindows() {
    global desktopDll, desktopRules
    count := DllCall(desktopDll "\GetDesktopCount", "Int")
    if count < 1
        return
    DetectHiddenWindows true
    for hwnd in WinGetList() {
        if !DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
            continue
        try {
            exe := WinGetProcessName(hwnd)
            if desktopRules.Has(exe) {
                target := desktopRules[exe]
            } else if exe = "ApplicationFrameHost.exe" && WinGetTitle(hwnd) = "Settings" {
                target := 9
            } else if (exe = "rundll32.exe" || exe = "control.exe") && WinGetTitle(hwnd) = "Sound" {
                target := 9
            } else {
                continue
            }
            if target >= count || !WinGetTitle(hwnd)
                continue
            current := DllCall(desktopDll "\GetWindowDesktopNumber", "Ptr", hwnd, "Int")
            if current >= 0 && current != target
                DllCall(desktopDll "\MoveWindowToDesktopNumber", "Ptr", hwnd, "Int", target, "Int")
        } catch TargetError {
            ; A window may close between enumeration and inspection.
        }
    }
}

SwitchDesktop(index) {
    global desktopDll
    count := DllCall(desktopDll "\GetDesktopCount", "Int")
    if index < count
        DllCall(desktopDll "\GoToDesktopNumber", "Int", index, "Int")
}

#1::SwitchDesktop(0)
#2::SwitchDesktop(1)
#3::SwitchDesktop(2)
#4::SwitchDesktop(3)
#5::SwitchDesktop(4)
#6::SwitchDesktop(5)
#7::SwitchDesktop(6)
#8::SwitchDesktop(7)
#9::SwitchDesktop(8)
#0::SwitchDesktop(9)


; Keep Win available as a modifier and suppress Start on a bare Win press.
~LWin::SendEvent "{Blind}{vkE8}"
~RWin::SendEvent "{Blind}{vkE8}"

; Intercept the Windows Feedback Hub shortcut and open File Pilot on the second press.
#f::return
#f up::{
    static firstPress := 0
    if firstPress && A_TickCount - firstPress <= 650 {
        firstPress := 0
        KeyWait "LWin"
        KeyWait "RWin"
        OpenFilePilot()
        return
    }
    firstPress := A_TickCount
}

:*?CX: ff::OpenFilePilot()

OpenFilePilot() {
    global desktopDll

    executable := EnvGet("LOCALAPPDATA") "\Voidstar\FilePilot\FPilot.exe"
    desktop := DllCall(desktopDll "\GetCurrentDesktopNumber", "Int")
    if ActivateFilePilot(desktop)
        return

    Run '"' executable '"', EnvGet("USERPROFILE")
    deadline := A_TickCount + 5000
    while A_TickCount < deadline {
        if ActivateFilePilot(desktop)
            return
        Sleep 100
    }
}

ActivateFilePilot(desktop) {
    global desktopDll
    for hwnd in WinGetList("ahk_exe FPilot.exe") {
        try {
            if !WinGetTitle(hwnd) || !DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
                continue
            if desktop >= 0 && DllCall(desktopDll "\GetWindowDesktopNumber", "Ptr", hwnd, "Int") != desktop
                continue
            WinActivate "ahk_id " hwnd
            return true
        } catch TargetError {
            ; File Pilot may replace its startup window before activation.
        }
    }
    return false
}
