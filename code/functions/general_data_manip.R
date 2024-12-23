################################################################################ 
# This file contains the functions necessary to do general data manipulation
# on the files necessary for performing type I error and power calculations for 
# several different rare variant association tests
################################################################################

#' make_geno
#' 
#' @description
#' function to convert the haplotypes into a genotype matrix
#' 
#' @param hap A matrix of 0s and 1s where the rows represent a variant and the columns 
#'            represent a single haplotype. Every 2 columns correspond to one individual
#' 
#' @return A genotype matrix where each row corresponds to an individual with 
#'         values being 0, 1, or 2 reference alleles

make_geno = function(hap) {
  
  # create an empty genotype matrix
  geno = matrix(0, nrow(hap), ncol(hap)/2)
  
  # sum up the number of alleles in adjacent haplotypes (2 haplotypes per person)
  for (j in 1:(ncol(hap)/2)) {
    geno[,j] = hap[,2*j] + hap[,2*j-1]
  }
  geno = as.data.frame(geno)
  
  return(geno)
}

#' make_long
#' 
#' @description
#' function to create a dataframe with a line for each variant instead of just 
#' counts (necessary for LogProx)
#' 
#' @param counts dataframe containing the ACs and AFs of a genotype file
#' @param leg the legend file
#' @param case a string indicating if the counts are "cases" or "controls"
#' @param group a string indicating if the counts are from an "int" (internal) 
#'              or "ext" (external) sample
#' 
#' @return a dataframe that repeats each variant mac times and retains the gene, 
#'         functional, case, and group status for each variant

make_long = function(counts, leg, case, group) {
  
  # add information to the counts
  temp = counts %>% mutate(id=leg$id, gene=leg$gene, fun=leg$fun, case=case, group=group)
  
  # remove the monomorphic variants 
  # temp2 = temp %>% filter(mac!=0)
  temp2 = temp %>% filter(ac!=0)
  
  # repeat each variant mac times
  # out = data.frame(lapply(temp2, rep, temp2$mac)) %>% select(-count, -mac, -maf)
  out = data.frame(lapply(temp2, rep, temp2$ac)) %>% select(-ac, -af)
  
  return(out)
}

#' merge_cases
#' 
#' @description
#' Function to merge the case datasets for power and t1e at the
#' genes associated with each calculation
#' 
#' @param cases_power case haplotype file used for power calculation
#' @param cases_t1e case haplotype file used for type I error calculation
#' @param leg legend file
#' @param genes_power a character vector of genes used to calculate power
#' 
#' @return the merged case haplotype file where the data pertaining to the power
#' genes are from the cases power df and the remaining data comes from the cases t1e df

merge_cases = function(cases_power, cases_t1e, leg, genes_power) {
  
  # Add row number and gene column to each hap
  hap_power = cases_power %>% mutate(row = leg$row, gene = leg$gene)
  hap_t1e = cases_t1e %>% mutate(row = leg$row, gene = leg$gene)
  
  # Subset haps to the necessary genes
  power_gene = subset(hap_power, gene %in% genes_power) 
  t1e_gene = subset(hap_t1e, !(gene %in% genes_power))
  
  # Merge the two case haps
  hap_merge = rbind(power_gene, t1e_gene)
  
  # Order the merged hap file by row number
  hap_ord = hap_merge[order(hap_merge$row),]
  
  # Remove the row number and gene columns
  hap_out = subset(hap_ord, select = -c(row, gene))
  
  return(hap_out)
}

#' calc_allele_freqs
#' 
#' @description
#' Function to calculate the ACs/AFs and MACs/MAFs for a given dataset
#' 
#' @param geno a genotype or haplotype matrix denoting the number of reference 
#'             alleles observed at each individual/haplotype for all variants in the region
#' @param n the number of individuals in geno
#' @param Pop a three letter string denoting the population of geno if applicable (mainly used for reference data)
#' 
#' @return a dataframe denoting the ac, af, mac, and maf for each variant in the region

calc_allele_freqs = function(geno, n, Pop=NULL) {
  
  # counts = data.frame(count = rowSums(geno)) %>%
  #   mutate(mac = ifelse(count>n, 2*n-count, count)) %>%
  #   mutate(maf = mac/(2*n))
  
  # Adelle's way
  counts = data.frame(ac = rowSums(geno)) %>%
    mutate(af = ac/(2*n))
  
  if(!is.null(Pop)) {
    Pop <- tolower(Pop)
    colnames(counts) <- c(paste0("ac_", Pop), paste0("af_", Pop))
  }

  return(counts)
}

