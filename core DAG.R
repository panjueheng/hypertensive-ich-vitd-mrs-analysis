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

# =====================================================
# 0. Scientific Reports / Nature Portfolio artwork settings
# =====================================================
# Build the figure at final printed size so that the point sizes below are the
# sizes that appear on the page.  Nature Portfolio final-artwork widths:
# single column 88 mm, double column 180 mm; this figure is double column.
# Text must be sans-serif (Arial or Helvetica) between 5 and 7 pt final size,
# and outlines between 0.25 and 1.5 pt.
FIG_W_MM   <- 180      # double-column width
FIG_H_MM   <- 160
PT_MM      <- 25.4 / 72           # 1 pt expressed in mm
LABEL_PT   <- 7                   # node labels: 7 pt at final size
LABEL_MM   <- LABEL_PT * PT_MM    # ggplot2 geom_text size is in mm
STROKE_PT  <- 1.3                 # node outline width (allowed 0.25-1.5 pt)
STROKE_SEL <- 1.45                # selection node, still within the limit
mm2in      <- function(x) x / 25.4

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
  "Sex",                        0.4,   0.85,  "T0",
  "Smoking",                       0.575, 0.85,  "T0",
  "Socioeconomic status",          0.700, 0.85,  "T0",
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
check_node_overlap(nodes,
                   plot_w_in = mm2in(FIG_W_MM),
                   plot_h_in = mm2in(FIG_H_MM))
cat("========================================\n")

# =====================================================
# 2. Edge table (core causal relationships)
# =====================================================
edges <- tibble::tribble(
  ~from, ~to,
  # T0 -> T1 (ancestors influence exposure)
  "Age", "25(OH)D",
  "Age", "Blood pressure",
  "Sex", "25(OH)D",
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
    # Outline width in mm; Nature Portfolio allows 0.25-1.5 pt.
    node_stroke = ifelse(node_type == "selection",
                         STROKE_SEL * PT_MM, STROKE_PT * PT_MM),
    # Time layer for background coloring
    time_layer = factor(time_layer, levels = c("T0", "T1", "T2", "T3"))
  )

# =====================================================
# 5. Plot DAG (STROBE-compliant, clean layout)
# =====================================================

# Scientific Reports house theme.  Note: theme_void() sets plot.background to
# element_blank() (transparent), which leaves an alpha channel in the TIFF that
# viewers render as a checkerboard grid, so an opaque white canvas is forced.
# The figure carries no title or legend: those live in the manuscript \u2019
# figure legends section, which is what the journal requires.
scirep_theme <- theme(
  plot.margin = margin(4, 12, 6, 4),
  text = element_text(family = "Arial"),
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
    # labels of the right-most nodes are right-aligned towards the node centre
    # so that they cannot run past the edge of the canvas
    aes(label = name, hjust = ifelse(x > 0.66, 1, 0.5)),
    size = LABEL_MM,   # 7 pt at final size
    repel = FALSE,  # Manual layout, no repel needed
    nudge_y = 0.03,
    fontface = "bold"
  ) +
  
  # Selection node description (placed below, dark color for contrast)
  annotate("text",
           x = 0.5, y = -0.02,
           label = "Selection\n(index event & attrition bias)",
           size = LABEL_MM,   # 7 pt at final size
           fontface = "italic",
           color = "#5A5A5A",
           hjust = 0.5,
           lineheight = 0.9
  ) +
  
  # Title and theme
  coord_cartesian(clip = "off") +
  theme_void() +
  scirep_theme

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
  paste0("Output files:   core_DAG.pdf, core_DAG.eps, core_DAG.tiff")
)
writeLines(run_info, file.path(output_dir, "00_run_info.txt"))
cat("Run info written -> output/00_run_info.txt\n")

# =====================================================
# 6. Save as high-resolution figure (Frontiers-compliant)
# =====================================================

# Output directory is fixed to OUTPUT_DIR (defined in the header scaffolding,
# defaults to <project_root>/output/). No interactive prompt is used.
pdf_file  <- file.path(output_dir, "core_DAG.pdf")
eps_file  <- file.path(output_dir, "core_DAG.eps")
tiff_file <- file.path(output_dir, "core_DAG.tiff")

# Vector output is the preferred format for line art and schematics.
ggsave(
  filename = pdf_file,
  plot = p,
  device = cairo_pdf,      # cairo device embeds the Arial outlines
  width = mm2in(FIG_W_MM), # 180 mm = double column
  height = mm2in(FIG_H_MM),
  units = "in",
  family = "Arial"
)

# EPS, the vector format named explicitly in the journal instructions.
tryCatch(
  ggsave(
    filename = eps_file,
    plot = p,
    device = function(filename, width, height, ...) {
      grDevices::cairo_ps(filename, width = width, height = height,
                         onefile = TRUE, family = "Arial", ...)
    },
    width = mm2in(FIG_W_MM),
    height = mm2in(FIG_H_MM),
    units = "in"
  ),
  error = function(e) warning("EPS not written: ", conditionMessage(e))
)

# Raster fallback at final size: 600 dpi, LZW compressed, RGB.
ggsave(
  filename = tiff_file,
  plot = p,
  device = "tiff",
  width = mm2in(FIG_W_MM),
  height = mm2in(FIG_H_MM),
  units = "in",
  dpi = 600,
  compression = "lzw"
)

message("Main DAG saved at 180 mm double-column width:")
message(paste("  -", pdf_file,  "(PDF, vector)"))
message(paste("  -", eps_file,  "(EPS, vector)"))
message(paste("  -", tiff_file, "(TIFF, 600 dpi, LZW)"))

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
