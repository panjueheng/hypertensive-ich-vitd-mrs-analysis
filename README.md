Analysis Code — README

================================================================================

1. Overview
   ================================================================================

This repository contains the R scripts used to generate every number, table and
figure reported in the manuscript

"Lower admission 25-hydroxyvitamin D associated with worse functional outcome
after hypertensive intracerebral hemorrhage: a prospective cohort study in
southern China"

Analytic cohort: n = 90. The 11 patients whose blood was sampled more than 12 h
after symptom onset were removed during data cleaning and are not part of the
shared data set, so no selection-bias or exclusion step is performed inside the
scripts.

The main script (`Allanalysis.R`) is self-contained: given the analytic data set
it reproduces the complete analysis, including the study flowchart (Figure 1),
which is drawn by Appendix A of the same script. Nothing has to be edited,
configured or supplied interactively.

Scripts run non-interactively — there are no file pickers or directory dialogs
in the analysis scripts — so the code can be executed unattended (HPC clusters,
continuous integration, or a reviewer's machine).

================================================================================
2. Directory Structure
======================

The project is organised as an RStudio Project (`ich_vitd_outcome.Rproj`).
Double-clicking the `.Rproj` file is the recommended way to start, because it
sets the working directory to the project root.

How each script resolves its paths:

- `Allanalysis.R` — uses the directory in which the script file itself lives.
  The working directory is irrelevant, and the file may be renamed freely.
- `core DAG.R`, `comprehensive DAG.R` — use `getwd()` as the project root, so
  they must be run from the project root (open the `.Rproj`, or `cd` there
  first).

ich_vitd_outcome/
├── ich_vitd_outcome.Rproj          <- RStudio Project file (DOUBLE-CLICK THIS)
├── README.md                       <- this file
├── Allanalysis.R                   <- main analysis: every number, table and
│                                      figure, including Figure 1 (Appendix A)
├── core DAG.R                      <- Figure 2: simplified core DAG
├── comprehensive DAG.R             <- Figure S1: comprehensive DAG
├── flowchart.R                     <- LEGACY, optional — see Section 6.2
├── renv.lock, renv/                <- optional: pinned package versions
├── LICENSE                         <- MIT
├── data/
│   └── clean/
│       └── final_ich_cohort.xlsx   <- INPUT analytic data set (required, n = 90)
└── output/                         <- auto-created; all results written here

Note: `output/` is created only if it does not exist. An existing `output/` is
never emptied: it is reused, files written by the run replace the previous file
of the same name, and unrelated files are left untouched.

================================================================================
3. Software Requirements
========================

- R >= 4.0 (the submitted analysis was run under R 4.4.3; the exact
  configuration is written to `output/sessionInfo.txt` at every run).
- RStudio: recommended for convenience, not required.
- R packages:
  - `Allanalysis.R` — readxl, MASS, ordinal, brant, car, mice, splines,
    ggplot2, officer, flextable, openxlsx, dplyr (grid ships with base R).
    The script does NOT install anything: if a package is missing it stops and
    prints the exact `install.packages(...)` call to run.
  - `core DAG.R` / `comprehensive DAG.R` — tidyverse, tidygraph, ggraph; these
    two scripts install any missing package from CRAN
    (https://cloud.r-project.org/) automatically on first run.
  - `flowchart.R` — grid only (base R).
- Internet access is needed only to install missing packages.
- All dependencies are open-source CRAN packages.

================================================================================
4. Preparing the Input Data
===========================

1. Save the cleaned analytic data set as

   data/clean/final_ich_cohort.xlsx

   relative to the folder that contains `Allanalysis.R`.
2. Column names are standardised with `make.names()` on import. A data
   dictionary is provided in the Supplementary Information of the manuscript
   (Supplementary Table S1). All analysis variables — including the ICH score —
   are supplied in the file; no score is recomputed inside the script.
3. De-identification: the shared data set is fully de-identified. All direct
   identifiers have been removed — hospital admission number (No), admission
   date (datein) and follow-up date (followday). The follow-up *duration in
   days* (follow-up duration) is retained because it is used as a covariate in
   every adjusted model; the raw follow-up *date* is not.

================================================================================
5. Running the Code
===================

Recommended order (the main script produces everything for the results, the two
DAG scripts produce the figures that are drawn from the causal graph):

Rscript Allanalysis.R
Rscript "core DAG.R"
Rscript "comprehensive DAG.R"

Option A — RStudio (recommended for reviewers)

1. Double-click `ich_vitd_outcome.Rproj` to open the project (this sets the
   working directory to the project root).
2. Open `Allanalysis.R`.
3. Session > Set Working Directory > To Source File Location, then click
   **Source** (Ctrl+Shift+Enter / Cmd+Shift+Enter) to run the whole script.
4. Run `core DAG.R` and `comprehensive DAG.R` the same way; because they use
   `getwd()`, keep the working directory at the project root.
   **Important**: always run each script in full. Do not execute partial
   selections — objects defined near the top are used throughout.

Option B — Command line (fully automated)
From the project root:

Rscript Allanalysis.R
Rscript "core DAG.R"
Rscript "comprehensive DAG.R"

No command-line arguments are required and nothing has to be edited. The main
script may be renamed (e.g. `Allanalysis_SciRep.R`); it detects its own name at
start-up and prints it in the console log and in `output/00_README.txt`, so the
log always matches the file on disk.

================================================================================
6. Script Descriptions
======================

6.1 Allanalysis.R — main analysis (sections follow the manuscript)
Input : data/clean/final_ich_cohort.xlsx (n = 90)
Output: everything listed in Section 7

1  Data import and derived variables (25(OH)D per 10 nmol/L, categorical
<50 vs >=50 nmol/L, log follow-up duration, mRS ordered factor)
2  Table 1 — baseline characteristics (three-line table; continuous variables
are tested with Welch's t-test when Shapiro-Wilk suggests normality and
with the Mann-Whitney U test otherwise; includes standardized mean
differences)
3  Primary analysis — proportional-odds ordinal logistic regression
(MASS::polr) of the 6-level mRS on 25(OH)D: Model 1 unadjusted,
Model 2 + age + sex + log follow-up, Model 3 + systolic blood pressure
4  Proportional-odds diagnostics — Brant test, nominal-effects test
(ordinal::clm), and the admissibility of partial proportional-odds
relaxations
5  Marginal (standardized) absolute risk difference from P25 to P75 of
25(OH)D, with a bootstrap confidence interval
6  Effect modification (Supplementary Table S4) with Benjamini-Hochberg
adjusted P values
7  Sensitivity analyses — 14 sensitivity specifications plus the primary
model = 15 specifications in total; Figure 3 of the manuscript shows 8
representative ones and the complete set of 15 is tabulated in
Supplementary Table S6 (a forest plot of all 15 is also written out)
8  Functional form — natural cubic splines (splines::ns) and the dose-response
curve, which is the figure presented as Supplementary Figure S2
9  Alternative adjustment set including BMI (60% missing): complete-case and
multiple imputation (mice, PMM, m = 20, maxit = 25)
10  Follow-up window strata
11  E-values for unmeasured confounding (VanderWeele & Ding), for the primary
and categorical analyses and on alternative exposure scales
12  Minimum detectable effect size and power check by simulation
12b Acute-phase surrogate adjustments (albumin, glucose) — reverse-causation
probe
12c Leave-one-out influence analysis (Model 3 refitted 90 times)
13, 13a  Supplementary Tables S5 and S3
13b Consistency check of every printed number against the manuscript
14  Consolidated workbook, session info and manifest
A  Appendix A — Figure 1, the study flowchart (drawing only, no statistics)

6.2 flowchart.R — LEGACY, not required

- Draws the study flowchart independently of the main script and writes
  `Figure1_flowchart.pdf`, `.tiff` and `.png` — the same file names produced by
  Appendix A of `Allanalysis.R`, so running it overwrites Figure 1.
- It is kept only for reference. In interactive use it asks for an output
  directory through a dialog, which breaks unattended execution; run it with an
  output-directory argument or leave it out entirely.

6.3 core DAG.R — Figure 2

- Simplified core DAG with the minimal sufficient adjustment set
  {age, sex, systolic blood pressure, log follow-up duration}.
- Sized and styled for Nature Portfolio artwork: 180 mm double column,
  7 pt Arial labels, 0.25-1.5 pt strokes.
- Outputs: `core_DAG.pdf`, `core_DAG.eps` (vector), `core_DAG.tiff` (600 dpi,
  LZW).

6.4 comprehensive DAG.R — Supplementary Figure S1

- Comprehensive DAG including the selection-bias (collider) node.
- Same artwork specification as 6.3.
- Outputs: `Figure_S1_comprehensive_DAG.pdf`, `.eps`, `.tiff`.

================================================================================
7. Output Files & Provenance
============================

Metadata written by the main script into `output/`:

00_README.txt

- Run instructions, file inventory, reproducibility notes, timestamp, R
  version and seed.
  00_output_manifest.txt
- Every file produced by the run, with its size.
  console_output.txt
- Complete console echo of the run, including every number quoted in the
  manuscript.
  sessionInfo.txt
- R version, package versions and locale for exact environment
  reconstruction.
  (The two DAG scripts additionally install missing packages and write
  `output/ERROR.txt` if they fail; the main script does not write ERROR.txt.)

Key result files:

Tables (CSV + a formatted three-line .docx for each)

- Table1_baseline.*                        main-text Table 1
- Table2_ordinal_models.*                  main-text Table 2
- TableS3_bmi_available_vs_missing.*       Supplementary Table S3
- TableS4_interactions.*                   Supplementary Table S4
- TableS5_additional_analyses.*            Supplementary Table S5

Figures (TIFF 600 dpi + PDF; TIFF/PNG are byte-identical between runs)

- Figure1_flowchart.*                      main-text Figure 1
- Figure3_key_sensitivity_forest.*         main-text Figure 3 (8 specifications)
- FigureS2_full_sensitivity_forest.*       forest plot of all 15 specifications
  (produced for completeness; in the
  manuscript the same 15 specifications
  are tabulated in Supplementary
  Table S6)
- FigureS3_dose_response.*                 dose-response curve — this is the
  figure presented as Supplementary
  Figure S2 in the manuscript. Note
  that file names follow the order in
  which the script draws the figures,
  which differs from the numbering used
  in the manuscript.
- core_DAG.*                               main-text Figure 2 (DAG script)
- Figure_S1_comprehensive_DAG.*            Supplementary Figure S1 (DAG script)

Supporting result files

- all_results.xlsx                         one workbook containing every table
- sensitivity_analyses.csv                 all 15 specifications with E-values
  and Benjamini-Hochberg adjusted P
- evalues.csv                              E-values on the reported scales
- absolute_risk_difference.csv             marginal risk difference, P25 to P75
- marginal_probabilities.csv               model-based category probabilities
- leave_one_out.csv                        Model 3 refitted 90 times
- reverse_causation_adjustments.csv        Model 3 + albumin / glucose / both
- reverse_causation_correlations.csv       Spearman correlations with severity
  and acute-phase markers
- followup_window_strata.csv               follow-up-window stratified models
- dose_response_curve.csv                  fitted dose-response curve
- mdes_power.csv                           minimum detectable effect size
- nonlinearity_tests.csv                   spline tests of linearity
- PO_assumption.txt                        Brant and nominal-effects tests, and
  the admissibility of the partial
  proportional-odds relaxations
- PO_alternative_checks.csv                6-level vs 3-level collapsed vs binary
- PO_partial_proportional_odds.csv         the relaxed fits (all inadmissible
  in this sample)
- Table2_fit_statistics.csv, Table2_vif.csv, Table2_models_detailed.csv
- Table1_vs_manuscript_check.csv           audit of Table 1 against the manuscript

================================================================================
8. Reproducibility Notes
========================

- The main script is deterministic. Its settings are declared in one place near
  the top of the file:
  SEED        = 20260911  master seed for every random procedure
  BOOT_ARD    = 2000      bootstrap replicates, absolute risk difference
  BOOT_SPLINE = 400       bootstrap replicates, dose-response band
  MI_M        = 20        multiple imputations (mice, PMM, maxit = 25)
  NSIM_POWER  = 300       simulations for the MDES power check
  QUANT_TYPE  = 6         quantile type (SPSS/Minitab convention), so that
  the quartile bounds in Table 1 of the manuscript
  are reproduced exactly; switching to the R default
  (7) changes 13 of the 27 Table 1 values by 0.1-0.3
  CUT_POINT   = 50        nmol/L threshold for the categorical analysis
  FIG_W_MM    = 180       figure width; change this one value for another
  journal's column width
  Repeated runs on the same R version therefore give identical results; numbers
  that involve no random draw at all are reproduced exactly by construction.
- Figures are rendered at final printed size (180 mm double column), with
  7 pt sans-serif text and 0.25-1.5 pt strokes, and are exported both as vector
  files (PDF/EPS) and as 600 dpi LZW-compressed TIFF. Figure titles and legends
  are not embedded in the image files.
- The source file is pure ASCII on purpose, to avoid encoding problems on
  Windows; non-ASCII glyphs used in Word tables are generated at run time with
  `intToUtf8()`.
- `output/` is never emptied: the script prints whether it created the folder or
  reused an existing one, and lists the files it produced.
- To rebuild the exact environment, install the package versions recorded in
  `output/sessionInfo.txt`; renv is the recommended mechanism:

  1. install.packages("renv")
  2. keep the provided renv.lock in the project root
  3. renv::restore()

  Without renv the latest CRAN versions are used, which may give slightly
  different results as packages evolve.

================================================================================
9. Troubleshooting
==================

- "Input data not found. Expected: <script dir>/data/clean/final_ich_cohort.xlsx"

  - Cause: the data file is not next to the script, or the script was run from
    an unexpected location.
  - Fix: confirm the file exists at data/clean/final_ich_cohort.xlsx relative to
    the script; in RStudio use Session > Set Working Directory > To Source File
    Location before sourcing.
- "Missing R package(s): ..."

  - Cause: a required package is not installed. The script stops rather than
    installing anything.
  - Fix: run the printed install.packages(...) call, then re-run the script.
- "object 'd' / 'f3c' not found"

  - Cause: only part of the script was executed.
  - Fix: restart R (Ctrl+Shift+F10) and run the whole script with Source or
    Rscript.
- A DAG script fails

  - Fix: open output/ERROR.txt for the captured error and traceback. Make sure
    the working directory is the project root, because these two scripts use
    getwd().

================================================================================
10. Contact
===========

For code-related queries, contact the corresponding author:
jueheng_p@139.com

================================================================================
11. Archiving & Citation
========================

1. Deposit in a public repository: this codebase is mirrored at
   https://github.com/panjueheng/hypertensive-ich-vitd-mrs-analysis
2. Persistent identifier (DOI): 10.5281/zenodo.21492323
   (If a new version is deposited, update the DOI here and in the manuscript's
   Data availability statement so that the two stay identical.)
3. Cite the repository URL and/or DOI in the manuscript's availability
   statement (see Section 13).

================================================================================
12. License
===========

This project is licensed under the MIT License (see the LICENSE file in the
repository root). This permissive license allows free use, modification and
distribution, provided the original copyright notice is included.

================================================================================
13. Availability Statements Used in the Manuscript
==================================================

Data availability: The data and R code supporting the findings of this study are
available at https://github.com/panjueheng/hypertensive-ich-vitd-mrs-analysis.

The statements in the manuscript must match the deposit and access conditions
described here.

================================================================================

Prepared to meet general standards for computational reproducibility in
scientific research.
