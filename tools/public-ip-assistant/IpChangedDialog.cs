using System.Diagnostics;

namespace BimalPathology.PublicIpAssistant;

public sealed class IpChangedDialog : Form
{
    public bool Confirmed { get; private set; }
    public IpChangedDialog(string ip)
    {
        Text = "Bimal Pathology — Public IP Changed";
        ClientSize = new Size(440, 205);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false; MinimizeBox = false; StartPosition = FormStartPosition.CenterScreen;
        TopMost = true; ShowInTaskbar = true;
        var heading = new Label { Text = "Public IP update required", Font = new Font(Font, FontStyle.Bold), AutoSize = true, Location = new Point(20, 18) };
        var info = new Label { Text = "Open the Sparrow panel and manually update Allowed IP to:", AutoSize = true, Location = new Point(20, 51) };
        var value = new TextBox { Text = ip, ReadOnly = true, Font = new Font("Segoe UI", 14, FontStyle.Bold), Location = new Point(20, 77), Width = 260 };
        var copy = new Button { Text = "Copy IP", Location = new Point(294, 77), Width = 120, Height = 31 };
        copy.Click += (_, _) => Clipboard.SetText(ip);
        var open = new Button { Text = "Open Sparrow Panel", Location = new Point(20, 130), Width = 170, Height = 36 };
        open.Click += (_, _) => Process.Start(new ProcessStartInfo("https://web.sparrowsms.com/token/") { UseShellExecute = true });
        var confirm = new Button { Text = "Confirm Updated", Location = new Point(204, 130), Width = 130, Height = 36 };
        confirm.Click += (_, _) => { Confirmed = true; DialogResult = DialogResult.OK; Close(); };
        var later = new Button { Text = "Later", DialogResult = DialogResult.Cancel, Location = new Point(344, 130), Width = 70, Height = 36 };
        Controls.AddRange([heading, info, value, copy, open, confirm, later]);
        AcceptButton = confirm; CancelButton = later;
    }
}

