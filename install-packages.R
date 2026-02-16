#!/usr/bin/env Rscript

# Install TTR and quantmod if not available
packages = c('TTR', 'quantmod')
for (pkg in packages) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    cat(paste0('Installing ', pkg, '...\n'))
    install.packages(pkg, repos='http://cran.rstudio.com/', quiet=TRUE)
  } else {
    cat(paste0('✅ ', pkg, ' already installed\n'))
  }
}
cat('\n✅ All required packages available\n')
