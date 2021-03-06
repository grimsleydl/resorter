options(width=350)
loaded <- suppressPackageStartupMessages(library(tidyverse, quietly = TRUE, logical.return = TRUE))
loaded <- suppressPackageStartupMessages(library(feather, quietly = TRUE, logical.return = TRUE))
loaded <- suppressPackageStartupMessages(library(arrow, quietly = TRUE, logical.return = TRUE))
loaded <- suppressPackageStartupMessages(library(postlogic, quietly = TRUE, logical.return = TRUE))
loaded <- suppressPackageStartupMessages(library(jsonlite, quietly = TRUE, logical.return = TRUE))
loaded <- suppressPackageStartupMessages(library(httr, quietly = TRUE, logical.return = TRUE))
loaded <- suppressPackageStartupMessages(library(jqr, quietly = TRUE, logical.return = TRUE))
loaded <- suppressPackageStartupMessages(library(dplyr, quietly = TRUE, logical.return = TRUE))
loaded <- suppressPackageStartupMessages(library(purrr, quietly = TRUE, logical.return = TRUE))
loaded <- suppressPackageStartupMessages(library(crayon, quietly = TRUE, logical.return = TRUE))
## attempt to load a library implementing the Bradley-Terry model for inferring rankings based on
## comparisons; if it doesn't load, try to install it through R's in-language package management;
## otherwise, abort and warn the user
## http://www.jstatsoft.org/v48/i09/paper
loaded <- library(BradleyTerry2, quietly = TRUE, logical.return = TRUE)
if (!loaded) {
  write("warning: R library 'BradleyTerry2' unavailable; attempting to install locally...", stderr())
  install.packages("BradleyTerry2")
  loadedAfterInstall <- library(BradleyTerry2, quietly = TRUE, logical.return = TRUE)
  if (!loadedAfterInstall) {
    write("error: 'BradleyTerry2' unavailable and cannot be installed. Aborting.", stderr())
    quit()
  }
}
## similarly, but for the library to parse command line arguments:
loaded <- library(argparser, quietly = TRUE, logical.return = TRUE)
if (!loaded) {
  write("warning: R library 'argparser' unavailable; attempting to install locally...", stderr())
  install.packages("argparser")
  loadedAfterInstall <- library(argparser, quietly = TRUE, logical.return = TRUE)
  if (!loadedAfterInstall) {
    write("error: 'argparser' unavailable and cannot be installed. Aborting.", stderr())
    quit()
  }
}
p <- arg_parser("sort a list using comparative rankings under the Bradley-Terry statistical model; see https://www.gwern.net/Resorter", name = "resorter")
p <- add_argument(p, "--input",
  short = "-i",
  "input file: a CSV file of items to sort: one per line, with up to two columns. (eg both 'Akira\\n' and 'Akira, 10\\n' are valid).", type = "character"
)
p <- add_argument(p, "--output", "output file: a file to write the final results to. Default: printing to stdout.")
p <- add_argument(p, "--working-directory", "set working directory; path to models and output")
p <- add_argument(p, "--verbose", "whether to print out intermediate statistics", flag = TRUE)
p <- add_argument(p, "--queries",
  short = "-n", default = NA,
  "Maximum number of questions to ask the user; defaults to N*log(N) comparisons. If already rated, 𝒪(n) is a good max, but the more items and more levels in the scale and more accuracy desired, the more comparisons are needed."
)
p <- add_argument(p, "--levels", short = "-l", default = 5, "The highest level; rated items will be discretized into 1-l levels, so l=5 means items are bucketed into 5 levels: [1,2,3,4,5], etc")
p <- add_argument(p, "--quantiles", short = "-q", "What fraction to allocate to each level; space-separated; overrides `--levels`. This allows making one level of ratings narrower (and more precise) than the others, at their expense; for example, one could make 3-star ratings rarer with quantiles like `--quantiles '0 0.25 0.8 1'`. Default: uniform distribution (1--5 → '0.0 0.2 0.4 0.6 0.8 1.0').")
p <- add_argument(p, "--no-scale", flag = TRUE, "Do not discretize/bucket the final estimated latent ratings into 1-l levels/ratings; print out inferred latent scores.")
p <- add_argument(p, "--progress", flag = TRUE, "Print out mean standard error of items")
p <- add_argument(p, "--header", flag = TRUE, "Input has a header; skip first line before looking for ratings")
p <- add_argument(p, "--colorize", flag = TRUE, "colorize output")
p <- add_argument(p, "--comparisons", "comparisons import")
p <- add_argument(p, "--quant-only", flag = TRUE, "only quantize based on provided comparisons")

argv <- parse_args(p)

if(!dir.exists(paste(argv$working_directory))) dir.create(paste(argv$working_directory))
if(!dir.exists(paste(argv$working_directory, "models", sep="/"))) dir.create(paste(argv$working_directory, "models", sep="/"))


