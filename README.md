# DESeq2
This is code review for DESeq2 for my personal understanding


# DESeq2 organization of R files

* core ........... most of the statistical code (example call below)
* fitNbinomGLMs .. three functions for fitting NB GLMs
* methods ........ the S4 methods (estimateSizeFactors, etc.)
* AllClasses ..... class definitions and object constructors
* AllGenerics .... the generics defined in DESeq2
* results ........ results() function and helpers
* plots .......... all plotting functions
* lfcShrink ...... log2 fold change shrinkage
* helper ......... unmix, collapseReplicates, fpkm, fpm, DESeqParallel
* expanded ....... helpers for dealing with expanded model matrices
* wrappers ....... the R wrappers for the C++ functions (mine)
* RcppExports .... the R wrappers for the C++ functions (auto)

* rlogTransformation ... rlog
* varianceStabilizingTransformation ... VST

* general outline of the internal function calls.
* note: not all of these functions are exported.

* DESeq
  *|- estimateSizeFactors
  *|- estimateSizeFactorsForMatrix
    *|- estimateDispersions
*    |- estimatedispersionsgeneest
*       |- fitnbinomglms
*          |- fitbeta (c++)
*       |- fitdisp (c++)
*    |- estimatedispersionsfit
*    |- estimatedispersionsmap
*       |- estimatedispersionpriorvar
*       |- fitdisp (c++)
* |- nbinomwaldtest
*    |- fitglmswithprior
*       |- fitnbinomglms
*          |- fitbeta (c++)
*       |- estimatebetapriorvar
*       |- fitnbinomglms
*          |- fitBeta (C++)
