// SPDX-License-Identifier: GPL-3.0-only
using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.Text;
using Microsoft.UI;

namespace Mazhu;

// An opt-in visual test session, with generated pictures and a separate temporary workspace.
// It never reads or writes the normal workspace, even when testing editing and export.
internal static class UiChecks
{
    private static Microsoft.UI.Dispatching.DispatcherQueueTimer? layoutTimer;
    internal static bool Enabled => Environment.GetCommandLineArgs().Contains("--ui-checks");
    internal static readonly string Root = Path.Combine(Path.GetTempPath(), "Mazhu-ui-" + Guid.NewGuid());

    internal static void CaptureLayout(Microsoft.UI.Xaml.FrameworkElement root, Func<object> context,
        params Microsoft.UI.Xaml.FrameworkElement[] elements)
    {
        var timer = root.DispatcherQueue.CreateTimer();
        layoutTimer = timer;
        timer.Interval = TimeSpan.FromSeconds(1);
        timer.Tick += (_, _) =>
        {
            var bounds = elements.Select(element =>
            {
                var point = element.TransformToVisual(root).TransformPoint(new Windows.Foundation.Point());
                return new { element.Name, X = point.X, Y = point.Y,
                    Width = element.ActualWidth, Height = element.ActualHeight, Visibility = element.Visibility.ToString() };
            });
            File.WriteAllText(Path.Combine(Root, "layout.json"), System.Text.Json.JsonSerializer.Serialize(
                new { Width = root.ActualWidth, Height = root.ActualHeight, Elements = bounds, Context = context() },
                new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));
        };
        timer.Start();
    }

    internal static async Task<Workspace> CreateWorkspaceAsync(CanvasDevice device)
    {
        Directory.CreateDirectory(Workspace.Originals);
        var workspace = new Workspace();
        if (Environment.GetCommandLineArgs().Contains("--empty")) return workspace;
        string[] names = ["周末出行计划.png", "预订确认单.png", "分享前的检查清单.png"];
        using var title = new CanvasTextFormat { FontFamily = "Microsoft YaHei UI", FontSize = 40, FontWeight = new Windows.UI.Text.FontWeight { Weight = 600 } };
        using var body = new CanvasTextFormat { FontFamily = "Microsoft YaHei UI", FontSize = 24 };
        for (int i = 0; i < names.Length; i++)
        {
            var photo = new Photo { Name = names[i], Width = 1200, Height = 800, Done = i == 1 };
            photo.StoredName = photo.Id + ".png";
            using var image = new CanvasRenderTarget(device, photo.Width, photo.Height, 96);
            using (var drawing = image.CreateDrawingSession())
            {
                drawing.Clear(Windows.UI.Color.FromArgb(255, 244, 246, 249));
                drawing.FillRoundedRectangle(48, 48, 1104, 704, 20, 20, Colors.White);
                drawing.FillRectangle(48, 48, 1104, 12, Windows.UI.Color.FromArgb(255, 82, 107, 157));
                drawing.DrawText(Path.GetFileNameWithoutExtension(photo.Name), 100, 100, Windows.UI.Color.FromArgb(255, 32, 40, 55), title);
                drawing.DrawText("2026.10.24 — 10.25    /    示例图片", 100, 168, Colors.Gray, body);
                drawing.DrawLine(100, 230, 1100, 230, Windows.UI.Color.FromArgb(255, 224, 228, 236), 2);
                drawing.DrawText("目的地", 100, 280, Colors.Gray, body);
                drawing.DrawText("山间漫步 · 周末两日", 320, 280, Colors.Black, body);
                drawing.DrawText("联系人", 100, 360, Colors.Gray, body);
                drawing.DrawText("示例联系人", 320, 360, Colors.Black, body);
                drawing.DrawText("联系电话", 100, 440, Colors.Gray, body);
                drawing.DrawText("138 0000 0000", 320, 440, Colors.Black, body);
                drawing.DrawText("预订编号", 100, 520, Colors.Gray, body);
                drawing.DrawText("DEMO — 1024 — 0001", 320, 520, Colors.Black, body);
                drawing.DrawText("此图片由界面检查自动生成，不包含真实个人信息。", 100, 660, Colors.Gray, body);
            }
            await image.SaveAsync(Path.Combine(Workspace.Originals, photo.StoredName), CanvasBitmapFileFormat.Png);
            if (i == 0)
                photo.Strokes.Add(new Stroke { Tool = MarkTool.Solid, Diameter = 36, Points = [new(322, 457), new(528, 457)] });
            workspace.Photos.Add(photo);
        }
        workspace.Selection = workspace.Photos[0].Id;
        workspace.Save();
        return workspace;
    }
}
