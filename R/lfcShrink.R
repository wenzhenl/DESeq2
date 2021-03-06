#' Shrink log2 fold changes
#'
#' Adds shrunken log2 fold changes (LFC) and SE to a
#' results table from \code{DESeq} run without LFC shrinkage.
#' Three shrinkage esimators for LFC are available via \code{type}.
#'
#' As of DESeq2 version 1.18, \code{type="apeglm"} and \code{type="ashr"}
#' are new features, and still under development.
#' Specifying \code{type="apeglm"} passes along DESeq2 MLE log2
#' fold changes and standard errors to the \code{apeglm} function
#' in the apeglm package, and re-estimates posterior LFCs for
#' the coefficient specified by \code{coef}.
#' Specifying \code{type="ashr"} passes along DESeq2 MLE log2
#' fold changes and standard errors to the \code{ash} function
#' in the ashr package, 
#' with arguments \code{mixcompdist="normal"} and \code{method="shrink"}
#' (\code{coef} and \code{contrast} ignored).
#' See vignette for a comparison of shrinkage estimators on an example dataset.
#' For all shrinkage methods, details on the prior is included in
#' \code{priorInfo(res)}, including the \code{fitted_g} mixture for ashr.
#' The integration of shrinkage methods from
#' external packages will likely evolve over time. We will likely incorporate an
#' \code{lfcThreshold} argument which can be passed to apeglm
#' to specify regions of the posterior at an arbitrary threshold.
#'
#' For \code{type="normal"}, and design as a formula, shrinkage cannot be applied
#' to coefficients in a model with interaction terms. For \code{type="normal"}
#' and user-supplied model matrices, shrinkage is only supported via \code{coef}.
#' 
#' @param dds a DESeqDataSet object, after running \code{\link{DESeq}}
#' @param coef the name or number of the coefficient (LFC) to shrink,
#' consult \code{resultsNames(dds)} after running \code{DESeq(dds)}.
#' note: only \code{coef} or \code{contrast} can be specified, not both.
#' \code{type="apeglm"} requires use of \code{coef}.
#' @param contrast see argument description in \code{\link{results}}.
#' only \code{coef} or \code{contrast} can be specified, not both.
#' @param res a DESeqResults object. Results table produced by the
#' default pipeline, i.e. \code{DESeq} followed by \code{results}.
#' If not provided, it will be generated internally using \code{coef} or \code{contrast}
#' @param type \code{"normal"} is the original DESeq2 shrinkage estimator;
#' \code{"apeglm"} is the adaptive t prior shrinkage estimator from the 'apeglm' package;
#' \code{"ashr"} is the adaptive shrinkage estimator from the 'ashr' package,
#' using a fitted mixture of normals prior
#' - see the Stephens (2016) reference below for citation
#' @param svalue logical, should p-values and adjusted p-values be replaced
#' with s-values when using \code{apeglm} or \code{ashr}.
#' See Stephens (2016) reference on s-values.
#' @param returnList logical, should \code{lfcShrink} return a list, where
#' the first element is the results table, and the second element is the
#' output of \code{apeglm} or \code{ashr}
#' @param apeAdapt logical, should \code{apeglm} use the MLE estimates of
#' LFC to adapt the prior, or use default or specified \code{prior.control}
#' @param apeMethod what \code{method} to run \code{apeglm}, which can
#' differ in terms of speed
#' @param parallel if FALSE, no parallelization. if TRUE, parallel
#' execution using \code{BiocParallel}, see same argument of \code{\link{DESeq}}
#' parallelization only used with \code{normal} or \code{apeglm}
#' @param BPPARAM see same argument of \code{\link{DESeq}}
#' @param bpx the number of dataset chunks to create for BiocParallel
#' will be \code{bpx} times the number of workers
#' @param ... arguments passed to \code{apeglm} and \code{ashr}
#'
#' @references
#'
#' \code{type="normal"}:
#'
#' Love, M.I., Huber, W., Anders, S. (2014) Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2. Genome Biology, 15:550. \url{https://doi.org/10.1186/s13059-014-0550-8}
#' 
#' \code{type="ashr"}:
#'
#' Stephens, M. (2016) False discovery rates: a new deal. Biostatistics, 18:2. \url{https://doi.org/10.1093/biostatistics/kxw041}
#' 
#' @return a DESeqResults object with the \code{log2FoldChange} and \code{lfcSE}
#' columns replaced with shrunken LFC and SE.
#' \code{priorInfo(res)} contains information about the shrinkage procedure,
#' relevant to the various methods specified by \code{type}.
#'
#' @export
#' 
#' @examples
#'
#'  set.seed(1)
#'  dds <- makeExampleDESeqDataSet(n=500,betaSD=1)
#'  dds <- DESeq(dds)
#'  res <- results(dds)
#' 
#'  res.shr <- lfcShrink(dds=dds, coef=2)
#'  res.shr <- lfcShrink(dds=dds, contrast=c("condition","B","A"))
#'  res.ape <- lfcShrink(dds=dds, coef=2, type="apeglm")
#'  res.ash <- lfcShrink(dds=dds, coef=2, type="ashr")
#' 
lfcShrink <- function(dds, coef, contrast, res,
                      type=c("normal","apeglm","ashr"),
                      svalue=FALSE, returnList=FALSE,
                      apeAdapt=TRUE, apeMethod="nbinomCR",
                      parallel=FALSE, BPPARAM=bpparam(), bpx=1,
                      ...) {  

  stopifnot(is(dds, "DESeqDataSet"))
  if (!missing(res)) stopifnot(is(res, "DESeqResults"))
  
  # TODO: lfcThreshold for types: normal and apeglm
  
  type <- match.arg(type, choices=c("normal","apeglm","ashr"))
  if (attr(dds,"betaPrior")) {
    stop("lfcShrink should be used downstream of DESeq() with betaPrior=FALSE (the default)")
  }
  if (!missing(coef)) {
    if (is.numeric(coef)) {
      stopifnot(coef <= length(resultsNames(dds)))
      coefAlpha <- resultsNames(dds)[coef]
      coefNum <- coef
    } else if (is.character(coef)) {
      stopifnot(coef %in% resultsNames(dds))
      coefNum <- which(resultsNames(dds) == coef)
      coefAlpha <- coef
    }
  }
  if (missing(res)) {
    if (!missing(coef)) {
      res <- results(dds, name=coefAlpha)
    } else if (!missing(contrast)) {
      res <- results(dds, contrast=contrast)
    } else {
      stop("one of coef or contrast required if 'res' is missing")
    }
  }
  if (type %in% c("normal","apeglm")) {
    if (is.null(dispersions(dds))) {
      stop("type='normal' and 'apeglm' require dispersion estimates, first call estimateDispersions()")
    }
    stopifnot(all(rownames(dds) == rownames(res)))
    if (parallel) {
      nworkers <- BPPARAM$workers
      parallelIdx <- factor(sort(rep(seq_len(bpx*nworkers),length=nrow(dds))))
    }
  }
  
  if (type == "normal") {

    ############
    ## normal ##
    ############

    if (is(design(dds), "formula")) {
      if (attr(dds, "modelMatrixType") == "user-supplied") {
        # if 'full' was used, the model matrix should be stored here
        # TODO... better one day to harmonize these two locations:
        # 1) provided by 'full' and stashed in attr(dds, "modelMatrix")
        # 2) design(dds)
        if (!missing(contrast)) {
          stop("user-supplied design matrix supports shrinkage only with 'coef'")
        }
        modelMatrix <- attr(dds, "modelMatrix")
      } else {
        termsOrder <- attr(terms.formula(design(dds)),"order")
        interactionPresent <- any(termsOrder > 1)
        if (interactionPresent) {
          stop("LFC shrinkage type='normal' not implemented for designs with interactions")
        }
        modelMatrix <- NULL
      }
    } else if (is(design(dds), "matrix")) {
      if (!missing(contrast)) {
        stop("user-supplied design matrix supports shrinkage only with 'coef'")
      }
      modelMatrix <- design(dds)
    }
    
    stopifnot(missing(coef) | missing(contrast))
    # find and rename the MLE columns for estimateBetaPriorVar
    betaCols <- grep("log2 fold change \\(MLE\\)", mcols(mcols(dds))$description)
    stopifnot(length(betaCols) > 0)
    if (!any(grepl("MLE_",names(mcols(dds))[betaCols]))) {
      names(mcols(dds))[betaCols] <- paste0("MLE_", names(mcols(dds))[betaCols])
    }
    if (missing(contrast)) {
      modelMatrixType <- "standard"
    } else {
      modelMatrixType <- "expanded"
    }
    attr(dds,"modelMatrixType") <- modelMatrixType
    betaPriorVar <- estimateBetaPriorVar(dds, modelMatrix=modelMatrix)
    stopifnot(length(betaPriorVar) > 0)
    # parallel fork
    if (!parallel) {
      dds.shr <- nbinomWaldTest(dds,
                                betaPrior=TRUE,
                                betaPriorVar=betaPriorVar,
                                modelMatrix=modelMatrix,
                                modelMatrixType=modelMatrixType,
                                quiet=TRUE)
    } else {
      dds.shr <- do.call(rbind, bplapply(levels(parallelIdx), function(l) {
        nbinomWaldTest(dds[parallelIdx == l,,drop=FALSE],
                       betaPrior=TRUE,
                       betaPriorVar=betaPriorVar,
                       modelMatrix=modelMatrix,
                       modelMatrixType=modelMatrixType,
                       quiet=TRUE)
      }, BPPARAM=BPPARAM))
    }
    if (missing(contrast)) {
      # parallel not necessary here
      res.shr <- results(dds.shr, name=coefAlpha)
    } else {
      res.shr <- results(dds.shr, contrast=contrast, parallel=parallel, BPPARAM=BPPARAM)
    }
    res$log2FoldChange <- res.shr$log2FoldChange
    res$lfcSE <- res.shr$lfcSE
    mcols(res)$description[2:3] <- mcols(res.shr)$description[2:3]
    deseq2.version <- packageVersion("DESeq2")
    priorInfo(res) <- list(type="normal",
                           package="DESeq2",
                           version=deseq2.version,
                           betaPriorVar=betaPriorVar)
    return(res)
    
  } else if (type == "apeglm") {

    ############
    ## apeglm ##
    ############
    
    if (!requireNamespace("apeglm", quietly=TRUE)) {
      stop("type='apeglm' requires installing the Bioconductor package 'apeglm'")
    }
    message("using 'apeglm' for LFC shrinkage")
    if (!missing(contrast)) {
      stop("type='apeglm' shrinkage only for use with 'coef'")
    }
    stopifnot(!missing(coef))
    incomingCoef <- gsub(" ","_",sub("log2 fold change \\(MLE\\): ","",mcols(res)[2,2]))
    if (coefAlpha != incomingCoef) {
      stop("'coef' should specify same coefficient as in results 'res'")
    }
    Y <- counts(dds)
    if (attr(dds, "modelMatrixType") == "user-supplied") {
      design <- attr(dds, "modelMatrix")
    } else {
      design <- model.matrix(design(dds), data=colData(dds))
    }
    disps <- dispersions(dds)
    if (is.null(normalizationFactors(dds))) {
      offset <- matrix(log(sizeFactors(dds)),
                       nrow=nrow(dds), ncol=ncol(dds), byrow=TRUE)
    } else {
      offset <- log(normalizationFactors(dds))
    }
    if ("weights" %in% assayNames(dds)) {
      weights <- assays(dds)[["weights"]]
    } else {
      weights <- matrix(1, nrow=nrow(dds), ncol=ncol(dds))
    }
    if (apeAdapt) {
      mle <- log(2) * cbind(res$log2FoldChange, res$lfcSE)
    } else {
      mle <- NULL
    }
    if (apeMethod == "general") {
      log.lik <- apeglm::logLikNB
    } else {
      log.lik <- NULL
    }
    if (!parallel) {
      fit <- apeglm::apeglm(Y=Y,
                            x=design,
                            log.lik=log.lik,
                            param=disps,
                            coef=coefNum,
                            mle=mle,
                            weights=weights,
                            offset=offset,
                            method=apeMethod, ...)
    } else {
      fitList <- bplapply(levels(parallelIdx), function(l) {
        idx <- parallelIdx == l
        apeglm::apeglm(Y=Y[idx,,drop=FALSE],
                       x=design,
                       log.lik=log.lik,
                       param=disps[idx],
                       coef=coefNum,
                       mle=mle,
                       weights=weights[idx,,drop=FALSE],
                       offset=offset[idx,,drop=FALSE],
                       method=apeMethod, ...)
      })
      fit <- list()
      for (param in c("map","sd","fsr","svalue","interval","diag")) {
        fit[[param]] <- do.call(rbind, lapply(fitList, `[[`, param))
      }
      fit$prior.control <- fitList[[1]]$prior.control
      fit$svalue <- apeglm::svalue(fit$fsr[,1])
    }
    stopifnot(nrow(fit$map) == nrow(dds))
    conv <- fit$diag[,"conv"]
    if (!all(conv[!is.na(conv)] == 0)) {
      message("Some rows did not converge in finding the MAP")
    }
    res$log2FoldChange <- log2(exp(1)) * fit$map[,coefNum]
    res$lfcSE <- log2(exp(1)) * fit$sd[,coefNum]
    mcols(res)$description[2] <- sub("MLE","MAP",mcols(res)$description[2])
    if (svalue) {
      coefAlphaSpaces <- gsub("_"," ",coefAlpha)
      res <- res[,1:3]
      res$svalue <- as.numeric(fit$svalue)
      mcols(res)[4,] <- DataFrame(type="results",
                                  description=paste("s-value:",coefAlphaSpaces))
    } else{
      res <- res[,c(1:3,5:6)]
    }
    priorInfo(res) <- list(type="apeglm",
                           package="apeglm",
                           version=packageVersion("apeglm"),
                           prior.control=fit$prior.control)
    if (returnList) {
      return(list(res=res, fit=fit))
    } else{
      return(res)
    }

  } else if (type == "ashr") {

    ##########
    ## ashr ##
    ##########
    
    if (!requireNamespace("ashr", quietly=TRUE)) {
      stop("type='ashr' requires installing the CRAN package 'ashr'")
    }
    message("using 'ashr' for LFC shrinkage. If used in published research, please cite:
    Stephens, M. (2016) False discovery rates: a new deal. Biostatistics, 18:2.
    https://doi.org/10.1093/biostatistics/kxw041")
    betahat <- res$log2FoldChange
    sebetahat <- res$lfcSE
    fit <- ashr::ash(betahat, sebetahat,
                     mixcompdist="normal", method="shrink", ...)
    res$log2FoldChange <- fit$result$PosteriorMean
    res$lfcSE <- fit$result$PosteriorSD
    mcols(res)$description[2] <- sub("MLE","PostMean",mcols(res)$description[2])
    if (svalue) {
      coefAlphaSpaces <- sub(".*p-value: ","",mcols(res)$description[5])
      res <- res[,1:3]
      res$svalue <- fit$result$svalue
      mcols(res)[4,] <- DataFrame(type="results",
                                  description=paste("s-value:",coefAlphaSpaces))
    } else {
      res <- res[,c(1:3,5:6)]
    }
    priorInfo(res) <- list(type="ashr",
                           package="ashr",
                           version=packageVersion("ashr"),
                           fitted_g=fit$fitted_g)
    if (returnList) {
      return(list(res=res, fit=fit))
    } else{
      return(res)
    }

  }
}
