import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = ROOT / "scripts" / "compile-mql.ps1"


def test_build_script_discovers_installed_mt4_and_mt5_compilers():
    result = subprocess.run(
        [
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(BUILD_SCRIPT), "-ListCompilers",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    compilers = json.loads(result.stdout)
    assert Path(compilers["MT4"]).is_file()
    assert Path(compilers["MT5"]).is_file()


def test_project_instructions_require_building_changed_mql_sources():
    instructions = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
    assert "compile-mql.ps1 -Target Both" in instructions
    assert ".ex4" in instructions
    assert ".ex5" in instructions


def test_build_script_fails_when_compiler_reports_errors():
    script = BUILD_SCRIPT.read_text(encoding="utf-8")
    assert "Result:\\s*(\\d+)\\s+errors?,\\s*(\\d+)\\s+warnings?" in script
    assert "if ($errors -ne 0)" in script
    assert "$process.ExitCode -ne 0" not in script
    assert "exit 1" in script
