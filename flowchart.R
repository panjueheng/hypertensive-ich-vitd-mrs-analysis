library(grid)

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

# ---- Output file paths ----
out_png  <- file.path(output_dir, "flowchart.png")
out_pdf  <- file.path(output_dir, "flowchart.pdf")
out_tiff <- file.path(output_dir, "flowchart.tiff")

width_in  <- 12
height_in <- 10
dpi       <- 600

# --- Color scheme (Black & White) -------------------------------------------
COL_BG      <- "white"
COL_BOX     <- "black"
COL_TEXT    <- "black"
COL_EXC_BG  <- "grey95"
COL_ARROW   <- "black"

# --- Font sizes --------------------------------------------------------------
FS_TITLE     <- 14
FS_MAIN_N    <- 16
FS_EXC_HEAD  <- 13
FS_EXC_ITEM  <- 11
FS_FINAL_N   <- 16
FS_FOOTNOTE  <- 9

# --- Data --------------------------------------------------------------------
# Stage 1: spontaneous ICH
N_spontaneous <- 271

# Stage 1 exclusions (n = 94)
N_exc1 <- 94
exc1_reasons <- list(
  list(text = "Secondary causes of spontaneous ICH",  n = 87),
  list(text = "Transient stress-induced hypertension", n = 7)
)

# Stage 2: hypertensive ICH
N_hypertensive <- 177

# Stage 2 exclusions (n = 76)
N_exc2 <- 76
exc2_reasons <- list(
  list(text = "Age >80 years",                              n = 3),
  list(text = "Prior stroke",                              n = 6),
  list(text = "Pre-stroke mRS >2",                         n = 4),
  list(text = "Antiplatelet/anticoagulant use",            n = 7),
  list(text = "Severe renal insufficiency/dialysis",       n = 3),
  list(text = "Concurrent malignancy",                     n = 3),
  list(text = "Complicated cerebral infarction/rebleeding", n = 7),
  list(text = "Voluntary discharge/treatment abandonment", n = 6),
  list(text = "25-hydroxyvitamin D not examined",          n = 32),
  list(text = "Lost to follow-up",                         n = 5)
)

# Stage 3: final analysis cohort
N_final <- 101

