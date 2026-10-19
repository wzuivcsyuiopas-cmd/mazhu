// SPDX-License-Identifier: GPL-3.0-only
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Mazhu;

public enum MarkTool { Mosaic, Solid, Lasso, Line, Blur }
public record MarkPoint(float X, float Y);
public sealed class Stroke
{
    public MarkTool Tool { get; set; }
    public float Diameter { get; set; } = 48;
    public float Block { get; set; } = 24;
    public float BlurRadius { get; set; } = 16;
    public bool Square { get; set; }
    public bool LassoBlur { get; set; }
    public byte Red { get; set; }
    public byte Green { get; set; }
    public byte Blue { get; set; }
    public float Opacity { get; set; } = 1;
    public List<MarkPoint> Points { get; set; } = [];
}

public sealed class Photo : INotifyPropertyChanged
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string StoredName { get; set; } = "";
    public int Width { get; set; }
    public int Height { get; set; }
    public List<Stroke> Strokes { get; set; } = [];
    public List<Stroke> Redo { get; set; } = [];
    public bool Done { get; set; }
    [JsonIgnore] public string Description => $"{Width} × {Height} · {(Done ? "已确认" : "待处理")}";
    [JsonIgnore] public double ThumbnailWidth => 56.0 * Width / Math.Max(1, Math.Max(Width, Height));
    [JsonIgnore] public double ThumbnailHeight => 56.0 * Height / Math.Max(1, Math.Max(Width, Height));
    private BitmapImage? thumbnail;
    [JsonIgnore] public BitmapImage Thumbnail => thumbnail ??= new BitmapImage
    {
        DecodePixelWidth = 128,
        UriSource = new Uri(Path.Combine(Workspace.Originals, StoredName))
    };
    public event PropertyChangedEventHandler? PropertyChanged;
    public override string ToString() => $"{Name}，{Description}";
    public void Refresh() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Description)));
}

public sealed class Workspace
{
    public int Version { get; set; } = 1;
    public ObservableCollection<Photo> Photos { get; set; } = [];
    public Guid? Selection { get; set; }
    [JsonIgnore] public static string Root => UiChecks.Enabled ? UiChecks.Root
        : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Mazhu");
    [JsonIgnore] public static string Originals => Path.Combine(Root, "Originals");
    private static string Session => Path.Combine(Root, "workspace.json");

    public static Workspace Load()
    {
        Directory.CreateDirectory(Originals);
        if (!File.Exists(Session)) return new();
        var value = JsonSerializer.Deserialize<Workspace>(File.ReadAllText(Session))
            ?? throw new InvalidDataException("工作区为空，现有文件已保留。");
        if (value.Version != 1) throw new InvalidDataException("无法读取此版本的工作区，现有文件已保留。");
        foreach (var photo in value.Photos)
            if (Path.GetFileName(photo.StoredName) != photo.StoredName || !File.Exists(Path.Combine(Originals, photo.StoredName)))
                throw new InvalidDataException($"原图缺失或记录无效：{photo.Name}。现有文件已保留。");
        return value;
    }

    public void Save()
    {
        Directory.CreateDirectory(Root);
        var temporary = Session + ".tmp";
        using (var file = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(file, this);
            file.Flush(true);
        }
        File.Move(temporary, Session, true);
    }
}
