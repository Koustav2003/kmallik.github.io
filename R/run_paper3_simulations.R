#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_dir <- if (length(file_arg) > 0) dirname(normalizePath(sub("^--file=", "", file_arg))) else getwd()
source(file.path(script_dir, "paper3_simulation_plan.R"))

# Reduce computational load for demonstration runs
replicates_for_n <- function(n) 2L

demo_grids <- list(
  k_grid = 1:3,
  alpha_grid = c(0, 0.10),
  lambda_grid = c(0, 1e-2),
  T0_grid = c(2),
  gamma_grid = c(0.9),
  tau0_grid = c(0)
)

log_dir <- file.path("results", "paper3_simulation", format(Sys.time(), "%Y%m%d_%H%M%S"))
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

set.seed(123)
dgp_base <- make_dgp(kstar = 3, sep = 1.5)

out <- list(
  log_dir = log_dir,
  E1 = exp_E1(n_vals = c(200), grid_sizes = c(12), dgp = dgp_base,
              grids = demo_grids, method = "ours", log_dir = log_dir),
  E2 = exp_E2(n_vals = c(200, 400), sep_vals = c(1.2, 1.8), dgp_base = dgp_base,
              grids = demo_grids, method = "ours", log_dir = log_dir),
  E3 = exp_E3(n_vals = c(200, 400), kstars = c(1, 2, 3), grids = demo_grids,
              method = "ours", log_dir = log_dir),
  E4 = exp_E4(eps_vals = c(0, 0.10), n = 400, kstar = 3, grids = demo_grids,
              method = "ours", log_dir = log_dir),
  E5 = exp_E5(h_vals = c(0, 0.10), n = 400, grids = demo_grids,
              method = "ours", log_dir = log_dir),
  E6 = exp_E6(n = 400, dgp = dgp_base, grids = demo_grids,
              methods = c("ours"), log_dir = log_dir),
  E7 = exp_E7(n = 400, dgp = dgp_base, grids = demo_grids,
              log_dir = log_dir),
  E8 = exp_E8(n_vals = c(200, 400), k_vals = c(1, 2, 3), grids = demo_grids,
              dgp_base = dgp_base, log_dir = log_dir)
)

save_fast_outputs(out, out_dir = log_dir)
make_all_figs_tables(out, out_dir = log_dir)

message("Saved outputs to ", log_dir)
