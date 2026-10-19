// SPDX-License-Identifier: GPL-3.0-only
using Microsoft.Graphics.Canvas;
using Microsoft.UI;

namespace Mazhu;

// Uses only generated fixtures in an owned temporary directory, never the user's workspace.
internal static class RenderChecks
{
    public static async Task RunAsync(CanvasDevice device)
    {
        var root = Path.Combine(Path.GetTempPath(), "Mazhu-checks-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        try
        {
            string input = Path.Combine(root, "source.png");
            using (var image = new CanvasRenderTarget(device, 64, 64, 96))
            {
                using (var drawing = image.CreateDrawingSession())
                {
                    drawing.Clear(Colors.Transparent);
                    drawing.FillRectangle(8, 0, 56, 64, Colors.White);
                    drawing.FillRectangle(0, 8, 8, 56, Colors.White);
                    for (int y = 0; y < 64; y += 2)
                        for (int x = 0; x < 64; x += 2)
                            if (x >= 8 || y >= 8) drawing.FillRectangle(x, y, 1, 1, Colors.Blue);
                }
                await image.SaveAsync(input, CanvasBitmapFileFormat.Png);
            }
            using var engine = await ImageEngine.LoadAsync(device, input);
            Require(engine.Width == 64 && engine.Height == 64, "decode dimensions");
            using var baseline = engine.Render([]);
            var original = baseline.GetPixelColors();
            foreach (double dpi in new[] { 72d, 144d, 300d })
            {
                string dpiPath = Path.Combine(root, $"source-{dpi}.png");
                File.WriteAllBytes(dpiPath, []);
                var dpiFile = await Windows.Storage.StorageFile.GetFileFromPathAsync(dpiPath);
                using (var stream = await dpiFile.OpenAsync(Windows.Storage.FileAccessMode.ReadWrite))
                {
                    var encoder = await Windows.Graphics.Imaging.BitmapEncoder.CreateAsync(Windows.Graphics.Imaging.BitmapEncoder.PngEncoderId, stream);
                    encoder.SetPixelData(Windows.Graphics.Imaging.BitmapPixelFormat.Bgra8,
                        Windows.Graphics.Imaging.BitmapAlphaMode.Premultiplied, 64, 64, dpi, dpi, baseline.GetPixelBytes());
                    await encoder.FlushAsync();
                }
                using var dpiEngine = await ImageEngine.LoadAsync(device, dpiPath);
                using var dpiBaseline = dpiEngine.Render([]);
                Require(dpiBaseline.GetPixelColors().SequenceEqual(original), $"{dpi} DPI image pixel coordinates changed on import");
                var mosaic = new Stroke { Tool = MarkTool.Mosaic, Diameter = 16, Block = 8, Points = [new(32, 32)] };
                using var dpiResult = dpiEngine.Render([mosaic]);
                var pixels = dpiResult.GetPixelColors();
                Require(!pixels[32 * 64 + 32].Equals(original[32 * 64 + 32]), $"{dpi} DPI mosaic missed its center");
                for (int y = 0; y < 64; y++)
                    for (int x = 0; x < 64; x++)
                        if ((x - 32) * (x - 32) + (y - 32) * (y - 32) > 10 * 10)
                            Require(pixels[y * 64 + x].Equals(original[y * 64 + x]), $"{dpi} DPI mosaic changed pixels outside its brush");
            }
            var cover = new Stroke { Tool = MarkTool.Solid, Diameter = 32, Red = 255, Points = [new(32,32)] };
            using (var result = engine.Render([cover]))
            {
                var pixels = result.GetPixelColors();
                Require(pixels[32*64+32].R == 255 && pixels[32*64+32].B == 0, "opaque red cover");
                Require(pixels[0].Equals(original[0]), "pixels outside stroke unchanged");
            }
            var square = new Stroke { Tool = MarkTool.Solid, Square = true, Diameter = 12, Points = [new(16,16), new(44,44)] };
            using (var result = engine.Render([square]))
                Require(result.GetPixelColors()[30*64+30].R == 0, "continuous diagonal square sweep");
            var lasso = new Stroke { Tool = MarkTool.Lasso, Block = 12, Points = [new(16,16),new(48,16),new(48,48),new(16,48)] };
            using (var result = engine.Render([lasso]))
            {
                var pixels = result.GetPixelColors();
                Require(pixels[0].Equals(original[0]), "lasso leaves outside untouched");
                Require(!pixels[32*64+32].Equals(original[32*64+32]), "mosaic changes covered pattern");
            }
            var blur = new Stroke { Tool = MarkTool.Blur, BlurRadius = 2, Diameter = 20, Points = [new(32,32)] };
            using (var result = engine.Render([cover, blur]))
                Require(result.GetPixelColors()[32*64+32].B < 5, "blur samples prior redaction");
            using (var committed = engine.Render([cover, blur]))
            {
                var committedPixels = committed.GetPixelColors();
                var translucent = new Stroke { Tool = MarkTool.Solid, Diameter = 24, Red = 40, Green = 100, Opacity = 0.35f,
                    Points = [new(12, 12), new(32, 32), new(12, 12)] };
                var mosaic = new Stroke { Tool = MarkTool.Mosaic, Diameter = 20, Block = 8, Points = [new(20, 24), new(40, 42)] };
                var lassoBlur = new Stroke { Tool = MarkTool.Lasso, LassoBlur = true, Points = [new(10,10), new(50,10), new(50,50)] };
                CanvasRenderTarget? scratch = null;
                try
                {
                    foreach (var stroke in new[] { square, lasso, blur, mosaic, translucent, lassoBlur })
                    {
                        var previous = scratch;
                        scratch = engine.RenderStroke(committed, stroke, scratch);
                        Require(previous is null || ReferenceEquals(previous, scratch), "draft target reused");
                        using var expected = engine.Render([cover, blur, stroke]);
                        Require(scratch.GetPixelColors().SequenceEqual(expected.GetPixelColors()), "incremental stroke matches replay: " + stroke.Tool);
                        Require(committed.GetPixelColors().SequenceEqual(committedPixels), "draft leaves committed pixels untouched");
                    }
                }
                finally { scratch?.Dispose(); }
            }
            using (var reset = engine.Render([]))
                Require(reset.GetPixelColors().SequenceEqual(original), "history replay restores exact source");
            string output = Path.Combine(root, "output.png");
            await engine.ExportAsync(new Photo { Strokes = [cover] }, output);
            using var exported = await ImageEngine.LoadAsync(device, output);
            Require(exported.Width == 64 && exported.Height == 64, "PNG export retains pixel dimensions");
            using var exportedPixels = exported.Render([]);
            Require(exportedPixels.GetPixelColors()[0].A == 0, "PNG export preserves transparency");
            async Task<PhotoSurface> SurfaceAsync()
            {
                var cachedEngine = await ImageEngine.LoadAsync(device, input);
                return new PhotoSurface { PhotoId = Guid.NewGuid(), Engine = cachedEngine, Preview = cachedEngine.Render([]) };
            }
            using (var cache = new PhotoSurfaceCache(capacity: 2))
            {
                var a = await SurfaceAsync(); cache.Add(a);
                var b = await SurfaceAsync(); cache.Add(b);
                Require(cache.TryGet(a.PhotoId, out _), "cache touch");
                cache.Reserve(a.EstimatedBytes);
                var c = await SurfaceAsync(); cache.Add(c);
                Require(cache.Count == 2 && cache.TryGet(a.PhotoId, out _) && !cache.TryGet(b.PhotoId, out _), "cache evicts least recently used photo");
            }
            using (var cache = new PhotoSurfaceCache(budget: 1))
            {
                var a = await SurfaceAsync(); cache.Add(a);
                var b = await SurfaceAsync(); cache.Add(b);
                Require(cache.Count == 1 && cache.TryGet(b.PhotoId, out _) && !cache.TryGet(a.PhotoId, out _), "oversized active photo releases inactive resources");
            }
        }
        finally { Directory.Delete(root, true); }
    }

    private static void Require(bool condition, string name)
    {
        if (!condition) throw new InvalidOperationException("Render check failed: " + name);
    }
}
