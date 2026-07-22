# Reproducible Analysis Code — README

## 1. Overview

This repository contains the R scripts used to generate all quantitative results,
the participant flowchart, and the Directed Acyclic Graphs (DAGs) reported in
the manuscript **"Lower Admission Serum 25-Hydroxyvitamin D Is Independently Associated with Worse Short-term Functional Outcomes in Patients with Hypertensive Intracerebral Hemorrhage: A Prospective Cohort Study"**.

All scripts are written to run **fully automatically and non-interactively** — there
are no file-picker or directory dialogs. This satisfies the code-availability and
reproducibility policies of the target journal and allows the code to be verified
on an unattended server (including Linux-based review/CI environments).

This README follows the **Frontiers** Code and Data Availability policy:
open-source code, deposited in a public repository (with a DOI) **or** uploaded as
a supplementary archive, accompanied by this README and an open-source license.

---

## 2. Directory structure

Place the **entire project at a single root directory** (the RStudio project
root). Every script derives its paths relative to the current working directory
(`getwd()`), so **no absolute paths need to be edited**.

```
project_root/
├── README.md                       <- this file
├── Allanalysis_SCI.R              <- main statistical analysis
├── flowchart.R                    <- participant-selection flowchart (Figure)
├── core_DAG.R                     <- Figure 1: core (minimal) DAG
├── comprehensived_DAG.R           <- Figure S1: comprehensive DAG
├── data/
│   └── clean/
│       └── final_ich_cohort.xlsx  <- INPUT cohort data (required)
└── output/                        <- auto-created; all results written here
```

> The `output/` folder is created automatically on the first run. You may submit
> it empty (the scripts will fill it) or pre-populated with prior results.

---

## 3. Software requirements

- **R** (version ≥ 4.0 recommended). The exact version used is recorded in
  `output/sessionInfo.txt` after a run.
- **R packages** — each script auto-installs any missing package from CRAN
  (`https://cloud.r-project.org/`) on first run:
  - `Allanalysis_SCI.R`: `tidyverse`, `readxl`, and others (see the
    package-install block at the top of the script).
  - `flowchart.R`: `grid`.
  - `core_DAG.R` / `comprehensived_DAG.R`: `tidyverse`, `tidygraph`, `ggraph`.
  - PDF figures use the bundled `cairo_pdf` device; TIFF uses the bundled
    `tiff` device — no external LaTeX/ghostscript required.
- **Internet** is needed on first run only, to install any missing CRAN packages.
- All dependencies used here are **open-source** (CRAN). If you later add any
  proprietary/closed-source package, declare it explicitly in the manuscript's
  Code Availability statement, as Frontiers requires code to be open-source.

---

## 4. Preparing the input data

1. Save the cleaned cohort dataset as  
   **`data/clean/final_ich_cohort.xlsx`** (relative to the project root).
2. The analysis script standardizes column names via `make.names()` and uses the
   variable names referenced inline. Document the data dictionary / variable
   definitions in the manuscript or a separate codebook.

---

## 5. Running the code

Two equivalent methods:

### Option A — RStudio (recommended for review)
1. Open RStudio and set the working directory to the project root
   (`Session → Set Working Directory → To Source File Location`, or open the
   folder as a project).
2. Open each `.R` script and click the **Source** button to run the whole
   script. **Do not** select-and-run partial lines — objects such as
   `output_dir` / `out_files` are defined at the top and used later, so a partial
   run will raise "object not found" errors.

### Option B — Command line (fully automated)
From the project root directory:

```bash
Rscript Allanalysis_SCI.R
Rscript flowchart.R
Rscript core_DAG.R
Rscript comprehensived_DAG.R
```

No command-line arguments are required — all paths are fixed inside the scripts.

---

## 6. What each script does

### 6.1 `Allanalysis_SCI.R` — main analysis
- Reads `data/clean/final_ich_cohort.xlsx`.
- Produces: Table 1 (baseline characteristics, `.xlsx` + `.docx`), ordinal
  logistic regression results (primary and sensitivity models) as `.csv`,
  E-values for robustness, proportional-odds / partial-proportional-odds
  diagnostics, interaction tests, forest plots (`.tiff`), fitted model objects
  (`.rds`), and a console log.
- All outputs are written to `output/`.

### 6.2 `flowchart.R` — participant flowchart
- Draws the study participant-selection flowchart (spontaneous ICH → exclusions
  → final analysis cohort).
