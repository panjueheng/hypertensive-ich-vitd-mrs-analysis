Reproducible Analysis Code — README

================================================================================
1. Overview
================================================================================

This repository contains the R scripts used to generate all quantitative results,
the participant flowchart, and the Directed Acyclic Graphs (DAGs) reported in
the manuscript "Lower admission 25-hydroxyvitamin D associated with worse
functional outcome after hypertensive intracerebral hemorrhage: A prospective
cohort study".

All scripts are written to run fully automatically and non-interactively — there
are no file-picker or directory dialogs. This design ensures computational
reproducibility and allows the code to be executed in unattended environments
(e.g., high-performance computing clusters, continuous integration servers, or
reviewer machines).

================================================================================
2. Directory Structure
================================================================================

The project is organized as an RStudio Project (`ich_vitd_outcome.Rproj`).
**Double-clicking this `.Rproj` file is the recommended way to start** — it
automatically sets the correct working directory.

Every script derives its paths relative to the project root directory
(`getwd()`), so no absolute paths need to be edited.

ich_vitd_outcome/
├── ich_vitd_outcome.Rproj         <- RStudio Project file (DOUBLE-CLICK THIS)
├── README.md                      <- this file
├── Allanalysis.R                  <- main statistical analysis
├── flowchart.R                    <- participant-selection flowchart (Figure)
├── core DAG.R                     <- Figure 1: core (minimal) DAG
├── comprehensive DAG.R            <- Figure S1: comprehensive DAG
├── renv.lock                      <- (Optional but recommended) package versions
├── data/
│   └── clean/
│       └── final_ich_cohort.xlsx  <- INPUT cohort data (required)
└── output/                        <- auto-created; all results written here

Note: The output/ folder is created automatically on the first run.

================================================================================
3. Software Requirements
================================================================================

- R (version >= 4.0 recommended). The exact version used is recorded in
  output/sessionInfo.txt after a run.
