# Arc inspection evidence

Collected from the installed Arc 1.165.1 application on 3 November 2026.

- `arc-package-evidence.json`: package versions, feature bundles, dependencies and executable hashes.
- `arc-rea-summary.json`: selected native metadata and coverage information for review.
- `arc-core-rea-evidence.json.gz`: complete exported REA ledger, compressed without changing its JSON content. This combined ledger includes the main application and ArcCore records; a separate duplicate main-app ledger is unnecessary.

These files contain static analysis of the shipped application, not private browsing profiles, passwords, cookies or captured account traffic. Metadata coverage is partial; see the audit and each record's limitations.

To read the full ledger:

```sh
gzip -dc docs/evidence/arc-core-rea-evidence.json.gz > /tmp/arc-core-rea-evidence.json
```

Arc executables and its proprietary assets are not included. The new browser uses upstream CEF as pinned in cef.lock.json.
