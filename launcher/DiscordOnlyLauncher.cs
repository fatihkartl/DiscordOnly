// Windows GUI-subsystem launcher: no attached console. Requires Windows .NET Framework 4.x.
// The UI, resolver and winws remain separate verified files in the package.
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using System.ComponentModel;
namespace DiscordOnly {
    internal static class Launcher {
        [STAThread]
        private static void Main() {
            try {
                string root = AppDomain.CurrentDomain.BaseDirectory;
                string script = Path.Combine(root, "app", "launcher.ps1");
                if (!File.Exists(script)) throw new FileNotFoundException("Missing app\\launcher.ps1; extract all files.");
                string pwsh = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                                           "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
                ProcessStartInfo start = new ProcessStartInfo();
                start.FileName = pwsh;
                start.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + script + "\"";
                start.WorkingDirectory = root;
                start.UseShellExecute = true;
                start.Verb = "runas"; // UAC; never silently bypass admin confirmation.
                start.WindowStyle = ProcessWindowStyle.Hidden;
                Process.Start(start);
            } catch (Win32Exception ex) {
                if (ex.NativeErrorCode != 1223) // user explicitly denied UAC
                    MessageBox.Show(ex.Message, "DiscordOnly launch error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            } catch (Exception ex) {
                MessageBox.Show(ex.Message, "DiscordOnly launch error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
