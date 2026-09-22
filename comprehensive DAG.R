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
# The figure is built at final printed size so the point sizes below are the
# sizes that appear on the page.  Double-column width is 180 mm; this DAG is
# node-dense, so the canvas is made taller than the printed width to keep the
# labels legible at 7 pt.  Every absolute dimension (node diameter, outline
# width, arrow length, end caps) is specified on this canvas, which is why the
# node diameters are smaller than on the old 12 x 10 inch canvas.
FIG_W_MM   <- 180
FIG_H_MM   <- 200
PT_MM      <- 25.4 / 72           # 1 pt expressed in mm
LABEL_PT   <- 7                   # node labels: 7 pt at final size
LABEL_MM   <- LABEL_PT * PT_MM    # ggplot2 geom_text size is in mm
STROKE_PT  <- 1.3                 # node outline (allowed 0.25-1.5 pt)
STROKE_SEL <- 1.45
NODE_MM    <- 10.5                # node diameter in mm on this canvas
NODE_SEL   <- 14
ARROW_MM   <- 2.5
CAP_MM     <- 6                   # edge trimmed this far from the node centre
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

# Register Arial only on Windows (harmless no-op / avoids error on Linux CI).
# Windows ships Arial system-wide but R needs explicit registration via
# windowsFonts(); on non-Windows the family="Arial" arg is simply ignored.
if (.Platform$OS.type == "windows") {
  windowsFonts(Arial = windowsFont("Arial"))
}

# =====================================================
# 1. Node table (coordinates exactly match original DAGitty layout)
# =====================================================
nodes <- tibble::tribble(
  ~name,                          ~x,    ~y,
  "25(OH)D",                      0.460, 1 - 0.376,
  "Admission season",             0.395, 1 - 0.182,
  "Alcohol consumption",          0.735, 1 - 0.124,
  "Anticoagulant/Antiplatelet use", 0.860, 1 - 0.400,
  "Blood pressure",               0.840, 1 - 0.265,
  "HDL-C",                        0.100, 1 - 0.560,
  "Hematoma volume",              0.781, 1 - 0.410,
  "Hemorrhage location",          0.810, 1 - 0.660,
  "Intraventricular extension",   0.790, 1 - 0.520,
  "LDL-C",                        0.120, 1 - 0.680,
  "Lost to follow-up",            0.730, 1 - 0.800,
  "Pre-stroke mRS",               0.660, 1 - 0.945,
  "Random plasma glucose",        0.358, 1 - 0.659,
  "Renal insufficiency",          0.920, 1 - 0.470,
  "Serum creatinine",            0.399, 1 - 0.920,
  "Socioeconomic status",         0.885, 1 - 0.122,
  "Stroke history",               0.910, 1 - 0.320,
  "Sun exposure",                 0.472, 1 - 0.133,
  "Surgical treatment",           0.810, 1 - 0.785,
  "Voluntary withdrawal",         0.915, 1 - 0.800,
  "ALT",                          0.200, 1 - 0.800,
  "AST",                          0.300, 1 - 0.810,
  "Age",                          0.137, 1 - 0.176,
  "BMI",                          0.720, 1 - 0.242,
  "GCS",                          0.539, 1 - 0.825,
  "GGT",                          0.100, 1 - 0.790,
  "Sex",                          0.298, 1 - 0.175,
  "Hemoglobin",                   0.120, 1 - 0.880,
  "Malignancy",                   0.900, 1 - 0.590,
  "NIHSS",                        0.642, 1 - 0.779,
  "Pregnancy",                    0.900, 1 - 0.710,
  "Selection",                    0.782, 1 - 0.910,
  "Smoking",                      0.609, 1 - 0.128,
  "TC",                           0.100, 1 - 0.320,
  "TG",                           0.100, 1 - 0.440,
  "mRS",                          0.465, 1 - 0.751
)

