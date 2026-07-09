# GitHub Actions Template

The current repository credentials may not have the `workflow` scope required to
push `.github/workflows/*` updates.

When workflow updates are allowed, add this file as
`.github/workflows/verify.yml`:

```yaml
name: Verify

on:
  push:
    branches:
      - main
  pull_request:

jobs:
  roadmap:
    name: Roadmap evidence and local checks
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Run local verification
        run: python3 tools/check_all.py
```
