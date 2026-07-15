#!/usr/bin/env python3
"""Render templates/starship.toml.j2 with role defaults to stdout.

Single source of truth for windows/starship.toml. CI diffs this output against
the committed file so the Windows prompt never drifts from the Ansible default.
Only the variables the template actually references are needed; none of them
depend on Ansible facts, so the render is deterministic.
"""
import sys
from pathlib import Path

import yaml
from jinja2 import Environment, StrictUndefined

ROLE_ROOT = Path(__file__).resolve().parent.parent
ANSIBLE_MANAGED = (
    "Managed by ansible-role-zsh (windows/render_starship_config.py) - do not edit"
)


def render() -> str:
    defaults = yaml.safe_load((ROLE_ROOT / "defaults" / "main.yml").read_text())
    ctx = dict(defaults)
    ctx["ansible_managed"] = ANSIBLE_MANAGED
    # _bool helpers normally computed in vars/main.yml:
    ctx["zsh_powerlevel9k_prompt_on_newline_bool"] = (
        "true" if defaults["zsh_powerlevel9k_prompt_on_newline"] else "false"
    )
    ctx["zsh_powerlevel9k_always_show_user_bool"] = (
        "true" if defaults["zsh_powerlevel9k_always_show_user"] else "false"
    )
    template_text = (ROLE_ROOT / "templates" / "starship.toml.j2").read_text()
    env = Environment(undefined=StrictUndefined, keep_trailing_newline=True)
    return env.from_string(template_text).render(**ctx)


if __name__ == "__main__":
    sys.stdout.write(render())
