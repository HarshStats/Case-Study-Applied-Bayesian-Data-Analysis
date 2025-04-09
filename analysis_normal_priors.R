library(data.table) # For data manipulation
library(ggplot2) # For plotting
library(brms) # For Bayesian modeling
library(bayesplot) # For posterior predictive checks
library(tidyr) # For pivoting data

setwd(dirname(rstudioapi::getActiveDocumentContext()$path))

# 1) Load & prep data
data_path <- "combined_sea_ice_area_extent.csv"
df <- fread(data_path)

df[, Date := as.IDate(Date, format = "%Y-%m-%d")]
df[, Year := year(Date)]
df <- df[Metric == "extent"]

columns_to_drop <- c("Month", "MonthNum")
df <- df[, setdiff(names(df), columns_to_drop), with = FALSE]

# Aggregate by Region & Year
df <- df[, .(Value = mean(Value, na.rm = TRUE)), by = .(Region, Year)]

# Log-transform sea ice extent
df[, LogValue := log(Value)]

# Pivot for hierarchical model
pivot_df <- dcast(df, Year ~ Region, value.var = "LogValue")
long_df <- pivot_df %>%
  pivot_longer(cols = -Year, names_to = "Region", values_to = "LogValue") %>%
  na.omit()


# 2) Specify Priors (explicit, proper, no defaults)
common_priors <- c(
  prior(normal(0, 5), class = "Intercept"),
  prior(normal(0, 2), class = "b"),
  prior(exponential(0.1), class = "sigma"),
  prior(exponential(0.1), class = "sd")
)

# AR(1) prior for the "ar" coefficient
ar_prior <- prior(normal(0, 0.5), class = "ar")


# 3) Fit hierarchical model (No AR)
hierarchical_model_log_noar <- brm(
  formula = bf(LogValue ~ Year + (1 | Region)),
  data = long_df,
  family = gaussian(),
  prior = common_priors,
  iter = 4000,
  warmup = 2000,
  chains = 2,
  cores = 2,
  seed = 42,
  save_pars = save_pars(all = TRUE),
  control = list(adapt_delta = 0.99, max_treedepth = 15)
)

cat("\n--- No-AR Model Summary ---\n")
print(summary(hierarchical_model_log_noar))

# Posterior predictive check
pp_noar <- pp_check(hierarchical_model_log_noar, type = "dens_overlay") +
  ggtitle("PP Check Without AR(1)") +
  xlab("log(Sea Ice Extent)") + ylab("Density") +
  theme_minimal(base_size = 14)

ggsave("figures/ppc_noar_model.pdf",
  pp_noar,
  width = 6,
  height = 4
)


# 4) Fit hierarchical model (AR(1))
hierarchical_model_log_ar1 <- brm(
  formula = bf(LogValue ~ Year + (1 | Region),
    autocor = cor_ar(~ Year | Region, p = 1)
  ),
  data = long_df,
  family = gaussian(),
  prior = c(common_priors, ar_prior),
  iter = 4000,
  warmup = 2000,
  chains = 2,
  cores = 2,
  seed = 42,
  save_pars = save_pars(all = TRUE),
  control = list(adapt_delta = 0.99, max_treedepth = 15)
)

cat("\n--- AR(1) Model Summary ---\n")
print(summary(hierarchical_model_log_ar1))

# Posterior predictive check
pp_ar1 <- pp_check(hierarchical_model_log_ar1, type = "dens_overlay") +
  ggtitle("PP Check With AR(1)") +
  xlab("log(Sea Ice Extent)") + ylab("Density") +
  theme_minimal(base_size = 14)

ggsave("figures/ppc_ar1_model.pdf",
  pp_ar1,
  width = 6,
  height = 4
)


# 5) Model Comparison via LOO
loo_noar <- loo(hierarchical_model_log_noar)
loo_ar1 <- loo(hierarchical_model_log_ar1)

cat("\n--- Pareto k Diagnostics (No-AR): ---\n")
print(loo_noar$diagnostics$pareto_k)

cat("\n--- Pareto k Diagnostics (AR(1)): ---\n")
print(loo_ar1$diagnostics$pareto_k)

model_comp <- loo_compare(loo_noar, loo_ar1)
cat("\n--- Approximate LOO Comparison ---\n")
print(model_comp)


# 6) Trace Plots for Convergence Diagnostics
# Extract MCMC draws from each model
posterior_noar <- as_draws_df(hierarchical_model_log_noar)
posterior_ar1 <- as_draws_df(hierarchical_model_log_ar1)

# Choose parameters to visualize in trace plots
params_noar <- c("b_Intercept", "b_Year", "sd_Region__Intercept", "sigma")
params_ar1 <- c("b_Intercept", "b_Year", "sd_Region__Intercept", "sigma", "ar[1]")

# Generate trace plots for No-AR model
trace_noar <- mcmc_trace(
  posterior_noar,
  pars = params_noar,
  facet_args = list(ncol = 1) # optional layout
) + ggtitle("Trace Plots: No-AR Model")

ggsave(
  filename = "figures/noar_trace_plots.pdf",
  plot     = trace_noar,
  width    = 8,
  height   = 6
)

# Generate trace plots for AR(1) model
trace_ar1 <- mcmc_trace(
  posterior_ar1,
  pars = params_ar1,
  facet_args = list(ncol = 1)
) + ggtitle("Trace Plots: AR(1) Model")

ggsave(
  filename = "figures/ar1_trace_plots.pdf",
  plot     = trace_ar1,
  width    = 8,
  height   = 6
)
