# Provisional Catalogue Review — 2026

Status: reviewed source normalization only. Not authoritative production data.

## Scope and normalization totals

The supplied catalogue contains 307 source-level commercial rows when the IHC prose is normalized as three commercial services (individual marker, any three, any five). The unpriced “100+ markers” list is not expanded into fabricated test rows.

| Canonical category | Source rows | Disposition |
|---|---:|---|
| Clinical Biochemistry | 38 | Existing matches, staged candidates, and clinical review holds |
| Hematology | 35 | Existing matches and clinical review holds |
| Endocrinology | 32 | Mostly hold pending method/reporting ownership |
| Serology & Immunology | 31 | Mostly hold; method-specific duplicates must remain distinct |
| Molecular Diagnostics | 28 | Hold — molecular workflow not modeled safely |
| Microbiology | 24 | Hold — culture/stain workflow and organism/susceptibility model absent |
| Hepatitis & HIV | 20 | Hold except existing generic tests; method variants conflict with generic rows |
| Tumor Markers | 13 | Hold pending analyzer/method and parameters |
| Histopathology & Cytology | 15 | Hold — narrative/gross/microscopy workflow absent |
| Immunohistochemistry | 3 | Hold; existing IHC manual-price/sample-tracking service remains authoritative |
| Allergy | 2 | Hold — panel parameter definitions absent |
| Vitamins & Minerals | 18 | Existing matches and holds |
| Genetics & Karyotyping | 9 | Hold — genetics workflow absent |
| Toxicology & Therapeutic Drug Monitoring | 19 | Hold pending methods, units, ranges, and custody requirements |
| General Clinical Pathology | 19 | Existing matches and holds |
| Health Packages | 1 | Hold — package/component relationship is not modeled in the current schema |
| **Total** | **307** | |

## Existing catalogue comparison

Comparison is against forward migrations `00003`, `00008`, `00017`, and `00018`; it does not assume the current live production price values.

- 46 source rows map semantically to an existing canonical test/profile.
- Existing IDs and codes are preserved. The prepared migration does not update them.
- Legacy baseline aliases requiring later review: `RFT` versus `KFT`, `LIPID` versus `LIPID_PROFILE`, and `THYROID_ECLIA` versus `THYROID_PROFILE`.
- Existing prices are deliberately treated as unknown/current-production values. Source prices are never used in an `UPDATE` or conflict clause.
- Every newly staged row has `reference_range_readiness = not_ready`; no reference range or parameter is inferred from a commercial test name.

## Duplicate and conflict register

### Exact source duplicates

1. ESR appears twice in Hematology at NPR 100, Whole Blood EDTA, 3 ml.
2. Haptoglobin appears in Hematology and Serology at NPR 3,300, Serum, 2 ml.
3. Iron appears in Biochemistry and Vitamins/Minerals at NPR 1,000, Serum, 2 ml.
4. Calcium Serum appears in Biochemistry and Vitamins/Minerals at NPR 500, Serum, 1 ml.
5. Widal Test appears in Microbiology and General at NPR 300, Serum.
6. Scrub Typhus IgM appears in Microbiology and General at NPR 1,750, Serum.

### Semantic duplicates or conflicts

| Source names | Conflict |
|---|---|
| Magnesium (two categories) | `Serum/24hr Urine` versus `Serum/Urine` |
| B12 (Vitamin) / Vitamin B12 | Naming duplicate; method supplied only in one category |
| Vitamin D / Vitamin D3 entries repeated | Same analytes repeated with method present only in Vitamins category |
| G6PD entries | `Whole Blood EDTA` versus `EDTA Blood` wording |
| Bone Marrow Karyotyping / Karyotyping (Bone Marrow) | Same service, price and specimen; category wording differs |
| HCG (Total) / existing Beta-hCG | Analyte identity is not safely interchangeable without clinical review |
| HBsAg, HCV and HIV generic existing tests versus Rapid/ELISA/CLIA variants | Method-specific services must not overwrite generic canonical tests |
| Rheumatoid Factor, ASO and CRP quantitative versus non-quantitative rows | Distinct result models despite similar names |

### Non-scalar price conflicts

- Thyroid Autoantibodies: NPR `2000/3000` is ambiguous.
- BCR/ABL Minor: NPR `8000-9000`.
- Neonatal Sepsis Panels: NPR `7500-12500`.
- Special Biopsy Group A-E: NPR `3000-11000`.
- Individual IHC markers: NPR `3300-4400`; marker-specific rates are not supplied.

No non-scalar price is present in the prepared seed.

## Workflow holds

The following remain outside the safe import subset:

- PCR, viral load, genotyping, genetics, karyotyping and NGS-like panels.
- Culture and sensitivity, microbiology incubation, organism identification and antimicrobial susceptibility.
- Histopathology, cytology, FNAC and biopsy narratives.
- IHC marker panels beyond the existing manual-price IHC service.
- Packages until a canonical package-to-component relationship exists.
- Tests with price ranges, slash-separated prices, unclear method variants, custody requirements, or unsupported multi-specimen collection rules.
- Any reportable new test until authoritative parameters, units, value types, methods, reference ranges and responsible in-house/reference-lab ownership are approved.

## Safe New decision and migration reservation

Safe New count is **0**. Twenty exact-price routine candidates are normalized in the companion CSV, but each remains `Needs Clinical Configuration`: the source does not provide enough authoritative parameter/unit/reference-range information to activate a clinical result model without fabrication.

No migration is prepared or approved. Migration number `00050` is reserved for actual, clinically approved catalogue additions; a placeholder/no-op migration must not occupy that number. Existing rows and prices remain untouched.

## Approval gates before activation

1. Confirm Bimal’s actual price, method, container and in-house/reference-lab ownership.
2. Resolve semantic duplicates against live production rows.
3. Define authoritative result parameters and value types.
4. Approve reference ranges independently; missing ranges must remain visibly unconfigured.
5. Confirm sample grouping/container compatibility.
6. For profiles/packages, define canonical component relationships rather than copying component tests.
7. Run billing, sample, result-entry, reporting and historical-snapshot regressions.

## Row-level import boundary

The review establishes 307 source-level commercial rows and category totals, but the workspace contains row-level normalized data for only 20 routine candidates plus the four priority investigations (23 unique Draft identities because LDH overlaps both sets). The remaining 284 source identities are not represented by a reviewed code/name/status row in a machine-readable workspace artifact. They must not be reconstructed from category totals or assigned generated clinical codes without review.

Migration `00050` therefore stages the 23 traceable, deduplicated identities only. Completing the 307-row identity import requires a reviewed row-level CSV with at minimum source name, proposed canonical name/code, category, duplicate/reuse decision, profile/workflow classification, and configuration status.
