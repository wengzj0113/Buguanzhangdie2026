from pathlib import Path
import json
import subprocess


ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = ROOT / "scripts" / "compile-mql.ps1"
PACKAGE_SCRIPT = ROOT / "scripts" / "package-distance-mode-eas.ps1"
PROFILES = (
    "FixedDistance",
    "CandleHeight",
    "AverageCandleHeight",
    "LongCandle",
    "BollingerRange",
    "ZigZagSwing",
    "BoxHeight",
    "BoxBreakout",
    "AverageDoubleCandle",
    "BollingerExpansion",
)


def _powershell(*args):
    return subprocess.run(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", *map(str, args)],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def _list_sources(profile="Legacy", target="Both"):
    result = _powershell(
        "-File", BUILD_SCRIPT, "-ListSources", "-Profile", profile, "-Target", target
    )
    return json.loads(result.stdout)["Sources"]


def test_default_legacy_and_explicit_legacy_compile_only_canonical_sources():
    assert [Path(item["SourcePath"]).name for item in _list_sources()] == [
        "NoMatterRiseFall_MT4.mq4",
        "NoMatterRiseFall_MT5.mq5",
    ]
    assert [Path(item["SourcePath"]).name for item in _list_sources("Legacy", "MT5")] == [
        "NoMatterRiseFall_MT5.mq5"
    ]


def test_profile_build_selection_resolves_platform_sources_and_outputs():
    sources = _list_sources("FixedDistance", "MT4")
    assert len(sources) == 1
    assert Path(sources[0]["SourcePath"]).name == "NoMatterRiseFall_FixedDistance_MT4.mq4"
    assert Path(sources[0]["OutputPath"]).suffix == ".ex4"
    sources = _list_sources("LongCandle", "MT5")
    assert len(sources) == 1
    assert Path(sources[0]["SourcePath"]).name == "NoMatterRiseFall_LongCandle_MT5.mq5"
    assert Path(sources[0]["OutputPath"]).suffix == ".ex5"


def test_all_profile_build_resolves_twenty_independent_targets():
    sources = _list_sources("All")
    assert len(sources) == 20
    assert {Path(item["SourcePath"]).suffix for item in sources} == {".mq4", ".mq5"}
    assert {Path(item["OutputPath"]).suffix for item in sources} == {".ex4", ".ex5"}
    assert len({Path(item["SourcePath"]).name for item in sources}) == 20


def test_package_matrix_places_zigzag_dependency_only_in_zigzag_profile(tmp_path):
    source_root = tmp_path / "source"
    output_root = tmp_path / "release"
    source_root.mkdir()
    for profile in PROFILES:
        for platform, extension, bytecode in (("MT4", ".mq4", ".ex4"), ("MT5", ".mq5", ".ex5")):
            (source_root / f"NoMatterRiseFall_{profile}_{platform}{extension}").write_text("source")
            (source_root / f"NoMatterRiseFall_{profile}_{platform}{bytecode}").write_bytes(b"compiled")
    for core in ("NoMatterRiseFall_MT4_Core.mqh", "NoMatterRiseFall_MT5_Core.mqh",
                 "NoMatterRiseFall_BasketRenewal.mqh"):
        (source_root / core).write_text("core")
    (source_root / "Indicators" / "MT4").mkdir(parents=True)
    (source_root / "Indicators" / "MT4" / "ZigZag.ex4").write_bytes(b"mt4 indicator")
    (source_root / "Indicators" / "MT5" / "Examples").mkdir(parents=True)
    (source_root / "Indicators" / "MT5" / "Examples" / "ZigZag.ex5").write_bytes(b"mt5 indicator")

    _powershell("-File", PACKAGE_SCRIPT, "-SourceRoot", source_root, "-OutputRoot", output_root)

    assert len(list(output_root.glob("*/MT4/Experts/*.ex4"))) == 10
    assert len(list(output_root.glob("*/MT5/Experts/*.ex5"))) == 10
    assert len(list(output_root.glob("*/*/Experts/NoMatterRiseFall_BasketRenewal.mqh"))) == 20
    assert (output_root / "ZigZagSwing" / "MT4" / "Indicators" / "ZigZag.ex4").is_file()
    assert (output_root / "ZigZagSwing" / "MT5" / "Indicators" / "Examples" / "ZigZag.ex5").is_file()
    for profile in set(PROFILES) - {"ZigZagSwing"}:
        assert not (output_root / profile / "MT4" / "Indicators").exists()
        assert not (output_root / profile / "MT5" / "Indicators").exists()
