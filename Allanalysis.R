rm(list = ls())

# ---- Project paths (override PROJECT_DIR only if running from elsewhere) ----
PROJECT_DIR <- getwd()                        # RStudio project root
DATA_DIR    <- file.path(PROJECT_DIR, "data", "clean")
OUTPUT_DIR  <- file.path(PROJECT_DIR, "output")

# ---- Reproducibility settings ----
CRAN_REPO   <- "https://cloud.r-project.org/"
options(repos = c(CRAN = CRAN_REPO))

# ---- Global error handler: capture the FIRST error with full traceback ----
# If the script aborts anywhere, write output/ERROR.txt (or <wd>/ERROR.txt)
# with the error message + traceback + sessionInfo, so the real failure is
# never hidden. This also prevents a silent, confusing abort.
options(error = function() {
  msg <- geterrmessage()
  tb  <- paste(capture.output(traceback()), collapse = "\n")
  out <- if (dir.exists(OUTPUT_DIR)) OUTPUT_DIR else getwd()
  si  <- tryCatch(paste(capture.output(sessionInfo()), collapse = "\n"),
                  error = function(e) "sessionInfo unavailable")
  log_lines <- c(
    paste0("ERROR occurred at: ", Sys.time()),
    "",
    "=== Error message ===",
    msg,
    "",
    "=== Traceback ===",
    ifelse(identical(tb, ""), "(no traceback available)", tb),
    "",
    "=== Session info ===",
    si
  )
  try(writeLines(log_lines, file.path(out, "ERROR.txt")), silent = TRUE)
  message("\n========== SCRIPT ERROR ==========\n",
          msg, "\n(Full details written to output/ERROR.txt)\n")
})
# ============================================================================
# 0. Set random seed for reproducibility
# ============================================================================
set.seed(20260719)
# ============================================================================
# 1. Package installation and loading
# ============================================================================
packages_needed <- c("MASS", "brant", "ordinal", "VGAM", "survival", "splines",
                     "readxl", "openxlsx", "officer", "flextable", "lmtest", "rms")
for (pkg in packages_needed) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    install.packages(pkg, repos = CRAN_REPO)
    library(pkg, character.only = TRUE)
  }
}

cat("=== R Package Versions ===\n")
cat("R version:", R.version$version.string, "\n")
cat("MASS version:", as.character(packageVersion("MASS")), "\n")
cat("brant version:", as.character(packageVersion("brant")), "\n")
cat("VGAM version:", as.character(packageVersion("VGAM")), "\n")
cat("rms version:", as.character(packageVersion("rms")), "\n")
cat("\n")

# ============================================================================
# 2. Data import — AUTOMATED (no interactive prompts)
#    Input : <DATA_DIR>/final_ich_cohort.xlsx  (fixed, required)
#    Output: <OUTPUT_DIR>/  (created if missing; flat, no timestamp subfolder)
# ============================================================================
data_file <- file.path(DATA_DIR, "final_ich_cohort.xlsx")
if (!file.exists(data_file)) {
  stop(
    paste0("INPUT DATA NOT FOUND: '", data_file, "'.\n",
           "Place 'final_ich_cohort.xlsx' inside the 'data/clean/' folder ",
           "at the project root, then re-run this script."),
    call. = FALSE
  )
}
cat("Data file:", data_file, "\n")

file_ext <- tolower(tools::file_ext(data_file))
if (file_ext == "csv") {
  data <- read.csv(data_file)
} else if (file_ext %in% c("xls", "xlsx")) {
  data <- read_excel(data_file)
} else {
  stop("Unsupported file format! Expected .csv, .xls or .xlsx file.")
}

names(data) <- make.names(names(data), unique = TRUE)
cat("Column names standardized.\n\n")
cat("Available columns:\n")
cat(paste("  ", colnames(data)), sep = "\n")
cat("\n")

# Create the flat output directory (per submission spec: results go to output/)
output_dir <- OUTPUT_DIR
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
  cat("Created output directory:", output_dir, "\n")
}