out_path <- paste(argv$working_directory)
models_path <- paste(out_path, "models", sep="/")

## setwd(paste(argv$input, "models", sep="/"))
get_cli_response <- function(n=1) {
  keywords <- scan("stdin", what=character(), nlines=n, quiet=TRUE)
  if (nchar(keywords) != 1 || length(keywords) != 1) {
    cat(red(paste("invalid input. try again\n")))
    get_cli_response()
  } else paste(keywords, collapse=",")
}

error <- red $ underline
warn <- yellow $ underline
note <- cyan
tiesWarning <- warn("Warning: too many ties; precision reduced\n")

infile <- paste(argv$working_directory, argv$input, sep="/")
comparisons_import <- paste(argv$working_directory, argv$comparisons, sep="/")

## read in the data from either the specified file or stdin:
if (!is.na(argv$input)) {
  if (argv$header) {
    ranking <- read.csv(file = infile, stringsAsFactors = TRUE, header = TRUE)
  }
  else {
    ranking <- read.csv(file = infile, stringsAsFactors = TRUE, header = FALSE)
  }
} else {
  ranking <- read.csv(file = file("stdin"), stringsAsFactors = TRUE, header = FALSE)
}

ranking <- read.csv(file = infile, stringsAsFactors = TRUE, header = TRUE)

## turns out noisy sorting is fairly doable in 𝒪(n * log(n)), so do that plus 1 to round up:
if (is.na(argv$queries)) {
  n <- nrow(ranking)
  argv$queries <- round(n * log(n) + 1)
}

## if user did not specify a second column of initial ratings, then put in a default of '1':
if (ncol(ranking) == 1) {
  ranking$Rating <- 1
}

## ranking$Title_en <- 0
colnames(ranking) <- c("Media", "Rating", "ID", "State", "Title_en")

## A set of ratings like 'foo,1\nbar,2' is not comparisons, though. We *could* throw out everything except the 'Media' column
## but we would like to accelerate the interactive querying process by exploiting the valuable data the user has given us.
## So we 'seed' the comparison dataset based on input data: higher rating means +1, lower means −1, same rating == tie (0.5 to both)
if (!is.na(comparisons_import)) {
  comparisons <- read_feather(comparisons_import)
  print(comparisons)
  comparisons$Media.1 <- factor(comparisons$Media.1, levels=unique(c(comparisons$Media.1, comparisons$Media.1)))
  comparisons$Media.2 <- factor(comparisons$Media.2, levels=unique(c(comparisons$Media.1, comparisons$Media.1)))
} else { comparisons <- NULL
  for (i in 1:(nrow(ranking) - 1)) {
    rating1 <- ranking[i, ]$Rating
    media1 <- ranking[i, ]$Media
    id1 <- ranking[i, ]$ID
    rating2 <- ranking[i + 1, ]$Rating
    media2 <- ranking[i + 1, ]$Media
    id2 <- ranking[i + 1, ]$ID
    if (rating1 == rating2) {
      comparisons <- rbind(comparisons, data.frame("timestamp"=Sys.time(), "Media.1" = media1, "ID.1"=id1, "Media.2" = media2, "ID.2"=id2, "win1" = 0.5, "win2" = 0.5))
    } else {
      if (rating1 > rating2) {
        comparisons <- rbind(comparisons, data.frame("timestamp"=Sys.time(), "Media.1" = media1, "ID.1"=id1, "Media.2" = media2, "ID.2"=id2, "win1" = 1, "win2" = 0))
      } else {
        comparisons <- rbind(comparisons, data.frame("timestamp"=Sys.time(), "Media.1" = media1, "ID.1"=id1, "Media.2" = media2, "ID.2"=id2, "win1" = 0, "win2" = 1))
      }
    }
  }
}
## the use of '0.5' is recommended by the BT2 paper, despite causing quasi-spurious warnings:
## > In several of the data examples (e.g., `?CEMS`, `?springall`, `?sound.fields`), ties are handled by the crude but
## > simple device of adding half of a 'win' to the tally for each player involved; in each of the examples where this
## > has been done it is found that the result is similar, after a simple re-scaling, to the more sophisticated
## > analyses that have appeared in the literature. Note that this device when used with `BTm` typically gives rise to
## > warnings produced by the back-end glm function, about non-integer 'binomial' counts; such warnings are of no
## > consequence and can be safely ignored. It is likely that a future version of `BradleyTerry2` will have a more
## > general method for handling ties.
suppressWarnings(priorRankings <- BTm(cbind(win1, win2), Media.1, Media.2, data = comparisons))

if (argv$verbose) {
  print("higher=better:")
  print(summary(priorRankings))
  print(sort(BTabilities(priorRankings)[, 1]))
}
set.seed(2015 - 09 - 10)

