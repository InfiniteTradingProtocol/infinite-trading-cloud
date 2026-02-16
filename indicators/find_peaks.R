###############################################
#### File: find_peaks.R                   #####
####                                      #####
#### Description                          #####
####                                      #####
#### It returns a list with all the peaks #####
#### of the x vector given a precision m  #####
#### We can obtain local max/min in ts    #####
###############################################

find_peaks <- function (x, m = 3){
  shape <- diff(sign(diff(x, na.pad = FALSE)))
  pks <- sapply(which(shape < 0), FUN = function(i){
    z <- i - m + 1
    z <- ifelse(z > 0, z, 1)
    w <- i + m + 1
    w <- ifelse(w < length(x), w, length(x))
    if(all(x[c(z : i, (i + 2) : w)] <= x[i + 1])) return(i + 1) else return(numeric(0))
  })
  pks <- unlist(pks)
  pks
}
find_bottoms <- function (x,m = 3) { return(find_peaks(-x,m)) }

return_peaks = function(x,m=3) { 
  adjustment = first_index(x)
  index = find_peaks(x[adjustment:length(x)],m=m) + adjustment - 1; new_series = c();
  for (i in 1:length(x)) {
    if (sum(as.numeric(index == i)) > 0) { new_series = c(new_series,x[i])}
    else { new_series = c(new_series,0) }
  }
  return(ts(new_series))
}

return_bottoms = function(x,m=3) { 
  index = find_bottoms(x,m=m); new_series = c();
  for (i in 1:length(x)) {
    if (sum(as.numeric(index == i)) > 0) { new_series = c(new_series,x[i])}
    else { new_series = c(new_series,0) }
  }
  return(ts(new_series))
}


