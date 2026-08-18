// DinaPlayer setup window — dark, minimalist, styled after the player itself.
// Inter font and the DinaFace watermark are embedded into the exe (see
// build/build-installer.ps1 /resource flags) so it looks the same on any PC.
// The app is DPI-aware (see installer/app.manifest); this form scales every
// pixel dimension by the current DPI so it stays crisp at 125%/150%/… scaling
// instead of being bitmap-stretched (blurry). Fonts are in points, so they
// scale with the DPI on their own.
// Only the LOOK lives here; the update logic (registry key, download/extract)
// is untouched in DinaSetup.cs, so a redesigned installer still recognizes an
// existing install and updates it in place.
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

class SetupForm : Form
{
    // 0 = auto (decide from registry), 1 = force install look, 2 = force update look.
    public static int PreviewMode = 0;
    // Preview only: render the install/update window mid-download (bar + caption).
    public static bool PreviewDownload = false;

    // Set by the /autoupdate launch (the in-player "Update DinaPlayer" button):
    // start the update on its own, no manual click.
    public static bool AutoStart = false;

    // ---- palette (matched to the DinaPlayer website: near-black background,
    // off-white text and primary button, neutral greys — no red accent) ----
    static readonly Color BG       = Color.FromArgb(0x0D, 0x0D, 0x0F);
    static readonly Color SURFACE2 = Color.FromArgb(0x26, 0x26, 0x2A);
    static readonly Color TEXT     = Color.FromArgb(0xF5, 0xF5, 0xF6);
    static readonly Color MUTED    = Color.FromArgb(0xA6, 0xA6, 0xAA);
    static readonly Color BTN_TEXT = Color.FromArgb(0x0C, 0x0C, 0x0D);
    static readonly Color DANGER   = Color.FromArgb(0xE0, 0x6A, 0x6A); // errors only, not the UI
    static readonly Color CHK_EDGE = Color.FromArgb(0x6F, 0x6F, 0x74);

    readonly float S;                 // DPI scale (1.0 = 96 DPI, 1.5 = 150%)
    int P(double v) { return (int)Math.Round(v * S); }

    bool isUpdate;
    bool minimal;                     // /autoupdate: bare progress bar, nothing else
    string existingDir;
    string installDir;               // chosen install location (fresh install)
    FlatLabel lblPath;               // quiet one-line install location
    CheckBox chkDefault, chkShortcut;
    Button btnPrimary;
    LinkText lnkRemove;              // update run: quiet "Remove" link
    FlatLabel lblStatus;             // download %, hidden at rest
    SlimBar bar;                      // slim white progress bar (install / update)
    SlimBar slim;                     // owner-drawn bar used by the minimal window
    CloseButton btnMiniClose;         // revealed only if a /autoupdate run fails
    static Image _icon;               // app icon shown in the header
    Rectangle _iconRect;              // where OnPaint draws it (empty in minimal mode)

    // Everything in the content column starts at exactly this x — see FlatLabel
    // and DarkCheck, which both had a few pixels of built-in leading padding.
    const int MARGIN = 28;
    const int WIDTH = 470;   // window content width in logical px

