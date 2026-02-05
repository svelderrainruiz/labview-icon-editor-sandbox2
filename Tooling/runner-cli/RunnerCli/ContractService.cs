using System.Text.Json;

namespace RunnerCli;

/// <summary>
/// Loads, saves, and validates runner contract JSON files.
/// </summary>
public static class ContractService
{

    /// <summary>Loads a runner contract from the given file path.</summary>
    public static RunnerContract Load(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
            throw new ArgumentException("Contract path must not be empty.", nameof(path));

        if (!File.Exists(path))
            throw new FileNotFoundException($"Runner contract file not found: {path}", path);

        var json = File.ReadAllText(path);
        return JsonSerializer.Deserialize(json, RunnerContractContext.Default.RunnerContract)
               ?? throw new InvalidOperationException($"Failed to deserialize runner contract: {path}");
    }

    /// <summary>Saves a runner contract to the given file path.</summary>
    public static void Save(string path, RunnerContract contract)
    {
        if (string.IsNullOrWhiteSpace(path))
            throw new ArgumentException("Contract path must not be empty.", nameof(path));

        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            Directory.CreateDirectory(dir);

        var json = JsonSerializer.Serialize(contract, RunnerContractContext.Default.RunnerContract);
        File.WriteAllText(path, json);
    }

    /// <summary>
    /// Validates that all required directory paths in the contract exist on disk.
    /// Returns a list of validation errors (empty if valid).
    /// </summary>
    public static List<string> Validate(RunnerContract contract)
    {
        var errors = new List<string>();

        ValidateDirectory(contract.RunnerRoot, "runner_root", errors);
        ValidateDirectory(contract.WorkRoot, "work_root", errors);
        ValidateDirectory(contract.WorktreeRoot, "worktree_root", errors);
        ValidateDirectory(contract.ArtifactRoot, "artifact_root", errors);
        ValidateDirectory(contract.LockRoot, "lock_root", errors);
        ValidateDirectory(contract.LogRoot, "log_root", errors);

        return errors;
    }

    /// <summary>
    /// Normalizes a set of runner labels: trims whitespace, removes empties, deduplicates (case-insensitive).
    /// </summary>
    public static List<string> NormalizeLabels(IEnumerable<string>? labels)
    {
        if (labels is null)
            return new List<string>();

        return labels
            .Select(l => l.Trim())
            .Where(l => l.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    /// <summary>
    /// Parses a comma-separated label string into a normalized list.
    /// </summary>
    public static List<string> ParseLabels(string? csv)
    {
        if (string.IsNullOrWhiteSpace(csv))
            return new List<string>();

        return NormalizeLabels(csv.Split(','));
    }

    private static void ValidateDirectory(string path, string label, List<string> errors)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            errors.Add($"Runner contract missing {label}.");
            return;
        }

        if (!Directory.Exists(path))
        {
            errors.Add($"Runner contract path not found: {label} => {path}");
        }
    }
}
