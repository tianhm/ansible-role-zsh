# Contributing

## Testing with Molecule

The role ships [Molecule](https://ansible.readthedocs.io/projects/molecule/) scenarios
(`default`, `shared`, `user`, `starship`) that converge the role in Docker and verify
the result. They require Docker and Python 3.

```bash
# one-time setup
python3 -m venv .venv
.venv/bin/pip install molecule "molecule-plugins[docker]" docker ansible-core pytest pytest-testinfra
.venv/bin/ansible-galaxy collection install community.docker ansible.posix

# run a scenario (activate the venv so the testinfra verifier finds pytest)
source .venv/bin/activate
molecule test -s default    # also: shared, user, starship
```

Note: the venv must be activated (or `.venv/bin` on `PATH`) — the `default`
scenario's testinfra verifier shells out to `pytest` by name.
