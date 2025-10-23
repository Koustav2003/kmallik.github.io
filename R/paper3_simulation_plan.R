#!/usr/bin/env Rscript

## =========================================================
## Paper No. 3 — Simulation Plan (E1–E8)
## Folded-mixture PMLE (L/R-trim) with DA prox-EM + barrier
## + Baselines, metrics, logging, figures, and tests
## =========================================================

suppressPackageStartupMessages({
  requireNamespace("jsonlite", quietly = TRUE)
  requireNamespace("ggplot2", quietly = TRUE)
  requireNamespace("parallel", quietly = TRUE)
  requireNamespace("clue", quietly = TRUE)
  # Optional: fast Gauss–Legendre; falls back to trapezoid if unavailable
  has_statmod <- requireNamespace("statmod", quietly = TRUE)
})

set.seed(42)

## ========== Utility helpers ==========
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
clip <- function(x, lo, hi) pmax(lo, pmin(hi, x))

softmax_rows <- function(M) {
  # numerically stable row-wise softmax
  maxes <- apply(M, 1, max)
  Z <- exp(M - maxes)
  Z / rowSums(Z)
}

logsumexp_rows <- function(M) {
  m <- apply(M, 1, max)
  m + log(rowSums(exp(M - m)))
}

## ========== Densities: folded normal mixture ==========

dnorm_safe <- function(x, mean = 0, sd = 1) {
  pmax(dnorm(x, mean, sd), 1e-300)
}

# folded normal single component density f_{mu, sigma}(y) on [0, \infty)
# as sum of two normals at +-mu

dfolded <- function(y, mu, sigma) {
  z1 <- (y - mu) / sigma
  z2 <- (y + mu) / sigma
  (dnorm(z1) + dnorm(z2)) / sigma
}

# k-component folded normal mixture density on [0, \infty)

gmix_folded <- function(y, pi, mu, sigma) {
  k <- length(pi)
  dens <- 0
  for (j in seq_len(k)) dens <- dens + pi[j] * dfolded(y, mu[j], sigma[j])
  pmax(dens, 1e-300)
}

# 2k-component unfolded symmetric mixture at means +-mu with weights pi/2

unfold_params <- function(pi, mu, sigma) {
  k <- length(pi)
  pi2 <- as.numeric(rbind(pi/2, pi/2))
  mu2 <- as.numeric(rbind(+mu, -mu))
  sigma2 <- as.numeric(rbind(sigma, sigma))
  list(pi2 = pi2, mu2 = mu2, sigma2 = sigma2)
}

gmix_unfolded <- function(x, pi2, mu2, sigma2) {
  dens <- 0
  for (j in seq_along(pi2)) dens <- dens + pi2[j] * dnorm_safe(x, mu2[j], sigma2[j])
  pmax(dens, 1e-300)
}

## ========== DGPs ==========

# Generate Y=|X| for a folded normal mixture with optional contamination/misspec.
# misspec: type in {"none", "laplace", "t"} used only when generating from unfolded alt.

r_folded_mixture <- function(n, pi, mu, sigma,
                             contam_eps = 0, contam_type = c("t3", "point"),
                             misspec = c("none", "laplace", "t")) {
  contam_type <- match.arg(contam_type)
  misspec <- match.arg(misspec)
  k <- length(pi)
  comp <- sample.int(k, size = n, replace = TRUE, prob = pi)
  # Unfolded draw X ~ sum pi_j N(+-mu_j, sigma_j^2)
  signz <- sample(c(-1, +1), size = n, replace = TRUE)
  x <- rnorm(n, mean = signz * mu[comp], sd = sigma[comp])
  if (misspec != "none") {
    # replace the Gaussian kernel by Laplace or t draws (same means, same scale proxy)
    if (misspec == "laplace") {
      # Draw Laplace with b = sigma / sqrt(2) for variance matching
      b <- sigma[comp] / sqrt(2)
      u <- runif(n, -0.5, 0.5)
      x <- signz * mu[comp] + b * sign(u) * log1p(-2 * abs(u)) * (-1)
    } else if (misspec == "t") {
      x <- signz * mu[comp] + sigma[comp] * rt(n, df = 5) / sqrt(5/(5-2))
    }
  }
  y <- abs(x)
  if (contam_eps > 0) {
    m <- rbinom(1, n, contam_eps)
    if (m > 0) {
      idx <- sample.int(n, m)
      if (contam_type == "t3") {
        y[idx] <- abs(rt(m, df = 3)) * quantile(y, 0.95) # heavy tails
      } else {
        y[idx] <- max(y) + rexp(m, rate = 0.1) + 10 # point-mass far out
      }
    }
  }
  pmax(y, 0)
}

## ========== Trimming rules ==========

# L-trim: keep (1-alpha) fraction with largest log-likelihood under current theta
ltrim_mask <- function(y, pi, mu, sigma, alpha) {
  ll <- log(gmix_folded(y, pi, mu, sigma))
  keep <- order(ll, decreasing = TRUE)[seq_len(ceiling((1 - alpha) * length(y)))]
  mask <- logical(length(y)); mask[keep] <- TRUE; mask
}

# R-trim: keep (1-alpha) fraction with largest max-responsibility (most confident)
# Based on tempered responsibilities at current T
rtrim_mask <- function(y, pi, mu, sigma, alpha, T = 1) {
  k <- length(pi)
  log_w <- matrix(NA_real_, nrow = length(y), ncol = k)
  for (j in seq_len(k)) {
    log_w[, j] <- (log(pi[j]) + log(dfolded(y, mu[j], sigma[j]))) / T
  }
  r <- softmax_rows(log_w)
  conf <- apply(r, 1, max)
  keep <- order(conf, decreasing = TRUE)[seq_len(ceiling((1 - alpha) * length(y)))]
  mask <- logical(length(y)); mask[keep] <- TRUE; mask
}

## ========== Responsibilities (tempered) ==========

resp_tempered_folded <- function(y, pi, mu, sigma, T = 1) {
  k <- length(pi)
  log_w <- matrix(NA_real_, nrow = length(y), ncol = k)
  for (j in seq_len(k)) {
    log_w[, j] <- (log(pi[j]) + log(dfolded(y, mu[j], sigma[j]))) / T
  }
  r <- softmax_rows(log_w)
  list(r = r, loglik = logsumexp_rows(log_w) * T)  # re-scale back by T
}

## ========== Prox-EM core (folded via unfolding trick) ==========

# One EM update for unfolded 2k normal mixture with prox blending
# Given weights w_ij for j in 1..2k (masked + tempered responsibilities)