#' est_props
#' 
#' @description
#' Function to estimate the ancestry proportions of a sample using only the 
#' common variants
#' 
#' @param counts dataframe containing the ACs and AFs of a sample for each 
#'               variant in the region
#' @param Pops a charcter vector of the continental populations that compose the 
#'             admixed population
#' @param maf a numeric value denoting the minor allele frequency threshold that 
#'            distinguishes rare variants from common variants
#' 
#' @return returns the proportion estimates outputted by Summix

est_props = function(counts, Pops, maf) {
  
  pops <- tolower(Pops)
  
  # Identify common variants for each population in pops
  pop_vars <- lapply(pops, function(pop) {counts[, paste0("af_", pop)] > maf & counts[, paste0("af_", pop)] < 1-maf})
  
  # Generate a single logical vector stating whether each variant is common in at least one of the ref pops 
  common_vars <- Reduce(`|`, pop_vars)
  
  # Find the common variant that are common in either the observed or the ref data
  common <- (counts$af > maf & counts$af < 1-maf) | common_vars
  
  # Subset counts dataframe to only common variants
  common_df <- counts[which(common),]
  
  # Calculate proportion estimates using Summix
  prop_est <- summix(data = common_df,
                     reference=c(sapply(pops, function(pop) paste0("af_", pop))),
                     observed="af", 
                     goodness.of.fit = TRUE, 
                     override_removeSmallRef = TRUE) #show estimates for anc w/ <1% AFs
  
  return(prop_est)
}

#' calc_adjusted_AF
#' 
#' @description
#' Function that uses Summix to update the AFs and ACs of a dataset 
#' (primarily the common controls)
#' 
#' @param counts dataframe containing the ACs and AFs for the data to be adjusted 
#'               as well as the reference data for all continental populations
#' @param Pops a character vector denoting the continental ancestries that 
#'             compose the admixed population 
#'             (Note: order of Pops must match order of Nref)
#' @param case_est the proportion estimates from Summix for the cases
#' @param control_est the proportion estimates from Summix for the controls
#' @param Nref a vector of the number of individuals in each reference population 
#'             (order of reference populations must match throughout adjAF function)
#' @param Ncc the number of individuals in the (common) controls
#' @param Neff a boolean value, if True the effective sample size is used to 
#'             calculate the adjusted ACs instead of Ncc, default value is False
#' 
#' @return a dataframe with the adjusted ACs and AFs for the controls as well as 
#'         the row number in case summix removed any variants in the adjustment

calc_adjusted_AF = function(counts, Pops, case_est, control_est, Nref, Ncc, Neff=FALSE) {
  
  pops <- tolower(Pops)
  
  # Add row index column to counts in case summix removes variants during adjustment 
  counts$row <- 1:nrow(counts)
  
  # Calculate adjusted AFs using Summix
  adj_AF <- adjAF(data = counts,
                  reference = c(sapply(pops, function(pop) paste0("af_", pop))),
                  observed = "af",
                  pi.target = unlist(lapply(paste0("af_", pops), function(col) case_est[, col])), 
                  pi.observed = unlist(lapply(paste0("af_", pops), function(col) control_est[, col])),
                  adj_method = "average",
                  N_reference = Nref,
                  N_observed = Ncc,
                  filter = TRUE) 
    
  # Create dataframe to store adjusted ACs and AFs
  counts_adj = data.frame(matrix(0, nrow = nrow(counts), ncol = 2))
  colnames(counts_adj) <- c("ac", "af")
  
  # If variants were removed during adjustment, this will add the adj AFs at the variants that weren't removed, leaving the rest as 0
  # If no variants were removed during adjustment, this will still work
  counts_adj[adj_AF$adjusted.AF$row, "af"] = adj_AF$adjusted.AF$adjustedAF
  
  # Calculate the adjusted ACs based on the adjusted AFs
  if (Neff) {
    
    # Use effective sample size
    counts_adj$ac <- round(counts_adj$af*(2*adj_AF$effective.sample.size))
    return(list(counts_adj, adj_AF$effective.sample.size))
    
  } else {
    
    # Use number of common controls
    counts_adj$ac <- round(counts_adj$af*(2*Ncc))
    return(counts_adj)
  }

}


#' flip_file
#' 
#' @description
#' Function the flip values for a specified file at variants with an AF >= 1-maf. 
#' Used in flip_data function
#' 
#' @param file_to_flip the file to be updated
#' @param flip the row indices corresponding to the variants that need to be flipped
#' @param file_type string specifying what file is to be flipped 
#'                  Options: "leg", "geno", and "count" 
#'                  Note count is really referring to the adjusted common controls
#' @param N number of individuals, only needed if flipping counts data, default value is NULL
#' 
#' @return the specified file with the relevant values flipped at the variants in flip

