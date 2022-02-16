loaded <- suppressPackageStartupMessages(library(crayon, quietly = TRUE, logical.return = TRUE))
cat(black(paste0("color test\n")))
cat(red(paste0("color test\n")))
cat(green(paste0("color test\n")))
cat(yellow(paste0("color test\n")))
cat(blue(paste0("color test\n")))
cat(magenta(paste0("color test\n")))
cat(cyan(paste0("color test\n")))
cat(white(paste0("color test\n")))
cat(cat(silver(paste0("color test\n"))))





cat(bgBlack(paste0("color test \n")))
cat(bgRed(paste0("color test \n")))
cat(bgGreen(paste0("color test \n")))
cat(bgYellow(paste0("color test \n")))
cat(bgBlue(paste0("color test \n")))
cat(bgMagenta(paste0("color test \n")))
cat(bgCyan(paste0("color test \n")))
cat(bgWhite(black(paste0("color test \n"))))