mstep_unfolded <- function(x, w, prev, eta = 0, pi_floor = 1e-4,
                           sigma_min = 0.05, sigma_max = 10) {
  # w: n x (2k)
  n <- nrow(w); J <- ncol(w)
  wsum <- colSums(w) + 1e-12
  pi2 <- wsum / sum(wsum)
  mu2 <- as.numeric(colSums(w * x) / wsum)
  v2 <- as.numeric(colSums(w * (x - rep(mu2, each = n))^2) / wsum)
  sigma2 <- sqrt(pmax(v2, sigma_min^2))
  # Prox blend toward previous parameters
  if (!is.null(prev)) {
    pi2 <- (pi2 + eta * prev$pi2) / (1 + eta)
    pi2 <- pmax(pi2, 0); pi2 <- pi2 / sum(pi2)
    mu2 <- (mu2 + eta * prev$mu2) / (1 + eta)
    sigma2 <- (sigma2 + eta * prev$sigma2) / (1 + eta)
  }
  # Project \sigma and prune small pi2 by collapsing later during folding
  sigma2 <- clip(sigma2, sigma_min, sigma_max)
  list(pi2 = pi2, mu2 = mu2, sigma2 = sigma2)
}

fold_params <- function(pi2, mu2, sigma2, pi_floor = 1e-4) {
  # Map 2k back to k by pairing (+,-)
  J <- length(pi2); stopifnot(J %% 2 == 0)
  k <- J / 2
  pi <- numeric(k); mu <- numeric(k); sigma <- numeric(k)
  for (j in seq_len(k)) {
    wj <- pi2[c(2*j - 1, 2*j)]
    mj <- mu2[c(2*j - 1, 2*j)]
    sj <- sigma2[c(2*j - 1, 2*j)]
    pi[j] <- sum(wj)
    # enforce symmetry: means equal magnitude, choose positive representative
    mu[j] <- mean(abs(mj))
    sigma[j] <- mean(sj)
  }
  # Prune tiny components
  keep <- which(pi >= pi_floor)
  if (length(keep) == 0) keep <- which.max(pi)
  pi <- pi[keep]; mu <- mu[keep]; sigma <- sigma[keep]
  pi <- pi / sum(pi)
  list(pi = pi, mu = mu, sigma = sigma, pruned = setdiff(seq_len(k), keep))
}

negloglik_trimmed <- function(y, pi, mu, sigma, alpha, mode = c("L", "R"), T = 1) {
  mode <- match.arg(mode)
  mask <- if (alpha <= 0) rep(TRUE, length(y)) else
    if (mode == "L") ltrim_mask(y, pi, mu, sigma, alpha) else rtrim_mask(y, pi, mu, sigma, alpha, T)
  -sum(log(gmix_folded(y[mask], pi, mu, sigma)))
}

pmle_prox_em <- function(y, k, alpha = 0, lambda = 0, T0 = 1, gamma = 0.9,
                         max_iter = 200, tol = 1e-6, restarts = 1,
                         pi_floor = 1e-4, sigma_min = 0.05, sigma_max = 10,
                         tau0 = 0, eta_floor = 1e-4, backtrack = TRUE,
                         switch_to_L_at_T1 = TRUE,
                         verbose = FALSE, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  best <- NULL; best_obj <- Inf
  n <- length(y)
  # Initialization via kmeans++ on unfolded surrogates
  for (rs in seq_len(restarts)) {
    # Start with k random centers in y plus jitter to seed mu
    mu0 <- sort(sample(y, k, replace = TRUE))
    sigma0 <- rep(sd(y)/sqrt(2) %||% 1, k)
    pi0 <- rep(1/k, k)
    theta <- list(pi = pi0, mu = pmax(mu0, 1e-3), sigma = clip(sigma0, sigma_min, sigma_max))
    # Temperature schedule
    T <- T0
    mode <- if (T > 1 && !isFALSE(switch_to_L_at_T1)) "R" else "L"
    eta <- 1e-2
    obj_hist <- c()
    pruned_total <- c()
    for (it in seq_len(max_iter)) {
      # Barrier weight decays with n
      tau_n <- (tau0 / n)
      # Trimming mask
      mask <- if (alpha <= 0) rep(TRUE, n) else
        if (mode == "L") ltrim_mask(y, theta$pi, theta$mu, theta$sigma, alpha) else rtrim_mask(y, theta$pi, theta$mu, theta$sigma, alpha, T)
      yy <- y[mask]
      # E-step (tempered responsibilities over folded components)
      tmp <- resp_tempered_folded(yy, theta$pi, theta$mu, theta$sigma, T)
      r <- tmp$r
      # Unfold responsibilities to 2k Gaussian components
      U <- unfold_params(theta$pi, theta$mu, theta$sigma)
      # For each j (folded comp), split responsibility equally to +/- (since f = sum of two normals)
      r2 <- r[, rep(seq_len(k), each = 2)] / 2
      # Build w for M-step over x (signed) using duplication; we need pseudo x for +/-
      x <- c(+yy, -yy)
      w <- rbind(r2, r2)  # n*2 rows by 2k cols weights correspond to x
      prev_unf <- NULL
      # previous unfolded params for prox
      prev_unf <- list(pi2 = U$pi2, mu2 = U$mu2, sigma2 = U$sigma2)
      # M-step (prox blended)
      eta_use <- max(eta, eta_floor)
      unf_new <- mstep_unfolded(x, w, prev = prev_unf, eta = eta_use,
                                pi_floor = pi_floor, sigma_min = sigma_min, sigma_max = sigma_max)
      # Fold back
      folded <- fold_params(unf_new$pi2, unf_new$mu2, unf_new$sigma2, pi_floor = pi_floor)
      theta_new <- list(pi = folded$pi, mu = folded$mu, sigma = folded$sigma)
      k <- length(theta_new$pi)  # allow pruning to reduce k
      # Penalized objective: trimmed -loglik + lambda*||mu||^2 + tau barrier on log sigma
      obj_core <- -sum(log(gmix_folded(yy, theta_new$pi, theta_new$mu, theta_new$sigma)))
      penalty <- lambda * sum(theta_new$mu^2)
      barrier <- -tau_n * sum(log(pmax(theta_new$sigma, 1e-9)))
      obj <- obj_core + penalty + barrier
      obj_hist <- c(obj_hist, obj)
      pruned_total <- c(pruned_total, folded$pruned)
      # Check convergence (relative)
      if (it > 5) {
        rel <- abs(obj_hist[it] - obj_hist[it-1]) / (abs(obj_hist[it-1]) + 1e-9)
        if (rel < tol && T <= 1 + 1e-12) break
      }
      # Backtracking on eta if objective increased under L-trim (should be monotone)
      if (backtrack && mode == "L" && it > 1 && obj_hist[it] > obj_hist[it-1]) {
        eta <- eta * 2  # stronger prox (more conservative)
      } else {
        eta <- eta * 0.95
      }
      # Cool temperature
      if (T > 1) {
        T <- max(1, T * gamma)
        if (T == 1 && switch_to_L_at_T1) mode <- "L"
      }
      theta <- theta_new
    }
    # Save restart with best validation-style objective (untrimmed NLL) as tie-breaker
    untrim_nll <- -sum(log(gmix_folded(y, theta$pi, theta$mu, theta$sigma)))
    if (untrim_nll < best_obj) {
      best_obj <- untrim_nll
      best <- list(theta = theta, obj_hist = obj_hist, iters = it, pruned = unique(pruned_total),
                   T0 = T0, gamma = gamma, alpha = alpha, lambda = lambda)
    }
  }
  best
}

