# eraBACK のウィンドウにだけキーを送り、背面のまま画面を撮る。
# 入力欄（RICHEDIT）のハンドルに PostMessage するので、他のウィンドウにキーが飛ばない。
# 使い方: & .\_tools\起動確認.ps1 -Restart -Debug -Keys "1","","2","" -Out shot.png   （"" は Enter だけ。-Restart で起動し直す）
# -Debug で EmueraEX.exe -DEBUG になり、開発用のコマンド [1990]〜[1999]（デバッグ.ERB）が効く。無いと「その番号は無い」。DEBUGPRINT もこのときだけ出る
# 必ず PowerShell の中から & で呼ぶ。powershell -File で呼ぶと -Keys の配列が "1,,2," という1本の文字列になって何も通らない（2026-09-11）
# 起動直後はロードに数秒かかる。-Restart で送ったキーが効いていなければ、もう一度 -Restart 無しで送る
param([string[]]$Keys = @(), [string]$Out = "", [switch]$Restart, [switch]$Debug)
Set-Location D:\egame\era\eraBACK
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if (-not ("Drv" -as [type])) {
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class Drv {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int L, T, R, B; }
  public static IntPtr FindRich(IntPtr p) { IntPtr f = IntPtr.Zero; EnumChildWindows(p, (h,l)=>{ var sb=new StringBuilder(256); GetClassName(h,sb,256); if (sb.ToString().Contains("RICHEDIT")) { f=h; return false; } return true; }, IntPtr.Zero); return f; }
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public static void Type(IntPtr h, string s) { foreach (char c in s) { SendMessage(h, 0x0102, (IntPtr)c, IntPtr.Zero); System.Threading.Thread.Sleep(30); } }
  // Enter は KEYDOWN/KEYUP だけで確定する（WM_CHAR は要らない）
  public static void Enter(IntPtr h) { PostMessage(h, 0x0100, (IntPtr)0x0D, (IntPtr)0x001C0001); PostMessage(h, 0x0101, (IntPtr)0x0D, (IntPtr)0xC01C0001); }
}
"@
}
$p = Get-Process EmueraEX -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "eraBACK*" } | Select-Object -First 1
if ($Restart -and $p) { $p | Stop-Process -Force; $p = $null; Start-Sleep -m 500 }
if (-not $p) {
  if ($Debug) { $p = Start-Process -FilePath ".\EmueraEX.exe" -ArgumentList "-DEBUG" -WorkingDirectory "D:\egame\era\eraBACK" -PassThru }
  else { $p = Start-Process -FilePath ".\EmueraEX.exe" -WorkingDirectory "D:\egame\era\eraBACK" -PassThru }
  Start-Sleep -Seconds 6; $p.Refresh()
}
$edit = [Drv]::FindRich($p.MainWindowHandle)
foreach ($k in $Keys) {
  if ($k -ne "") { [Drv]::Type($edit, $k) }
  [Drv]::Enter($edit); Start-Sleep -m 900
}
Start-Sleep -m 600
if ($Out -ne "") {
  $r = New-Object Drv+RECT; [Drv]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
  $bmp = New-Object System.Drawing.Bitmap ($r.R-$r.L), ($r.B-$r.T)
  $g = [System.Drawing.Graphics]::FromImage($bmp); $dc = $g.GetHdc()
  [Drv]::PrintWindow($p.MainWindowHandle, $dc, 2) | Out-Null; $g.ReleaseHdc($dc)
  $bmp.Save([string]$Out, [System.Drawing.Imaging.ImageFormat]::Png)
}
"pid $($p.Id) rich $edit"
