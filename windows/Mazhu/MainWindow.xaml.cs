// SPDX-License-Identifier: GPL-3.0-only
using System.Numerics;
using System.IO.Compression;
using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.UI;
using Microsoft.Graphics.Canvas.UI.Xaml;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.ApplicationModel.DataTransfer;
using Windows.Foundation;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.System;
using WinRT.Interop;

namespace Mazhu;

public sealed partial class MainWindow : Window
{
    private Workspace workspace = new();
    private ImageEngine? engine;
    private CanvasRenderTarget? preview;
    private readonly PhotoSurfaceCache surfaces = new();
    private PhotoSurface? activeSurface;
    private Stroke? draft;
    private CanvasRenderTarget? draftPreview;
    private bool draftDirty;
    private bool busy, ready, failedRestore, ignoreSelection;
    private float scale = 1;
    private Vector2 offset;
    private Vector2? pan;
    private bool panWithRightButton;
    private bool fit = true;
    private Photo? activePhoto;
    private Photo? pendingPhoto;
    private Photo? Selected => activePhoto;

    public MainWindow()
    {
        InitializeComponent();
        SystemBackdrop = new Microsoft.UI.Xaml.Media.MicaBackdrop { Kind = Microsoft.UI.Composition.SystemBackdrops.MicaKind.BaseAlt };
        ExtendsContentIntoTitleBar = true;
        AppWindow.TitleBar.PreferredHeightOption = Microsoft.UI.Windowing.TitleBarHeightOption.Tall;
        SetTitleBar(AppTitleBar);
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico"));
        Status.Closed += (_, _) => Status.Visibility = Visibility.Collapsed;
        Root.ActualThemeChanged += (_, _) => UpdateTitleBarTheme();
        UpdateTitleBarTheme();
        presentationReady = true;
        InitializeLibrarySelection();
        // Child controls such as ListView/ScrollViewer may mark drag events handled.
        Root.AddHandler(UIElement.DragOverEvent, new DragEventHandler(OnDragOver), true);
        Root.AddHandler(UIElement.DropEvent, new DragEventHandler(OnDrop), true);
        UpdateToolOptions();
        AddShortcut(VirtualKey.O, VirtualKeyModifiers.Control, ImportClick);
        AddShortcut(VirtualKey.V, VirtualKeyModifiers.Control, PasteClick);
        AddShortcut(VirtualKey.Z, VirtualKeyModifiers.Control, UndoClick);
        AddShortcut(VirtualKey.Z, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, RedoClick);
        AddShortcut(VirtualKey.Y, VirtualKeyModifiers.Control, RedoClick);
        AddShortcut(VirtualKey.Number0, VirtualKeyModifiers.Control, FitClick);
        AddShortcut(VirtualKey.Number1, VirtualKeyModifiers.Control, ActualClick);
        AddShortcut((VirtualKey)187, VirtualKeyModifiers.Control, ZoomInClick);
        AddShortcut((VirtualKey)187, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, ZoomInClick);
        AddShortcut((VirtualKey)189, VirtualKeyModifiers.Control, ZoomOutClick);
        AddShortcut(VirtualKey.Add, VirtualKeyModifiers.Control, ZoomInClick);
        AddShortcut(VirtualKey.Subtract, VirtualKeyModifiers.Control, ZoomOutClick);
        AppWindow.Closing += (_, args) =>
        {
            if (busy) { args.Cancel = true; return; }
            if (!ready || failedRestore) return;
            try { CancelDraft(); workspace.Save(); }
            catch (Exception error) { args.Cancel = true; Show(error.Message, true); }
        };
        Closed += (_, _) => { draftPreview?.Dispose(); surfaces.Dispose(); Canvas.RemoveFromVisualTree(); };
    }

    private void AddShortcut(VirtualKey key, VirtualKeyModifiers modifiers, RoutedEventHandler action)
    {
        var accelerator = new KeyboardAccelerator { Key = key, Modifiers = modifiers };
        accelerator.Invoked += (_, args) => { action(this, new RoutedEventArgs()); args.Handled = true; };
        Root.KeyboardAccelerators.Add(accelerator);
    }

