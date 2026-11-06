# Publication Checklist

Status as of the local commit. Nothing has been pushed or published.

## Done

- [x] Inventory of report, programs, tables and missing components ([PROJECT_INVENTORY.md](PROJECT_INVENTORY.md)).
- [x] Original code copied unchanged into `src/01–07` (34 files, byte-identical to the working copies). No SAS was converted to Python and no scripts were invented.
- [x] English documentation: ARCHITECTURE (Mermaid), DATA_PIPELINE, MODELLING, VALIDATION, STRATEGY_SIMULATOR, REPRODUCIBILITY.
- [x] README with results tables, gallery and relative links; no badges.
- [x] `.gitignore` covering caches, logs, SAS datasets, CSVs, credentials and editor files.
- [x] `data/README.md`: no raw data committed (OpenF1 CC BY-NC-SA 4.0).
- [x] Dashboard exported from the live VA report:
  - 7 full-page PNGs (1920 px wide; all content including the scrolling part, rendered by the VA report-images service), each checked visually;
  - PDF without cover page (7 pages, checked visually);
  - report definition JSON.
- [x] Security scan of the files to be committed: no tokens, passwords, API keys, SAS credentials, `.env` files, e-mail addresses, phone numbers or student ID. Paths are generic (`~/f1`, `&home/f1`).
- [x] Static checks:
  - Python files compile;
  - red-flag rule tests pass (4/4);
  - SAS comment and quote balance;
  - all relative links in the Markdown resolve, apart from the exported files pending copy.
- [x] Documented numbers cross-checked against the frozen results (table below).

## Pending: manual steps on the author's machine

The browser exports were saved to the **Downloads** folder of the computer running Chrome. This workspace had no access to that folder, so the files still need to be copied into the repository before publishing:

| File in Downloads | Destination in repo |
|---|---|
| `01-overview.png` … `07-method-limitations.png` | `assets/dashboard/` |
| `F1_Strategy_Intelligence_2023_2025_nocover.pdf` | `reports/F1_Strategy_Intelligence_2023_2025.pdf` |
| `F1_Strategy_Intelligence_report_content.json` | `src/07_visual_analytics/report_definition/` |

PowerShell, run from the repository root:

```powershell
$dl = "$env:USERPROFILE\Downloads"
New-Item -ItemType Directory -Force assets\dashboard, reports, src\07_visual_analytics\report_definition | Out-Null
'01-overview','02-data-quality','03-tyre-degradation','04-model-validation','05-simulator-2024','06-simulator-2025','07-method-limitations' |
  ForEach-Object { Copy-Item "$dl\$_.png" "assets\dashboard\$_.png" }
Copy-Item "$dl\F1_Strategy_Intelligence_2023_2025_nocover.pdf" "reports\F1_Strategy_Intelligence_2023_2025.pdf"
Copy-Item "$dl\F1_Strategy_Intelligence_report_content.json" "src\07_visual_analytics\report_definition\"
git add assets reports src/07_visual_analytics/report_definition
git commit -m "docs: add dashboard exports"
```

Do **not** publish an earlier PDF exported from the VA menu: it has a cover page with the author's e-mail address. Chrome may have added `(1)` to file names if a file with the same name already existed.

## Pending: author decisions

- [ ] **Licence.** Left open on purpose. The code is the author's own, but it was written in an education environment (SAS Viya for Learners) and possibly as coursework, so ownership should be confirmed first. Once confirmed, a common choice is MIT for code and docs, while noting that OpenF1-derived figures remain under CC BY-NC-SA 4.0. Add `LICENSE` and update the README line.
- [ ] Review the author section in the README (name, GitHub and LinkedIn links).
- [ ] Review the Portuguese code comments. They are kept unchanged on purpose and the README says so.
- [ ] Optionally re-save the unsaved interactive steps (program "23" labels, "17b" checks, `F1_SIMULADOR` load) from SAS Studio history into `src/`, if they can be recovered.

## Pending: requires explicit authorisation

- [ ] Create the GitHub repository `f1-strategy-intelligence` and choose its visibility.
- [ ] `git push`.

## Number cross-check

| Claim | Documented | Frozen source | Match |
|---|---|---|---|
| Dry races | 54 (17/19/18) | program 19 seasons table | ✓ |
| Laps in V3c base | 50,580 (14,863 + 18,048 + 17,669) | `candidata.base_candidata` | ✓ (sum = 50,580) |
| V3c MAE E1 / E2 | 1.325 / 1.134 | program 19 | ✓ |
| Without tyre age E1 / E2 | 1.422 / 1.179 | program 19 | ✓ |
| Zero baseline E1 / E2 | 1.332 / 1.302 | program 19 | ✓ |
| Tyre-age gain E1 | +0.107 [+0.028; +0.207], 11/14 | program 19 (`boot_E1c`) | ✓ |
| Tyre-age gain E2 | +0.036 [−0.021; +0.101], 10/16 | program 19 (`boot_E2c`) | ✓ |
| V3c vs zero | E1 −0.011 [−0.422; +0.305]; E2 +0.178 [−0.199; +0.514] | program 19 | ✓ |
| Pit-in reclassified | 128 / 43 / 34 | program 19 | ✓ |
| 2025 simulator circuits | 14 | programs 20/21 | ✓ |
| Input B stop-count accuracy, 2nd half 2025 | 43% | program 21 `entrada_b_metades` | ✓ |
| LAP_ERROR rows | 85,578 = 3 models × (12,867 + 15,659) | program 22 | ✓ |

One difference to be aware of: E1 and E2 evaluate 14 and 16 **races** for the lap-time model, while the 2025 **simulator** covers 14 **circuits**. These are different scopes, not a discrepancy.
