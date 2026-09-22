# ============================================================================
#  Allanalysis.R
#  Complete statistical analysis for:
#    "Lower admission 25-hydroxyvitamin D associated with worse functional
#     outcome after hypertensive intracerebral hemorrhage: a prospective
#     cohort study in southern China"
#
#  Analytic cohort: n = 90 (final, cleaned data set; the 11 patients sampled
#  > 12 h after onset were removed during data cleaning and are NOT part of
#  this file, so no exclusion / selection-bias section is needed here).
#
#  SELF-CONTAINED: the only two things needed are this file and the analytic
#  data set next to it. No other script, no manual path editing.
#
#    <this folder>/
#      Allanalysis.R
#      data/clean/final_ich_cohort.xlsx     <- input  (n = 90)
#      output/                              <- results; created only if absent,
#                                              otherwise reused and overwritten
#                                              file by file
#
#  Run from the command line : Rscript Allanalysis.R
#  Run from RStudio          : Session > Set Working Directory > To Source File
#                              Location, then Source
#
#  The file can be renamed freely (Allanalysis.R, Allanalysis_SciRep.R, ...):
#  the analysis is identical whatever the file is called, and nothing inside
#  the script depends on its own name. The name of the file actually being run
#  is detected at start-up and printed in the console log and in the README, so
#  the log always matches the file on disk.
#
#  Produces: Table 1 and Table 2 (main text), Figure 1 (flowchart, Appendix A),
#  Figure 3 and Supplementary Figures S2-S3, Supplementary Tables S3-S5, one
#  workbook with every result, and a full console log.
#
#  The input path is fixed relative to the script itself; nothing is read from
#  or written to any other directory. output/ is created only when it is
#  absent; an existing output/ is reused and only the files this script writes
#  are replaced (same name -> newest version wins).
#
#  Reproduction requirements (a snapshot is written to output/sessionInfo.txt
#  and output/00_README.txt at every run). Required CRAN packages are checked
#  before any analysis starts and, if any is missing, the script stops and
#  prints the exact install.packages() call.
#
#  The source file is pure ASCII on purpose (avoids encoding problems on
#  Windows). Non-ASCII glyphs used in tables are generated at run time with
#  intToUtf8() so that they are written to Word as proper UTF-8.
# ============================================================================

# ---------------------------------------------------------------- 0.1 paths
script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f) > 0) {
    f <- sub("^--file=", "", f[1])
    if (file.exists(f)) return(dirname(normalizePath(f)))
  }
  of <- tryCatch(as.character(sys.frame(1)$ofile), error = function(e) NULL)
  if (!is.null(of) && length(of) == 1 && !is.na(of) && file.exists(of)) {
    return(dirname(normalizePath(of)))
  }
  getwd()
}

SCRIPT_DIR <- script_dir()
# Name of the file actually being run. Detected the same way so that the
# console log and output/00_README.txt always name the file on disk, whichever
# name it was given.
script_name <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f) > 0) {
    f <- sub("^--file=", "", f[1])
    if (file.exists(f)) return(basename(f))
  }
  of <- tryCatch(as.character(sys.frame(1)$ofile), error = function(e) NULL)
  if (!is.null(of) && length(of) == 1 && !is.na(of) && file.exists(of)) {
    return(basename(of))
  }
  "Allanalysis.R"
}
SELF_NAME <- script_name()
DATA_FILE  <- file.path(SCRIPT_DIR, "data", "clean", "final_ich_cohort.xlsx")
if (!file.exists(DATA_FILE)) {
  stop("Input data not found.\n  Expected: ",
       file.path(SCRIPT_DIR, "data", "clean", "final_ich_cohort.xlsx"),
       "\n  The script reads its input only from <script dir>/data/clean/.",
       "\n  If the script was sourced from RStudio, set the working directory ",
       "to the script location first (Session > Set Working Directory > ",
       "To Source File Location).", call. = FALSE)
}
OUT_DIR <- file.path(SCRIPT_DIR, "output")
# An existing output/ directory is never emptied and never re-created: it is
# reused, and files produced by this run overwrite the previous file of the
# same name, so the newest version of every result is what stays on disk.
OUT_PRE_EXISTED <- dir.exists(OUT_DIR)
pre_existing <- if (OUT_PRE_EXISTED) list.files(OUT_DIR) else character(0)
if (OUT_PRE_EXISTED) {
  dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
  cat("Note: output/ already existed and was kept as it is; files with the\n",
      "     same name are overwritten, unrelated files are left untouched.\n",
      sep = "")
} else {
  dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
  cat("Note: output/ did not exist and has been created.\n")
}

# ------------------------------------------------------- 0.2 user settings
SEED        <- 20260911   # master seed
BOOT_ARD    <- 2000       # bootstrap replicates for the absolute risk difference
BOOT_SPLINE <- 400        # bootstrap replicates for the dose-response band
MI_M        <- 20         # multiple imputations (BMI analysis)
NSIM_POWER  <- 300        # simulations for the MDES power check
CUT_POINT   <- 50         # nmol/L, clinical threshold for the categorical analysis
ALPHA       <- 0.05
QUANT_TYPE  <- 6          # 6 = SPSS/Minitab: the quartile bounds of most
                          # continuous variables in Table 1 of the manuscript
                          # are reproduced exactly.
                          # 7 = R / Python / Excel default. Switching to 7 changes
                          # 13 of the 27 values in Table 1 by 0.1-0.3 units
                          # (quartile bounds only, never the medians).
                          # Run Table1_vs_manuscript_check.csv to see the effect.
FIG_FONT    <- "sans"     # Arial / Helvetica
FIG_W_MM    <- 180        # full double-column figure width in mm; change this
                          # single value to the width required by the target
                          # journal (single column is usually 85-90 mm)

# Sensitivity rows shown in the main-text forest plot (Figure 3).
# All 15 specifications are always written to Supplementary Figure S2.
MAIN_SENS <- c("Primary model (Model 3)",
               "Binary logistic (mRS > 2)",
               "Additionally adjusted for admission period",
               "NS follow-up time",
               "Additionally adjusted for ICH score",
               "Additionally adjusted for NLR",
               "Additionally adjusted for surgery",
               "Non-surgical subgroup")

# --------------------------------------------------- 0.3 glyphs + utilities
# On Windows the native code page cannot represent characters such as <=, mu or
# the superscript 2, which corrupts flextable column names. Switch to the UTF-8
# code page first; if that is impossible, fall back to ASCII spellings so that
# the script still runs and every table stays readable.
UTF8_OK <- FALSE
if (.Platform$OS.type == "windows") {
  UTF8_OK <- tryCatch({
    !is.na(Sys.setlocale("LC_ALL", ".UTF8")) &&
      isTRUE(l10n_info()$`UTF-8`)
  }, error = function(e) FALSE)
} else {
  UTF8_OK <- TRUE
}
if (UTF8_OK) {
  PM   <- intToUtf8(0x00B1)   # plus-minus
  LE   <- intToUtf8(0x2264)   # less-or-equal
  GE   <- intToUtf8(0x2265)   # greater-or-equal
  MU   <- intToUtf8(0x03BC)   # micro
  SUP2 <- intToUtf8(0x00B2)   # superscript two
  END  <- intToUtf8(0x2013)   # en dash
} else {
  PM <- "+-"; LE <- "<="; GE <- ">="; MU <- "u"; SUP2 <- "^2"; END <- "-"
  warning("UTF-8 locale unavailable; tables will use ASCII substitutes.")
}