# ---- Data-provenance / run log ----
src_file <- file.path(DATA_DIR, "final_ich_cohort.xlsx")
src_note <- if (file.exists(src_file)) {
  paste0("Source data:   ", src_file,
         "  (MD5: ", as.character(tools::md5sum(src_file)),
         ", ", round(file.size(src_file) / 1024, 1), " KB)")
} else {
  paste0("Source data:   ", src_file,
         "  [NOT FOUND — cohort counts below are hard-coded in-script]")
}
run_info <- c(
  paste0("Script:        flowchart.R"),
  paste0("Run timestamp:  ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste0("R version:      ", R.version$version.string),
  paste0("Platform:       ", R.version$platform),
  src_note,
  paste0("N_spontaneous:  ", N_spontaneous),
  paste0("N_hypertensive: ", N_hypertensive),
  paste0("N_final:        ", N_final)
)
writeLines(run_info, file.path(output_dir, "00_run_info.txt"))
cat("Run info written -> output/00_run_info.txt\n")

# --- Helper: draw rounded rectangle box -------------------------------------
draw_box <- function(x, y, width, height, label_lines, font_sizes,
                     fill = COL_BG, border = COL_BOX, lwd = 1.5,
                     text_color = COL_TEXT, hjust = 0.5, vjust = 0.5) {
  grid.roundrect(
    x = x, y = y,
    width = unit(width, "npc"), height = unit(height, "npc"),
    r = unit(0.06, "inches"),
    gp = gpar(fill = fill, col = border, lwd = lwd)
  )
  n_lines <- length(label_lines)
  if (n_lines == 1) {
    grid.text(label_lines[1], x = x, y = y,
              gp = gpar(fontsize = font_sizes[1], col = text_color,
                        fontface = "bold", fontfamily = "sans"),
              hjust = hjust, vjust = vjust)
  } else {
    line_spacing <- 0.04
    total_h <- (n_lines - 1) * line_spacing
    start_y <- y + total_h / 2
    for (i in seq_along(label_lines)) {
      yy <- start_y - (i - 1) * line_spacing
      face <- if (i == n_lines) "bold" else "plain"
      grid.text(label_lines[i], x = x, y = yy,
                gp = gpar(fontsize = font_sizes[i], col = text_color,
                          fontface = face, fontfamily = "sans"),
                hjust = hjust, vjust = vjust)
    }
  }
}

# --- Helper: draw arrow ------------------------------------------------------
draw_arrow <- function(x0, y0, x1, y1, lwd = 1.5) {
  grid.lines(x = c(x0, x1), y = c(y0, y1),
             arrow = arrow(length = unit(0.12, "inches"), type = "closed"),
             gp = gpar(col = COL_ARROW, lwd = lwd, fill = COL_ARROW))
}

# --- Helper: draw dashed connector -------------------------------------------
draw_dashed <- function(x0, y0, x1, y1, lwd = 1.2) {
  grid.lines(x = c(x0, x1), y = c(y0, y1),
             gp = gpar(col = COL_ARROW, lwd = lwd, lty = "dashed"))
}

# --- Helper: draw exclusion box with dynamic item spacing --------------------
draw_excl_box <- function(cx, cy, w, h, exc_n, reasons,
                          header_fs = FS_EXC_HEAD, item_fs = FS_EXC_ITEM) {
  # Background
  grid.roundrect(
    x = cx, y = cy,
    width = unit(w, "npc"), height = unit(h, "npc"),
    r = unit(0.06, "inches"),
    gp = gpar(fill = COL_EXC_BG, col = COL_BOX, lwd = 2)
  )
  
  # Header
  top_y <- cy + h / 2
  header_y <- top_y - 0.025
  grid.text(paste0("Excluded (n = ", exc_n, ")"),
            x = cx, y = header_y,
            gp = gpar(fontsize = header_fs, col = COL_TEXT,
                      fontface = "bold", fontfamily = "sans"),
            hjust = 0.5, vjust = 0.5)
  
  # Horizontal line under header
  line_y <- header_y - 0.022
  left_edge  <- cx - w / 2
  right_edge <- cx + w / 2
  grid.lines(x = c(left_edge + 0.02, right_edge - 0.02),
             y = c(line_y, line_y),
             gp = gpar(col = COL_BOX, lwd = 0.8))
  
  # Items with dynamic spacing (fit any number of reasons)
  n_items <- length(reasons)
  bottom_y <- cy - h / 2 + 0.015
  
  if (n_items > 1) {
    available <- line_y - 0.025 - bottom_y
    item_spacing <- available / (n_items - 1)
    item_start_y <- line_y - 0.025
  } else {
    item_spacing <- 0
    item_start_y <- (line_y + bottom_y) / 2
  }
  
  for (i in seq_along(reasons)) {
    yy <- item_start_y - (i - 1) * item_spacing
    
    # Bullet
    grid.points(x = left_edge + 0.025, y = yy, pch = 16, size = unit(2, "mm"),
                gp = gpar(col = COL_TEXT))
    
    # Reason text (left-justified)
    grid.text(paste0("  ", reasons[[i]]$text),
              x = left_edge + 0.045, y = yy,
              gp = gpar(fontsize = item_fs, col = COL_TEXT,
                        fontfamily = "sans"),
              hjust = 0, vjust = 0.5)
    
    # n value (right-justified)
    grid.text(paste0("(n = ", reasons[[i]]$n, ")"),
              x = right_edge - 0.02, y = yy,
              gp = gpar(fontsize = item_fs, col = COL_TEXT,
                        fontfamily = "sans"),
              hjust = 1, vjust = 0.5)
  }
}

# --- Main drawing function ---------------------------------------------------
plot_flowchart <- function() {
  
  # --- Layout coordinates ---------------------------------------------------
  left_x  <- 0.20
  left_w  <- 0.28
  
  right_x <- 0.70
  right_w <- 0.46
  
  # Main box positions (left column)
  box1_y  <- 0.92
  box1_h  <- 0.10
  
  box2_y  <- 0.50
  box2_h  <- 0.08
  
  box3_y  <- 0.08
  box3_h  <- 0.10
  
  # Exclusion box positions (right column)
  exc1_y  <- 0.92
  exc1_h  <- 0.14
  
  exc2_y  <- 0.50
  exc2_h  <- 0.60
  
  # --- Box 1: Spontaneous ICH -----------------------------------------------
  draw_box(
    x = left_x, y = box1_y,
    width = left_w, height = box1_h,
    label_lines = c("Patients with spontaneous ICH",
                    paste0("N = ", N_spontaneous)),
    font_sizes = c(FS_TITLE, FS_TITLE, FS_MAIN_N),
    fill = COL_BG, border = COL_BOX, lwd = 2,
    text_color = COL_TEXT
  )
  
  # --- Exclusion box 1 (upper right) ----------------------------------------
  draw_excl_box(
    cx = right_x, cy = exc1_y, w = right_w, h = exc1_h,
    exc_n = N_exc1, reasons = exc1_reasons
  )
  
  # --- Box 2: Hypertensive ICH ----------------------------------------------
  draw_box(
    x = left_x, y = box2_y,
    width = left_w, height = box2_h,
    label_lines = c("Hypertensive ICH",
                    paste0("N = ", N_hypertensive)),
    font_sizes = c(FS_TITLE, FS_MAIN_N),
    fill = COL_BG, border = COL_BOX, lwd = 2,
    text_color = COL_TEXT
  )
  
  # --- Exclusion box 2 (lower right) ----------------------------------------
  draw_excl_box(
    cx = right_x, cy = exc2_y, w = right_w, h = exc2_h,
    exc_n = N_exc2, reasons = exc2_reasons
  )
  
  # --- Box 3: Final analysis cohort -----------------------------------------
  draw_box(
    x = left_x, y = box3_y,
    width = left_w, height = box3_h,
    label_lines = c("Final hypertensive ICH",
                    "cohort for analysis",
                    paste0("N = ", N_final)),
    font_sizes = c(FS_TITLE, FS_TITLE, FS_FINAL_N),
    fill = COL_BG, border = COL_BOX, lwd = 2,
    text_color = COL_TEXT
  )
  
  # --- Arrows (vertical, between main boxes) --------------------------------
  
  # Arrow 1: Box 1 -> Box 2
  arrow_x   <- left_x
  arrow1_y0 <- box1_y - box1_h / 2 - 0.01
  arrow1_y1 <- box2_y + box2_h / 2 + 0.01
  draw_arrow(arrow_x, arrow1_y0, arrow_x, arrow1_y1)
  
  # Arrow 2: Box 2 -> Box 3
  arrow2_y0 <- box2_y - box2_h / 2 - 0.01
  arrow2_y1 <- box3_y + box3_h / 2 + 0.01
  draw_arrow(arrow_x, arrow2_y0, arrow_x, arrow2_y1)
  
  # --- Dashed connectors (main box -> exclusion box) -------------------------
  
  dash_x0 <- left_x + left_w / 2 + 0.01
  dash_x1 <- right_x - right_w / 2 - 0.01
  
  # Dashed 1: Box 1 -> Excl 1
  draw_dashed(dash_x0, box1_y, dash_x1, exc1_y)
  
  # Dashed 2: Box 2 -> Excl 2
  draw_dashed(dash_x0, box2_y, dash_x1, exc2_y)
  
  # --- Footnote --------------------------------------------------------------
  grid.text(
    "ICH = intracerebral hemorrhage; 25(OH)D = 25-hydroxyvitamin D; mRS = modified Rankin Scale",
    x = 0.98, y = 0.02,
    gp = gpar(fontsize = FS_FOOTNOTE, col = COL_TEXT, fontfamily = "sans"),
    hjust = 1, vjust = 0
  )
}

# --- Export PNG --------------------------------------------------------------
png(out_png, width = width_in * dpi, height = height_in * dpi, res = dpi)
grid.newpage()
plot_flowchart()
dev.off()
cat("PNG saved:", out_png, "\n")

# --- Export PDF --------------------------------------------------------------
pdf(out_pdf, width = width_in, height = height_in)
grid.newpage()
plot_flowchart()
dev.off()
cat("PDF saved:", out_pdf, "\n")

# --- Export TIFF (high-res for publication) ----------------------------------
tiff(out_tiff, width = width_in * dpi, height = height_in * dpi,
     res = dpi, compression = "lzw")
grid.newpage()
plot_flowchart()
dev.off()
cat("TIFF saved:", out_tiff, "\n")

cat("\nFlowchart generation complete!\n")
cat("Summary: N =", N_spontaneous,
    "-> Excluded n =", N_exc1,
    "-> N =", N_hypertensive,
    "-> Excluded n =", N_exc2,
    "-> Final N =", N_final, "\n")

# --- Session info (reproducibility) ---
si_lines <- capture.output(sessionInfo())
writeLines(si_lines, file.path(output_dir, "sessionInfo.txt"))
cat("Session info written -> output/sessionInfo.txt\n")

# --- Output manifest ---
out_files <- sort(list.files(output_dir, full.names = FALSE))
manifest <- c(
  "Output files produced by flowchart.R:",
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
