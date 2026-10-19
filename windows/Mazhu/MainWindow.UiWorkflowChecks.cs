// SPDX-License-Identifier: GPL-3.0-only
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;

namespace Mazhu;

public sealed partial class MainWindow
{
    private async Task RunUiWorkflowChecksIfRequestedAsync()
    {
        if (!UiChecks.Enabled || !Environment.GetCommandLineArgs().Contains("--workflow-checks")) return;
        try
        {
            void Require(bool condition, string message)
            {
                if (!condition) throw new InvalidOperationException(message);
            }
            var first = workspace.Photos[0];
            var second = workspace.Photos[1];
            var third = workspace.Photos[2];
            var originalEngine = engine;
            var originalPreview = preview;
            SetLibrarySelection([second]);
            Task loading = QueuePhotoAsync(second);
            Root.UpdateLayout();
            Require(busy && BusyOverlay.Visibility == Visibility.Visible, "Loading indicator did not appear");
            Require(Editor.IsEnabled && Commands.IsEnabled && HeaderActions.IsEnabled, "Loading disabled the whole editor");
            Require(VisualTreeHelper.GetParent(BusyOverlay) == CanvasViewport, "Loading overlay escaped the canvas");
            Require(Math.Abs(BusyOverlay.ActualWidth - Canvas.ActualWidth) < 0.1
                && Math.Abs(BusyOverlay.ActualHeight - Canvas.ActualHeight) < 0.1, "Loading overlay bounds mismatch");
            SetLibrarySelection([third]);
            await QueuePhotoAsync(third);
            SetLibrarySelection([first]);
            await QueuePhotoAsync(first);
            await loading;
            Require(activePhoto == first && workspace.Selection == first.Id && PhotoList.SelectedItems.Contains(first),
                "Last photo selection was not applied");
            Require(!busy && BusyOverlay.Visibility == Visibility.Collapsed && engine is not null, "Loading did not finish");
            Require(ReferenceEquals(engine, originalEngine) && ReferenceEquals(preview, originalPreview), "Cached selection decoded or rendered again");
            var timer = System.Diagnostics.Stopwatch.StartNew();
            await QueuePhotoAsync(second);
            await QueuePhotoAsync(first);
            timer.Stop();
            double cachedSwitchMs = timer.Elapsed.TotalMilliseconds / 2;
            var mark = new Stroke { Tool = MarkTool.Solid, Diameter = 48, Red = 255, Points = [new(600, 400)] };
            first.Strokes.Add(mark);
            RenderPreview();
            var edited = preview;
            await QueuePhotoAsync(second);
            await QueuePhotoAsync(first);
            Require(ReferenceEquals(preview, edited) && preview!.GetPixelColors(600, 400, 1, 1)[0].R == 255,
                "Cached selection lost the latest edit");
            first.Strokes.Remove(mark);
            RenderPreview();
            var undone = preview;
            await QueuePhotoAsync(second);
            await QueuePhotoAsync(first);
            Require(ReferenceEquals(preview, undone) && !ReferenceEquals(preview, edited), "Cache retained a stale preview after undo");
            double diameter = Diameter.Value;
            ChangeBrushDiameter(4);
            Require(Diameter.Value == diameter + 4, "Brush size increment failed");
            ChangeBrushDiameter(-4);
            UpdateFit();
            float fittedScale = scale;
            pointerOverCanvas = true;
            brushPointer = new System.Numerics.Vector2(100, 100);
            UpdateBrushCursor();
            Require(BrushCursor.Visibility == Visibility.Visible
                && Math.Abs(BrushCursor.Width - Diameter.Value) < 0.01, "Brush cursor diameter mismatch");
            ZoomAtCenter(1.25f);
            UpdateBrushCursor();
            Require(Math.Abs(scale - fittedScale * 1.25f) < 0.001
                && Math.Abs(BrushCursor.Width - Diameter.Value) < 0.01, "Zoom changed the window-space brush size");
            float savedScale = scale;
            var savedOffset = offset;
            double savedDiameter = Diameter.Value;
            foreach (float zoom in new[] { 0.25f, 0.5f, 1f, 2f })
                foreach (double size in new[] { 12d, 48d, 160d })
                {
                    scale = zoom;
                    offset = new System.Numerics.Vector2(31, -17);
                    Diameter.Value = size;
                    brushPointer = new System.Numerics.Vector2(350, 250) * scale + offset;
                    UpdateBrushCursor();
                    var projected = CreateStroke(ImagePoint(brushPointer));
                    Require(Math.Abs(projected.Points[0].X - 350) < 0.001 && Math.Abs(projected.Points[0].Y - 250) < 0.001
                        && Math.Abs(projected.Diameter * scale - size) < 0.001 && BrushCursor.Width == size,
                        "Brush position or window-space footprint differs after zoom/size changes");
                    Require(Math.Abs(Microsoft.UI.Xaml.Controls.Canvas.GetLeft(BrushCursor) + size / 2 - brushPointer.X) < 0.01
                        && Math.Abs(Microsoft.UI.Xaml.Controls.Canvas.GetTop(BrushCursor) + size / 2 - brushPointer.Y) < 0.01,
                        "Brush guide is not centered on the paint position");
                }
            scale = savedScale; offset = savedOffset; Diameter.Value = savedDiameter;
            UpdateBrushCursor();
            var beforePan = offset;
            float beforePanScale = scale;
            int beforePanStrokes = first.Strokes.Count;
            PanCanvas(WheelPanDelta(-120, false, false));
            Require(offset == beforePan + new System.Numerics.Vector2(0, -48), "Wheel down did not move the picture upward");
            PanCanvas(WheelPanDelta(120, false, false));
            PanCanvas(WheelPanDelta(120, true, false));
            Require(offset == beforePan + new System.Numerics.Vector2(-48, 0), "Horizontal wheel direction mismatch");
            PanCanvas(WheelPanDelta(120, false, true));
            Require(offset == beforePan && scale == beforePanScale && first.Strokes.Count == beforePanStrokes && !fit,
                "Panning changed zoom or edit history");
            Require(Root.KeyboardAcceleratorPlacementMode == Microsoft.UI.Xaml.Input.KeyboardAcceleratorPlacementMode.Hidden,
                "Automatic shortcut tooltips remain enabled");
            selectedTool = MarkTool.Lasso;
            draft = new Stroke { Tool = MarkTool.Lasso, Points = [new(100, 100), new(300, 100), new(300, 300)] };
            UpdateLassoGuide();
            UpdateBrushCursor();
            Require(LassoTrace.Visibility == Visibility.Visible && LassoTrace.Points.Count == 3
                && BrushCursor.Visibility == Visibility.Collapsed, "Lasso guide or precision cursor missing");
            var firstGuidePoint = LassoTrace.Points[0];
            Require(Math.Abs(firstGuidePoint.X - (100 * scale + offset.X)) < 0.01
                && Math.Abs(LassoClosingEdge.X1 - (300 * scale + offset.X)) < 0.01
                && Math.Abs(LassoClosingEdge.Y1 - (300 * scale + offset.Y)) < 0.01
                && LassoClosingEdge.X2 == firstGuidePoint.X && LassoClosingEdge.Y2 == firstGuidePoint.Y,
                "Lasso trace or closing edge does not follow image coordinates");
            scale *= 1.25f;
            offset += new System.Numerics.Vector2(32, 16);
            UpdateLassoGuide();
            UpdateBrushCursor();
            Require(Math.Abs(LassoTrace.Points[0].X - (100 * scale + offset.X)) < 0.01 && LassoTrace.StrokeThickness == 1.5,
                "Zoom changed lasso guide alignment or screen-space thickness");
            CancelDraft();
            Require(LassoTrace.Visibility == Visibility.Collapsed && LassoClosingEdge.Visibility == Visibility.Collapsed
                && LassoTrace.Points.Count == 0 && first.Strokes.Count == beforePanStrokes,
                "Canceled lasso retained its guide or changed history");
            selectedTool = MarkTool.Mosaic;
            UpdateBrushCursor();
            var committedPreview = preview;
            int committedCount = first.Strokes.Count;
            draft = CreateStroke(new MarkPoint(300, 300));
            for (int i = 0; i < 100; i++) { draft.Points.Add(new(300 + i, 300)); InvalidateDraft(); }
            Require(ReferenceEquals(preview, committedPreview) && draftPreview is null && draftDirty,
                "Pointer updates rendered immediately or mutated the committed preview");
            RenderDraftPreview();
            var reusableDraft = draftPreview;
            draft.Points.Add(new(450, 320)); InvalidateDraft(); RenderDraftPreview();
            Require(ReferenceEquals(reusableDraft, draftPreview) && ReferenceEquals(preview, committedPreview),
                "Draft frame did not reuse its target or mutated the committed preview");
            CancelDraft();
            Require(draftPreview is null && ReferenceEquals(preview, committedPreview) && first.Strokes.Count == committedCount,
                "Cancel did not preserve the committed preview/history");
            draft = CreateStroke(new MarkPoint(300, 300)); InvalidateDraft(); CommitDraft(first);
            Require(draft is null && draftPreview is null && !ReferenceEquals(preview, committedPreview)
                && ReferenceEquals(preview, activeSurface!.Preview) && first.Strokes.Count == committedCount + 1,
                "Stroke commit did not adopt its rendered frame and update history/cache");
            first.Strokes.RemoveAt(first.Strokes.Count - 1); RenderPreview();
            foreach (var slider in new[] { Diameter, BlockSize, BlurRadius, Opacity, ZoomSlider })
            {
                double saved = slider.Value;
                double middle = (slider.Minimum + slider.Maximum) / 2;
                slider.Value = middle;
                slider.AdjustFromWheel(120);
                Require(Math.Abs(slider.Value - middle - slider.SmallChange) < 0.0001, $"{slider.Name}: wheel increment failed");
                slider.AdjustFromWheel(-120);
                Require(Math.Abs(slider.Value - middle) < 0.0001, $"{slider.Name}: wheel decrement failed");
                slider.Value = slider.Maximum;
                slider.AdjustFromWheel(120);
                Require(slider.Value == slider.Maximum, $"{slider.Name}: wheel exceeded maximum");
                slider.Value = slider.Minimum;
                slider.AdjustFromWheel(-120);
                Require(slider.Value == slider.Minimum, $"{slider.Name}: wheel exceeded minimum");
                slider.Value = saved;
            }
            Require(DiameterValue.Text == $"{Diameter.Value:0} px" && OpacityValue.Text == $"{Opacity.Value:P0}",
                "Wheel adjustment did not update parameter labels");
            Root.UpdateLayout();
            var card = InspectorCard.TransformToVisual(Root).TransformBounds(new Windows.Foundation.Rect(0, 0, InspectorCard.ActualWidth, InspectorCard.ActualHeight));
            var frame = CanvasFrame.TransformToVisual(Root).TransformBounds(new Windows.Foundation.Rect(0, 0, CanvasFrame.ActualWidth, CanvasFrame.ActualHeight));
            Require(Math.Abs(card.Y - frame.Y) < 0.1 && Math.Abs(card.Height - frame.Height) < 0.1, "Canvas/card edges mismatch");
            Require(Math.Abs(card.X - frame.Right - 12) < 0.1 && Math.Abs(Root.ActualWidth - card.Right - 12) < 0.1, "Canvas/card spacing mismatch");
            var titlePoint = DocumentTitle.TransformToVisual(Root).TransformPoint(new Windows.Foundation.Point(DocumentTitle.ActualWidth / 2, DocumentTitle.ActualHeight / 2));
            double dpi = Root.XamlRoot.RasterizationScale;
            var nonClient = Microsoft.UI.Input.InputNonClientPointerSource.GetForWindowId(AppWindow.Id);
            bool Contains(Windows.Graphics.RectInt32 r) => titlePoint.X * dpi >= r.X && titlePoint.X * dpi < r.X + r.Width
                && titlePoint.Y * dpi >= r.Y && titlePoint.Y * dpi < r.Y + r.Height;
            Require(nonClient.GetRegionRects(Microsoft.UI.Input.NonClientRegionKind.Caption).Any(Contains)
                && !nonClient.GetRegionRects(Microsoft.UI.Input.NonClientRegionKind.Passthrough).Any(Contains), "Document title blocks native caption input");
            string source = Path.Combine(Workspace.Originals, first.StoredName);
            await RemovePhotosAsync([second]);
            Require(workspace.Photos.Count == 2 && activePhoto == first && ReferenceEquals(engine, originalEngine)
                && !surfaces.TryGet(second.Id, out _), "Inactive removal changed the canvas or retained its cache");
            await RemovePhotosAsync([first]);
            Require(workspace.Photos.Count == 1 && activePhoto == third && engine is not null && File.Exists(source),
                "Active removal did not navigate safely or deleted the source");
            await RemovePhotosAsync([third]);
            Require(workspace.Photos.Count == 0 && activePhoto is null && engine is null && preview is null
                && surfaces.Count == 0 && EmptyState.Visibility == Visibility.Visible && Workspace.Load().Photos.Count == 0,
                "Last removal did not persist the empty workspace");
            var dropData = new Windows.ApplicationModel.DataTransfer.DataPackage();
            dropData.SetStorageItems(new[] {
                await Windows.Storage.StorageFile.GetFileFromPathAsync(source),
                await Windows.Storage.StorageFile.GetFileFromPathAsync(Path.Combine(Workspace.Originals, second.StoredName))
            });
            await Run(() => ImportDroppedItemsAsync(dropData.GetView()));
            Require(workspace.Photos.Count == 2 && workspace.Photos[0].Name == first.StoredName
                && activePhoto == workspace.Photos[0] && LibraryView.IsPaneOpen && Workspace.Load().Photos.Count == 2,
                "Dropped images did not append, select, reveal the list and persist");
            Require(File.ReadAllBytes(source).SequenceEqual(File.ReadAllBytes(Path.Combine(Workspace.Originals, workspace.Photos[0].StoredName))),
                "Dropped image copy differs from source");
            var existingIds = workspace.Photos.Select(p => p.Id).ToArray();
            var nextDrop = new Windows.ApplicationModel.DataTransfer.DataPackage();
            nextDrop.SetStorageItems(new[] { await Windows.Storage.StorageFile.GetFileFromPathAsync(Path.Combine(Workspace.Originals, third.StoredName)) });
            await Run(() => ImportDroppedItemsAsync(nextDrop.GetView()));
            Require(workspace.Photos.Count == 3 && workspace.Photos.Take(2).Select(p => p.Id).SequenceEqual(existingIds)
                && activePhoto == workspace.Photos[2] && Workspace.Load().Photos.Count == 3,
                "Dropping into a populated list replaced or reordered existing pictures");
            File.WriteAllText("workflow-checks-result.txt", $"PASS: local loading, last-selection queue, cache reuse/edit/undo, brush sizing, zoom synchronization, wheel panning without zoom/history changes, shortcut tooltip suppression, lasso guide/closing edge/zoom/cancellation, all five wheel sliders and bounds/labels, canvas/card geometry, native caption hit regions, inactive/active/last removal and persistence, dropped StorageItems batch import/list reveal/selection/persistence/source integrity. Cached selection mean: {cachedSwitchMs:F2} ms (generated 1200x800 fixtures; excludes frame presentation).");
            Environment.Exit(0);
        }
        catch (Exception error)
        {
            File.WriteAllText("workflow-checks-result.txt", error.ToString());
            Environment.Exit(1);
        }
    }
}
