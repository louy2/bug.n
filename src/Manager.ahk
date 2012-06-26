/**
 *	bug.n - tiling window management
 *	Copyright (c) 2010-2012 joten
 *
 *	This program is free software: you can redistribute it and/or modify
 *	it under the terms of the GNU General Public License as published by
 *	the Free Software Foundation, either version 3 of the License, or
 *	(at your option) any later version.
 *
 *	This program is distributed in the hope that it will be useful,
 *	but WITHOUT ANY WARRANTY; without even the implied warranty of
 *	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *	GNU General Public License for more details.
 *
 *	You should have received a copy of the GNU General Public License
 *	along with this program. If not, see <http://www.gnu.org/licenses/>.
 *
 *	@version 8.3.0
 */

Manager_init() {
	Local ncm, ncmSize
	
	; Windows UI
	If Config_selBorderColor {
		SetFormat, Integer, hex
		Manager_normBorderColor := DllCall("GetSysColor", "Int", 10)
		SetFormat, Integer, d
		DllCall("SetSysColors", "Int", 1, "Int*", 10, "UInt*", Config_selBorderColor)
	}
	If (Config_borderWidth > 0) Or (Config_borderPadding >= 0 And A_OSVersion = WIN_VISTA) {
		ncmSize := VarSetCapacity(ncm, 4 * (A_OSVersion = WIN_VISTA ? 11 : 10) + 5 * (28 + 32 * (A_IsUnicode ? 2 : 1)), 0)
		NumPut(ncmSize, ncm, 0, "UInt")
		DllCall("SystemParametersInfo", "UInt", 0x0029, "UInt", ncmSize, "UInt", &ncm, "UInt", 0)
		Manager_borderWidth := NumGet(ncm, 4, "Int")
		Manager_borderPadding := NumGet(ncm, 40 + 5 * (28 + 32 * (A_IsUnicode ? 2 : 1)), "Int")
		If (Config_borderWidth > 0)
			NumPut(Config_borderWidth, ncm, 4, "Int")
		If (Config_borderPadding >= 0 And A_OSVersion = WIN_VISTA)
			NumPut(Config_borderPadding, ncm, 40 + 5 * (28 + 32 * (A_IsUnicode ? 2 : 1)), "Int")
		DllCall("SystemParametersInfo", "UInt", 0x002a, "UInt", ncmSize, "UInt", &ncm, "UInt", 0)
	}
	
	Bar_getHeight()
	Manager_aMonitor := 1
	Manager_taskBarMonitor := ""
	Manager_showTaskBar := True
	SysGet, Manager_monitorCount, MonitorCount
	Loop, % Manager_monitorCount
		Monitor_init(A_Index)
	Bar_initCmdGui()
	If Not Config_showTaskBar
		Monitor_toggleTaskBar()
	
	Manager_focus			:= False
	Manager_hideShow		:= False
	Bar_hideTitleWndIds		:= ""
	Manager_allWndIds		:= ""
	Manager_managedWndIds	:= ""
	Manager_initial_sync()
	
	Bar_updateStatus()
	Bar_updateTitle()
	Loop, % Manager_monitorCount {
		View_arrange(A_Index, Monitor_#%A_Index%_aView_#1)
		Bar_updateView(A_Index, Monitor_#%A_Index%_aView_#1)
	}
	
	Manager_registerShellHook()
	SetTimer, Bar_loop, %Config_readinInterval%
}

Manager_activateMonitor(d) {
	Local aView, aWndClass, aWndHeight, aWndId, aWndWidth, aWndX, aWndY, v, wndId
	
	If (Manager_monitorCount > 1) {
		aView := Monitor_#%Manager_aMonitor%_aView_#1
		WinGet, aWndId, ID, A
		If WinExist("ahk_id" aWndId) {
			WinGetClass, aWndClass, ahk_id %aWndId%
			If Not (aWndClass = "Progman") And Not (aWndClass = "AutoHotkeyGui") And Not (aWndClass = "DesktopBackgroundClass") {
				WinGetPos, aWndX, aWndY, aWndWidth, aWndHeight, ahk_id %aWndId%
				If (Monitor_get(aWndX + aWndWidth / 2, aWndY + aWndHeight / 2) = Manager_aMonitor)
					View_#%Manager_aMonitor%_#%aView%_aWndId := aWndId
			}
		}
		
		Manager_aMonitor := Manager_loop(Manager_aMonitor, d, 1, Manager_monitorCount)
		v := Monitor_#%Manager_aMonitor%_aView_#1
		wndId := View_#%Manager_aMonitor%_#%v%_aWndId
		If Not (wndId And WinExist("ahk_id" wndId)) {
			If View_#%Manager_aMonitor%_#%v%_wndIds
				wndId := SubStr(View_#%Manager_aMonitor%_#%v%_wndIds, 1, InStr(View_#%Manager_aMonitor%_#%v%_wndIds, ";")-1)
			Else
				wndId := 0
		}
		Manager_winActivate(wndId)
	}
}

Manager_applyRules(wndId, ByRef isManaged, ByRef m, ByRef tags, ByRef isFloating, ByRef isDecorated, ByRef hideTitle) {
	Local mouseX, mouseY, wndClass, wndHeight, wndStyle, wndTitle, wndWidth, wndX, wndY
	Local rule0, rule1, rule2, rule3, rule4, rule5, rule6, rule7, rule8, rule9
	
	isManaged   := True
	m           := 0
	tags        := 0
	isFloating  := False
	isDecorated := False
	hideTitle   := False
	
	WinGetClass, wndClass, ahk_id %wndId%
	WinGetTitle, wndTitle, ahk_id %wndId%
	WinGetPos, wndX, wndY, wndWidth, wndHeight, ahk_id %wndId%
	WinGet, wndStyle, Style, ahk_id %wndId%
	If wndClass And wndTitle And Not (wndX < -4999) And Not (wndY < -4999) {
		Loop, % Config_ruleCount {
			StringSplit, rule, Config_rule_#%A_index%, `;
			If RegExMatch(wndClass . ";" . wndTitle, rule1 . ";" . rule2) And (rule3 = "" Or wndStyle & rule3) {	; The last matching rule is returned.
				isManaged   := rule4
				m           := rule5
				tags        := rule6
				isFloating  := rule7
				isDecorated := rule8
				hideTitle   := rule9
			}
		}
	} Else {
		isManaged := False
		If wndTitle
			hideTitle := True
	}
}

Manager_cleanup() {
	Local aWndId, m, ncmSize, ncm, wndIds
	
	WinGet, aWndId, ID, A
	
	; Reset border color, padding and witdh.
	If Config_selBorderColor
		DllCall("SetSysColors", "Int", 1, "Int*", 10, "UInt*", Manager_normBorderColor)
	If (Config_borderWidth > 0) Or (Config_borderPadding >= 0 And A_OSVersion = WIN_VISTA) {
		ncmSize := VarSetCapacity(ncm, 4 * (A_OSVersion = WIN_VISTA ? 11 : 10) + 5 * (28 + 32 * (A_IsUnicode ? 2 : 1)), 0)
		NumPut(ncmSize, ncm, 0, "UInt")
		DllCall("SystemParametersInfo", "UInt", 0x0029, "UInt", ncmSize, "UInt", &ncm, "UInt", 0)
		If (Config_borderWidth > 0)
			NumPut(Manager_borderWidth, ncm, 4, "Int")
		If (Config_borderPadding >= 0 And A_OSVersion = WIN_VISTA)
			NumPut(Manager_borderPadding, ncm, 40 + 5 * (28 + 32 * (A_IsUnicode ? 2 : 1)), "Int")
		DllCall("SystemParametersInfo", "UInt", 0x002a, "UInt", ncmSize, "UInt", &ncm, "UInt", 0)
	}
	
	; Show borders and title bars.
	StringTrimRight, wndIds, Manager_managedWndIds, 1
	Manager_hideShow := True
	Loop, PARSE, wndIds, `;
	{
		WinShow, ahk_id %A_LoopField%
		If Not Config_showBorder
			WinSet, Style, +0x40000, ahk_id %A_LoopField%
		WinSet, Style, +0xC00000, ahk_id %A_LoopField%
	}
	
	; Show the task bar.
	WinShow, Start ahk_class Button
	WinShow, ahk_class Shell_TrayWnd
	Manager_hideShow := False
	
	; Reset windows position and size.
	Manager_showTaskBar := True
	Loop, % Manager_monitorCount {
		m := A_Index
		Monitor_#%m%_showBar := False
		Monitor_getWorkArea(m)
		Loop, % Config_viewCount
			View_arrange(m, A_Index)
	}
	WinSet, AlwaysOnTop, On, ahk_id %aWndId%
	WinSet, AlwaysOnTop, Off, ahk_id %aWndId%
	
	DllCall("Shell32.dll\SHAppBarMessage", "UInt", (ABM_REMOVE := 0x1), "UInt", &Bar_appBarData)
	; SKAN: Crazy Scripting : Quick Launcher for Portable Apps (http://www.autohotkey.com/forum/topic22398.html)
}

Manager_closeWindow() {
	WinGet, aWndId, ID, A
	WinGetClass, aWndClass, ahk_id %aWndId%
	WinGetTitle, aWndTitle, ahk_id %aWndId%
	If Not (aWndClass = "AutoHotkeyGUI" And RegExMatch(aWndTitle, "bug.n_BAR_[0-9]+"))
		WinClose, ahk_id %aWndId%
}

Manager_getWindowInfo() {
	Local text, v, aWndClass, aWndHeight, aWndId, aWndProcessName, aWndStyle, aWndTitle, aWndWidth, aWndX, aWndY
	
	WinGet, aWndId, ID, A
	WinGetClass, aWndClass, ahk_id %aWndId%
	WinGetTitle, aWndTitle, ahk_id %aWndId%
	WinGet, aWndProcessName, ProcessName, ahk_id %aWndId%
	WinGet, aWndStyle, Style, ahk_id %aWndId%
	WinGetPos, aWndX, aWndY, aWndWidth, aWndHeight, ahk_id %aWndId%
	text := "ID: " aWndId "`nclass:`t" aWndClass "`ntitle:`t" aWndTitle
	If InStr(Bar_hiddenWndIds, aWndId)
		text .= " (hidden)"
	text .= "`nprocess:`t" aWndProcessName "`nstyle:`t" aWndStyle "`nmetrics:`tx: " aWndX ", y: " aWndY ", width: " aWndWidth ", height: " aWndHeight "`ntags:`t" Manager_#%aWndId%_tags
	If Manager_#%aWndId%_isFloating
		text .= " (floating)"
	MsgBox, 260, bug.n: Window Information, % text "`n`nCopy text to clipboard?"
	IfMsgBox Yes
		Clipboard := text
}

Manager_getWindowList() {
	Local text, v, aWndId, wndIds, aWndTitle
	
	v := Monitor_#%Manager_aMonitor%_aView_#1
	aWndId := View_#%Manager_aMonitor%_#%v%_aWndId
	WinGetTitle, aWndTitle, ahk_id %aWndId%
	text := "Active Window`n" aWndId ":`t" aWndTitle
	
	StringTrimRight, wndIds, View_#%Manager_aMonitor%_#%v%_wndIds, 1
	text .= "`n`nWindow List"
	Loop, PARSE, wndIds, `;
	{
		WinGetTitle, wndTitle, ahk_id %A_LoopField%
		text .= "`n" A_LoopField ":`t" wndTitle
	}
	
	MsgBox, 260, bug.n: Window List, % text "`n`nCopy text to clipboard?"
	IfMsgBox Yes
		Clipboard := text
}

Manager_logViewLayout() {

}

Manager_logWindowInfo( w ) {
	Local av, aWndId, aIsWinFocus, aIsBugnActive, aIsFloating, aIsHidden, aIsDecorated, aWndTitle, aWndStyle, aWndX, aWndY, aWndW, aWndH
	
	WinGet, aWndId, ID, A
	If aWndId = %w%
		aIsWinFocus := "*"
	Else
		aIsWinFocus := " "
	av := Monitor_#%Manager_aMonitor%_aView_#1
	If View_#%Manager_aMonitor%_#%av%_aWndId = %w%
		aIsBugnActive := "*"
	Else
		aIsBugnActive := " "
	WinGetTitle, aWndTitle, ahk_id %w%
	If InStr(Bar_hiddenWndIds, w)
		aIsHidden := "*"
	Else 
		aIsHidden := " "
	If Manager_#%w%_isFloating
		aIsFloating := "*"
	Else
		aIsFloating := " "
	If Manager_#%w%_isDecorated
		aIsDecorated := "*"
	Else
		aIsDecorated := " "
	WinGet, aWndStyle, Style, ahk_id %w%
	WinGetPos, aWndX, aWndY, aWndW, aWndH, ahk_id %w%
	;Manager_#%wndId%_monitor     := m
	;Manager_#%wndId%_tags        := tags
	;Manager_#%wndId%_isDecorated := isDecorated
	;Manager_#%wndId%_isFloating  := isFloating
	Log_bare(w . "`t" . aIsHidden . " " aIsWinFocus . " " . aIsBugnActive . " " . aIsFloating . " " . aIsDecorated . " " . Manager_#%w%_monitor . "`t" . Manager_#%w%_tags . "`t" . aWndX . "`t" . aWndY . "`t" . aWndW . "`t" . aWndH . "`t" . aWndStyle . "`t" . aWndTitle)
}

Manager_logViewWindowList() {
	Local text, v, aWndId, wndIds, aWndTitle
	
	v := Monitor_#%Manager_aMonitor%_aView_#1
	Log_msg( "Window dump for active view (" . Manager_aMonitor . ", " . v . ")" )
	Log_bare( "ID`t`tH W A F D M`tTags`tX`tY`tW`tH`tStyle`t`tTitle")
	
	StringTrimRight, wndIds, View_#%Manager_aMonitor%_#%v%_wndIds, 1
	Loop, PARSE, wndIds, `;
	{
		Manager_logWindowInfo( A_LoopField )
	}
}

Manager_logHelp() {
	Log_msg("Help Display")
	Log_bare("Window list columns")
	Log_bare("    ID - Windows ID")
	Log_bare("    H - Hidden")
	Log_bare("    W - Windows active")
	Log_bare("    A - View active")
	Log_bare("    F - Floating")
	Log_bare("    D - Decorated")
	Log_bare("    M - Monitor")
	Log_bare("    Tags - Bit-mask of the views in which the window is active")
	Log_bare("    X - Windows X position")
	Log_bare("    Y - Windows Y position")
	Log_bare("    W - Windows width")
	Log_bare("    H - Windows height")
	Log_bare("    Style - Windows style")
	Log_bare("    Title - Title of the window")
}

Manager_lockWorkStation() {
    Global Config_shellMsgDelay
    
    RegWrite, REG_DWORD, HKEY_CURRENT_USER, Software\Microsoft\Windows\CurrentVersion\Policies\System, DisableLockWorkstation, 0
    Sleep, % Config_shellMsgDelay
    DllCall("LockWorkStation")
    Sleep, % 4 * Config_shellMsgDelay
    RegWrite, REG_DWORD, HKEY_CURRENT_USER, Software\Microsoft\Windows\CurrentVersion\Policies\System, DisableLockWorkstation, 1
}
; Unambiguous: Re-use WIN+L as a hotkey in bug.n (http://www.autohotkey.com/community/viewtopic.php?p=500903&sid=eb3c7a119259b4015ff045ef80b94a81#p500903)

Manager_loop(index, increment, lowerBound, upperBound) {
	index += increment
	If (index > upperBound)
		index := lowerBound
	If (index < lowerBound)
		index := upperBound
	If (upperBound = 0)
		index := 0
	
	Return, index
}

; Accept a window to be added to the system for management.
; Provide a monitor, view preference, but don't override the config.
; pm - Preferred monitor
; pv - Preferred view
; wndId - Window to add to the manager.
Manager_manage(pm, pv, wndId) {
	Local a, c0, hideTitle, i, isDecorated, isFloating, isManaged, l, m, n, replace, search, tags
    Local wndControlList0, wndId0, wndIds, wndX, wndY, wndWidth, wndHeight, wndProcessName
	
	If Not InStr(Manager_allWndIds, wndId ";")
		Manager_allWndIds .= wndId ";"
	Manager_applyRules(wndId, isManaged, m, tags, isFloating, isDecorated, hideTitle)
	
	If (m = 0)
		m := pm
	If (m < 0)
		m := 1
	If (m > Manager_monitorCount)	; If the specified monitor is out of scope, set it to the max. monitor.
		m := Manager_monitorCount
	If (tags = 0)
		tags := 1 << (pv - 1)
	
	WinGet, wndProcessName, ProcessName, ahk_id %wndId%
	If (wndProcessName = "chrome.exe") {
		WinGet, wndControlList, ControlList, ahk_id %wndId%
		StringSplit, c, wndControlList, `n
		If (c0 <= 1)
			isManaged := False
	}
	
	If isManaged {
		Monitor_moveWindow(m, wndId)

		Manager_managedWndIds .= wndId ";"
		Manager_#%wndId%_monitor     := m
		Manager_#%wndId%_tags        := tags
		Manager_#%wndId%_isDecorated := isDecorated
		Manager_#%wndId%_isFloating  := isFloating
		
		Loop, % Config_viewCount
			If (Manager_#%wndId%_tags & 1 << A_Index - 1) {
				View_addWnd(m, A_Index, wndId)
			}
		
		If Not Config_showBorder
			WinSet, Style, -0x40000, ahk_id %wndId%
		If Not Manager_#%wndId%_isDecorated
			WinSet, Style, -0xC00000, ahk_id %wndId%
		
		a := Manager_#%wndId%_tags & 1 << Monitor_#%m%_aView_#1 - 1
		If a {
			Manager_aMonitor := m
			Manager_winActivate(wndId)
		} Else {
			Manager_hideShow := True
			WinHide, ahk_id %wndId%
			Manager_hideShow := False
		}
	}
	
	If hideTitle And Not InStr(Bar_hideTitleWndIds, wndId)
		Bar_hideTitleWndIds .= wndId . ";"
	Else If Not hideTitle
		StringReplace, Bar_hideTitleWndIds, Bar_hideTitleWndIds, %wndId%`;, 
	
	Return, a
}

Manager_maximizeWindow() {
	Local aWndId, l, v
	
	WinGet, aWndId, ID, A
	v := Monitor_#%Manager_aMonitor%_aView_#1
	l := View_#%Manager_aMonitor%_#%v%_layout_#1
	If Not Manager_#%aWndId%_isFloating And Not (Config_layoutFunction_#%l% = "")
		View_toggleFloating()
	WinSet, Top,, ahk_id %aWndId%
	
	Manager_winMove(aWndId, Monitor_#%Manager_aMonitor%_x, Monitor_#%Manager_aMonitor%_y, Monitor_#%Manager_aMonitor%_width, Monitor_#%Manager_aMonitor%_height)
}

Manager_moveWindow() {
	Local aWndId, l, SC_MOVE, v, WM_SYSCOMMAND
	
	WinGet, aWndId, ID, A
	v := Monitor_#%Manager_aMonitor%_aView_#1
	l := View_#%Manager_aMonitor%_#%v%_layout_#1
	If Not Manager_#%aWndId%_isFloating And Not (Config_layoutFunction_#%l% = "")
		View_toggleFloating()
	WinSet, Top,, ahk_id %aWndId%
	
	WM_SYSCOMMAND = 0x112
	SC_MOVE = 0xF010
	SendMessage, WM_SYSCOMMAND, SC_MOVE, , , ahk_id %aWndId%
}

HSHELL_WINDOWCREATED := 1
; Seems to get sent sometimes when windows are deactivated.
HSHELL_WINDOWDESTROYED := 2
HSHELL_WINDOWACTIVATED := 4
; At least title change.
HSHELL_REDRAW := 6
; Full-screen app activated? Root-privileged window activated?
HSHELL_RUDEAPPACTIVATED := 32772
; When a window is signalling an application update.
WINDOW_NOTICE := 32774

Manager_onShellMessage(wParam, lParam) {
	Local a, isChanged, aWndClass, aWndHeight, aWndId, aWndTitle, aWndWidth, aWndX, aWndY, m, t, wndClass, wndId, wndIds, wndPName, wndTitle, x, y
	
	Log_dbg_msg(2, "Manager_onShellMessage(wParam: " . wParam . ", lParam: " . lParam)
	
	SetFormat, Integer, hex
	lParam := lParam+0
	SetFormat, Integer, d
	WinGetClass, wndClass, ahk_id %lParam%
	WinGetTitle, wndTitle, ahk_id %lParam%
	WinGet, wndPName, ProcessName, ahk_id %lParam%
	
	WinGet, aWndId, ID, A
	WinGetClass, aWndClass, ahk_id %aWndId%
	WinGetTitle, aWndTitle, ahk_id %aWndId%
	If ((wParam = 4 Or wParam = 32772) And lParam = 0 And aWndClass = "Progman" And aWndTitle = "Program Manager") {
		MouseGetPos, x, y
		m := Monitor_get(x, y)
		If m
			Manager_aMonitor := m
		Bar_updateTitle()
	}
	
	If (wParam = 1 Or wParam = 2 Or wParam = 4 Or wParam = 6 Or wParam = 32772) And lParam And Not Manager_hideShow And Not Manager_focus {
		If Not (wParam = 4 Or wParam = 32772)
			If Not wndClass And Not (wParam = 2) {
				WinGetClass, wndClass, ahk_id %lParam%
				If wndClass {
					If (wndClass = "Emacs")
						Sleep, % 12 * Config_shellMsgDelay
				} Else
					Sleep, %Config_shellMsgDelay%
			}
		
		isChanged := Manager_sync(wndIds)
		If wndIds
			isChanged := False

		If a Or isChanged {
			View_arrange(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1)
			Bar_updateView(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1)
		}
		
		If (Manager_monitorCount > 1) {
			WinGetPos, aWndX, aWndY, aWndWidth, aWndHeight, ahk_id %aWndId%
			m := Monitor_get(aWndX + aWndWidth / 2, aWndY + aWndHeight / 2)
			If m
				Manager_aMonitor := m
		}
		
		If wndIds {
			If (Config_onActiveHiddenWnds = "view") {
				; Grab the first of such windows and make it visible.
				; All others get forgotten (until the next round?)
				wndId := SubStr(wndIds, 1, InStr(wndIds, ";") - 1)
				Loop, % Config_viewCount
					If (Manager_#%wndId%_tags & 1 << A_Index - 1) {
						Manager_aMonitor := Manager_#%wndId%_monitor
						Monitor_activateView(A_Index)
						Break
					}
			} Else {
				StringTrimRight, wndIds, wndIds, 1
				StringSplit, wndId, wndIds, `;
				; Otherwise re-hide them.
				If (Config_onActiveHiddenWnds = "hide") {
					Loop, % wndId0
						WinHide, % "ahk_id " wndId%A_Index%
				} Else If (Config_onActiveHiddenWnds = "tag") {
					; Or tag all of them for the current view.
					t := Monitor_#%Manager_aMonitor%_aView_#1
					Loop, % wndId0 {
						wndId := wndId%A_Index%
						View_#%Manager_aMonitor%_#%t%_wndIds := wndId ";" View_#%Manager_aMonitor%_#%t%_wndIds
						View_#%Manager_aMonitor%_#%t%_aWndId := wndId
						Manager_#%wndId%_tags += 1 << t - 1
					}
					Bar_updateView(Manager_aMonitor, t)
					View_arrange(Manager_aMonitor, t)
				}
			}
		}
		
		Bar_updateTitle()
	}
}