## ========== Baselines ==========

em_vanilla <- function(y, k, max_iter = 200, tol = 1e-6,
                       pi_floor = 1e-4, sigma_min = 0.05, sigma_max = 10, seed = NULL) {
  pmle_prox_em(y, k, alpha = 0, lambda = 0, T0 = 1, gamma = 1,
               max_iter = max_iter, tol = tol, restarts = 1,
               pi_floor = pi_floor, sigma_min = sigma_min, sigma_max = sigma_max,
               tau0 = 0, eta_floor = 0, backtrack = FALSE, switch_to_L_at_T1 = FALSE,
               verbose = FALSE, seed = seed)
}

trimmed_em_L <- function(y, k, alpha, max_iter = 200, tol = 1e-6,
                         pi_floor = 1e-4, sigma_min = 0.05, sigma_max = 10, seed = NULL) {
  pmle_prox_em(y, k, alpha = alpha, lambda = 0, T0 = 1, gamma = 1,
               max_iter = max_iter, tol = tol, restarts = 1,
               pi_floor = pi_floor, sigma_min = sigma_min, sigma_max = sigma_max,
               tau0 = 0, eta_floor = 0, backtrack = FALSE, switch_to_L_at_T1 = FALSE,
               verbose = FALSE, seed = seed)
}

our_method_full <- function(y, k, alpha, lambda, T0, gamma, tau0,
                            max_iter = 200, tol = 1e-6, restarts = 3,
                            pi_floor = 1e-4, sigma_min = 0.05, sigma_max = 10,
                            seed = NULL) {
  pmle_prox_em(y, k, alpha = alpha, lambda = lambda, T0 = T0, gamma = gamma,
               max_iter = max_iter, tol = tol, restarts = restarts,
               pi_floor = pi_floor, sigma_min = sigma_min, sigma_max = sigma_max,
               tau0 = tau0, eta_floor = 1e-4, backtrack = TRUE, switch_to_L_at_T1 = TRUE,
               verbose = FALSE, seed = seed)
}

## ========== Metrics ==========

# Hellinger distance between densities g and h on [0, m]
hellinger <- function(gfun, hfun, m, nodes = 400) {
  # Try Gauss–Legendre nodes; fall back to trapezoid
  if (has_statmod) {
    gl <- statmod::gauss.quad(nodes, kind = "legendre")
    # map [-1,1] -> [0,m]
    x <- (gl$nodes + 1) * (m/2)
    w <- gl$weights * (m/2)
    gy <- pmax(gfun(x), 1e-300)
    hy <- pmax(hfun(x), 1e-300)
    integrand <- (sqrt(gy) - sqrt(hy))^2
    sum(w * integrand)
  } else {
    x <- seq(0, m, length.out = nodes)
    gy <- pmax(gfun(x), 1e-300)
    hy <- pmax(hfun(x), 1e-300)
    integrand <- (sqrt(gy) - sqrt(hy))^2
    trapz <- function(x, y) sum(diff(x) * (head(y,-1) + tail(y,-1)) / 2)
    trapz(x, integrand)
  }
}

# Parameter Hausdorff / matching metric between sets of (mu, sigma)
match_metric <- function(mu_hat, sig_hat, mu_true, sig_true) {
  # cost matrix on pairs
  k1 <- length(mu_hat); k2 <- length(mu_true)
  K <- max(k1, k2)
  # pad smaller set with dummies at large cost
  MUh <- c(mu_hat, rep(Inf, K - k1))
  SIh <- c(sig_hat, rep(Inf, K - k1))
  MUt <- c(mu_true, rep(Inf, K - k2))
  SIt <- c(sig_true, rep(Inf, K - k2))
  cost <- outer(seq_len(K), seq_len(K), Vectorize(function(i, j) {
    if (is.infinite(MUh[i]) || is.infinite(MUt[j])) return(1e6)
    sqrt((MUh[i] - MUt[j])^2 + (SIh[i] - SIt[j])^2)
  }))
  # Hungarian assignment
  if (requireNamespace("clue", quietly = TRUE)) {
    assign <- clue::solve_LSAP(cost)
    mean(sapply(seq_len(K), function(i) cost[i, assign[i]]))
  } else {
    # Greedy fallback
    total <- 0
    used <- rep(FALSE, K)
    for (i in seq_len(K)) {
      j <- which.min(ifelse(used, Inf, cost[i, ]))
      used[j] <- TRUE; total <- total + cost[i, j]
    }
    total / K
  }
}

# Validation NLL (untrimmed)
val_nll <- function(y, theta) {
  -mean(log(gmix_folded(y, theta$pi, theta$mu, theta$sigma)))
}

## ========== Train/validation split ==========

split_train_val <- function(y) {
  n <- length(y); idx <- sample.int(n)
  tr <- idx[seq_len(floor(n/2))]
  va <- setdiff(idx, tr)
  list(ytr = y[tr], yva = y[va])
}

## ========== Grids and selection ==========

default_grids <- function(kmax = 8, kstar = NULL) {
  list(
    k_grid = seq_len(kmax),
    alpha_grid = c(0, 0.05, 0.10, 0.15, 0.20),
    lambda_grid = c(0, 1e-3, 1e-2, 1e-1),
    T0_grid = c(2, 5),
    gamma_grid = c(0.9, 0.8),
    tau0_grid = c(0, 0.1)
  )
}

