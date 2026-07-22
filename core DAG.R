# ---- Project paths (override PROJECT_DIR only if running from elsewhere) ----
PROJECT_DIR <- getwd()                        # RStudio project root
DATA_DIR    <- file.path(PROJECT_DIR, "data", "clean")
OUTPUT_DIR  <- file.path(PROJECT_DIR, "output")

# ---- Reproducibility settings ----
CRAN_REPO  <- "https://cloud.r-project.org/"
options(repos = c(CRAN = CRAN_REPO))

# ---- Global error handler: capture the FIRST error with full traceback ----
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

# ---- Output directory (flat, per submission spec) ----
output_dir <- OUTPUT_DIR
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
  cat("Created output directory:", output_dir, "\n")
}

# ---- Required packages (auto-install if missing) ----
required_pkgs <- c("tidyverse", "tidygraph", "ggraph")
for (pkg in required_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, repos = CRAN_REPO)
  }
}
library(tidyverse)
library(tidygraph)
library(ggraph)

# Register Arial only on Windows (harmless no-op / avoids error on Linux CI)
if (.Platform$OS.type == "windows") {
  windowsFonts(Arial = windowsFont("Arial"))
}

# =====================================================
# 1. Node table (core causal structure only)
# Time-ordered layout: T0 (ancestors) -> T1 (exposure) -> T2 (outcome) -> T3 (selection)
# =====================================================
nodes <- tibble::tribble(
  ~name,                          ~x,    ~y,    ~time_layer,
  # T0: Long-term characteristics (ancestors)
  "Age",                          0.2,   0.85,  "T0",
  "Gender",                        0.4,   0.85,  "T0",
  "Smoking",                       0.6,   0.85,  "T0",
  "Socioeconomic status",          0.7,   0.85,  "T0",
  # T1: Exposure and immediate determinants
  "Sun exposure",                 0.3,   0.65,  "T1",
  "BMI",                          0.5,   0.65,  "T1",
  "25(OH)D",                      0.5,   0.45,  "T1",  # Exposure
  # T2: Outcome and clinical pathway
  "Blood pressure",               0.7,   0.65,  "T2",
  "mRS",                          0.5,   0.25,  "T2",  # Outcome
  # T3: Selection bias mechanism
  "Selection",                    0.5,   0.08,  "T3"
)

# =====================================================
# 1b. Node position overlap check (run BEFORE plotting)
# =====================================================
check_node_overlap <- function(nodes_df,
                               plot_w_in = 7, plot_h_in = 7,
                               min_gap_x = 0.10, min_gap_y = 0.06,
                               node_diam_mm = 18) {
  node_r_x <- (node_diam_mm / 2) / (plot_w_in * 25.4)
  node_r_y <- (node_diam_mm / 2) / (plot_h_in * 25.4)
  safe_dist <- max(node_r_x * 2 + 0.02, min_gap_x)
  
  n <- nrow(nodes_df)
  issues <- character(0)
  
  for (y_val in unique(nodes_df$y)) {
    idx <- which(nodes_df$y == y_val)
    if (length(idx) < 2) next
    ord <- order(nodes_df$x[idx])
    xs <- nodes_df$x[idx[ord]]
    ns <- nodes_df$name[idx[ord]]
    for (i in 2:length(xs)) {
      gap <- xs[i] - xs[i - 1]
      if (gap < safe_dist) {
        issues <- c(issues, sprintf(
          "  ⚠ 同行重叠: '%s' ↔ '%s'  (y=%.2f, Δx=%.3f < 安全阈值 %.2f)",
          ns[i - 1], ns[i], y_val, gap, safe_dist
        ))
      }
    }
  }
  
  for (i in 1:(n - 1)) {
    for (j in (i + 1):n) {
      dx <- abs(nodes_df$x[i] - nodes_df$x[j])
      dy <- abs(nodes_df$y[i] - nodes_df$y[j])
      if (dy > 0 && dx < safe_dist && dy < min_gap_y) {
        issues <- c(issues, sprintf(
          "  ⚠ 跨层重叠: '%s'(%.2f,%.2f) ↔ '%s'(%.2f,%.2f)  (dx=%.3f, dy=%.3f)",
          nodes_df$name[i], nodes_df$x[i], nodes_df$y[i],
          nodes_df$name[j], nodes_df$x[j], nodes_df$y[j], dx, dy
        ))
      }
    }
  }
  
  if (length(issues) == 0) {
    cat("  ✅ 所有节点位置通过重叠检测！\n\n")
  } else {
    cat("  ❌ 发现重叠风险：\n")
    cat(paste(issues, collapse = "\n"), "\n\n")
  }
  invisible(list(pass = length(issues) == 0, issues = issues))
}

