#!/usr/bin/env Rscript
#######################################################################
#######################################################################
## Created on Aug. 24, 2021 assign interacion type for the peaks
## Copyright (c) 2021 Jianhong Ou (jianhong.ou@gmail.com)
#######################################################################
#######################################################################
library(graph)
library(RBGL)
library(InteractionSet)
writeLines(as.character(packageVersion("graph")), "graph.version.txt")
writeLines(as.character(packageVersion("RBGL")), "RBGL.version.txt")
writeLines(as.character(packageVersion("InteractionSet")), "InteractionSet.version.txt")

OUTPUT = "peaks"
COUNT_CUTOFF = 12
RATIO_CUTOFF = 2.0
FDR = 2
if("optparse" %in% installed.packages()){
    library(optparse)
    option_list <- list(make_option(c("-c", "--count_cutoff"), type="integer", default=12, help="count cutoff, default 12", metavar="integer"),
                        make_option(c("-r", "--ratio_cutoff"), type="numeric", default=2.0, help="ratio cutoff, default 2.0", metavar="float"),
                        make_option(c("-f", "--fdr"), type="integer", default=2, help="-log10(fdr) cutoff, default 2", metavar="integer"),
                        make_option(c("-i", "--interactions"), type="character", default=NULL, help="interactions output by call hipeak", metavar="string"),
                        make_option(c("-o", "--output"), type="character", default="peaks", help="sample name of the output prefix", metavar="string"))
    opt_parser <- OptionParser(option_list=option_list)
    opt <- parse_args(opt_parser)
}else{
    args <- commandArgs(TRUE)
    parse_args <- function(options, args){
        out <- lapply(options, function(.ele){
            if(any(.ele[-3] %in% args)){
                if(.ele[3]=="logical"){
                    TRUE
                }else{
                    id <- which(args %in% .ele[-3])[1]
                    x <- args[id+1]
                    mode(x) <- .ele[3]
                    x
                }
            }
        })
    }
    option_list <- list("count_cutoff"=c("--count_cutoff", "-c", "integer"),
                        "ratio_cutoff"=c("--ratio_cutoff", "-r", "numeric"),
                        "fdr"=c("--fdr", "-f", "integer"),
                        "interactions"=c("--interactions", "-i", "character"),
                        "output"=c("--output", "-o", "character"))
    opt <- parse_args(option_list, args)
}

if(!is.null(opt$output)){
    OUTPUT <- opt$output
}
if(!is.null(opt$count_cutoff)){
    COUNT_CUTOFF <- opt$count_cutoff
}
if(!is.null(opt$ratio_cutoff)){
    RATIO_CUTOFF <- opt$ratio_cutoff
}
if(!is.null(opt$fdr)){
    FDR <- opt$fdr
}
if(!is.null(opt$output)){
    mm <- read.csv(opt$interactions)
}else{
    stop("count is required")
}
if(!all(c("chr1", "start1", "end1", "width1",
        "chr2", "start2", "end2", 'width2',
        "count", "logl", "logn", "loggc", "logm", "logdist", 'logShortCount',
        "ratio2", 'fdr') %in% colnames(mm))){
    stop("count table is not in correct format.")
}