run_grid <- function(ytr, yva, grids, method = c("ours", "vanilla", "trimL"), restarts = 3,
                     max_k = 12, seed = NULL, sieve = list(pi_floor=1e-4, sigma_min=0.05, sigma_max=10)) {
  method <- match.arg(method)
  set.seed(seed %||% 1)
  results <- list()
  t_id <- 1
  for (k in grids$k_grid) {
    for (alpha in grids$alpha_grid) {
      for (lambda in grids$lambda_grid) {
        for (T0 in grids$T0_grid) {
          for (gamma in grids$gamma_grid) {
            for (tau0 in grids$tau0_grid) {
              if (method == "vanilla" && (alpha != 0 || lambda != 0 || T0 != 1 || gamma != 1 || tau0 != 0)) next
              if (method == "trimL" && (T0 != 1 || gamma != 1 || tau0 != 0 || lambda != 0)) next
              fit <- switch(method,
                            ours = our_method_full(ytr, k, alpha, lambda, T0, gamma, tau0,
                                                   restarts = restarts,
                                                   pi_floor = sieve$pi_floor, sigma_min = sieve$sigma_min, sigma_max = sieve$sigma_max),
                            vanilla = em_vanilla(ytr, k, pi_floor = sieve$pi_floor, sigma_min = sieve$sigma_min, sigma_max = sieve$sigma_max),
                            trimL = trimmed_em_L(ytr, k, alpha, pi_floor = sieve$pi_floor, sigma_min = sieve$sigma_min, sigma_max = sieve$sigma_max))
              val <- val_nll(yva, fit$theta)
              results[[t_id]] <- list(id = t_id, k = length(fit$theta$pi), alpha = alpha, lambda = lambda,
                                      T0 = T0, gamma = gamma, tau0 = tau0, val_nll = val, fit = fit)
              t_id <- t_id + 1
            }
          }
        }
      }
    }
  }
  # Selection: minimum validation NLL, tie-break smaller k
  vals <- sapply(results, function(r) r$val_nll)
  ks <- sapply(results, function(r) r$k)
  min_val <- min(vals)
  cand <- which(abs(vals - min_val) < 1e-12)
  sel <- cand[which.min(ks[cand])]
  list(all = results, selected = results[[sel]], min_val = min_val)
}

## ========== Experiments E1–E8 ==========

# DGP constructor respecting sieve
make_dgp <- function(kstar = 3, pi_mode = c("equal", "skewed"), sigma_choice = 1,
                     sep = 1.5, sigma_min = 0.05, sigma_max = 2, m = 8) {
  pi_mode <- match.arg(pi_mode)
  if (pi_mode == "equal") pi <- rep(1/kstar, kstar) else {
    tmp <- runif(kstar); pi <- tmp / sum(tmp)
  }
  sigma <- rep(sigma_choice, kstar)
  # Place means with target separation relative to sigma_min
  mu <- sort(cumsum(c(0, rep(sep * sigma_min, kstar - 1)))) + runif(kstar, 0, 0.2)
  list(pi = pi, mu = mu, sigma = sigma, kstar = kstar, m = m,
       sigma_min = sigma_min, sigma_max = sigma_max)
}

# Run a single replicate across grid, return metrics
run_replicate <- function(n = 1000, dgp, contam_eps = 0, contam_type = "t3",
                          misspec = "none", grids = default_grids(), method = "ours",
                          restarts = 3, seed = NULL, kmax_override = NULL,
                          sieve = list(pi_floor=1e-4, sigma_min=0.05, sigma_max=10),
                          log_dir = NULL, run_id = NULL) {
  set.seed(seed %||% sample.int(1e8, 1))
  y <- r_folded_mixture(n, dgp$pi, dgp$mu, dgp$sigma, contam_eps = contam_eps,
                        contam_type = contam_type, misspec = misspec)
  sp <- split_train_val(y)
  grids$k_grid <- seq_len(kmax_override %||% max(8, dgp$kstar + 3))
  gres <- run_grid(sp$ytr, sp$yva, grids, method = method, restarts = restarts,
                   sieve = sieve)
  sel <- gres$selected
  # Metrics
  theta_hat <- sel$fit$theta
  dH <- match_metric(theta_hat$mu, theta_hat$sigma, dgp$mu, dgp$sigma)
  # Density Hellinger on [0, m]
  ghat <- function(x) gmix_folded(x, theta_hat$pi, theta_hat$mu, theta_hat$sigma)
  gtrue <- function(x) gmix_folded(x, dgp$pi, dgp$mu, dgp$sigma)
  hdist <- hellinger(ghat, gtrue, m = dgp$m, nodes = 600)
  # Selection event relative to k*
  ksel <- length(theta_hat$pi)
  sel_status <- if (ksel < dgp$kstar) "under" else if (ksel == dgp$kstar) "exact" else "over"
  # Optimization logs
  obj_traj <- sel$fit$obj_hist
  mono_viol <- sum(diff(obj_traj) > 1e-10)
  pruned_frac <- length(sel$fit$pruned)
  # Oracle gap on validation
  delta_sel <- sel$val_nll - gres$min_val
  out <- list(run_id = run_id %||% paste0("rep-", sample.int(1e9, 1)), n = n,
              method = method, contam_eps = contam_eps, misspec = misspec,
              metrics = list(dH = dH, h = hdist, val_nll = sel$val_nll, delta_sel = delta_sel,
                             iter = sel$fit$iters, mono_viol = mono_viol,
                             pruned = pruned_frac, ksel = ksel, sel_status = sel_status),
              theta_hat = theta_hat, theta_true = list(pi=dgp$pi, mu=dgp$mu, sigma=dgp$sigma),
              grid_choice = list(k = sel$k, alpha = sel$alpha, lambda = sel$lambda,
                                 T0 = sel$T0, gamma = sel$gamma, tau0 = sel$tau0))
  # Optional JSON log
  if (!is.null(log_dir)) {
    dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(log_dir, paste0(out$run_id, ".json"))
    jsonlite::write_json(out, path, auto_unbox = TRUE, digits = 8)
  }
  out
}

## ========== High-level experiment wrappers ==========

# Decide replicate count as in plan
replicates_for_n <- function(n) if (n <= 2000) 100L else 50L

# E1: Oracle gap calibration
exp_E1 <- function(n_vals = c(500,1000,2000,4000), grid_sizes = c(50, 100),
                   dgp = make_dgp(kstar = 3, sep = 1.5),
                   grids = default_grids(), method = "ours",
                   seeds = NULL, log_dir = NULL) {
  library(parallel)
  results <- list()
  id <- 1
  for (n in n_vals) {
    R <- replicates_for_n(n)
    if (!is.null(seeds)) set.seed(seeds[id] %||% 1)
    for (gsize in grid_sizes) {
      # downsample grid size by random thinning of combinations
      all_comb <- expand.grid(k=grids$k_grid, alpha=grids$alpha_grid, lambda=grids$lambda_grid,
                              T0=grids$T0_grid, gamma=grids$gamma_grid, tau0=grids$tau0_grid)
      take <- sample.int(nrow(all_comb), min(gsize, nrow(all_comb)))
      gsub <- list(k_grid = sort(unique(all_comb$k[take])),
                   alpha_grid = sort(unique(all_comb$alpha[take])),
                   lambda_grid = sort(unique(all_comb$lambda[take])),
                   T0_grid = sort(unique(all_comb$T0[take])),
                   gamma_grid = sort(unique(all_comb$gamma[take])),
                   tau0_grid = sort(unique(all_comb$tau0[take])))
      reps <- mclapply(seq_len(R), function(r) {
        run_replicate(n = n, dgp = dgp, grids = gsub, method = method,
                      restarts = 3, log_dir = log_dir)
      }, mc.cores = max(1, detectCores() - 1))
      deltas <- sapply(reps, function(z) z$metrics$delta_sel)
      results[[id]] <- data.frame(n = n, grid_size = gsize, delta_sel = deltas,
                                  bound = sqrt(log(gsize)/ (n/2)))
      id <- id + 1
    }
  }
  do.call(rbind, results)
}