# =====================================================
# 2. Edge table (identical to original DAGitty arrows)
# =====================================================
edges <- tibble::tribble(
  ~from, ~to,
  "25(OH)D", "Selection",
  "25(OH)D", "mRS",
  "Admission season", "25(OH)D",
  "Alcohol consumption", "HDL-C",
  "Alcohol consumption", "LDL-C",
  "Alcohol consumption", "ALT",
  "Alcohol consumption", "AST",
  "Alcohol consumption", "GGT",
  "Alcohol consumption", "TG",
  "Alcohol consumption", "mRS",
  "Anticoagulant/Antiplatelet use", "Selection",
  "Anticoagulant/Antiplatelet use", "mRS",
  "Blood pressure", "Renal insufficiency",
  "Blood pressure", "Selection",
  "Blood pressure", "mRS",
  "Hematoma volume", "mRS",
  "Hemorrhage location", "mRS",
  "Intraventricular extension", "mRS",
  "Lost to follow-up", "Selection",
  "Pre-stroke mRS", "Selection",
  "Random plasma glucose", "mRS",
  "Renal insufficiency", "Selection",
  "Renal insufficiency", "mRS",
  "Serum creatinine", "Selection",
  "Serum creatinine", "mRS",
  "Socioeconomic status", "mRS",
  "Stroke history", "Selection",
  "Stroke history", "mRS",
  "Sun exposure", "25(OH)D",
  "Surgical treatment", "mRS",
  "Voluntary withdrawal", "Selection",
  "Age", "25(OH)D",
  "Age", "Random plasma glucose",
  "Age", "Selection",
  "Age", "TC",
  "Age", "mRS",
  "BMI", "25(OH)D",
  "BMI", "Blood pressure",
  "GCS", "mRS",
  "Sex", "25(OH)D",
  "Sex", "HDL-C",
  "Sex", "LDL-C",
  "Sex", "mRS",
  "Malignancy", "Selection",
  "Malignancy", "mRS",
  "NIHSS", "mRS",
  "Pregnancy", "Selection",
  "Smoking", "Blood pressure",
  "Smoking", "HDL-C",
  "Smoking", "LDL-C",
  "Smoking", "TC",
  "Smoking", "TG",
  "mRS", "Selection"
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
# 4. Node attributes
# Selection node color unified to RED to match Figure 1 (red diamond)
# =====================================================
dag_graph <- dag_graph %>%
  activate(nodes) %>%
  mutate(
    node_type = case_when(
      name == "25(OH)D" ~ "exposure",
      name == "mRS" ~ "outcome",
      name %in% c(
        "Alcohol consumption",
        "Socioeconomic status",
        "Sun exposure",
        "Smoking"
      ) ~ "latent",
      TRUE ~ "other"
    ),
    is_selection = name == "Selection",
    node_shape = ifelse(is_selection, 23, 21),
    node_color = case_when(
      is_selection ~ "#CC0000",        # RED border — unified with Figure 1
      node_type == "exposure" ~ "#FFBF00",
      node_type == "outcome" ~ "#0072B2",
      node_type == "latent" ~ "#999999",
      TRUE ~ "#000000"
    ),
    node_fill = case_when(
      is_selection ~ "#FFE0E0",        # pale red fill — unified with Figure 1
      node_type == "exposure" ~ "#FFFACD",
      node_type == "outcome" ~ "#ADD8E6",
      node_type == "latent" ~ "#FFFFFF",
      TRUE ~ "#F0F0F0"
    ),
    node_size = ifelse(is_selection, NODE_SEL, NODE_MM),
    # Outline width in mm; Nature Portfolio allows 0.25-1.5 pt.
    node_stroke = ifelse(is_selection, STROKE_SEL * PT_MM, STROKE_PT * PT_MM)
  )

# =====================================================
# 5. Plot DAG
# =====================================================
p <- ggraph(dag_graph, layout = "manual", x = x, y = y) +
  
  geom_edge_link(
    colour = "grey40",
    alpha = 0.6,
    arrow = arrow(length = unit(ARROW_MM, "mm")),
    end_cap = circle(CAP_MM, "mm"),
    start_cap = circle(CAP_MM, "mm")
  ) +
  
  geom_node_point(
    aes(
      colour = I(node_color),
      fill = I(node_fill),
      shape = I(node_shape),
      size = I(node_size),
      stroke = I(node_stroke)
    )
  ) +
  
  geom_node_text(
    aes(label = name),
    size = LABEL_MM,   # 7 pt at final size
    repel = TRUE,
    nudge_y = -0.045,
    segment.color = "grey45",
    segment.size = 0.35,     # ~1 pt, inside the 0.25-1.5 pt range
    segment.alpha = 0.8,
    box.padding = 0.012,
    point.padding = 0.008,
    force = 0.7,             # gentler repulsion: labels stay near their node
    fontface = "bold",
    max.overlaps = 100
  ) +
  
  coord_cartesian(clip = "off") +
  theme_void() +
  theme(
    legend.position = "none",
    plot.margin = margin(6, 6, 6, 6),
    text = element_text(family = "Arial"),
    # Force opaque white background (overrides theme_void()'s transparent background)
    plot.background = element_rect(fill = "white", colour = NA),
    panel.background = element_rect(fill = "white", colour = NA)
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
  paste0("Script:        comprehensived_DAG.R"),
  paste0("Run timestamp:  ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste0("R version:      ", R.version$version.string),
  paste0("Platform:       ", R.version$platform),
  src_note,
  paste0("Output files:   Figure_S1_comprehensive_DAG.pdf, ",
         "Figure_S1_comprehensive_DAG.eps, Figure_S1_comprehensive_DAG.tiff")
)
writeLines(run_info, file.path(output_dir, "00_run_info.txt"))
cat("Run info written -> output/00_run_info.txt\n")

# =====================================================
# 6. Save as high-resolution figure (PDF + TIFF)
# =====================================================

# Output directory is fixed to OUTPUT_DIR (defined in the header scaffolding,
# defaults to <project_root>/output/). No interactive prompt is used.
pdf_file  <- file.path(output_dir, "Figure_S1_comprehensive_DAG.pdf")
eps_file  <- file.path(output_dir, "Figure_S1_comprehensive_DAG.eps")
tiff_file <- file.path(output_dir, "Figure_S1_comprehensive_DAG.tiff")

# Vector output is the preferred format for line art and schematics.
ggsave(
  filename = pdf_file,
  plot = p,
  device = cairo_pdf,
  width = mm2in(FIG_W_MM),
  height = mm2in(FIG_H_MM),
  units = "in",
  family = "Arial"
)

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

message("Comprehensive DAG saved at 180 mm double-column width:")
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
  "Output files produced by comprehensived_DAG.R:",
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