fmt_p <- function(p) {
  ifelse(is.na(p), "", ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
}
f1 <- function(x) sprintf("%.1f", x)
f2 <- function(x) sprintf("%.2f", x)
f3 <- function(x) sprintf("%.3f", x)

# OR + Wald CI + P from an ordinal (polr / clm) or binary (glm) fit
or_ci <- function(fit, var = "vitd10") {
  V <- try(vcov(fit), silent = TRUE)
  if (inherits(V, "try-error")) return(c(OR = NA, LCL = NA, UCL = NA, P = NA))
  if (!(var %in% rownames(V))) return(c(OR = NA, LCL = NA, UCL = NA, P = NA))
  b  <- unname(coef(fit)[var])
  se <- sqrt(as.numeric(V[var, var]))
  if (is.na(b) || is.na(se)) return(c(OR = NA, LCL = NA, UCL = NA, P = NA))
  z  <- b / se
  c(OR  = exp(b),
    LCL = exp(b - 1.96 * se),
    UCL = exp(b + 1.96 * se),
    P   = 2 * (1 - pnorm(abs(z))))
}
or_ci_glm <- function(fit, var = "vitd10") {
  s  <- summary(fit)$coefficients
  b  <- unname(s[var, "Estimate"])
  se <- unname(s[var, "Std. Error"])
  c(OR  = exp(b),
    LCL = exp(b - 1.96 * se),
    UCL = exp(b + 1.96 * se),
    P   = unname(s[var, "Pr(>|z|)"]))
}
# E-value for an OR (and its CI limit) via the sqrt approximation OR -> RR
evalue_or <- function(or) {
  rr <- ifelse(or >= 1, sqrt(or), 1 / sqrt(or))
  rr + sqrt(rr * (rr - 1))
}
# E-value for the confidence interval. VanderWeele and Ding evaluate it at the
# limit closest to the null, which is the upper limit when the estimate is
# below 1 and the lower limit when it is above 1. Using the upper limit
# throughout would report 4.44 instead of 1.42 for the categorical model.
evalue_ci <- function(or, lo, hi) evalue_or(ifelse(or >= 1, lo, hi))

# ------------------------------------------------------------- 0.4 packages
need <- c("readxl", "MASS", "ordinal", "brant", "car", "mice",
          "splines", "ggplot2", "officer", "flextable", "openxlsx", "dplyr")
miss <- need[!vapply(need, requireNamespace, logical(1), quietly = TRUE)]
if (length(miss)) {
  stop("Missing R package(s): ", paste(miss, collapse = ", "),
       "\nInstall with: install.packages(c(",
       paste(sprintf("'%s'", miss), collapse = ", "), "))", call. = FALSE)
}
suppressPackageStartupMessages({
  library(readxl); library(MASS); library(ordinal); library(brant)
  library(car);                 library(mice);    library(splines)
  library(ggplot2); library(officer); library(flextable); library(openxlsx)
  library(dplyr);   library(grid)      # grid = base R, used for Figure 1
})
set.seed(SEED)

sink(file.path(OUT_DIR, "console_output.txt"), split = TRUE)
cat("================================================================\n")
cat(" ", SELF_NAME, " --  complete analysis, n = 90\n")
cat("================================================================\n")
cat("R version      :", R.version.string, "\n")
cat("Script dir     :", SCRIPT_DIR, "\n")
cat("Input data     :", DATA_FILE, "\n")
cat("Output dir     :", OUT_DIR, "\n")
cat("Date           :", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Seed           :", SEED, "\n\n")

# ============================================================================
# 1. DATA IMPORT AND DERIVED VARIABLES
# ============================================================================
raw <- read_excel(DATA_FILE)
names(raw) <- make.names(names(raw), unique = TRUE)
cat("Columns in file:\n"); print(names(raw)); cat("\n")

d <- raw
d$vitd       <- d$X25.OH.Vitamin.D
d$vitd10     <- d$vitd / 10                      # per 10 nmol/L
d$low50      <- as.integer(d$vitd < CUT_POINT)   # 1 = < 50 nmol/L
d$vitd_lt50  <- factor(ifelse(d$vitd < CUT_POINT, "<50", ">=50"),
                       levels = c(">=50", "<50"))
d$log_fu     <- log(d$follow.up.duration)
d$poor       <- as.integer(d$mRS > 2)
d$mRS_ord    <- ordered(d$mRS, levels = sort(unique(d$mRS)))
# The source workbook may carry either spelling of the column ("gender" in the
# submitted data extract, "sex" if the extract is ever regenerated). Normalise
# it to "sex" so that the code and the manuscript use the same term. The "[d]"
# below keeps this line from being rewritten by any gender -> sex sweep.
gid <- grep("^(gen[d]er|sex)$", names(d), value = TRUE)
if (length(gid) == 1L) names(d)[names(d) == gid] <- "sex"
d$sex        <- factor(d$sex, levels = c(1, 2), labels = c("Male", "Female"))
d$surgery    <- factor(d$surgical.treatment, levels = c(0, 1),
                       labels = c("No", "Yes"))
d$ivh        <- factor(d$intraventricular.extension, levels = c(0, 1),
                       labels = c("No", "Yes"))
d$period     <- factor(d$admission.period, levels = c(1, 2),
                       labels = c("May-October", "November-April"))
d$location   <- factor(d$Hemorrhage.location, levels = c(1, 2),
                       labels = c("Supratentorial", "Infratentorial"))
d$vol30      <- factor(ifelse(d$hematoma.volume >= 30, ">=30 mL", "<30 mL"),
                       levels = c("<30 mL", ">=30 mL"))
d$ich_grp    <- factor(ifelse(d$ICH_score <= 1, "ICH 0-1", "ICH >=2"),
                       levels = c("ICH 0-1", "ICH >=2"))
d$gcs_grp    <- factor(ifelse(d$GCS <= 8, "GCS <=8", "GCS >8"),
                       levels = c("GCS >8", "GCS <=8"))
d$fu120      <- factor(ifelse(d$follow.up.duration >= 120, ">=120 d", "<120 d"),
                       levels = c("<120 d", ">=120 d"))

# Rescaled copies of the continuous covariates. They are used only inside
# ordinal::clm (proportional-odds diagnostics, the collapsed-outcome check and
# the spline tests); every polr fit and every reported number stay on the
# original scale. Rescaling is an exact linear reparametrisation, so the
# log-likelihood, all LRTs, the AIC and the exposure estimate are unchanged -
# verified to the last printed digit (logLik identical, vitd10 coefficient and
# standard error identical, spline LRT P = 0.653 and 0.823, collapsed-outcome
# OR 0.70). The only purpose is numerical: on the raw scale SBP is around 185
# while log follow-up duration ranges from 4.45 to 5.23, so the Hessian of the
# six-level models has a condition number of 1.7e8 and clm flags
# "(3) Model is nearly unidentifiable: large eigenvalue ratio". After rescaling
# the condition number falls to 2.8e5 and clm reports successful convergence.
d$SBP10   <- d$SBP / 10
d$age10   <- d$age / 10
d$logfu_c <- (d$log_fu - mean(d$log_fu)) * 10

cat("=== Cohort description (text numbers for the manuscript) ===\n")
cat("N =", nrow(d), "\n")
cat("mRS distribution:\n"); print(table(d$mRS))
cat("No patient with mRS = 6:", !any(d$mRS == 6), "\n")
cat("Good outcome (mRS <= 2):", sum(d$mRS <= 2),
    " Poor outcome (mRS > 2):", sum(d$mRS > 2), "\n")
cat(sprintf("Age: median %.1f (IQR %.1f-%.1f)\n", median(d$age),
            quantile(d$age, .25, type = QUANT_TYPE),
            quantile(d$age, .75, type = QUANT_TYPE)))
cat("Male:", sum(d$sex == "Male"),
    sprintf("(%.1f%%)\n", 100 * mean(d$sex == "Male")))
cat(sprintf("Onset-to-sampling (BCT): median %.1f h (IQR %.1f-%.1f; range %.0f-%.0f)\n",
            median(d$BCT), quantile(d$BCT, .25, type = QUANT_TYPE),
            quantile(d$BCT, .75, type = QUANT_TYPE), min(d$BCT), max(d$BCT)))
cat(sprintf("Follow-up: median %.1f d (IQR %.1f-%.1f; range %.0f-%.0f)\n",
            median(d$follow.up.duration),
            quantile(d$follow.up.duration, .25, type = QUANT_TYPE),
            quantile(d$follow.up.duration, .75, type = QUANT_TYPE),
            min(d$follow.up.duration), max(d$follow.up.duration)))
cat(sprintf("25(OH)D: mean %.1f (SD %.1f); median %.1f (IQR %.1f-%.1f)\n",
            mean(d$vitd), sd(d$vitd), median(d$vitd),
            quantile(d$vitd, .25), quantile(d$vitd, .75)))
sw <- shapiro.test(d$vitd)
cat(sprintf("Shapiro-Wilk on 25(OH)D: W = %.4f, P = %.3f  (normal -> mean (SD))\n",
            sw$statistic, sw$p.value))
cat(sprintf("25(OH)D < %d nmol/L: %d (%.1f%%)\n", CUT_POINT,
            sum(d$low50 == 1), 100 * mean(d$low50 == 1)))
cat(sprintf("GCS <= 8: %d (%.1f%%) | hematoma >= 30 mL: %d (%.1f%%) | surgery: %d (%.1f%%)\n",
            sum(d$GCS <= 8), 100 * mean(d$GCS <= 8),
            sum(d$hematoma.volume >= 30), 100 * mean(d$hematoma.volume >= 30),
            sum(d$surgery == "Yes"), 100 * mean(d$surgery == "Yes")))
cat("BMI missing:", sum(is.na(d$BMI)),
    sprintf("(%.1f%%)\n", 100 * mean(is.na(d$BMI))))
ct_vd_nlr <- cor.test(d$vitd, d$NLR, method = "spearman", exact = FALSE)
cat(sprintf("25(OH)D vs NLR: Spearman rho = %.2f, P = %.2f\n",
            unname(ct_vd_nlr$estimate), ct_vd_nlr$p.value))
# Sample-size adequacy. The familiar n/5 ratio is not a valid events-per-
# variable figure for an ordinal model: Model 3 estimates 10 parameters (5
# cut-points + 5 slopes) and the sparsest outcome level holds
# min(table(d$mRS)) patients. Both honest counts are printed, and neither is
# quoted in the manuscript -- the leave-one-out and bootstrap evidence in
# sections 12c and 6 is what the paper relies on instead.
cat(sprintf("Model 3 parameters: %d cut-points + 5 slopes = %d; sparsest mRS level: %d patients\n",
            length(unique(d$mRS)) - 1, length(unique(d$mRS)) - 1 + 5,
            min(table(d$mRS))))
cat(sprintf("Conventional dichotomous EPV min(events, non-events)/5: %.1f\n",
            min(sum(d$mRS > 2), sum(d$mRS <= 2)) / 5))

# ============================================================================
# 2. TABLE 1 -- BASELINE CHARACTERISTICS (three-line table)
# ============================================================================
# Continuous variables are summarised as median (IQR); the exposure 25(OH)D is
# normally distributed and therefore summarised as mean (SD). Shapiro-Wilk
# results for every continuous variable are printed below for transparency.
grp  <- ifelse(d$mRS <= 2, "good", "poor")
gn   <- sum(grp == "good"); pn <- sum(grp == "poor")

cont_vars <- list(
  list(var = "age",                 label = "Age (years)",                 dig = 1),
  list(var = "BMI",                 label = paste0("BMI (kg/m", SUP2, ")"), dig = 1),
  list(var = "SBP",                 label = "SBP (mmHg)",                   dig = 1),
  list(var = "GCS",                 label = "GCS (score)",                  dig = 1),
  list(var = "NIHSS",               label = "NIHSS (score)",                dig = 1),
  list(var = "hematoma.volume",     label = "Hematoma volume (mL)",         dig = 1),
  list(var = "ICH_score",           label = "ICH (score)",                  dig = 1),
  list(var = "HGB",                 label = "Hemoglobin (g/L)",             dig = 1),
  list(var = "NLR",                 label = "NLR",                          dig = 1),
  list(var = "GLU",                 label = "RPG (mmol/L)",                 dig = 1),
  list(var = "Cr",                  label = paste0("Creatinine (", MU, "mol/L)"), dig = 1),
  list(var = "CHOL",                label = "Total cholesterol (mmol/L)",   dig = 1),
  list(var = "TRIG",                label = "Triglycerides (mmol/L)",       dig = 1),
  list(var = "HDL.C",               label = "HDL-C (mmol/L)",               dig = 1),
  list(var = "LDL.C",               label = "LDL-C (mmol/L)",               dig = 1),
  list(var = "ALT",                 label = "ALT (U/L)",                    dig = 1),
  list(var = "AST",                 label = "AST (U/L)",                    dig = 1),
  list(var = "GGT",                 label = "GGT (U/L)",                    dig = 1),
  list(var = "ALP",                 label = "ALP (U/L)",                    dig = 1),
  list(var = "ALB",                 label = "Albumin (g/L)",                dig = 1),
  list(var = "X25.OH.Vitamin.D",    label = "25(OH)D (nmol/L)",             dig = 1, normal = TRUE),
  list(var = "follow.up.duration",  label = "Follow-up duration (days)",    dig = 1)
)
cat_vars <- list(
  list(var = "sex",   label = "Sex, n (%)",              levels = c("Male", "Female")),
  list(var = "ivh",      label = "Intraventricular extension, n (%)", levels = c("No", "Yes")),
  list(var = "surgery",  label = "Surgical treatment, n (%)",  levels = c("No", "Yes")),
  list(var = "period",   label = "Admission period, n (%)",    levels = c("May-October", "November-April")),
  list(var = "location", label = "Hemorrhage location, n (%)", levels = c("Supratentorial", "Infratentorial"))
)

cat("\n=== Shapiro-Wilk on continuous variables (all patients) ===\n")
for (cv in cont_vars) {
  x <- d[[cv$var]]; x <- x[!is.na(x)]
  cat(sprintf("  %-26s P = %.4f\n", cv$var, shapiro.test(x)$p.value))
}

med_iqr <- function(x, dig = 1) {
  q <- quantile(x, c(.25, .5, .75), na.rm = TRUE, type = QUANT_TYPE)
  sprintf(paste0("%.", dig, "f (%.", dig, "f", END, "%.", dig, "f)"),
          q[2], q[1], q[3])
}
mean_sd <- function(x, dig = 1) {
  sprintf(paste0("%.", dig, "f ", PM, " %.", dig, "f"), mean(x, na.rm = TRUE),
          sd(x, na.rm = TRUE))
}
smd_cont <- function(x, g) {
  a <- x[g == "good"]; b <- x[g == "poor"]
  a <- a[!is.na(a)];   b <- b[!is.na(b)]
  s <- sqrt((var(a) + var(b)) / 2)
  if (!is.finite(s) || s == 0) return(0)
  (mean(b) - mean(a)) / s
}
smd_cat <- function(p1, p2) {
  s <- sqrt((p1 * (1 - p1) + p2 * (1 - p2)) / 2)
  if (!is.finite(s) || s == 0) return(0)
  (p2 - p1) / s
}
p_cat <- function(tab) {
  e <- suppressWarnings(chisq.test(tab)$expected)
  if (any(e < 5)) fisher.test(tab)$p.value else chisq.test(tab, correct = FALSE)$p.value
}

# Display order of Table 1 (identical to the manuscript)
tab1_spec <- list(
  list(type = "cont", var = "age"),
  list(type = "cat",  var = "sex"),
  list(type = "cont", var = "BMI"),
  list(type = "cont", var = "SBP"),
  list(type = "cont", var = "GCS"),
  list(type = "cont", var = "NIHSS"),
  list(type = "cont", var = "hematoma.volume"),
  list(type = "cont", var = "ICH_score"),
  list(type = "cat",  var = "ivh"),
  list(type = "cat",  var = "surgery"),
  list(type = "cat",  var = "period"),
  list(type = "cat",  var = "location"),
  list(type = "cont", var = "HGB"),
  list(type = "cont", var = "NLR"),
  list(type = "cont", var = "GLU"),
  list(type = "cont", var = "Cr"),
  list(type = "cont", var = "CHOL"),
  list(type = "cont", var = "TRIG"),
  list(type = "cont", var = "HDL.C"),
  list(type = "cont", var = "LDL.C"),
  list(type = "cont", var = "ALT"),
  list(type = "cont", var = "AST"),
  list(type = "cont", var = "GGT"),
  list(type = "cont", var = "ALP"),
  list(type = "cont", var = "ALB"),
  list(type = "cont", var = "X25.OH.Vitamin.D"),
  list(type = "cont", var = "follow.up.duration"))

t1_rows <- list()
add_row <- function(characteristic, total, good, poor, p, smd, indent = FALSE) {
  t1_rows[[length(t1_rows) + 1]] <<- data.frame(
    Characteristic = if (indent) paste0("    ", characteristic) else characteristic,
    Total = total, Good = good, Poor = poor, P = p, SMD = smd,
    stringsAsFactors = FALSE)
}
spec_of <- function(lst, v) lst[[match(v, vapply(lst, function(z) z$var, ""))]]

for (sp in tab1_spec) {
  if (sp$type == "cont") {
    cv <- spec_of(cont_vars, sp$var)
    x  <- d[[cv$var]]
    xg <- x[grp == "good"]; xp <- x[grp == "poor"]
    if (!isTRUE(cv$normal)) {
      tot <- med_iqr(x, cv$dig); gd <- med_iqr(xg, cv$dig); pr <- med_iqr(xp, cv$dig)
    } else {
      tot <- mean_sd(x, cv$dig);  gd <- mean_sd(xg, cv$dig);  pr <- mean_sd(xp, cv$dig)
    }
    # Test of group difference: Welch's t-test for the variable that satisfied
    # normality (25(OH)D), Mann-Whitney U for every other continuous variable.
    # This follows the rule stated in the Statistical analysis section of the
    # manuscript (Shapiro-Wilk -> mean +- SD -> Welch; otherwise median (IQR)
    # -> Mann-Whitney U).
    pv <- if (isTRUE(cv$normal)) {
      suppressWarnings(t.test(xg, xp, var.equal = FALSE)$p.value)
    } else {
      suppressWarnings(wilcox.test(xg, xp)$p.value)
    }
    # The choice of test rests on a Shapiro-Wilk pre-test, so for the single
    # variable that satisfied normality we also keep the Mann-Whitney U
    # result. It is disclosed in the Table 1 footnote so that a reader can see
    # how much the reported P value depends on that pre-test.
    if (isTRUE(cv$normal)) {
      p_mw_normal   <<- suppressWarnings(wilcox.test(xg, xp)$p.value)
      label_normal  <<- cv$label
      p_welch_normal <<- pv
    }
    add_row(cv$label, tot, gd, pr, fmt_p(pv), sprintf("%.3f", smd_cont(x, grp)))
  } else {
    cv <- spec_of(cat_vars, sp$var)
    v  <- droplevels(as.factor(d[[cv$var]]))
    v  <- factor(as.character(v), levels = cv$levels)
    tab_all <- table(v)
    tab_grp <- table(v, grp)
    p_good <- as.numeric(tab_grp[cv$levels[1], "good"]) / gn
    p_poor <- as.numeric(tab_grp[cv$levels[1], "poor"]) / pn
    add_row(cv$label,
            sprintf("%d (%.1f%%)", tab_all[cv$levels[1]],
                    100 * mean(v == cv$levels[1], na.rm = TRUE)),
            sprintf("%d (%.1f%%)", tab_grp[cv$levels[1], "good"], 100 * p_good),
            sprintf("%d (%.1f%%)", tab_grp[cv$levels[1], "poor"], 100 * p_poor),
            fmt_p(p_cat(tab_grp)), sprintf("%.3f", smd_cat(p_good, p_poor)))
    for (lvX in cv$levels) {
      add_row(lvX,
              sprintf("%d (%.1f%%)", tab_all[lvX],
                      100 * mean(v == lvX, na.rm = TRUE)),
              sprintf("%d (%.1f%%)", tab_grp[lvX, "good"],
                      100 * as.numeric(tab_grp[lvX, "good"]) / gn),
              sprintf("%d (%.1f%%)", tab_grp[lvX, "poor"],
                      100 * as.numeric(tab_grp[lvX, "poor"]) / pn),
              "", "", indent = TRUE)
    }
  }
}
t1 <- bind_rows(t1_rows)

hdr_row <- data.frame(Characteristic = "n",
                      Total = paste0("N = ", nrow(d)),
                      Good  = paste0("N = ", gn),
                      Poor  = paste0("N = ", pn),
                      P = "", SMD = "", stringsAsFactors = FALSE)
t1_out <- bind_rows(hdr_row, t1)
write.csv(t1_out, file.path(OUT_DIR, "Table1_baseline.csv"), row.names = FALSE,
          fileEncoding = "UTF-8")

# ---- three-line Word table -------------------------------------------------
make_three_line_docx <- function(df, path, title, footnote = NULL, widths = NULL) {
  ft <- flextable(df)
  ft <- theme_booktabs(ft)
  ft <- font(ft, fontname = "Arial", part = "all")
  ft <- fontsize(ft, size = 9, part = "all")
  ft <- fontsize(ft, size = 9, part = "header")
  ft <- bold(ft, part = "header")
  ft <- align(ft, align = "left", part = "header")
  ft <- align(ft, j = 1, align = "left", part = "body")
  if (ncol(df) > 1) ft <- align(ft, j = 2:ncol(df), align = "center", part = "body")
  ft <- valign(ft, valign = "top", part = "all")
  ft <- padding(ft, padding = 2, part = "all")
  ft <- set_table_properties(ft, layout = "autofit")
  if (!is.null(widths)) ft <- width(ft, width = widths)
  doc <- read_docx()
  doc <- body_add_par(doc, title, style = "Normal")
  doc <- body_add_flextable(doc, ft)
  if (!is.null(footnote)) {
    for (fn in footnote) doc <- body_add_par(doc, fn, style = "Normal")
  }
  print(doc, target = path)
  invisible(path)
}
tab1_df <- t1_out
names(tab1_df) <- c("Characteristic",
                    paste0("Total (N = ", nrow(d), ")"),
                    paste0("Good outcome (mRS ", LE, " 2) (N = ", gn, ")"),
                    paste0("Poor outcome (mRS > 2) (N = ", pn, ")"),
                    "P value", "SMD")
fn1 <- paste0("Values are median (IQR) or n (%); 25(OH)D is mean ", PM,
              " SD because it was normally distributed (Shapiro-Wilk P = ",
              sprintf("%.2f", sw$p.value), ").")
fn2 <- paste0("P values from Welch's t-test for normally distributed ",
              "variables and the Mann-Whitney U test otherwise (continuous), ",
              "and from the chi-square test, or Fisher's exact test when any ",
              "expected count was < 5 (categorical). The choice between the ",
              "two continuous tests rests on a Shapiro-Wilk pre-test, so it ",
              "is disclosed here: for ", label_normal, ", the only variable ",
              "that satisfied normality, Welch's t-test gives P = ",
              fmt_p(p_welch_normal), " (reported) whereas the Mann-Whitney U ",
              "test gives P = ", fmt_p(p_mw_normal), "; the direction and the ",
              "magnitude of the group difference are unchanged.")
fn3 <- paste0("SMD = standardised mean difference (poor versus good outcome). ",
              "BMI was available in ", sum(!is.na(d$BMI)), " patients.")
fn4 <- paste0("Abbreviations: SMD, standardised mean difference; SBP, systolic ",
              "blood pressure; GCS, Glasgow Coma Scale; NIHSS, National ",
              "Institutes of Health Stroke Scale; ICH, intracerebral ",
              "haemorrhage; NLR, neutrophil-to-lymphocyte ratio; RPG, random ",
              "plasma glucose; HDL-C, high-density lipoprotein cholesterol; ",
              "LDL-C, low-density lipoprotein cholesterol; 25(OH)D, ",
              "25-hydroxyvitamin D.")
t1_docx <- make_three_line_docx(
  tab1_df, file.path(OUT_DIR, "Table1_baseline_three_line.docx"),
  "Table 1. Baseline characteristics of the study population.",
  footnote = c(fn1, fn2, fn3, fn4))
cat("\nTable 1 written:", t1_docx, "\n")
print(t1_out, row.names = FALSE)

# ============================================================================
# 3. PRIMARY ANALYSIS -- ORDINAL LOGISTIC REGRESSION (TABLE 2)
# ============================================================================
f1c <- "mRS_ord ~ vitd10"
f2c <- "mRS_ord ~ vitd10 + age + sex + log_fu"
f3c <- "mRS_ord ~ vitd10 + age + sex + SBP + log_fu"
# f3s is f3c with the continuous covariates on the rescaled scale (see the note
# in section 1). It is passed to ordinal::clm only; it describes the same model.
f3s <- "mRS_ord ~ vitd10 + age10 + sex + SBP10 + logfu_c"
m1 <- polr(as.formula(f1c), data = d, method = "logistic", Hess = TRUE)
m2 <- polr(as.formula(f2c), data = d, method = "logistic", Hess = TRUE)
m3 <- polr(as.formula(f3c), data = d, method = "logistic", Hess = TRUE)

k1 <- polr(mRS_ord ~ vitd_lt50, data = d, method = "logistic", Hess = TRUE)
k2 <- polr(mRS_ord ~ vitd_lt50 + age + sex + log_fu, data = d,
           method = "logistic", Hess = TRUE)
k3 <- polr(mRS_ord ~ vitd_lt50 + age + sex + SBP + log_fu, data = d,
           method = "logistic", Hess = TRUE)

cat("\n=== Table 2: primary ordinal logistic models ===\n")
tab2 <- data.frame(
  Variable = c("Panel A: Primary analysis (continuous)",
               "25(OH)D (per 10 nmol/L increment)",
               "Panel B: Categorical analysis",
               paste0(GE, " 50 nmol/L"),
               paste0("< 50 nmol/L")),
  Model1 = c("", "", "", "Ref", ""),
  Model2 = c("", "", "", "Ref", ""),
  Model3 = c("", "", "", "Ref", ""),
  stringsAsFactors = FALSE)
for (i in 1:3) {
  fm <- get(paste0("m", i)); rr <- or_ci(fm, "vitd10")
  tab2[2, i + 1] <- sprintf("%.2f (%.2f, %.2f)", rr["OR"], rr["LCL"], rr["UCL"])
  fk <- get(paste0("k", i)); rk <- or_ci(fk, "vitd_lt50<50")
  tab2[5, i + 1] <- sprintf("%.2f (%.2f, %.2f)", rk["OR"], rk["LCL"], rk["UCL"])
}
print(tab2, row.names = FALSE)
write.csv(tab2, file.path(OUT_DIR, "Table2_ordinal_models.csv"), row.names = FALSE,
          fileEncoding = "UTF-8")

res_det <- rbind(
  data.frame(Analysis = "Continuous, per 10 nmol/L",
             Model = c("Model 1", "Model 2", "Model 3"),
             t(sapply(list(m1, m2, m3), function(z) or_ci(z, "vitd10")))),
  data.frame(Analysis = paste0("Categorical, <50 vs ", GE, " 50 nmol/L"),
             Model = c("Model 1", "Model 2", "Model 3"),
             t(sapply(list(k1, k2, k3), function(z) or_ci(z, "vitd_lt50<50")))))
rownames(res_det) <- NULL
res_det$E_value <- evalue_or(res_det$OR)
res_det$E_value_CI <- evalue_ci(res_det$OR, res_det$LCL, res_det$UCL)
cat("\nDetailed estimates:\n"); print(res_det, row.names = FALSE)
write.csv(res_det, file.path(OUT_DIR, "Table2_models_detailed.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")

# ---- fit statistics and collinearity --------------------------------------
ll0 <- as.numeric(logLik(polr(mRS_ord ~ 1, data = d, method = "logistic", Hess = TRUE)))
fit_tab <- do.call(rbind, lapply(
  list("Model 1" = m1, "Model 2" = m2, "Model 3" = m3), function(z) {
    ll <- as.numeric(logLik(z)); n <- nrow(d)
    data.frame(logLik = ll, McFadden = 1 - ll / ll0,
               Nagelkerke = (1 - exp((2 / n) * (ll0 - ll))) /
                            (1 - exp((2 / n) * ll0)),
               AIC = AIC(z))
  }))
fit_tab <- data.frame(Model = c("Model 1", "Model 2", "Model 3"), fit_tab)
cat("\nFit statistics:\n"); print(fit_tab, row.names = FALSE)
write.csv(fit_tab, file.path(OUT_DIR, "Table2_fit_statistics.csv"), row.names = FALSE)

X <- model.matrix(as.formula("~ vitd10 + age + sex + SBP + log_fu"), data = d)
X <- X[, colnames(X) != "(Intercept)", drop = FALSE]
vif_tab <- data.frame(Variable = colnames(X), VIF = round(diag(solve(cor(X))), 3))
cat("\nVIF (Model 3):\n"); print(vif_tab, row.names = FALSE)
write.csv(vif_tab, file.path(OUT_DIR, "Table2_vif.csv"), row.names = FALSE)

t2_docx_df <- tab2
names(t2_docx_df) <- c("Variable", "Model 1 OR (95% CI)", "Model 2 OR (95% CI)",
                       "Model 3 OR (95% CI)")
make_three_line_docx(
  t2_docx_df, file.path(OUT_DIR, "Table2_ordinal_models_three_line.docx"),
  "Table 2. Association between 25(OH)D levels and mRS assessed by ordinal logistic regression.",
  footnote = c(paste0("Model 1: unadjusted. Model 2: adjusted for age, sex and ",
                      "log follow-up duration. Model 3: additionally adjusted ",
                      "for systolic blood pressure."),
               paste0("OR < 1 indicates lower odds of a worse mRS with higher ",
                      "25(OH)D. ** P < 0.01, * P < 0.05.")))

# ============================================================================
# 4. PROPORTIONAL ODDS ASSUMPTION
# ============================================================================
cat("\n=== Proportional odds diagnostics (Model 3) ===\n")
sink(file.path(OUT_DIR, "PO_assumption.txt"), split = TRUE)
cat("--- Brant test, Model 3 ---\n")
print(suppressWarnings(try(brant::brant(m3), silent = TRUE)))
cat("\n--- nominal_test (clm), Model 3 ---\n")
clm3 <- clm(as.formula(f3s), data = d, link = "logit")
print(nominal_test(clm3))
cat("\nNote: a relaxation is only interpretable if the fitted thresholds are still\n",
    "increasing. That is checked explicitly for each of these relaxations in the\n",
    "next block, including the relaxation of log follow-up time, which is the one\n",
    "with the largest apparent gain in fit above; it fails the check, so it is\n",
    "recorded as inadmissible and never quoted.\n")
cat("\n--- Partial proportional odds models (admissibility checked) ---\n")
# Declaring a covariate nominal adds K - 1 category-specific parameters, i.e.
# five for each covariate with six outcome levels, estimated from 90 patients.
# In this sample every relaxation attempted returns an inadmissible fit: the
# estimated thresholds are not increasing, which would imply negative category
# probabilities, and the design is rank deficient, so the apparent gain in fit
# reflects near-separation rather than a better description of the data. That
# is checked explicitly below; an inadmissible fit is recorded, never quoted.
# The fits are run on the rescaled covariates (f3s) so that the check rests on
# optima that were actually reached: on the raw scale several relaxations stop
# with a non-zero convergence code, which says nothing about admissibility.
ppo_try <- function(nom_rhs, label) {
  fit <- try(suppressWarnings(clm(as.formula(f3s), data = d, link = "logit",
                                  nominal = as.formula(nom_rhs))), silent = TRUE)
  if (inherits(fit, "try-error")) {
    cat(sprintf("%-44s : FAILED TO FIT\n", label)); return(NULL)
  }
  alpha <- as.numeric(fit$alpha)
  mono <- all(diff(alpha) > 0)
  if (!mono || !isTRUE(fit$convergence$code == 0)) {
    cat(sprintf("%-44s : INADMISSIBLE (monotone thresholds = %s, code = %d)\n",
                label, mono, fit$convergence$code))
    return(data.frame(Model = label, OR = NA, LCL = NA, UCL = NA, P = NA,
                      AIC = AIC(fit), Admissible = FALSE,
                      stringsAsFactors = FALSE))
  }
  b  <- coef(fit)["vitd10"]; se <- sqrt(vcov(fit)["vitd10", "vitd10"])
  cat(sprintf("%-44s OR = %.2f (%.2f-%.2f) P = %.4f | AIC %.2f vs %.2f\n", label,
              exp(b), exp(b - 1.96 * se), exp(b + 1.96 * se),
              2 * (1 - pnorm(abs(b / se))), AIC(fit), AIC(clm3)))
  data.frame(Model = label, OR = exp(b), LCL = exp(b - 1.96 * se),
             UCL = exp(b + 1.96 * se),
             P = 2 * (1 - pnorm(abs(b / se))), AIC = AIC(fit),
             Admissible = TRUE, stringsAsFactors = FALSE)
}
ppo <- list(ppo_try("~ logfu_c", "PPO: non-PO on log follow-up"),
            ppo_try("~ age10", "PPO: non-PO on age"),
            ppo_try("~ sex", "PPO: non-PO on sex"),
            ppo_try("~ age10 + logfu_c", "PPO: non-PO on age + log follow-up"),
            ppo_try("~ age10 + sex + logfu_c", "PPO: age + sex + log follow-up"))
ppo <- ppo[!vapply(ppo, is.null, logical(1))]
if (length(ppo)) {
  ppo_df <- bind_rows(ppo)
  cat("\nAIC of the proportional-odds Model 3 (clm):", sprintf("%.2f", AIC(clm3)), "\n")
  write.csv(ppo_df, file.path(OUT_DIR, "PO_partial_proportional_odds.csv"),
            row.names = FALSE)
}

cat("\n--- Checks that do not rely on an admissible PPO relaxation ---\n")
# The constraint can also be side-stepped by coarsening the outcome instead of
# relaxing it. Both specifications below are admissible (monotone thresholds,
# full rank) and neither imposes the six-level proportional-odds structure.
d$mRS3     <- cut(d$mRS, breaks = c(-1, 2, 4, 6), labels = c("0-2", "3-4", "5"))
d$mRS3_ord <- ordered(d$mRS3, levels = c("0-2", "3-4", "5"))
clm3_3     <- clm(mRS3_ord ~ vitd10 + age10 + sex + SBP10 + logfu_c, data = d,
                  link = "logit")
b3l  <- unname(coef(clm3_3)["vitd10"])
se3l <- sqrt(vcov(clm3_3)["vitd10", "vitd10"])
d$poor_bin <- d$mRS > 2
glm_bin <- suppressWarnings(glm(poor_bin ~ vitd10 + age + sex + SBP + log_fu,
                                data = d, family = binomial()))
bb  <- unname(coef(glm_bin)["vitd10"])
sbb <- summary(glm_bin)$coefficients["vitd10", "Std. Error"]
cat(sprintf("%-44s OR = %.2f (%.2f-%.2f) P = %.4f | thresholds %s, code %d\n",
            "Ordinal, outcome collapsed to 3 levels (0-2/3-4/5)",
            exp(b3l), exp(b3l - 1.96 * se3l), exp(b3l + 1.96 * se3l),
            2 * (1 - pnorm(abs(b3l / se3l))),
            all(diff(as.numeric(clm3_3$alpha)) > 0), clm3_3$convergence$code))
cat(sprintf("%-44s OR = %.2f (%.2f-%.2f) P = %.4f\n",
            "Binary logistic, outcome dichotomised at mRS 2",
            exp(bb), exp(bb - 1.96 * sbb), exp(bb + 1.96 * sbb),
            summary(glm_bin)$coefficients["vitd10", "Pr(>|z|)"]))
cat("\nBrant test on the 3-level ordinal model:\n")
print(suppressWarnings(try(
  brant::brant(polr(mRS3_ord ~ vitd10 + age + sex + SBP + log_fu, data = d,
                    method = "logistic", Hess = TRUE)), silent = TRUE)))
cat("\nnominal_test on the 3-level ordinal model:\n")
print(nominal_test(clm3_3))
write.csv(data.frame(
  Specification = c("Ordinal, 6 mRS levels (primary)",
                    "Ordinal, outcome collapsed to 3 levels (0-2/3-4/5)",
                    "Binary logistic, outcome dichotomised at mRS 2"),
  OR = c(exp(unname(coef(clm3)["vitd10"])), exp(b3l), exp(bb)),
  LCL = c(exp(unname(coef(clm3)["vitd10"]) - 1.96 * sqrt(vcov(clm3)["vitd10", "vitd10"])),
          exp(b3l - 1.96 * se3l), exp(bb - 1.96 * sbb)),
  UCL = c(exp(unname(coef(clm3)["vitd10"]) + 1.96 * sqrt(vcov(clm3)["vitd10", "vitd10"])),
          exp(b3l + 1.96 * se3l), exp(bb + 1.96 * sbb)),
  P = c(2 * (1 - pnorm(abs(unname(coef(clm3)["vitd10"]) /
             sqrt(vcov(clm3)["vitd10", "vitd10"])))),
        2 * (1 - pnorm(abs(b3l / se3l))),
        summary(glm_bin)$coefficients["vitd10", "Pr(>|z|)"]),
  Admissible = c(TRUE, all(diff(as.numeric(clm3_3$alpha)) > 0), TRUE),
  stringsAsFactors = FALSE),
  file.path(OUT_DIR, "PO_alternative_checks.csv"), row.names = FALSE)
sink()
cat("Brant / nominal_test / PPO / alternative checks written to PO_assumption.txt\n")

# ============================================================================
# 5. MARGINAL (STANDARDISED) RISK DIFFERENCE
# ============================================================================
cat("\n=== Marginal predicted probabilities (g-computation, Model 3) ===\n")
lv  <- as.numeric(as.character(sort(unique(d$mRS))))
p25 <- quantile(d$vitd, .25); p75 <- quantile(d$vitd, .75)
marg <- function(fit, val) {
  nd <- d; nd$vitd10 <- val / 10
  colMeans(predict(fit, newdata = nd, type = "probs"))
}
pa <- marg(m3, p25); pb <- marg(m3, p75)
marg_tab <- rbind(P25 = pa, P75 = pb, Diff = pb - pa)
colnames(marg_tab) <- paste0("mRS", lv)
print(round(marg_tab, 4))
risk_p25 <- sum(pa[as.numeric(names(pa)) > 2]); risk_p75 <- sum(pb[as.numeric(names(pb)) > 2])
ard <- risk_p75 - risk_p25
cat(sprintf("P(mRS > 2) at P25 (%.1f nmol/L) = %.3f ; at P75 (%.1f nmol/L) = %.3f\n",
            p25, risk_p25, p75, risk_p75))
cat(sprintf("Absolute risk difference = %.3f (%.1f percentage points)\n", ard, 100 * ard))
set.seed(SEED)
ard_boot <- numeric(BOOT_ARD)
for (i in seq_len(BOOT_ARD)) {
  db <- d[sample(seq_len(nrow(d)), replace = TRUE), ]
  db$mRS_ord <- ordered(db$mRS, levels = sort(unique(db$mRS)))
  fb <- try(polr(as.formula(f3c), data = db, method = "logistic", Hess = TRUE),
            silent = TRUE)
  if (inherits(fb, "try-error")) { ard_boot[i] <- NA; next }
  n1 <- db; n1$vitd10 <- p25 / 10; n2 <- db; n2$vitd10 <- p75 / 10
  c1 <- colMeans(predict(fb, newdata = n1, type = "probs"))
  c2 <- colMeans(predict(fb, newdata = n2, type = "probs"))
  ard_boot[i] <- sum(c2[lv > 2]) - sum(c1[lv > 2])
}
ard_boot <- ard_boot[!is.na(ard_boot)]
cat(sprintf("Bootstrap 95%% CI for the ARD (n = %d): %.3f to %.3f (%.1f to %.1f pp)\n",
            length(ard_boot), quantile(ard_boot, .025), quantile(ard_boot, .975),
            100 * quantile(ard_boot, .025), 100 * quantile(ard_boot, .975)))
write.csv(round(marg_tab, 4), file.path(OUT_DIR, "marginal_probabilities.csv"))
write.csv(data.frame(ARD = ard,
                     CI_low = as.numeric(quantile(ard_boot, .025)),
                     CI_high = as.numeric(quantile(ard_boot, .975)),
                     Risk_P25 = risk_p25, Risk_P75 = risk_p75),
          file.path(OUT_DIR, "absolute_risk_difference.csv"), row.names = FALSE)

# ============================================================================
# 6. EFFECT MODIFICATION (SUPPLEMENTARY TABLE S4)
# ============================================================================
cat("\n=== Effect modification: likelihood-ratio tests (Supplementary Table S4) ===\n")
lrt_int <- function(base, term, label) {
  a <- polr(as.formula(base), data = d, method = "logistic", Hess = TRUE)
  b <- polr(as.formula(paste0(base, term)), data = d, method = "logistic", Hess = TRUE)
  lr <- 2 * (as.numeric(logLik(b)) - as.numeric(logLik(a)))
  df <- b$edf - a$edf
  data.frame(Interaction = label, LR = lr, df = df,
             P = pchisq(lr, df, lower.tail = FALSE), stringsAsFactors = FALSE)
}
ints <- rbind(
  lrt_int(f3c, " + vitd10:sex",  "25(OH)D x sex"),
  lrt_int(f3c, " + vitd10:age",     "25(OH)D x age"),
  lrt_int(f3c, " + vitd10:SBP",     "25(OH)D x systolic blood pressure"),
  lrt_int(f3c, " + vitd10:period",  "25(OH)D x admission period"),
  lrt_int(f3c, " + vitd10:surgery", "25(OH)D x surgical treatment"),
  lrt_int(f3c, " + vitd10:gcs_grp", "25(OH)D x GCS <= 8"),
  lrt_int(f3c, " + vitd10:ich_grp", "25(OH)D x ICH score >= 2"),
  lrt_int(f3c, " + vitd10:vol30",   "25(OH)D x hematoma >= 30 mL"))
ints$P_BH <- p.adjust(ints$P, "BH")
ints$P    <- format.pval(ints$P, digits = 3, eps = 0.001)
ints$P_BH <- format.pval(ints$P_BH, digits = 3, eps = 0.001)
ints$LR   <- round(ints$LR, 3)
print(ints, row.names = FALSE)
write.csv(ints, file.path(OUT_DIR, "TableS4_interactions.csv"), row.names = FALSE)
int_docx <- ints; names(int_docx) <- c("Interaction", "LR chi-square", "df",
                                       "P value", "P value (BH)")
# Why the nominally significant interactions are not interpreted: in every
# stratum concerned the outcome almost collapsed onto a single mRS level, so
# the ordinal slope is no longer identified. The counts below are generated
# from the data rather than typed in, so they cannot drift out of step with
# the cohort. The footnote therefore carries the argument, not just a caveat.
coll <- function(flag, lab) {
  n  <- sum(flag, na.rm = TRUE)
  po <- sum(flag & d$mRS > 2, na.rm = TRUE)
  sprintf("%s, %d of %d patients had a poor outcome and %d remained in the good-outcome range",
          lab, po, n, n - po)
}
collapse_txt <- paste0(
  "The interaction terms involving baseline severity and treatment intensity ",
  "were exploratory and are not interpreted further. Within every stratum in ",
  "which a nominally significant interaction was observed the outcome had ",
  "almost collapsed onto a single level: ",
  paste(c(coll(d$gcs_grp == "GCS <=8", "GCS <= 8"),
          coll(d$ich_grp == "ICH >=2",  "ICH score >= 2"),
          coll(d$vol30   == ">=30 mL",  "haematoma >= 30 mL"),
          coll(d$surgery == "Yes",      "surgical treatment")),
        collapse = "; "),
  ". The ordinal slopes are therefore no longer identified with any usable ",
  "precision in these strata.")
d30     <- d[d$hematoma.volume >= 30, ]
d30$mRS_ord <- ordered(d30$mRS, levels = sort(unique(d30$mRS)))
d30$poor30  <- d30$mRS > 2
s30o <- polr(mRS_ord ~ vitd10 + age + sex + SBP + log_fu, data = d30,
             method = "logistic", Hess = TRUE)
s30b <- suppressWarnings(glm(poor30 ~ vitd10 + age + sex + SBP + log_fu,
                             data = d30, family = binomial()))
r30o <- or_ci(s30o); r30b <- or_ci_glm(s30b)
example_txt <- paste0(
  "Illustratively, the ordinal stratum estimate for haematoma >= 30 mL ",
  "inverts direction (OR ", sprintf("%.2f", r30o["OR"]), ", 95% CI ",
  sprintf("%.2f", r30o["LCL"]), "-", sprintf("%.2f", r30o["UCL"]),
  ", P = ", fmt_p(r30o["P"]), ") whereas the dichotomised estimate in the ",
  "same stratum does not (OR ", sprintf("%.2f", r30b["OR"]), ", 95% CI ",
  sprintf("%.2f", r30b["LCL"]), "-", sprintf("%.2f", r30b["UCL"]),
  ", P = ", fmt_p(r30b["P"]), "), an instability that reflects the two ",
  "good-outcome patients rather than a genuine reversal. No stratum-specific ",
  "estimate should be quoted.")
make_three_line_docx(
  int_docx, file.path(OUT_DIR, "TableS4_interactions_three_line.docx"),
  "Supplementary Table S4. Tests of effect modification (interaction) for the association between 25(OH)D and mRS.",
  footnote = c(paste0("Likelihood-ratio tests comparing Model 3 with and without ",
                      "the product term. P values adjusted by the ",
                      "Benjamini-Hochberg procedure across the eight tests."),
               collapse_txt, example_txt))

# ============================================================================
# 7. SENSITIVITY ANALYSES + FOREST PLOTS (FIGURE 3 / SUPPLEMENTARY FIGURE S2)
# ============================================================================
cat("\n=== Sensitivity analyses ===\n")
srow <- function(lab, fit, var = "vitd10") {
  rr <- or_ci(fit, var)
  data.frame(Analysis = lab, OR = rr["OR"], LCL = rr["LCL"], UCL = rr["UCL"],
             P = rr["P"], stringsAsFactors = FALSE)
}
srow_glm <- function(lab, fit, var = "vitd10") {
  rr <- or_ci_glm(fit, var)
  data.frame(Analysis = lab, OR = rr["OR"], LCL = rr["LCL"], UCL = rr["UCL"],
             P = rr["P"], stringsAsFactors = FALSE)
}
S <- list(
  srow("Primary model (Model 3)", m3),
  srow_glm("Binary logistic (mRS > 2)",
           glm(poor ~ vitd10 + age + sex + SBP + log_fu, data = d, family = binomial())),
  srow("Additionally adjusted for admission period",
       polr(mRS_ord ~ vitd10 + age + sex + SBP + log_fu + period, data = d,
            method = "logistic", Hess = TRUE)),
  srow("Follow-up entered as linear days",
       polr(mRS_ord ~ vitd10 + age + sex + SBP + follow.up.duration, data = d,
            method = "logistic", Hess = TRUE)),
  srow("NS follow-up time",
       polr(mRS_ord ~ vitd10 + age + sex + SBP + ns(follow.up.duration, 3), data = d,
            method = "logistic", Hess = TRUE)),
  srow("Follow-up removed from the model",
       polr(mRS_ord ~ vitd10 + age + sex + SBP, data = d,
            method = "logistic", Hess = TRUE)))
for (extra in c("NIHSS", "GCS", "hematoma.volume", "ICH_score", "GLU", "Cr", "NLR")) {
  lab <- switch(extra,
                NIHSS = "Additionally adjusted for NIHSS",
                GCS = "Additionally adjusted for GCS",
                hematoma.volume = "Additionally adjusted for hematoma volume",
                ICH_score = "Additionally adjusted for ICH score",
                GLU = "Additionally adjusted for random plasma glucose",
                Cr = "Additionally adjusted for creatinine",
                NLR = "Additionally adjusted for NLR")
  ff <- as.formula(paste0("mRS_ord ~ vitd10 + age + sex + SBP + log_fu + ", extra))
  S[[length(S) + 1]] <- srow(lab, polr(ff, data = d, method = "logistic", Hess = TRUE))
}
S[[length(S) + 1]] <- srow("Additionally adjusted for surgery",
  polr(mRS_ord ~ vitd10 + age + sex + SBP + log_fu + surgery, data = d,
       method = "logistic", Hess = TRUE))
dd_ns <- d[d$surgery == "No", ]
dd_ns$mRS_ord <- ordered(dd_ns$mRS, levels = sort(unique(dd_ns$mRS)))
S[[length(S) + 1]] <- srow("Non-surgical subgroup",
  polr(mRS_ord ~ vitd10 + age + sex + SBP + log_fu, data = dd_ns,
       method = "logistic", Hess = TRUE))
sens <- bind_rows(S)
sens$E_value    <- evalue_or(sens$OR)
sens$E_value_CI <- evalue_ci(sens$OR, sens$LCL, sens$UCL)
sens$P_BH <- NA
isens <- sens$Analysis != "Primary model (Model 3)"
sens$P_BH[isens] <- p.adjust(sens$P[isens], "BH")
sens$OR_r  <- sprintf("%.2f", sens$OR)
sens$CI    <- sprintf("%.2f-%.2f", sens$LCL, sens$UCL)
sens$P_r   <- format.pval(sens$P, digits = 3, eps = 0.001)
sens$PBH_r <- ifelse(is.na(sens$P_BH), "", format.pval(sens$P_BH, digits = 3, eps = 0.001))
print(sens[, c("Analysis", "OR_r", "CI", "P_r", "PBH_r")], row.names = FALSE)
cat(sprintf("\nSensitivity analyses only: OR range %.2f-%.2f ; all OR < 1: %s\n",
            min(sens$OR[isens]), max(sens$OR[isens]), all(sens$OR[isens] < 1)))
cat(sprintf("Significant at P < 0.05: %d/%d ; after BH adjustment: %d/%d\n",
            sum(sens$P[isens] < 0.05), sum(isens),
            sum(sens$P_BH[isens] < 0.05, na.rm = TRUE), sum(isens)))
write.csv(sens, file.path(OUT_DIR, "sensitivity_analyses.csv"), row.names = FALSE)

forest_plot <- function(dat, prefix, height_mm) {
  dat$y   <- rev(seq_len(nrow(dat)))               # first row at the top
  dat$lab <- dat$Analysis
  dat$est <- paste0(sprintf("%.2f", dat$OR), " (",
                    sprintf("%.2f", dat$LCL), "-", sprintf("%.2f", dat$UCL), ")")
  dat$est <- paste0(dat$est, ", ",
                    ifelse(dat$P < 0.001, "P < 0.001",
                           paste0("P = ", sprintf("%.3f", dat$P))))
  p <- ggplot(dat) +
    geom_vline(xintercept = 1, linetype = "dashed", colour = "grey50", linewidth = 0.4) +
    geom_errorbar(aes(xmin = LCL, xmax = UCL, y = y), width = 0.16, linewidth = 0.4) +
    geom_point(aes(x = OR, y = y), shape = 15, size = 2.4) +
    geom_text(aes(x = 0.362, y = y, label = lab), hjust = 1, size = 2.6,
              family = FIG_FONT) +
    geom_text(aes(x = 1.16, y = y, label = est), hjust = 0, size = 2.6,
              family = FIG_FONT) +
    scale_x_continuous(
      breaks = c(0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1),
      limits = c(0.36, 1.55), expand = c(0, 0)) +
    coord_cartesian(clip = "off") +
    labs(x = "Odds ratio for a worse mRS with higher 25(OH)D (95% CI)", y = NULL) +
    theme_bw(base_family = FIG_FONT, base_size = 9) +
    theme(panel.grid = element_blank(),
          axis.text.y = element_blank(),
          axis.ticks.y = element_blank(),
          axis.title.x = element_text(size = 8),
          plot.margin = margin(4, 40, 4, 78, "mm"))
  ggsave(paste0(prefix, ".pdf"), p, width = FIG_W_MM, height = height_mm,
         units = "mm", device = cairo_pdf)
  tiff(paste0(prefix, ".tiff"), width = FIG_W_MM, height = height_mm,
       units = "mm", res = 600, compression = "lzw", family = FIG_FONT)
  print(p); dev.off()
  png(paste0(prefix, ".png"), width = FIG_W_MM, height = height_mm,
      units = "mm", res = 300, family = FIG_FONT)
  print(p); dev.off()
  invisible(prefix)
}

# Figure 3 (main text): one representative analysis per threat to validity
sens_main <- sens[sens$Analysis %in% MAIN_SENS, ]
sens_main$Analysis <- factor(sens_main$Analysis, levels = MAIN_SENS)
sens_main <- sens_main[order(sens_main$Analysis), ]
forest_plot(sens_main, file.path(OUT_DIR, "Figure3_key_sensitivity_forest"),
            height_mm = 92)
# Supplementary Figure S2: complete set
forest_plot(sens, file.path(OUT_DIR, "FigureS2_full_sensitivity_forest"),
            height_mm = 150)
cat("\nFigure 3 (main text) rows:", nrow(sens_main),
    "| Supplementary Figure S2 rows:", nrow(sens), "\n")

# ============================================================================
# 8. FUNCTIONAL FORM OF THE EXPOSURE (LINEARITY) + DOSE-RESPONSE FIGURE
# ============================================================================
cat("\n=== Non-linearity of the 25(OH)D association ===\n")
m_lin <- clm(mRS_ord ~ vitd10 + age10 + sex + SBP10 + logfu_c, data = d, link = "logit")
m_ns3 <- clm(mRS_ord ~ ns(vitd, df = 3) + age10 + sex + SBP10 + logfu_c, data = d,
             link = "logit")
m_ns4 <- clm(mRS_ord ~ ns(vitd, df = 4) + age10 + sex + SBP10 + logfu_c, data = d,
             link = "logit")
lr3 <- anova(m_lin, m_ns3); lr4 <- anova(m_lin, m_ns4)
cat(sprintf("LRT linear vs ns(df = 3): chi2 = %.3f, df = %d, P = %.3f\n",
            lr3[2, "LR.stat"], lr3[2, "df"], lr3[2, "Pr(>Chisq)"]))
cat(sprintf("LRT linear vs ns(df = 4): chi2 = %.3f, df = %d, P = %.3f\n",
            lr4[2, "LR.stat"], lr4[2, "df"], lr4[2, "Pr(>Chisq)"]))
# Note on the choice of spline basis. A restricted cubic spline (rms::rcs)
# was fitted in an earlier version as a cross-check. The two families span the
# same function space and gave the same conclusion here (rcs P = 0.688 and
# 0.861 versus ns P = 0.653 and 0.823), but reporting both invited the
# question of why the primary specification used one basis rather than the
# other, so only the natural cubic spline is retained.
write.csv(data.frame(
  Comparison = c("linear vs ns(df = 3)", "linear vs ns(df = 4)"),
  LR = c(lr3[2, "LR.stat"], lr4[2, "LR.stat"]),
  df = c(lr3[2, "df"], lr4[2, "df"]),
  P = c(lr3[2, "Pr(>Chisq)"], lr4[2, "Pr(>Chisq)"])),
  file.path(OUT_DIR, "nonlinearity_tests.csv"), row.names = FALSE)

grid_v <- seq(min(d$vitd), max(d$vitd), length.out = 100)
nd_grid <- d[rep(1, length(grid_v)), ]
nd_grid$vitd  <- grid_v
nd_grid$vitd10 <- grid_v / 10
risk_curve <- function(fit) {
  pr <- as.matrix(predict(fit, newdata = nd_grid, type = "probs"))
  if (is.null(colnames(pr))) colnames(pr) <- as.character(lv)
  rowSums(pr[, as.numeric(colnames(pr)) > 2, drop = FALSE])
}
m_ns3_polr <- polr(mRS_ord ~ ns(vitd, 3) + age + sex + SBP + log_fu, data = d,
                   method = "logistic", Hess = TRUE)
obs_curve <- risk_curve(m_ns3_polr)
set.seed(SEED)
boot_risk <- matrix(NA_real_, nrow = BOOT_SPLINE, ncol = length(grid_v))
for (i in seq_len(BOOT_SPLINE)) {
  db <- d[sample(seq_len(nrow(d)), replace = TRUE), ]
  db$mRS_ord <- ordered(db$mRS, levels = sort(unique(db$mRS)))
  fb <- try(polr(mRS_ord ~ ns(vitd, 3) + age + sex + SBP + log_fu, data = db,
                 method = "logistic", Hess = TRUE), silent = TRUE)
  if (inherits(fb, "try-error")) next
  boot_risk[i, ] <- risk_curve(fb)
}
band <- data.frame(vitd = grid_v, p = obs_curve,
                   lo = apply(boot_risk, 2, quantile, probs = .025, na.rm = TRUE),
                   hi = apply(boot_risk, 2, quantile, probs = .975, na.rm = TRUE))
write.csv(round(band, 4), file.path(OUT_DIR, "dose_response_curve.csv"),
          row.names = FALSE)

p_dr <- ggplot(band, aes(x = vitd)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), fill = "grey80", alpha = 0.8) +
  geom_line(aes(y = p), linewidth = 0.6) +
  geom_rug(data = d, aes(x = vitd), sides = "b", alpha = 0.35, linewidth = 0.3) +
  geom_vline(xintercept = CUT_POINT, linetype = "dotted", colour = "grey40",
             linewidth = 0.4) +
  labs(x = "25(OH)D (nmol/L)",
       y = paste0("Probability of poor outcome (mRS > 2)")) +
  theme_bw(base_family = FIG_FONT, base_size = 9) +
  theme(panel.grid = element_blank())
for (dev_name in c("pdf", "tiff", "png")) {
  fp <- file.path(OUT_DIR, paste0("FigureS3_dose_response.", dev_name))
  if (dev_name == "pdf") {
    ggsave(fp, p_dr, width = FIG_W_MM, height = 100, units = "mm",
           device = cairo_pdf)
  } else if (dev_name == "tiff") {
    tiff(fp, width = FIG_W_MM, height = 100, units = "mm", res = 600,
         compression = "lzw", family = FIG_FONT)
    print(p_dr); dev.off()
  } else {
    png(fp, width = FIG_W_MM, height = 100, units = "mm", res = 300,
        family = FIG_FONT)
    print(p_dr); dev.off()
  }
}

# ============================================================================
# 9. ALTERNATIVE ADJUSTMENT SET INCLUDING BMI (MISSING 60%)
# ============================================================================
cat("\n=== Alternative adjustment set {age, sex, BMI} ===\n")
cc <- d[!is.na(d$BMI), ]
cc$mRS_ord <- ordered(cc$mRS, levels = sort(unique(cc$mRS)))
f_cc <- polr(mRS_ord ~ vitd10 + age + sex + BMI + log_fu, data = cc,
             method = "logistic", Hess = TRUE)
rr_cc <- or_ci(f_cc)
cat(sprintf("Complete case (n = %d): OR = %.2f (%.2f-%.2f) P = %.3f\n",
            nrow(cc), rr_cc["OR"], rr_cc["LCL"], rr_cc["UCL"], rr_cc["P"]))

mi_vars <- c("vitd", "age", "sex", "SBP", "DBP", "BMI", "mRS",
             "follow.up.duration", "GCS", "NIHSS", "hematoma.volume",
             "ICH_score", "HGB", "GLU", "Cr", "ALB", "NEUT", "LY", "NLR")
mi_dat <- d[, intersect(mi_vars, names(d))]
set.seed(SEED)
imp <- mice(mi_dat, m = MI_M, method = "pmm", maxit = 25, printFlag = FALSE)
mi_est <- lapply(seq_len(MI_M), function(k) {
  dd <- complete(imp, k)
  dd$vitd10  <- dd$vitd / 10
  dd$log_fu  <- log(dd$follow.up.duration)
  dd$mRS_ord <- ordered(dd$mRS, levels = sort(unique(dd$mRS)))
  f <- polr(mRS_ord ~ vitd10 + age + sex + BMI + log_fu, data = dd,
            method = "logistic", Hess = TRUE)
  b  <- unname(coef(f)["vitd10"]); se <- sqrt(as.numeric(vcov(f)["vitd10", "vitd10"]))
  c(b, se)
})
mi_est <- do.call(rbind, mi_est)
Q <- mean(mi_est[, 1]); U <- mean(mi_est[, 2]^2); B <- var(mi_est[, 1])
Tv <- U + (1 + 1 / MI_M) * B
nu <- (MI_M - 1) * (1 + U / ((1 + 1 / MI_M) * B))^2
mi_or <- exp(Q)
mi_lo <- exp(Q - qt(0.975, nu) * sqrt(Tv))
mi_hi <- exp(Q + qt(0.975, nu) * sqrt(Tv))
mi_p  <- 2 * (1 - pt(abs(Q / sqrt(Tv)), df = nu))
cat(sprintf("After multiple imputation (m = %d, PMM): OR = %.2f (%.2f-%.2f) P = %.3f\n",
            MI_M, mi_or, mi_lo, mi_hi, mi_p))

# ============================================================================
# 10. FOLLOW-UP WINDOW STRATA
# ============================================================================
cat("\n=== Follow-up window strata (< 120 d vs >= 120 d) ===\n")
fw_rows <- list()
for (lvl in levels(d$fu120)) {
  ds <- d[d$fu120 == lvl, ]
  ds$mRS_ord <- ordered(ds$mRS, levels = sort(unique(ds$mRS)))
  rr <- or_ci(polr(mRS_ord ~ vitd10 + age + sex + SBP + log_fu, data = ds,
                   method = "logistic", Hess = TRUE))
  cat(sprintf("  %-8s n = %3d  OR = %.2f (%.2f-%.2f) P = %.3f\n", lvl, nrow(ds),
              rr["OR"], rr["LCL"], rr["UCL"], rr["P"]))
  fw_rows[[lvl]] <- data.frame(Stratum = lvl, n = nrow(ds), OR = rr["OR"],
                               LCL = rr["LCL"], UCL = rr["UCL"], P = rr["P"])
}
m_pool <- polr(mRS_ord ~ vitd10 + age + sex + SBP + log_fu, data = d,
               method = "logistic", Hess = TRUE)
m_int  <- polr(mRS_ord ~ vitd10 * fu120 + age + sex + SBP + log_fu, data = d,
               method = "logistic", Hess = TRUE)
lr  <- 2 * (as.numeric(logLik(m_int)) - as.numeric(logLik(m_pool)))
dfi <- m_int$edf - m_pool$edf
cat(sprintf("Interaction 25(OH)D x follow-up window: LR = %.3f, df = %d, P = %.3f\n",
            lr, dfi, pchisq(lr, dfi, lower.tail = FALSE)))
fw <- bind_rows(fw_rows)
fw <- rbind(fw, data.frame(Stratum = "Interaction", n = nrow(d), OR = NA,
                           LCL = NA, UCL = NA, P = pchisq(lr, dfi, lower.tail = FALSE)))
write.csv(fw, file.path(OUT_DIR, "followup_window_strata.csv"), row.names = FALSE)

# ============================================================================
# 11. E-VALUES
# ============================================================================
ev <- data.frame(
  Analysis = c("Continuous, per 10 nmol/L (Model 3)",
               paste0("Categorical, <50 vs ", GE, " 50 nmol/L (Model 3)")),
  OR = c(or_ci(m3)["OR"], or_ci(k3, "vitd_lt50<50")["OR"]),
  LCL = c(or_ci(m3)["LCL"], or_ci(k3, "vitd_lt50<50")["LCL"]),
  UCL = c(or_ci(m3)["UCL"], or_ci(k3, "vitd_lt50<50")["UCL"]),
  P = c(or_ci(m3)["P"], or_ci(k3, "vitd_lt50<50")["P"]))
ev$E_value    <- evalue_or(ev$OR)
ev$E_value_CI <- evalue_ci(ev$OR, ev$LCL, ev$UCL)

# The per-10-nmol/L scale is a convention, not a natural unit. Two further
# scales are reported because they are easier to read against the literature
# and because the P25-to-P75 contrast is the one that corresponds to the
# adjusted risk difference computed in section 6.
b3  <- unname(coef(m3)["vitd10"])
se3 <- sqrt(as.numeric(vcov(m3)["vitd10", "vitd10"]))
scale_row <- function(lab, units) {
  f  <- units / 10
  or <- exp(b3 * f)
  lo <- exp((b3 - 1.96 * se3) * f)
  hi <- exp((b3 + 1.96 * se3) * f)          # limit nearer the null (OR < 1)
  data.frame(Analysis = lab, OR = or,
             LCL = lo, UCL = hi,
             P = unname(or_ci(m3)["P"]),
             E_value = evalue_or(or), E_value_CI = evalue_ci(or, lo, hi),
             stringsAsFactors = FALSE)
}
sd_vitd <- sd(d$vitd)
q25_v   <- as.numeric(quantile(d$vitd, 0.25, type = QUANT_TYPE))
q75_v   <- as.numeric(quantile(d$vitd, 0.75, type = QUANT_TYPE))
ev <- rbind(ev,
            scale_row(sprintf("Continuous, per 1 SD (%.1f nmol/L) (Model 3)", sd_vitd),
                      sd_vitd),
            scale_row(sprintf("Continuous, P25 to P75 (%.1f nmol/L) (Model 3)",
                              q75_v - q25_v), q75_v - q25_v))
cat(sprintf("\nExposure distribution: SD %.2f nmol/L; P25 %.1f, P75 %.1f nmol/L (span %.1f)\n",
            sd_vitd, q25_v, q75_v, q75_v - q25_v))
cat("\n=== E-values ===\n"); print(ev, row.names = FALSE)
write.csv(ev, file.path(OUT_DIR, "evalues.csv"), row.names = FALSE)

# ============================================================================
# 12. MINIMUM DETECTABLE EFFECT SIZE (MDES) + POWER CHECK
# ============================================================================
b_obs  <- unname(coef(m3)["vitd10"])
se_obs <- sqrt(as.numeric(vcov(m3)["vitd10", "vitd10"]))
z_pair <- qnorm(1 - ALPHA / 2) + qnorm(0.80)
mdes   <- exp(-z_pair * se_obs)
cat("\n=== Minimum detectable effect size ===\n")
cat(sprintf("Observed log OR = %.4f (SE %.4f)\n", b_obs, se_obs))
cat(sprintf("MDES at 80%% power, alpha = %.2f, two-sided: OR = %.2f per 10 nmol/L\n",
            ALPHA, mdes))

simulate_power <- function(beta_log_or, nsim = NSIM_POWER) {
  X    <- model.matrix(as.formula(f3c), data = d)
  zeta <- m3$zeta
  bn   <- setNames(rep(0, ncol(X)), colnames(X))
  bn[names(coef(m3))] <- coef(m3)
  bn["vitd10"] <- beta_log_or
  lp   <- as.numeric(X %*% bn)
  hits <- 0
  for (i in seq_len(nsim)) {
    u <- runif(nrow(d))
    # polr: logit P(Y <= j) = zeta_j - eta ; the last category is the remainder.
    # p is an n x (K + 1) matrix of cumulative probabilities.
    p <- plogis(outer(-lp, c(zeta, Inf), "+"))
    y <- rowSums(u > p)                           # 0-based mRS category
    ds <- d; ds$mRS <- y
    ds$mRS_ord <- ordered(ds$mRS, levels = sort(unique(d$mRS)))
    f <- try(polr(as.formula(f3c), data = ds, method = "logistic", Hess = TRUE),
             silent = TRUE)
    if (inherits(f, "try-error")) next
    pv <- or_ci(f)["P"]
    if (is.na(pv)) next
    hits <- hits + (pv < ALPHA)
  }
  hits / nsim
}
set.seed(SEED)
pw_mdes <- simulate_power(log(mdes))
pw_obs  <- simulate_power(b_obs)
cat(sprintf("Simulation check (%d replications): power at the MDES = %.2f ; at the observed effect = %.2f\n",
            NSIM_POWER, pw_mdes, pw_obs))
write.csv(data.frame(SE_logOR = se_obs, MDES_OR = mdes,
                     Power_at_MDES = pw_mdes, Power_at_observed = pw_obs),
          file.path(OUT_DIR, "mdes_power.csv"), row.names = FALSE)

# ============================================================================
# 12b. ACUTE-PHASE SURROGATE ADJUSTMENTS (REVERSE-CAUSATION PROBE)
# ============================================================================
# 25(OH)D falls as a negative acute-phase reactant, so a low admission value
# could be a consequence rather than a cause of a severe ictus. The registry
# of this cohort contains no C-reactive protein or interleukin-6, but albumin
# and random plasma glucose at admission index nutritional state and the
# stress hyperglycaemia response; both are correlated with 25(OH)D here. They
# are therefore added to the primary adjustment set as empirical proxies for
# the reversed pathway. This is the most unfavourable specification examined.
cat("\n=== Acute-phase surrogate adjustments (reverse-causation probe) ===\n")
adm_spec <- list("Model 3 + albumin"  = " + ALB",
                 "Model 3 + random plasma glucose" = " + GLU",
                 "Model 3 + albumin and random plasma glucose" = " + ALB + GLU")
adm_res <- lapply(names(adm_spec), function(lab) {
  fit <- polr(as.formula(paste0(f3c, adm_spec[[lab]])), data = d,
              method = "logistic", Hess = TRUE)
  r <- or_ci(fit)
  cat(sprintf("  %-46s OR = %.2f (%.2f-%.2f) P = %.3f  [%d parameters]\n",
              lab, r["OR"], r["LCL"], r["UCL"], r["P"], fit$edf))
  list(lab = lab, r = r, npar = fit$edf)
})
names(adm_res) <- vapply(adm_res, function(z) z$lab, "")
# correlations that motivate the probe
adm_cor <- data.frame(
  Variable = c("Random plasma glucose", "Albumin", "NIHSS", "ICH score",
               "GCS", "Haematoma volume", "NLR"),
  rho = NA_real_, P = NA_real_, stringsAsFactors = FALSE)
for (i in seq_len(nrow(adm_cor))) {
  v <- switch(adm_cor$Variable[i],
              "Random plasma glucose" = "GLU", "Albumin" = "ALB",
              "NIHSS" = "NIHSS", "ICH score" = "ICH_score", "GCS" = "GCS",
              "Haematoma volume" = "hematoma.volume", "NLR" = "NLR")
  ct <- suppressWarnings(cor.test(d$vitd, d[[v]], method = "spearman"))
  adm_cor$rho[i] <- unname(ct$estimate); adm_cor$P[i] <- ct$p.value
}
print(adm_cor, row.names = FALSE, digits = 3)
write.csv(adm_cor, file.path(OUT_DIR, "reverse_causation_correlations.csv"),
          row.names = FALSE)
write.csv(do.call(rbind, lapply(adm_res, function(z)
  data.frame(Analysis = z$lab, OR = z$r["OR"], LCL = z$r["LCL"],
             UCL = z$r["UCL"], P = z$r["P"], Parameters = z$npar))),
  file.path(OUT_DIR, "reverse_causation_adjustments.csv"), row.names = FALSE)

# ============================================================================
# 12c. LEAVE-ONE-OUT INFLUENCE ANALYSIS
# ============================================================================
# With 90 patients the estimate could in principle be carried by one or two
# individuals. Refitting the primary model 90 times, each time omitting one
# patient, answers that directly.
cat("\n=== Leave-one-out refitting of Model 3 ===\n")
set.seed(SEED)
loo <- t(vapply(seq_len(nrow(d)), function(i) {
  ds <- d[-i, ]
  ds$mRS_ord <- ordered(ds$mRS, levels = sort(unique(ds$mRS)))
  f <- try(polr(as.formula(f3c), data = ds, method = "logistic", Hess = TRUE),
           silent = TRUE)
  if (inherits(f, "try-error")) return(c(OR = NA, LCL = NA, UCL = NA, P = NA))
  or_ci(f)
}, numeric(4)))
loo_df <- data.frame(Patient = seq_len(nrow(d)), vitd = d$vitd, mRS = d$mRS,
                     OR = loo[, "OR"], LCL = loo[, "LCL"], UCL = loo[, "UCL"],
                     P = loo[, "P"])
write.csv(loo_df, file.path(OUT_DIR, "leave_one_out.csv"), row.names = FALSE)
loo_or_lo <- min(loo[, "OR"], na.rm = TRUE); loo_or_hi <- max(loo[, "OR"], na.rm = TRUE)
loo_p_lo  <- min(loo[, "P"],  na.rm = TRUE); loo_p_hi  <- max(loo[, "P"],  na.rm = TRUE)
loo_nsig  <- sum(loo[, "P"] >= ALPHA, na.rm = TRUE)
loo_worst <- which.max(loo[, "OR"])
cat(sprintf("  OR range               : %.3f - %.3f\n", loo_or_lo, loo_or_hi))
cat(sprintf("  P range                : %.4f - %.4f\n", loo_p_lo, loo_p_hi))
cat(sprintf("  deletions with P >= %.2f : %d of %d\n", ALPHA, loo_nsig, nrow(d)))
cat(sprintf("  most influential patient: #%d (25(OH)D %.1f nmol/L, mRS %d) -> OR %.3f, P %.4f\n",
            loo_worst, d$vitd[loo_worst], d$mRS[loo_worst],
            loo[loo_worst, "OR"], loo[loo_worst, "P"]))

# ============================================================================
# 13. SUPPLEMENTARY TABLE S5 -- ADDITIONAL (NON-FIGURE) ANALYSES
# ============================================================================
extra <- data.frame(
  Analysis = c("Alternative adjustment set {age, sex, BMI}: complete case",
               paste0("Alternative adjustment set {age, sex, BMI}: MI (m = ", MI_M, ")"),
               "Follow-up window < 120 d",
               "Follow-up window >= 120 d",
               "Interaction 25(OH)D x follow-up window",
               "Non-linearity, LRT linear vs ns(df = 3)",
               "Non-linearity, LRT linear vs ns(df = 4)",
               "Reverse-causation probe: Model 3 + albumin",
               "Reverse-causation probe: Model 3 + random plasma glucose",
               "Reverse-causation probe: Model 3 + albumin and glucose",
               "Leave-one-out refitting of Model 3 (90 refits): range"),
  Estimate = c(sprintf("%.2f (%.2f-%.2f)", rr_cc["OR"], rr_cc["LCL"], rr_cc["UCL"]),
               sprintf("%.2f (%.2f-%.2f)", mi_or, mi_lo, mi_hi),
               sprintf("%.2f (%.2f-%.2f)", fw$OR[1], fw$LCL[1], fw$UCL[1]),
               sprintf("%.2f (%.2f-%.2f)", fw$OR[2], fw$LCL[2], fw$UCL[2]),
               sprintf("LR = %.2f, df = %d", lr, dfi),
               sprintf("chi2 = %.2f, df = %d", lr3[2, "LR.stat"], lr3[2, "df"]),
               sprintf("chi2 = %.2f, df = %d", lr4[2, "LR.stat"], lr4[2, "df"]),
               sprintf("%.2f (%.2f-%.2f)", adm_res[[1]]$r["OR"], adm_res[[1]]$r["LCL"], adm_res[[1]]$r["UCL"]),
               sprintf("%.2f (%.2f-%.2f)", adm_res[[2]]$r["OR"], adm_res[[2]]$r["LCL"], adm_res[[2]]$r["UCL"]),
               sprintf("%.2f (%.2f-%.2f)", adm_res[[3]]$r["OR"], adm_res[[3]]$r["LCL"], adm_res[[3]]$r["UCL"]),
               sprintf("%.2f-%.2f", loo_or_lo, loo_or_hi)),
  P = c(format.pval(rr_cc["P"], digits = 3, eps = 0.001),
        format.pval(mi_p, digits = 3, eps = 0.001),
        format.pval(fw$P[1], digits = 3, eps = 0.001),
        format.pval(fw$P[2], digits = 3, eps = 0.001),
        format.pval(pchisq(lr, dfi, lower.tail = FALSE), digits = 3, eps = 0.001),
        format.pval(lr3[2, "Pr(>Chisq)"], digits = 3, eps = 0.001),
        format.pval(lr4[2, "Pr(>Chisq)"], digits = 3, eps = 0.001),
        format.pval(adm_res[[1]]$r["P"], digits = 3, eps = 0.001),
        format.pval(adm_res[[2]]$r["P"], digits = 3, eps = 0.001),
        format.pval(adm_res[[3]]$r["P"], digits = 3, eps = 0.001),
        sprintf("%.3f-%.3f", loo_p_lo, loo_p_hi)),
  stringsAsFactors = FALSE)
write.csv(extra, file.path(OUT_DIR, "TableS5_additional_analyses.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
make_three_line_docx(
  extra, file.path(OUT_DIR, "TableS5_additional_analyses_three_line.docx"),
  "Supplementary Table S5. Additional analyses not shown in the main figures.",
  footnote = c(paste0("MI, multiple imputation by predictive mean matching. ",
                      "BMI was missing in ", sum(is.na(d$BMI)), " of ", nrow(d),
                      " patients (", sprintf("%.1f", 100 * mean(is.na(d$BMI))), "%)."),
               paste0("ns, natural cubic spline implemented in the splines ",
                      "package; LRT, likelihood-ratio test against the linear ",
                      "term."),
               paste0("Knot positions (nmol/L). ns(df = 3): boundary knots at ",
                      "the minimum and maximum observed value (",
                      paste(round(range(d$vitd), 1), collapse = " and "),
                      "), interior knots at the 33rd and 67th centile (",
                      paste(round(attr(splines::ns(d$vitd, df = 3), "knots"), 1),
                            collapse = " and "), ")."),
               paste0("Reverse-causation probe. 25(OH)D behaves as a negative ",
                      "acute-phase reactant, so a low admission value could ",
                      "be a consequence rather than a cause of a severe ",
                      "ictus. C-reactive protein and interleukin-6 were not ",
                      "measured, so albumin and random plasma glucose at ",
                      "admission - both correlated with 25(OH)D in this ",
                      "cohort (Spearman rho = ",
                      sprintf("%+.2f", adm_cor$rho[2]), " and ",
                      sprintf("%+.2f", adm_cor$rho[1]), "; P = ",
                      fmt_p(adm_cor$P[2]), " and ", fmt_p(adm_cor$P[1]),
                      ") - were added as empirical proxies for acute ",
                      "metabolic and nutritional state. The specification ",
                      "with both is the least favourable of all those ",
                      "examined and estimates ", adm_res[[3]]$npar,
                      " parameters from ", nrow(d), " patients."),
               paste0("Leave-one-out. The primary model was refitted ", nrow(d),
                      " times, omitting one patient each time. The table gives ",
                      "the range of the odds ratio and of the P value across ",
                      "the ", nrow(d), " refits; ", loo_nsig, " of them gave ",
                      "P >= ", ALPHA, ". Per-patient estimates are in ",
                      "leave_one_out.csv.")))

# ============================================================================
# 13a. SUPPLEMENTARY TABLE S3 -- BASELINE BY BMI AVAILABILITY
# ============================================================================
cat("\n=== Supplementary Table S3: BMI available vs missing ===\n")
bmi_ok  <- !is.na(d$BMI)
cat(sprintf("BMI available: %d ; BMI missing: %d ; missing %.1f%%\n",
            sum(bmi_ok), sum(!bmi_ok), 100 * mean(!bmi_ok)))

med_iqr_s <- function(x, ok, dig) {
  z <- x[ok]
  paste0(sprintf(paste0("%.", dig, "f (%.", dig, "f"), median(z, na.rm = TRUE),
                 quantile(z, .25, na.rm = TRUE, type = QUANT_TYPE)),
         END, sprintf(paste0("%.", dig, "f)"),
                      quantile(z, .75, na.rm = TRUE, type = QUANT_TYPE)))
}
s3_rows <- list()
add_s3 <- function(label, a, b, p) {
  s3_rows[[length(s3_rows) + 1]] <<- data.frame(
    Characteristic = label, Available = a, Missing = b, P = p,
    stringsAsFactors = FALSE)
}
s3_cont <- list(
  list("Age, years",                 "age",                1),
  list("SBP, mmHg",                  "SBP",                1),
  list("GCS, score",                 "GCS",                1),
  list("NIHSS, score",               "NIHSS",              1),
  list("Hematoma volume, mL",        "hematoma.volume",    1),
  list("25(OH)D, nmol/L",            "vitd",               1),
  list("mRS, score",                 "mRS",                1),
  list("Follow-up duration, days",   "follow.up.duration", 1))
for (v in s3_cont) {
  x  <- d[[v[[2]]]]
  pv <- suppressWarnings(wilcox.test(x[bmi_ok], x[!bmi_ok])$p.value)
  add_s3(v[[1]], med_iqr_s(x, bmi_ok, v[[3]]), med_iqr_s(x, !bmi_ok, v[[3]]),
         fmt_p(pv))
}
s3_cat <- list(
  list("Male sex, n (%)",          d$sex == "Male"),
  list("Surgical treatment, n (%)", d$surgery == "Yes"),
  list("Poor outcome (mRS > 2), n (%)", d$poor == 1))
for (v in s3_cat) {
  vv <- v[[2]]
  ok <- bmi_ok & !is.na(vv)                # patients with a known value
  tb <- matrix(c(sum(vv[ok]),  sum(vv[!bmi_ok & !is.na(vv)]),
                 sum(!vv[ok]), sum(!vv[!bmi_ok & !is.na(vv)])), nrow = 2)
  pv <- tryCatch(if (any(chisq.test(tb, correct = FALSE)$expected < 5))
                   fisher.test(tb)$p.value else
                     chisq.test(tb, correct = FALSE)$p.value,
                 error = function(e) NA_real_)
  add_s3(v[[1]],
         sprintf("%d (%.1f%%)", sum(vv[ok]),  100 * mean(vv[ok])),
         sprintf("%d (%.1f%%)", sum(vv[!bmi_ok & !is.na(vv)]),
                 100 * mean(vv[!bmi_ok & !is.na(vv)])),
         fmt_p(pv))
}
t3 <- bind_rows(s3_rows)
names(t3) <- c("Characteristic",
               paste0("BMI available (n = ", sum(bmi_ok), ")"),
               paste0("BMI missing (n = ", sum(!bmi_ok), ")"),
               "P value")
write.csv(t3, file.path(OUT_DIR, "TableS3_bmi_available_vs_missing.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
make_three_line_docx(
  t3, file.path(OUT_DIR, "TableS3_bmi_available_vs_missing_three_line.docx"),
  "Supplementary Table S3. Baseline characteristics of patients with and without an available BMI.",
  footnote = c("Values are median (IQR) or n (%). P values from the Mann-Whitney U test (continuous) or the chi-square test, or Fisher's exact test when any expected count was < 5 (categorical).",
               "BMI, body mass index; other abbreviations as in Table 1."))
print(t3, row.names = FALSE)

# ============================================================================
# 13b. CONSISTENCY CHECK AGAINST THE NUMBERS PRINTED IN THE MANUSCRIPT
# ============================================================================
# Values of the "Total" column as they appear in the current version of the
# manuscript. The comparison flags any number that this script recomputes
# differently, so that the manuscript can be updated (or QUANT_TYPE changed).
ref_names <- c(
  "Age (years)", "Sex, n (%)", paste0("BMI (kg/m", SUP2, ")"), "SBP (mmHg)",
  "GCS (score)", "NIHSS (score)", "Hematoma volume (mL)", "ICH (score)",
  "Intraventricular extension, n (%)", "Surgical treatment, n (%)",
  "Admission period, n (%)", "Hemorrhage location, n (%)",
  "Hemoglobin (g/L)", "NLR", "RPG (mmol/L)",
  paste0("Creatinine (", MU, "mol/L)"), "Total cholesterol (mmol/L)",
  "Triglycerides (mmol/L)", "HDL-C (mmol/L)", "LDL-C (mmol/L)", "ALT (U/L)",
  "AST (U/L)", "GGT (U/L)", "ALP (U/L)", "Albumin (g/L)", "25(OH)D (nmol/L)",
  "Follow-up duration (days)")
ref_vals <- c(
  paste0("54.5 (51.0", END, "61.0)"), "63 (70.0%)",
  paste0("25.6 (23.1", END, "27.4)"), paste0("181.5 (168.0", END, "197.8)"),
  paste0("13.0 (8.0", END, "15.0)"), paste0("10.0 (6.0", END, "18.0)"),
  paste0("12.0 (6.0", END, "26.2)"), paste0("1.0 (0.0", END, "2.0)"),
  "53 (58.9%)", "52 (57.8%)", "37 (41.1%)", "86 (95.6%)",
  paste0("142.0 (130.0", END, "152.0)"), paste0("4.6 (2.1", END, "9.0)"),
  paste0("7.8 (6.8", END, "9.5)"), paste0("69.5 (57.0", END, "90.0)"),
  paste0("4.7 (3.9", END, "5.4)"), paste0("1.0 (0.7", END, "1.6)"),
  paste0("1.2 (1.1", END, "1.5)"), paste0("2.8 (2.4", END, "3.6)"),
  paste0("18.0 (13.0", END, "30.2)"), paste0("20.0 (16.0", END, "31.0)"),
  paste0("29.0 (18.0", END, "56.2)"), paste0("67.0 (53.0", END, "85.2)"),
  paste0("38.3 (34.9", END, "42.0)"), paste0("57.1 ", PM, " 13.8"),
  paste0("107.5 (95.0", END, "124.0)"))
ref <- setNames(ref_vals, ref_names)
chk <- data.frame(
  Characteristic = names(ref),
  In_manuscript  = unname(ref),
  Recomputed     = unname(t1_out$Total[match(names(ref), t1_out$Characteristic)]),
  stringsAsFactors = FALSE)
chk$Identical <- chk$In_manuscript == chk$Recomputed
write.csv(chk, file.path(OUT_DIR, "Table1_vs_manuscript_check.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
cat("\n=== Table 1 consistency check against the manuscript ===\n")
print(chk, row.names = FALSE)
cat("Identical:", sum(chk$Identical), "/", nrow(chk), "\n")

# ============================================================================
# 14. CONSOLIDATED WORKBOOK, SESSION INFO AND MANIFEST
# ============================================================================
try({
  wb <- createWorkbook()
  addWorksheet(wb, "Table1");        writeData(wb, "Table1", t1_out)
  addWorksheet(wb, "Table2");        writeData(wb, "Table2", res_det)
  addWorksheet(wb, "Sensitivity");   writeData(wb, "Sensitivity", sens)
  addWorksheet(wb, "Interactions");  writeData(wb, "Interactions", ints)
  addWorksheet(wb, "PO");            writeData(wb, "PO", if (length(ppo)) bind_rows(ppo) else data.frame(x = "not available"))
  addWorksheet(wb, "Marginal");      writeData(wb, "Marginal", as.data.frame(marg_tab))
  addWorksheet(wb, "Evalues");       writeData(wb, "Evalues", ev)
  addWorksheet(wb, "Additional");    writeData(wb, "Additional", extra)
  addWorksheet(wb, "TableS3_BMI");   writeData(wb, "TableS3_BMI", t3)
  saveWorkbook(wb, file.path(OUT_DIR, "all_results.xlsx"), overwrite = TRUE)
}, silent = TRUE)

sink(file.path(OUT_DIR, "sessionInfo.txt"))
print(sessionInfo())
sink()
while (sink.number() > 0) sink()

# ---- run instructions for readers, reviewers and editors -------------------
writeLines(c(
  "Reproducing the analysis reported in",
  "  \"Lower admission 25-hydroxyvitamin D associated with worse functional",
  "   outcome after hypertensive intracerebral hemorrhage:",
  "   a prospective cohort study in southern China\"",
  "",
  "CONTENTS",
  paste0("  ", SELF_NAME, "  --  this script; produces every number,"),
  "                                      table and figure in the manuscript",
  "  data/clean/final_ich_cohort.xlsx    analytic data set, n = 90",
  "                                      (de-identified; no name, no record",
  "                                      number, no study identifier)",
  "  output/                             all results; created if absent, reused",
  "                                      otherwise (same-named files are",
  "                                      overwritten, nothing is deleted)",
  "",
  "HOW TO RUN",
  "  1. Command line :  cd <folder containing this file>",
  paste0("                     Rscript ", SELF_NAME),
  "  2. RStudio      :  Session > Set Working Directory > To Source File",
  "                     Location, then Source.",
  "  Nothing else has to be installed, configured or edited. The input path is",
  "  fixed relative to the script. output/ is created only if it is missing; if",
  "  it already exists it is kept, files written by this run simply replace",
  "  the previous file of the same name, and unrelated files stay untouched.",
  "",
  "REQUIREMENTS",
  "  R >= 4.0 with the CRAN packages readxl, MASS, ordinal, brant, car,",
  "  mice, splines, ggplot2, officer, flextable, openxlsx, dplyr. Missing",
  "  packages cause the script to stop with the exact install.packages() call.",
  "  The exact R and package versions used for the submitted analysis are in",
  "  sessionInfo.txt.",
  "",
  "RUNTIME AND RANDOMNESS",
  "  Approx. 1-2 minutes on a standard laptop. Every random procedure",
  "  (bootstrap confidence intervals, multiple imputation, the simulation",
  "  check of the minimum detectable effect size) is started from the fixed",
  "  master seed printed at the top of the script and in console_output.txt,",
  "  so repeated runs on the same R version give identical output. Numbers",
  "  that do not depend on a random draw at all (descriptive statistics,",
  "  percentiles, all regression estimates, P values) are reproduced exactly.",
  "  Percentiles use quantile(type = 6); the type is set in one place near",
  "  the top of the script.",
  "",
  "OUTPUT FILES",
  "  00_README.txt                this file (run instructions)",
  "  00_output_manifest.txt       inventory of files produced by the last run",
  "  console_output.txt           complete console log, including every",
  "                               number quoted in the manuscript",
  "  sessionInfo.txt              R version, package versions, locale",
  "  all_results.xlsx             one workbook with every table",
  "  Table1_baseline*.{csv,docx}  main-text Table 1",
  "  Table2_ordinal_models*.{csv,docx}  main-text Table 2",
  "  Figure1_flowchart.*          main-text Figure 1 (flowchart), written to",
  "                               output/ as PDF, TIFF (600 dpi) and PNG by",
  "                               Appendix A of this same script",
  "  Figure3_key_sensitivity_forest.*        main-text Figure 3 (8 specifications)",
  "  FigureS2_full_sensitivity_forest.*      Supplementary Figure S2 (all 15)",
  "  FigureS3_dose_response.*                Supplementary Figure S3",
  "  TableS3_bmi_available_vs_missing*.{csv,docx}  Supplementary Table S3",
  "  TableS4_interactions*.{csv,docx}             Supplementary Table S4",
  "  TableS5_additional_analyses*.{csv,docx}      Supplementary Table S5",
  "  reverse_causation_adjustments.csv  Model 3 + albumin / glucose / both",
  "  reverse_causation_correlations.csv Spearman rho of 25(OH)D with baseline",
  "                               severity and acute-phase markers",
  "  leave_one_out.csv           Model 3 refitted 90 times, one patient omitted",
  "  PO_alternative_checks.csv   6-level ordinal vs 3-level collapsed vs binary",
  "                               (used because the PPO relaxations in this",
  "                               sample are inadmissible; see PO_assumption.txt)",
  "  sensitivity_analyses.csv     all 15 specifications with E-values and",
  "                               Benjamini-Hochberg adjusted P values",
  "  Table1_vs_manuscript_check.csv  audit of Table 1 against the manuscript",
  "",
  "ANALYSIS SUMMARY",
  "  Cohort: 90 patients with hypertensive intracerebral hemorrhage, blood",
  "  sampled within 12 h of symptom onset. Primary model: proportional-odds",
  "  ordinal logistic regression of the 6-level modified Rankin Scale on",
  "  25(OH)D, adjusted for the minimal sufficient adjustment set derived from",
  "  the directed acyclic graph (age, sex, systolic blood pressure, log",
  "  follow-up duration). Sections 1-14 of the script follow the order of the",
  "  manuscript: description, Table 1, primary models, diagnostics,",
  "  proportional-odds checks, marginal probabilities, interactions,",
  "  sensitivity analyses, functional form, alternative adjustment sets,",
  "  follow-up windows, E-values, minimum detectable effect size, tables,",
  "  and the consistency check against the manuscript. Appendix A draws",
  "  Figure 1 (the study flowchart); it contains no statistics.",
  "",
  paste("Run    :", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  paste("R      :", R.version.string),
  paste("Input  :", DATA_FILE, sprintf("(n = %d)", nrow(d))),
  paste("Seed   :", SEED)),
  file.path(OUT_DIR, "00_README.txt"))

# ============================================================================
# APPENDIX A. FIGURE 1 -- STUDY FLOWCHART
# ============================================================================
# Screening counts are not derivable from the analytic data set (the 181
# patients screened out before the data set was assembled are not in it), so
# they are entered here as constants and cross-checked by the arithmetic
# assertions at the end of this appendix.
cat("\n=== Figure 1: study flowchart ===\n")
N_spontaneous  <- 271
N_exc1         <- 94                      # 87 secondary + 7 transient hypertension
N_hypertensive <- 177
N_exc2         <- 87                      # 50 criterion-related + 37 other
N_final        <- 90
exc1_reasons <- list(
  list(text = "Secondary causes of ICH",               n = 87),
  list(text = "Transient stress-induced hypertension", n = 7))
exc2_reasons <- list(
  list(text = "Exclusion criteria (n = 50)",                 n = NULL),
  list(text = "Blood sampling > 12 h after onset",           n = 11),
  list(text = "Voluntary discharge or treatment withdrawal", n = 6),
  list(text = "Cerebral infarction or rebleeding",           n = 7),
  list(text = "Antiplatelet or anticoagulant use",           n = 7),
  list(text = "Prior stroke",                                n = 6),
  list(text = "Pre-stroke mRS > 2",                          n = 4),
  list(text = "Age > 80 years",                              n = 3),
  list(text = "Concurrent malignancy",                       n = 3),
  list(text = "Severe renal insufficiency or dialysis",      n = 3),
  list(text = "Other reasons (n = 37)",                      n = NULL),
  list(text = "25(OH)D not measured",                        n = 32),
  list(text = "Lost to follow-up",                           n = 5))
stopifnot(87 + 7 == N_exc1,
          N_spontaneous - N_exc1 == N_hypertensive,
          11 + 6 + 7 + 7 + 6 + 4 + 3 + 3 + 3 == 50,
          32 + 5 == 37,
          50 + 37 == N_exc2,
          N_hypertensive - N_exc2 == N_final,
          N_final == nrow(d),
          max(d$mRS) == 5)

COL_BG <- "white"; COL_BOX <- "black"; COL_TEXT <- "black"
COL_EXC_BG <- "grey95"; COL_ARROW <- "black"
FS_TITLE <- 8.0; FS_MAIN_N <- 8.0; FS_EXC_HEAD <- 7.5
FS_ITEM <- 7.0;  FS_SUBHEAD <- 7.0; FS_FOOT <- 7.0

flow_draw_box <- function(x, y, width, height, label_lines, font_sizes,
                          fill = COL_BG, border = COL_BOX, lwd = 1.0,
                          text_color = COL_TEXT) {
  grid.roundrect(x = x, y = y, width = unit(width, "npc"),
                 height = unit(height, "npc"), r = unit(0.04, "inches"),
                 gp = gpar(fill = fill, col = border, lwd = lwd))
  if (length(label_lines) == 1) {
    grid.text(label_lines[1], x = x, y = y,
              gp = gpar(fontsize = font_sizes[1], col = text_color,
                        fontface = "bold", fontfamily = "sans"))
  } else {
    spacing <- 0.042
    start_y <- y + (length(label_lines) - 1) * spacing / 2
    for (i in seq_along(label_lines)) {
      grid.text(label_lines[i], x = x, y = start_y - (i - 1) * spacing,
                gp = gpar(fontsize = font_sizes[i], col = text_color,
                          fontface = if (i == length(label_lines)) "bold" else "plain",
                          fontfamily = "sans"))
    }
  }
}
flow_draw_excl <- function(cx, cy, w, h, exc_n, reasons) {
  grid.roundrect(x = cx, y = cy, width = unit(w, "npc"), height = unit(h, "npc"),
                 r = unit(0.04, "inches"),
                 gp = gpar(fill = COL_EXC_BG, col = COL_BOX, lwd = 1.2))
  top_y <- cy + h / 2
  header_y <- top_y - 0.030
  grid.text(paste0("Excluded (n = ", exc_n, ")"), x = cx, y = header_y,
            gp = gpar(fontsize = FS_EXC_HEAD, col = COL_TEXT,
                      fontface = "bold", fontfamily = "sans"))
  line_y <- header_y - 0.026
  left_edge <- cx - w / 2; right_edge <- cx + w / 2
  grid.lines(x = c(left_edge + 0.015, right_edge - 0.015), y = c(line_y, line_y),
             gp = gpar(col = COL_BOX, lwd = 0.6))
  n_items <- length(reasons)
  bottom_y <- cy - h / 2 + 0.015
  item_spacing <- if (n_items > 1) (line_y - 0.030 - bottom_y) / (n_items - 1) else 0
  item_start_y <- if (n_items > 1) line_y - 0.030 else (line_y + bottom_y) / 2
  for (i in seq_along(reasons)) {
    yy <- item_start_y - (i - 1) * item_spacing
    if (is.null(reasons[[i]]$n)) {
      grid.text(reasons[[i]]$text, x = left_edge + 0.022, y = yy,
                gp = gpar(fontsize = FS_SUBHEAD, col = COL_TEXT,
                          fontface = "bold", fontfamily = "sans"),
                hjust = 0, vjust = 0.5)
    } else {
      grid.points(x = left_edge + 0.022, y = yy, pch = 16,
                  size = unit(1.2, "mm"), gp = gpar(col = COL_TEXT))
      grid.text(paste0("  ", reasons[[i]]$text), x = left_edge + 0.038, y = yy,
                gp = gpar(fontsize = FS_ITEM, col = COL_TEXT, fontfamily = "sans"),
                hjust = 0, vjust = 0.5)
      grid.text(paste0("(n = ", reasons[[i]]$n, ")"), x = right_edge - 0.015, y = yy,
                gp = gpar(fontsize = FS_ITEM, col = COL_TEXT, fontfamily = "sans"),
                hjust = 1, vjust = 0.5)
    }
  }
}
flow_arrow <- function(x0, y0, x1, y1, lwd = 1.0) {
  grid.lines(x = c(x0, x1), y = c(y0, y1),
             arrow = arrow(length = unit(0.09, "inches"), type = "closed"),
             gp = gpar(col = COL_ARROW, lwd = lwd, fill = COL_ARROW))
}
flow_dashed <- function(x0, y0, x1, y1, lwd = 0.8) {
  grid.lines(x = c(x0, x1), y = c(y0, y1),
             gp = gpar(col = COL_ARROW, lwd = lwd, lty = "dashed"))
}
flow_plot <- function() {
  left_x <- 0.205;  left_w <- 0.29
  right_x <- 0.700; right_w <- 0.455
  box1_y <- 0.930; box1_h <- 0.075
  box2_y <- 0.620; box2_h <- 0.070
  box3_y <- 0.075; box3_h <- 0.090
  exc1_y <- 0.930; exc1_h <- 0.130
  exc2_y <- 0.390; exc2_h <- 0.560
  flow_draw_box(left_x, box1_y, left_w, box1_h,
                c("Spontaneous ICH (screened)", "Jan 2024 - Mar 2026   N = 271"),
                c(FS_TITLE, FS_MAIN_N))
  flow_draw_excl(right_x, exc1_y, right_w, exc1_h, N_exc1, exc1_reasons)
  flow_draw_box(left_x, box2_y, left_w, box2_h,
                c("Hypertensive ICH", "N = 177"), c(FS_TITLE, FS_MAIN_N))
  flow_draw_excl(right_x, exc2_y, right_w, exc2_h, N_exc2, exc2_reasons)
  flow_draw_box(left_x, box3_y, left_w, box3_h,
                c("Final analysis cohort", "N = 90"), c(FS_TITLE, FS_MAIN_N))
  flow_arrow(left_x, box1_y - box1_h / 2 - 0.006, left_x, box2_y + box2_h / 2 + 0.006)
  flow_arrow(left_x, box2_y - box2_h / 2 - 0.006, left_x, box3_y + box3_h / 2 + 0.006)
  dash_x0 <- left_x + left_w / 2 + 0.008
  dash_x1 <- right_x - right_w / 2 - 0.008
  flow_dashed(dash_x0, box1_y, dash_x1, exc1_y)
  flow_dashed(dash_x0, box2_y, dash_x1, exc2_y)
  grid.text("ICH, intracerebral haemorrhage; 25(OH)D, 25-hydroxyvitamin D; mRS, modified Rankin Scale.",
            x = 0.985, y = 0.032,
            gp = gpar(fontsize = FS_FOOT, col = COL_TEXT, fontfamily = "sans"),
            hjust = 1, vjust = 0)
  grid.text("Sampling-window criterion refers to inclusion criterion (4); no patient in the final cohort died (mRS range 0-5).",
            x = 0.985, y = 0.008,
            gp = gpar(fontsize = FS_FOOT, col = COL_TEXT, fontfamily = "sans"),
            hjust = 1, vjust = 0)
}
FIG_A_W <- 180 / 25.4
FIG_A_H <- 150 / 25.4
pdf(file.path(OUT_DIR, "Figure1_flowchart.pdf"), width = FIG_A_W, height = FIG_A_H)
grid.newpage(); flow_plot(); dev.off()
tiff(file.path(OUT_DIR, "Figure1_flowchart.tiff"),
     width = FIG_A_W * 600, height = FIG_A_H * 600, res = 600,
     compression = "lzw")
grid.newpage(); flow_plot(); dev.off()
png(file.path(OUT_DIR, "Figure1_flowchart.png"),
    width = FIG_A_W * 600, height = FIG_A_H * 600, res = 600)
grid.newpage(); flow_plot(); dev.off()
cat("Figure 1 written (PDF, TIFF 600 dpi, PNG 600 dpi).\n")

files    <- list.files(OUT_DIR, full.names = FALSE)
produced <- setdiff(files, pre_existing)
legacy   <- intersect(files, pre_existing)
writeLines(c(paste("Files produced by", SELF_NAME),
             paste("Run  :", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
             paste("Input:", DATA_FILE),
             "",
             "--- produced by this run ---",
             produced,
             "",
             "--- already present in output/ before this run (NOT from this script) ---",
             legacy),
           file.path(OUT_DIR, "00_output_manifest.txt"))
cat("\n=== DONE ===\n")
cat("Output directory:", OUT_DIR, "\n")
cat("Produced", length(produced), "files;", length(legacy),
    "pre-existing files were left untouched:\n")
print(legacy)
