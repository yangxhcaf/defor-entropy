library(ggplot2)
library(plm)
library(TTR)
library(mFilter)

prep.data <- function(out.name, force = FALSE) {
  ## Retrieve data from S3 and concatenate the results into a single
  ## text file, if separated into more than one part
  out.path <- paste("../../data/processed/", out.name, sep="")
  if (file.exists(out.path) == FALSE | force == TRUE) {
    cmd <- paste("s3cmd get s3://forma-analysis/entropy/long-form/*",
                 "../../data/raw/long-form/", "--force", sep = " ")
    system(cmd, wait = TRUE)
    cat.cmd <- paste("cat ../../data/raw/long-form/part* > ", out.path, sep="")
    system(cat.cmd, wait = TRUE)
  } else {
    print("File exists. Set `force = TRUE` to replace file.")
  }
}

entropy <- function(p.coll) {
  ## Return the entropy measure in bits of the probability collection
  ## in p.coll
  p.coll <- p.coll[p.coll > 0]
  bit.entropy <- -1 * sum(p.coll * log2(p.coll))
  return(bit.entropy)
}

shannon.entropy <- function(coll, probs = FALSE, normalize = TRUE) {
  ## A measure of dipsersion or entropy is an increasing function of
  ## the shannon entropy measure.
  if (probs == FALSE) {
    T <- sum(coll)
    coll <- coll / T
  }

  H <- entropy(coll)

  if (normalize == TRUE) {
    ## Normalize by dividing by the maximum amount of entropy, given
    ## the number of observations
    N <- length(coll)
    I <- entropy(rep(1/N, N))
    return(H/I)
  } else {
    return(H)
  }
}

graph.entropy <- function(df, graph.name, first.pd) {
  ## Create a data frame to graph
  ets <- aggregate(df$rate, by=list(df$date), FUN=shannon.entropy)
  names(ets) <- c("date", "entropy")
  g.data <- data.frame(date = as.Date(ets$date), entropy = ets$entropy)
  g.data <- g.data[g.data$date > as.Date(first.pd), ]
  
  ## Generate and save graph to images directory
  fname <- paste("../../write-up/images/", graph.name, sep="")
  g <- ggplot(g.data, aes(x = date, y = entropy)) + geom_line()
  g <- g + ylab("") + xlab("") 

  ggsave(filename = fname, plot = g, width=8, height=3, dpi=200)
}

## Grab data from S3 if not already downloaded
out.code <- prep.data("gadm-ts.txt", force = TRUE)

## Read in data, normalize total pixel hits
data <- read.table("../../data/processed/gadm-ts.txt")
names(data) <- c("iso", "gadm", "date", "forma.idx")
data$forma.idx <- data$forma.idx / 100

## Convert data frame to panel data frame, with GADM as the unit
## variable
data$date <- as.Date(data$date)
data <- pdata.frame(data, c("gadm", "date"))

## Generate a variable indicating the rate of pixel hits; remove
## observations for 2005-12-31, which has no observable rate (first
## period)
data$lag.total <- lag(data$forma.idx)
data$rate <- data$forma.idx - data$lag.total
gadm.data <- data <- na.omit(data)


## Aggregate the rate data by province level and data, sum over all
## GADM IDs within a given province
load("../../data/raw/gadm-map.Rdata")
merge.map <- gadm.map[ , c("prov", "gadm")]
data <- merge(merge.map, data, by=c("gadm"))

prov.data <- aggregate(data$rate, by=list(data$prov, data$date), FUN=sum)
names(prov.data) <- c("prov", "date", "rate")

## Aggregate the rate data by ISO3 code and date, effectively sum over
## all GADM IDs within an ISO code for each period
iso.data <- aggregate(data$rate, by=list(data$iso, data$date), FUN=sum)
names(iso.data) <- c("iso", "date", "rate")

## Graph the entropy at the GADM, sub-province level
graph.entropy(gadm.data, "gadm-entropy1.png", first.pd = "2008-01-01")

## Graph the entropy at the Province level
graph.entropy(prov.data, "prov-entropy1.png", first.pd = "2008-01-01")

## Graph the entropy at the ISO, country level
graph.entropy(iso.data, "iso-entropy1.png", first.pd = "2008-01-01")

## Graph the total, global rate of clearing activity
global.data <- aggregate(iso.data$rate, by=list(iso.data$date), FUN=sum)
g.data <- data.frame(date = as.Date(global.data$Group.1), rate = global.data$x)
g.data <- g.data[g.data$date > as.Date("2008-01-01"), ]
g.data$hp <- hpfilter(g.data$rate, freq = 100)$trend

(g <- ggplot(g.data, aes(x = date, y = rate)) + geom_line())
ggsave(filename = "../../write-up/images/total-rate.png", plot = g)

(g <- ggplot(g.data, aes(x = date, y = hp)) + geom_line())
ggsave(filename = fname <- "../../write-up/images/smoothed-rate.png", plot = g)

save(iso.data, file="../../data/processed/iso-data.Rdata")