    public SetupForm()
    {
        S = DpiScale();

        existingDir = DinaSetup.InstalledDir();
        isUpdate = existingDir != null && File.Exists(Path.Combine(existingDir, "DinaPlayer.exe"));
        if (PreviewMode == 1) isUpdate = false;
        else if (PreviewMode == 2) { isUpdate = true; if (existingDir == null) existingDir = DinaSetup.DefaultDir(); }

        _icon = _icon ?? LoadIcon("dinaicon.ico");

        // Own frame: Windows draws its close glyph at a fixed tiny size, so the
        // caption row below is ours — same left margin as the rest of the column,
        // and a close button we can actually make big. `Text` still feeds the
        // taskbar and alt-tab.
        Text = "DinaPlayer";
        Font = F(10f, FontStyle.Regular);
        FormBorderStyle = FormBorderStyle.None;
        MaximizeBox = false; MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.None; // we scale manually; no WinForms auto-scale
        BackColor = BG;
        ForeColor = TEXT;
        DoubleBuffered = true;
        KeyPreview = true;

        // Launched by the in-player button: no chrome, no choices — just a slim
        // progress bar and its caption. Build that and stop.
        if (AutoStart && isUpdate) { BuildMinimal(); return; }

        int cap = P(44);
        int titleY = P(28), titleH = P(34);
        installDir = existingDir ?? DinaSetup.DefaultDir();

        // Close button, inset P(5) from the top-right corner.
        var btnClose = new CloseButton(TEXT, SURFACE2, BG) {
            Location = new Point(P(WIDTH) - cap - P(5), P(5)),
            Size = new Size(cap, cap), HoverInset = P(7), HoverRadius = P(9)
        };
        btnClose.Click += (s, e) => Close();
        Controls.Add(btnClose);

        // Header: app icon (painted in OnPaint at _iconRect) + title, flush left.
        int icoSz = _icon != null ? P(30) : 0;
        int icoGap = _icon != null ? P(12) : 0;
        var titleFont = F(16.5f, FontStyle.Bold);
        string titleText = isUpdate ? "Update DinaPlayer" : "Install DinaPlayer";
        int titleX = P(MARGIN) + icoSz + icoGap;
        var lblTitle = new FlatLabel {
            Text = titleText, Font = titleFont, ForeColor = TEXT, BackColor = Color.Transparent,
            Location = new Point(titleX, titleY),
            Size = new Size(btnClose.Left - P(8) - titleX, titleH)
        };
        lblTitle.MouseDown += DragMove;
        Controls.Add(lblTitle);
        if (icoSz > 0)
        {
            int textH = TextRenderer.MeasureText(titleText, titleFont,
                new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding).Height;
            var fam = titleFont.FontFamily;
            FontStyle ms = fam.IsStyleAvailable(titleFont.Style) ? titleFont.Style
                : (fam.IsStyleAvailable(FontStyle.Regular) ? FontStyle.Regular : FontStyle.Bold);
            float descentPx;
            try { descentPx = titleFont.GetHeight() * fam.GetCellDescent(ms) / (float)fam.GetLineSpacing(ms); }
            catch { descentPx = textH * 0.18f; }
            int baseline = titleY + (titleH + textH) / 2 - (int)Math.Round(descentPx);
            int drop = (int)Math.Round(descentPx * 0.6f);
            _iconRect = new Rectangle(P(MARGIN), baseline + drop - icoSz, icoSz, icoSz);
        }

        int y = lblTitle.Bottom + P(26);

        // Install only: a quiet one-line install location + a "Change" link, instead
        // of a full path field. Most users never touch it.
        if (!isUpdate)
        {
            lblPath = new FlatLabel {
                Font = F(9.5f, FontStyle.Regular), ForeColor = MUTED, BackColor = Color.Transparent,
                Location = new Point(P(MARGIN), y), Size = new Size(P(320), P(20))
            };
            UpdatePathLabel();
            Controls.Add(lblPath);

            var lnkChange = new LinkText {
                Text = "Change", Font = F(9.5f, FontStyle.Regular), Idle = MUTED, Hot = TEXT,
                ForeColor = MUTED, BackColor = Color.Transparent,
                Location = new Point(P(MARGIN) + P(326), y), Size = new Size(P(80), P(20))
            };
            lnkChange.Click += (s, e) => Browse();
            Controls.Add(lnkChange);

            y = lblPath.Bottom + P(26);
        }

        chkShortcut = Check("Desktop shortcut & right-click menu", P(MARGIN), y,
            isUpdate ? DinaSetup.StateBool("Shortcut") : true);
        Controls.Add(chkShortcut);

        chkDefault = Check("Make default player", P(MARGIN), chkShortcut.Bottom + P(14),
            isUpdate && (DinaSetup.StateBool("SetDefault") || DinaSetup.IsDefaultNow()));
        Controls.Add(chkDefault);

        int by = chkDefault.Bottom + P(28);

        btnPrimary = new RoundButton {
            Text = isUpdate ? "Update" : "Install",
            Location = new Point(P(MARGIN), by), Size = new Size(P(160), P(46)),
            ForeColor = BTN_TEXT, Font = F(11.5f, FontStyle.Bold), Cursor = Hand(),
            Normal = TEXT, Hover = Color.FromArgb(0xE4, 0xE4, 0xE6),
            Down = Color.FromArgb(0xCF, 0xCF, 0xD2), Bg = BG, Radius = P(12)
        };
        btnPrimary.Click += (s, e) => DoPrimary();
        Controls.Add(btnPrimary);

        // Update only: uninstall as a quiet grey link to the right of Update — not a
        // red button. (Vertically centred on the button row.)
        if (isUpdate)
        {
            lnkRemove = new LinkText {
                Text = "Remove", Font = F(10f, FontStyle.Regular), Idle = MUTED, Hot = TEXT,
                ForeColor = MUTED, BackColor = Color.Transparent,
                Location = new Point(btnPrimary.Right + P(32), by), Size = new Size(P(160), btnPrimary.Height)
            };
            lnkRemove.Click += (s, e) => DoUninstall();
            Controls.Add(lnkRemove);
        }

        // Download progress replaces the button row while running; hidden at rest,
        // so there's no empty band and no status text sitting idle.
        bar = new SlimBar(SURFACE2, TEXT) {
            Location = new Point(P(MARGIN), btnPrimary.Top + P(12)), Size = new Size(P(414), P(6)),
            Visible = false
        };
        Controls.Add(bar);
        lblStatus = new FlatLabel {
            Text = "", Font = F(10f, FontStyle.Regular), ForeColor = TEXT, BackColor = Color.Transparent,
            Location = new Point(P(MARGIN), btnPrimary.Top + P(24)), Size = new Size(P(414), P(20)),
            Visible = false
        };
        Controls.Add(lblStatus);

        ClientSize = new Size(P(WIDTH), btnPrimary.Bottom + P(24));
        MouseDown += DragMove;
    }