- Cohort counts are the study's reported numbers, defined in-script; the source
  data file is recorded for provenance only.
- Outputs: `flowchart.png`, `flowchart.pdf`, `flowchart.tiff` in `output/`.

### 6.3 `core_DAG.R` — Figure 1
- Plots the core STROBE-compliant DAG with the minimal sufficient adjustment set.
- Outputs: `core_DAG.pdf`, `core_DAG.tiff`.

### 6.4 `comprehensived_DAG.R` — Figure S1
- Plots the comprehensive DAG including the selection-bias (collider) node.
- Outputs: `Figure_S1_comprehensive_DAG.pdf`, `Figure_S1_comprehensive_DAG.tiff`.

---

## 7. Output files & reproducibility logs

Every script additionally writes the following provenance files into `output/`:

| File | Purpose |
|------|---------|
| `00_run_info.txt` | Script name, run timestamp, R version, platform, source-data MD5 + size (where applicable), and key parameters. |
| `sessionInfo.txt` | Full R and package-version information for exact environment reconstruction. |
| `99_output_manifest.txt` | Manifest listing every generated file with its size, so reviewers can verify completeness. |
| `ERROR.txt` | Created **only on failure**; contains the exact error message, a traceback, and session info to aid debugging. |

---

## 8. Reproducibility notes

- All scripts are **deterministic** for a given input file and package versions;
  re-running reproduces identical numeric results and figures.
- **No interactive prompts remain** — the code runs end-to-end unattended,
  suitable for continuous-integration / journal verification servers.
- Font registration (`Arial`) is guarded for Windows and safely skipped on Linux;
  figures still render on a white, publication-ready background.
- To rebuild the exact environment, install the package versions listed in
  `output/sessionInfo.txt` (e.g. via `renv` or `install.packages()`).

---

## 9. Troubleshooting

- **"object 'output_dir' / 'out_files' not found"** — you ran only a partial
  selection of lines. Re-run the *entire* script via **Source** / `Rscript`.
- **Any other error** — open `output/ERROR.txt` and read the
  `=== Error message ===` section; it captures the first failure with a full
  traceback.
- **Missing packages / no internet** — pre-install the required packages in your
  environment; the scripts will then skip installation.

---

## 10. Contact

For code-related queries, contact the corresponding author:
**jueheng_p@139.com**

---

## 11. Repository & archiving (Frontiers requirement)

Frontiers requires that code be either (a) deposited in a recognized public
repository, or (b) uploaded as supplementary material. For full reproducibility we
recommend one of the following:

- **Public repository + archived DOI (preferred):** push this folder to
  GitHub/GitLab, then archive a release via **Zenodo** (or similar) to obtain a
  citable DOI, and cite that DOI in the manuscript.
- **Code Ocean (Frontiers partner):** create a Code Ocean "capsule" that executes
  the code in a controlled environment — Frontiers encourages this for
  computational manuscripts.
- **Supplementary archive:** if uploading directly to Frontiers, package the whole
  `project_root/` (README + 4 scripts + `data/clean/` + `output/`) as a single
  `.zip` and submit it as "Supplementary Material".

## 12. License

Frontiers requires submitted code to be **open-source** under an open-source
license. Add a `LICENSE` file to the repository root, for example:

- `MIT License` (permissive — recommended for analysis code), or
- `GPL-3.0` (copyleft).

State the chosen license in the manuscript's Code Availability statement.

## 13. Code & Data Availability statement (manuscript text)

Frontiers requires a short "Code and Data Availability" statement in the
manuscript. Use a template such as:

> **Code availability:** The analysis and figure-generation scripts (R ≥ 4.0) are
> available at &lt;repository URL, or "as Supplementary Material"&gt; under the
> &lt;MIT&gt; License. Exact package versions are recorded in
> `output/sessionInfo.txt`.
>
> **Data availability:** The cohort dataset `final_ich_cohort.xlsx` contains
> de-identified patient data and is available from the corresponding author upon
> reasonable request, subject to the original ethical approval.
> *(Alternatively, if the data is public: "is deposited at &lt;URL / DOI&gt; under
> &lt;CC-BY 4.0 / CC0&gt;.")*

> If the raw data cannot be made public for privacy/ethical reasons, Frontiers
> permits an "available on request" statement — but the **code** itself must
> still be publicly available.

---

*Prepared to meet the **Frontiers** computational reproducibility / code-availability
requirements.*
