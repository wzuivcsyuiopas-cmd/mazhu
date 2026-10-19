// SPDX-License-Identifier: GPL-3.0-only
using System.Diagnostics;
using System.Text.Json;
using Microsoft.Graphics.Canvas;
using Windows.UI;

namespace Mazhu;

internal static class SwitchPerformanceChecks
{
    internal static async Task RunAsync(CanvasDevice device)
    {
        string root = Path.Combine(Path.GetTempPath(), "Mazhu-performance-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        try
        {
            string path = Path.Combine(root, "4k.jpg");
            using (var source = new CanvasRenderTarget(device, 3840, 2160, 96))
            {
                using (var drawing = source.CreateDrawingSession())
                    for (int y = 0; y < 2160; y += 64)
                        for (int x = 0; x < 3840; x += 64)
                            drawing.FillRectangle(x, y, 64, 64, Color.FromArgb(255, (byte)(x % 255), (byte)(y % 255), (byte)((x + y) % 255)));
                await source.SaveAsync(path, CanvasBitmapFileFormat.Jpeg);
            }
            var strokes = new List<Stroke>
            {
                new() { Tool = MarkTool.Solid, Diameter = 100, Points = [new(500, 500), new(1500, 500)] },
                new() { Tool = MarkTool.Mosaic, Diameter = 100, Points = [new(500, 800), new(1600, 800)] }
            };
            for (int i = 0; i < 6; i++)
                strokes.Add(new Stroke { Tool = MarkTool.Blur, Diameter = 160, BlurRadius = 16,
                    Points = [new(600, 400 + i * 200), new(1800, 400 + i * 200)] });
            var samples = new List<object>();
            for (int i = 0; i < 3; i++)
            {
                var watch = Stopwatch.StartNew();
                using var engine = await ImageEngine.LoadAsync(device, path);
                double decode = watch.Elapsed.TotalMilliseconds;
                watch.Restart();
                using var preview = engine.Render(strokes);
                double submit = watch.Elapsed.TotalMilliseconds;
                // Include completion, not just asynchronous GPU command submission.
                _ = preview.GetPixelBytes();
                samples.Add(new { DecodeMs = decode, RenderSubmitMs = submit,
                    RenderCompletedMs = watch.Elapsed.TotalMilliseconds });
            }
            File.WriteAllText("switch-performance.json", JsonSerializer.Serialize(
                new { Width = 3840, Height = 2160, BlurStrokes = 6, Samples = samples }, new JsonSerializerOptions { WriteIndented = true }));
        }
        finally { Directory.Delete(root, true); }
    }
}