if (is.na(argv$quant_only)) {
  cat("Comparison commands: 1=yes, 2=second is better, 3=tied, p=print estimates, s=skip, q=quit\n")
  for (i in 1:( argv$queries - nrow(comparisons) )) {
    cat(note(paste0("Query ", if (nrow(comparisons) > i) {nrow(comparisons)} else {i}, " ")))
    ## with the current data, calculate and extract the new estimates:
    suppressWarnings(updatedRankings <- BTm(cbind(win1, win2), Media.1, Media.2, br = TRUE, data = comparisons))
    coefficients <- BTabilities(updatedRankings)
    ## sort by latent variable 'ability':
    coefficients <- coefficients[order(coefficients[, 1]), ]

    if (argv$verbose) {
      print(i)
      print(coefficients)
    }
    ## select two media to compare: pick the media with the highest standard error and the media above or below it with the highest standard error:
    ## which is a heuristic for the most informative pairwise comparison. BT2 appears to get caught in some sort of a fixed point with greedy selection,
    ## so every few rounds pick a random starting point:
    media1N <- if (i %% 3 == 0) {
                 which.max(coefficients[, 2])
               } else {
                 sample.int(nrow(coefficients), 1)
               }
    media2N <- if (media1N == nrow(coefficients)) {
                 nrow(coefficients) - 1
               } else { # if at the top & 1st place, must compare to 2nd place
                 if (media1N == 1) {
                   2
                 } else { # if at the bottom/last place, must compare to 2nd-to-last
                   ## if neither at bottom nor top, then there are two choices, above & below, and we want the one with highest SE; if equal, arbitrarily choose the better:
                   if ((coefficients[, 2][media1N + 1]) > (coefficients[, 2][media1N - 1])) {
                     media1N + 1
                   } else {
                     media1N - 1
                   }
                 }
               }

    targets <- row.names(coefficients)
    media1 <- targets[media1N]
    media2 <- targets[media2N]
    media1_en <- trimws(ranking$Title_en[match(media1, ranking$Media)])
    media2_en <- trimws(ranking$Title_en[match(media2, ranking$Media)])
    id1 <- ranking$ID[match(media1, ranking$Media)]
    id2 <- ranking$ID[match(media2, ranking$Media)]

    no_en <- function(title, title_en) {
      return(tolower(noquote(as.character(title))) == tolower(title_en))
    }
    titles_no_en <- list(
      title1=no_en(media1, media1_en),
      title2=no_en(media2, media2_en)
    )

    is_repeat <- nrow(comparisons %>% filter({ Media.1 == media1 | Media.1 == media2 } & { Media.2 == media1 | Media.2 == media2 }))
    if (!is_repeat) {
      if (argv$colorize) {
        printMedia1 <- if (titles_no_en[["title1"]]) red(as.character(media1)) else yellow(as.character(media1))
        printMedia2 <- if (titles_no_en[["title2"]]) red(as.character(media2)) else yellow(as.character(media2))
        printMedia1_en <- red(as.character(media1_en))
        printMedia2_en <- red(as.character(media2_en))
      }
      else {
        printMedia1 <- as.character(media1)
        printMedia2 <- as.character(media2)
      }

      if (argv$`progress`) {
        cat(paste0("Mean stderr: ", round(mean(coefficients[, 2]))), " | ")
      }
      if (titles_no_en[["title1"]] && titles_no_en[["title2"]]) {
        cat(paste0(printMedia1, " vs ", printMedia2, ": "))
      }
      if (titles_no_en[["title1"]] && (! titles_no_en[["title2"]])) {
        cat(paste0(printMedia1, " vs ", printMedia2, " (", printMedia2_en, ")", ": "))
      }
      if ((! titles_no_en[["title1"]]) && titles_no_en[["title2"]]) {
        cat(paste0(printMedia1, " (", printMedia1_en, ")", " vs ", printMedia2, ": "))
      }
      if ((! titles_no_en[["title1"]]) && (! titles_no_en[["title2"]])) {
        cat(paste0(printMedia1, " (", printMedia1_en, ")", " vs ", printMedia2, " (", printMedia2_en, ")", ": "))
      }

      rating <- get_cli_response() # scan("stdin", character(), n = 1, quiet = TRUE)

      switch(rating,
             "1" = {
               comparisons <- rbind(comparisons, data.frame("timestamp"=Sys.time(), "Media.1" = media1, "ID.1"=id1, "Media.2" = media2, "ID.2"=id2, "win1" = 1, "win2" = 0))
             },
             "2" = {
               comparisons <- rbind(comparisons, data.frame("timestamp"=Sys.time(), "Media.1" = media1, "ID.1"=id1, "Media.2" = media2, "ID.2"=id2, "win1" = 0, "win2" = 1))
             },
             "3" = {
               comparisons <- rbind(comparisons, data.frame("timestamp"=Sys.time(), "Media.1" = media1, "ID.1"=id1, "Media.2" = media2, "ID.2"=id2, "win1" = 0.5, "win2" = 0.5))
             },
             "p" = {
               estimates <- data.frame(Media = row.names(coefficients), Estimate = coefficients[, 1], SE = coefficients[, 2])
               print(comparisons)
               print(warnings())
               print(summary(updatedRankings))
               print(estimates[order(estimates$Estimate), ], row.names = FALSE)
             },
             "s" = {},
             "q" = {
               break
             }
             )
    }
    else {
      estimates <- data.frame(Media = row.names(coefficients), Estimate = coefficients[, 1], SE = coefficients[, 2])
      ## print(comparisons)
      ## print(warnings())
      cat(paste0("repeated ", printMedia1, " vs ", printMedia2, "\n"))}
    if (!is.na(argv$output)) {
      write_feather(comparisons, paste(models_path, "comparisons.feather", sep="/"))
    }
  }
}
## results of all the questioning:
if (argv$verbose) {
  print("Verbose summary:")
  print(comparisons)
  print(warnings())
  print(summary(updatedRankings))
  print(estimates[order(estimates$Estimate), ], row.names = FALSE)
}