flip_file = function(file_to_flip, flip, file_type, N=NULL) {
  
  # Make copy of original file
  file2 = file_to_flip
  
  if (file_type == "leg") {

    # Flip ref allele in file2 with alt allele in file
    file2[flip, "a0"] <- file_to_flip[flip, "a1"]
    
    # Flip alt allele in leg2 with ref allele in leg
    file2[flip, "a1"] <- file_to_flip[flip, "a0"]
    
    return(file2)
    
  } else if (file_type == "geno") {
    
    # Flip the alternate allele counts at the relevant variants
    file2[flip, ] <- 2-file_to_flip[flip, ]
    
    return(file2)
    
  } else if (file_type == "count") {
    
    # Flip the ACs at the variants that need to be flipped
    file2[flip, "ac"] <- (2*N)-file_to_flip[flip, "ac"]
    
    # Flip the AFs at the variants that need to be flipped
    file2[flip, "af"] <- 1-file_to_flip[flip, "af"]
    
    return(file2)
    
  } else {
    stop("ERROR: 'file_type' must be a string of either 'leg', 'geno', or 'count'")
  }
  
}

#' flip_data
#' 
#' @description
#' Function to flip the relevant datasets at variants where AF >= 1-maf for each possible scenario
#' 
#' @param leg legend file
#' @param flip the rows of the legend file specifying which variants need to be flipped
#' @param geno.case genotype matrix for the cases
#' @param count.case the dataframe of ACs and AFs for the cases
#' @param Ncase number of individuals in the cases
#' @param cntrl string specifying the type(s) of controls used, 
#'              Options: int, ext, all
#' @param geno.ic genotype matric for the internal controls, default value is NULL
#' @param count.ic the dataframe of ACs and AFs for the internal controls, default value is NULL
#' @param Nic number of individuals in the internal controls, default value is NULL
#' @param geno.cc genotype matric for the common controls, default value is NULL
#' @param count.cc the dataframe of ACs and AFs for the common controls, default value is NULL
#' @param count.cc.adj adjusted AC and AF dataframe for the common controls, default value is NULL
#' @param Ncc number of individuals in the common controls, default value is NULL
#' @param adj boolean value specifying if the common controls used are adjusted or unadjusted, default value is false
#' 
#' @return a list of all files that could be flipped, returns the unaltered files if no variants needed to be flipped

flip_data = function(leg, flip, geno.case, count.case, Ncase, cntrl, geno.ic=NULL, count.ic=NULL, Nic=NULL, geno.cc=NULL, count.cc=NULL, count.cc.adj=NULL, Ncc=NULL, adj=FALSE) {
  
  if (length(flip) != 0) {
    
    # Create new leg file
    leg2 = flip_file(leg, flip, file_type="leg", N=NULL)
    
    # Create new case data files
    geno.case2 = flip_file(geno.case, flip, file_type="geno", N=NULL)
    count.case2 = flip_file(count.case, flip, file_type="count", N=Ncase)
    
    if (cntrl == "int") {
      
      # Update geno files
      geno.ic2 = flip_file(geno.ic, flip, file_type="geno", N=NULL)
      
      # Recalculate ac/af 
      count.ic2 = flip_file(count.ic, flip, file_type="count", N=Nic)
      
      # Return all changed files, note some may be NULL
      return(list(leg2, geno.case2, geno.ic2, geno.cc2=NULL, count.case2, count.ic2, count.cc2=NULL, count.cc.adj2=NULL))
      
    } else if (cntrl == "ext" & !adj) {

      # Update geno files
      geno.cc2 = flip_file(geno.cc, flip, file_type="geno", N=NULL)
      
      # Recalculate ac/af 
      count.cc2 = flip_file(count.cc, flip, file_type="count", N=Ncc)
      
      # Return all changed files, note some may be NULL
      return(list(leg2, geno.case2, geno.ic2=NULL, geno.cc2, count.case2, count.ic2=NULL, count.cc2, count.cc.adj2=NULL))
      
    } else if (cntrl == "ext" & adj) {
      
      # Recalculate ac/af 
      count.cc.adj2 = flip_file(count.cc.adj, flip, file_type="count", N=Ncc)
      
      # Return all changed files, note some may be NULL
      return(list(leg2, geno.case2, geno.ic2=NULL, geno.cc2=NULL, count.case2, count.ic2=NULL, count.cc2=NULL, count.cc.adj2))
      
    } else if (cntrl == "all" & !adj) {
      
      # Update geno files
      geno.ic2 = flip_file(geno.ic, flip, file_type="geno", N=NULL)
      geno.cc2 = flip_file(geno.cc, flip, file_type="geno", N=NULL)
      
      # Recalculate ac/af 
      count.ic2 = flip_file(count.ic, flip, file_type="count", N=Nic)
      count.cc2 = flip_file(count.cc, flip, file_type="count", N=Ncc)
      
      # Return all changed files, note some may be NULL
      return(list(leg2, geno.case2, geno.ic2, geno.cc2, count.case2, count.ic2, count.cc2, count.cc.adj2=NULL))
      
    } else if (cntrl == "all" & adj) {

      # Update geno files
      geno.ic2 = flip_file(geno.ic, flip, file_type="geno", N=NULL)
      
      # Recalculate ac/af 
      count.ic2 = flip_file(count.ic, flip, file_type="count", N=Nic)
      count.cc.adj2 = flip_file(count.cc.adj, flip, file_type="count", N=Ncc)
      
      # Return all changed files, note some may be NULL
      return(list(leg2, geno.case2, geno.ic2, geno.cc2=NULL, count.case2, count.ic2, count.cc2=NULL, count.cc.adj2))
      
    }
    
  } else {
    
    # Return all unchanged datasets, note some may be NULL
    return(list(leg, geno.case, geno.ic, geno.cc, count.case, count.ic, count.cc, count.cc.adj))
  }
  
}