    private void Show(string text, bool error = false)
    {
        Status.Visibility = Visibility.Visible;
        Status.Message = text;
        Status.Severity = error ? InfoBarSeverity.Error : InfoBarSeverity.Informational;
        Status.IsOpen = true;
    }

    private async Task Run(Func<Task> action)
    {
        if (busy || failedRestore || !ready) return;
        CancelDraft();
        busy = true;
        UpdateBrushCursor();
        BusyOverlay.Visibility = Visibility.Visible;
        try { await action(); }
        catch (Exception error) { Show(error.Message, true); }
        finally
        {
            busy = false;
            BusyOverlay.Visibility = Visibility.Collapsed;
            UpdateCount();
            if (pendingPhoto is not null) await Run(LoadPendingPhotosAsync);
        }
    }

    private void CreateResources(CanvasControl sender, CanvasCreateResourcesEventArgs args)
    {
        if (args.Reason == CanvasCreateResourcesReason.NewDevice)
        {
            draftPreview?.Dispose(); draftPreview = null; draftDirty = false;
            surfaces.Dispose();
            engine = null; preview = null; activeSurface = null; draft = null;
        }
        args.TrackAsyncAction(InitializeAsync().AsAsyncAction());
    }

    private async Task InitializeAsync()
    {
        if (UiChecks.Enabled && Environment.GetCommandLineArgs().Contains("--stroke-benchmark"))
        {
            try { await StrokePerformanceChecks.RunAsync(Canvas.Device); Environment.Exit(0); }
            catch (Exception error) { File.WriteAllText("stroke-performance-failure.txt", error.ToString()); Environment.Exit(1); }
            return;
        }
        if (UiChecks.Enabled && Environment.GetCommandLineArgs().Contains("--switch-benchmark"))
        {
            try { await SwitchPerformanceChecks.RunAsync(Canvas.Device); Environment.Exit(0); }
            catch (Exception error) { File.WriteAllText("switch-performance-failure.txt", error.ToString()); Environment.Exit(1); }
            return;
        }
        if (Environment.GetCommandLineArgs().Contains("--render-checks"))
        {
            try { await RenderChecks.RunAsync(Canvas.Device); Environment.Exit(0); }
            catch (Exception error) { File.WriteAllText("render-checks-failure.txt", error.ToString()); Environment.Exit(1); }
            return;
        }
        try
        {
            if (!ready)
            {
                workspace = UiChecks.Enabled ? await UiChecks.CreateWorkspaceAsync(Canvas.Device) : Workspace.Load();
                ignoreSelection = true;
                PhotoList.ItemsSource = workspace.Photos;
                activePhoto = workspace.Photos.FirstOrDefault(p => p.Id == workspace.Selection) ?? workspace.Photos.FirstOrDefault();
                PhotoList.SelectedItem = activePhoto;
                ignoreSelection = false;
            }
            ready = true;
            await LoadSelectedAsync();
            UpdateCount();
            await RunUiWorkflowChecksIfRequestedAsync();
        }
        catch (Exception error)
        {
            failedRestore = true; Editor.IsEnabled = Commands.IsEnabled = HeaderActions.IsEnabled = false;
            Show($"初始化失败：{error.Message}。现有数据已保留。", true);
        }
    }

