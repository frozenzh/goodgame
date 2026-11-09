$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
# 封装 Win32 显示设备枚举接口，读取原生设备标识。
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
// 声明枚举屏幕时使用的原生结构体和入口。
public class DisplayNames {
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
 public struct Device { public int cb; [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string DeviceName; [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string DeviceString; public int StateFlags; [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string DeviceID; [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string DeviceKey; }
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern bool EnumDisplayDevices(string device,uint index,ref Device output,uint flags);
}
"@
# WMI 提供可读名称。查询失败时沿用系统或 Win32 名称。
$monitors = @(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)
# 枚举所有屏幕，同时保留它们在虚拟桌面中的坐标。
$result = @(foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
 $device = New-Object DisplayNames+Device
 # 原生接口要求先填写结构体字节数。
 $device.cb = [Runtime.InteropServices.Marshal]::SizeOf($device)
 $name = $screen.DeviceName
 # 枚举成功时，先采用驱动返回的设备名。
 if ([DisplayNames]::EnumDisplayDevices($screen.DeviceName,0,[ref]$device,0)) {
  $name = $device.DeviceString
  $parts = $device.DeviceID -split '\\'
  # 用设备 ID 匹配 WMI 的显示器实例。
  foreach ($monitor in $monitors) {
   # 确认设备 ID 有足够字段，再用前缀进行不区分大小写的比较。
   if ($parts.Length -gt 2 -and $monitor.InstanceName.StartsWith(('DISPLAY\'+$parts[1]+'\'+$parts[2]),[StringComparison]::OrdinalIgnoreCase)) {
    # 过滤 WMI 名称字段的零填充，再组合为字符串。
    $friendly = -join ($monitor.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
    # 可读名称为空时保留此前取得的名称。
    if ($friendly) { $name = $friendly }
   }
  }
 }
 @{name=$name;x=$screen.Bounds.X;y=$screen.Bounds.Y}
})
# 单屏和多屏都输出数组，便于游戏使用同一解析逻辑。
ConvertTo-Json -InputObject $result -Compress