- RStudio: Recommended for ease of use, but not strictly required.
- R packages — each script checks for and installs missing packages from CRAN
  (https://cloud.r-project.org/) on first run:
  - Allanalysis.R: MASS, brant, ordinal, VGAM, survival, splines, readxl,
    openxlsx, officer, flextable, lmtest, rms, mice.
  - flowchart.R: grid.
  - core DAG.R / comprehensive DAG.R: tidyverse, tidygraph, ggraph.
- Internet is needed on first run only, to install any missing CRAN packages.
- All dependencies used here are open-source (CRAN). If you later add any
  proprietary/closed-source package, please declare it appropriately in the
  manuscript's Code Availability statement.

================================================================================
4. Preparing the Input Data
================================================================================

1. Save the cleaned cohort dataset as:
   data/clean/final_ich_cohort.xlsx
   (relative to the project root).
2. The analysis script standardizes column names via make.names(). It is highly
   recommended to document the data dictionary and variable definitions in a
   separate codebook or the manuscript appendix.
   Note: The ICH score (Hemphill et al., Stroke 2001) is computed *inside* the
   script from its component variables (GCS, age, hemorrhage location, hematoma
   volume, and intraventricular extension), so it does not need to be supplied
   pre-computed in the input file.
3. De-identification: the shared dataset is fully de-identified. All direct
   identifiers have been removed — the hospital admission number (`No`), the
   admission date (`datein`), and the follow-up date (`followday`). Only the
   de-identified analysis variables are retained; note that the follow-up
   *duration in days* (`follow-up duration`, an analysis covariate used in
   every adjusted model) is kept, whereas the raw follow-up *date* is not.

================================================================================
5. Running the Code
================================================================================

Two equivalent methods:

Option A — RStudio (Recommended for Reviewers)
1. **Double-click `ich_vitd_outcome.Rproj`** to open the project. This
   automatically sets the working directory to the project root.
2. Open the desired .R script (e.g., Allanalysis.R).
3. Click the **Source** button (or press Ctrl+Shift+Enter / Cmd+Shift+Enter)
   to run the entire script.
   **Important**: Always run the *entire* script. Do not select and run partial
   lines, as objects such as output_dir / out_files are defined at the top and
   used throughout.

Option B — Command Line (Fully Automated)
From the project root directory:

Rscript Allanalysis.R
Rscript flowchart.R
Rscript "core DAG.R"
Rscript "comprehensive DAG.R"

No command-line arguments are required — all paths are fixed inside the scripts.

================================================================================
6. Script Descriptions
================================================================================

6.1 Allanalysis.R — Main Analysis
- Reads data/clean/final_ich_cohort.xlsx (relative to the project root; the
  ICH score is computed internally — see Section 4).
- Primary analysis: ordinal logistic regression (proportional-odds model) of
  functional outcome (mRS) on admission 25(OH)D, reported both continuously
  (per 10 nmol/L) and categorically (<50 vs >=50 nmol/L), under three models
  (unadjusted; age + gender + follow-up; fully adjusted +SBP).
- Sensitivity analyses: a series of 14 sensitivity analyses (analytical-method
  variants, alternative follow-up-time specifications, sequential addition of
  established ICH prognostic factors — NIHSS, GCS, hematoma volume, ICH score,
  random plasma glucose, creatinine — additional adjustment for surgery and
  the inflammatory marker NLR, and restriction to the non-surgical subgroup),
  each reported with its own E-value. Results are exported to
  sensitivity_analyses.csv and plotted as two forest plots: the key analyses
  in Figure 3 (Fig_sensitivity_forest.tiff) and the complete set in
  Supplementary Figure S2 (FigS2_forest_plot.tiff), both anchored by the
  Model 3 estimate.
- Major-revision analyses (Section 14b in the script):
  - R1 (surgery bias): Model 3 + surgery, a surgery ~ 25(OH)D diagnostic
    model, and non-surgical / surgical subgroup analyses.
  - R2 (Table 1 SMD): standardized mean differences for all Table 1 variables
    (R2_SMD_table1.csv), merged into baseline_characteristics_R.xlsx.
  - R4 (DAG transparency): minimal sufficient adjustment sets (pre-computed in
    DAGitty v3.1) with structure-sensitivity results
    (R4_DAG_adjustment_sets.txt).
  - R5 (BMI missingness): missingness-mechanism comparison
    (R5_BMI_missingness.csv), multiple imputation by chained equations
    (mice, m = 10), and complete-case analysis under {age, gender, BMI}.
  - R6 (inflammation): neutrophil-to-lymphocyte ratio (NLR) as surrogate for
    CRP — Spearman correlation with 25(OH)D and Model 3 + NLR.
  - R7 (power): post-hoc power and minimum detectable effect size (MDES).
- Robustness diagnostics: E-values (VanderWeele & Ding) for primary and
  sensitivity models, Brant proportional-odds tests (PO_assumption_check.txt),
  and VitD x Gender / VitD x Age interaction tests (interaction_tests.csv).
- Produces: Table 1 baseline characteristics (baseline_characteristics_R.xlsx
  and Table1_Baseline_Characteristics.docx, including an SMD column),
  ordinal logistic regression results (ordinal_logistic_results.csv),
  sensitivity results (sensitivity_analyses.csv), interaction tests
  (interaction_tests.csv), missing-data summary (missing_summary.txt), SMD
  table (R2_SMD_table1.csv), BMI missingness comparison
  (R5_BMI_missingness.csv), DAG adjustment sets (R4_DAG_adjustment_sets.txt),
  primary forest plot (forest_plot.tiff), key sensitivity forest plot
  (Fig_sensitivity_forest.tiff, Figure 3), complete sensitivity forest plot
  (FigS2_forest_plot.tiff, Figure S2), fitted model objects (.rds), and
  console/run logs.
- All outputs are written to output/.

6.2 flowchart.R — Participant Flowchart
- Draws the study participant-selection flowchart.
- Outputs: flowchart.png, flowchart.pdf, flowchart.tiff in output/.

6.3 core DAG.R — Figure 1
- Plots the core STROBE-compliant DAG with the minimal sufficient adjustment set.
- Outputs: core_DAG.pdf, core_DAG.tiff.

6.4 comprehensive DAG.R — Figure S1
- Plots the comprehensive DAG including the selection-bias (collider) node.
- Outputs: Figure_S1_comprehensive_DAG.pdf, Figure_S1_comprehensive_DAG.tiff.

================================================================================
7. Output Files & Provenance
================================================================================

Every script writes the following metadata files into output/ to ensure
traceability:

00_run_info.txt
  - Script name, run timestamp, R version, platform, source-data MD5 + size.

console_output.txt
  - Full console echo of the run (mirrors the on-screen log).

sessionInfo.txt
  - Full R and package-version information for exact environment reconstruction.

99_output_manifest.txt
  - Manifest listing every generated file with its size.

ERROR.txt
  - Created only on failure; contains the exact error message and traceback.

Key result files:
- baseline_characteristics_R.xlsx / Table1_Baseline_Characteristics.docx —
  baseline characteristics table (Table 1, including a standardized mean
  difference [SMD] column).
- ordinal_logistic_results.csv — primary regression results (OR, CI, P, E-value)
  for continuous and categorical 25(OH)D across Models 1–3.
- sensitivity_analyses.csv — 14 sensitivity-analysis results with E-values.
- interaction_tests.csv — VitD x Gender and VitD x Age interaction tests.
- missing_summary.txt — per-variable missingness summary.
- R2_SMD_table1.csv — standardized mean differences for all Table 1 variables.
- R5_BMI_missingness.csv — BMI missing vs complete group comparison.
- R4_DAG_adjustment_sets.txt — DAG minimal sufficient adjustment sets
  (DAGitty v3.1) and structure-sensitivity results.
- forest_plot.tiff — primary analysis forest plot.
- Fig_sensitivity_forest.tiff — key sensitivity forest plot (Figure 3).
- FigS2_forest_plot.tiff — complete sensitivity forest plot (Figure S2).
- PO_assumption_check.txt — Brant proportional-odds assumption tests.
- *.rds — fitted primary model objects (continuous + categorical).
- console_output.txt — full console echo of the run.

================================================================================
8. Reproducibility Notes
================================================================================

- All scripts are deterministic for a given input file and package versions;
  re-running produces identical numeric results and figures.
- No interactive prompts remain — the code runs end-to-end unattended.
- Font registration (Arial) is guarded for Windows and safely skipped on Linux;
  figures render on a white, publication-ready background.
- To rebuild the exact environment, install the package versions listed in
  output/sessionInfo.txt. The recommended method is renv (see below).

Using renv for exact environment reconstruction:
1. Ensure renv is installed: install.packages("renv")
2. Place the provided renv.lock file in the project root.
3. In the R console (with the project open): renv::restore()
4. Follow the prompts to install the specific package versions.

Without renv, the scripts will install the latest CRAN versions, which may
produce slightly different results due to package updates over time.

================================================================================
9. Troubleshooting
================================================================================

- "object 'output_dir' / 'out_files' not found"
  - Cause: You ran only a partial selection of lines.
  - Fix: Restart R (Ctrl+Shift+F10) and re-run the entire script via Source
    or Rscript.

- "cannot open file 'data/clean/...'"
  - Cause: Incorrect working directory or missing data file.
  - Fix: Ensure you opened the project via ich_vitd_outcome.Rproj and that
    final_ich_cohort.xlsx exists in data/clean/.

- Any other error
  - Fix: Open output/ERROR.txt to read the captured error message and
    traceback.

- Missing packages / no internet
  - Fix: Pre-install the required packages in your environment; the scripts
    will then skip automatic installation. Alternatively, use renv::restore()
    if a local package cache exists.

================================================================================
10. Contact
================================================================================

For code-related queries, contact the corresponding author:
jueheng_p@139.com

================================================================================
11. Archiving & Citation
================================================================================

To ensure long-term accessibility and citability, it is strongly recommended to:

1. Deposit in a Public Repository: Host this codebase on platforms like GitHub,
   GitLab, or Bitbucket.
2. Obtain a Persistent Identifier (DOI): https://10.5281/zenodo.21492323
3. Include in Manuscript: Cite the repository URL and/or DOI in the
   manuscript's "Code Availability" statement.

================================================================================
12. License
================================================================================

This project is licensed under the MIT License (see the LICENSE file in the
repository root). This permissive license allows for free use, modification, and
distribution, provided the original copyright notice is included.

================================================================================
13. Suggested Code & Data Availability Statement
================================================================================

When publishing, consider using a statement similar to the following in your
manuscript:

Code availability: The analysis and figure-generation scripts (R >= 4.0) are
available at [Repository URL or DOI] under the MIT License. Exact package
versions are recorded in output/sessionInfo.txt and locked via renv.lock.

Data availability: The cohort dataset final_ich_cohort.xlsx contains
de-identified patient data. Due to privacy and ethical restrictions, the full
dataset is available from the corresponding author upon reasonable request.
(Alternative for public data: "...is publicly available at [URL/DOI].")

Note: The Data Availability Statement in the manuscript must match the
deposit and access conditions described here.

================================================================================

Prepared to meet general standards for computational reproducibility in
scientific research.