    private async Task LoadSelectedAsync()
    {
        preview = null; engine = null; activeSurface = null;
        if (Selected is { } photo)
        {
            if (!surfaces.TryGet(photo.Id, out var surface))
            {
                surfaces.Reserve((long)photo.Width * photo.Height * 8);
                if (UiChecks.Enabled && Environment.GetCommandLineArgs().Contains("--slow-load"))
                    await Task.Delay(1800);
                var loaded = await ImageEngine.LoadAsync(Canvas.Device, Path.Combine(Workspace.Originals, photo.StoredName));
                try
                {
                    surface = new PhotoSurface { PhotoId = photo.Id, Engine = loaded, Preview = loaded.Render(photo.Strokes) };
                    surfaces.Add(surface);
                }
                catch { loaded.Dispose(); throw; }
            }
            activeSurface = surface!;
            engine = activeSurface.Engine;
            preview = activeSurface.Preview;
            workspace.Selection = photo.Id;
            fit = true;
        }
        EmptyState.Visibility = Selected is null ? Visibility.Visible : Visibility.Collapsed;
        Canvas.Invalidate();
    }

    private async void SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        if (ignoreSelection) return;
        var next = PhotoList.SelectedItems.Contains(activePhoto) ? activePhoto
            : args.AddedItems.OfType<Photo>().LastOrDefault() ?? PhotoList.SelectedItems.OfType<Photo>().FirstOrDefault();
        if (next is null || (next == activePhoto && pendingPhoto is null)) return;
        await QueuePhotoAsync(next);
    }

    private async Task QueuePhotoAsync(Photo photo)
    {
        pendingPhoto = photo;
        if (!busy) await Run(LoadPendingPhotosAsync);
    }

    private async Task LoadPendingPhotosAsync()
    {
        while (pendingPhoto is { } photo)
        {
            pendingPhoto = null;
            if (!PhotoList.SelectedItems.Contains(photo)) SetLibrarySelection([photo]);
            if (photo == activePhoto && engine is not null) continue;
            CancelDraft();
            activePhoto = photo;
            await LoadSelectedAsync();
        }
        workspace.Save();
    }

    private void UpdateCount() => UpdatePresentation();

    private void RenderPreview()
    {
        if (engine is null || Selected is null) return;
        ReplacePreview(engine.Render(Selected.Strokes));
        Canvas.Invalidate();
    }

    private void ReplacePreview(CanvasRenderTarget replacement)
    {
        preview?.Dispose(); preview = replacement;
        if (activeSurface is not null)
        {
            activeSurface.Preview = replacement;
            surfaces.Trim(activeSurface.PhotoId);
        }
    }

    private void InvalidateDraft()
    {
        draftDirty = true;
        Canvas.Invalidate();
    }

    private void RenderDraftPreview()
    {
        if (!draftDirty || draft is null || engine is null || preview is null) return;
        draftPreview = engine.RenderStroke(preview, draft, draftPreview);
        draftDirty = false;
    }

    private void CommitDraft(Photo photo)
    {
        RenderDraftPreview();
        if (draft is null || draftPreview is null) return;
        var stroke = draft;
        draft = null; draftDirty = false;
        var completed = draftPreview; draftPreview = null;
        ReplacePreview(completed);
        photo.Strokes.Add(stroke); photo.Redo.Clear(); photo.Done = false; photo.Refresh();
        workspace.Save();
        UpdateCount();
        Canvas.Invalidate();
    }

    private void UpdateFit()
    {
        if (engine is null || Canvas.ActualWidth <= 0 || Canvas.ActualHeight <= 0) return;
        scale = Math.Max(0.001f, Math.Min((float)(Canvas.ActualWidth - 40) / engine.Width, (float)(Canvas.ActualHeight - 40) / engine.Height));
        offset = new Vector2(((float)Canvas.ActualWidth - engine.Width * scale) / 2, ((float)Canvas.ActualHeight - engine.Height * scale) / 2);
    }

    private void Draw(CanvasControl sender, CanvasDrawEventArgs args)
    {
        if (preview is null) return;
        if (fit) UpdateFit();
        try { RenderDraftPreview(); }
        catch (Exception error) { CancelDraft(); Show(error.Message, true); }
        args.DrawingSession.Transform = Matrix3x2.CreateScale(scale) * Matrix3x2.CreateTranslation(offset);
        args.DrawingSession.DrawImage(draftPreview ?? preview);
        UpdateZoomDisplay();
        UpdateLassoGuide();
        UpdateBrushCursor();
    }
    private void CanvasSizeChanged(object sender, SizeChangedEventArgs args) => Canvas.Invalidate();
    private Vector2 Position(PointerRoutedEventArgs args)
    {
        var p = args.GetCurrentPoint(Canvas).Position;
        return new Vector2((float)p.X, (float)p.Y);
    }
    private MarkPoint ImagePoint(Vector2 p) => new((p.X - offset.X) / scale, (p.Y - offset.Y) / scale);

    private void PointerPressed(object sender, PointerRoutedEventArgs args)
    {
        TrackBrushPointer(args);
        if (busy || engine is null || Selected is null) return;
        var properties = args.GetCurrentPoint(Canvas).Properties;
        if (draft is not null || pan is not null) { args.Handled = true; return; }
        if (!properties.IsMiddleButtonPressed && !properties.IsRightButtonPressed && !properties.IsLeftButtonPressed) return;
        Canvas.Focus(FocusState.Pointer);
        if (fit) UpdateFit();
        if (properties.IsMiddleButtonPressed || properties.IsRightButtonPressed)
        {
            fit = false;
            panWithRightButton = properties.IsRightButtonPressed;
            pan = Position(args);
            CanvasViewport.CapturePointer(args.Pointer);
            UpdateBrushCursor();
            args.Handled = true;
            return;
        }
        var point = ImagePoint(Position(args));
        if (point.X < 0 || point.Y < 0 || point.X >= engine.Width || point.Y >= engine.Height) return;
        draft = CreateStroke(point);
        CanvasViewport.CapturePointer(args.Pointer);
        InvalidateDraft();
        args.Handled = true;
    }

    private Stroke CreateStroke(MarkPoint point)
    {
        var color = Ink.Color;
        return new Stroke
        {
            // Controls describe window DIPs; saved strokes remain in image pixels.
            Tool = selectedTool, Diameter = (float)Diameter.Value / scale, Block = (float)BlockSize.Value,
            BlurRadius = (float)BlurRadius.Value, Opacity = (float)Opacity.Value,
            Square = SquareBrush.IsChecked == true, LassoBlur = LassoBlur.IsChecked == true,
            Red = color.R, Green = color.G, Blue = color.B, Points = [point]
        };
    }

    private void PointerMoved(object sender, PointerRoutedEventArgs args)
    {
        TrackBrushPointer(args);
        if (pan is { } start)
        {
            var next = Position(args); offset += next - start; pan = next; Canvas.Invalidate(); args.Handled = true; return;
        }
        if (draft is null) return;
        var point = ImagePoint(Position(args));
        var previous = draft.Points[^1];
        if ((point.X - previous.X) * (point.X - previous.X) * scale * scale
            + (point.Y - previous.Y) * (point.Y - previous.Y) * scale * scale < 0.25f) return;
        if (draft.Tool == MarkTool.Line && draft.Points.Count > 1) draft.Points[1] = point;
        else draft.Points.Add(point);
        InvalidateDraft();
        args.Handled = true;
    }

    private void PointerReleased(object sender, PointerRoutedEventArgs args)
    {
        var properties = args.GetCurrentPoint(Canvas).Properties;
        // Releasing a secondary button must not end a drag or commit a left-button stroke.
        if (pan is not null && (panWithRightButton ? properties.IsRightButtonPressed : properties.IsMiddleButtonPressed)
            || draft is not null && properties.IsLeftButtonPressed) { args.Handled = true; return; }
        if (draft is { } stroke && Selected is { } photo)
        {
            var last = ImagePoint(Position(args));
            if (stroke.Tool == MarkTool.Line && stroke.Points.Count > 1) stroke.Points[1] = last;
            else stroke.Points.Add(last);
            draftDirty = true;
            if (stroke.Tool != MarkTool.Lasso || stroke.Points.Count >= 3)
            {
                try { CommitDraft(photo); } catch (Exception error) { CancelDraft(); Show(error.Message, true); }
            }
            else CancelDraft();
        }
        pan = null;
        CanvasViewport.ReleasePointerCapture(args.Pointer);
        TrackBrushPointer(args);
        args.Handled = true;
    }
    private void PointerCanceled(object sender, PointerRoutedEventArgs args) => CancelDraft();
    private void PointerCaptureLost(object sender, PointerRoutedEventArgs args) => CancelDraft();
    private void CancelDraft()
    {
        pan = null;
        draft = null;
        draftDirty = false;
        draftPreview?.Dispose(); draftPreview = null;
        UpdateLassoGuide();
        UpdateBrushCursor();
        Canvas.Invalidate();
    }
    private void PointerWheelChanged(object sender, PointerRoutedEventArgs args)
    {
        TrackBrushPointer(args);
        var properties = args.GetCurrentPoint(Canvas).Properties;
        if (properties.MouseWheelDelta == 0) return;
        if (!busy && engine is not null && args.KeyModifiers.HasFlag(VirtualKeyModifiers.Menu))
        {
            ChangeBrushDiameter(args.GetCurrentPoint(Canvas).Properties.MouseWheelDelta > 0 ? 4 : -4);
            args.Handled = true;
            return;
        }
        if (busy || engine is null) return;
        if (!args.KeyModifiers.HasFlag(VirtualKeyModifiers.Control))
        {
            PanCanvas(WheelPanDelta(properties.MouseWheelDelta, properties.IsHorizontalMouseWheel,
                args.KeyModifiers.HasFlag(VirtualKeyModifiers.Shift)));
            args.Handled = true;
            return;
        }
        CancelDraft();
        if (fit) UpdateFit();
        fit = false;
        var anchor = Position(args);
        var imageAnchor = (anchor - offset) / scale;
        scale = Math.Clamp(scale * (args.GetCurrentPoint(Canvas).Properties.MouseWheelDelta > 0 ? 1.15f : 1/1.15f), 0.01f, 16);
        offset = anchor - imageAnchor * scale;
        Canvas.Invalidate(); UpdateBrushCursor(); args.Handled = true;
    }
    private static Vector2 WheelPanDelta(int delta, bool horizontal, bool shift)
    {
        float distance = delta / 120f * 48;
        return horizontal ? new Vector2(-distance, 0) : shift ? new Vector2(distance, 0) : new Vector2(0, distance);
    }

    private void PanCanvas(Vector2 delta)
    {
        CancelDraft();
        if (fit) UpdateFit();
        fit = false;
        offset += delta;
        Canvas.Invalidate();
    }
    private void CanvasKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == (VirtualKey)219) { ChangeBrushDiameter(-4); args.Handled = true; }
        else if (args.Key == (VirtualKey)221) { ChangeBrushDiameter(4); args.Handled = true; }
        else if (args.Key == VirtualKey.Enter) { DoneClick(sender, new()); args.Handled = true; }
        else if (args.Key == VirtualKey.Left) { PreviousClick(sender, new()); args.Handled = true; }
        else if (args.Key == VirtualKey.Right) { NextClick(sender, new()); args.Handled = true; }
        else if (args.Key == VirtualKey.Escape) { CancelDraft(); args.Handled = true; }
    }

    private void InitializePicker(object picker) => InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
    private async void ImportClick(object sender, RoutedEventArgs args) => await Run(async () =>
    {
        var picker = new FileOpenPicker(); InitializePicker(picker);
        foreach (var extension in new[] { ".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff", ".webp", ".heic" }) picker.FileTypeFilter.Add(extension);
        await ImportAsync(await picker.PickMultipleFilesAsync());
    });

    private async Task ImportAsync(IEnumerable<StorageFile> files)
    {
        var failures = new List<string>();
        Photo? first = null;
        foreach (var file in files)
        {
            try
            {
                using var image = await ImageEngine.LoadAsync(Canvas.Device, file.Path);
                var photo = new Photo { Name = file.Name, Width = image.Width, Height = image.Height };
                photo.StoredName = photo.Id.ToString() + Path.GetExtension(file.Name);
                File.Copy(file.Path, Path.Combine(Workspace.Originals, photo.StoredName));
                workspace.Photos.Add(photo); first ??= photo;
            }
            catch (Exception error) { failures.Add($"{file.Name}：{error.Message}"); }
        }
        if (first is not null) await SelectAsync(first);
        workspace.Save();
        Show(failures.Count > 0 ? string.Join("\n", failures) : "导入完成", failures.Count > 0);
    }

    private async Task SelectAsync(Photo photo)
    {
        ignoreSelection = true;
        PhotoList.SelectedItems.Clear();
        PhotoList.SelectedItems.Add(photo);
        activePhoto = photo;
        ignoreSelection = false;
        await LoadSelectedAsync();
    }

    private async void PasteClick(object sender, RoutedEventArgs args) => await Run(async () =>
    {
        var data = Clipboard.GetContent();
        if (data.Contains(StandardDataFormats.StorageItems))
            await ImportAsync((await data.GetStorageItemsAsync()).OfType<StorageFile>());
        else if (data.Contains(StandardDataFormats.Bitmap))
        {
            using var input = await (await data.GetBitmapAsync()).OpenReadAsync();
            var directory = Path.Combine(Path.GetTempPath(), "Mazhu-" + Guid.NewGuid());
            Directory.CreateDirectory(directory);
            try
            {
                var path = Path.Combine(directory, "粘贴图片.png");
                using (var output = File.Create(path)) { await input.AsStreamForRead().CopyToAsync(output); }
                await ImportAsync(new[] { await StorageFile.GetFileFromPathAsync(path) });
            }
            finally { Directory.Delete(directory, true); }
        }
        else Show("剪贴板里没有图片或图片文件。");
    });

    private void OnDragOver(object sender, DragEventArgs args)
    {
        if (reorderingLibrary) return;
        args.AcceptedOperation = !busy && ready && !failedRestore && args.DataView.Contains(StandardDataFormats.StorageItems)
            ? DataPackageOperation.Copy : DataPackageOperation.None;
        if (args.AcceptedOperation == DataPackageOperation.Copy)
        {
            args.DragUIOverride.Caption = "添加到图片列表";
            args.DragUIOverride.IsCaptionVisible = true;
        }
        args.Handled = true;
    }
    private async void OnDrop(object sender, DragEventArgs args)
    {
        args.Handled = true;
        if (reorderingLibrary || !args.DataView.Contains(StandardDataFormats.StorageItems)) return;
        var deferral = args.GetDeferral();
        try { await Run(() => ImportDroppedItemsAsync(args.DataView)); }
        finally { deferral.Complete(); }
    }

    private async Task ImportDroppedItemsAsync(DataPackageView data)
    {
        var files = (await data.GetStorageItemsAsync()).OfType<StorageFile>().ToArray();
        if (files.Length == 0) { Show("请拖入图片文件。"); return; }
        int previousCount = workspace.Photos.Count;
        await ImportAsync(files);
        if (workspace.Photos.Count > previousCount)
        {
            LibraryView.IsPaneOpen = true;
            UpdateAdaptiveLayout();
        }
    }

    private async void UndoClick(object sender, RoutedEventArgs args) => await Run(() =>
    {
        if (Selected is { } photo && photo.Strokes.Count > 0)
        {
            photo.Redo.Add(photo.Strokes[^1]); photo.Strokes.RemoveAt(photo.Strokes.Count-1);
            Changed(photo);
        }
        return Task.CompletedTask;
    });
    private async void RedoClick(object sender, RoutedEventArgs args) => await Run(() =>
    {
        if (Selected is { } photo && photo.Redo.Count > 0)
        {
            photo.Strokes.Add(photo.Redo[^1]); photo.Redo.RemoveAt(photo.Redo.Count-1);
            Changed(photo);
        }
        return Task.CompletedTask;
    });
    private void Changed(Photo photo) { photo.Done = false; photo.Refresh(); workspace.Save(); RenderPreview(); }
    private void FitClick(object sender, RoutedEventArgs args) { if (busy) return; CancelDraft(); fit = true; Canvas.Invalidate(); }
    private void ActualClick(object sender, RoutedEventArgs args)
    {
        if (busy) return;
        CancelDraft(); fit = false; scale = 96 / Canvas.Dpi;
        if (engine is not null) offset = new Vector2(((float)Canvas.ActualWidth-engine.Width*scale)/2, ((float)Canvas.ActualHeight-engine.Height*scale)/2);
        Canvas.Invalidate();
    }
    private async Task NavigateAsync(int delta)
    {
        int index = (Selected is null ? -1 : workspace.Photos.IndexOf(Selected)) + delta;
        if (index >= 0 && index < workspace.Photos.Count) { await SelectAsync(workspace.Photos[index]); workspace.Save(); }
    }
    private async void PreviousClick(object sender, RoutedEventArgs args) => await Run(() => NavigateAsync(-1));
    private async void NextClick(object sender, RoutedEventArgs args) => await Run(() => NavigateAsync(1));
    private async void DoneClick(object sender, RoutedEventArgs args) => await Run(async () =>
    {
        if (Selected is not { } photo) return;
        photo.Done = true; photo.Refresh(); workspace.Save(); await NavigateAsync(1);
    });

    private async void ExportFolderClick(object sender, RoutedEventArgs args) => await Run(async () =>
    {
        if (!workspace.Photos.Any(p => p.Done)) { Show("请先确认需要导出的图片。"); return; }
        var picker = new FolderPicker(); picker.FileTypeFilter.Add("*"); InitializePicker(picker);
        if (await picker.PickSingleFolderAsync() is not { } folder) return;
        // Each operation owns a new directory; existing exports are never overwritten.
        var destination = Path.Combine(folder.Path, "码住-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N")[..6]);
        Directory.CreateDirectory(destination);
        await ExportAsync(destination);
        Show($"已导出到 {destination}");
    });

    private async void ExportZipClick(object sender, RoutedEventArgs args) => await Run(async () =>
    {
        if (!workspace.Photos.Any(p => p.Done)) { Show("请先确认需要导出的图片。"); return; }
        var picker = new FileSavePicker { SuggestedFileName = "码住-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") };
        picker.FileTypeChoices.Add("ZIP 压缩包", new List<string> { ".zip" }); InitializePicker(picker);
        if (await picker.PickSaveFileAsync() is not { } file) return;
        var temporary = Path.Combine(Path.GetTempPath(), "Mazhu-export-" + Guid.NewGuid());
        Directory.CreateDirectory(temporary);
        var temporaryZip = temporary + ".zip";
        try
        {
            await ExportAsync(temporary);
            await Task.Run(() => ZipFile.CreateFromDirectory(temporary, temporaryZip, CompressionLevel.NoCompression, false));
            File.Copy(temporaryZip, file.Path, true);
            Show($"已导出 {workspace.Photos.Count(p => p.Done)} 张图片。");
        }
        finally { Directory.Delete(temporary, true); if (File.Exists(temporaryZip)) File.Delete(temporaryZip); }
    });

    private async Task ExportAsync(string folder)
    {
        int index = 0;
        foreach (var photo in workspace.Photos.Where(p => p.Done))
        {
            using var image = await ImageEngine.LoadAsync(Canvas.Device, Path.Combine(Workspace.Originals, photo.StoredName));
            string name = Path.GetFileNameWithoutExtension(photo.Name);
            foreach (char invalid in Path.GetInvalidFileNameChars()) name = name.Replace(invalid, '_');
            name = name[..Math.Min(100, name.Length)];
            var output = Path.Combine(folder, $"{++index:D3}-{name}.png");
            await image.ExportAsync(photo, output);
        }
    }
}
