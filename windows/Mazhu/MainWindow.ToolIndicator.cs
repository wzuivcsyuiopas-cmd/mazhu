// SPDX-License-Identifier: GPL-3.0-only
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.UI.ViewManagement;

namespace Mazhu;

public sealed partial class MainWindow
{
    private Storyboard? toolIndicatorAnimation;

    private void ToolStripLoaded(object sender, RoutedEventArgs args) => UpdateToolIndicator(false);
    private void ToolStripSizeChanged(object sender, SizeChangedEventArgs args) => UpdateToolIndicator(false);

    private void UpdateToolIndicator(bool animate)
    {
        if (!presentationReady || ToolStrip.ActualWidth <= 0) return;
        var button = new[] { MosaicTool, SolidTool, LassoTool, LineTool, BlurTool }[(int)selectedTool];
        double target = button.TransformToVisual(ToolStrip).TransformPoint(new Windows.Foundation.Point()).X
            + (button.ActualWidth - ToolIndicator.Width) / 2;
        double current = ToolIndicatorTransform.X;
        toolIndicatorAnimation?.Stop();
        ToolIndicatorTransform.X = target;
        if (!animate || !new UISettings().AnimationsEnabled) return;
        var animation = new DoubleAnimation
        {
            From = current, To = target, Duration = new Duration(TimeSpan.FromMilliseconds(180)),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        Storyboard.SetTarget(animation, ToolIndicatorTransform);
        Storyboard.SetTargetProperty(animation, "X");
        toolIndicatorAnimation = new Storyboard();
        toolIndicatorAnimation.Children.Add(animation);
        toolIndicatorAnimation.Begin();
    }
}
