// SPDX-License-Identifier: GPL-3.0-only
using System.Numerics;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Input;

namespace Mazhu;

public sealed partial class MainWindow
{
    private bool pointerOverCanvas;
    private Vector2 brushPointer;
    private CompositionRoundedRectangleGeometry? viewportGeometry;

    private void ViewportSizeChanged(object sender, SizeChangedEventArgs args)
    {
        var visual = ElementCompositionPreview.GetElementVisual(CanvasViewport);
        if (viewportGeometry is null)
        {
            viewportGeometry = visual.Compositor.CreateRoundedRectangleGeometry();
            viewportGeometry.CornerRadius = new Vector2(6);
            visual.Clip = visual.Compositor.CreateGeometricClip(viewportGeometry);
        }
        viewportGeometry.Size = new Vector2((float)args.NewSize.Width, (float)args.NewSize.Height);
    }

    private void CanvasPointerEntered(object sender, PointerRoutedEventArgs args) => TrackBrushPointer(args);
    private void CanvasPointerExited(object sender, PointerRoutedEventArgs args)
    {
        pointerOverCanvas = false;
        UpdateBrushCursor();
    }

    private void TrackBrushPointer(PointerRoutedEventArgs args)
    {
        brushPointer = Position(args);
        pointerOverCanvas = brushPointer.X >= 0 && brushPointer.Y >= 0
            && brushPointer.X < Canvas.ActualWidth && brushPointer.Y < Canvas.ActualHeight;
        UpdateBrushCursor();
    }

    private void UpdateBrushCursor()
    {
        if (!presentationReady) return;
        bool canDraw = pointerOverCanvas && engine is not null && !busy && pan is null;
        bool visible = canDraw && selectedTool != MarkTool.Lasso;
        BrushCursor.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        CanvasViewport.SetBrushCursor(visible, pointerOverCanvas && pan is not null, canDraw && selectedTool == MarkTool.Lasso);
        if (!visible) return;
        double diameter = Math.Max(2, draft is { } stroke ? stroke.Diameter * scale : Diameter.Value);
        BrushCursor.Width = BrushCursor.Height = diameter;
        bool square = selectedTool != MarkTool.Line && (draft?.Square ?? SquareBrush.IsChecked == true);
        BrushCursor.CornerRadius = square ? new CornerRadius(0) : new CornerRadius(9999);
        Microsoft.UI.Xaml.Controls.Canvas.SetLeft(BrushCursor, brushPointer.X - diameter / 2);
        Microsoft.UI.Xaml.Controls.Canvas.SetTop(BrushCursor, brushPointer.Y - diameter / 2);
    }

    private void UpdateLassoGuide()
    {
        bool visible = !busy && engine is not null && draft is { Tool: MarkTool.Lasso, Points.Count: > 1 };
        LassoTrace.Visibility = LassoClosingEdge.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        if (!visible) { LassoTrace.Points.Clear(); return; }
        var points = new Microsoft.UI.Xaml.Media.PointCollection();
        foreach (var point in draft!.Points)
            points.Add(new Windows.Foundation.Point(point.X * scale + offset.X, point.Y * scale + offset.Y));
        LassoTrace.Points = points;
        LassoClosingEdge.X1 = points[^1].X;
        LassoClosingEdge.Y1 = points[^1].Y;
        LassoClosingEdge.X2 = points[0].X;
        LassoClosingEdge.Y2 = points[0].Y;
    }

    private void ChangeBrushDiameter(double amount)
    {
        if (busy || engine is null || selectedTool == MarkTool.Lasso) return;
        Diameter.Value = Math.Clamp(Diameter.Value + amount, Diameter.Minimum, Diameter.Maximum);
        UpdateBrushCursor();
    }
}
