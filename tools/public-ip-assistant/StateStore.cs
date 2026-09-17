using System.Text.Json;

namespace BimalPathology.PublicIpAssistant;

public sealed class StateStore
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    public string StatePath { get; }

    public StateStore(string? statePath = null)
    {
        StatePath = statePath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "BimalPathology", "PublicIpAssistant", "state.json");
    }

    public AssistantState Load()
    {
        if (!File.Exists(StatePath)) return new(null, null, null, null);
        try
        {
            return JsonSerializer.Deserialize<AssistantState>(File.ReadAllText(StatePath), JsonOptions)
                ?? new(null, null, null, null);
        }
        catch (JsonException)
        {
            return new(null, null, null, null);
        }
    }

    public void Save(AssistantState state)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(StatePath)!);
        var temporaryPath = StatePath + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(state, JsonOptions));
        File.Move(temporaryPath, StatePath, true);
    }
}

