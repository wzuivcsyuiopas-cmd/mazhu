// SPDX-License-Identifier: GPL-3.0-only
using System.Numerics;
using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.Effects;
using Microsoft.Graphics.Canvas.Geometry;
using Microsoft.UI;
using Windows.Foundation;
using Windows.Graphics.DirectX;
using Windows.Graphics.Imaging;
using Windows.Storage;

namespace Mazhu;

public sealed class ImageEngine : IDisposable
{
    private readonly CanvasDevice device;
    private readonly CanvasBitmap original;
    private readonly Dictionary<int, CanvasRenderTarget> mosaics = [];
    public int Width => (int)original.SizeInPixels.Width;
    public int Height => (int)original.SizeInPixels.Height;
    private Rect Bounds => new(0, 0, Width, Height);

    private ImageEngine(CanvasDevice device, CanvasBitmap original) { this.device = device; this.original = original; }

    public static async Task<ImageEngine> LoadAsync(CanvasDevice device, string path)
    {
        var file = await StorageFile.GetFileFromPathAsync(path);
        using var stream = await file.OpenReadAsync();
        var decoder = await BitmapDecoder.CreateAsync(stream);
        if ((long)decoder.OrientedPixelWidth * decoder.OrientedPixelHeight > 60_000_000)
            throw new InvalidDataException("图片超过 6000 万像素，请先缩小。");
        // Normalize EXIF orientation and sRGB before creating a 96-DPI pixel canvas.
        using var bitmap = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Premultiplied, new BitmapTransform(),
            ExifOrientationMode.RespectExifOrientation, ColorManagementMode.ColorManageToSRgb);
        return new ImageEngine(device, CanvasBitmap.CreateFromSoftwareBitmap(device, bitmap));
    }

    private CanvasRenderTarget Target() => new(device, Width, Height, 96,
        DirectXPixelFormat.B8G8R8A8UIntNormalized, CanvasAlphaMode.Premultiplied);

    private CanvasRenderTarget Mosaic(float block)
    {
        var size = Math.Clamp((int)MathF.Round(block), 2, 128);
        if (mosaics.TryGetValue(size, out var cached)) return cached;
        if (mosaics.Count >= 3) { foreach (var item in mosaics.Values) item.Dispose(); mosaics.Clear(); }
        using var small = new CanvasRenderTarget(device, Math.Max(1, (int)Math.Ceiling((double)Width / size)),
            Math.Max(1, (int)Math.Ceiling((double)Height / size)), 96);
        using (var drawing = small.CreateDrawingSession())
        {
            drawing.Clear(Colors.Transparent);
            drawing.DrawImage(original, new Rect(0, 0, small.Size.Width, small.Size.Height), Bounds);
        }
        var result = Target();
        using (var drawing = result.CreateDrawingSession())
        {
            drawing.Clear(Colors.Transparent);
            drawing.DrawImage(small, Bounds, new Rect(0, 0, small.Size.Width, small.Size.Height), 1, CanvasImageInterpolation.NearestNeighbor);
        }
        mosaics[size] = result;
        return result;
    }

    private CanvasGeometry Mask(Stroke stroke)
    {
        if (stroke.Square && stroke.Tool is not (MarkTool.Lasso or MarkTool.Line))
            return SquareMask(stroke);
        using var path = new CanvasPathBuilder(device);
        path.SetFilledRegionDetermination(CanvasFilledRegionDetermination.Alternate);
        var points = stroke.Tool == MarkTool.Line
            ? new List<MarkPoint> { stroke.Points[0], stroke.Points[^1] } : stroke.Points;
        path.BeginFigure(points[0].X, points[0].Y);
        foreach (var point in points.Skip(1)) path.AddLine(point.X, point.Y);
        path.EndFigure(stroke.Tool == MarkTool.Lasso ? CanvasFigureLoop.Closed : CanvasFigureLoop.Open);
        using var geometry = CanvasGeometry.CreatePath(path);
        if (stroke.Tool == MarkTool.Lasso) return geometry.Transform(Matrix3x2.Identity);
        if (points.Count == 1)
        {
            float r = stroke.Diameter / 2;
            return stroke.Square ? CanvasGeometry.CreateRectangle(device, points[0].X-r, points[0].Y-r, r*2, r*2)
                : CanvasGeometry.CreateCircle(device, points[0].X, points[0].Y, r);
        }
        using var style = new CanvasStrokeStyle
        {
            StartCap = stroke.Tool == MarkTool.Line ? CanvasCapStyle.Flat : CanvasCapStyle.Round,
            EndCap = stroke.Tool == MarkTool.Line ? CanvasCapStyle.Flat : CanvasCapStyle.Round,
            LineJoin = CanvasLineJoin.Round
        };
        return geometry.Stroke(stroke.Diameter, style);
    }

    private CanvasGeometry SquareMask(Stroke stroke)
    {
        // Sweep axis-aligned squares rather than rotating a square along the stroke.
        using var path = new CanvasPathBuilder(device);
        path.SetFilledRegionDetermination(CanvasFilledRegionDetermination.Winding);
        float r = stroke.Diameter / 2;
        var points = stroke.Points;
        for (int i = 0; i < Math.Max(1, points.Count-1); i++)
        {
            var a = points[i]; var b = points[Math.Min(i+1, points.Count-1)];
            var corners = new[] {
                new Vector2(a.X-r,a.Y-r), new Vector2(a.X+r,a.Y-r), new Vector2(a.X+r,a.Y+r), new Vector2(a.X-r,a.Y+r),
                new Vector2(b.X-r,b.Y-r), new Vector2(b.X+r,b.Y-r), new Vector2(b.X+r,b.Y+r), new Vector2(b.X-r,b.Y+r)
            }.Distinct().OrderBy(p => p.X).ThenBy(p => p.Y).ToArray();
            static float Cross(Vector2 p, Vector2 q, Vector2 s) => (q.X-p.X)*(s.Y-p.Y)-(q.Y-p.Y)*(s.X-p.X);
            var lower = new List<Vector2>(); var upper = new List<Vector2>();
            foreach (var p in corners)
            {
                while (lower.Count >= 2 && Cross(lower[^2], lower[^1], p) <= 0) lower.RemoveAt(lower.Count-1);
                lower.Add(p);
            }
            foreach (var p in corners.Reverse())
            {
                while (upper.Count >= 2 && Cross(upper[^2], upper[^1], p) <= 0) upper.RemoveAt(upper.Count-1);
                upper.Add(p);
            }
            var hull = lower.SkipLast(1).Concat(upper.SkipLast(1)).ToArray();
            path.BeginFigure(hull[0]);
            foreach (var p in hull.Skip(1)) path.AddLine(p);
            path.EndFigure(CanvasFigureLoop.Closed);
        }
        return CanvasGeometry.CreatePath(path);
    }

    public CanvasRenderTarget Render(IEnumerable<Stroke> strokes)
    {
        var result = Target();
        try
        {
            using (var drawing = result.CreateDrawingSession()) { drawing.Clear(Colors.Transparent); drawing.DrawImage(original); }
            foreach (var stroke in strokes.Where(s => s.Points.Count > 0))
            {
                if (stroke.Tool == MarkTool.Lasso && stroke.Points.Count < 3) continue;
                using var mask = Mask(stroke);
                bool solid = stroke.Tool is MarkTool.Solid or MarkTool.Line;
                bool blur = stroke.Tool == MarkTool.Blur || (stroke.Tool == MarkTool.Lasso && stroke.LassoBlur);
                // Read the completed previous canvas, never sample an active render target.
                using var snapshot = blur ? CanvasBitmap.CreateFromBytes(device, result.GetPixelBytes(), Width, Height,
                    DirectXPixelFormat.B8G8R8A8UIntNormalized) : null;
                using var effect = blur ? new GaussianBlurEffect
                {
                    Source = snapshot, BlurAmount = Math.Clamp(stroke.BlurRadius, 2, 60), BorderMode = EffectBorderMode.Hard
                } : null;
                var mosaic = !solid && !blur ? Mosaic(stroke.Block) : null;
                using var drawing = result.CreateDrawingSession();
                using var layer = drawing.CreateLayer(solid ? Math.Clamp(stroke.Opacity, 0, 1) : 1, mask);
                if (solid) drawing.FillRectangle(Bounds, Windows.UI.Color.FromArgb(255, stroke.Red, stroke.Green, stroke.Blue));
                else
                {
                    // Copy avoids applying source transparency a second time inside the mask.
                    drawing.Blend = CanvasBlend.Copy;
                    if (blur) drawing.DrawImage(effect!, Bounds, Bounds);
                    else drawing.DrawImage(mosaic!, Bounds, Bounds);
                }
            }
            return result;
        }
        catch { result.Dispose(); throw; }
    }

    public async Task ExportAsync(Photo photo, string path)
    {
        using var output = Render(photo.Strokes);
        await output.SaveAsync(path, CanvasBitmapFileFormat.Png);
    }

    public void Dispose()
    {
        foreach (var image in mosaics.Values) image.Dispose();
        original.Dispose();
    }
}
