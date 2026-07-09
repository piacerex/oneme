# Local Verification

Run the repository checks before committing roadmap work:

```bash
python3 tools/check_all.py
```

The check runner covers:

- JSON syntax for every file in `schemas/`
- one `.example.json` for every `.schema.json`
- example files matching the supported JSON Schema subset
- Python syntax for local tooling
- API mock smoke test
- Admin dashboard smoke test
- Web SDK API smoke test
- Widget API smoke test
- VRM sample and contract smoke tests
- roadmap evidence coverage through `tools/roadmap/check_progress.py`

This is the local MVP gate. It does not replace browser, Unity, hosted API, GLB,
or VRM viewer testing once production implementations are added.
