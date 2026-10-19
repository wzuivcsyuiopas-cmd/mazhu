// SPDX-License-Identifier: GPL-3.0-only
using System.Diagnostics;
using System.Text.Json;
using Microsoft.Graphics.Canvas;
using Windows.UI;

namespace Mazhu;

internal static class StrokePerformanceChecks
{
    internal static async Task RunAsync(CanvasDevice device)
    {
        string root = Path.Combine(Path.GetTempPath(), "Mazhu-stroke-performance-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        try
        {
            string path = Path.Combine(root, "4k.png");
            using (var source = new CanvasRenderTarget(device, 3840, 2160, 96))
            {
                using (var drawing = source.CreateDrawingSession())
                    for (int y = 0; y < 2160; y += 32)
                        for (int x = 0; x < 3840; x += 32)
                            drawing.FillRectangle(x, y, 32, 32, Color.FromArgb(255, (byte)(x % 255), (byte)(y % 255), (byte)((x + y) % 255)));
                await source.SaveAsync(path, CanvasBitmapFileFormat.Png);
            }
            using var engine = await ImageEngine.LoadAsync(device, path);
            var history = Enumerable.Range(0, 30).Select(i => new Stroke
            {
                Tool = i % 10 == 0 ? MarkTool.Blur : MarkTool.Mosaic, Diameter = 160, Block = 24,
                Points = [new(300 + i * 60, 200 + i * 40), new(1000 + i * 60, 500 + i * 40)]
            }).ToArray();
            using var committed = engine.Render(history);
            _ = committed.GetPixelColors(0, 0, 1, 1);
            var replay = new List<double>();
            var incremental = new List<double>();
            var stroke = new Stroke { Tool = MarkTool.Mosaic, Diameter = 180, Block = 24, Points = [new(400, 1000)] };
            CanvasRenderTarget? scratch = null;
            try
            {
                for (int i = 0; i < 20; i++)
                {
                    stroke.Points.Add(new(450 + i * 100, 1000 + (i % 4) * 40));
                    var watch = Stopwatch.StartNew();
                    using (var old = engine.Render(history.Append(stroke)))
                        _ = old.GetPixelColors(0, 0, 1, 1); // Wait for GPU completion, not just submission.
                    replay.Add(watch.Elapsed.TotalMilliseconds);
                    watch.Restart();
                    scratch = engine.RenderStroke(committed, stroke, scratch);
                    _ = scratch.GetPixelColors(0, 0, 1, 1);
                    incremental.Add(watch.Elapsed.TotalMilliseconds);
                }
                using var expected = engine.Render(history.Append(stroke));
                if (!scratch!.GetPixelColors().SequenceEqual(expected.GetPixelColors()))
                    throw new InvalidOperationException("Incremental stroke differs from history replay");
            }
            finally { scratch?.Dispose(); }
            static double Median(List<double> values) => values.Order().ElementAt(values.Count / 2);
            File.WriteAllText("stroke-performance.json", JsonSerializer.Serialize(new
            {
                Width = 3840, Height = 2160, HistoryStrokes = history.Length, Updates = replay.Count,
                ReplayMedianMs = Median(replay), IncrementalMedianMs = Median(incremental),
                ReplaySamplesMs = replay, IncrementalSamplesMs = incremental, PixelMatch = true
            }, new JsonSerializerOptions { WriteIndented = true }));
        }
        finally { Directory.Delete(root, true); }
    }
}
