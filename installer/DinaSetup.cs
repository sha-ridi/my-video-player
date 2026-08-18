// DinaPlayer — установщик/обновлятор (WinForms, .NET Framework).
// Лёгкий: сам НЕ содержит плеер, а качает свежую сборку из публичного репозитория
// GitHub Releases (dina-player-releases). Собирается build/build-installer.ps1.
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Drawing;
using System.Windows.Forms;
using Microsoft.Win32;

static class DinaSetup
{
    const string StateKey = @"Software\DinaPlayer";
    const string Classes = @"Software\Classes";

    // Публичный репозиторий только со сборками (исходный код остаётся приватным).
    const string RepoOwner = "sha-ridi";
    const string RepoName = "my-video-player";
    const string ZipUrl = "https://github.com/" + RepoOwner + "/" + RepoName + "/releases/latest/download/DinaPlayer-Portable.zip";
    const string SetupUrl = "https://github.com/" + RepoOwner + "/" + RepoName + "/releases/latest/download/DinaPlayer-Setup.exe";
    const string ApiUrl = "https://api.github.com/repos/" + RepoOwner + "/" + RepoName + "/releases/latest";

    static readonly string[] Exts = {
        ".mkv", ".mp4", ".avi", ".mov", ".webm", ".m4v", ".ts", ".flv", ".wmv", ".mpg", ".mpeg"
    };

    static DinaSetup()
    {
        // GitHub требует TLS 1.2 — на старых .NET Framework он не включён по умолчанию.
        try { ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12; } catch { }
    }

