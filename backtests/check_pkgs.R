pkgs <- c('quantmod','TTR','ggplot2','dplyr','scales','gridExtra','lubridate','tidyr','PerformanceAnalytics','patchwork')
missing <- pkgs[!pkgs %in% installed.packages()[,'Package']]
cat('Missing:', paste(missing, collapse=', '), '\n')
