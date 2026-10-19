// SPDX-License-Identifier: GPL-3.0-only
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace Mazhu;

// Consume the wheel at the slider so its parent does not scroll as well.
public sealed class WheelSlider : Slider
{
    protected override void OnPointerWheelChanged(PointerRoutedEventArgs args)
    {
        AdjustFromWheel(args.GetCurrentPoint(this).Properties.MouseWheelDelta);
        args.Handled = true;
    }

    internal void AdjustFromWheel(int delta)
    {
        if (!IsEnabled || delta == 0) return;
        Value = Math.Clamp(Value + delta / 120.0 * SmallChange, Minimum, Maximum);
    }
}
