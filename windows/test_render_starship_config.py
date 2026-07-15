import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
COMMITTED = ROOT / "starship.toml"


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
