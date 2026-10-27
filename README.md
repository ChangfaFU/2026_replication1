# Replication of Kern et al. (2020)

The analysis follows `paper_to_be_replicated.pdf`: 2014 verification, immigrant-sample descriptives and country counts, and the two cross-classified model structures applied to 2018. Added sensitivity models, formal receiving-minus-origin contrasts and simulation power have been removed at the user's request. The previously requested preliminary power calculation from `Secondary data power.pdf` is retained separately.

The user confirmed editorial approval and OSF registration complete; URLs/dates are not recorded. Prior exposure and method differences are documented in [power_assessment.md](results/power_assessment.md).

## Run

```powershell
& 'C:/Program Files/R/R-4.6.0/bin/Rscript.exe' code/replication.R
```

Default execution verifies 2014 first, then fits the two 2018 models and updates reporting tables, the comparison figure and preliminary power. The project is located automatically. Separate modes are `--verify-2014`, `--replicate-2018`, `--power-only`, and `--compare-waves`. Only the 2014 and 2018 participant files are used; excluded earlier waves are not tested.

## Method limits

The supplied 2014 edition 1.1 explicitly removed Lithuania. National birthplace mappings and national coding/release differences remain unresolved, so published 2014 immigrant-model values are benchmarks, not reproduced estimates.

The 2018 implementation follows the paper's conceptual measures and covariates, retaining detailed UK units. It uses WHO LMS, person-weighted sex centring, six-item FAS midrank quintiles within country/age-category/sex and complete-sample age standardisation, without an extra z exclusion. Exact author conventions remain unverified. Both models currently use lme4 ML, whereas the paper used Stata IGLS and MLwiN MCMC. These remain documented approximations; exact replication needs the original settings rather than invented analyses. The cached WHO reference is `data/who2007_bmi_lms.csv`.

## Outputs

Only four reporting files are retained in `results/`:

- `power_assessment.md`: methods, verification findings, results and preliminary power.
- `comparison2014_2018.csv`: published 2014 versus fitted 2018 sample/descriptive/model statistics.
- `country_fai.png`: country-sex reference means and intervals.
- `models2018.png`: the paper's two model structures compared across waves.

Supporting per-wave CSVs, the country-reference CSV and duplicate diagnostic figures were removed on 27 October 2026. Working tables now stay in memory. Routine runs do not recreate removed outputs. `--power-only` and `--compare-waves` use the retained comparison table; `--figures-only` refreshes the two figures without fitting models. Raw input files are unchanged.