classify_peaks <- function(final) {
    # group the interactions
    gi <- with(final, GInteractions(GRanges(chr1, IRanges(start1, end1)), GRanges(chr2, IRanges(start2, end2))))
    ol1 <- findOverlaps(first(gi), drop.self = TRUE, drop.redundant = TRUE)
    ol2 <- findOverlaps(second(gi), drop.self = TRUE, drop.redundant = TRUE)
    ol <- unique(c(queryHits(ol1), subjectHits(ol1), queryHits(ol2), subjectHits(ol2)))
    ol_ <- seq_along(gi)[-ol]

    group <- unique(rbind(as.data.frame(ol1), as.data.frame(ol2)))
    colnames(group) <- c("from", "to")
    group$weight <- 1
    group <- graphBAM(group)
    group <- connectedComp(ugraph(group))
    group <- lapply(group, as.numeric)
    group <- data.frame(id=unlist(group), g=rep(seq_along(group), lengths(group)))

    final$Cluster <- NA
    final$Cluster[group$id] <- group$g
    final$ClusterSize <- 0
    final$ClusterSize[group$id] <- table(group$g)[group$g]
    final$Cluster[is.na(final$Cluster)] <- seq(from=max(group$g)+1, to=max(group$g)+sum(is.na(final$Cluster)))
    final$NegLog10P <- -log10( final$p_val_reg2 )
    NegLog10P <- rowsum(final$NegLog10P, final$Cluster)
    final$NegLog10P <- NegLog10P[final$Cluster, 1]

    x <- unique( final[ final$ClusterSize != 0, c('chr1', 'Cluster', 'NegLog10P', 'ClusterSize')] )
    if(nrow(x)==0){
        final$ClusterType <- 'Singleton'
        return(final)
    }

    # sort rows by cumulative -log10 P-value
    x <- x[ order(x$NegLog10P) ,]
    y<-sort(x$NegLog10P)
    z<-cbind( seq(1,length(y),1), y )

    # keep a record of z before normalization
    z0 <- z

    z[,1]<-z[,1]/max(z[,1])
    z[,2]<-z[,2]/max(z[,2])

    u<-z
    u[,1] <-  1/sqrt(2)*z[,1] + 1/sqrt(2)*z[,2]
    u[,2] <- -1/sqrt(2)*z[,1] + 1/sqrt(2)*z[,2]

    v<-cbind(u, seq(1,nrow(u),1) )
    RefPoint <- v[ v[,2]==min(v[,2]) , 3]
    RefValue <- z0[RefPoint,2]

    # define peak cluster type
    final$ClusterType <- rep(NA, nrow(final))
    if(length(ol_)) final$ClusterType[ ol_ ] <- 'Singleton'
    if(length(ol)){
        final$ClusterType[ seq_along(gi) %in% ol & final$NegLog10P<RefValue  ] <-  'SharpPeak'
        final$ClusterType[ seq_along(gi) %in% ol & final$NegLog10P>=RefValue  ] <- 'BroadPeak'
    }
    return(final)
}

mm = classify_peaks(mm)

peaks <- if(nrow(mm)>0) subset(mm, count >= COUNT_CUTOFF & ratio2 >= RATIO_CUTOFF & -log10(fdr) > FDR) else data.frame()
if (dim(peaks)[1] == 0) {
    print(paste('ERROR caller_hipeak.r: 0 bin pairs with count >= ',COUNT_CUTOFF,' observed/expected ratio >= ',RATIO_CUTOFF,' and -log10(fdr) > ',fdr_cutoff,sep=''))
    quit()
}

outf_name = paste(OUTPUT, '.',FDR,'.peaks',sep='')
dir.create(OUTPUT, recursive=TRUE)
write.table(peaks, file.path(OUTPUT, outf_name),
            row.names = FALSE, col.names = TRUE, quote=FALSE)
peaks1 <- cbind(peaks[, c("chr1", "start1", "end1", "chr2", "start2", "end2")], "*", peaks[, "NegLog10P", drop=FALSE])
write.table(peaks1,
            file.path(OUTPUT, paste0(OUTPUT, '.', FDR, '.bedpe')),
            row.names = FALSE, col.names = FALSE, quote=FALSE, sep="\t")

summary_all_runs <- split(peaks, peaks$ClusterType)
summary_all_runs <- lapply(summary_all_runs, function(.ele){
    c(count = nrow(.ele),
    minWidth1 = min(.ele$width1),
    medianWidth1 = median(.ele$width1),
    maxWidth1 = max(.ele$width1),
    minWidth2 = min(.ele$width2),
    medianWidth2 = median(.ele$width2),
    maxWidth2 = max(.ele$width2),
    minFoldChange = min(.ele$ratio2),
    medianFoldChange = median(.ele$ratio2),
    maxFoldChange = max(.ele$ratio2))
})
summary_all_runs <- do.call(rbind, summary_all_runs)
summary_outf_name = paste('summary.',OUTPUT,'.txt',sep='')
write.table(summary_all_runs, file.path(OUTPUT, summary_outf_name), row.names = TRUE, col.names = TRUE, quote=FALSE)
