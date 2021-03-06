#' @useDynLib bambu, .registration = TRUE
#' @importFrom Rcpp sourceCpp
NULL

#' @noRd
.onUnload <- function(libpath) {
    library.dynam.unload("bambu", libpath)
}


## Functions to set basic parameters and check inputs
#' setBiocParallelParameters
#' @noRd
setBiocParallelParameters <- function(reads, readClass.file, ncore, verbose){
    bpParameters <- BiocParallel::bpparam()
    #===# set parallel options: otherwise use parallel to distribute samples
    bpParameters$workers <- ifelse(max(length(reads),
            length(readClass.file)) == 1, 1, ncore)
    bpParameters$progressbar <- (!verbose)
    return(bpParameters)
}


#' setIsoreparameters
#' @noRd
setIsoreParameters <- function(isoreParameters){
    # ===# set default controlling parameters for isoform reconstruction  #===#
    isoreParameters.default <- list(
        remove.subsetTx = TRUE, min.readCount = 2,
        min.readFractionByGene = 0.05, min.sampleNumber = 1,
        min.exonDistance = 35, min.exonOverlap = 10, prefix = "") 
    isoreParameters <- 
        updateParameters(isoreParameters, isoreParameters.default)
    return(isoreParameters)
}


#' setEmParameters
#' @noRd
setEmParameters <- function(emParameters){
    emParameters.default <- list(bias = TRUE, maxiter = 10000, conv = 10^(-4))
    emParameters <- updateParameters(emParameters, emParameters.default)
    return(emParameters)
}

#' check parameters for isore and em
#' @param Parameters parameters inputted by user
#' @param Parameters.default default parameters
#' @noRd
updateParameters <- function(Parameters, Parameters.default) {
    if (!is.null(Parameters)) {
        for (i in names(Parameters)) {
            Parameters.default[[i]] <- Parameters[[i]]
        }
    }
    Parameters <- Parameters.default
    return(Parameters)
}

#' check valid inputs
#' @param annotations path to GTF file or TxDb object
#' @param reads path to BAM file(s)
#' @param readClass.file path to readClass file(s)
#' @param readClass.outputDir path to readClass output directory
#' @noRd
checkInputs <- function(annotations, reads, readClass.file,
    readClass.outputDir, genomeSequence){
    # ===# Check annotation inputs #===#
    if (!is.null(annotations)) {
        if (methods::is(annotations, "TxDb")) {
            annotations <- prepareAnnotations(annotations)
        } else if (methods::is(annotations, "CompressedGRangesList")) {
            ## check if annotations is as expected
            if (!all(c("TXNAME", "GENEID", "eqClass") %in% 
                colnames(mcols(annotations)))) 
                stop("The annotations is not properly prepared.\nPlease 
                prepareAnnnotations using prepareAnnotations function.")
        } else {
            stop("The annotations is not a GRangesList object.")
        }
    } else {
        stop("Annotations is missing.")
    }
    ## When SE object from bambu.quantISORE is provided ##
    if (!is.null(reads) & (!is.null(readClass.file))) stop("At least bam file or
        path to readClass file needs to be provided.")
    # ===# Check whether provided readClass.outputDir exists  #===#
    if (!is.null(readClass.outputDir)) {
        if (!dir.exists(readClass.outputDir)) 
            stop("output folder does not exist")
    }
    # ===# Check whether provided readclass files are all in rds format #===#
    if (!is.null(readClass.file)) {
        if (!all(grepl(".rds", readClass.file))) 
            stop("Read class files should be provided in rds format.")
    }
    ## check genomeSequence can't be FaFile in Windows as faFile will be dealt
    ## strangely in windows system
    if (.Platform$OS.type == "windows") {
        if (methods::is(genomeSequence, "FaFile")) 
        warning("Note that use of FaFile using Rsamtools in Windows is a bit 
        fuzzy, recommend to provide the path as a string variable to avoid
        use of Rsamtools for opening.")
    }
    return(annotations)
}

#' process reads
#' @param reads path to BAM file(s)
#' @param annotations path to GTF file or TxDb object
#' @param genomeSequence path to FA file or BSgenome object
#' @param readClass.outputDir path to readClass output directory
#' @param yieldSize yieldSize
#' @param bpParameters BioParallel parameter
#' @param stranded stranded
#' @param ncore ncore
#' @param verbose verbose
#' @noRd
processReads <- function(reads, readClass.file, annotations, genomeSequence,
    readClass.outputDir, yieldSize, bpParameters, stranded, ncore, verbose) {
        # ===# create BamFileList object from character #===#
        if (methods::is(reads, "BamFile")) {
            if (!is.null(yieldSize)) {
                Rsamtools::yieldSize(reads) <- yieldSize
            } else {
                yieldSize <- Rsamtools::yieldSize(reads)
            }
        reads <- Rsamtools::BamFileList(reads)
        names(reads) <- tools::file_path_sans_ext(BiocGenerics::basename(reads))
        } else if (methods::is(reads, "BamFileList")) {
            if (!is.null(yieldSize)) {
                Rsamtools::yieldSize(reads) <- yieldSize
            } else {
                yieldSize <- min(Rsamtools::yieldSize(reads))
            }
        } else if (any(!grepl("\\.bam$", reads))) {
            stop("Bam file is missing from arguments.")
        } else {
            if (is.null(yieldSize)) yieldSize <- NA
        reads <- Rsamtools::BamFileList(reads, yieldSize = yieldSize)
        names(reads) <- tools::file_path_sans_ext(BiocGenerics::basename(reads))
        }

        if (!verbose) message("Start generating read class files")
        readClassList <- BiocParallel::bplapply(names(reads),
            function(bamFileName) {
            bambu.constructReadClass(bam.file = reads[bamFileName],
                readClass.outputDir = readClass.outputDir,
                genomeSequence = genomeSequence,annotations = annotations,
                stranded = stranded,ncore = ncore,verbose = verbose)},
        BPPARAM = bpParameters)
        if (!verbose)
            message("Finished generating read classes from genomic alignments.")

    return(readClassList)
}

#' @noRd
helpFun <- function(chr, chrRanges, bamFile) {
    return(GenomicAlignments::grglist(GenomicAlignments::readGAlignments(
        file = bamFile,
        param = Rsamtools::ScanBamParam(
            flag = Rsamtools::scanBamFlag(isSecondaryAlignment = FALSE),
            which = chrRanges[chr]),
        use.names = FALSE)))
}