Manager_registerShellHook() {
	Gui, +LastFound
	hWnd := WinExist()
	DllCall("RegisterShellHookWindow", "UInt", hWnd)	; Minimum operating systems: Windows 2000 (http://msdn.microsoft.com/en-us/library/ms644989(VS.85).aspx)
	msgNum := DllCall("RegisterWindowMessage", "Str", "SHELLHOOK")
	OnMessage(msgNum, "Manager_onShellMessage")
}
; SKAN: How to Hook on to Shell to receive its messages? (http://www.autohotkey.com/forum/viewtopic.php?p=123323#123323)

Manager_setViewMonitor(d) {
	Local aView, m, v, wndIds
	
	If (Manager_monitorCount > 1) {
		m := Manager_loop(Manager_aMonitor, d, 1, Manager_monitorCount)
		v := Monitor_#%m%_aView_#1
		aView := Monitor_#%Manager_aMonitor%_aView_#1
		If View_#%Manager_aMonitor%_#%aView%_wndIds {
			View_#%m%_#%v%_wndIds := View_#%Manager_aMonitor%_#%aView%_wndIds View_#%m%_#%v%_wndIds
			
			StringTrimRight, wndIds, View_#%Manager_aMonitor%_#%aView%_wndIds, 1
			Loop, PARSE, wndIds, `;
			{
				Loop, % Config_viewCount {
					StringReplace, View_#%Manager_aMonitor%_#%A_Index%_wndIds, View_#%Manager_aMonitor%_#%A_Index%_wndIds, %A_LoopField%`;, 
					View_#%Manager_aMonitor%_#%A_Index%_aWndId := 0
				}
				
				Monitor_moveWindow(m, A_LoopField)
				Manager_#%A_LoopField%_tags := 1 << v - 1
			}
			View_arrange(Manager_aMonitor, aView)
			Loop, % Config_viewCount
				Bar_updateView(Manager_aMonitor, A_Index)
			
			Manager_aMonitor := m
			View_arrange(m, v)
			Bar_updateTitle()
			Bar_updateView(m, v)
		}
	}
}