cat("\n========== 节点位置重叠检测 ==========")
check_node_overlap(nodes)
cat("========================================\n")

# =====================================================
# 2. Edge table (core causal relationships)
# =====================================================
edges <- tibble::tribble(
  ~from, ~to,
  # T0 -> T1 (ancestors influence exposure)
  "Age", "25(OH)D",
  "Age", "Blood pressure",
  "Gender", "25(OH)D",
  "Smoking", "Blood pressure",
  "Socioeconomic status", "25(OH)D",
  "Socioeconomic status", "mRS",
  # T1 determinants -> Exposure
  "Sun exposure", "25(OH)D",
  "BMI", "25(OH)D",
  "BMI", "Blood pressure",
  # Exposure -> Outcome (main hypothesis)
  "25(OH)D", "mRS",
  # T2: Clinical pathway
  "Blood pressure", "mRS",
  # T3: Selection bias (collider)
  "mRS", "Selection",
  "Age", "Selection",
  "Blood pressure", "Selection"
)

# =====================================================
# 3. Build graph object
# =====================================================
dag_graph <- tbl_graph(
  nodes = nodes,
  edges = edges,
  directed = TRUE
)

# =====================================================
# 4. Node attributes (STROBE-compliant styling)
# =====================================================
dag_graph <- dag_graph %>%
  activate(nodes) %>%
  mutate(
    node_type = case_when(
      name == "25(OH)D" ~ "exposure",
      name == "mRS" ~ "outcome",
      name == "Selection" ~ "selection",
      TRUE ~ "confounder"
    ),
    is_selection = name == "Selection",
    # STROBE-compliant colors
    node_color = case_when(
      node_type == "exposure" ~ "#E69F00",  # Orange/gold for exposure
      node_type == "outcome" ~ "#0072B5",   # Blue for outcome
      node_type == "selection" ~ "#D55E00",  # Red-orange for selection bias
      TRUE ~ "#999999"                      # Gray for confounders
    ),
    node_fill = case_when(
      node_type == "exposure" ~ "#FFFACD",  # Light yellow
      node_type == "outcome" ~ "#ADD8E6",   # Light blue
      node_type == "selection" ~ "#FFCCCB",  # Light red (selection bias)
      TRUE ~ "#F0F0F0"                     # Light gray
    ),
    node_shape = case_when(
      node_type == "selection" ~ 23,  # Diamond for selection (bias mechanism)
      TRUE ~ 21                         # Circle for others
    ),
    node_size = case_when(
      node_type == "exposure" ~ 22,
      node_type == "outcome" ~ 22,
      TRUE ~ 18
    ),
    node_stroke = case_when(
      node_type == "selection" ~ 2.5,  # Thicker border for selection
      TRUE ~ 1.2
    ),
    # Time layer for background coloring
    time_layer = factor(time_layer, levels = c("T0", "T1", "T2", "T3"))
  )

# =====================================================
# 5. Plot DAG (STROBE-compliant, clean layout)
# =====================================================

# Apply Frontiers-compliant theme (font size ≥8pt, clear lines)
# Note: theme_void() sets plot.background to element_blank() (transparent).
# This causes TIFF output to retain an alpha channel, which image viewers
# render as a checkerboard grid. Explicitly force a white background so
# both PDF and TIFF render with an opaque white canvas (Frontiers requirement).
frontiers_theme <- theme(
  plot.title = element_text(hjust = 0.5, face = "bold", size = 14),
  plot.subtitle = element_text(hjust = 0.5, size = 12),
  plot.margin = margin(20, 40, 40, 20),
  plot.caption = element_text(hjust = 0, size = 10, face = "italic", lineheight = 1.2),
  text = element_text(family = "Arial"),  # Ensure Arial font
  # Force opaque white background (overrides theme_void()'s transparent background)
  plot.background = element_rect(fill = "white", colour = NA),
  panel.background = element_rect(fill = "white", colour = NA)
)

x_vec <- nodes$x
y_vec <- nodes$y

