import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
COMMITTED = ROOT / "starship.toml"
INSTALL_PS1 = ROOT.parent / "install.ps1"


def _embedded_toml() -> str:
    """The starship.toml embedded in install.ps1's `$script:StarshipToml` here-string."""
    text = INSTALL_PS1.read_text()
    marker = "$script:StarshipToml = @'\n"
    start = text.index(marker) + len(marker)
    end = text.index("\n'@", start)
    # here-string omits the single trailing newline; add it back to match the file/render.
    return text[start:end] + "\n"


def _render() -> str:
    proc = subprocess.run(
        [sys.executable, str(ROOT / "render_starship_config.py")],
        capture_output=True, text=True, check=True,
    )
    return proc.stdout


def test_render_contains_expected_prompt_segments():
    out = _render()
    assert 'format = "$username$hostname$directory"' in out
    assert "[git_branch]" in out
    assert "[cmd_duration]" in out


def test_committed_config_is_not_stale():
    # Drift guard: catches "templates/starship.toml.j2 edited but windows/starship.toml
    # not regenerated". It does NOT independently verify that this harness's Jinja
    # settings still match Ansible's `template` module — that parity is maintained by
    # trim_blocks=True in render_starship_config.py.
    assert COMMITTED.exists(), "run: python windows/render_starship_config.py > windows/starship.toml"
    assert COMMITTED.read_text() == _render(), (
        "windows/starship.toml is stale; regenerate with "
        "`python windows/render_starship_config.py > windows/starship.toml`"
    )


def test_install_ps1_embedded_config_matches_render():
    # install.ps1 embeds the config (so `irm | iex` needs no download); it must not
    # drift from the rendered default.
    assert _embedded_toml() == _render(), (
        "the $script:StarshipToml here-string in install.ps1 is stale; "
        "re-embed the output of `python windows/render_starship_config.py`"
    )