# E2: Underfitting probability vs n_va * Delta_gap^2
proxy_underfit_gap <- function(dgp, n_proxy = 5e4) {
  # estimate L(theta_-)-L(theta^*) by evaluating true densities
  y <- r_folded_mixture(n_proxy, dgp$pi, dgp$mu, dgp$sigma)
  # Fit k* and k*-1 with strong regularization (many restarts)
  fit_star <- em_vanilla(y, dgp$kstar, restarts = 3)
  fit_under <- em_vanilla(y, max(1, dgp$kstar - 1), restarts = 3)
  L_star <- -mean(log(gmix_folded(y, fit_star$theta$pi, fit_star$theta$mu, fit_star$theta$sigma)))
  L_under <- -mean(log(gmix_folded(y, fit_under$theta$pi, fit_under$theta$mu, fit_under$theta$sigma)))
  max(0, L_under - L_star)
}

exp_E2 <- function(n_vals = c(500,1000,2000,4000), sep_vals = c(1.0, 1.5, 2.0),
                   dgp_base = make_dgp(kstar = 3, sep = 1.5), grids = default_grids(),
                   method = "ours", log_dir = NULL) {
  library(parallel)
  out <- list(); id <- 1
  for (sep in sep_vals) {
    dgp <- make_dgp(kstar = dgp_base$kstar, sep = sep)
    Delta_gap <- proxy_underfit_gap(dgp)
    for (n in n_vals) {
      R <- replicates_for_n(n)
      reps <- mclapply(seq_len(R), function(r) {
        z <- run_replicate(n = n, dgp = dgp, grids = grids, method = method, log_dir = log_dir)
        z$metrics$sel_status
      }, mc.cores = max(1, detectCores() - 1))
      tab <- table(factor(unlist(reps), levels = c("under","exact","over")))
      p_under <- as.numeric(tab["under"]/sum(tab))
      out[[id]] <- data.frame(n = n, sep = sep, p_under = p_under,
                              nvagap2 = (n/2) * Delta_gap^2,
                              bound = exp(-(n/2) * Delta_gap^2 / 8))
      id <- id + 1
    }
  }
  do.call(rbind, out)
}

# E3: Minimax rate in well-specified case
exp_E3 <- function(n_vals = c(500,1000,2000,4000), kstars = c(1,2,3,5),
                   grids = default_grids(), method = "ours", log_dir = NULL) {
  library(parallel)
  res <- list(); id <- 1
  for (k in kstars) {
    for (n in n_vals) {
      R <- replicates_for_n(n)
      dgp <- make_dgp(kstar = k, sep = 1.5)
      reps <- mclapply(seq_len(R), function(r) {
        z <- run_replicate(n = n, dgp = dgp, grids = grids, method = method, log_dir = log_dir)
        z$metrics$dH
      }, mc.cores = max(1, detectCores() - 1))
      res[[id]] <- data.frame(n = n, kstar = k, dH = unlist(reps),
                              rate = sqrt(k/n))
      id <- id + 1
    }
  }
  do.call(rbind, res)
}

# E4: Contamination robustness
exp_E4 <- function(eps_vals = c(0, 0.02, 0.05, 0.10, 0.20), n = 2000, kstar = 3,
                   grids = default_grids(), method = "ours", log_dir = NULL) {
  library(parallel)
  dgp <- make_dgp(kstar = kstar, sep = 1.5)
  res <- list(); id <- 1
  for (eps in eps_vals) {
    R <- replicates_for_n(n)
    reps <- mclapply(seq_len(R), function(r) {
      z <- run_replicate(n = n, dgp = dgp, grids = grids, method = method,
                         contam_eps = eps, log_dir = log_dir)
      c(dH = z$metrics$dH, h = z$metrics$h, nll = z$metrics$val_nll)
    }, mc.cores = max(1, detectCores() - 1))
    M <- do.call(rbind, reps)
    res[[id]] <- data.frame(eps = eps, dH = M[,"dH"], h = M[,"h"], nll = M[,"nll"])
    id <- id + 1
  }
  do.call(rbind, res)
}

# E5: Misspecification variance–bias decomposition
exp_E5 <- function(h_vals = c(0, 0.05, 0.1, 0.2), n = 2000,
                   grids = default_grids(), method = "ours", log_dir = NULL) {
  library(parallel)
  # Control misspec via generating Laplace/t then fitting normals
  res <- list(); id <- 1
  for (hlev in h_vals) {
    # crude control: mix Laplace proportion hlev into Gaussian kernel
    miss <- if (hlev == 0) "none" else "laplace"
    dgp <- make_dgp(kstar = 3, sep = 1.5)
    R <- replicates_for_n(n)
    reps <- mclapply(seq_len(R), function(r) {
      z <- run_replicate(n = n, dgp = dgp, grids = grids, method = method,
                         misspec = miss, log_dir = log_dir)
      c(dH = z$metrics$dH, h = z$metrics$h)
    }, mc.cores = max(1, detectCores() - 1))
    M <- do.call(rbind, reps)
    res[[id]] <- data.frame(h_target = hlev, dH = M[,"dH"], h = M[,"h"],
                            var_term = sqrt(3/n))
    id <- id + 1
  }
  do.call(rbind, res)
}

# E6: Optimization correctness
exp_E6 <- function(n = 2000, dgp = make_dgp(kstar = 3), grids = default_grids(),
                   methods = c("ours"), log_dir = NULL) {
  library(parallel)
  R <- replicates_for_n(n)
  reps <- mclapply(seq_len(R), function(r) {
    z <- run_replicate(n = n, dgp = dgp, grids = grids, method = methods[1], log_dir = log_dir)
    list(iter = z$metrics$iter, mono_viol = z$metrics$mono_viol, pruned = z$metrics$pruned,
         ksel = z$metrics$ksel)
  }, mc.cores = max(1, detectCores() - 1))
  do.call(rbind, lapply(reps, as.data.frame))
}

# E7: Ablations
exp_E7 <- function(n = 2000, dgp = make_dgp(kstar = 3), grids = default_grids(), log_dir = NULL) {
  library(parallel)
  methods <- c("ours","vanilla","trimL")
  res <- list(); id <- 1
  for (m in methods) {
    R <- replicates_for_n(n)
    reps <- mclapply(seq_len(R), function(r) {
      z <- run_replicate(n = n, dgp = dgp, grids = grids, method = m, log_dir = log_dir)
      c(method = m, dH = z$metrics$dH, nll = z$metrics$val_nll, iter = z$metrics$iter)
    }, mc.cores = max(1, detectCores() - 1))
    M <- do.call(rbind, reps)
    res[[id]] <- as.data.frame(M)
    id <- id + 1
  }
  do.call(rbind, res)
}