# --- Data provenance / run log (helps reviewers verify reproducibility) ---
run_info <- c(
  paste0("Script:         Allanalysis_SCI.R"),
  paste0("Run timestamp:  ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste0("R version:      ", R.version$version.string),
  paste0("Platform:       ", R.version$platform),
  paste0("Data file:      ", data_file),
  paste0("Data size (KB): ", round(file.size(data_file) / 1024, 1)),
  paste0("Data MD5:       ", as.character(tools::md5sum(data_file))),
  paste0("N rows (raw):   ", nrow(data)),
  paste0("N cols (raw):   ", ncol(data))
)
writeLines(run_info, file.path(output_dir, "00_run_info.txt"))
cat("Run info written -> output/00_run_info.txt\n")

# Redirect console output to a log file (split = TRUE keeps the console echo)
sink(file.path(output_dir, "console_output.txt"), split = TRUE)
cat("=== Console output log (mirrors the R console) ===\n")

# ============================================================================
# 3. Column name resolution
# ============================================================================
resolve_colnames <- function(col_data, mapping_list) {
  resolved <- list()
  for (varname in names(mapping_list)) {
    pattern <- mapping_list[[varname]]
    matches <- grep(pattern, col_data, ignore.case = TRUE, value = TRUE)
    if (length(matches) >= 1) {
      resolved[[varname]] <- matches[1]
    } else {
      cat("  [WARNING] No column matched pattern '", pattern, "'\n", sep = "")
    }
  }
  used_cols <- unlist(resolved)
  unmatched <- setdiff(col_data, used_cols)
  if (length(unmatched) > 0) {
    cat("  [INFO] Unmatched columns (not in any predefined pattern):\n")
    cat(paste("    ", unmatched), sep = "\n")
    cat("\n")
  }
  return(resolved)
}

cont_patterns <- c(
  age                    = "^age$|^Age$",
  SBP                    = "^(SBP|sbp|Systolic|systolic)",
  DBP                    = "^(DBP|dbp|Diastolic|diastolic)",
  MAP                    = "^(MAP|map|Mean.arterial)",
  GCS                    = "^(GCS|gcs)",
  NIHSS                  = "^(NIHSS|nihss)",
  Hematoma.volume        = "hematoma",
  HGB                    = "^(HGB|hgb|Hemoglobin|hemoglobin)",
  GLU                    = "^(GLU|glu|Glucose|glucose|RPG|rpg)",
  Cr                     = "^(Cr|cr|Creatinine|creatinine)",
  Ca                     = "^(Ca|ca|Calcium|calcium)",
  CHOL                   = "^(CHOL|chol|Cholesterol|cholesterol|Total.cholesterol)",
  TRIG                   = "^(TRIG|trig|Triglycerides|triglycerides)",
  HDL.C                  = "^(HDL|hdl|HDL\\.C)",
  LDL.C                  = "^(LDL|ldl|LDL\\.C)",
  ALT                    = "^(ALT|alt)",
  AST                    = "^(AST|ast)",
  GGT                    = "^(GGT|ggt|Gamma.GT|gamma.gt)",
  ALP                    = "^(ALP|alp|Alkaline|alkaline)",
  ALB                    = "^(ALB|alb|Albumin|albumin)",
  X25.OH.Vitamin.D       = "25\\.?OH|Vitamin\\.?D|vitamin\\.?d|Vit\\.?D|vit\\.?d",
  follow.up.duration     = "^follow\\.up\\.duration$|^follow_up_duration$",
  BMI                    = "^(BMI|bmi|Body.mass)",
  mRS                    = "^(mRS|MRS|Modified.Rankin|modified.rankin)"
)

cat_patterns <- c(
  gender                  = "^(gender|Gender|sex|Sex)",
  Hemorrhage.location     = "hemorrhage|Hemorrhage|bleeding",
  intraventricular.extension = "intraventricular|Intraventricular|IVH|ivh",
  surgical.treatment      = "surgical|Surgical|surgery|Surgery|operation",
  admission.period        = "admission|Admission|season|Season|period"
)

cat("\n=== Resolving column names ===\n")
resolved_cont <- resolve_colnames(colnames(data), cont_patterns)
resolved_cat <- resolve_colnames(colnames(data), cat_patterns)

cat("\nResolved continuous variables:\n")
for (nm in names(resolved_cont)) {
  cat(sprintf("  %s -> %s\n", nm, resolved_cont[[nm]]))
}
cat("\nResolved categorical variables:\n")
for (nm in names(resolved_cat)) {
  cat(sprintf("  %s -> %s\n", nm, resolved_cat[[nm]]))
}
cat("\n")

mrs_col      <- resolved_cont[["mRS"]]
age_col      <- resolved_cont[["age"]]
gender_col   <- resolved_cat[["gender"]]
vitd_col     <- resolved_cont[["X25.OH.Vitamin.D"]]
followup_col <- resolved_cont[["follow.up.duration"]]

if (is.null(mrs_col))      stop("mRS column not found!")
if (is.null(age_col))      stop("Age column not found!")
if (is.null(gender_col))   stop("Gender column not found!")
if (is.null(vitd_col))     stop("25(OH)D column not found!")
if (is.null(followup_col)) stop("Follow-up duration column not found!")

# ============================================================================
# 4. Label mappings and variable transformations
# ============================================================================
label_mapping <- list(
  gender                  = c("1" = "Male", "2" = "Female"),
  Hemorrhage.location     = c("1" = "Supratentorial", "2" = "Infratentorial"),
  intraventricular.extension = c("0" = "No", "1" = "Yes"),
  admission.period        = c("1" = "May-October", "2" = "November-April"),
  surgical.treatment      = c("0" = "No", "1" = "Yes")
)

for (var_name in names(label_mapping)) {
  if (var_name %in% names(resolved_cat)) {
    actual_col <- resolved_cat[[var_name]]
    data[[actual_col]] <- factor(data[[actual_col]],
                                 levels = names(label_mapping[[var_name]]),
                                 labels = label_mapping[[var_name]])
  }
}

# Explicitly set mRS ordered levels: 0 = best, 6 = worst
# OR < 1 indicates lower odds of worse outcome (protective)
data$mRS_ordered <- ordered(data[[mrs_col]], levels = sort(unique(data[[mrs_col]])))
if (any(is.na(data$mRS_ordered))) {
  stop("mRS values contain non-integer values outside 0-6. Please verify coding.")
}

data$vitd_per10   <- data[[vitd_col]] / 10
data$log_followup <- log(data[[followup_col]])

# ============================================================================
# 5. Baseline characteristics (Table 1)
# ============================================================================
data$outcome_group <- ifelse(data[[mrs_col]] <= 2, "Good (mRS≤2)", "Poor (mRS>2)")
cat(sprintf("Good outcome: %d (%.1f%%)\n", 
            sum(data$outcome_group == "Good (mRS≤2)"), 
            mean(data$outcome_group == "Good (mRS≤2)") * 100))
cat(sprintf("Poor outcome: %d (%.1f%%)\n", 
            sum(data$outcome_group == "Poor (mRS>2)"), 
            mean(data$outcome_group == "Poor (mRS>2)") * 100))

continuous_labels <- list(
  age                    = "Age (years)",
  SBP                    = "SBP (mmHg)",
  DBP                    = "DBP (mmHg)",
  MAP                    = "MAP (mmHg)",
  GCS                    = "GCS (score)",
  NIHSS                  = "NIHSS (score)",
  Hematoma.volume        = "Hematoma volume (mL)",
  HGB                    = "Hemoglobin (g/L)",
  GLU                    = "RPG (mmol/L)",
  Cr                     = "Creatinine (μmol/L)",
  Ca                     = "Calcium (mmol/L)",
  CHOL                   = "Cholesterol (mmol/L)",
  TRIG                   = "Triglycerides (mmol/L)",
  HDL.C                  = "HDL-C (mmol/L)",
  LDL.C                  = "LDL-C (mmol/L)",
  ALT                    = "ALT (U/L)",
  AST                    = "AST (U/L)",
  GGT                    = "GGT (U/L)",
  ALP                    = "ALP (U/L)",
  ALB                    = "Albumin (g/L)",
  X25.OH.Vitamin.D       = "25(OH)D (nmol/L)",
  follow.up.duration     = "Follow-up duration (days)",
  BMI                    = "BMI (kg/m²)"
)

categorical_labels <- list(
  gender                  = "Gender",
  Hemorrhage.location     = "Hemorrhage location",
  intraventricular.extension = "Intraventricular extension",
  surgical.treatment      = "Surgical treatment",
  admission.period        = "Admission period"
)

# Normality test and Table 1 generation
normality_results <- data.frame(
  Variable = character(),
  W_statistic = numeric(),
  p_value = numeric(),
  Distribution = character(),
  stringsAsFactors = FALSE
)
for (var_name in names(resolved_cont)) {
  actual_col <- resolved_cont[[var_name]]
  if (actual_col %in% colnames(data)) {
    vals <- data[[actual_col]]
    vals <- vals[!is.na(vals)]
    if (length(vals) >= 3) {
      sw <- shapiro.test(vals)
      normality_results <- rbind(normality_results, data.frame(
        Variable = var_name,
        W_statistic = round(sw$statistic, 4),
        p_value = signif(sw$p.value, 4),
        Distribution = ifelse(sw$p.value > 0.05, "Normal", "Non-normal")
      ))
    }
  }
}
cat("=== Normality Test Results ===\n")
print(normality_results)
cat("\n")

# Overall descriptive statistics
overall_results <- list()
for (var_name in names(resolved_cont)) {
  actual_col <- resolved_cont[[var_name]]
  if (actual_col %in% colnames(data)) {
    vals <- data[[actual_col]]
    vals_clean <- vals[!is.na(vals)]
    if (length(vals_clean) >= 3) {
      sw <- shapiro.test(vals_clean)
      if (sw$p.value > 0.05) {
        repr <- sprintf("%.1f ± %.1f", mean(vals_clean), sd(vals_clean))
      } else {
        repr <- sprintf("%.1f (%.1f–%.1f)", median(vals_clean), quantile(vals_clean, 0.25), quantile(vals_clean, 0.75))
      }
      overall_results[[var_name]] <- list(
        label = continuous_labels[[var_name]],
        overall = repr,
        missing = sum(is.na(vals))
      )
    }
  }
}
for (var_name in names(resolved_cat)) {
  actual_col <- resolved_cat[[var_name]]
  if (actual_col %in% colnames(data)) {
    counts <- table(data[[actual_col]])
    total <- sum(!is.na(data[[actual_col]]))
    repr_parts <- c()
    for (cat_name in names(counts)) {
      pct <- counts[cat_name] / total * 100
      repr_parts <- c(repr_parts, sprintf("%s: %d (%.1f%%)", cat_name, counts[cat_name], pct))
    }
    overall_results[[var_name]] <- list(
      label = categorical_labels[[var_name]],
      overall = paste(repr_parts, collapse = "; "),
      missing = sum(is.na(data[[actual_col]]))
    )
  }
}

# Group comparisons (Good vs Poor outcome)
comparison_results <- list()
for (var_name in names(resolved_cont)) {
  actual_col <- resolved_cont[[var_name]]
  if (!(actual_col %in% colnames(data))) next
  
  good <- data[[actual_col]][data$outcome_group == "Good (mRS≤2)"]
  poor <- data[[actual_col]][data$outcome_group == "Poor (mRS>2)"]
  good_clean <- good[!is.na(good)]
  poor_clean <- poor[!is.na(poor)]
  
  if (length(good_clean) == 0 || length(poor_clean) == 0) {
    cat(sprintf("  Skipping '%s': one group has zero non-missing values.\n", var_name))
    next
  }
  
  all_data <- c(good_clean, poor_clean)
  is_normal <- if (length(all_data) >= 3) shapiro.test(all_data)$p.value > 0.05 else FALSE
  
  if (is_normal) {
    tr <- t.test(good_clean, poor_clean, var.equal = FALSE)
    test_name <- "t-test"
    p_val <- tr$p.value
    good_repr <- sprintf("%.1f ± %.1f", mean(good_clean), sd(good_clean))
    poor_repr <- sprintf("%.1f ± %.1f", mean(poor_clean), sd(poor_clean))
  } else {
    tr <- wilcox.test(good_clean, poor_clean, exact = FALSE)
    test_name <- "Mann-Whitney U"
    p_val <- tr$p.value
    good_repr <- sprintf("%.1f (%.1f–%.1f)", median(good_clean), quantile(good_clean, 0.25), quantile(good_clean, 0.75))
    poor_repr <- sprintf("%.1f (%.1f–%.1f)", median(poor_clean), quantile(poor_clean, 0.25), quantile(poor_clean, 0.75))
  }
  
  total_n <- nrow(data)
  good_n <- sum(data$outcome_group == "Good (mRS≤2)")
  poor_n <- sum(data$outcome_group == "Poor (mRS>2)")
  total_miss <- sum(is.na(data[[actual_col]]))
  good_miss <- sum(is.na(data[[actual_col]][data$outcome_group == "Good (mRS≤2)"]))
  poor_miss <- sum(is.na(data[[actual_col]][data$outcome_group == "Poor (mRS>2)"]))
  
  overall_entry <- overall_results[[var_name]]
  overall_text <- if (!is.null(overall_entry) && !is.null(overall_entry$overall)) overall_entry$overall else ""
  char_label <- continuous_labels[[var_name]]
  if (is.null(char_label)) char_label <- var_name
  
  safe_char <- function(x) {
    if (is.null(x) || length(x) == 0) return("")
    as.character(x)[1]
  }
  
  comparison_results[[var_name]] <- data.frame(
    Characteristic = safe_char(char_label),
    Total = safe_char(overall_text),
    Good_Outcome = safe_char(good_repr),
    Poor_Outcome = safe_char(poor_repr),
    Test = safe_char(test_name),
    p_value = if (is.null(p_val) || length(p_val) == 0) NA_real_ else p_val,
    Missing_n = if (is.null(total_miss) || length(total_miss) == 0) NA_integer_ else total_miss,
    Missing_Good = if (is.null(good_miss) || length(good_miss) == 0) NA_integer_ else good_miss,
    Missing_Poor = if (is.null(poor_miss) || length(poor_miss) == 0) NA_integer_ else poor_miss,
    stringsAsFactors = FALSE
  )
  
  if (total_miss > 0) {
    t_pct <- sprintf("%.1f%%", total_miss / total_n * 100)
    g_pct <- if (good_n > 0) sprintf("%.1f%%", good_miss / good_n * 100) else "0.0%"
    p_pct <- if (poor_n > 0) sprintf("%.1f%%", poor_miss / poor_n * 100) else "0.0%"
    missing_row <- data.frame(
      Characteristic = "  Missing",
      Total = sprintf("%d (%s)", total_miss, t_pct),
      Good_Outcome = sprintf("%d (%s)", good_miss, g_pct),
      Poor_Outcome = sprintf("%d (%s)", poor_miss, p_pct),
      Test = NA_character_,
      p_value = NA_real_,
      Missing_n = NA_integer_,
      Missing_Good = NA_integer_,
      Missing_Poor = NA_integer_,
      stringsAsFactors = FALSE
    )
    comparison_results[[paste0(var_name, "_miss")]] <- missing_row
  }
}

# Categorical variable comparison
for (var_name in names(resolved_cat)) {
  actual_col <- resolved_cat[[var_name]]
  if (actual_col %in% colnames(data)) {
    ct <- table(data[[actual_col]], data$outcome_group)
    chi2_tmp <- suppressWarnings(chisq.test(ct, correct = FALSE))
    min_exp <- min(chi2_tmp$expected)
    if (min_exp < 5 || any(ct < 5)) {
      fr <- fisher.test(ct)
      p_val <- fr$p.value
      test_name <- "Fisher's exact"
    } else {
      chi2_tmp2 <- chisq.test(ct, correct = TRUE)
      p_val <- chi2_tmp2$p.value
      test_name <- "Chi-square"
    }
    missing_n <- sum(is.na(data[[actual_col]]))
    var_label <- categorical_labels[[var_name]]
    header_row <- data.frame(
      Characteristic = var_label,
      Total = "",
      Good_Outcome = "",
      Poor_Outcome = "",
      Test = test_name,
      p_value = p_val,
      Missing_n = missing_n,
      Missing_Good = NA_integer_,
      Missing_Poor = NA_integer_,
      stringsAsFactors = FALSE
    )
    category_rows <- data.frame()
    good_total_n <- sum(ct[, "Good (mRS≤2)"])
    poor_total_n <- sum(ct[, "Poor (mRS>2)"])
    for (cat_name in rownames(ct)) {
      g_cnt <- ct[cat_name, "Good (mRS≤2)"]
      p_cnt <- ct[cat_name, "Poor (mRS>2)"]
      t_cnt <- g_cnt + p_cnt
      t_n <- good_total_n + poor_total_n
      category_rows <- rbind(category_rows, data.frame(
        Characteristic = paste0("  ", cat_name),
        Total = sprintf("%d (%.1f%%)", t_cnt, t_cnt / t_n * 100),
        Good_Outcome = sprintf("%d (%.1f%%)", g_cnt, g_cnt / good_total_n * 100),
        Poor_Outcome = sprintf("%d (%.1f%%)", p_cnt, p_cnt / poor_total_n * 100),
        Test = NA_character_,
        p_value = NA_real_,
        Missing_n = NA_integer_,
        Missing_Good = NA_integer_,
        Missing_Poor = NA_integer_,
        stringsAsFactors = FALSE
      ))
    }
    comparison_results[[var_name]] <- rbind(header_row, category_rows)
  }
}

# Compile Table 1
en_dash <- function(x) {
  gsub("([0-9]\\.?[0-9]*)-([0-9])", "\\1–\\2", x)
}

results_df <- do.call(rbind, comparison_results)
results_df$p_value <- sapply(results_df$p_value, function(x) {
  if (is.na(x)) return("")
  else if (x < 0.001) return("<0.001")
  else return(sprintf("%.3f", x))
})

n_total <- nrow(data)
n_good <- sum(data$outcome_group == "Good (mRS≤2)")
n_poor <- sum(data$outcome_group == "Poor (mRS>2)")

n_header <- data.frame(
  Characteristic = "N",
  Total = sprintf("N = %d", n_total),
  Good_Outcome = sprintf("N = %d", n_good),
  Poor_Outcome = sprintf("N = %d", n_poor),
  Test = "", p_value = "", Missing_n = "", Missing_Good = "", Missing_Poor = "",
  stringsAsFactors = FALSE
)
results_df <- rbind(n_header, results_df)

for (col_i in c("Total", "Good_Outcome", "Poor_Outcome")) {
  results_df[[col_i]] <- en_dash(results_df[[col_i]])
}

output_df <- results_df[, !(colnames(results_df) %in% c("Missing_Good", "Missing_Poor"))]
write.xlsx(output_df, file.path(output_dir, "baseline_characteristics_R.xlsx"), rowNames = FALSE)

# Export Word table (three-line table)
tryCatch({
  library(officer)
  library(flextable)
  
  tbl_display <- output_df[, !(colnames(output_df) %in% c("Test"))]
  colnames(tbl_display) <- c(
    "Characteristic",
    sprintf("Total (n = %d)", n_total),
    sprintf("Good outcome (mRS ≤ 2, n = %d)", n_good),
    sprintf("Poor outcome (mRS > 2, n = %d)", n_poor),
    "P-value",
    "Missing, n"
  )
  
  ft <- flextable(tbl_display)
  ft <- theme_booktabs(ft)
  ft <- font(ft, fontname = "Arial", part = "all")
  ft <- fontsize(ft, size = 9, part = "body")
  ft <- fontsize(ft, size = 9, part = "header")
  ft <- bold(ft, part = "header")
  ft <- align(ft, align = "left", part = "all")
  ft <- set_table_properties(ft, layout = "autofit")
  ft <- padding(ft, padding = 2, part = "all")
  
  footnote_txt <- paste0(
    "Data are median (IQR) for continuous variables with non-normal distribution, ",
    "mean ± SD for continuous variables with normal distribution, ",
    "or n (%) for categorical variables. ",
    "P-values were calculated using Mann–Whitney U test for skewed continuous variables, ",
    "independent t-test for normally distributed continuous variables, ",
    "Chi-square test (with Yates’ continuity correction) or Fisher’s exact test ",
    "(when expected cell frequencies <5) for categorical variables."
  )
  
  ft <- add_footer_lines(ft, footnote_txt)
  ft <- fontsize(ft, size = 8, part = "footer")
  ft <- italic(ft, italic = TRUE, part = "footer")
  
  doc <- read_docx()
  doc <- body_add_flextable(doc, ft)
  doc <- body_add_par(doc, "")
  doc <- body_add_par(doc, "Table 1. Baseline characteristics of the study population.", style = "Normal")
  
  word_file <- file.path(output_dir, "Table1_Baseline_Characteristics.docx")
  print(doc, target = word_file)
  cat("Baseline table (Word) saved to:", word_file, "\n")
}, error = function(e) {
  cat("[WARNING] Word table generation failed:", e$message, "\n")
  cat("Continuing with Excel output only.\n")
})

# ============================================================================
# 6. Complete-case subset for primary models
# ============================================================================
sbp_candidates <- grep("systol|sbp", names(data), ignore.case = TRUE, value = TRUE)
has_sbp <- length(sbp_candidates) > 0
if (has_sbp) {
  sbp_var <- sbp_candidates[1]
  cat("Detected SBP variable:", sbp_var, "\n")
} else {
  sbp_var <- NULL
  cat("SBP variable not found.\n")
}

cc_vars <- c(mrs_col, followup_col, vitd_col, age_col, gender_col)
if (has_sbp) cc_vars <- c(cc_vars, sbp_var)
cc_before <- nrow(data)
data_cc <- data[complete.cases(data[, cc_vars]), ]
cc_after <- nrow(data_cc)
cc_pct <- (cc_before - cc_after) / cc_before * 100
cat(sprintf("Complete-case subset: %d -> %d (dropped %.1f%%)\n", cc_before, cc_after, cc_pct))

# Save missing summary to file
writeLines(
  sprintf("Complete-case analysis: %d -> %d (dropped %.1f%%, %d cases)", 
          cc_before, cc_after, cc_pct, cc_before - cc_after),
  file.path(output_dir, "missing_summary.txt")
)
write(
  "Missingness was confined to BMI and lipid profiles; BMI excluded from all multivariable models.",
  file = file.path(output_dir, "missing_summary.txt"),
  append = TRUE
)
# Compute EPV (Events Per Variable) for Model 3
n_event <- sum(data_cc[[mrs_col]] > 2, na.rm = TRUE)
n_pred_m3 <- 5  # vitd_per10 + age + gender + SBP + log_followup
epv <- n_event / n_pred_m3
cat(sprintf("EPV for Model 3: %.1f (events=%d, predictors=%d)\n", epv, n_event, n_pred_m3))
cat("Missingness was confined to BMI and lipid profiles; BMI excluded from all multivariable models.\n")

# Re-derive transformations on complete-case subset
data <- data_cc
data$vitd_per10   <- data[[vitd_col]] / 10
data$log_followup <- log(data[[followup_col]])
data$mRS_ordered  <- ordered(data[[mrs_col]], levels = sort(unique(data[[mrs_col]])))
# Binary indicator: <50 nmol/L = 1, >=50 nmol/L = 0 (reference)
data$vitd_50 <- ifelse(data[[vitd_col]] < 50, 1, 0)

# ============================================================================
# 7. Helper function for OR extraction from polr
# ============================================================================
extract_polr_or <- function(model, var_name) {
  res <- tryCatch({
    coef_val <- coef(model)[var_name]
    vcov_mat <- vcov(model)
    se_val <- sqrt(vcov_mat[var_name, var_name])
    or <- exp(coef_val)
    ci_lower <- exp(coef_val - 1.96 * se_val)
    ci_upper <- exp(coef_val + 1.96 * se_val)
    z_val <- coef_val / se_val
    p_val <- 2 * (1 - pnorm(abs(z_val)))
    list(coefficient = coef_val, se = se_val, or = or,
         ci_lower = ci_lower, ci_upper = ci_upper, p_value = p_val)
  }, error = function(e) {
    list(coefficient = NA_real_, se = NA_real_, or = NA_real_,
         ci_lower = NA_real_, ci_upper = NA_real_, p_value = NA_real_)
  })
  return(res)
}

# ============================================================================
# 8. Primary analysis: Ordinal logistic regression (proportional odds model)
# ============================================================================
cat("\n=== Primary Analysis: Ordinal Logistic Regression ===\n")

# Model 1: Unadjusted
model1 <- polr(
  mRS_ordered ~ vitd_per10,
  data = data,
  method = "logistic",
  Hess = TRUE
)
res1 <- extract_polr_or(model1, "vitd_per10")

# Model 2: Adjusted for age, gender, and follow-up duration
model2 <- polr(
  as.formula(paste0("mRS_ordered ~ vitd_per10 + ", age_col, " + ", gender_col, " + log_followup")),
  data = data,
  method = "logistic",
  Hess = TRUE
)
res2 <- extract_polr_or(model2, "vitd_per10")

# Model 3: Fully adjusted (age, gender, SBP, and follow-up duration)
if (has_sbp) {
  model3 <- polr(
    as.formula(paste0("mRS_ordered ~ vitd_per10 + ", age_col, " + ", gender_col, " + ", sbp_var, " + log_followup")),
    data = data,
    method = "logistic",
    Hess = TRUE
  )
  res3 <- extract_polr_or(model3, "vitd_per10")
} else {
  res3 <- NULL
}

# Print results
cat(sprintf("Model 1 (Unadjusted): OR = %.3f (95%% CI: %.3f-%.3f), P = %.4f\n",
            res1$or, res1$ci_lower, res1$ci_upper, res1$p_value))
cat(sprintf("Model 2 (Age + Gender + Follow-up): OR = %.3f (95%% CI: %.3f-%.3f), P = %.4f\n",
            res2$or, res2$ci_lower, res2$ci_upper, res2$p_value))
if (has_sbp && !is.null(res3)) {
  cat(sprintf("Model 3 (Fully adjusted): OR = %.3f (95%% CI: %.3f-%.3f), P = %.4f\n",
              res3$or, res3$ci_lower, res3$ci_upper, res3$p_value))
}

# ---- Categorical analysis: <50 vs >=50 nmol/L (>=50 as reference) ----
cat("\n--- Primary Analysis (Categorical): <50 vs >=50 nmol/L ---\n")

# Model 1c: Unadjusted
model1_cat <- polr(
  mRS_ordered ~ vitd_50,
  data = data,
  method = "logistic",
  Hess = TRUE
)
res1_cat <- extract_polr_or(model1_cat, "vitd_50")

# Model 2c: Adjusted for age, gender, and follow-up duration
model2_cat <- polr(
  as.formula(paste0("mRS_ordered ~ vitd_50 + ", age_col, " + ", gender_col, " + log_followup")),
  data = data,
  method = "logistic",
  Hess = TRUE
)
res2_cat <- extract_polr_or(model2_cat, "vitd_50")

# Model 3c: Fully adjusted (age, gender, SBP, and follow-up duration)
if (has_sbp) {
  model3_cat <- polr(
    as.formula(paste0("mRS_ordered ~ vitd_50 + ", age_col, " + ", gender_col, " + ", sbp_var, " + log_followup")),
    data = data,
    method = "logistic",
    Hess = TRUE
  )
  res3_cat <- extract_polr_or(model3_cat, "vitd_50")
} else {
  res3_cat <- NULL
}

# Print categorical results
cat(sprintf("Model 1c (<50 vs >=50, Unadjusted): OR = %.3f (95%% CI: %.3f-%.3f), P = %.4f\n",
            res1_cat$or, res1_cat$ci_lower, res1_cat$ci_upper, res1_cat$p_value))
cat(sprintf("Model 2c (<50 vs >=50, Age + Gender + Follow-up): OR = %.3f (95%% CI: %.3f-%.3f), P = %.4f\n",
            res2_cat$or, res2_cat$ci_lower, res2_cat$ci_upper, res2_cat$p_value))
if (has_sbp && !is.null(res3_cat)) {
  cat(sprintf("Model 3c (<50 vs >=50, Fully adjusted): OR = %.3f (95%% CI: %.3f-%.3f), P = %.4f\n",
              res3_cat$or, res3_cat$ci_lower, res3_cat$ci_upper, res3_cat$p_value))
}

# ============================================================================
# 9. Proportional odds assumption testing
# ============================================================================
cat("\n=== Proportional Odds Assumption Testing ===\n")

# 9.1 Brant test on Model 2
brant_result <- tryCatch({
  brant::brant(model2)
}, error = function(e) {
  cat("Brant test failed:", e$message, "\n")
  NULL
})
if (!is.null(brant_result)) {
  print(brant_result)
}

# 9.2 nominal_test via ordinal::clm
library(ordinal)

model_clm <- clm(
  as.formula(paste0("mRS_ordered ~ vitd_per10 + ", age_col, " + ", gender_col, " + log_followup")),
  data = data, link = "logit"
)

cat("\n--- nominal_test (clm) ---\n")
nt <- nominal_test(model_clm)
print(nt)

# 9.3 If vitd_per10 significantly violates PO (p < 0.05), fit PPO model
po_violated <- FALSE
if (!is.null(nt) && any(rownames(nt) == "vitd_per10")) {
  if (nt["vitd_per10", "Pr(>Chi)"] < 0.05) {
    po_violated <- TRUE
    cat("\n--- Fitting Partial Proportional Odds Model (PPO) for vitd_per10 ---\n")
    
    formula_ppo <- as.formula(
      paste0("mRS_ordered ~ vitd_per10 + ", age_col, " + ", gender_col)
    )
    fit_ppo <- clm(formula_ppo,
                   nominal = ~ vitd_per10,
                   data = data, link = "logit")
    
    lr_ppo <- 2 * (logLik(fit_ppo) - logLik(model_clm))
    df_ppo <- fit_ppo$edf - model_clm$edf
    p_ppo <- pchisq(lr_ppo, df = df_ppo, lower.tail = FALSE)
    cat(sprintf("PPO vs PO: LR = %.3f, df = %d, P = %.4f\n",
                lr_ppo, df_ppo, p_ppo))
    
    coef_ppo <- coef(fit_ppo)
    idx_vitd <- grep("^vitd_per10", names(coef_ppo))
    if (length(idx_vitd) > 0) {
      cat("\nThreshold-specific OR for vitd_per10 (per 10 nmol/L):\n")
      for (i in seq_along(idx_vitd)) {
        or_val <- exp(coef_ppo[idx_vitd[i]])
        ci <- exp(confint(fit_ppo)[idx_vitd[i], ])
        cat(sprintf("  Threshold %d: OR = %.3f (%.3f–%.3f)\n",
                    i, or_val, ci[1], ci[2]))
      }
    }
  } else {
    cat("vitd_per10 does not significantly violate PO; retain PO model.\n")
  }
}

# PO decision summary for Methods section
cat("\n=== PO Decision Summary ===\n")
if (po_violated) {
  cat("PO assumption violated for vitD; PPO model fitted.\n")
} else {
  cat("PO assumption not violated; standard PO model retained.\n")
}

# ============================================================================
# 10. E-value calculation
# ============================================================================
calc_e_value <- function(est, ci_lower, ci_upper) {
  if (any(is.na(c(est, ci_lower, ci_upper)))) return(list(E_value = NA, E_value_CI = NA))
  if (est >= 1) {
    e_point <- est + sqrt(est * (est - 1))
  } else {
    e_point <- 1/est + sqrt((1/est) * ((1/est) - 1))
  }
  if (ci_lower <= 1 && ci_upper >= 1) {
    e_ci <- 1
  } else if (est < 1) {
    e_ci <- if (ci_upper < 1) 1/ci_upper + sqrt((1/ci_upper)*((1/ci_upper)-1)) else 1
  } else {
    e_ci <- if (ci_lower > 1) ci_lower + sqrt(ci_lower*(ci_lower-1)) else 1
  }
  return(list(E_value = e_point, E_value_CI = e_ci))
}
rr1 <- sqrt(res1$or); rr1_l <- sqrt(res1$ci_lower); rr1_u <- sqrt(res1$ci_upper)
rr2 <- sqrt(res2$or); rr2_l <- sqrt(res2$ci_lower); rr2_u <- sqrt(res2$ci_upper)
e1 <- calc_e_value(rr1, rr1_l, rr1_u)
e2 <- calc_e_value(rr2, rr2_l, rr2_u)
if (has_sbp && !is.null(res3)) {
  rr3 <- sqrt(res3$or); rr3_l <- sqrt(res3$ci_lower); rr3_u <- sqrt(res3$ci_upper)
  e3 <- calc_e_value(rr3, rr3_l, rr3_u)
}
cat("\n=== E-values ===\n")
cat(sprintf("Model 1: E = %.3f (CI: %.3f)\n", e1$E_value, e1$E_value_CI))
cat(sprintf("Model 2: E = %.3f (CI: %.3f)\n", e2$E_value, e2$E_value_CI))
cat(sprintf("Model 3: E = %.3f (CI: %.3f)\n", e3$E_value, e3$E_value_CI))

# E-values for categorical analysis (<50 vs >=50)
rr1_cat <- sqrt(res1_cat$or); rr1_cat_l <- sqrt(res1_cat$ci_lower); rr1_cat_u <- sqrt(res1_cat$ci_upper)
rr2_cat <- sqrt(res2_cat$or); rr2_cat_l <- sqrt(res2_cat$ci_lower); rr2_cat_u <- sqrt(res2_cat$ci_upper)
e1_cat <- calc_e_value(rr1_cat, rr1_cat_l, rr1_cat_u)
e2_cat <- calc_e_value(rr2_cat, rr2_cat_l, rr2_cat_u)
if (has_sbp && !is.null(res3_cat)) {
  rr3_cat <- sqrt(res3_cat$or); rr3_cat_l <- sqrt(res3_cat$ci_lower); rr3_cat_u <- sqrt(res3_cat$ci_upper)
  e3_cat <- calc_e_value(rr3_cat, rr3_cat_l, rr3_cat_u)
}
cat("\n=== E-values (Categorical: <50 vs >=50) ===\n")
cat(sprintf("Model 1c: E = %.3f (CI: %.3f)\n", e1_cat$E_value, e1_cat$E_value_CI))
cat(sprintf("Model 2c: E = %.3f (CI: %.3f)\n", e2_cat$E_value, e2_cat$E_value_CI))
cat(sprintf("Model 3c: E = %.3f (CI: %.3f)\n", e3_cat$E_value, e3_cat$E_value_CI))

# Interpretive sentence for E-value
cat("\nInterpretation: An E-value of X means that an unmeasured confounder would need to be associated\n")
cat("with both 25(OH)D and mRS by a risk ratio of at least X (above and beyond measured confounders)\n")
cat("to explain away the observed association.\n")

# ============================================================================
# 11. Sensitivity analyses
# ============================================================================
# Strategy: All sensitivity analyses use the SAME complete-case subset as the
# primary analysis (Model 3), with the SAME adjustment set (age + gender + SBP
# + log_followup). Each analysis varies EXACTLY ONE assumption to test
# robustness. Two categories:
#   A. Analytical-method sensitivity: binary logistic, seasonal
#   B. Follow-up-time sensitivity: functional form (linear-log / linear-raw / RCS)
#      and removal of follow-up adjustment

# Build adjustment-set string (Model 3 baseline)
adj_base <- paste0(age_col, " + ", gender_col)
if (has_sbp) adj_base <- paste0(adj_base, " + ", sbp_var)
adj_full <- paste0(adj_base, " + log_followup")  # with follow-up time

# Use the complete-case data (already built in Section 6, same as primary)
data_sens <- data
cat(sprintf("\nSensitivity analysis uses primary complete-case subset: N = %d\n", nrow(data_sens)))

# Also create binary outcome for logistic regression
data_sens$unfavorable <- ifelse(data_sens[[mrs_col]] > 2, 1, 0)

# ---------------------------------------------------------------------------
# Category A: Analytical-method sensitivity
# ---------------------------------------------------------------------------

# 11.1 Binary logistic regression (mRS ≤2 vs ＞2)
cat("\n--- Sensitivity Analysis 1: Binary Logistic Regression (mRS ≤2 vs ＞2) ---\n")
model_logit <- glm(
  as.formula(paste0("unfavorable ~ vitd_per10 + ", adj_full)),
  family = binomial(link = "logit"),
  data = data_sens
)
logit_or <- exp(coef(model_logit)["vitd_per10"])
logit_ci <- exp(confint.default(model_logit)["vitd_per10", ])
logit_p <- summary(model_logit)$coefficients["vitd_per10", 4]
cat(sprintf("Binary logistic: OR = %.3f (%.3f-%.3f), P = %.4f\n",
            logit_or, logit_ci[1], logit_ci[2], logit_p))

# 11.2 Seasonal adjustment (admission period as additional covariate)
cat("\n--- Sensitivity Analysis 2: Seasonal Adjustment ---\n")
admission_col <- resolved_cat[["admission.period"]]
res_season <- NULL
if (!is.null(admission_col) && admission_col %in% colnames(data_sens)) {
  model_season <- polr(
    as.formula(paste0("mRS_ordered ~ vitd_per10 + ", adj_full, " + ", admission_col)),
    data = data_sens, method = "logistic", Hess = TRUE
  )
  res_season <- extract_polr_or(model_season, "vitd_per10")
  cat(sprintf("Seasonal adjustment: OR = %.3f (%.3f-%.3f), P = %.4f\n",
              res_season$or, res_season$ci_lower, res_season$ci_upper, res_season$p_value))
} else {
  cat("admission.period column not found, skipped.\n")
}

# ---------------------------------------------------------------------------
# Category B: Follow-up-time sensitivity
# ---------------------------------------------------------------------------

# 11.3 Functional form of follow-up time
#     Two mutually exclusive forms, all with Model 3 adjustment set:
#       (a) Linear, raw scale        — tests log transformation assumption
#       (b) RCS (3 knots)            — tests linearity assumption
cat("\n--- Sensitivity Analysis 3: Functional Form of Follow-up Time ---\n")
cat("    (all with Model 3 adjustment set: age + gender + SBP)\n\n")

# (a) Linear, raw scale
cat("\n(b) Linear, raw scale:\n")
data_sens$followup_raw <- data_sens[[followup_col]]
model_fu_raw <- polr(
  as.formula(paste0("mRS_ordered ~ vitd_per10 + ", adj_base, " + followup_raw")),
  data = data_sens, method = "logistic", Hess = TRUE
)
res_fu_raw <- extract_polr_or(model_fu_raw, "vitd_per10")
cat(sprintf("    OR = %.3f (%.3f-%.3f), P = %.4f\n",
            res_fu_raw$or, res_fu_raw$ci_lower, res_fu_raw$ci_upper, res_fu_raw$p_value))

# (b) RCS (3 knots) — tests nonlinearity
cat("\n(c) Restricted cubic spline (3 knots):\n")
model_fu_rcs <- polr(
  as.formula(paste0("mRS_ordered ~ vitd_per10 + ", adj_base, " + rcs(followup_raw, 3)")),
  data = data_sens, method = "logistic", Hess = TRUE
)
res_fu_rcs <- extract_polr_or(model_fu_rcs, "vitd_per10")
cat(sprintf("    OR = %.3f (%.3f-%.3f), P = %.4f\n",
            res_fu_rcs$or, res_fu_rcs$ci_lower, res_fu_rcs$ci_upper, res_fu_rcs$p_value))

# 11.4 Without follow-up time adjustment
#      Tests whether follow-up time is a material confounder
cat("\n--- Sensitivity Analysis 4: Without Follow-up Time Adjustment ---\n")
model_nofollowup <- polr(
  as.formula(paste0("mRS_ordered ~ vitd_per10 + ", adj_base)),
  data = data_sens, method = "logistic", Hess = TRUE
)
res_nofollowup <- extract_polr_or(model_nofollowup, "vitd_per10")
cat(sprintf("Without follow-up time: OR = %.3f (%.3f-%.3f), P = %.4f\n",
            res_nofollowup$or, res_nofollowup$ci_lower, res_nofollowup$ci_upper, res_nofollowup$p_value))

# ============================================================================
# 12. Interaction tests (effect modification) - exploratory
#     Updated: base model now includes SBP (consistent with Model 3)
# ============================================================================
cat("\n=== Interaction Tests (Effect Modification) ===\n")

# Base formula without interaction (uses Model 3 adjustment set: age + gender + SBP + log_followup)
base_formula_str <- paste0("mRS_ordered ~ vitd_per10 + ", age_col, " + ", gender_col, " + ", sbp_var, " + log_followup")

# 12.1 VitD × Gender
model_int_gender <- polr(
  as.formula(paste0("mRS_ordered ~ vitd_per10 * ", gender_col, " + ", age_col, " + ", sbp_var, " + log_followup")),
  data = data, method = "logistic", Hess = TRUE
)
model_base_gender <- polr(
  as.formula(base_formula_str),
  data = data, method = "logistic", Hess = TRUE
)
lrt_gender <- anova(model_base_gender, model_int_gender)
p_gender <- lrt_gender$`Pr(Chi)`[2]
lr_gender <- lrt_gender$`LR stat.`[2]

cat("\nVitD × Gender interaction:\n")
print(lrt_gender)

# 12.2 VitD × Age (continuous)
model_int_age <- polr(
  as.formula(paste0("mRS_ordered ~ vitd_per10 * ", age_col, " + ", gender_col, " + ", sbp_var, " + log_followup")),
  data = data, method = "logistic", Hess = TRUE
)
model_base_age <- polr(
  as.formula(base_formula_str),
  data = data, method = "logistic", Hess = TRUE
)
lrt_age <- anova(model_base_age, model_int_age)
p_age <- lrt_age$`Pr(Chi)`[2]
lr_age <- lrt_age$`LR stat.`[2]

cat("\nVitD × Age interaction:\n")
print(lrt_age)

# --- Sensitivity analyses combined table (including E-values) ---
sens_list <- list()

# Helper to compute E-value for a sensitivity result
add_sens_row <- function(name, or_val, ci_low, ci_up, p_val) {
  rr_val <- sqrt(or_val)
  rr_low <- sqrt(ci_low)
  rr_up  <- sqrt(ci_up)
  ev <- calc_e_value(rr_val, rr_low, rr_up)
  c(name, or_val, ci_low, ci_up, p_val, ev$E_value, ev$E_value_CI)
}

# Category A: Analytical-method sensitivity
if (exists("logit_or")) sens_list[[length(sens_list)+1]] <- add_sens_row("A1. Binary Logistic (mRS ≤2 vs ＞2)", logit_or, logit_ci[1], logit_ci[2], logit_p)
if (exists("res_season") && !is.null(res_season)) sens_list[[length(sens_list)+1]] <- add_sens_row("A2. Seasonal Adjustment", res_season$or, res_season$ci_lower, res_season$ci_upper, res_season$p_value)
# Category B: Follow-up-time sensitivity
if (exists("res_fu_raw")) sens_list[[length(sens_list)+1]] <- add_sens_row("B1. Follow-up linear (raw scale)", res_fu_raw$or, res_fu_raw$ci_lower, res_fu_raw$ci_upper, res_fu_raw$p_value)
if (exists("res_fu_rcs")) sens_list[[length(sens_list)+1]] <- add_sens_row("B2. Follow-up RCS (3 knots)", res_fu_rcs$or, res_fu_rcs$ci_lower, res_fu_rcs$ci_upper, res_fu_rcs$p_value)
if (exists("res_nofollowup")) sens_list[[length(sens_list)+1]] <- add_sens_row("B3. Without follow-up adjustment", res_nofollowup$or, res_nofollowup$ci_lower, res_nofollowup$ci_upper, res_nofollowup$p_value)

if (length(sens_list) > 0) {
  sens_table <- as.data.frame(do.call(rbind, sens_list), stringsAsFactors = FALSE)
  colnames(sens_table) <- c("Analysis", "OR", "CI_lower", "CI_upper", "P_value", "E_value", "E_value_CI")
  for (col_i in c("OR","CI_lower","CI_upper","P_value","E_value","E_value_CI")) {
    sens_table[[col_i]] <- as.numeric(sens_table[[col_i]])
  }
  write.csv(sens_table, file.path(output_dir, "sensitivity_analyses.csv"), row.names = FALSE)
  cat("Sensitivity analyses saved (with E-values).\n")
} else {
  cat("No sensitivity results available to save.\n")
}

# ============================================================================
# 13. Export results and generate tables/figures
# ============================================================================
# ---- Continuous analysis results (per 10 nmol/L) ----
results_table_cont <- data.frame(
  Analysis = "Continuous (per 10 nmol/L)",
  Model = c("Model 1 (Unadjusted)", "Model 2 (Age + Gender + Follow-up)"),
  OR = round(c(res1$or, res2$or), 3),
  CI_lower = round(c(res1$ci_lower, res2$ci_lower), 3),
  CI_upper = round(c(res1$ci_upper, res2$ci_upper), 3),
  P_value = c(res1$p_value, res2$p_value),
  E_value = round(c(e1$E_value, e2$E_value), 3),
  E_value_CI = round(c(e1$E_value_CI, e2$E_value_CI), 3),
  stringsAsFactors = FALSE
)
if (has_sbp && !is.null(res3)) {
  results_table_cont <- rbind(results_table_cont, data.frame(
    Analysis = "Continuous (per 10 nmol/L)",
    Model = "Model 3 (Fully adjusted)",
    OR = round(res3$or, 3),
    CI_lower = round(res3$ci_lower, 3),
    CI_upper = round(res3$ci_upper, 3),
    P_value = res3$p_value,
    E_value = round(e3$E_value, 3),
    E_value_CI = round(e3$E_value_CI, 3),
    stringsAsFactors = FALSE
  ))
}

# ---- Categorical analysis results (<50 vs >=50 nmol/L, >=50 as reference) ----
results_table_cat <- data.frame(
  Analysis = "Categorical (<50 vs >=50 nmol/L)",
  Model = c("Model 1 (Unadjusted)", "Model 2 (Age + Gender + Follow-up)"),
  OR = round(c(res1_cat$or, res2_cat$or), 3),
  CI_lower = round(c(res1_cat$ci_lower, res2_cat$ci_lower), 3),
  CI_upper = round(c(res1_cat$ci_upper, res2_cat$ci_upper), 3),
  P_value = c(res1_cat$p_value, res2_cat$p_value),
  E_value = round(c(e1_cat$E_value, e2_cat$E_value), 3),
  E_value_CI = round(c(e1_cat$E_value_CI, e2_cat$E_value_CI), 3),
  stringsAsFactors = FALSE
)
if (has_sbp && !is.null(res3_cat)) {
  results_table_cat <- rbind(results_table_cat, data.frame(
    Analysis = "Categorical (<50 vs >=50 nmol/L)",
    Model = "Model 3 (Fully adjusted)",
    OR = round(res3_cat$or, 3),
    CI_lower = round(res3_cat$ci_lower, 3),
    CI_upper = round(res3_cat$ci_upper, 3),
    P_value = res3_cat$p_value,
    E_value = round(e3_cat$E_value, 3),
    E_value_CI = round(e3_cat$E_value_CI, 3),
    stringsAsFactors = FALSE
  ))
}

# Combine for export to main results file
results_table <- rbind(results_table_cont, results_table_cat)
write.csv(results_table, file.path(output_dir, "ordinal_logistic_results.csv"), row.names = FALSE)

# Forest plot
# --- 13a. Primary analysis forest plot ---
cat("\n=== Generating Primary Forest Plot ===\n")

tryCatch({
  n_models <- sum(!is.na(results_table_cont$OR))
  
  fig_width_mm  <- 180
  fig_height_mm <- 44 + 34 * n_models   # ~146 mm for 3 models
  
  tiff(file.path(output_dir, "forest_plot.tiff"),
       width = fig_width_mm, height = fig_height_mm,
       units = "mm", res = 400,
       compression = "lzw", type = "cairo")
  
  par(family = "sans",
      mar = c(4.2, 12, 2.5, 1.2),
      mgp = c(2.4, 0.7, 0),
      xpd = FALSE)
  
  or_vals <- results_table_cont$OR
  ci_l    <- results_table_cont$CI_lower
  ci_u    <- results_table_cont$CI_upper
  
  model_names <- c("Model 1 (Unadjusted)",
                   "Model 2 (Age+Gender+Follow-up)",
                   "Model 3 (Fully adjusted)")
  
  x_min <- floor(min(ci_l, na.rm = TRUE) * 10) / 10
  x_max <- ceiling(max(ci_u, na.rm = TRUE) * 20) / 20
  if (x_min < 0.3) x_min <- 0.3
  if (x_max < 1.2) x_max <- 1.2
  
  y_pos <- n_models:1
  
  plot(NA, NA,
       xlim = c(x_min, x_max), ylim = c(0.5, n_models + 0.5),
       xlab = "OR (95% CI) per 10 nmol/L 25(OH)D",
       ylab = "", yaxt = "n", bty = "l")
  abline(v = 1, lty = 2, col = "grey60", lwd = 1.2)
  
  for (i in 1:n_models) {
    lines(c(ci_l[i], ci_u[i]), c(y_pos[i], y_pos[i]), lwd = 2.5, col = "#1F4E79")
    points(or_vals[i], y_pos[i], pch = 18, cex = 1.5, col = "#1F4E79")
  }
  
  axis(2, at = y_pos, labels = model_names[1:n_models],
       las = 1, cex.axis = 0.76, tick = FALSE, line = -0.5, font = 1)
  
  for (i in 1:n_models) {
    lab <- sprintf("%.2f (%.2f–%.2f)", or_vals[i], ci_l[i], ci_u[i])
    text(x_max * 1.03, y_pos[i], lab, cex = 0.73, adj = 0, font = 1)
  }
  
  mtext("Primary analysis – ordinal logistic regression",
        side = 3, line = 0.5, adj = 0, cex = 0.84, font = 2)
  
  dev.off()
  cat("Primary forest plot saved: forest_plot.tiff\n")
}, error = function(e) {
  if (dev.cur() > 1) dev.off()   # safety: never leave a device open
  cat("[WARNING] Primary forest plot failed:", e$message, "\n")
  cat("Continuing; numeric results were still saved to CSV/Excel.\n")
}
)

# Read sensitivity CSV (should exist from Section 14 later, but we build from sens_table if present)
# We'll use the in-memory sens_table if available, otherwise read file
if (exists("sens_table") && nrow(sens_table) > 0) {
  sens_forest <- sens_table
} else {
  sens_csv <- file.path(output_dir, "sensitivity_analyses.csv")
  if (file.exists(sens_csv)) {
    sens_forest <- read.csv(sens_csv, stringsAsFactors = FALSE)
  } else {
    sens_forest <- NULL
  }
}

if (!is.null(sens_forest) && nrow(sens_forest) > 0) {
  tryCatch({
    
    # Insert Model 3 as anchor row (only if Model 3 was fitted)
    if (has_sbp && !is.null(res3)) {
      model3_row <- data.frame(
        Analysis = "Primary: Model 3 (fully adjusted)",
        OR = round(res3$or, 3),
        CI_lower = round(res3$ci_lower, 3),
        CI_upper = round(res3$ci_upper, 3),
        P_value = res3$p_value,
        E_value = round(e3$E_value, 3),
        E_value_CI = round(e3$E_value_CI, 3),
        stringsAsFactors = FALSE
      )
      model3_row <- model3_row[, colnames(sens_forest)]
      forest_df <- rbind(model3_row, sens_forest)
      cat("Included Model 3 anchor row in sensitivity forest plot.\n")
    } else {
      forest_df <- sens_forest
      cat("Model 3 unavailable (no SBP); plotting sensitivity rows only.\n")
    }
    
    # --- 13b. Sensitivity analysis forest plot ---
    cat("\n=== Generating Sensitivity Forest Plot ===\n")
    
    clean_label <- function(s) {
      s <- gsub("＞", ">",  s, useBytes = TRUE)
      s <- sub("^[AB]\\d+\\.\\s*", "", s)
      s
    }
    forest_df$Analysis <- sapply(forest_df$Analysis, clean_label)
    
    n_rows <- nrow(forest_df)
    
    fig_width_mm  <- 180
    fig_height_mm <- 42 + 22 * n_rows
    
    tiff(file.path(output_dir, "Fig_sensitivity_forest.tiff"),
         width = fig_width_mm, height = fig_height_mm,
         units = "mm", res = 400,
         compression = "lzw", type = "cairo",
         bg = "white")
    
    par(family = "sans",
        mar = c(4.2, 13, 4.0, 8),
        mgp = c(2.5, 0.7, 0),
        xpd = NA)
    
    xlims     <- range(c(forest_df$CI_lower, forest_df$CI_upper), na.rm = TRUE)
    x_min     <- max(0.3, floor(xlims[1] * 10) / 10)
    x_max_data <- min(1.2, ceiling(xlims[2] * 20) / 20)
    if (x_max_data < 1.0) x_max_data <- 1.0
    x_lab_max <- x_max_data + 0.25 * (x_max_data - x_min)
    
    y_pos <- n_rows:1
    plot(NA, NA,
         xlim = c(x_min, x_lab_max), ylim = c(0.5, n_rows + 0.5),
         xlab = "", ylab = "", yaxt = "n", bty = "l", xaxt = "n")
    segments(1, 0.5, 1, n_rows + 0.5, lty = 2, col = "grey50", lwd = 1)
    
    data_ticks <- pretty(c(x_min, x_max_data), 5)
    axis(1, at = data_ticks, cex.axis = 0.72, tick = FALSE, line = -0.3)
    
    for (i in 1:n_rows) {
      lines(c(forest_df$CI_lower[i], forest_df$CI_upper[i]),
            c(y_pos[i], y_pos[i]), lwd = 2, col = "#1F4E79")
      points(forest_df$OR[i], y_pos[i], pch = 18, cex = 1.2, col = "#1F4E79")
    }
    
    axis(2, at = y_pos, labels = forest_df$Analysis,
         las = 1, cex.axis = 0.72, tick = FALSE, line = -0.3, font = 1)
    
    for (i in 1:n_rows) {
      lab <- sprintf("%.2f (%.2f-%.2f)",
                     forest_df$OR[i], forest_df$CI_lower[i], forest_df$CI_upper[i])
      text(x_lab_max, y_pos[i], lab, cex = 0.70, adj = 0, font = 1)
    }
    
    mtext("Sensitivity Analyses for the Association Between Serum 25(OH)D\nand mRS After Hypertensive ICH",
          side = 3, line = 1.2, adj = 0.5, cex = 0.80, font = 2)
    mtext("Odds Ratio (95% CI) per 10 nmol/L 25(OH)D",
          side = 1, line = 1.8, cex = 0.72)
    
    dev.off()
    cat("Sensitivity forest plot saved: Fig_sensitivity_forest.tiff\n")
  }, error = function(e) {
    if (dev.cur() > 1) dev.off()
    cat("[WARNING] Sensitivity forest plot failed:", e$message, "\n")
    cat("Continuing; numeric sensitivity results were still saved to CSV.\n")
  })
  if (dev.cur() > 1) dev.off()   # safety: never leave a graphic device open
}

# ============================================================================
# 14. Save additional results to files
# ============================================================================
# --- PO assumption test results ---
po_results <- capture.output({
  cat("=== Brant Test ===\n")
  if (exists("brant_result") && !is.null(brant_result)) print(brant_result)
  cat("\n=== nominal_test ===\n")
  if (exists("nt") && !is.null(nt)) print(nt)
  cat("\n=== PPO Decision ===\n")
  if (po_violated) {
    cat(sprintf("PPO vs PO LR test: P = %.4f\n", p_ppo))
  } else {
    cat("vitd_per10 does not significantly violate PO; retain PO model.\n")
  }
})
writeLines(po_results, file.path(output_dir, "PO_assumption_check.txt"))

# --- Interaction tests ---
interaction_list <- list()
if (exists("p_gender") && exists("lr_gender")) {
  interaction_list[[length(interaction_list)+1]] <- c("VitD × Gender", lr_gender, 1, p_gender)
}
if (exists("p_age") && exists("lr_age")) {
  interaction_list[[length(interaction_list)+1]] <- c("VitD × Age", lr_age, 1, p_age)
}
if (length(interaction_list) > 0) {
  interaction_table <- as.data.frame(do.call(rbind, interaction_list), stringsAsFactors = FALSE)
  colnames(interaction_table) <- c("Interaction", "LR_stat", "df", "P_value")
  interaction_table$LR_stat <- as.numeric(interaction_table$LR_stat)
  interaction_table$df <- as.numeric(interaction_table$df)
  interaction_table$P_value <- as.numeric(interaction_table$P_value)
  write.csv(interaction_table, file.path(output_dir, "interaction_tests.csv"), row.names = FALSE)
  cat("Interaction results saved.\n")
} else {
  cat("No interaction results available to save.\n")
}

# --- Save model objects for reproducibility ---
saveRDS(list(model1 = model1, model2 = model2, model3 = if (has_sbp) model3 else NULL,
             model1_cat = model1_cat, model2_cat = model2_cat,
             model3_cat = if (has_sbp) model3_cat else NULL),
        file = file.path(output_dir, "primary_models.rds"))
cat("Primary model objects saved (continuous + categorical).\n")

cat("\nAll additional results processing complete.\n")

# ============================================================================
# 15. Session info & cleanly close all sinks
# ============================================================================
# Write sessionInfo() to its own file, then close that sink.
sink(file.path(output_dir, "sessionInfo.txt"))
print(sessionInfo())
sink()                              # close the sessionInfo sink

# Close the main console-output sink opened in Section 2 (if still open)
if (sink.number() > 0) sink()

cat("\n========== ALL ANALYSES COMPLETE ==========\n")
cat("Files saved to:", output_dir, "\n")

# ============================================================================
# 16. Output manifest (helps reviewers locate every generated file)
# ============================================================================
out_files <- sort(list.files(output_dir, full.names = FALSE))
manifest <- c(
  "Output files produced by Allanalysis_SCI.R:",
  "",
  sprintf("%-38s %12s", "File", "Size (KB)"),
  sprintf("%-38s %12s", "----", "--------")
)
for (f in out_files) {
  sz <- round(file.size(file.path(output_dir, f)) / 1024, 1)
  manifest <- c(manifest, sprintf("%-38s %12s", f, sz))
}
writeLines(manifest, file.path(output_dir, "99_output_manifest.txt"))
cat("Output manifest written -> output/99_output_manifest.txt\n")
cat("TOTAL output files:", length(out_files), "\n")