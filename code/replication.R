# Replication base: paper_to_be_replicated.pdf, Kern et al. (2020),
# Sections 1.4 and 2.1-2.3, Tables 1-4, Figures 1-2.
# Secondary data power.pdf governs preliminary effect-size/power assessment.
# Run from project root: Rscript code/replication.R
# Base R execution uses the cached official WHO reference; raw files are unchanged.
args <- commandArgs(trailingOnly = TRUE)
positional <- args[!grepl("^--", args)]
find_project_root <- function(explicit = NULL) {
  is_project <- function(path) file.exists(file.path(path,"Replication_protocol.md")) &&
    file.exists(file.path(path,"paper_to_be_replicated.pdf")) && dir.exists(file.path(path,"data"))
  if (length(explicit)) {
    path <- normalizePath(explicit[1], mustWork=TRUE)
    if (!is_project(path)) stop("The supplied project path must contain Replication_protocol.md, paper_to_be_replicated.pdf and data/: ",path,call.=FALSE)
    return(path)
  }
  script_arg <- grep("^--file=",commandArgs(trailingOnly=FALSE),value=TRUE)
  script_paths <- sub("^--file=","",script_arg)
  # source() records its input file on the calling stack (including RStudio Source).
  source_paths <- unlist(lapply(sys.frames(),function(frame) {
    if (exists("ofile",envir=frame,inherits=FALSE)) get("ofile",envir=frame,inherits=FALSE) else NULL
  }),use.names=FALSE)
  paths <- c(source_paths,script_paths)
  # Run-selection in RStudio may have neither --file nor source() context.
  if (requireNamespace("rstudioapi",quietly=TRUE) && rstudioapi::isAvailable())
    paths <- c(paths,tryCatch(rstudioapi::getSourceEditorContext()$path,error=function(e) character()))
  paths <- paths[!is.na(paths) & nzchar(paths)]
  starts <- c(dirname(paths),getwd())
  for (start in starts) {
    path <- normalizePath(start,mustWork=FALSE)
    if (!dir.exists(path)) next
    repeat {
      if (is_project(path)) return(path)
      parent <- dirname(path)
      if (identical(parent,path)) break
      path <- parent
    }
  }
  stop("Cannot locate the replication project. Run/source code/replication.R, or pass the project directory as the first Rscript argument. Searched from script locations and: ",getwd(),call.=FALSE)
}
root <- find_project_root(positional)
# Published targets, not observed results or imposed sample restrictions.
paper_spec <- list(
  original_wave = 2014L, temporal_replication_wave = 2018L,
  reference_N = 166798L, reference_countries = 41L,
  migration_N = 14024L, participating_origin_N = 8638L,
  complete_case_exclusions = 514L, model_N = 8124L,
  generation15_N = 2603L, generation2_N = 5521L,
  receiving_countries = c("Albania", "Austria", "Belgium", "Bulgaria",
    "Croatia", "Czech Republic", "Denmark", "Estonia", "Finland", "Germany",
    "Greece", "Iceland", "Ireland", "Italy", "Luxembourg", "Portugal",
    "Republic of Moldova", "Romania", "Scotland", "Slovenia", "Spain", "Ukraine", "Wales"),
  outcome = "Perceived status minus WHO-reference actual status; range -4 to 4",
  origin_rule = "Own birthplace for 1.5 generation; maternal birthplace for second generation, falling back to paternal if maternal is missing or receiving country",
  reference_rule = "All adolescents with valid inputs across participating countries, not just immigrants; country-sex mean FAI centred on overall sex-specific mean",
  original_model1_estimator = "Stata IGLS",
  original_model2_estimator = "MLwiN MCMC"
)
stopifnot(length(paper_spec$receiving_countries) == 23L,
  paper_spec$participating_origin_N - paper_spec$complete_case_exclusions == paper_spec$model_N,
  paper_spec$generation15_N + paper_spec$generation2_N == paper_spec$model_N)
