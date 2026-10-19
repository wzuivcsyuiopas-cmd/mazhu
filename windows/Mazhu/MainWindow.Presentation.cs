// SPDX-License-Identifier: GPL-3.0-only
using System.Numerics;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;

namespace Mazhu;

public sealed partial class MainWindow
{
    private bool presentationReady;
    private bool hadPhoto;
    private bool? propertiesInline;
    private bool updatingZoom;
    private MarkTool selectedTool = MarkTool.Mosaic;

    private void RootLoaded(object sender, RoutedEventArgs args)
    {
        AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        var work = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        double dpi = Root.XamlRoot.RasterizationScale;
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.PreferredMinimumWidth = (int)(640 * dpi);
            presenter.PreferredMinimumHeight = (int)(480 * dpi);
        }
        if (UiChecks.Enabled)
            Root.RequestedTheme = Environment.GetCommandLineArgs().Contains("--light") ? ElementTheme.Light : ElementTheme.Dark;
        int width = Math.Min(work.Width - 48, (int)((UiChecks.Enabled && Environment.GetCommandLineArgs().Contains("--narrow") ? 720 : 1280) * dpi));
        int height = Math.Min(work.Height - 48, (int)(800 * dpi));
        AppWindow.MoveAndResize(new Windows.Graphics.RectInt32(
            work.X + (work.Width - width) / 2, work.Y + (work.Height - height) / 2, width, height));
        UpdateTitleBarInsets();
        Root.XamlRoot.Changed += (_, _) => UpdateTitleBarInsets();
        UpdatePresentation();
        if (UiChecks.Enabled && Environment.GetCommandLineArgs().Contains("--layout-checks"))
            UiChecks.CaptureLayout(Root, () => new { Active = Selected?.Name,
                Selected = PhotoList.SelectedItems.OfType<Photo>().Select(p => p.Name).ToArray(),
                Order = workspace.Photos.Select(p => p.Name).ToArray(), Busy = busy,
                BrushSize = Diameter.Value, Scale = scale, OffsetX = offset.X, OffsetY = offset.Y, Fit = fit,
                StrokeCount = Selected?.Strokes.Count, Pending = pendingPhoto?.Name,
                EditorEnabled = Editor.IsEnabled, CommandsEnabled = Commands.IsEnabled,
                HeaderEnabled = HeaderActions.IsEnabled }, AppTitleBar, CanvasFooter, FooterSelectionGroup,
                SelectionLabel, BatchPositionLabel, InspectorCard, CanvasFrame, Canvas, BrushCursor, BusyOverlay, Status, HeaderActions, ExportButton);
    }

    private void UpdateTitleBarTheme() => AppWindow.TitleBar.PreferredTheme =
        Root.ActualTheme == ElementTheme.Dark ? TitleBarTheme.Dark : TitleBarTheme.Light;

    private void RootSizeChanged(object sender, SizeChangedEventArgs args)
    {
        if (presentationReady)
        {
            UpdateTitleBarInsets();
            UpdateAdaptiveLayout();
        }
    }

    private void UpdateTitleBarInsets()
    {
        if (Root.XamlRoot is null || VisualTreeHelper.GetChildrenCount(AppTitleBar) == 0) return;
        // WinUI 1.8's TitleBar uses the physical caption inset as a XAML width.
        // Convert to DIPs so display scaling does not add a second empty gap.
        if (VisualTreeHelper.GetChild(AppTitleBar, 0) is FrameworkElement templateRoot
            && templateRoot.FindName("RightPaddingColumn") is ColumnDefinition rightPadding)
            rightPadding.Width = new GridLength(AppWindow.TitleBar.RightInset / Root.XamlRoot.RasterizationScale);
    }

    private void UpdatePresentation()
    {
        if (!presentationReady) return;
        int count = workspace.Photos.Count, done = workspace.Photos.Count(p => p.Done);
        bool hasPhoto = Selected is not null && engine is not null;
        ToolStrip.Visibility = CanvasFooter.Visibility = hasPhoto ? Visibility.Visible : Visibility.Collapsed;
        EmptyState.Visibility = hasPhoto ? Visibility.Collapsed : Visibility.Visible;
        UndoButton.IsEnabled = hasPhoto && Selected!.Strokes.Count > 0;
        RedoButton.IsEnabled = hasPhoto && Selected!.Redo.Count > 0;
        ExportButton.IsEnabled = done > 0;
        DoneButton.IsEnabled = PropertiesButton.IsEnabled = hasPhoto;
        LibraryButton.IsEnabled = count > 0;
        int index = Selected is null ? -1 : workspace.Photos.IndexOf(Selected);
        PreviousButton.IsEnabled = hasPhoto && index > 0;
        NextButton.IsEnabled = hasPhoto && index < count - 1;
        DoneLabel.Text = hasPhoto && index == count - 1 ? "确认图片" : "确认并下一张";
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(DoneButton, DoneLabel.Text);
        BatchPositionLabel.Text = hasPhoto ? $"{index + 1} / {count}" : "";
        DocumentTitle.Text = hasPhoto ? Selected!.Name : "码住";
        UpdateAdaptiveLayout();
        UpdateBrushCursor();
    }

    private void UpdateAdaptiveLayout()
    {
        bool hasPhoto = Selected is not null && engine is not null;
        double canvasWidth = Root.ActualWidth - (LibraryView.IsPaneOpen ? LibraryView.OpenPaneLength : 0);
        bool nextProperties = canvasWidth >= 880;
        PropertiesView.DisplayMode = nextProperties ? SplitViewDisplayMode.Inline : SplitViewDisplayMode.Overlay;
        if (!hasPhoto) LibraryView.IsPaneOpen = false;
        if (propertiesInline != nextProperties || !hasPhoto) PropertiesView.IsPaneOpen = hasPhoto && nextProperties;
        // Open the default inline panes when the first photo is imported.
        if (hasPhoto && !hadPhoto)
        {
            PropertiesView.IsPaneOpen = nextProperties;
        }
        hadPhoto = hasPhoto;
        propertiesInline = nextProperties;
        DocumentTitle.Visibility = Root.ActualWidth >= 960 ? Visibility.Visible : Visibility.Collapsed;
        DocumentTitle.Margin = new Thickness(Commands.ActualWidth + 16, 0,
            HeaderActions.ActualWidth + AppWindow.TitleBar.RightInset / (Root.XamlRoot?.RasterizationScale ?? 1) + 8, 0);
        SelectionLabel.Text = hasPhoto
            ? Root.ActualWidth < 960 ? Selected!.Name : $"{Path.GetExtension(Selected!.Name).TrimStart('.').ToUpperInvariant()}   {Selected.Width} × {Selected.Height}"
            : "";
        DoneLabel.Visibility = Root.ActualWidth >= 1100 ? Visibility.Visible : Visibility.Collapsed;
        ZoomSlider.Visibility = Root.ActualWidth >= 760 ? Visibility.Visible : Visibility.Collapsed;
        CanvasFrame.Margin = new Thickness(LibraryView.IsPaneOpen ? 0 : 12, 0,
            PropertiesView.IsPaneOpen && nextProperties ? 0 : 12, 0);
    }

    private void LibraryClick(object sender, RoutedEventArgs args)
    {
        LibraryView.IsPaneOpen = !LibraryView.IsPaneOpen;
        UpdateAdaptiveLayout();
    }
    private void PropertiesClick(object sender, RoutedEventArgs args)
    {
        PropertiesView.IsPaneOpen = !PropertiesView.IsPaneOpen;
        UpdateAdaptiveLayout();
    }

    private void ToolClick(object sender, RoutedEventArgs args)
    {
        if (busy)
        {
            foreach (var item in new[] { MosaicTool, SolidTool, LassoTool, LineTool, BlurTool })
                item.IsChecked = (MarkTool)int.Parse((string)item.Tag) == selectedTool;
            return;
        }
        CancelDraft();
        selectedTool = (MarkTool)int.Parse((string)((ToggleButton)sender).Tag);
        foreach (var button in new[] { MosaicTool, SolidTool, LassoTool, LineTool, BlurTool })
            button.IsChecked = (MarkTool)int.Parse((string)button.Tag) == selectedTool;
        UpdateToolOptions();
        UpdateToolIndicator(true);
    }

    private void UpdateToolOptions()
    {
        if (!presentationReady) return;
        bool lasso = selectedTool == MarkTool.Lasso;
        bool ink = selectedTool is MarkTool.Solid or MarkTool.Line;
        bool blur = selectedTool == MarkTool.Blur || (lasso && LassoBlur.IsChecked == true);
        ToolTitle.Text = selectedTool switch
        {
            MarkTool.Solid => "画笔", MarkTool.Lasso => "圈选", MarkTool.Line => "直线",
            MarkTool.Blur => "高斯模糊", _ => "马赛克"
        };
        ToolDescription.Text = selectedTool switch
        {
            MarkTool.Solid => "用颜色覆盖图片中的内容。",
            MarkTool.Lasso => "沿边缘圈出区域，松开后填充。",
            MarkTool.Line => "拖动绘制一条直线。",
            MarkTool.Blur => "涂抹需要柔化的区域。",
            _ => "涂抹需要隐藏的区域。"
        };
        DiameterLabel.Text = selectedTool == MarkTool.Line ? "线条宽度" : "笔刷大小";
        DiameterPanel.Visibility = lasso ? Visibility.Collapsed : Visibility.Visible;
        BlockPanel.Visibility = selectedTool == MarkTool.Mosaic || (lasso && !blur) ? Visibility.Visible : Visibility.Collapsed;
        BlurPanel.Visibility = blur ? Visibility.Visible : Visibility.Collapsed;
        SquareBrush.Visibility = selectedTool is MarkTool.Line or MarkTool.Lasso ? Visibility.Collapsed : Visibility.Visible;
        LassoBlur.Visibility = lasso ? Visibility.Visible : Visibility.Collapsed;
        ColorPanel.Visibility = OpacityPanel.Visibility = ink ? Visibility.Visible : Visibility.Collapsed;
        UpdateParameterLabels();
        UpdateBrushCursor();
    }

    private void LassoFillChanged(object sender, RoutedEventArgs args) => UpdateToolOptions();
    private void ParameterChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        if (presentationReady) { UpdateParameterLabels(); UpdateBrushCursor(); }
    }
    private void UpdateParameterLabels()
    {
        DiameterValue.Text = $"{Diameter.Value:0} px";
        BlockValue.Text = $"{BlockSize.Value:0} px";
        BlurValue.Text = $"{BlurRadius.Value:0}";
        OpacityValue.Text = $"{Opacity.Value:P0}";
    }
    private void InkChanged(ColorPicker sender, ColorChangedEventArgs args)
    {
        if (presentationReady) ColorSwatch.Background = new SolidColorBrush(args.NewColor);
    }

    private void ZoomInClick(object sender, RoutedEventArgs args) => ZoomAtCenter(1.25f);
    private void ZoomOutClick(object sender, RoutedEventArgs args) => ZoomAtCenter(0.8f);
    private void UpdateZoomDisplay()
    {
        ZoomButton.Content = $"{scale * Canvas.Dpi / 96:P0}";
        updatingZoom = true;
        try { ZoomSlider.Value = Math.Clamp(Math.Log2(scale * Canvas.Dpi / 96), ZoomSlider.Minimum, ZoomSlider.Maximum); }
        finally { updatingZoom = false; }
    }
    private void ZoomSliderChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        if (!presentationReady || updatingZoom || busy || engine is null) return;
        if (fit) UpdateFit();
        ZoomAtCenter(MathF.Pow(2, (float)args.NewValue) * 96 / Canvas.Dpi / scale);
    }
    private void ZoomAtCenter(float factor)
    {
        if (busy || engine is null) return;
        CancelDraft();
        if (fit) UpdateFit();
        fit = false;
        var anchor = new Vector2((float)Canvas.ActualWidth / 2, (float)Canvas.ActualHeight / 2);
        var imageAnchor = (anchor - offset) / scale;
        scale = Math.Clamp(scale * factor, 0.01f, 16);
        offset = anchor - imageAnchor * scale;
        Canvas.Invalidate();
    }
}
