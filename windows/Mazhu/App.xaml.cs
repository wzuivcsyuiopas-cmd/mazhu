// SPDX-License-Identifier: GPL-3.0-only
using Microsoft.UI.Xaml;

namespace Mazhu;

public partial class App : Application
{
    private Window? window;
    private Mutex? instanceLock;
    public App()
    {
        if (Environment.GetCommandLineArgs().Contains("--render-checks") || UiChecks.Enabled)
        {
            DebugSettings.IsXamlResourceReferenceTracingEnabled = true;
            DebugSettings.XamlResourceReferenceFailed += (_, args) =>
                File.AppendAllText("render-checks-failure.txt", args.Message + Environment.NewLine);
            UnhandledException += (_, args) =>
            {
                File.AppendAllText("render-checks-failure.txt", args.Message + Environment.NewLine + args.Exception);
                Environment.Exit(1);
            };
        }
        InitializeComponent();
    }
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        // One process owns the local workspace. A second launch must not overwrite it.
        if (!Environment.GetCommandLineArgs().Contains("--render-checks") && !UiChecks.Enabled)
        {
            instanceLock = new Mutex(true, "Local\\Mazhu.Windows.Workspace", out bool ownsWorkspace);
            if (!ownsWorkspace) { Exit(); return; }
        }
        window = new MainWindow();
        window.Activate();
    }
}
