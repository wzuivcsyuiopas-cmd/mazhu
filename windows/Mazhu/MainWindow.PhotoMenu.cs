// SPDX-License-Identifier: GPL-3.0-only
using Microsoft.UI.Xaml.Controls;

namespace Mazhu;

public sealed partial class MainWindow
{
    private void PhotoContainerChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue || args.Item is not Photo photo) return;
        var remove = new MenuFlyoutItem { Text = "移除图片", Icon = new SymbolIcon(Symbol.Delete) };
        var menu = new MenuFlyout();
        menu.Items.Add(remove);
        menu.Opening += (_, _) =>
        {
            remove.IsEnabled = !busy && !failedRestore;
            if (busy) return;
            if (!PhotoList.SelectedItems.Contains(photo)) SetLibrarySelection([photo]);
            remove.Text = PhotoList.SelectedItems.Count > 1 ? $"移除选中的 {PhotoList.SelectedItems.Count} 张图片" : "移除图片";
        };
        remove.Click += async (_, _) =>
        {
            var photos = PhotoList.SelectedItems.Contains(photo)
                ? PhotoList.SelectedItems.OfType<Photo>().ToArray() : [photo];
            await RemovePhotosAsync(photos);
        };
        args.ItemContainer.ContextFlyout = menu;
    }

    private async Task RemovePhotosAsync(IReadOnlyCollection<Photo> photos) => await Run(async () =>
    {
        var removed = photos.ToHashSet();
        int oldIndex = activePhoto is null ? -1 : workspace.Photos.IndexOf(activePhoto);
        var next = activePhoto is not null && !removed.Contains(activePhoto) ? activePhoto
            : workspace.Photos.Skip(oldIndex + 1).FirstOrDefault(p => !removed.Contains(p))
                ?? workspace.Photos.Take(Math.Max(0, oldIndex)).LastOrDefault(p => !removed.Contains(p));
        if (pendingPhoto is not null && removed.Contains(pendingPhoto)) pendingPhoto = null;
        bool reload = activePhoto != next;
        if (reload) { activePhoto = next; activeSurface = null; engine = null; preview = null; }
        ignoreSelection = true;
        try
        {
            foreach (var photo in photos)
            {
                workspace.Photos.Remove(photo);
                surfaces.Remove(photo.Id);
            }
            SetLibrarySelection(next is null ? [] : [next]);
        }
        finally { ignoreSelection = false; }
        // Removal only changes the batch and its GPU cache; source files stay intact.
        if (reload) await LoadSelectedAsync();
        workspace.Selection = next?.Id;
        workspace.Save();
    });
}