Manager_setWindowMonitor(d) {
	Local aWndId, v
	
	WinGet, aWndId, ID, A
	If (Manager_monitorCount > 1 And InStr(Manager_managedWndIds, aWndId ";")) {
		Loop, % Config_viewCount {
			StringReplace, View_#%Manager_aMonitor%_#%A_Index%_wndIds, View_#%Manager_aMonitor%_#%A_Index%_wndIds, %aWndId%`;, 
			If (aWndId = View_#%Manager_aMonitor%_#%A_Index%_aWndId)
				View_#%Manager_aMonitor%_#%A_Index%_aWndId := 0
			Bar_updateView(Manager_aMonitor, A_Index)
		}
		View_arrange(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1)
		
		Manager_aMonitor := Manager_loop(Manager_aMonitor, d, 1, Manager_monitorCount)
		Monitor_moveWindow(Manager_aMonitor, aWndId)
		v := Monitor_#%Manager_aMonitor%_aView_#1
		Manager_#%aWndId%_tags := 1 << v - 1
		View_#%Manager_aMonitor%_#%v%_wndIds := aWndId ";" View_#%Manager_aMonitor%_#%v%_wndIds
		View_#%Manager_aMonitor%_#%v%_aWndId := aWndId
		View_arrange(Manager_aMonitor, v)
		Bar_updateTitle()
		Bar_updateView(Manager_aMonitor, v)
	}
}

Manager_sizeWindow() {
	Local aWndId, l, SC_SIZE, v, WM_SYSCOMMAND
	
	WinGet, aWndId, ID, A
	v := Monitor_#%Manager_aMonitor%_aView_#1
	l := View_#%Manager_aMonitor%_#%v%_layout_#1
	If Not Manager_#%aWndId%_isFloating And Not (Config_layoutFunction_#%l% = "")
		View_toggleFloating()
	WinSet, Top,, ahk_id %aWndId%
	
	WM_SYSCOMMAND = 0x112
	SC_SIZE	= 0xF000
	SendMessage, WM_SYSCOMMAND, SC_SIZE, , , ahk_id %aWndId%
}

Manager_sync(ByRef wndIds = "") {
	Local a, flag, shownWndIds, v, visibleWndIds, wndId
	
	Loop, % Manager_monitorCount {
		v := Monitor_#%A_Index%_aView_#1
		shownWndIds .= View_#%A_Index%_#%v%_wndIds
	}
	; check all visible windows against the known windows
	WinGet, wndId, List, , , 
	Loop, % wndId {
		If Not InStr(shownWndIds, wndId%A_Index% ";") {
			If Not InStr(Manager_managedWndIds, wndId%A_Index% ";") {
				flag := Manager_manage(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1, wndId%A_Index%)
				If flag
					a := flag
			} Else
				wndIds .= wndId%A_Index% ";"
		}
		visibleWndIds := visibleWndIds wndId%A_Index% ";"
	}
	
	; check, if a window, that is known to be visible, is actually not visible
	StringTrimRight, shownWndIds, shownWndIds, 1
	Loop, PARSE, shownWndIds, `;
	{
		If Not InStr(visibleWndIds, A_LoopField) {
			flag := Manager_unmanage(A_LoopField)
			If flag
				a := flag
		}
	}
	
	Return, a
}

; No windows are known to the system yet.
; Try to do something smart with the initial layout.
Manager_initial_sync() {
	Local wndId0, wnd, wndX, wndY, wndW, wndH, x, y, m, len
	
	; Initialize lists
	; Note that these variables make this function non-reentrant.
	Loop, % Manager_monitorCount
		Manager_initial_sync_m#%A_Index%_wndList := List_new()
	
	; check all visible windows against the known windows
	WinGet, wndId, List, , , 
	Loop, % wndId {
		; Based on some analysis here, determine which monitors and layouts would best 
		; serve existing windows. Do not override configuration settings.
		
		; Which monitor is it on?
		
		wnd := wndId%A_Index%
		WinGetPos, wndX, wndY, wndW, wndH, ahk_id %wnd%
		
		x := wndX + wndW/2
		y := wndY + wndH/2
		
		m := Monitor_get(x, y)
		If m > 0
			List_append(Manager_initial_sync_m#%m%_wndList, wndId%A_index%)
		
		; @todo: What percentage of the monitor area is it occupying? (Suggest layout)
		; @todo: What part of the monitor is it on? (Ordering of windows)
	}

	Loop, % Manager_monitorCount {
		m := A_Index
		len := List_toArray(Manager_initial_sync_m#%m%_wndList, "Manager_initial_sync_tmpArray")
		Loop, % len
			Manager_manage(m, 1, Manager_initial_sync_tmpArray%A_Index%)
	}
}

Manager_toggleDecor() {
	Local aWndId
	
	WinGet, aWndId, ID, A
	Manager_#%aWndId%_isDecorated := Not Manager_#%aWndId%_isDecorated
	If Manager_#%aWndId%_isDecorated
		WinSet, Style, +0xC00000, ahk_id %aWndId%
	Else
		WinSet, Style, -0xC00000, ahk_id %aWndId%
}

Manager_unmanage(wndId) {
	Local a
	
	a := Manager_#%wndId%_tags & 1 << Monitor_#%Manager_aMonitor%_aView_#1 - 1
	Loop, % Config_viewCount
		If (Manager_#%wndId%_tags & 1 << A_Index - 1) {
			View_delWnd( Manager_aMonitor, A_Index, wndId )
			Bar_updateView(Manager_aMonitor, A_Index)
		}
	Manager_#%wndId%_monitor     :=
	Manager_#%wndId%_tags        :=
	Manager_#%wndId%_isDecorated :=
	Manager_#%wndId%_isFloating  :=
	StringReplace, Bar_hideTitleWndIds, Bar_hideTitleWndIds, %wndId%`;, 
	StringReplace, Manager_allWndIds, Manager_allWndIds, %wndId%`;, 
	StringReplace, Manager_managedWndIds, Manager_managedWndIds, %wndId%`;, , All
	
	Return, a
}

Manager_winActivate(wndId) {
	Local wndHeight, wndWidth, wndX, wndY
	
	If Config_mouseFollowsFocus {
		If wndId {
			WinGetPos, wndX, wndY, wndWidth, wndHeight, ahk_id %wndId%
			DllCall("SetCursorPos", "Int", Round(wndX + wndWidth / 2), "Int", Round(wndY + wndHeight / 2))
		} Else
			DllCall("SetCursorPos", "Int", Round(Monitor_#%Manager_aMonitor%_x + Monitor_#%Manager_aMonitor%_width / 2), "Int", Round(Monitor_#%Manager_aMonitor%_y + Monitor_#%Manager_aMonitor%_height / 2))
	}
	WinActivate, ahk_id %wndId%
	Bar_updateTitle()
}

Manager_winMove(wndId, x, y, width, height) {
	WinRestore, ahk_id %wndId%
	WM_ENTERSIZEMOVE = 0x0231
	WM_EXITSIZEMOVE  = 0x0232
	SendMessage, WM_ENTERSIZEMOVE, , , , ahk_id %wndId%
	WinMove, ahk_id %wndId%, , %x%, %y%, %width%, %height%
	SendMessage, WM_EXITSIZEMOVE, , , , ahk_id %wndId%
}
