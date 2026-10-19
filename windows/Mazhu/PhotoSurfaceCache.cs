// SPDX-License-Identifier: GPL-3.0-only
using Microsoft.Graphics.Canvas;

namespace Mazhu;

internal sealed class PhotoSurface : IDisposable
{
    internal required Guid PhotoId { get; init; }
    internal required ImageEngine Engine { get; init; }
    internal required CanvasRenderTarget Preview { get; set; }
    internal long LastUsed { get; set; }
    internal long EstimatedBytes => Engine.EstimatedMemoryBytes + (long)Engine.Width * Engine.Height * 4;

    public void Dispose() { Preview.Dispose(); Engine.Dispose(); }
}

// Owns retained GPU resources. The active photo may exceed the budget by itself;
// in that case all inactive entries are released rather than reducing image quality.
internal sealed class PhotoSurfaceCache : IDisposable
{
    internal const long DefaultBudget = 256L * 1024 * 1024;
    private readonly long budget;
    private readonly int capacity;
    private readonly Dictionary<Guid, PhotoSurface> entries = [];
    private long clock;
    internal int Count => entries.Count;
    internal long EstimatedBytes => entries.Values.Sum(p => p.EstimatedBytes);

    internal PhotoSurfaceCache(long budget = DefaultBudget, int capacity = 3)
    {
        this.budget = budget;
        this.capacity = capacity;
    }

    internal bool TryGet(Guid id, out PhotoSurface? surface)
    {
        if (!entries.TryGetValue(id, out surface)) return false;
        surface.LastUsed = ++clock;
        return true;
    }

    internal void Reserve(long incomingBytes)
    {
        while (entries.Count > 0 && (entries.Count >= capacity || EstimatedBytes + incomingBytes > budget))
            Remove(entries.Values.MinBy(p => p.LastUsed)!);
    }

    internal void Add(PhotoSurface surface)
    {
        surface.LastUsed = ++clock;
        entries.Add(surface.PhotoId, surface);
        Trim(surface.PhotoId);
    }

    internal void Trim(Guid active)
    {
        while (entries.Count > capacity || EstimatedBytes > budget)
        {
            var oldest = entries.Values.Where(p => p.PhotoId != active).MinBy(p => p.LastUsed);
            if (oldest is null) break;
            Remove(oldest);
        }
    }

    internal void Remove(Guid id)
    {
        if (entries.TryGetValue(id, out var surface)) Remove(surface);
    }

    private void Remove(PhotoSurface surface)
    {
        entries.Remove(surface.PhotoId);
        surface.Dispose();
    }

    public void Dispose()
    {
        foreach (var surface in entries.Values) surface.Dispose();
        entries.Clear();
    }
}
