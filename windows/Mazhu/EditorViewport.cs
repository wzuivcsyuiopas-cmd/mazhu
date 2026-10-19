// SPDX-License-Identifier: GPL-3.0-only
using Microsoft.UI.Input;
using Microsoft.UI.Xaml.Controls;

namespace Mazhu;

// Exposes the protected cursor API without changing the window's other cursors.
public sealed class EditorViewport : Grid
{
    private readonly InputSystemCursor arrow = InputSystemCursor.Create(InputSystemCursorShape.Arrow);
    private readonly InputSystemCursor hand = InputSystemCursor.Create(InputSystemCursorShape.Hand);
    private readonly InputSystemCursor cross = InputSystemCursor.Create(InputSystemCursorShape.Cross);

    internal void SetBrushCursor(bool showBrush, bool panning, bool lasso)
        => ProtectedCursor = panning ? hand : lasso ? cross : showBrush ? null : arrow;
}