    // Hand the drag off to Windows, so snapping and multi-monitor behave natively.
    void DragMove(object sender, MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left) return;
        ReleaseCapture();
        SendMessage(Handle, 0xA1 /* WM_NCLBUTTONDOWN */, (IntPtr)2 /* HTCAPTION */, IntPtr.Zero);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Escape) Close();
        base.OnKeyDown(e);
    }

    // ---- flat dark background (no watermark; the brand is the header icon) ----
    protected override void OnPaintBackground(PaintEventArgs e)
    {
        e.Graphics.Clear(BG);
    }

    // Header app icon, drawn over the flat background beside the title label.
    // (No window outline — the frameless dark window carries no border.)
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        if (_icon != null && !minimal && _iconRect.Width > 0)
        {
            e.Graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            e.Graphics.DrawImage(_icon, _iconRect);
        }
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        try { if (btnPrimary != null) btnPrimary.Focus(); } catch { }

        // Preview only: show the mid-download look (bar + caption replacing the button).
        if (PreviewDownload && bar != null) { EnterBusy("Downloading… 42%"); bar.Value = 42; }

        // Launched by the in-player button: start the update ourselves. Only for a
        // real update (an install has nothing to update and needs a chosen folder).
        // PreviewMode renders the window without touching the disk.
        if (AutoStart && isUpdate && PreviewMode == 0) AutoUpdate();
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        // Win11: round the window corners (like the player's rounded rectangles) and
        // get a soft shadow that separates this borderless dark window from the
        // desktop. Attribute 33 = DWMWA_WINDOW_CORNER_PREFERENCE, 2 = round. No-op
        // on Win10, where the call just returns an error we ignore.
        try { int round = 2; DwmSetWindowAttribute(Handle, 33, ref round, sizeof(int)); }
        catch { }
    }

    // The minimal /autoupdate window: a slim bar and a single caption, nothing else.
    void BuildMinimal()
    {
        minimal = true;
        int m = P(24), w = P(300);
        int cw = m + w + m;

        // Always visible: a title-bar-less window must never trap the user. Whether
        // the update is running, done, failed, or stuck, × (or Esc) is the way out.
        // Same size and rounded-chip hover as the main window's close button, so it
        // doesn't look like a tiny odd round dot.
        int mcap = P(36);
        btnMiniClose = new CloseButton(TEXT, SURFACE2, BG) {
            Location = new Point(cw - mcap - P(4), P(4)), Size = new Size(mcap, mcap),
            HoverInset = P(6), HoverRadius = P(8)
        };
        btnMiniClose.Click += (s, e) => Close();
        Controls.Add(btnMiniClose);

        slim = new SlimBar(SURFACE2, TEXT) {
            Location = new Point(m, P(52)), Size = new Size(w, P(6))
        };
        Controls.Add(slim);

        lblStatus = new FlatLabel {
            Text = "Downloading…", Font = F(10f, FontStyle.Regular),
            ForeColor = TEXT, BackColor = Color.Transparent,
            Location = new Point(m, slim.Bottom + P(14)), Size = new Size(w, P(20))
        };
        Controls.Add(lblStatus);

        ClientSize = new Size(cw, lblStatus.Bottom + P(20));
        MouseDown += DragMove; // draggable even without a caption row

        if (PreviewMode != 0) { slim.Value = 42; lblStatus.Text = "Downloading… 42%"; }
    }

    // The button quits the player AFTER launching us, so the player may still be
    // exiting. Wait for it to go (up to ~5s), then update in place and relaunch —
    // no clicks, no dialogs. Update settings carry over from the saved state.
    void AutoUpdate()
    {
        var dir = existingDir;
        bool def = DinaSetup.StateBool("SetDefault") || DinaSetup.IsDefaultNow();
        bool sc  = DinaSetup.StateBool("Shortcut");

        Action<int> progress = pct => { try { BeginInvoke((Action)(() =>
        {
            slim.Value = pct;
            lblStatus.Text = pct >= 100 ? "Installing…" : ("Downloading… " + pct + "%");
        })); } catch { } };

        var th = new Thread(() =>
        {
            // Wait for the player to exit (up to ~15s), then give Windows a moment to
            // release the handle on the big DinaPlayer.exe before we copy over it.
            for (int i = 0; i < 150 && DinaSetup.IsRunning(); i++) Thread.Sleep(100);
            Thread.Sleep(600);

            string err = null;
            try { DinaSetup.Install(dir, def, sc, progress); }
            catch (Exception ex)
            {
                err = ex.Message;
                try { File.WriteAllText(Path.Combine(dir, "update-error.log"),
                    DateTime.Now + Environment.NewLine + ex); } catch { }
            }

            try { BeginInvoke((Action)(() =>
            {
                if (err != null)
                {
                    lblStatus.ForeColor = DANGER;
                    lblStatus.Text = "Update failed.";   // × is always visible; no hint needed
                    return;
                }
                DinaSetup.LaunchPlayer(dir);
                Close();
            })); } catch { }
        });
        th.IsBackground = true; th.Start();
    }

    // (The window has no system titlebar to darken any more — the caption row is ours.)

    [DllImport("user32.dll")]
    static extern uint GetDpiForSystem();

    [DllImport("user32.dll")]
    static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    static extern IntPtr LoadImage(IntPtr hinst, IntPtr name, uint type, int cx, int cy, uint load);

    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);

    static float DpiScale()
    {
        try { uint d = GetDpiForSystem(); if (d >= 96) return d / 96f; } catch { }
        try { using (var g = Graphics.FromHwnd(IntPtr.Zero)) return g.DpiX / 96f; } catch { }
        return 1f;
    }

    // A hand cursor sized for the current DPI. WinForms' built-in Cursors.Hand is a
    // fixed 32px bitmap, so at 150%/200% it looks tiny next to Windows' own scaled
    // arrow; loading the system hand (OCR_HAND) at the scaled size fixes that.
    static Cursor _hand;
    internal static Cursor Hand()
    {
        if (_hand != null) return _hand;
        try
        {
            int sz = (int)Math.Round(32 * DpiScale());
            const uint IMAGE_CURSOR = 2, LR_SHARED = 0x8000;
            const int OCR_HAND = 32649;
            IntPtr h = LoadImage(IntPtr.Zero, (IntPtr)OCR_HAND, IMAGE_CURSOR, sz, sz, LR_SHARED);
            _hand = h != IntPtr.Zero ? new Cursor(h) : Cursors.Hand;
        }
        catch { _hand = Cursors.Hand; }
        return _hand;
    }

    CheckBox Check(string text, int x, int y, bool chk)
    {
        return new DarkCheck(TEXT, CHK_EDGE, TEXT, BG) {
            Text = text, Location = new Point(x, y), Size = new Size(P(414), P(24)), Checked = chk,
            Font = F(9.5f, FontStyle.Regular), BackColor = BG
        };
    }

    // ---- embedded Inter font (falls back to Segoe UI if anything goes wrong) ----
    static PrivateFontCollection _pfc;
    static FontFamily _inter;
    static bool _fontTried;

    static void EnsureFont()
    {
        if (_fontTried) return;
        _fontTried = true;
        try
        {
            var asm = Assembly.GetExecutingAssembly();
            using (var s = asm.GetManifestResourceStream("Inter.ttf"))
            {
                if (s == null) return;
                var data = new byte[s.Length];
                int off = 0, r;
                while ((r = s.Read(data, off, data.Length - off)) > 0) off += r;
                IntPtr p = Marshal.AllocCoTaskMem(data.Length);
                Marshal.Copy(data, 0, p, data.Length);
                _pfc = new PrivateFontCollection();
                _pfc.AddMemoryFont(p, data.Length); // p intentionally kept for app lifetime
                if (_pfc.Families.Length > 0) _inter = _pfc.Families[0];
            }
        }
        catch { _inter = null; }
    }

    static Font F(float size, FontStyle style)
    {
        EnsureFont();
        if (_inter != null)
        {
            try
            {
                if (_inter.IsStyleAvailable(style)) return new Font(_inter, size, style);
                if (_inter.IsStyleAvailable(FontStyle.Regular)) return new Font(_inter, size, FontStyle.Regular);
            }
            catch { }
        }
        return new Font("Segoe UI", size, style);
    }

    // Load an embedded .ico and return its largest frame as a bitmap we can
    // downscale crisply to the header size at any DPI. dinaplayer.ico stores every
    // frame as PNG, which the GDI Icon class decodes to garbage — so parse the
    // icon directory ourselves and decode the biggest frame's PNG bytes directly.
    static Image LoadIcon(string res)
    {
        try
        {
            byte[] b;
            using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream(res))
            {
                if (s == null) return null;
                using (var ms = new MemoryStream()) { s.CopyTo(ms); b = ms.ToArray(); }
            }
            int count = BitConverter.ToUInt16(b, 4);
            int bestW = -1, bestOff = 0, bestLen = 0;
            for (int i = 0; i < count; i++)
            {
                int o = 6 + i * 16;
                int w = b[o] == 0 ? 256 : b[o];
                if (w > bestW)
                {
                    bestW = w;
                    bestLen = BitConverter.ToInt32(b, o + 8);
                    bestOff = BitConverter.ToInt32(b, o + 12);
                }
            }
            if (bestW < 0) return null;
            bool isPng = bestLen > 8 && b[bestOff] == 0x89 && b[bestOff + 1] == 0x50
                && b[bestOff + 2] == 0x4E && b[bestOff + 3] == 0x47;
            if (isPng)
                using (var fs = new MemoryStream(b, bestOff, bestLen))
                using (var img = Image.FromStream(fs))
                    return new Bitmap(img); // detached copy, so the stream can close
            using (var ms2 = new MemoryStream(b))
            using (var ico = new Icon(ms2, bestW, bestW))
                return ico.ToBitmap(); // classic (uncompressed) frame
        }
        catch { }
        return null;
    }

    void Browse()
    {
        using (var d = new FolderBrowserDialog { Description = "Choose a folder for DinaPlayer" })
            if (d.ShowDialog() == DialogResult.OK)
            {
                installDir = Path.Combine(d.SelectedPath, "DinaPlayer");
                UpdatePathLabel();
            }
    }

    // While an install/update/remove runs, the button row is replaced by the
    // progress bar + caption (so there's no idle status text and no empty band).
    void EnterBusy(string status)
    {
        btnPrimary.Visible = false;
        if (lnkRemove != null) lnkRemove.Visible = false;
        bar.Value = 0; bar.Visible = true;
        lblStatus.ForeColor = TEXT; lblStatus.Text = status ?? ""; lblStatus.Visible = true;
        Cursor = Cursors.WaitCursor;
    }
    void ExitBusy()
    {
        bar.Visible = false; lblStatus.Visible = false;
        btnPrimary.Visible = true;
        if (lnkRemove != null) lnkRemove.Visible = true;
        Cursor = Cursors.Default;
    }

    void UpdatePathLabel() { if (lblPath != null) lblPath.Text = installDir; }

    void DoPrimary()
    {
        var dir = isUpdate ? existingDir : installDir;
        if (string.IsNullOrEmpty(dir)) { MessageBox.Show(this, "Choose a folder first.", "DinaPlayer"); return; }
        if (DinaSetup.IsRunning())
        {
            MessageBox.Show(this, "Close DinaPlayer first.", "DinaPlayer");
            return;
        }
        bool def = chkDefault.Checked, sc = chkShortcut.Checked;
        // Only pop Windows' Default-apps page when default is being turned ON now,
        // not on every routine update where it was already the default (annoying).
        bool wasDefault = isUpdate && (DinaSetup.StateBool("SetDefault") || DinaSetup.IsDefaultNow());
        EnterBusy("Downloading…");

        Action<int> progress = pct => BeginInvoke((Action)(() =>
        {
            bar.Value = Math.Min(100, Math.Max(0, pct));
            lblStatus.Text = pct >= 100 ? "Installing…" : ("Downloading… " + pct + "%");
        }));

        var th = new Thread(() =>
        {
            string err = null;
            try { DinaSetup.Install(dir, def, sc, progress); } catch (Exception ex) { err = ex.Message; }
            BeginInvoke((Action)(() =>
            {
                if (err != null)
                {
                    ExitBusy();
                    MessageBox.Show(this, "Failed:\n" + err, "DinaPlayer");
                    return;
                }
                if (def && !wasDefault) DinaSetup.OpenDefaultSettings();
                // Reopen the player after an update so you land back in what you were
                // watching — that reappearing window is the confirmation, no dialog
                // needed. A fresh install has nothing to reopen, so it still says so.
                if (isUpdate) DinaSetup.LaunchPlayer(dir);
                else MessageBox.Show(this, "DinaPlayer installed.", "DinaPlayer");
                Close();
            }));
        });
        th.IsBackground = true; th.Start();
    }

    void DoUninstall()
    {
        if (MessageBox.Show(this, "Remove DinaPlayer from this computer?", "DinaPlayer",
            MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        if (DinaSetup.IsRunning())
        {
            MessageBox.Show(this, "Close DinaPlayer first.", "DinaPlayer");
            return;
        }
        EnterBusy("Removing…");
        var dir = existingDir;
        var th = new Thread(() =>
        {
            string err = null;
            try { DinaSetup.Uninstall(dir); } catch (Exception ex) { err = ex.Message; }
            BeginInvoke((Action)(() =>
            {
                if (err != null) { ExitBusy(); MessageBox.Show(this, "Failed: " + err, "DinaPlayer"); return; }
                MessageBox.Show(this, "DinaPlayer removed.", "DinaPlayer");
                Close();
            }));
        });
        th.IsBackground = true; th.Start();
    }
}

// Label that starts its text at x = 0 exactly. WinForms adds a few pixels of
// leading padding of its own, which left the heading and the status line sitting
// slightly right of the checkboxes and buttons.
class FlatLabel : Label
{
    public FlatLabel() { AutoSize = false; }

    // No base call: Label's own OnPaint is what draws the padded text.
    protected override void OnPaint(PaintEventArgs e)
    {
        TextRenderer.DrawText(e.Graphics, Text, Font, new Rectangle(0, 0, Width, Height), ForeColor,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter
            | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
    }
}

// A quiet clickable text link — grey, brightens on hover. Used for secondary
// actions ("Change", "Remove") that shouldn't look like buttons.
class LinkText : Label
{
    public Color Idle = Color.Gray, Hot = Color.White;
    public LinkText() { AutoSize = false; Cursor = SetupForm.Hand(); }
    protected override void OnMouseEnter(EventArgs e) { ForeColor = Hot; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { ForeColor = Idle; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnPaint(PaintEventArgs e)
    {
        TextRenderer.DrawText(e.Graphics, Text, Font, new Rectangle(0, 0, Width, Height), ForeColor,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter
            | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
    }
}

// Close button for our own caption row. Windows draws its close glyph at a fixed
// small size regardless of the window; this one scales with the DPI and is drawn
// deliberately larger.
class CloseButton : Control
{
    readonly Color _fg, _hover, _bg;
    public int HoverInset = 0;    // margin from each edge for the rounded hover chip
    public int HoverRadius = 0;   // 0 = plain square hover fill
    bool _hot;

    public CloseButton(Color fg, Color hover, Color bg)
    {
        _fg = fg; _hover = hover; _bg = bg;
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint
            | ControlStyles.UserPaint, true);
        Cursor = SetupForm.Hand();
        TabStop = false;
    }

    protected override void OnMouseEnter(EventArgs e) { _hot = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { _hot = false; Invalidate(); base.OnMouseLeave(e); }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        // Always paint the full background first (the control is owner-painted), then
        // the hover chip on top so its rounded corners show the window colour.
        using (var b0 = new SolidBrush(_bg)) g.FillRectangle(b0, ClientRectangle);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        if (_hot)
            using (var b = new SolidBrush(_hover))
            {
                if (HoverRadius > 0)
                {
                    var rc = new Rectangle(HoverInset, HoverInset,
                        Width - 2 * HoverInset - 1, Height - 2 * HoverInset - 1);
                    using (var path = RoundRect(rc, HoverRadius)) g.FillPath(b, path);
                }
                else g.FillRectangle(b, ClientRectangle);
            }

        float s = DeviceDpi / 96f;
        float arm = 8f * s;                      // Windows' own glyph is roughly half this
        float cx = Width / 2f, cy = Height / 2f;
        using (var pen = new Pen(_fg, Math.Max(1.6f, 1.9f * s))
            { StartCap = LineCap.Round, EndCap = LineCap.Round })
        {
            g.DrawLine(pen, cx - arm, cy - arm, cx + arm, cy + arm);
            g.DrawLine(pen, cx + arm, cy - arm, cx - arm, cy + arm);
        }
    }

    // Rounded-rectangle hover chip.
    static GraphicsPath RoundRect(Rectangle r, int radius)
    {
        int d = Math.Max(1, radius * 2);
        var p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
}

// Slim, fully-rounded progress bar for the minimal /autoupdate window: a dark
// track with a light fill, matching the player's palette instead of the stock
// green Windows bar. Value is 0–100.
class SlimBar : Control
{
    readonly Color _track, _fill;
    int _value;
    public int Value
    {
        get { return _value; }
        set { int v = Math.Min(100, Math.Max(0, value)); if (v != _value) { _value = v; Invalidate(); } }
    }

    public SlimBar(Color track, Color fill)
    {
        _track = track; _fill = fill;
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint
            | ControlStyles.UserPaint, true);
        TabStop = false;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        int h = Height, r = h; // radius >= half-height => fully rounded ends

        using (var track = Pill(new Rectangle(0, 0, Width, h), r))
        using (var tb = new SolidBrush(_track)) g.FillPath(tb, track);

        int fw = (int)Math.Round(Width * (_value / 100.0));
        if (fw >= 2)
            using (var fill = Pill(new Rectangle(0, 0, fw, h), r))
            using (var fb = new SolidBrush(_fill)) g.FillPath(fb, fill);
    }

    // Rounded rectangle, radius clamped so a short fill stays a clean lozenge.
    static GraphicsPath Pill(Rectangle rc, int radius)
    {
        int d = Math.Max(1, Math.Min(radius, Math.Min(rc.Width, rc.Height)));
        var p = new GraphicsPath();
        if (rc.Width <= d) { p.AddEllipse(rc); p.CloseFigure(); return p; }
        p.AddArc(rc.X, rc.Y, d, d, 90, 180);
        p.AddArc(rc.Right - d, rc.Y, d, d, 270, 180);
        p.CloseFigure();
        return p;
    }
}

// Flat button with rounded corners (matches the player's rounded rectangles),
// owner-drawn for antialiased corners and hover/press states. The corners are
// filled with the parent background so they read as truly rounded on the window.
class RoundButton : Button
{
    public Color Normal, Hover, Down, Bg;
    public int Radius = 8;
    bool _hot, _press;

    public RoundButton()
    {
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint
            | ControlStyles.UserPaint, true);
        FlatStyle = FlatStyle.Flat;
        FlatAppearance.BorderSize = 0;
    }

    protected override void OnMouseEnter(EventArgs e) { _hot = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { _hot = false; _press = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) { _press = true; Invalidate(); } base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { _press = false; Invalidate(); base.OnMouseUp(e); }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.Clear(Bg);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Color fill = _press ? Down : (_hot ? Hover : Normal);
        using (var path = Rounded(new Rectangle(0, 0, Width, Height), Radius))
        using (var b = new SolidBrush(fill))
            g.FillPath(b, path);
        TextRenderer.DrawText(g, Text, Font, ClientRectangle, ForeColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
    }

    static GraphicsPath Rounded(Rectangle r, int radius)
    {
        int d = Math.Max(1, radius * 2);
        var p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
}

// Owner-drawn checkbox: high-contrast on dark. Unchecked = light rounded
// outline; checked = filled square with a dark check. Text stays white.
// Scales its box/checkmark by the control DPI so it stays crisp when scaled.
class DarkCheck : CheckBox
{
    readonly Color _text, _edge, _fill, _check;

    public DarkCheck(Color text, Color edge, Color fill, Color check)
    {
        _text = text; _edge = edge; _fill = fill; _check = check;
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint
            | ControlStyles.UserPaint, true);
        AutoSize = false;
        Cursor = SetupForm.Hand();
        CheckedChanged += (s, e) => Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.Clear(BackColor); // solid fill; no transparency (avoids sibling bleed-through)
        g.SmoothingMode = SmoothingMode.AntiAlias;

        float s = DeviceDpi / 96f;
        int box = (int)Math.Round(18 * s);
        int by = (Height - box) / 2;
        var rect = new Rectangle(0, by, box, box); // flush left, same column as everything else

        using (var path = RoundRect(rect, (int)Math.Round(4 * s)))
        {
            if (Checked)
            {
                using (var b = new SolidBrush(_fill)) g.FillPath(b, path);
                using (var pen = new Pen(_check, Math.Max(1.5f, 2.2f * s))
                    { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
                {
                    g.DrawLines(pen, new[] {
                        new PointF(rect.X + box * 0.26f, rect.Y + box * 0.52f),
                        new PointF(rect.X + box * 0.44f, rect.Y + box * 0.70f),
                        new PointF(rect.X + box * 0.74f, rect.Y + box * 0.30f),
                    });
                }
            }
            else
            {
                using (var pen = new Pen(_edge, Math.Max(1f, 1.6f * s))) g.DrawPath(pen, path);
            }
        }

        int tx = box + (int)Math.Round(10 * s);
        TextRenderer.DrawText(g, Text, Font,
            new Rectangle(tx, 0, Width - tx, Height), _text,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
    }

    static GraphicsPath RoundRect(Rectangle r, int radius)
    {
        int d = Math.Max(1, radius * 2);
        var p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
}
