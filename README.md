Reproducible Analysis Code — README

================================================================================
1. Overview
================================================================================

This repository contains the R scripts used to generate all quantitative results,
the participant flowchart, and the Directed Acyclic Graphs (DAGs) reported in
the manuscript "Lower Admission Serum 25-Hydroxyvitamin D Is Independently
Associated with Worse Short-term Functional Outcomes in Patients with Hypertensive
Intracerebral Hemorrhage: A Prospective Cohort Study".

All scripts are written to run fully automatically and non-interactively — there
are no file-picker or directory dialogs. This design ensures computational
reproducibility and allows the code to be executed in unattended environments
(e.g., high-performance computing clusters, continuous integration servers).

================================================================================
2. Directory Structure
================================================================================

Place the entire project at a single root directory (the RStudio project root).
Every script derives its paths relative to the current working directory
(getwd()), so no absolute paths need to be edited.

project_root/
├── README.md                       <- this file
├── Allanalysis.R                  <- main statistical analysis
├── flowchart.R                    <- participant-selection flowchart (Figure)
├── core_DAG.R                     <- Figure 1: core (minimal) DAG
├── comprehensived_DAG.R           <- Figure S1: comprehensive DAG
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
- R packages — each script checks for and installs missing packages from CRAN
  (https://cloud.r-project.org/) on first run:
  - Allanalysis_SCI.R: tidyverse, readxl, and others.
  - flowchart.R: grid.
  - core_DAG.R / comprehensived_DAG.R: tidyverse, tidygraph, ggraph.
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

================================================================================
5. Running the Code
================================================================================

Two equivalent methods:

Option A — RStudio (Recommended for Development)
1. Open RStudio and set the working directory to the project root
   (Session -> Set Working Directory -> To Source File Location).
2. Open each .R script and click the Source button to run the entire script.
   Note: Do not select-and-run partial lines, as objects such as output_dir /
   out_files are defined at the top and used throughout.

Option B — Command Line (Fully Automated)
From the project root directory:

Rscript Allanalysis_SCI.R
Rscript flowchart.R
Rscript core_DAG.R
Rscript comprehensived_DAG.R

No command-line arguments are required — all paths are fixed inside the scripts.

================================================================================
6. Script Descriptions
================================================================================

6.1 Allanalysis_SCI.R — Main Analysis
- Reads data/clean/final_ich_cohort.xlsx.
- Produces: Table 1 (baseline characteristics, .xlsx + .docx), ordinal
  logistic regression results (primary and sensitivity models) as .csv,
  E-values for robustness, proportional-odds diagnostics, interaction tests,
  forest plots (.tiff), fitted model objects (.rds), and a console log.
- All outputs are written to output/.

6.2 flowchart.R — Participant Flowchart
- Draws the study participant-selection flowchart.
- Outputs: flowchart.png, flowchart.pdf, flowchart.tiff in output/.

6.3 core_DAG.R — Figure 1
- Plots the core STROBE-compliant DAG with the minimal sufficient adjustment set.
- Outputs: core_DAG.pdf, core_DAG.tiff.

6.4 comprehensived_DAG.R — Figure S1
- Plots the comprehensive DAG including the selection-bias (collider) node.
- Outputs: Figure_S1_comprehensive_DAG.pdf, Figure_S1_comprehensive_DAG.tiff.

================================================================================
7. Output Files & Provenance
================================================================================

Every script writes the following metadata files into output/ to ensure
traceability:

00_run_info.txt
  - Script name, run timestamp, R version, platform, source-data MD5 + size.

sessionInfo.txt
  - Full R and package-version information for exact environment reconstruction.

99_output_manifest.txt
  - Manifest listing every generated file with its size.

ERROR.txt
  - Created only on failure; contains the exact error message and traceback.

================================================================================
8. Reproducibility Notes
================================================================================

- All scripts are deterministic for a given input file and package versions;
  re-running produces identical numeric results and figures.
- No interactive prompts remain — the code runs end-to-end unattended.
- Font registration (Arial) is guarded for Windows and safely skipped on Linux;
  figures render on a white, publication-ready background.
- To rebuild the exact environment, install the package versions listed in
  output/sessionInfo.txt (e.g., via renv or install.packages()).

================================================================================
9. Troubleshooting
================================================================================

- "object 'output_dir' / 'out_files' not found"
  - Cause: You ran only a partial selection of lines.
  - Fix: Re-run the entire script via Source / Rscript.

- Any other error
  - Fix: Open output/ERROR.txt to read the captured error message.

- Missing packages / no internet
  - Fix: Pre-install the required packages in your environment; the scripts
    will then skip automatic installation.

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
2. Obtain a Persistent Identifier (DOI): Archive a specific release (e.g., via
   Zenodo, Figshare, or institutional repositories) to obtain a DOI. This allows
   others to cite the exact version of the code used in the study.
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
versions are recorded in output/sessionInfo.txt.

Data availability: The cohort dataset final_ich_cohort.xlsx contains
de-identified patient data. Due to privacy and ethical restrictions, the full
dataset is available from the corresponding author upon reasonable request.
(Alternative for public data: "...is publicly available at [URL/DOI].")

================================================================================

Prepared to meet general standards for computational reproducibility in
scientific research.