    public static string DefaultDir()
    {
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "DinaPlayer");
    }

    [STAThread]
    static void Main(string[] a)
    {
        // Скрытые режимы (для автоматизации/тестов):
        //   /extract-only <dir>            -> только скачать и распаковать (без реестра/ярлыка)
        //   /silent <dir> <def0|1> <sc0|1> -> полная установка (со скачиванием)
        //   /uninstall                     -> удалить
        if (a.Length >= 2 && a[0] == "/extract-only") { DownloadAndExtract(a[1], null); return; }
        if (a.Length >= 1 && a[0] == "/silent")
        {
            Install(a.Length > 1 ? a[1] : DefaultDir(), a.Length > 2 && a[2] == "1", a.Length > 3 && a[3] == "1", null);
            return;
        }
        if (a.Length >= 1 && a[0] == "/uninstall") { Uninstall(InstalledDir()); return; }

        // Launched by the in-player "Update DinaPlayer" button: show the normal
        // window but start the update automatically and reopen the player when done.
        if (a.Length >= 1 && a[0] == "/autoupdate") SetupForm.AutoStart = true;

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        // /preview <png> [install|update]  -> render the window to a PNG off-screen
        // (design preview only; performs no install). Never captures the desktop.
        if (a.Length >= 2 && a[0] == "/preview")
        {
            try
            {
                if (a.Length >= 3 && a[2] == "autoupdate") { SetupForm.PreviewMode = 2; SetupForm.AutoStart = true; }
                else SetupForm.PreviewMode = (a.Length >= 3 && a[2] == "update") ? 2 : 1;
                if (a.Length >= 4 && a[3] == "dl") SetupForm.PreviewDownload = true;
                using (var f = new SetupForm())
                {
                    f.StartPosition = FormStartPosition.Manual;
                    f.Location = new Point(-4000, -4000);
                    f.ShowInTaskbar = false;
                    f.Show();
                    Application.DoEvents();
                    System.Threading.Thread.Sleep(1500); // long enough for the version check to land
                    Application.DoEvents();
                    // Whole window, not just the client area: DrawToBitmap paints the
                    // frame too, so a client-sized bitmap would clip the bottom row.
                    using (var bmp = new Bitmap(f.Width, f.Height))
                    {
                        f.DrawToBitmap(bmp, new Rectangle(0, 0, f.Width, f.Height));
                        bmp.Save(a[1], System.Drawing.Imaging.ImageFormat.Png);
                    }
                    f.Close();
                }
            }
            catch (Exception ex)
            {
                try { File.WriteAllText(a[1] + ".err.txt", ex.ToString()); } catch { }
            }
            Environment.Exit(0);
            return;
        }

        Application.Run(new SetupForm());
    }

    // ---- состояние (реестр) ----
    public static string InstalledDir()
    {
        using (var k = Registry.CurrentUser.OpenSubKey(StateKey))
            return k == null ? null : k.GetValue("InstallDir") as string;
    }
    public static string InstalledVersion()
    {
        using (var k = Registry.CurrentUser.OpenSubKey(StateKey))
            return k == null ? null : k.GetValue("Version") as string;
    }
    public static bool StateBool(string name)
    {
        using (var k = Registry.CurrentUser.OpenSubKey(StateKey))
            return k != null && Convert.ToInt32(k.GetValue(name, 0)) == 1;
    }
    static void SaveState(string dir, bool def, bool shortcut, string version)
    {
        using (var k = Registry.CurrentUser.CreateSubKey(StateKey))
        {
            k.SetValue("InstallDir", dir);
            k.SetValue("SetDefault", def ? 1 : 0, RegistryValueKind.DWord);
            k.SetValue("Shortcut", shortcut ? 1 : 0, RegistryValueKind.DWord);
            if (version != null) k.SetValue("Version", version);
        }
    }

    // ---- сеть ----
    // Последняя версия (tag_name последнего релиза) или null, если недоступно.
    public static string GetLatestVersion()
    {
        try
        {
            var req = (HttpWebRequest)WebRequest.Create(ApiUrl);
            req.UserAgent = "DinaPlayer-Setup";
            req.Accept = "application/vnd.github+json";
            req.Timeout = 15000;
            using (var resp = req.GetResponse())
            using (var r = new StreamReader(resp.GetResponseStream()))
            {
                var json = r.ReadToEnd();
                var m = Regex.Match(json, "\"tag_name\"\\s*:\\s*\"([^\"]+)\"");
                return m.Success ? m.Groups[1].Value : null;
            }
        }
        catch { return null; }
    }

    static void DownloadFile(string url, string dest, Action<int> progress)
    {
        var req = (HttpWebRequest)WebRequest.Create(url);
        req.UserAgent = "DinaPlayer-Setup";
        req.AllowAutoRedirect = true;
        req.Timeout = 30000;
        using (var resp = (HttpWebResponse)req.GetResponse())
        using (var input = resp.GetResponseStream())
        using (var output = File.Create(dest))
        {
            long total = resp.ContentLength;
            var buf = new byte[81920];
            long got = 0; int n; int last = -1;
            while ((n = input.Read(buf, 0, buf.Length)) > 0)
            {
                output.Write(buf, 0, n);
                got += n;
                if (progress != null && total > 0)
                {
                    int pct = (int)(got * 100 / total);
                    if (pct != last) { last = pct; progress(pct); }
                }
            }
        }
    }

    // ---- скачать + распаковать (без реестра/ярлыка) ----
    static void DownloadAndExtract(string dir, Action<int> progress)
    {
        var tmp = Path.Combine(Path.GetTempPath(), "dina-setup-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tmp);
        try
        {
            var zipPath = Path.Combine(tmp, "player.zip");
            DownloadFile(ZipUrl, zipPath, progress);

            var stage = Path.Combine(tmp, "stage");
            ZipFile.ExtractToDirectory(zipPath, stage);

            Directory.CreateDirectory(dir);
            // Копируем поверх (перезапись); ничего не удаляем, поэтому watch_later и
            // *-on-start.state (прогресс и настройки) переживают обновление.
            CopyDir(stage, dir);
        }
        finally { try { Directory.Delete(tmp, true); } catch { } }
    }

    // ---- установка / обновление ----
    public static void Install(string dir, bool def, bool shortcut, Action<int> progress)
    {
        var version = GetLatestVersion();
        DownloadAndExtract(dir, progress);
        // Keep a copy of the installer next to the player so its "update" button
        // works — and refresh it to the latest so installer fixes reach users on
        // a normal player update. Falls back to copying ourselves if download fails.
        if (!RefreshBundledSetup(dir)) CopySelfTo(dir);

        var exe = Path.Combine(dir, "DinaPlayer.exe");
        var playFolder = Path.Combine(dir, "play-folder.ps1");

        if (shortcut) { InstallMenu(exe, playFolder); CreateShortcut(exe, dir); }
        else { RemoveMenu(); DeleteShortcut(); }

        // Only ever ADD the default registration here. Never UnregisterDefault on
        // install/update: deleting the DinaPlayer.Video ProgID orphans Windows'
        // UserChoice for the video extensions and silently resets the user's
        // default player. Removing the default is left to Uninstall only.
        if (def) RegisterDefault(exe);

        // Preserve a previously-saved SetDefault=1 across updates: if the box is
        // unchecked now we still don't wipe the association, so keep the flag truthful
        // to whether DinaPlayer is (still) registered as a default option.
        SaveState(dir, def || IsRegisteredDefault(), shortcut, version);
    }

    public static void Uninstall(string dir)
    {
        RemoveMenu();
        DeleteShortcut();
        UnregisterDefault();
        try { if (dir != null && Directory.Exists(dir)) Directory.Delete(dir, true); } catch { }
        try { Registry.CurrentUser.DeleteSubKeyTree(StateKey, false); } catch { }
    }

    // Copy this Setup.exe next to the player, so the in-player "Обновить плеер"
    // button can launch it. Skipped when we're already running from there
    // (e.g. launched by that very button) to avoid copying onto a locked file.
    // Download the latest Setup.exe and make it the bundled <dir>\DinaPlayer-Setup.exe.
    // Windows lets us RENAME a running exe (not overwrite/delete it), so when we're
    // running from the bundled copy we move it aside to *.old and drop the new one in.
    // The *.old is cleaned up on a later run (once that process has exited).
    static bool RefreshBundledSetup(string dir)
    {
        var dest = Path.Combine(dir, "DinaPlayer-Setup.exe");
        var tmp = dest + ".new";
        var old = dest + ".old";
        try
        {
            try { if (File.Exists(old)) File.Delete(old); } catch { } // leftover from a previous update
            DownloadFile(SetupUrl, tmp, null);
            if (!File.Exists(tmp) || new FileInfo(tmp).Length < 200000) { try { File.Delete(tmp); } catch { } return false; }

            var self = Assembly.GetExecutingAssembly().Location;
            bool fromDest = !string.IsNullOrEmpty(self) &&
                string.Equals(Path.GetFullPath(self), Path.GetFullPath(dest), StringComparison.OrdinalIgnoreCase);
            bool moved = false;
            if (File.Exists(dest))
            {
                if (fromDest) { File.Move(dest, old); moved = true; } // rename the running exe aside
                else File.Delete(dest);
            }
            try { File.Move(tmp, dest); }
            catch { if (moved && !File.Exists(dest)) { try { File.Move(old, dest); } catch { } } throw; }
            return true;
        }
        catch { try { if (File.Exists(tmp)) File.Delete(tmp); } catch { } return false; }
    }

    static void CopySelfTo(string dir)
    {
        try
        {
            var self = Assembly.GetExecutingAssembly().Location;
            var dest = Path.Combine(dir, "DinaPlayer-Setup.exe");
            if (!string.IsNullOrEmpty(self) &&
                !string.Equals(Path.GetFullPath(self), Path.GetFullPath(dest), StringComparison.OrdinalIgnoreCase))
            {
                File.Copy(self, dest, true);
            }
        }
        catch { }
    }

    static void CopyDir(string src, string dst)
    {
        Directory.CreateDirectory(dst);
        string self = null;
        try { self = Path.GetFullPath(Assembly.GetExecutingAssembly().Location); } catch { }
        foreach (var f in Directory.GetFiles(src))
        {
            var dest = Path.Combine(dst, Path.GetFileName(f));
            // Never overwrite the running installer (locked); RefreshBundledSetup
            // swaps the bundled Setup.exe separately via rename.
            if (self != null && string.Equals(Path.GetFullPath(dest), self, StringComparison.OrdinalIgnoreCase)) continue;
            CopyOverBusy(f, dest);
        }
        foreach (var d in Directory.GetDirectories(src))
            CopyDir(d, Path.Combine(dst, Path.GetFileName(d)));
    }

    // Overwrite a file that may still be briefly locked. The one-press "Update
    // DinaPlayer" button closes the player and updates within milliseconds, so
    // Windows can still hold a handle on the big DinaPlayer.exe when we copy over
    // it. Retry for a few seconds instead of failing the whole update.
    static void CopyOverBusy(string src, string dest)
    {
        for (int attempt = 0; ; attempt++)
        {
            try { File.Copy(src, dest, true); return; }
            catch (Exception)
            {
                if (attempt >= 40) throw;                  // give up after ~10s, surface the real error
                System.Threading.Thread.Sleep(250);
            }
        }
    }

    // ---- контекстное меню (HKCU) ----
    static void SetMenu(string keyPath, string label, string command, string icon)
    {
        using (var k = Registry.CurrentUser.CreateSubKey(keyPath))
        {
            k.SetValue(null, label);
            k.SetValue("Icon", icon);
            using (var c = k.CreateSubKey("command")) c.SetValue(null, command);
        }
    }
    static void InstallMenu(string exe, string playFolder)
    {
        foreach (var ext in Exts)
            SetMenu(Classes + @"\SystemFileAssociations\" + ext + @"\shell\DinaPlayer",
                "Play with DinaPlayer", "\"" + exe + "\" \"%1\"", exe + ",0");
        var fcmd = "powershell -NoProfile -ExecutionPolicy Bypass -File \"" + playFolder + "\" \"%V\"";
        SetMenu(Classes + @"\Directory\shell\DinaPlayer", "Play with DinaPlayer", fcmd, exe + ",0");
        SetMenu(Classes + @"\Directory\Background\shell\DinaPlayer", "Play with DinaPlayer", fcmd, exe + ",0");
    }
    static void RemoveMenu()
    {
        foreach (var ext in Exts)
            Del(Classes + @"\SystemFileAssociations\" + ext + @"\shell\DinaPlayer");
        Del(Classes + @"\Directory\shell\DinaPlayer");
        Del(Classes + @"\Directory\Background\shell\DinaPlayer");
    }
    static void Del(string path) { try { Registry.CurrentUser.DeleteSubKeyTree(path, false); } catch { } }

    // ---- ярлык на рабочем столе ----
    static string DesktopLnk()
    {
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "DinaPlayer.lnk");
    }
    static void CreateShortcut(string exe, string workdir)
    {
        try
        {
            object shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
            object sc = shell.GetType().InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { DesktopLnk() });
            var t = sc.GetType();
            t.InvokeMember("TargetPath", BindingFlags.SetProperty, null, sc, new object[] { exe });
            t.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, sc, new object[] { workdir });
            t.InvokeMember("IconLocation", BindingFlags.SetProperty, null, sc, new object[] { exe + ",0" });
            t.InvokeMember("Save", BindingFlags.InvokeMethod, null, sc, null);
        }
        catch { }
    }
    static void DeleteShortcut() { try { File.Delete(DesktopLnk()); } catch { } }

    // ---- плеер по умолчанию (best effort; Win11 просит подтвердить) ----
    static void RegisterDefault(string exe)
    {
        using (var p = Registry.CurrentUser.CreateSubKey(Classes + @"\DinaPlayer.Video"))
        {
            p.SetValue(null, "Video (DinaPlayer)");
            using (var di = p.CreateSubKey("DefaultIcon")) di.SetValue(null, exe + ",0");
            using (var c = p.CreateSubKey(@"shell\open\command")) c.SetValue(null, "\"" + exe + "\" \"%1\"");
        }
        foreach (var ext in Exts)
            using (var e = Registry.CurrentUser.CreateSubKey(Classes + "\\" + ext + @"\OpenWithProgIds"))
                e.SetValue("DinaPlayer.Video", new byte[0], RegistryValueKind.None);
    }
    // True if our ProgID registration is present (an "open with" option exists).
    public static bool IsRegisteredDefault()
    {
        using (var k = Registry.CurrentUser.OpenSubKey(Classes + @"\DinaPlayer.Video"))
            return k != null;
    }
    // True if Windows currently has DinaPlayer as the actual default (UserChoice)
    // for at least one of the video extensions.
    public static bool IsDefaultNow()
    {
        foreach (var ext in Exts)
        {
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\" + ext + @"\UserChoice"))
                    if (k != null && (k.GetValue("ProgId") as string) == "DinaPlayer.Video") return true;
            }
            catch { }
        }
        return false;
    }
    static void UnregisterDefault()
    {
        Del(Classes + @"\DinaPlayer.Video");
        foreach (var ext in Exts)
            try { using (var e = Registry.CurrentUser.OpenSubKey(Classes + "\\" + ext + @"\OpenWithProgIds", true)) { if (e != null) e.DeleteValue("DinaPlayer.Video", false); } }
            catch { }
    }
    // Start the freshly updated player. Its last-session state reopens whatever
    // was playing before the update, so "Update DinaPlayer" feels seamless.
    public static void LaunchPlayer(string dir)
    {
        try
        {
            var exe = Path.Combine(dir, "DinaPlayer.exe");
            if (File.Exists(exe))
                Process.Start(new ProcessStartInfo { FileName = exe, WorkingDirectory = dir, UseShellExecute = true });
        }
        catch { }
    }
    public static void OpenDefaultSettings() { try { Process.Start("ms-settings:defaultapps"); } catch { } }

    public static bool IsRunning()
    {
        try { return Process.GetProcessesByName("DinaPlayer").Length > 0; } catch { return false; }
    }
}
