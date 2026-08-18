// Generates the Setup.exe icon: the player's face icon + a small wrench badge
// in the bottom-right corner, so the installer is easy to tell apart from the
// player. Writes a multi-size .ico (PNG frames) plus a 256px preview PNG.
// Base is the face PNG (Icon.ToBitmap can't decode PNG-compressed .ico frames).
//   csc make-setup-icon.cs && make-setup-icon.exe face.png out.ico preview.png E90F
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;

static class MakeSetupIcon
{
    static readonly int[] SIZES = { 256, 128, 64, 48, 32, 24, 16 };

    static void Main(string[] a)
    {
        string basePng = a[0], outIco = a[1], previewPng = a[2];
        string glyph = char.ConvertFromUtf32(Convert.ToInt32(a.Length > 3 ? a[3] : "E90F", 16));

        Bitmap baseBmp;
        using (var img = Image.FromFile(basePng)) baseBmp = new Bitmap(img);

        var frames = new List<byte[]>();
        foreach (int s in SIZES)
        {
            using (var bmp = Render(baseBmp, glyph, s))
            using (var ms = new MemoryStream())
            {
                bmp.Save(ms, ImageFormat.Png);
                frames.Add(ms.ToArray());
                if (s == 256) bmp.Save(previewPng, ImageFormat.Png);
            }
        }
        WriteIco(outIco, frames);
        Console.WriteLine("Wrote " + outIco);
    }

    static Bitmap Render(Bitmap face, string glyph, int size)
    {
        var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;

            g.DrawImage(face, new Rectangle(0, 0, size, size));

            float d = size * 0.54f;              // badge diameter
            float m = size * 0.02f;              // margin from corner
            var outer = new RectangleF(size - d - m, size - d - m, d, d);
            float rw = Math.Max(1f, size * 0.022f); // white ring width
            var inner = new RectangleF(outer.X + rw, outer.Y + rw, outer.Width - 2 * rw, outer.Height - 2 * rw);

            g.FillEllipse(Brushes.White, outer);                                   // separating ring
            using (var db = new SolidBrush(Color.FromArgb(0x17, 0x17, 0x1A)))
                g.FillEllipse(db, inner);                                          // dark disc

            using (var f = new Font("Segoe MDL2 Assets", inner.Height * 0.56f, GraphicsUnit.Pixel))
            using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                g.DrawString(glyph, f, Brushes.White, inner, sf);                  // wrench
        }
        return bmp;
    }

    static void WriteIco(string path, List<byte[]> pngs)
    {
        using (var fs = new FileStream(path, FileMode.Create))
        using (var w = new BinaryWriter(fs))
        {
            w.Write((short)0);            // reserved
            w.Write((short)1);            // type = icon
            w.Write((short)pngs.Count);   // count
            int offset = 6 + 16 * pngs.Count;
            for (int i = 0; i < pngs.Count; i++)
            {
                int s = SIZES[i];
                w.Write((byte)(s >= 256 ? 0 : s)); // width  (0 => 256)
                w.Write((byte)(s >= 256 ? 0 : s)); // height
                w.Write((byte)0);         // palette
                w.Write((byte)0);         // reserved
                w.Write((short)1);        // planes
                w.Write((short)32);       // bpp
                w.Write(pngs[i].Length);  // bytes in resource
                w.Write(offset);          // image offset
                offset += pngs[i].Length;
            }
            foreach (var p in pngs) w.Write(p);
        }
    }
}