# E8: Computational scaling (rough)
exp_E8 <- function(n_vals = c(500,1000,2000,4000), k_vals = c(1,2,3,5),
                   grids = default_grids(), dgp_base = make_dgp(kstar = 3), log_dir = NULL) {
  times <- list(); id <- 1
  for (k in k_vals) {
    for (n in n_vals) {
      dgp <- make_dgp(kstar = k, sep = 1.5)
      t0 <- proc.time()[3]
      z <- run_replicate(n = n, dgp = dgp, grids = grids, method = "ours", log_dir = log_dir)
      t1 <- proc.time()[3]
      times[[id]] <- data.frame(n = n, k = k, time_sec = as.numeric(t1 - t0), iter = z$metrics$iter)
      id <- id + 1
    }
  }
  do.call(rbind, times)
}

## ========== Figures/Tables (sketches) ==========

fig_E1 <- function(df) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) return(invisible())
  ggplot2::ggplot(df, ggplot2::aes(x = sqrt(log(grid_size)/(n/2)), y = delta_sel)) +
    ggplot2::geom_point(alpha = 0.5) +
    ggplot2::geom_smooth(method = "lm", se = FALSE) +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = 2) +
    ggplot2::labs(x = expression(sqrt(log(group("|", T, "|"))/n[va])), y = expression(Delta[sel]))
}

fig_rate <- function(df) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) return(invisible())
  ggplot2::ggplot(df, ggplot2::aes(x = n, y = dH, color = factor(kstar))) +
    ggplot2::geom_point(alpha = 0.5) + ggplot2::geom_smooth(method = "lm") +
    ggplot2::scale_x_log10() + ggplot2::scale_y_log10() +
    ggplot2::labs(color = "k*", x = "n (log)", y = "d_H (log)")
}

## ========== Statistical tests ==========

paired_tests <- function(df_method_wide, metrics = c("dH","nll")) {
  # df_method_wide: columns method, replicate id, and metrics for each method in separate cols
  out <- list()
  for (m in metrics) {
    x <- df_method_wide[[paste0("ours_", m)]]
    y <- df_method_wide[[paste0("vanilla_", m)]]
    z <- df_method_wide[[paste0("trimL_", m)]]
    tests <- list(
      ours_vs_vanilla = t.test(x, y, paired = TRUE),
      ours_vs_trimL = t.test(x, z, paired = TRUE)
    )
    pvals <- sapply(tests, function(t) t$p.value)
    adj <- p.adjust(pvals, method = "holm")
    effsize <- list(
      ours_vs_vanilla = (mean(x - y))/sd(x - y),
      ours_vs_trimL = (mean(x - z))/sd(x - z)
    )
    out[[m]] <- list(pvals = pvals, pvals_holm = adj, effect = effsize)
  }
  out
}

## ========== Entrypoint convenience ==========

run_all_experiments <- function() {
  grids <- default_grids()
  dgp <- make_dgp(kstar = 3, sep = 1.5)
  log_dir <- file.path("logs", format(Sys.time(), "%Y%m%d_%H%M%S"))
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  message("Running E1 (this may take time)...")
  dfE1 <- exp_E1(grids = grids, dgp = dgp, method = "ours", log_dir = log_dir)
  message("Running E2...")
  dfE2 <- exp_E2(grids = grids, method = "ours", log_dir = log_dir)
  message("Running E3...")
  dfE3 <- exp_E3(grids = grids, method = "ours", log_dir = log_dir)
  message("Running E4...")
  dfE4 <- exp_E4(grids = grids, method = "ours", log_dir = log_dir)
  message("Running E5...")
  dfE5 <- exp_E5(grids = grids, method = "ours", log_dir = log_dir)
  message("Running E6...")
  dfE6 <- exp_E6(grids = grids, method = "ours", log_dir = log_dir)
  message("Running E7...")
  dfE7 <- exp_E7(grids = grids, log_dir = log_dir)
  message("Running E8...")
  dfE8 <- exp_E8(grids = grids, log_dir = log_dir)
  list(E1=dfE1, E2=dfE2, E3=dfE3, E4=dfE4, E5=dfE5, E6=dfE6, E7=dfE7, E8=dfE8)
}

## =========================================================
## Notes:
## - The prox-EM blends M-step estimates toward the previous iterate, which
##   empirically enforces monotonicity under L-trim; we log any violations.
## - R-trim is used while T>1 (annealing). At T=1 we switch to L-trim.
## - Barrier is implemented via projection to [sigma_min, sigma_max] and a small
##   -tau * sum(log sigma) term in the objective; tau_n = tau0/n.
## - Pruning zeros out tiny mixture weights (pi < pi_floor) and renormalizes.
## - Hellinger is computed on [0,m] with Gauss–Legendre if statmod is available.
## - Hungarian matching uses clue::solve_LSAP if available; else a greedy fallback.
## - JSON logs include seeds, chosen grid point, objective trajectory length,
##   pruning events, and validation NLL, per replicate.
## - Figures F1/F3 helpers included; others can be assembled analogously from the
##   returned data frames (E2–E8).
## =========================================================

# =========================================================
# Output helpers — save CSVs and lightweight figures
# =========================================================

