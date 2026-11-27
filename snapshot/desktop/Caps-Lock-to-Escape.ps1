# Save your work first. This script maps Caps Lock to Escape and restarts Windows.
$ErrorActionPreference = 'Stop'

$taskIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$taskPrincipal = [Security.Principal.WindowsPrincipal]::new($taskIdentity)
if (-not $taskPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $taskArguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $taskArguments -WindowStyle Hidden -Wait
    exit
}

try {
    $taskRegistryPath = 'SYSTEM\CurrentControlSet\Control\Keyboard Layout'
    $taskKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($taskRegistryPath, $true)
    if ($null -eq $taskKey) { throw 'Could not open the keyboard layout registry key.' }
    try {
        $taskOriginal = $taskKey.GetValue('Scancode Map')
        $taskEntries = [Collections.Generic.List[byte]]::new()
        if ($null -ne $taskOriginal) {
            if ($taskOriginal -isnot [byte[]] -or $taskOriginal.Length -lt 16) {
                throw 'Existing Scancode Map is invalid; no changes were made.'
            }
            $taskCount = [BitConverter]::ToUInt32($taskOriginal, 8)
            if ($taskCount -lt 1 -or (12L + 4L * $taskCount) -ne $taskOriginal.Length) {
                throw 'Existing Scancode Map has an invalid length; no changes were made.'
            }
            for ($taskIndex = 0; $taskIndex -lt ($taskCount - 1); $taskIndex++) {
                $taskOffset = 12 + 4 * $taskIndex
                # Replace mappings whose source key is Caps Lock (scan code 0x003A).
                if ([BitConverter]::ToUInt16($taskOriginal, $taskOffset + 2) -ne 0x003A) {
                    $taskEntries.AddRange([byte[]]$taskOriginal[$taskOffset..($taskOffset + 3)])
                }
            }
        }
        $taskEntries.AddRange([byte[]](0x01, 0x00, 0x3A, 0x00))
        $taskNewMap = [Collections.Generic.List[byte]]::new()
        $taskNewMap.AddRange([byte[]](0, 0, 0, 0, 0, 0, 0, 0))
        $taskNewMap.AddRange([BitConverter]::GetBytes([uint32]($taskEntries.Count / 4 + 1)))
        $taskNewMap.AddRange($taskEntries.ToArray())
        $taskNewMap.AddRange([byte[]](0, 0, 0, 0))
        $taskKey.SetValue('Scancode Map', $taskNewMap.ToArray(), [Microsoft.Win32.RegistryValueKind]::Binary)
        $taskReadback = $taskKey.GetValue('Scancode Map')
        if ([BitConverter]::ToString($taskReadback) -ne [BitConverter]::ToString($taskNewMap.ToArray())) {
            throw 'The registry change could not be verified.'
        }
    } finally {
        $taskKey.Close()
    }
    & shutdown.exe /r /t 0
    if ($LASTEXITCODE -ne 0) { throw 'The remap was applied, but Windows could not restart. Restart your PC manually.' }
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Caps Lock remap failed')
    exit 1
}

