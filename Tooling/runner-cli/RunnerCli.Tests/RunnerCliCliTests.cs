using System.Diagnostics;
using System.Text.Json;
using RunnerCli;

namespace RunnerCli.Tests;

[Collection("RunnerCliCli")]
public class RunnerCliCliTests
{
    [Fact]
    public void VersionGate_emits_json_payload()
    {
        var repoRoot = FindRepoRoot();
        var (exitCode, stdout, stderr) = RunCli(repoRoot, $"version-gate --repo-root \"{repoRoot}\" --json");

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr), $"stderr: {stderr}");

        using var doc = JsonDocument.Parse(stdout);
        var root = doc.RootElement;
        Assert.True(TryGetPropertyIgnoreCase(root, "year", out _), "year missing");
        Assert.True(TryGetPropertyIgnoreCase(root, "numericVersion", out _), "numericVersion missing");
    }

    [Fact]
    public void PylaviSummarize_writes_output_even_with_json()
    {
        var repoRoot = FindRepoRoot();
        var tempDir = Directory.CreateTempSubdirectory("lvie-cli-test");
        var reportPath = Path.Combine(tempDir.FullName, "pylavi-report.json");
        var outputPath = Path.Combine(tempDir.FullName, "pylavi-summary.json");

        var report = new PylaviOffendersReport
        {
            Label = "pylavi",
            GeneratedUtc = "2026-02-06T12:00:00Z",
            TotalFails = 1,
            ConfiguredRoots = "<redacted>",
            ConfiguredRootCount = 1,
            TopOffenders = new List<PylaviOffenderEntry>
            {
                new() { Item = "foo.vi", Count = 1 }
            },
            TopAbsoluteOffenders = new List<PylaviOffenderEntry>
            {
                new() { Item = "C:\\Users\\DevUser\\Projects\\bar.vi", Count = 1 }
            }
        };
        File.WriteAllText(reportPath, JsonSerializer.Serialize(report, RunnerCliJsonContext.Default.PylaviOffendersReport));

        var args = $"pylavi summarize --path \"{reportPath}\" --json --output-path \"{outputPath}\"";
        var (exitCode, stdout, stderr) = RunCli(repoRoot, args);

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr), $"stderr: {stderr}");
        Assert.True(File.Exists(outputPath), "output path not written");

        using var stdoutDoc = JsonDocument.Parse(stdout);
        Assert.True(stdoutDoc.RootElement.TryGetProperty("label", out _));

        var outputJson = File.ReadAllText(outputPath);
        using var outputDoc = JsonDocument.Parse(outputJson);
        Assert.True(outputDoc.RootElement.TryGetProperty("file", out _));
        Assert.True(outputDoc.RootElement.TryGetProperty("has_findings", out _));
    }

    [Fact]
    public void PylaviSummarize_validate_exists_returns_exit_code_2()
    {
        var repoRoot = FindRepoRoot();
        var tempDir = Directory.CreateTempSubdirectory("lvie-cli-missing");
        var missingPath = Path.Combine(tempDir.FullName, "missing.json");

        var args = $"pylavi summarize --path \"{missingPath}\" --validate-exists";
        var (exitCode, stdout, _) = RunCli(repoRoot, args);

        Assert.Equal(2, exitCode);
        Assert.Contains("PYLAVI_OFFENDERS_EXIT_CODE=2", stdout, StringComparison.OrdinalIgnoreCase);
    }

    private static string FindRepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null)
        {
            var marker = Path.Combine(dir.FullName, ".lvversion");
            if (File.Exists(marker))
            {
                return dir.FullName;
            }
            dir = dir.Parent;
        }

        throw new DirectoryNotFoundException("Repo root not found (missing .lvversion).");
    }

    private static (int ExitCode, string StdOut, string StdErr) RunCli(string repoRoot, string args)
    {
        var dllPath = ResolveRunnerCliDll(repoRoot);
        var runArgs = dllPath is null
            ? BuildDotnetRunArgs(repoRoot, args)
            : $"\"{dllPath}\" {args}";

        var psi = new ProcessStartInfo
        {
            FileName = "dotnet",
            Arguments = runArgs,
            WorkingDirectory = repoRoot,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var process = Process.Start(psi);
        if (process is null)
        {
            throw new InvalidOperationException("Failed to start dotnet process.");
        }

        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();

        return (process.ExitCode, stdout.Trim(), stderr.Trim());
    }

    private static string BuildDotnetRunArgs(string repoRoot, string args)
    {
        var projectPath = Path.Combine(repoRoot, "Tooling", "runner-cli", "RunnerCli", "RunnerCli.csproj");
        if (!File.Exists(projectPath))
        {
            throw new FileNotFoundException("RunnerCli.csproj not found.", projectPath);
        }

        return $"run --project \"{projectPath}\" --configuration Release -- {args}";
    }

    private static string? ResolveRunnerCliDll(string repoRoot)
    {
        var outputRoot = Path.Combine(repoRoot, "Tooling", "runner-cli", "RunnerCli", "bin", "Release", "net8.0");
        if (!Directory.Exists(outputRoot))
        {
            return null;
        }

        var dlls = Directory.GetFiles(outputRoot, "runner-cli.dll", SearchOption.AllDirectories);
        if (dlls.Length == 0)
        {
            return null;
        }

        return dlls[0];
    }

    private static bool TryGetPropertyIgnoreCase(JsonElement element, string name, out JsonElement value)
    {
        foreach (var prop in element.EnumerateObject())
        {
            if (string.Equals(prop.Name, name, StringComparison.OrdinalIgnoreCase))
            {
                value = prop.Value;
                return true;
            }
        }

        value = default;
        return false;
    }
}
