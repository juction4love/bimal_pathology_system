# Priority Investigation Clinical-Configuration Audit — 2026-08-26

Status: review only. No migration was created or applied, and no production data was modified.

## Evidence and audit boundary

The comparison covered the repository's forward catalogue migrations, test and parameter seeds, reference ranges, calculation engine, result-entry behavior, frozen report snapshot creation, and canonical `ReportDocument` rendering. The four names were also searched semantically by expanded name and common acronym.

None of AFP, Bleeding Time, Clotting Time, PT/INR, Prothrombin Time, Patient PT, Control PT, ISI, INR, LDH, or Lactate Dehydrogenase has a test, parameter, reference-range, method, specimen/container, reporting-tier, or local-price row in the reviewed repository migrations. Acronym entries in string formatting and INR display precision are presentation helpers, not catalogue implementation.

The source catalogue remains non-authoritative. Its prices and specimen/method descriptions below are shown only to explain what requires operator confirmation.

## Decisions

| Investigation | Existing/new | Proposed canonical code | Proposed canonical name | Category | Shape | Local price | Production price confirmation | Activation decision |
|---|---|---|---|---|---|---:|---|---|
| AFP | New | `AFP` | Alpha-Fetoprotein (AFP) | Tumor Markers | Individual | Not defined | Required | **NEEDS BIMAL CLINICAL APPROVAL** |
| BT & CT | New | `BT_CT` | Bleeding Time and Clotting Time (BT & CT) | Hematology / Coagulation | One profile/investigation with two result parameters | Not defined | Required | **NEEDS BIMAL CLINICAL APPROVAL** |
| PT / INR | New | `PT_INR` | Prothrombin Time / International Normalized Ratio (PT / INR) | Hematology / Coagulation | One profile/investigation | Not defined | Required | **NEEDS BIMAL CLINICAL APPROVAL** |
| LDH | New | `LDH` | Lactate Dehydrogenase (LDH) | Clinical Biochemistry | Individual | Not defined | Required | **NEEDS BIMAL CLINICAL APPROVAL** |

Codes, canonical names, categories, and shapes in this table are proposals for approval, not seeded facts.

## AFP

- Existing match: none. `AFP` appears only as an acronym recognized by name-formatting code.
- Specimen/container: not authoritative locally. The source says Serum but supplies no container; both require Bimal confirmation.
- Method: not authoritative locally. The source's `CLIA/CMIA` is a choice, not a single validated local method.
- Parameters: no local parameter exists. A single `AFP` result is the likely shape, but its value type and parameter label require clinical approval.
- Unit: none configured; do not infer one.
- Validated reference ranges: none. No interval may be invented.
- Calculation dependencies: none found or proposed.
- Reporting tier: not configured; Bimal must select `InHouse` or `OutsourceWithBimalReport` according to the actual workflow.
- Price: none locally. Source reference NPR 1,600 must not be copied without operator confirmation.
- Safe to activate: no. Parameter value type, unit, method, specimen/container, reporting ownership, price, and any validated range are unresolved.

## BT & CT

- Existing match: none for the combined service or either component.
- Canonical shape: if approved, use one `BT_CT` investigation/profile containing `Bleeding Time` and `Clotting Time`; do not create separate duplicate billable/reportable services at the same time.
- Specimen/container: not authoritative locally. Source wording `Walk to Lab` describes collection context, not a specimen/container definition.
- Method: none configured.
- Parameters: proposed `BLEEDING_TIME` and `CLOTTING_TIME`; neither exists locally.
- Value types and units: not configured. Numeric/time units may be clinically plausible but are not authoritative and are therefore not seeded.
- Validated reference ranges: none.
- Calculation dependencies: none expected from current evidence; none configured.
- Reporting tier: not configured; likely workflow ownership must be confirmed rather than inferred.
- Price: none locally. Source reference NPR 400 requires operator confirmation.
- Safe to activate: no. Bimal must approve the combined-service model, collection workflow, method, parameter types/units, ranges, tier, and price.

## PT / INR

- Existing match: none. `PT`/`INR` acronym formatting and INR decimal precision support do not constitute an investigation or formula.
- Specimen/container: not authoritative locally. The source says Citrated Plasma and supplies no approved container configuration.
- Method: none configured.
- Parameters requested for clinical review: `PATIENT_PT`, `CONTROL_PT`, `ISI`, and `INR`. None exists locally, so names, value types, units, mandatory status, and display order are unapproved.
- Validated reference ranges: none for any proposed parameter.
- Calculation dependencies: none configured. The browser calculation engine can parse generic arithmetic dependencies, but no authoritative INR formula is present.
- Sign-off blocker: `recompute_order_item_calculated_results` is hard-coded to recompute only `IBIL`, `GLOB`, `AG_RATIO`, and `VLDL` before freezing a signed report. It does not calculate INR. Adding only parameter metadata would create a browser/server authority mismatch.
- Reporting tier: not configured.
- Price: none locally. The source contains PT at NPR 500 but does not establish a PT/INR service price; operator confirmation is required.
- Safe to activate: no. Requires Bimal-approved PT/INR model, formula and dependencies, units, ranges, specimen/container, method, tier, price, plus server-authoritative calculation implementation and regression tests.

## LDH

- Existing match: none. `LDH` appears only in acronym formatting; there is no existing LDH parameter or range to reuse.
- Specimen/container: not authoritative locally. The source says Body Fluid/Serum but this multi-specimen choice is not configured, and no container is supplied.
- Method: none configured.
- Parameters: no local parameter. A single `LDH` result is the likely shape, but its value type and label require approval.
- Unit: none configured.
- Validated reference ranges: none.
- Calculation dependencies: none found or proposed.
- Reporting tier: not configured.
- Price: none locally. Source reference NPR 800 requires operator confirmation.
- Safe to activate: no. Method-dependent unit/range, specimen handling, tier, price, and parameter configuration require approval.

## Existing report behavior relevant to activation

- Result entry supports `Numeric`, `Text`, `Select`, `Boolean`, `Heading`, and `Calculated` parameter types and loads only active, approved reference ranges.
- A missing approved range is explicitly rendered as `Not configured`; this prevents a fabricated interval but is not sufficient clinical configuration for activation.
- A combined BT/CT investigation would naturally render its two parameters as two rows under one investigation heading.
- Calculated parameters are visibly marked as calculated in the report. Signed snapshots preserve result values, formula metadata, units, flags, and resolved range text.

## Required approvals before a real `00050`

1. Confirm canonical service names/codes and whether each is in-house or Bimal-branded outsourced reporting.
2. Confirm production prices; never update existing prices from the reference catalogue.
3. Approve specimen, container, method, parameters, value types, units, mandatory status, and display order.
4. Supply independently validated reference ranges or explicitly approve a clinically appropriate no-range configuration where applicable.
5. For PT/INR, approve the exact formula/dependency semantics and extend the server-authoritative sign-off recalculation path before seeding.
6. Validate result entry, abnormal flags, snapshot freezing, and Chromium report output with clinical fixtures.

Current classification count: **0 READY TO SEED; 4 NEEDS BIMAL CLINICAL APPROVAL; 0 ALREADY IMPLEMENTED**.