# Power-only mode updates only the existing assessment. No audit files are written.
classify_iso_2018 <- function(d, uk = c("detailed", "GB")) {
  uk <- match.arg(uk)
  clean <- function(x) {
    x <- toupper(trimws(x))
    x[x %in% c("", ".", "XX", "ZZ", "UNKNOWN", "99")] <- NA_character_
    x[!is.na(x) & !grepl("^[A-Z]{2}(-[A-Z0-9]+)?$", x)] <- NA_character_
    # Belgium's survey regions map to the paper's country unit.
    x[x %in% c("BE-VLG", "BE-WAL")] <- "BE"
    if (uk == "GB") x[!is.na(x) & grepl("^GB-", x)] <- "GB"
    x
  }
  receiving <- clean(d$region)
  own <- clean(d$countryborn); mother <- clean(d$countrybornmo); father <- clean(d$countrybornfa)
  compare <- function(birth) {
    same <- birth == receiving
    if (uk == "detailed") {
      ambiguous <- !is.na(birth) & !is.na(receiving) &
        ((birth == "GB" & grepl("^GB-", receiving)) |
         (receiving == "GB" & grepl("^GB-", birth)))
      same[ambiguous] <- NA
    }
    same
  }
  self_same <- compare(own); mother_same <- compare(mother); father_same <- compare(father)
  # Three-valued logic preserves unresolved information; no missing-to-native recode.
  migration <- !self_same | !mother_same | !father_same
  generation <- ifelse(!is.na(self_same) & !self_same, "1.5",
    ifelse(!is.na(self_same) & self_same & (!mother_same | !father_same), "2", NA_character_))
  origin <- rep(NA_character_, nrow(d))
  first <- which(generation == "1.5"); second <- which(generation == "2")
  origin[first] <- own[first]
  maternal_foreign <- !is.na(mother_same) & !mother_same
  origin[second] <- ifelse(maternal_foreign[second], mother[second], NA_character_)
  # Paternal fallback only if mother is missing or known native.
  fallback <- second[is.na(mother[second]) | (!is.na(mother_same[second]) & mother_same[second])]
  origin[fallback] <- ifelse(!is.na(father_same[fallback]) & !father_same[fallback], father[fallback], NA_character_)
  if (uk == "detailed") origin[!is.na(origin) & origin == "GB"] <- NA_character_
  one_native <- mother_same | father_same
  data.frame(receiving_iso = receiving, own_iso = own, mother_iso = mother, father_iso = father,
    migration = migration, generation = generation, origin_iso = origin,
    one_native_parent = one_native, origin_in_wave = !is.na(origin) & origin %in% receiving)
}
assess_iso_2018 <- function(uk = c("detailed", "GB")) {
  uk <- match.arg(uk)
  path <- file.path(root, "data", "HBSC2018OAed1.1.csv")
  header <- names(read.table(path, sep = ";", header = TRUE, nrows = 0))
  wanted <- c("region", "countryborn", "countrybornmo", "countrybornfa")
  stopifnot(all(wanted %in% header))
  # 'NA' is Namibia's ISO code: never use it as a string missing-value token.
  d <- read.table(path, sep = ";", header = TRUE, quote = "\"", comment.char = "",
    colClasses = ifelse(header %in% wanted, "character", "NULL"),
    na.strings = c("", " ", "."), strip.white = TRUE)
  z <- classify_iso_2018(d, uk = uk)
  counts <- c(nrow(z), sum(z$migration %in% TRUE), sum(z$migration %in% FALSE),
    sum(is.na(z$migration)), sum(z$generation %in% "1.5"), sum(z$generation %in% "2"),
    sum(!is.na(z$origin_iso)), sum(z$origin_in_wave), sum(z$own_iso %in% "GB"),
    sum(z$mother_iso %in% "GB"), sum(z$father_iso %in% "GB"))
  labels <- c("Imported", "Known migration background", "Known native respondent and both parents",
    "Migration background unresolved", "Generation 1.5", "Second generation", "Exact origin assigned",
    "Assigned origin represented among receiving ISO units", "GB respondent birthplace",
    "GB maternal birthplace", "GB paternal birthplace")
  data.frame(step = labels, n = counts)
}
who_bmi_z <- function(bmi, age, sex, reference) {
  out <- rep(NA_real_, length(bmi))
  for (s in 1:2) {
    ref <- reference[reference$sex == s, ]
    i <- which(sex %in% s & is.finite(bmi) & bmi > 0 & is.finite(age) &
      age * 12 >= min(ref$month) & age * 12 <= max(ref$month))
    if (!length(i)) next
    # Linear interpolation in months; preserves reported fractional-year age.
    p <- lapply(ref[c("L", "M", "S")], function(v) approx(ref$month, v, age[i]*12)$y)
    L <- p$L; M <- p$M; S <- p$S
    z <- ((bmi[i]/M)^L - 1)/(L*S)
    centile <- function(q) M * (1 + L*S*q)^(1/L)
    lo <- z < -3; hi <- z > 3
    z[lo] <- (-3 + (bmi[i]-centile(-3))/(centile(-2)-centile(-3)))[lo]
    z[hi] <- (3 + (bmi[i]-centile(3))/(centile(3)-centile(2)))[hi]
    out[i] <- z
  }
  out
}
country_iso_2014 <- function(cno) {
  mapping <- c(`8`="AL",`40`="AT",`51`="AM",`56`="BE",`100`="BG",`124`="CA",
    `191`="HR",`203`="CZ",`208`="DK",`233`="EE",`246`="FI",`250`="FR",
    `276`="DE",`300`="GR",`304`="GL",`348`="HU",`352`="IS",`372`="IE",
    `376`="IL",`380`="IT",`398`="KZ",`428`="LV",`440`="LT",`442`="LU",
    `470`="MT",`498`="MD",`528`="NL",`578`="NO",`616`="PL",`620`="PT",
    `642`="RO",`643`="RU",`703`="SK",`705`="SI",`724`="ES",`752`="SE",
    `756`="CH",`792`="TR",`804`="UA",`807`="MK",`31`="AZ",`268`="GE",`688`="RS")
  x <- unname(mapping[as.character(floor(cno/1000))])
  x[cno==826001] <- "GB-ENG"; x[cno==826002] <- "GB-SCT"; x[cno==826003] <- "GB-WLS"
  if (anyNA(x)) stop("Unmapped 2014 survey-country code: ",paste(unique(cno[is.na(x)]),collapse=","))
  x
}
# The methodologically reviewed Markdown is maintained as the version of record
# for this local preliminary assessment; do not overwrite it with boilerplate.
run_power <- function() {
  if (any(grepl("^--usable-n=", args)))
    stop("Usable N alone is insufficient; the non-standard power method needs study-lead review.")
  report <- file.path(root, "results", "power_assessment.md")
  if (!file.exists(report)) stop("Reviewed preliminary assessment is missing: ", report)
  effects <- data.frame(effect=c("Origin", "Receiving"), beta=c(.17,.71),
    lower=c(.03,.54), upper=c(.32,.89))
  effects$SE_approx <- (effects$upper-effects$lower)/(2*qnorm(.975))
  effects$absolute_ratio <- abs(effects$beta/effects$SE_approx)
  comparison <- read.csv(file.path(root,"results","comparison2014_2018.csv"))
  candidate <- as.numeric(comparison$fitted_2018[comparison$section=="Sample and descriptives" & comparison$statistic=="Analysis N"])
  stopifnot(length(candidate)==1L,is.finite(candidate),candidate>10)
  N <- candidate; k <- 9L; original_df <- 8124L-k-1L; v <- N-k-1L
  # Requested preliminary benchmark, NOT effective multilevel df or final power.
  effects$r_approx <- effects$absolute_ratio / sqrt(effects$absolute_ratio^2+original_df)
  power_at <- function(r) {
    f2 <- r^2/(1-r^2)
    # Same noncentral F calculation as pwr.f2.test(u=1,v=v,f2=f2).
    pf(qf(.95,1,v),1,v,ncp=f2*(v+2),lower.tail=FALSE)
  }
  effects$tier1 <- vapply(.75*effects$r_approx,power_at,numeric(1))
  effects$tier2 <- vapply(effects$r_approx,power_at,numeric(1))
  if (requireNamespace("pwr",quietly=TRUE)) {
    check <- vapply(effects$r_approx,function(r) pwr::pwr.f2.test(u=1,v=v,
      f2=r^2/(1-r^2),sig.level=.05)$power,numeric(1))
    stopifnot(max(abs(check-effects$tier2))<1e-10)
  }
  if (requireNamespace("effectsize",quietly=TRUE)) {
    check <- effectsize::t_to_r(effects$absolute_ratio,df_error=original_df)$r
    stopifnot(max(abs(check-effects$r_approx))<1e-10)
  }
  section <- c("## 4. Approximate power using the 2018 candidate sample", "",
    "At the user's request, the standard-regression recipe in [the linked RPHB power guidance](https://docs.google.com/document/d/1dg7GZqi1hwIEcXiAqmR7un-wL1V7K33yX3TQ3vHmCDk/edit?tab=t.0) is calculated below as an explicitly conditional preliminary benchmark. The user confirmed that this document and the supplied `Secondary data power.pdf` contain the same guidance; the local PDF is therefore the source used for this calculation. This calculation uses existing summary counts and published statistics only; no new participant outcomes or regression models are analysed.", "",
    "**Two essential decisions remain:** (1) verify the exact COS-assigned focal hypothesis/statistic against the assigned preregistration; and (2) obtain study-lead methodological approval for the power calculation in this cross-classified multilevel design. Neither decision has been confirmed in the supplied materials. Until both are resolved, report the numerical benchmarks without assigning formal Tier 1 or Tier 2 eligibility.", "",
    "**Status: provisional, not adjusted for the multilevel structure.** The guidelines require consultation with the study lead for this cross-classified multilevel design. No study-lead decision approving this power method has been recorded; editorial approval and OSF registration do not themselves establish that the power calculation is design-appropriate.", "",
    "**COS-assigned focal effect: not documented in the supplied materials.** Confirm and insert the assigned effect/statistic from the COS preregistration before submitting a focal power conclusion. Both origin and receiving benchmarks are shown provisionally; neither is selected as focal on the basis of the 2018 findings. If COS assigned a different statistic, these two rows do not supply its power.", "",
    sprintf("**Replication N = %s**, taken from the analysis-N row in comparison2014_2018.csv. Neither full-wave N=244,097 nor the descriptive reference N is used as the immigrant sample. Power is conditional on this analysis definition; methodological and independence limitations remain documented.",format(N,big.mark=",")), "",
    sprintf("**Assumptions:** Model 1 has k=9 fixed-effect slopes, excluding intercept. For this benchmark only, original df=8,124-9-1=%d and replication v=N-9-1=%d. These are independent-observation regression df, not established effective multilevel df. Original SE=rounded CI width/(2*qnorm(.975)); t=abs(beta/SE); partial r=t/sqrt(t^2+original_df). Both origin and receiving candidates are reported without choosing or changing the COS-assigned claim. No contrast power is calculated because coefficient covariance is unavailable.",original_df,v), "",
    "| Model 1 candidate | Beta | Approx. SE | Approx. partial r | Tier 1: 75% of r | Tier 2: 100% of r |", "|---|---:|---:|---:|---:|---:|",
    vapply(seq_len(nrow(effects)),function(i) sprintf("| %s | %.2f | %.5f | %.5f | %.2f%% | %.2f%% |",
      effects$effect[i],effects$beta[i],effects$SE_approx[i],effects$r_approx[i],
      100*effects$tier1[i],100*effects$tier2[i]),character(1)), "",
    "The PDF recipe uses alpha=.05, r_tier1=.75*r_original, r_tier2=r_original, f2=r^2/(1-r^2), and pwr::pwr.f2.test(u=1,v=v,f2=f2,sig.level=.05). Base R computes the equivalent noncentral F power, with ncp=f2*(u+v+1); equivalence is checked against pwr/effectsize when those packages are installed. Tier targets are 90% and 80%, respectively. Displayed 100.00% values are rounded, not certainty.", "",
    "**Why report the 75% benchmark?** Tier 1 asks whether the replication can detect an effect smaller than the originally reported estimate: 75% of the original partial correlation, with a 90% power target. Tier 2 assesses the full original partial correlation with an 80% power target. Reporting only full-effect power would omit this smaller-effect criterion.", "",
    "**Interpretation:** Compare the displayed powers against 90% (Tier 1) and 80% (Tier 2). These numbers do not establish RPHB tier qualification. Country-level information, cross-classification, survey clustering/weights and generated contextual means are not accounted for. Approximate partial r and usable N require review. Added simulation analyses are excluded from the current scope. The PDF explicitly requires study-lead escalation for this non-standard design. Changing original df also changes converted r, so this is not a conservative or design-adjusted power estimate.", "")
  text <- readLines(report,warn=FALSE)
  start <- grep("^## 4\\.",text)
  end <- grep("^### Four design questions and two validity questions",text)
  stopifnot(length(start)==1L,length(end)==1L,end>start)
  writeLines(c(text[seq_len(start-1L)],section,text[seq.int(end,length(text))]),report)
  print(effects, row.names=FALSE)
  message("Updated only the approximate-power section: ", report,
    ". Multilevel power remains pending. No survey files read by run_power().")
  invisible(effects)
}
verify_2014 <- function() {
  # Reads only the original-wave CSV; no 2018 participant records or models.
  path <- file.path(root,"data","HBSC2014OAed1.1_F1.csv")
  d <- read.csv(path,na.strings=c("","."),check.names=FALSE)
  names(d) <- tolower(names(d))
  expected <- c(thinkbody=201130,bodyweight=183730,bodyheight=183139,
    age=212226,m133=127661,m134=126164,m135=125628)
  observed <- vapply(names(expected),function(v) sum(!is.na(d[[v]])),integer(1))
  stopifnot(nrow(d)==214080L,!anyDuplicated(d$uniqueid),identical(as.integer(expected),as.integer(observed)),
    all(na.omit(d$sex) %in% 1:2),all(na.omit(d$thinkbody) %in% 1:5))
  country <- country_iso_2014(d$countryno)
  stopifnot(!any(country=="LT"))
  ref <- read.csv(file.path(root,"data","who2007_bmi_lms.csv"))
  stopifnot(max(abs(who_bmi_z(c(30,14,19),c(11,16,9),c(1,1,1),ref)-c(3.35,-3.80,1.47)))<.025)
  stopifnot(max(abs(who_bmi_z(c(30,14,19),c(11,16,9),c(1,1,1),ref)-c(3.35,-3.80,1.47)))<.025)
  bmi <- d$bodyweight/(d$bodyheight/100)^2
  bmi[!is.finite(bmi)|d$bodyweight<=0|d$bodyheight<=0] <- NA_real_
  z <- who_bmi_z(bmi,d$age,d$sex,ref)
  fai <- d$thinkbody-as.integer(cut(z,c(-Inf,-2,-1,1,2,Inf),right=FALSE))
  # No undocumented z exclusion in the verification main line; retain it as sensitivity.
  valid <- is.finite(fai)
  screened <- valid & z>=-5 & z<=5
  birth <- d[c("m133","m134","m135")]
  migration <- Reduce(`|`,lapply(birth,function(x) x %in% 2:6))
  first <- d$m133 %in% 2:6
  second <- d$m133 %in% 1 & (d$m134 %in% 2:6 | d$m135 %in% 2:6)
  inputs <- vapply(birth,function(x) sum(x %in% 1:6),integer(1))
  # Coverage counts do not pretend to recover exact origin from category numbers.
  tab <- do.call(rbind,lapply(split(seq_len(nrow(d)),country),function(i) data.frame(
    country=country[i[1]],imported_N=length(i),FAI_N=sum(valid[i]),screened_FAI_N=sum(screened[i]),
    own_birth_N=sum(d$m133[i] %in% 1:6),maternal_birth_N=sum(d$m134[i] %in% 1:6),
    paternal_birth_N=sum(d$m135[i] %in% 1:6),migration_N=sum(migration[i]),
    migration_with_FAI_N=sum(migration[i]&valid[i]),generation15_N=sum(first[i]),generation2_N=sum(second[i]))))
  stat <- do.call(rbind,lapply(split(which(valid),paste(country[valid],d$sex[valid])),function(i) {
    n <- length(i); m <- mean(fai[i]); se <- sd(fai[i])/sqrt(n)
    data.frame(country=country[i[1]],sex=d$sex[i[1]],n=n,mean=m,
      lower=m-qt(.975,n-1)*se,upper=m+qt(.975,n-1)*se)
  }))
  counts <- c(sum(valid),sum(screened),sum(migration),sum(migration&valid),sum(first),sum(second))
  labels <- c("Valid reference FAI; no extra z screen","Valid reference FAI; provisional [-5,5] screen",
    "Known migration background; all imported","Known migration background with valid FAI",
    "Generation 1.5; all imported","Second generation; all imported")
  report <- file.path(root,"results","power_assessment.md")
  text <- readLines(report,warn=FALSE)
  marker <- "## 7. Original-wave verification: 2014 only"
  previous <- which(text==marker)
  later_sections <- character()
  if (length(previous)) {
    next_heading <- which(seq_along(text)>previous[1] & grepl("^## ",text))
    if(length(next_heading)) later_sections <- text[seq.int(next_heading[1],length(text))]
    text <- text[seq_len(previous[1]-1L)]
  }
  section <- c(marker,"","Approval and registration were confirmed complete by the user in this conversation. URLs/dates have not been supplied. Following the user's latest instruction, this run verifies only 2014 and does not analyse 2018 participant records.","",
    "**Release difference verified in the supplied codebook:** p.4 explicitly states that OA edition 1.1 removed Lithuanian data. This is a documented release difference, not just an inferred absent code. The article includes Lithuania in its reference population and Table 2. Matching all original observations therefore needs an appropriate authorised release or the missing national data, as well as the birthplace crosswalk.","",
    "**Import checks passed:** 214,080 records, unique respondent IDs, and seven observed nonmissing counts match the codebook: perceived weight 201,130; bodyweight 183,730; bodyheight 183,139; age 212,226; own/maternal/paternal birthplace 127,661 / 126,164 / 125,628. Sex and perceived-weight values match documented categories. There are 41 raw survey-country codes but 40 units after combining Belgian regions.","",
    "| Verification stage | Observed 2014 N |","|---|---:|",
    vapply(seq_along(counts),function(i)sprintf("| %s | %d |",labels[i],counts[i]),character(1)),"",
    sprintf("Relative to the paper's reference N=166,798, the unscreened WHO-LMS construction is short by %d. The extra provisional z screen removes a further %d records. Missing Lithuania could contribute to the former gap, but neither its complete-case N nor the original scoring/exclusions are available to prove exact reconciliation. The primary line of this verification therefore applies no additional undocumented z exclusion; the previous screened table is retained as sensitivity, not relabelled as the paper's method.",166798-sum(valid),sum(valid)-sum(screened)),"",
    "The all-file migration counts above are not the paper's selected N=14,024, nor are the generation counts comparable to its final 2,603 / 5,521 until exact-origin and complete-case restrictions are applied. Countries with migration questions but no eligible participating origins can disappear after selection. No origin country is inferred from category rank.","",
    "**Additional receiving-country inconsistency:** Table 1 reports 333 eligible immigrants in the Republic of Moldova. The supplied file yields zero known migration-background records for MD under the generic dictionary's 1=native, 2-6=foreign coding. Thus a national crosswalk for codes 2-5 alone cannot be presumed to resolve every sample difference. Ask the provider/authors about the national raw coding and release processing, and verify any national exception before recoding.","",
    sprintf("With naive individual-level 95%% t intervals, girls' means are above zero in %d of 40 available countries; boys' means are above zero in %d and below zero in %d. The paper reports 37/41 for girls and 9/41 above, 24/41 below for boys. These are diagnostic counts only: coverage differs and the paper's exact interval/design convention is not verified.",sum(stat$lower[stat$sex==2]>0),sum(stat$lower[stat$sex==1]>0),sum(stat$upper[stat$sex==1]<0)),"",


    "**Verification outcome:** released-data integrity and partial reference-population patterns are checked. Tables 1-4 are not verified. The concrete missing inputs are (1) an authorised 2014 release including Lithuania, (2) national birthplace labels for m133/m134/m135 choices 2-5 and original category-6 treatment, and (3) author-equivalent WHO/exclusion, FAS and estimation settings. Searches of available public material did not recover a verified national crosswalk. The official data-provider page was inaccessible to the browsing tool; this is not evidence that the mappings do not exist. No external messages or restricted-data requests were sent.")
  writeLines(c(text,"",section,"",later_sections),report)
  print(data.frame(stage=labels,n=counts),row.names=FALSE)
  message("2014 verification complete to the extent supported by this release; exact-origin models remain unresolved. No 2018 analysis run.")
}
compare_waves <- function(m=NULL,d=NULL) {
  if(!is.null(m) && !is.null(d)) {


  a <- m[m$scenario=="primary_unscreened",]
  get_stat <- function(variable) d[d$generation=="All" & d$variable==variable,]
  n <- unique(a$n); stopifnot(length(n)==1)
  rows <- list()
  add <- function(section,statistic,paper,current,note="") {
    rows[[length(rows)+1L]] <<- data.frame(section=section,statistic=statistic,
      published_2014=paper,fitted_2018=current,note=note,stringsAsFactors=FALSE)
  }
  add("Sample and descriptives","Analysis N","8124",as.character(n),"Different waves and eligible populations")
  add("Sample and descriptives","Receiving countries","23",as.character(unique(a$receiving_countries)))
  add("Sample and descriptives","Origin countries","41",as.character(unique(a$origin_countries)))
  add("Sample and descriptives","Generation 1.5 N","2603",as.character(unique(d$n[d$generation=="1.5"])))
  add("Sample and descriptives","Second generation N","5521",as.character(unique(d$n[d$generation=="2"])))
  v <- get_stat("girl");add("Sample and descriptives","Girls (%)","51",sprintf("%.2f",100*v$mean))
  for (v in c("fai","age","fas_quintile","bmi_z")) {
    stat<-get_stat(v)
    published<-switch(v,fai="0.19 (0.89)",age="13.83 (1.65)",fas_quintile="3.09 (1.43)",bmi_z="-0.01 (1.22)")
    label<-switch(v,fai="FAI mean (SD)",age="Age mean (SD)",fas_quintile="FAS quintile mean (SD)",bmi_z="BMI z-score mean (SD)")
    add("Sample and descriptives",label,published,sprintf("%.2f (%.2f)",stat$mean,stat$sd),
      if(v%in%c("fas_quintile","bmi_z"))"Author-equivalent scoring not established" else "")
  }
  terms<-c("age_z","girl","age_z:girl","fas_quintile","generation15","one_native_parent","bmi_z","receiving_standard","origin_standard")
  labels<-c("Standardised age","Girl","Girl x age","FAS quintile","Generation 1.5","Native-parent indicator","BMI z-score","Receiving-country standard","Origin-country standard")
  b1<-c(-.03,.34,.11,.01,-.01,.06,-.29,.71,.17)
  lo1<-c(-.05,.31,.07,0,-.05,.02,-.31,.54,.03);hi1<-c(0,.38,.14,.02,.03,.10,-.28,.89,.32)
  b2<-c(-.03,.34,.11,.01,-.02,.07,-.29,.80,.04)
  lo2<-c(-.05,.30,.07,0,-.04,.03,-.31,.52,-.19);hi2<-c(0,.37,.14,.02,.08,.11,-.28,1.07,.26)
  format_est<-function(b,lo,hi)sprintf("%.3f [%.3f, %.3f]",b,lo,hi)
  for (model in c("Model 1 ML","Model 2 ML approximation")) {
    part<-a[a$model==model,];is_m1<-model=="Model 1 ML"
    for (i in seq_along(terms)) {
      z<-part[part$term==terms[i],];stopifnot(nrow(z)==1)
      add(if(is_m1)"Model 1" else "Model 2",labels[i],
        format_est(if(is_m1)b1[i] else b2[i],if(is_m1)lo1[i] else lo2[i],if(is_m1)hi1[i] else hi2[i]),
        format_est(z$estimate,z$lower,z$upper),if(is_m1)"2014 IGLS vs 2018 ML; intervals normal" else "2014 MCMC posterior vs 2018 ML normal intervals")
    }
    if(!is_m1) {
      for (i in 1:2) {
        term<-c("receiving_standard:generation15","origin_standard:generation15")[i]
        z<-part[part$term==term,]
        add("Model 2",c("Generation 1.5 x receiving standard","Generation 1.5 x origin standard")[i],
          format_est(c(-.19,.24)[i],c(-.52,-.11)[i],c(.16,.60)[i]),format_est(z$estimate,z$lower,z$upper),
          "2014 MCMC posterior vs 2018 ML normal intervals")
      }
    }
  }
  comparison<-do.call(rbind,rows)
  write.csv(comparison,file.path(root,"results","comparison2014_2018.csv"),row.names=FALSE)
  } else comparison <- read.csv(file.path(root,"results","comparison2014_2018.csv"))
  report<-file.path(root,"results","power_assessment.md");text<-readLines(report,warn=FALSE)
  marker<-"## 9. Side-by-side comparison: published 2014 and fitted 2018"
  previous<-which(text==marker);tail<-character()
  if(length(previous)) {
    next_section<-which(seq_along(text)>previous[1] & grepl("^## ",text))
    if(length(next_section))tail<-text[seq.int(next_section[1],length(text))]
    text<-text[seq_len(previous[1]-1L)]
  }
  lines<-c(marker,"","**2014 values are published benchmarks from Kern et al. Tables 1-4, not reproduced estimates.** The 2018 values are from the primary unscreened complete-case ML specification. Mean (SD) is shown for descriptives; regression cells show coefficient [95% interval]. The 2014 Model 2 intervals are Bayesian posterior intervals; all 2018 intervals are normal ML approximations.")
  for(section in unique(comparison$section)) {
    z<-comparison[comparison$section==section,]
    lines<-c(lines,"",paste0("### ",section),"","| Statistic | Published 2014 | Fitted 2018 |","|---|---|---|",
      vapply(seq_len(nrow(z)),function(i)sprintf("| %s | %s | %s |",z$statistic[i],z$published_2014[i],z$fitted_2018[i]),character(1)))
  }
  lines<-c(lines,"","2018 retains more origin/receiving countries and uses documented FAS, age-scaling and BMI assumptions. Table differences therefore combine population, measurement and estimation differences. Model 2 main contextual effects refer to second-generation adolescents (generation 1.5 indicator=0). Neither differing point estimates nor significance in one wave alone establishes temporal change; a dependence-aware cross-wave test is required. ","",
    "[Download the comparison table](comparison2014_2018.csv). This table is generated from existing model/descriptive outputs and transcribed published benchmarks; no models were rerun.")
  writeLines(c(text,"",lines,"",tail),report)
  message("Updated side-by-side comparison CSV and assessment; no participant data read.")
  invisible(comparison)
}
replicate_2018 <- function() {
  if (!requireNamespace("lme4",quietly=TRUE)) stop("lme4 is required.")
  number <- function(x) suppressWarnings(as.numeric(gsub(",",".",x,fixed=TRUE)))
  message("2018: importing, constructing WHO outcomes and FAS quintiles")
  d <- read.table(file.path(root,"data","HBSC2018OAed1.1.csv"),header=TRUE,sep=";",
    quote="\"",comment.char="",colClasses="character",na.strings=c(""," ","."),strip.white=TRUE)
  ref <- read.csv(file.path(root,"data","who2007_bmi_lms.csv"))
  age <- number(d$age); sex <- number(d$sex); agecat <- number(d$agecat)
  bmi <- number(d$bodyweight)/(number(d$bodyheight)/100)^2
  bmi[!is.finite(bmi)|number(d$bodyweight)<=0|number(d$bodyheight)<=0] <- NA_real_
  z <- who_bmi_z(bmi,age,sex,ref)
  perceived <- number(d$thinkbody); perceived[!perceived %in% 1:5] <- NA_real_
  fai <- perceived-as.integer(cut(z,c(-Inf,-2,-1,1,2,Inf),right=FALSE))
  items <- lapply(d[c("fasfamcar","fasbedroom","fascomputers","fasbathroom","fasdishwash","fasholidays")],number)
  items <- Map(function(x,maxv) {x[!x %in% seq_len(maxv)]<-NA_real_;x-1},items,c(3,2,4,4,2,4))
  fas_sum <- Reduce(`+`,items)
  construct <- function() {
    iso <- classify_iso_2018(d,"detailed")
    valid <- is.finite(fai)

    reference_valid <- valid

    country <- iso$receiving_iso
    key <- paste(country,sex)
    groups <- split(which(reference_valid),key[reference_valid])
    means <- vapply(groups,function(i)mean(fai[i]),numeric(1))
    counts <- vapply(groups,length,integer(1))
    centre <- vapply(1:2,function(s)mean(fai[reference_valid&sex %in% s]),numeric(1))
    R <- unname(means[key])-centre[sex]
    O <- unname(means[paste(iso$origin_iso,sex)])-centre[sex]
    # Relative FAS is constructed in the full-wave country/age-category/sex frame,
    # before immigrant restriction. Average ranks preserve ties.
    quintile <- rep(NA_real_,nrow(d))
    fas_valid <- is.finite(fas_sum)&agecat %in% 1:3&sex %in% 1:2
    fas_groups <- split(which(fas_valid),paste(country[fas_valid],agecat[fas_valid],sex[fas_valid]))
    for (i in fas_groups) quintile[i] <- pmin(5,pmax(1,ceiling(5*(rank(fas_sum[i],ties.method="average")-.5)/length(i))))
    x <- data.frame(fai=fai,receiving_standard=R,origin_standard=O,age=age,
      girl=as.integer(sex==2),fas_quintile=quintile,bmi_z=z,
      generation15=as.integer(iso$generation=="1.5"),one_native_parent=as.integer(iso$one_native_parent),
      receiving=country,origin=iso$origin_iso)
    immigrant <- iso$migration %in% TRUE
    standard_ok <- is.finite(R)&is.finite(O)
    eligible <- immigrant&valid&standard_ok&complete.cases(x)
    x <- x[eligible,]
    stopifnot(nrow(x)>100,sd(x$age)>0,all(x$fas_quintile %in% 1:5))
    x$age_z <- as.numeric(scale(x$age))
    x$receiving <- factor(x$receiving); x$origin <- factor(x$origin)
    list(data=x,flow=c(imported=nrow(d),reference=sum(valid),known_migration=sum(iso$migration %in% TRUE),
      origin_and_receiving_standard=sum(immigrant&standard_ok),complete=nrow(x)))
  }
  fit <- function(x,interactions=FALSE) {
    formula <- fai ~ receiving_standard+origin_standard+age_z*girl+fas_quintile+bmi_z+
      generation15+one_native_parent+(1|receiving)+(1|origin)
    if(interactions) formula <- update(formula,.~.+generation15:receiving_standard+generation15:origin_standard)
    lme4::lmer(formula,data=x,REML=FALSE,control=lme4::lmerControl(optimizer="bobyqa",optCtrl=list(maxfun=100000)))
  }
  convergence_messages <- function(m) {
    messages <- m@optinfo$conv$lme4$messages
    # A zero random-effect variance is a valid boundary fit, not optimizer failure.
    messages <- messages[!grepl("boundary.*singular",messages)]
    if (length(m@optinfo$conv$opt) && any(m@optinfo$conv$opt != 0))
      messages <- c(messages,"Nonzero optimizer status")
    messages
  }
  extract <- function(m,scenario,model) {
    b<-lme4::fixef(m); V<-as.matrix(vcov(m)); se<-sqrt(diag(V))
    estimate<-b
    data.frame(scenario=scenario,model=model,term=names(estimate),estimate=as.numeric(estimate),se=as.numeric(se),
      lower=as.numeric(estimate-qnorm(.975)*se),upper=as.numeric(estimate+qnorm(.975)*se),
      p_normal=2*pnorm(-abs(estimate/se)),n=nobs(m),receiving_countries=nlevels(model.frame(m)$receiving),
      origin_countries=nlevels(model.frame(m)$origin),singular=lme4::isSingular(m),
      convergence=if(!length(convergence_messages(m)))"OK" else paste(convergence_messages(m),collapse=";"))
  }
  primary<-construct(); x<-primary$data
  message("2018: primary complete sample N=",nrow(x),"; fitting both models")
  m1<-fit(x); m2<-fit(x,TRUE)
  results<-rbind(extract(m1,"primary_unscreened","Model 1 ML"),extract(m2,"primary_unscreened","Model 2 ML approximation"))
  flows<-list(data.frame(scenario="primary_unscreened",stage=names(primary$flow),n=unname(primary$flow)))
  # Primary descriptive statistics correspond to the actual regression sample.
  desc<-do.call(rbind,lapply(c("All","1.5","2"),function(g){
    a<-if(g=="All")x else x[x$generation15==as.integer(g=="1.5"),]
    do.call(rbind,lapply(c("fai","age","fas_quintile","bmi_z","girl"),function(v)
      data.frame(generation=g,n=nrow(a),variable=v,mean=mean(a[[v]]),sd=sd(a[[v]]),min=min(a[[v]]),max=max(a[[v]]))))
  }))
  coverage<-rbind(data.frame(type="receiving",country=names(table(x$receiving)),n=as.integer(table(x$receiving))),
    data.frame(type="origin",country=names(table(x$origin)),n=as.integer(table(x$origin))))
  compare_waves(results,desc)
  run_power()
  report<-file.path(root,"results","power_assessment.md");text<-readLines(report,warn=FALSE)
  marker<-"## 8. Full-sample 2018 replication under documented approximations"
  start<-which(text==marker);if(length(start))text<-text[seq_len(start[1]-1L)]
  focus<-results[results$scenario=="primary_unscreened" & results$term%in%c("origin_standard","receiving_standard","receiving_minus_origin","receiving_standard:generation15","origin_standard:generation15","generation15:receiving_standard","generation15:origin_standard"),]
  vc<-as.data.frame(lme4::VarCorr(m1))
  section<-c(marker,"","Approval and OSF registration were confirmed complete by the user; identifiers/dates remain unrecorded. The user requested 2018 analysis after the 2014 check. The original 2014 models remain unreproduced: effect and variance inputs below come from published Table 4, not from a fitted 2014 reproduction.","",
    sprintf("**Primary 2018 model N=%d**, with %d receiving and %d origin countries. The primary outcome uses WHO LMS with no extra z screen, following the latest 2014 verification; the earlier screened N=13,858 is a superseded diagnostic count, not this model N.",nrow(x),nlevels(x$receiving),nlevels(x$origin)),"",
    "**Explicit approximations fixed before these fits:** unweighted reference means including immigrants; person-weighted sex-specific grand centring; six FAS items recoded from 1-based to 0-based and summed; country x age-category x sex midrank percentiles, quintiles ceiling(5*p) preserving ties; age z-standardised within each complete analysis sample; at-least-one-known-native-parent coding; missing own birthplace/generation unresolved; detailed UK geographic units matching the paper. The age-category rather than exact-age FAS stratification is an approximation requiring methodological review. The same sample is used for Models 1 and 2.","",
    "Model 1 and Model 2 both use lme4 maximum likelihood, retaining origin and receiving random intercepts. Model 2 adds both generation interactions but is NOT the paper's Bayesian MLwiN MCMC model. Intervals/p-values are asymptotic normal approximations, without survey-weight or school-cluster correction. These are implemented temporal-replication estimates under stated assumptions, not an exact reproduction of the original estimators.","",
    "| Model | Term | Estimate | 95% interval | Normal p |","|---|---|---:|---|---:|",
    vapply(seq_len(nrow(focus)),function(i)sprintf("| %s | %s | %.3f | [%.3f, %.3f] | %.4f |",focus$model[i],focus$term[i],focus$estimate[i],focus$lower[i],focus$upper[i],focus$p_normal[i]),character(1)),"",
    "For this primary ML approximation, the receiving-country association is positive and its interval excludes zero; the origin-country interval includes zero. This supports the receiving component in this specification, but does not reproduce the paper's positive origin finding. The Model 2 interaction intervals must be interpreted jointly with their estimation differences; lack of significance is not evidence that effects are identical across generations.","",
    sprintf("Model 1 variance components: %s. Singular fits: Model 1=%s, Model 2=%s. Inspect the convergence/singular columns in the full model table; a boundary origin variance is retained, not silently dropped.",paste(sprintf("%s=%.5f",vc$grp,vc$vcov),collapse="; "),lme4::isSingular(m1),lme4::isSingular(m2)),"",
    "### Outputs and limits","",
    "[Published 2014 and fitted 2018 comparison table](comparison2014_2018.csv)","",
    "![2018 contextual coefficients and published 2014 benchmarks](models2018.png)","",
    "Scope is restricted to the paper's two model structures and reporting tables. Additional sensitivity models, generated-regressor variants and simulation power have been removed at the user's request. Differences in significance between waves are not themselves a test of temporal change. No causal interpretation is warranted. Exact 2014 verification, author-equivalent FAS/BMI conventions, Bayesian Model 2 and survey/school-adjusted inference remain unresolved; this run completes the documented ML approximation rather than those outstanding methods.")
  writeLines(c(text,"",section),report)
  compare_waves()
  update_figures()
  capture.output(sessionInfo(),file=file.path(root,"environment","session_info.txt"))
  print(focus)
  invisible(list(model1=m1,model2=m2,sample=x))
}
update_figures <- function() {
  # Refresh reporting figures only; no model fitting or additional analyses.
  number <- function(x) suppressWarnings(as.numeric(gsub(",",".",x,fixed=TRUE)))
  ref <- read.csv(file.path(root,"data","who2007_bmi_lms.csv"))
  stats <- list()
  for (wave in c("2014","2018")) {
    file <- if(wave=="2014") "HBSC2014OAed1.1_F1.csv" else "HBSC2018OAed1.1.csv"
    sep <- if(wave=="2014") "," else ";"
    path <- file.path(root,"data",file)
    header <- names(read.table(path,header=TRUE,sep=sep,nrows=0,check.names=FALSE))
    wanted <- tolower(header) %in% c("age","sex","bodyweight","bodyheight","thinkbody","countryno","region")
    d <- read.table(path,header=TRUE,sep=sep,quote="\"",comment.char="",check.names=FALSE,
      colClasses=ifelse(wanted,"character","NULL"),na.strings=c(""," ","."),strip.white=TRUE)
    names(d) <- tolower(names(d)); sex<-number(d$sex);age<-number(d$age)
    bmi<-number(d$bodyweight)/(number(d$bodyheight)/100)^2
    bmi[!is.finite(bmi)|number(d$bodyweight)<=0|number(d$bodyheight)<=0]<-NA_real_
    z<-who_bmi_z(bmi,age,sex,ref);perceived<-number(d$thinkbody)
    perceived[!perceived %in% 1:5]<-NA_real_
    fai<-perceived-as.integer(cut(z,c(-Inf,-2,-1,1,2,Inf),right=FALSE))
    country<-if(wave=="2014")country_iso_2014(number(d$countryno)) else {
      x<-toupper(trimws(d$region));x[x%in%c("BE-VLG","BE-WAL")]<-"BE";x
    }
    valid<-is.finite(fai)&sex%in%1:2
    stats[[wave]]<-do.call(rbind,lapply(split(which(valid),paste(country[valid],sex[valid])),function(i){
      n<-length(i);m<-mean(fai[i]);sd<-sd(fai[i]);half<-qt(.975,n-1)*sd/sqrt(n)
      data.frame(wave=wave,country=country[i[1]],sex=sex[i[1]],n=n,mean_fai=m,sd_fai=sd,
        lower= m-half,upper=m+half,
        centered_person=m-mean(fai[valid&sex%in%sex[i[1]]]))
    }))
  }
  st<-do.call(rbind,stats)
  stopifnot(sum(st$n[st$wave==2014])==163139,sum(st$n[st$wave==2018])==181999)

  blue<-"#176B87";orange<-"#BC572F";grey<-"#666666"
  draw_country<-function(a,codes,title,col) {
    a<-a[match(codes,a$country),];y<-seq_along(codes)
    plot(NA,xlim=range(st$lower,st$upper,na.rm=TRUE),ylim=c(.5,length(codes)+.5),yaxt="n",
      xlab="Mean FAI (95% interval)",ylab="",main=title,bty="l")
    abline(v=0,lty=2,col="grey75");axis(2,at=y,labels=codes,las=1,cex.axis=.57)
    segments(a$lower,y,a$upper,y,col=col);points(a$mean_fai,y,pch=16,col=col,cex=.62)
  }
  png(file.path(root,"results","country_fai.png"),width=2300,height=2100,res=190)
  par(mfrow=c(2,2),mar=c(4,6,3,1),oma=c(3,0,2,0))
  for(s in c(2,1)) {
    a<-st[st$wave==2014&st$sex==s,];b<-st[st$wave==2018&st$sex==s,]
    codes<-c(a$country[order(a$mean_fai)],sort(setdiff(b$country,a$country)))
    draw_country(a,codes,paste("2014 public file:",if(s==2)"girls" else "boys"),blue)
    draw_country(b,codes,paste("2018:",if(s==2)"girls" else "boys"),orange)
  }
  mtext("Country-sex weight-evaluation standards",side=3,outer=TRUE,line=.4,font=2,cex=1.1)
  mtext("Unscreened WHO-LMS reference populations; unweighted, naive individual-level intervals. Lithuania absent in 2014.",side=1,outer=TRUE,line=.8,cex=.75)
  dev.off()
  # Paper Table 4 estimates versus the corresponding fitted 2018 coefficients.
  m<-read.csv(file.path(root,"results","comparison2014_2018.csv"))
  terms<-c("age_z","girl","age_z:girl","fas_quintile","generation15","one_native_parent","bmi_z","receiving_standard","origin_standard")
  labels<-c("Standardised age","Girl","Girl x age","FAS quintile","Generation 1.5","Native-parent indicator","BMI z-score","Receiving-country standard","Origin-country standard")
  b<-list(c(-.03,.34,.11,.01,-.01,.06,-.29,.71,.17),c(-.03,.34,.11,.01,-.02,.07,-.29,.80,.04,-.19,.24))
  lo<-list(c(-.05,.31,.07,0,-.05,.02,-.31,.54,.03),c(-.05,.30,.07,0,-.04,.03,-.31,.52,-.19,-.52,-.11))
  hi<-list(c(0,.38,.14,.02,.03,.10,-.28,.89,.32),c(0,.37,.14,.02,.08,.11,-.28,1.07,.26,.16,.60))
  png(file.path(root,"results","models2018.png"),width=2100,height=1150,res=170)
  par(mfrow=c(1,2),mar=c(5,11,4,1),oma=c(5,0,2,0))
  for(j in 1:2) {
    t<-terms;lab<-labels
    if(j==2){t<-c(t,"receiving_standard:generation15","origin_standard:generation15");lab<-c(lab,"Generation 1.5 x receiving standard","Generation 1.5 x origin standard")}
    a<-m[m$section==paste("Model",j),];a<-a[match(lab,a$statistic),]
    values<-t(vapply(a$fitted_2018,function(value)scan(text=gsub("[^0-9.eE+-]"," ",value),quiet=TRUE),numeric(3)))
    a<-data.frame(estimate=values[,1],lower=values[,2],upper=values[,3])
    stopifnot(!anyNA(a$estimate));y<-rev(seq_along(t))
    plot(NA,xlim=c(-.57,1.12),ylim=c(.5,length(t)+.5),yaxt="n",xlab="Coefficient (95% interval)",ylab="",bty="l",
      main=paste("Model",j))
    axis(2,at=y,labels=lab,las=1,cex.axis=.65);abline(v=0,lty=2,col="grey75")
    segments(lo[[j]],y+.12,hi[[j]],y+.12,col=grey);points(b[[j]],y+.12,pch=17,col=grey,cex=.8)
    segments(a$lower,y-.12,a$upper,y-.12,col=blue);points(a$estimate,y-.12,pch=16,col=blue,cex=.8)
    legend("bottomright",c("2014 published","2018 fitted ML"),pch=c(17,16),col=c(grey,blue),bty="n",cex=.7)
  }
  mtext("Paper model coefficients: published 2014 and fitted 2018",side=3,outer=TRUE,font=2,cex=1.1)
  mtext("2014 estimates are published benchmarks, not reproduced fits. Model 2: original posterior intervals versus 2018 normal ML intervals.",side=1,outer=TRUE,line=1,cex=.68)
  mtext("Author-equivalent FAS/BMI coding and original IGLS/MCMC estimators remain unverified. No added sensitivity models or contrasts.",side=1,outer=TRUE,line=2.4,cex=.68)
  dev.off()
  message("Updated the two retained reporting figures; no models refitted or intermediate tables written.")
}
if ("--figures-only" %in% args) {
  update_figures()
  quit(save="no",status=0)
}
if ("--compare-waves" %in% args) {
  compare_waves()
  quit(save="no",status=0)
}
if ("--replicate-2018" %in% args) {
  replicate_2018()
  quit(save="no",status=0)
}
if ("--verify-2014" %in% args) {
  verify_2014()
  quit(save="no",status=0)
}
if ("--power-only" %in% args) {
  run_power()
  quit(save = "no", status = 0)
}
for (folder in c("results", "environment"))
  dir.create(file.path(root, folder), showWarnings = FALSE)
verify_2014()
replicate_2018()
# Downstream helpers: not called by the audit. Use only after the protocol is
# resolved and approved derived data have been independently validated.
construct_fai <- function(perceived, who_bmi_z) {
  stopifnot(length(perceived) == length(who_bmi_z))
  perceived[!perceived %in% 1:5] <- NA_real_
  actual <- cut(who_bmi_z, c(-Inf, -2, -1, 1, 2, Inf), right = FALSE, labels = FALSE)
  perceived - actual
}
