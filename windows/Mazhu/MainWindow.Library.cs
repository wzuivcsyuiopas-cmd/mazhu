// SPDX-License-Identifier: GPL-3.0-only
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;
using Windows.System;

namespace Mazhu;

public sealed partial class MainWindow
{
    private bool reorderingLibrary, additiveBox, rangeSelection;
    private Photo[] draggedPhotos = [], selectionBeforeBox = [];
    private Photo? pressedPhoto, selectionAnchor;
    private Point? selectionOrigin;

    private void InitializeLibrarySelection()
    {
        LibrarySurface.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler(LibraryPointerPressed), true);
        LibrarySurface.PointerMoved += LibraryPointerMoved;
        LibrarySurface.PointerReleased += LibraryPointerReleased;
        LibrarySurface.PointerCaptureLost += LibraryPointerCaptureLost;
        Root.KeyDown += LibraryKeyDown;
    }

    private void SetLibrarySelection(IEnumerable<Photo> photos)
    {
        bool previous = ignoreSelection;
        ignoreSelection = true;
        try
        {
            var desired = photos.ToHashSet();
            foreach (var photo in PhotoList.SelectedItems.OfType<Photo>().Where(p => !desired.Contains(p)).ToArray())
                PhotoList.SelectedItems.Remove(photo);
            foreach (var photo in desired.Where(p => workspace.Photos.Contains(p) && !PhotoList.SelectedItems.Contains(p)))
                PhotoList.SelectedItems.Add(photo);
        }
        finally { ignoreSelection = previous; }
    }

    private void BeginLibraryGesture(PointerRoutedEventArgs args)
    {
        selectionBeforeBox = PhotoList.SelectedItems.OfType<Photo>().ToArray();
        additiveBox = args.KeyModifiers.HasFlag(VirtualKeyModifiers.Control);
        rangeSelection = args.KeyModifiers.HasFlag(VirtualKeyModifiers.Shift);
        selectionOrigin = args.GetCurrentPoint(LibrarySurface).Position;
        LibrarySurface.CapturePointer(args.Pointer);
        args.Handled = true;
    }

    private void LibraryItemPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        if (busy || !args.GetCurrentPoint(LibrarySurface).Properties.IsLeftButtonPressed
            || ((FrameworkElement)sender).DataContext is not Photo photo) return;
        pressedPhoto = photo;
        for (DependencyObject? parent = sender as DependencyObject; parent is not null; parent = VisualTreeHelper.GetParent(parent))
            if (parent is ListViewItem item) { item.Focus(FocusState.Pointer); break; }
        BeginLibraryGesture(args);
    }

    private void LibraryPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        if (args.Handled || busy || !args.GetCurrentPoint(LibrarySurface).Properties.IsLeftButtonPressed) return;
        for (DependencyObject? source = args.OriginalSource as DependencyObject; source is not null && source != LibrarySurface;
            source = VisualTreeHelper.GetParent(source))
            if (source is ListViewItem or ScrollBar) return;
        pressedPhoto = null;
        BeginLibraryGesture(args);
    }

    private Rect? LibraryItemBounds(int index) => PhotoList.ContainerFromIndex(index) is FrameworkElement item
        ? item.TransformToVisual(LibrarySurface).TransformBounds(new Rect(0, 0, item.ActualWidth, item.ActualHeight)) : null;

    private int LibraryDropIndex(Point point)
    {
        for (int i = 0; i < workspace.Photos.Count; i++)
            if (LibraryItemBounds(i) is { } bounds && point.Y < bounds.Y + bounds.Height / 2) return i;
        return workspace.Photos.Count;
    }

    private void MoveLibraryPhotos(int index)
    {
        var moving = draggedPhotos.ToHashSet();
        int destination = workspace.Photos.Take(index).Count(p => !moving.Contains(p));
        var order = workspace.Photos.Where(p => !moving.Contains(p)).ToList();
        order.InsertRange(destination, draggedPhotos);
        ignoreSelection = true;
        try
        {
            for (int i = 0; i < order.Count; i++)
            {
                int current = workspace.Photos.IndexOf(order[i]);
                if (current != i) workspace.Photos.Move(current, i);
            }
            SetLibrarySelection(draggedPhotos);
        }
        finally { ignoreSelection = false; }
        try { workspace.Save(); }
        catch (Exception error) { Show(error.Message, true); }
        UpdatePresentation();
    }

    private void LibraryPointerMoved(object sender, PointerRoutedEventArgs args)
    {
        if (selectionOrigin is not { } origin) return;
        var point = args.GetCurrentPoint(LibrarySurface).Position;
        if (Math.Abs(point.X - origin.X) < 4 && Math.Abs(point.Y - origin.Y) < 4) return;
        if (pressedPhoto is { } photo)
        {
            if (!reorderingLibrary)
            {
                if (!PhotoList.SelectedItems.Contains(photo))
                    SetLibrarySelection(additiveBox ? selectionBeforeBox.Append(photo) : [photo]);
                draggedPhotos = workspace.Photos.Where(p => PhotoList.SelectedItems.Contains(p)).ToArray();
                reorderingLibrary = true;
            }
            int index = LibraryDropIndex(point);
            if (LibraryItemBounds(Math.Min(index, workspace.Photos.Count - 1)) is { } bounds)
            {
                Microsoft.UI.Xaml.Controls.Canvas.SetLeft(LibraryInsertionMark, 8);
                Microsoft.UI.Xaml.Controls.Canvas.SetTop(LibraryInsertionMark, index < workspace.Photos.Count ? bounds.Y : bounds.Bottom);
                LibraryInsertionMark.Width = Math.Max(0, LibrarySurface.ActualWidth - 16);
                LibraryInsertionMark.Visibility = Visibility.Visible;
            }
        }
        else
        {
            double x = Math.Clamp(point.X, 0, LibrarySurface.ActualWidth), y = Math.Clamp(point.Y, 0, LibrarySurface.ActualHeight);
            var box = new Rect(Math.Min(origin.X, x), Math.Min(origin.Y, y), Math.Abs(x - origin.X), Math.Abs(y - origin.Y));
            Microsoft.UI.Xaml.Controls.Canvas.SetLeft(LibrarySelectionRectangle, box.X);
            Microsoft.UI.Xaml.Controls.Canvas.SetTop(LibrarySelectionRectangle, box.Y);
            LibrarySelectionRectangle.Width = box.Width;
            LibrarySelectionRectangle.Height = box.Height;
            LibrarySelectionRectangle.Visibility = Visibility.Visible;
            var selected = additiveBox ? selectionBeforeBox.ToHashSet() : new HashSet<Photo>();
            for (int i = 0; i < workspace.Photos.Count; i++)
                if (LibraryItemBounds(i) is { } bounds && bounds.X < box.Right && bounds.Right > box.X && bounds.Y < box.Bottom && bounds.Bottom > box.Y)
                    selected.Add(workspace.Photos[i]);
            SetLibrarySelection(selected);
        }
        args.Handled = true;
    }

    private async void LibraryPointerReleased(object sender, PointerRoutedEventArgs args)
    {
        if (selectionOrigin is null) return;
        Photo? next = null;
        if (reorderingLibrary)
        {
            var point = args.GetCurrentPoint(LibrarySurface).Position;
            if (point.X >= 0 && point.X <= LibrarySurface.ActualWidth && point.Y >= 0 && point.Y <= LibrarySurface.ActualHeight)
                MoveLibraryPhotos(LibraryDropIndex(point));
            else SetLibrarySelection(selectionBeforeBox);
        }
        else if (pressedPhoto is { } photo)
        {
            if (rangeSelection && selectionAnchor is not null)
            {
                int start = workspace.Photos.IndexOf(selectionAnchor), end = workspace.Photos.IndexOf(photo);
                var range = workspace.Photos.Skip(Math.Min(start, end)).Take(Math.Abs(end - start) + 1);
                SetLibrarySelection(additiveBox ? selectionBeforeBox.Concat(range) : range);
            }
            else if (additiveBox)
                SetLibrarySelection(selectionBeforeBox.Contains(photo) ? selectionBeforeBox.Where(p => p != photo) : selectionBeforeBox.Append(photo));
            else SetLibrarySelection([photo]);
            if (!rangeSelection) selectionAnchor = photo;
            if (!additiveBox) next = photo;
        }
        else if (LibrarySelectionRectangle.Visibility != Visibility.Visible && !additiveBox) SetLibrarySelection([]);
        FinishLibraryGesture();
        args.Handled = true;
        next ??= PhotoList.SelectedItems.Contains(activePhoto) ? activePhoto : PhotoList.SelectedItems.OfType<Photo>().FirstOrDefault();
        if (next is not null && (next != activePhoto || pendingPhoto is not null))
        {
            await QueuePhotoAsync(next);
        }
    }

    private void LibraryPointerCaptureLost(object sender, PointerRoutedEventArgs args)
    {
        if (selectionOrigin is null) return;
        SetLibrarySelection(selectionBeforeBox);
        FinishLibraryGesture();
    }

    private void FinishLibraryGesture()
    {
        selectionOrigin = null;
        pressedPhoto = null;
        reorderingLibrary = false;
        draggedPhotos = [];
        LibrarySelectionRectangle.Visibility = LibraryInsertionMark.Visibility = Visibility.Collapsed;
        LibrarySurface.ReleasePointerCaptures();
    }

    private void LibraryKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key != VirtualKey.Escape || selectionOrigin is null) return;
        SetLibrarySelection(selectionBeforeBox);
        FinishLibraryGesture();
        args.Handled = true;
    }
}