save_fast_outputs <- function(out, out_dir = NULL) {
  if (is.null(out_dir)) out_dir <- file.path(out$log_dir, "summaries")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  # Helper to save a data.frame safely
  save_df <- function(df, name) {
    if (!is.null(df) && !inherits(df, "try-error")) {
      utils::write.csv(df, file = file.path(out_dir, paste0(name, ".csv")), row.names = FALSE)
    }
  }
  # E1–E8 CSVs
  save_df(out$E1, "E1_oracle_gap")
  save_df(out$E2, "E2_underfit_prob")
  save_df(out$E3, "E3_minimax_rate")
  save_df(out$E4, "E4_robustness")
  save_df(out$E5, "E5_misspec")
  save_df(out$E6, "E6_optimization")
  save_df(out$E7, "E7_ablations")
  save_df(out$E8, "E8_scaling")
  
  # Lightweight plots (use ggplot2 if available, else base)
  has_gg <- requireNamespace("ggplot2", quietly = TRUE)
  png_safe <- function(name, expr) {
    gr <- grDevices
    path <- file.path(out_dir, paste0(name, ".png"))
    gr$png(path, width = 1200, height = 800, res = 150)
    on.exit(gr$dev.off(), add = TRUE)
    force(expr)
  }
  
  # E1 figure: Delta_sel vs sqrt(log|T|/n_va)
  if (!is.null(out$E1)) {
    df <- out$E1
    png_safe("F1_oracle_gap", {
      if (has_gg) {
        ggplot2::ggplot(df, ggplot2::aes(x = bound, y = delta_sel)) +
          ggplot2::geom_point(alpha = 0.6) +
          ggplot2::geom_smooth(method = "lm", se = FALSE) +
          ggplot2::geom_abline(slope = 1, intercept = 0, linetype = 2) +
          ggplot2::labs(x = expression(sqrt(log(group("|", T, "|"))/n[va])), y = expression(Delta[sel])) +
          ggplot2::theme_minimal()
      } else {
        plot(df$bound, df$delta_sel, pch = 19, col = "gray30",
             xlab = "sqrt(log|T|/n_va)", ylab = "Delta_sel")
        abline(0, 1, lty = 2)
      }
    })
  }
  
  # E3 figure: log–log dH vs n (by k*)
  if (!is.null(out$E3)) {
    df <- out$E3
    png_safe("F3_minimax_rate", {
      if (has_gg) {
        ggplot2::ggplot(df, ggplot2::aes(x = n, y = dH, color = factor(kstar))) +
          ggplot2::geom_point(alpha = 0.6) +
          ggplot2::scale_x_log10() + ggplot2::scale_y_log10() +
          ggplot2::labs(color = "k*", x = "n (log)", y = "d_H (log)") +
          ggplot2::theme_minimal()
      } else {
        cols <- as.integer(as.factor(df$kstar))
        plot(log10(df$n), log10(df$dH), col = cols, pch = 19,
             xlab = "log10 n", ylab = "log10 d_H")
        legend("topright", legend = sort(unique(df$kstar)), col = sort(unique(cols)), pch = 19, title = "k*")
      }
    })
  }
  
  # E4 figure: Robustness — dH vs epsilon
  if (!is.null(out$E4)) {
    df <- out$E4
    png_safe("F4_robustness_dH", {
      if (has_gg) {
        ggplot2::ggplot(df, ggplot2::aes(x = eps, y = dH)) +
          ggplot2::geom_point() + ggplot2::geom_line() +
          ggplot2::labs(x = expression(epsilon), y = "d_H") + ggplot2::theme_minimal()
      } else {
        plot(df$eps, df$dH, type = "b", pch = 19, xlab = "epsilon", ylab = "d_H")
      }
    })
  }
  
  invisible(out_dir)
}

# Convenience one-shot runner
run_and_save_fast <- function() {
  out <- run_two_minute_demo()
  dir <- save_fast_outputs(out)
  message("Saved CSVs and PNGs in: ", dir)
  out
}


# =========================================================
# Extra: E7 variant with runtime, and full figure/table builders
# =========================================================

# E7 with wall-clock timings per replicate
exp_E7_with_time <- function(n = 2000, dgp = make_dgp(kstar = 3), grids = default_grids(), log_dir = NULL) {
  methods <- c("ours","vanilla","trimL")
  res <- list(); id <- 1
  for (m in methods) {
    R <- replicates_for_n(n)
    reps <- lapply(seq_len(R), function(r) {
      t0 <- proc.time()[3]
      z <- run_replicate(n = n, dgp = dgp, grids = grids, method = m, log_dir = log_dir)
      t1 <- proc.time()[3]
      c(method = m,
        dH = z$metrics$dH,
        nll = z$metrics$val_nll,
        iter = z$metrics$iter,
        time_sec = as.numeric(t1 - t0))
    })
    M <- do.call(rbind, reps)
    res[[id]] <- as.data.frame(M)
    id <- id + 1
  }
  do.call(rbind, res)
}

# ---------------- Figures & Tables ----------------

.ensure_dir <- function(path) { dir.create(path, recursive = TRUE, showWarnings = FALSE); path }

make_F1 <- function(df, out_dir) {
  if (is.null(df)) return(invisible())
  out_dir <- .ensure_dir(out_dir)
  grDevices::png(file.path(out_dir, "F1_oracle_gap.png"), 1200, 800, res = 150)
  on.exit(grDevices::dev.off(), add = TRUE)
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    ggplot2::ggplot(df, ggplot2::aes(x = bound, y = delta_sel)) +
      ggplot2::geom_point(alpha = 0.6) +
      ggplot2::geom_smooth(method = "lm", se = FALSE) +
      ggplot2::geom_abline(slope = 1, intercept = 0, linetype = 2) +
      ggplot2::labs(x = expression(sqrt(log(group("|", T, "|"))/n[va])), y = expression(Delta[sel])) +
      ggplot2::theme_minimal() |> print()
  } else { plot(df$bound, df$delta_sel); abline(0,1,lty=2) }
}

make_F2 <- function(df, out_dir) {
  if (is.null(df)) return(invisible())
  out_dir <- .ensure_dir(out_dir)
  grDevices::png(file.path(out_dir, "F2_underfit_probability.png"), 1200, 800, res = 150)
  on.exit(grDevices::dev.off(), add = TRUE)
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    ggplot2::ggplot(df, ggplot2::aes(x = nvagap2, y = p_under, color = factor(sep))) +
      ggplot2::geom_point() + ggplot2::geom_line() +
      ggplot2::geom_line(ggplot2::aes(y = bound), linetype = 2) +
      ggplot2::labs(color = "sep", x = expression(n[va] * Delta[gap]^2), y = "Pr( k_hat < k* )") +
      ggplot2::theme_minimal() |> print()
  } else { plot(df$nvagap2, df$p_under) }
}

make_F3 <- function(df, out_dir) {
  if (is.null(df)) return(invisible())
  out_dir <- .ensure_dir(out_dir)
  grDevices::png(file.path(out_dir, "F3_minimax_rate.png"), 1200, 800, res = 150)
  on.exit(grDevices::dev.off(), add = TRUE)
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    ggplot2::ggplot(df, ggplot2::aes(x = n, y = dH, color = factor(kstar))) +
      ggplot2::geom_point(alpha = 0.6) +
      ggplot2::scale_x_log10() + ggplot2::scale_y_log10() +
      ggplot2::labs(color = "k*", x = "n (log)", y = "d_H (log)") +
      ggplot2::theme_minimal() |> print()
  } else { plot(log10(df$n), log10(df$dH)) }
}