# version that doesn't deselect count since the adjusted count files don't have that col
# make_long_adj = function(counts, leg, case, group) {
#   
#   # add information to the counts
#   temp = counts %>% mutate(id=leg$id, gene=leg$gene, fun=leg$fun, case=case, group=group)
#   
#   # remove the monomorphic variants 
#   temp2 = temp %>% filter(mac!=0)
#   
#   # repeat each variant mac times
#   out = data.frame(lapply(temp2, rep, temp2$mac)) %>% select(-mac, -maf)
#   
#   return(out)
# }

### Determine the number of rare fun and syn minor alleles in a dataset FROM THE COUNTS DF
# rare_counts = function(counts, leg.fun, leg.syn, maf){
#   
#   fun.counts = counts[leg.fun$row, ]
#   rare.fun = which(fun.counts$maf <= maf)
#   out.fun = sum(fun.counts[rare.fun, ]$mac)
#   
#   syn.counts = counts[leg.syn$row, ]
#   rare.syn = which(syn.counts$maf <= maf)
#   out.syn = sum(syn.counts[rare.syn, ]$mac)
#   
#   out = c(out.fun, out.syn)
#   
#   return(out)
# }

# Function to calculate allele counts/freqs for all datasets
# calc_allele_freqs_all = function(counts_cases, counts_int, counts_cc, Ncase, Nint, Ncc) {
#   
#   # counts_all = data.frame(count = counts_cases$count + counts_int$count + counts_cc$count) %>% 
#   #   mutate(mac = ifelse(count > (Ncase+Nint+Ncc), 2*(Ncase+Nint+Ncc)-count, count)) %>%
#   #   mutate(maf = mac/(2*(Ncase+Nint+Ncc)))
#   
#   # Adelle's way
#   counts_all = data.frame(ac = counts_cases$ac + counts_int$ac + counts_cc$ac) %>% 
#     mutate(af = ac/(2*(Ncase+Nint+Ncc)))
#   
#   return(counts_all)
# }

# Function to calculate allele counts/freqs for reference datasets
# calc_allele_freqs_ref = function(Pop, hap_ref, Nref) {
#   
#   # counts_ref = data.frame(count = rowSums(hap_ref)) %>%
#   #   mutate(mac = ifelse(count > Nref, 2*Nref-count, count)) %>%
#   #   mutate(maf = mac/(2*Nref))
#   # 
#   # Pop <- tolower(Pop)
#   # colnames(counts_ref) <- c(paste0("count_", Pop), paste0("mac_", Pop), paste0("maf_", Pop))
#   
#   # Adelle's way
#   counts_ref = data.frame(ac = rowSums(hap_ref)) %>%
#     mutate(af = ac/(2*Nref))
# 
#   Pop <- tolower(Pop)
#   colnames(counts_ref) <- c(paste0("ac_", Pop), paste0("af_", Pop))
#   
#   return(counts_ref)
# }

# Function to calculate adjusted MACs and MAFs
# calc_adj_allele_freqs = function(counts, Ncc) {
#   
#   counts = counts %>% mutate(adj_mac2 = ifelse(adj_mac>Ncc, 2*Ncc-adj_mac, adj_mac)) %>%
#     mutate(adj_maf2 = ifelse(adj_maf>0.5, 1-adj_maf, adj_maf))
#   
#   return(counts)
# }

