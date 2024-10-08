############################################################################## 
# This file contains the functions necessary for pruning the haplotype files
# as well as determining the rare alleles in a dataset
# Variable legend:
# legend: the legend file
# bins: the MAC bin estimates    
# remove: the variants to be removed in the pruning step
# haplotype/hap: the haplotype file
# nsim: the number of individuals being simulated in the haplotype file
# legend_fun_idx: row indices of functional variants of the haplotype file
# maf: the minor allele frequency
# leg_pcase: legend file for haplotype of 1st RAREsim v2.1.1 pruning step
# leg_pconf: legend file for haplotype of 2nd RAREsim v2.1.1 pruning step
# hap_pconf: haplotype file of the second RAREsim v2.1.1 pruning step
##############################################################################


### function to determine which variants to prune
select_var = function(legend, bins){
  
  rem = c()
  for (k in 1:nrow(bins)){ # loop through the MAC bins
    
    # subset the variants within the MAC bin
    leg_k = legend %>% filter(MAC %in% c(bins$Lower[k]:bins$Upper[k]))
    
    if(nrow(leg_k)>0){
      
      # calculate the proportion of variants to keep
      prop = bins$Expected_var[k]/nrow(leg_k)
      leg_k$draw = runif(nrow(leg_k), 0, 1)
      
      # store the variants to change back to reference
      rem = rbind(rem, leg_k %>% filter(leg_k$draw>prop))
    }
  }
  return(rem)
}

### function to prune the selected variants
prune_var = function(remove, haplotype, nsim){
  
  # create rows of zeros (i.e. reference)
  add =  data.frame(matrix(0, nrow=nrow(remove), ncol=(2*nsim)))
  colnames(add) = colnames(haplotype)
  
  # add row numbers to the haplotypes
  add$row = remove$row
  haplotype$row = 1:nrow(haplotype)
  
  # remove the selected variants
  haplotype = haplotype[-c(remove$row),]
  
  # add rows of zeros to the original haplotypes
  hap_out = rbind(haplotype, add)
  
  # make sure the variants are in the correct order to match the legend file
  hap_out = hap_out[order(hap_out$row),]
  
  # remove the row numbers
  hap_out = hap_out[,-c(ncol(hap_out))]
  
  return(hap_out)
}

### function to add rows of zeros back into the pruned haplotype file in the correct 
# order. Haplotype pruned using RAREsim v2.1.1
# add_prune_var = function(leg_pcase, leg_pconf, hap_pconf, nsim){
#   
#   # Add row number to pconf legend file based on variant id in pcase legend file
#   pconf_rows = subset(leg_pcase, id %in% leg_pconf$id)
#   leg_pconf$row = pconf_rows$row
#   
#   # Subset rows that were pruned from pcase legend file
#   pruned_rows = subset(leg_pcase, !(id %in% leg_pconf$id))
#   
#   # create rows of zeros to add back in to hap.pconf
#   add =  data.frame(matrix(0, nrow=nrow(pruned_rows), ncol=(2*nsim)))
#   colnames(add) = colnames(hap_pconf)
#   
#   # add row numbers to the haplotypes
#   add$row = pruned_rows$row
#   hap_pconf$row = leg_pconf$row
#   
#   # add rows of zeros to the p_conf pruned haplotype
#   hap_out = rbind(hap_pconf, add)
#   
#   # make sure the variants are in the correct order to match the legend file
#   hap_out = hap_out[order(hap_out$row),]
#   
#   # remove the row numbers
#   hap_out = hap_out[,-c(ncol(hap_out))]
#   
#   return(hap_out)
# }

### Determine the number of rare alleles in a dataset
# rare_var = function(legend_fun_idx, hap, maf){
#   
#   # Note: legend_fun_idx are the row indices of the haplotype file subset by 
#   # functional status (fun or syn)
#   
#   # Subset haplotype file to rows of legend file by functional status
#   hap_fun = hap[legend_fun_idx, ]
#   
#   # Calculate the AFs of each row of the haplotype file
#   hap_AF = rowSums(hap_fun)/ncol(hap)
#   
#   # Determine which rows of the haplotype file are rare variants
#   hap_rare = which(hap_AF <= maf)
#   
#   # Sum up number of rare alleles in the haplotype file
#   out = sum(rowSums(hap_fun[hap_rare, ]))
#   
#   return(out)
# }
