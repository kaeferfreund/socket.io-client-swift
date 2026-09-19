# Historical documentation

[Current documentation](../README.md) · [Evidence index](../ReviewEvidence/README.md)

This is a preservation area, not an alternative guide to the current API.
Retired installation methods and backend options remain retired.

## Preserved usage pages

The former `Usage Docs` directory is preserved byte for byte as
[UsageDocs](UsageDocs). Its [FAQ](UsageDocs/FAQ.md) and
[compatibility page](UsageDocs/Compatibility.md) retain their original wording,
including historical recommendations and relative links. Read them in their
[original commit context](https://github.com/kaeferfreund/socket.io-client-swift/tree/f308e571f987795a3c077b358fb8c07b310b4f1f/Usage%20Docs)
when following those old links. Current replacements are
[troubleshooting](../Guides/Troubleshooting.md) and
[compatibility](../Guides/Compatibility.md).

## Material removed before this reorganization

The SPM-only deletion commit was `f308e571f987795a3c077b358fb8c07b310b4f1f`.
Its parent, `7adf66498a086bdb7b5e75d032c9560b0b7aec64`, preserves the removed
material in Git history. The links below deliberately use that fixed revision,
not `master`, so later cleanup does not erase access to the original records.

| Historical material | Original location |
| --- | --- |
| Completed CodeRabbit, client-parity, final-assertion, native-coverage and polling-failure reports | [Documentation before cleanup](https://github.com/kaeferfreund/socket.io-client-swift/tree/7adf66498a086bdb7b5e75d032c9560b0b7aec64/Documentation) |
| Original parser reproduction and validation records | [ReviewEvidence before cleanup](https://github.com/kaeferfreund/socket.io-client-swift/tree/7adf66498a086bdb7b5e75d032c9560b0b7aec64/Documentation/ReviewEvidence) |
| State-recovery and gap-fill implementation plans/specifications | [Original plans and specifications](https://github.com/kaeferfreund/socket.io-client-swift/tree/7adf66498a086bdb7b5e75d032c9560b0b7aec64/docs/superpowers) |
| Former remaining-work list | [REMAINING-WORK.md](https://github.com/kaeferfreund/socket.io-client-swift/blob/7adf66498a086bdb7b5e75d032c9560b0b7aec64/REMAINING-WORK.md) |
| Retired package-manager and framework/Xcode metadata | [Repository before cleanup](https://github.com/kaeferfreund/socket.io-client-swift/tree/7adf66498a086bdb7b5e75d032c9560b0b7aec64) |

The current working tree does not restore these completed plans or obsolete build
systems. Still-active test contracts, baselines, tests and license notices remain
in their normal locations. Historical findings must be interpreted with their
recorded revision and later follow-ups, not as current release requirements.
