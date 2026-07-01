# TODO

- [x] Add support for the [starship](https://github.com/starship/starship) prompt theme as an alternative to powerlevel10k. Keep backward compatible — user can choose the theme, default stays powerlevel10k.
- [x] starship config tasks should have tag `configure`
- [ ] check and simplify zero-knowledge install for ubuntu and macos
- [x] migrate bare `ansible_*` facts to `ansible_facts['...']` (INJECT_FACTS_AS_VARS deprecation, removed in ansible-core 2.24) across tasks/, defaults/main.yml, templates/