make_F4 <- function(df, out_dir) {
  if (is.null(df)) return(invisible())
  out_dir <- .ensure_dir(out_dir)
  # dH vs eps
  grDevices::png(file.path(out_dir, "F4_robustness_dH.png"), 1200, 800, res = 150)
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    ggplot2::ggplot(df, ggplot2::aes(x = eps, y = dH)) +
      ggplot2::geom_point() + ggplot2::geom_line() +
      ggplot2::labs(x = expression(epsilon), y = "d_H") + ggplot2::theme_minimal() |> print()
  } else { plot(df$eps, df$dH, type = "b") }
  grDevices::dev.off()
  # NLL vs eps
  if (!is.null(df$nll)) {
    grDevices::png(file.path(out_dir, "F4_robustness_NLL.png"), 1200, 800, res = 150)
    if (requireNamespace("ggplot2", quietly = TRUE)) {
      ggplot2::ggplot(df, ggplot2::aes(x = eps, y = nll)) +
        ggplot2::geom_point() + ggplot2::geom_line() +
        ggplot2::labs(x = expression(epsilon), y = "NLL (val)") + ggplot2::theme_minimal() |> print()
    } else { plot(df$eps, df$nll, type = "b") }
    grDevices::dev.off()
  }
  # Hellinger density error vs eps (if present)
  if (!is.null(df$h)) {
    grDevices::png(file.path(out_dir, "F4_robustness_Hellinger.png"), 1200, 800, res = 150)
    if (requireNamespace("ggplot2", quietly = TRUE)) {
      ggplot2::ggplot(df, ggplot2::aes(x = eps, y = h)) +
        ggplot2::geom_point() + ggplot2::geom_line() +
        ggplot2::labs(x = expression(epsilon), y = "Hellinger (density)") + ggplot2::theme_minimal() |> print()
    } else { plot(df$eps, df$h, type = "b") }
    grDevices::dev.off()
  }
}

make_F5 <- function(df, out_dir) {
  if (is.null(df)) return(invisible())
  out_dir <- .ensure_dir(out_dir)
  grDevices::png(file.path(out_dir, "F5_misspec_variance_bias.png"), 1200, 800, res = 150)
  on.exit(grDevices::dev.off(), add = TRUE)
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    ggplot2::ggplot(df, ggplot2::aes(x = h_target, y = dH)) +
      ggplot2::geom_point() + ggplot2::geom_line() +
      ggplot2::geom_line(ggplot2::aes(y = var_term), linetype = 2) +
      ggplot2::geom_abline(intercept = 0, slope = mean(df$dH[df$h_target>0]/df$h_target[df$h_target>0]), linetype = 3) +
      ggplot2::labs(x = "target h (misspec)", y = "d_H", subtitle = "Dashed: variance term; dotted: linear bias proxy") +
      ggplot2::theme_minimal() |> print()
  } else { plot(df$h_target, df$dH, type = "b") }
}

make_F6 <- function(df, log_dir, out_dir) {
  if (is.null(df)) return(invisible())
  out_dir <- .ensure_dir(out_dir)
  # Iterations distribution
  grDevices::png(file.path(out_dir, "F6_iters_hist.png"), 1200, 800, res = 150)
  hist(as.numeric(df$iter), main = "Iterations to tolerance", xlab = "iters"); grDevices::dev.off()
  # Monotonicity violations
  grDevices::png(file.path(out_dir, "F6_monotonicity_violations.png"), 1200, 800, res = 150)
  barplot(table(as.numeric(df$mono_viol)), xlab = "# violations", ylab = "count", main = "L-trim monotonicity")
  grDevices::dev.off()
  # Pruning events
  if (!is.null(df$pruned)) {
    grDevices::png(file.path(out_dir, "F6_pruned_hist.png"), 1200, 800, res = 150)
    hist(as.numeric(df$pruned), main = "Pruned components per run", xlab = "count"); grDevices::dev.off()
  }
  # Example objective trajectory from any JSON log (if available)
  cand <- try(list.files(log_dir, pattern = "\.json$", recursive = TRUE, full.names = TRUE)[1], silent = TRUE)
  if (!inherits(cand, "try-error") && length(cand) && !is.na(cand)) {
    jj <- try(jsonlite::read_json(cand, simplifyVector = TRUE), silent = TRUE)
    if (!inherits(jj, "try-error") && !is.null(jj$fit$obj_hist)) {
      grDevices::png(file.path(out_dir, "F6_objective_trajectory.png"), 1200, 800, res = 150)
      plot(jj$fit$obj_hist, type = "l", xlab = "iteration", ylab = "penalized trimmed obj", main = "Objective per-iter (example)")
      grDevices::dev.off()
    }
  }
}

make_T1 <- function(df, out_dir) {
  if (is.null(df)) return(invisible())
  out_dir <- .ensure_dir(out_dir)
  df$method <- as.character(df$method)
  agg <- aggregate(cbind(dH, nll, iter, time_sec = ifelse(is.na(df$time_sec), NA, df$time_sec)) ~ method, data = df, FUN = function(x) c(mean = mean(as.numeric(x), na.rm=TRUE), se = sd(as.numeric(x), na.rm=TRUE)/sqrt(sum(!is.na(x)))))
  # Flatten
  flat <- data.frame(method = agg$method,
                     dH_mean = sapply(agg$dH, `[`, 1), dH_se = sapply(agg$dH, `[`, 2),
                     nll_mean = sapply(agg$nll, `[`, 1), nll_se = sapply(agg$nll, `[`, 2),
                     iter_mean = sapply(agg$iter, `[`, 1), iter_se = sapply(agg$iter, `[`, 2),
                     time_mean = sapply(agg$time_sec, `[`, 1), time_se = sapply(agg$time_sec, `[`, 2))
  utils::write.csv(flat, file.path(out_dir, "T1_ablation.csv"), row.names = FALSE)
}

make_T2 <- function(df, out_dir) {
  if (is.null(df)) return(invisible())
  out_dir <- .ensure_dir(out_dir)
  agg <- aggregate(cbind(time_sec, iter) ~ n + k, data = df, FUN = function(x) c(mean = mean(as.numeric(x)), se = sd(as.numeric(x))))
  flat <- data.frame(n = agg$n, k = agg$k,
                     time_mean = sapply(agg$time_sec, `[`, 1), time_sd = sapply(agg$time_sec, `[`, 2),
                     iter_mean = sapply(agg$iter, `[`, 1), iter_sd = sapply(agg$iter, `[`, 2))
  utils::write.csv(flat, file.path(out_dir, "T2_scaling.csv"), row.names = FALSE)
}

make_all_figs_tables <- function(out, out_dir = NULL) {
  out_dir <- out_dir %||% file.path(out$log_dir, "summaries")
  .ensure_dir(out_dir)
  # Figures
  make_F1(out$E1, out_dir)
  make_F2(out$E2, out_dir)
  make_F3(out$E3, out_dir)
  make_F4(out$E4, out_dir)
  make_F5(out$E5, out_dir)
  make_F6(out$E6, log_dir = out$log_dir, out_dir)
  # Tables
  dfE7 <- out$E7
  make_T1(dfE7, out_dir)
  make_T2(out$E8, out_dir)
  invisible(out_dir)
}