suppressWarnings(updatedRankings <- BTm(cbind(win1, win2), Media.1, Media.2, ~Media, id = "Media", data = comparisons))
coefficients <- BTabilities(updatedRankings)
if (argv$verbose) {
  print(rownames(coefficients)[which.max(coefficients[2, ])])
  print(summary(updatedRankings))
  print(sort(coefficients[, 1]))
}
ranking2 <- as.data.frame(BTabilities(updatedRankings))
ranking2$Media <- rownames(ranking2)
ranking2$ID <- rownames(ranking2)
ranking2$State <- rownames(ranking2)
ranking2$Title_en <- rownames(ranking2)
## ranking2$ID <- with(ranking, ID[match(ranking2$Media, "Media")])
ranking2$ID <- with(ranking, ID[match(ranking2$Media, Media)])
ranking2$State <- with(ranking, State[match(ranking2$State, Media)])
ranking2$Title_en <- with(ranking, Title_en[match(ranking2$Title_en, Media)])
## ranking$ID[match(media1, ranking[ranking$Media, "Media"])],
rownames(ranking2) <- NULL
if (!(argv$`no_scale`)) {

  ## if the user specified a bunch of buckets using `--quantiles`, parse it and use it,
  ## otherwise, take `--levels` and make a uniform distribution
  quantiles <- if (!is.na(argv$quantiles)) {
    (sapply(strsplit(argv$quantiles, " "), as.numeric))[, 1]
  } else {
    seq(0, 1, length.out = (argv$levels + 1))
  }
  ranking2$Quantile <- with(ranking2, {
    brk <- quantile(ability, probs = quantiles, type=8)
    ## clean them up so there are no "NA" values--simply expand the ends to just outside the score range
    brk <- append(brk[brk < max(brk)], max(ability) + .Machine$double.eps)
    brk <- append(brk[brk > min(brk)], min(ability) - .Machine$double.eps)
    if (length(unique(brk)) < length(brk)) {cat(paste0(tiesWarning)); as.integer(length(unique(brk)) - 1) }
    ## print("bins")
    ## print(length(lbl))
    ## print(sort(brk))
    ## print("unique bins")
    print(sort(unique(brk)))
    print(.bincode(ability, breaks=sort(brk), include.lowest=TRUE))
    .bincode(ability, breaks=sort(brk), include.lowest=TRUE)
    ## cut(ability
    ## , breaks = unique(brk)
    ## , labels = lbl
    ## , include.lowest = TRUE
    ## ,
    ## )
  })


print(ranking2)
  df <- subset(ranking2[order(ranking2$Quantile, decreasing = TRUE), ], select = c("Media", "Quantile", "ID", "State", "Title_en"))
  if (!is.na(argv$output)) {
    write.csv(df, file = paste(out_path, argv$output, sep="/"), row.names = FALSE)
    write_feather(df, paste(models_path, "df.feather", sep="/"))
    write_feather(ranking2, paste(models_path, "ranking2.feather", sep="/"))
    print(df)
  } else {
    print(df)
  }
} else { # return just the latent continuous scores:
  df <- data.frame(Media = rownames(coefficients), Estimate = coefficients[, 1])
  if (!is.na(argv$output)) {
    write.csv(df[order(df$Estimate, decreasing = TRUE), ], file = argv$output, row.names = FALSE)
  } else {
    print(finalReport)
  }
}

cat("\nResorting complete\n")