p <- ggraph(dag_graph, layout = "manual", x = x_vec, y = y_vec) +
  
  # Background rectangles for time layers (optional, for clarity)
  # T0: Ancestors, T1: Exposure determinants, T2: Outcome, T3: Selection
  
  # Draw edges
  geom_edge_link(
    colour = "grey30",
    alpha = 0.7,
    arrow = arrow(length = unit(3, "mm")),
    end_cap = circle(8, "mm"),
    start_cap = circle(8, "mm")
  ) +
  
  # Draw nodes
  geom_node_point(
    aes(
      colour = I(node_color),
      fill = I(node_fill),
      shape = I(node_shape),
      size = I(node_size),
      stroke = I(node_stroke)
    )
  ) +
  
  # Draw node labels
  geom_node_text(
    aes(label = name),
    size = 3.5,
    repel = FALSE,  # Manual layout, no repel needed
    nudge_y = 0.03,
    fontface = "bold"
  ) +
  
  # Selection node description (placed below, dark color for contrast)
  annotate("text",
           x = 0.5, y = -0.02,
           label = "Selection\n(index event & attrition bias)",
           size = 2.5,
           fontface = "italic",
           color = "#5A5A5A",
           hjust = 0.5,
           lineheight = 0.9
  ) +
  
  # Title and theme
  coord_cartesian(clip = "off") +
  theme_void() +
  frontiers_theme +  # Apply Frontiers-compliant theme
  labs(
    title = "Directed Acyclic Graph (DAG) of 25(OH)D and mRS",
    subtitle = "Core causal structure with selection bias mechanism",
    caption = "Nodes: Exposure (gold), Outcome (blue), Confounders (gray), Selection bias (red diamond).\nMinimal sufficient adjustment set: {Age, Gender, Blood pressure}"
  )

print(p)

# ---- Data-provenance / run log ----
src_file <- file.path(DATA_DIR, "final_ich_cohort.xlsx")
src_note <- if (file.exists(src_file)) {
  paste0("Source data:   ", src_file,
         "  (MD5: ", as.character(tools::md5sum(src_file)),
         ", ", round(file.size(src_file) / 1024, 1), " KB)")
} else {
  paste0("Source data:   ", src_file,
         "  [NOT FOUND — DAG structure is defined in-script]")
}
run_info <- c(
  paste0("Script:        core_DAG.R"),
  paste0("Run timestamp:  ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste0("R version:      ", R.version$version.string),
  paste0("Platform:       ", R.version$platform),
  src_note,
  paste0("Output files:   core_DAG.pdf, core_DAG.tiff")
)
writeLines(run_info, file.path(output_dir, "00_run_info.txt"))
cat("Run info written -> output/00_run_info.txt\n")

# =====================================================
# 6. Save as high-resolution figure (Frontiers-compliant)
# =====================================================

# Output directory is fixed to OUTPUT_DIR (defined in the header scaffolding,
# defaults to <project_root>/output/). No interactive prompt is used.
pdf_file  <- file.path(output_dir, "core_DAG.pdf")
tiff_file <- file.path(output_dir, "core_DAG.tiff")

# Save as PDF (primary format for Frontiers)
ggsave(
  filename = pdf_file,
  plot = p,
  device = cairo_pdf,      # Use cairo device for font embedding
  width = 7,               # Frontiers double-column width: 180mm ≈ 7.09 inches
  height = 7,              # Square format
  units = "in",
  dpi = 300,               # Frontiers requires ≥300 DPI
  family = "Arial"         # Embed Arial font
)

# Save as TIFF (alternative format, also accepted by Frontiers)
ggsave(
  filename = tiff_file,
  plot = p,
  device = "tiff",
  width = 7,
  height = 7,
  units = "in",
  dpi = 300,
  compression = "lzw"    # LZW compression to reduce file size
)

message("Main DAG (STROBE-compliant) saved as:")
message(paste("  -", pdf_file, "(PDF, Frontiers-compliant)"))
message(paste("  -", tiff_file, "(TIFF, Frontiers-compliant)"))

# ---- Session info (reproducibility) ----
si_lines <- capture.output(sessionInfo())
writeLines(si_lines, file.path(output_dir, "sessionInfo.txt"))
cat("Session info written -> output/sessionInfo.txt\n")

# ---- Output manifest ----
out_files <- sort(list.files(output_dir, full.names = FALSE))
manifest <- c(
  "Output files produced by core_DAG.R:",
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