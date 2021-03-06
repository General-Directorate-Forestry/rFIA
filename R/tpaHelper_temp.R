tpaHelperDT <- function(x, combos, data, grpBy, aGrpBy, totals, SE){

  # Update domain indicator for each each column speficed in grpBy
  td = 1 # Start both at 1, update as we iterate through
  ad = 1
  pd = 1
  for (n in 1:ncol(combos[[x]])){
    # Tree domain indicator for each column in
    tObs <- as.character(combos[[x]][[grpBy[n]]]) == as.character(data[[grpBy[n]]])
    if (length(which(is.na(tObs))) == length(tObs)) tObs <- 1
    td <- data$tDI * tObs * td
    # Area domain indicator for each column in
    if(grpBy[n] %in% aGrpBy){
      aObs <- as.character(combos[[x]][[aGrpBy[n]]]) == as.character(data[[aGrpBy[n]]])
      if (length(which(is.na(aObs))) == length(aObs)) aObs <- 1
      aObs[is.na(aObs)] <- 0
      ad <- data$aDI * aObs * ad
      pd <- data$pDI * pd * aObs

    }
  }


  if(SE){
    data$tDI <- td
    data$tDI[is.na(data$tDI)] <- 0
    data$aDI <- ad
    data$aDI[is.na(data$aDI)] <- 0
    data$pDI <- pd
    data$pDI[is.na(data$pDI)] <- 0
    ## We produce an intermediate object in this chain as it is needed to compute the ratio of means variance
    ## Numerator and denominator are in different domains of interest, and may be grouped by different variables
    ## see covariance estimation below
    ### Compute total TREES in domain of interest
    tInt <- lazy_dt(data) %>%
      distinct(ESTN_UNIT_CN, STRATUM_CN, PLT_CN, CONDID, SUBP, TREE, EVALID, COND_STATUS_CD, .keep_all = TRUE) %>%
      #filter(EVALID %in% tID) %>%
      # Compute estimates at plot level
      group_by(ESTN_UNIT_CN, ESTN_METHOD, STRATUM_CN, PLT_CN) %>%
      summarize(tPlot = sum(TPA_UNADJ * tAdj * tDI, na.rm = TRUE),
                bPlot = sum(basalArea(DIA) * TPA_UNADJ * tAdj * tDI, na.rm = TRUE),
                tTPlot = sum(TPA_UNADJ * tAdj * pDI, na.rm = TRUE),
                bTPlot = sum(basalArea(DIA) * TPA_UNADJ * tAdj * pDI, na.rm = TRUE),
                plotIn = ifelse(sum(tDI >  0, na.rm = TRUE), 1,0),
                a = first(AREA_USED),
                p1EU = first(P1PNTCNT_EU),
                p1 = first(P1POINTCNT),
                p2 = first(P2POINTCNT)) %>%
      as.data.frame()
    ### Compute total AREA in the domain of interest
    aInt <- lazy_dt(data) %>%
      #filter(EVALID %in% aID) %>%
      distinct(ESTN_UNIT_CN, STRATUM_CN, PLT_CN, CONDID, .keep_all = TRUE) %>%
      group_by(ESTN_UNIT_CN, ESTN_METHOD, STRATUM_CN, PLT_CN) %>%
      summarize(fa = sum(CONDPROP_UNADJ * aDI * aAdj, na.rm = TRUE),
                plotIn = ifelse(sum(aDI >  0, na.rm = TRUE), 1,0),
                a = first(AREA_USED),
                p1EU = first(P1PNTCNT_EU),
                p1 = first(P1POINTCNT),
                p2 = first(P2POINTCNT)) %>%
      as.data.frame()

    # Continue through totals
    t <- tInt %>%
      inner_join(aInt, by = c('PLT_CN', 'ESTN_UNIT_CN', 'ESTN_METHOD', 'STRATUM_CN'), suffix = c('_t', '_a')) %>%
      lazy_dt() %>%
      group_by(ESTN_UNIT_CN, ESTN_METHOD, STRATUM_CN) %>%
      summarize(aStrat = mean(fa, na.rm = TRUE),
                tStrat = mean(tPlot, na.rm = TRUE),
                bStrat = mean(bPlot, na.rm = TRUE),
                tTStrat = mean(tTPlot, na.rm = TRUE),
                bTStrat = mean(bTPlot, na.rm = TRUE),
                plotIn_TREE = sum(plotIn_t, na.rm = TRUE),
                plotIn_AREA = sum(plotIn_a, na.rm = TRUE),
                a = first(a_t),
                w = first(p1_t) / first(p1EU_a), # Stratum weight
                nh = first(p2_t), # Number plots in stratum
                # Strata level variances
                tv = stratVar(tPlot, a_t, p2_t, ESTN_METHOD),
                bv = stratVar(bPlot, a_t, p2_t, ESTN_METHOD),
                tTv = stratVar(tTPlot, a_t, p2_t, ESTN_METHOD),
                bTv = stratVar(bTPlot, a_t, p2_t, ESTN_METHOD),
                av = stratVar(fa, a_t, p2_t, ESTN_METHOD),
                #Strata level covariances
                cvStrat_t = stratVar(tPlot, a_t, p2_t, ESTN_METHOD, fa),
                cvStrat_b = stratVar(bPlot, a_t, p2_t, ESTN_METHOD, fa),
                cvStrat_tT = stratVar(tTPlot, a_t, p2_t, ESTN_METHOD, tTPlot),
                cvStrat_bT = stratVar(bTPlot, a_t, p2_t, ESTN_METHOD, bTPlot)) %>%
                # # Strata level variances
                # tv = ifelse(first(ESTN_METHOD == 'simple'),
                #             var(tPlot * first(a) / nh),
                #             (sum(tPlot^2) - sum(nh * tStrat^2)) / (nh * (nh-1))), # Stratified and double cases
                # bv = ifelse(first(ESTN_METHOD == 'simple'),
                #             var(bPlot * first(a) / nh),
                #             (sum(bPlot^2) - sum(nh * bStrat^2)) / (nh * (nh-1))),
                # tTv = ifelse(first(ESTN_METHOD == 'simple'),
                #              var(tTPlot * first(a) / nh),
                #              (sum(tTPlot^2) - sum(nh * tTStrat^2)) / (nh * (nh-1))), # Stratified and double cases
                # bTv = ifelse(first(ESTN_METHOD == 'simple'),
                #              var(bTPlot * first(a) / nh),
                #              (sum(bTPlot^2) - sum(nh * bTStrat^2)) / (nh * (nh-1))),
                # av = ifelse(first(ESTN_METHOD == 'simple'),
                #             var(fa * first(a) / nh),
                #             (sum(fa^2) - sum(nh * aStrat^2)) / (nh * (nh-1))),
                # # Strata level covariances
                # cvStrat_t = ifelse(first(ESTN_METHOD == 'simple'),
                #                    cov(fa,tPlot),
                #                    (sum(fa*tPlot) - sum(nh * aStrat *tStrat)) / (nh * (nh-1))), # Stratified and double cases
                # cvStrat_b = ifelse(first(ESTN_METHOD == 'simple'),
                #                    cov(fa,bPlot),
                #                    (sum(fa*bPlot) - sum(nh * aStrat *bStrat)) / (nh * (nh-1))),
                # cvStrat_tT = ifelse(first(ESTN_METHOD == 'simple'),
                #                     cov(tTPlot,tPlot),
                #                     (sum(tTPlot*tPlot) - sum(nh * tTStrat *tStrat)) / (nh * (nh-1))), # Stratified and double cases
                # cvStrat_bT = ifelse(first(ESTN_METHOD == 'simple'),
                #                     cov(bTPlot,bPlot),
                #                     (sum(bTPlot*bPlot) - sum(nh * bTStrat *bStrat)) / (nh * (nh-1)))) %>% # Stratified and double cases
      group_by(ESTN_UNIT_CN) %>%
      summarize(aEst = unitMean(ESTN_METHOD, a, nh, w, aStrat),
                tEst = unitMean(ESTN_METHOD, a, nh, w, tStrat),
                bEst = unitMean(ESTN_METHOD, a, nh, w, bStrat),
                tTEst = unitMean(ESTN_METHOD, a, nh, w, tTStrat),
                bTEst = unitMean(ESTN_METHOD, a, nh, w, bTStrat),
                plotIn_TREE = sum(plotIn_TREE, na.rm = TRUE),
                plotIn_AREA = sum(plotIn_AREA, na.rm = TRUE),
                # Estimation of unit variance
                aVar = unitVarDT(method = 'var', ESTN_METHOD, a, nh, w, av, aStrat),
                tVar = unitVarDT(method = 'var', ESTN_METHOD, a, nh, w, tv, tStrat),
                bVar = unitVarDT(method = 'var', ESTN_METHOD, a, nh, w, bv, bStrat),
                tTVar = unitVarDT(method = 'var', ESTN_METHOD, a, nh, w, tTv, tTStrat),
                bTVar = unitVarDT(method = 'var', ESTN_METHOD, a, nh, w, bTv, bTStrat),
                # Unit Covariance
                cvEst_t = unitVarDT(method = 'cov', ESTN_METHOD, a, nh, w, cvStrat_t, tStrat, aStrat),
                cvEst_b = unitVarDT(method = 'cov', ESTN_METHOD, a, nh, w, cvStrat_b, bStrat, aStrat),
                cvEst_tT = unitVarDT(method = 'cov', ESTN_METHOD, a, nh, w, cvStrat_t, tStrat, tTStrat),
                cvEst_bT = unitVarDT(method = 'cov', ESTN_METHOD, a, nh, w, cvStrat_b, bStrat, bTStrat)) %>%
      # Compute totals
      summarize(TREE_TOTAL = sum(tEst, na.rm = TRUE),
                BA_TOTAL = sum(bEst, na.rm = TRUE),
                TREE_TOTAL_full = sum(tTEst, na.rm = TRUE),
                BA_TOTAL_full = sum(bTEst, na.rm = TRUE),
                AREA_TOTAL = sum(aEst, na.rm = TRUE),
                ## Variances
                treeVar = sum(tVar, na.rm = TRUE),
                baVar = sum(bVar, na.rm = TRUE),
                tTVar = sum(tTVar, na.rm = TRUE),
                bTVar = sum(bTVar, na.rm = TRUE),
                aVar = sum(aVar, na.rm = TRUE),
                cvT = sum(cvEst_t, na.rm = TRUE),
                cvB = sum(cvEst_b, na.rm = TRUE),
                cvTT = sum(cvEst_tT, na.rm = TRUE),
                cvBT = sum(cvEst_bT, na.rm = TRUE),
                nPlots_TREE = sum(plotIn_TREE, na.rm = TRUE),
                nPlots_AREA = sum(plotIn_AREA, na.rm = TRUE)) %>%
      as_tibble() %>%
      mutate(
        ## Ratios
        TPA = TREE_TOTAL / AREA_TOTAL,
        BAA = BA_TOTAL / AREA_TOTAL,
        TPA_PERC = TREE_TOTAL / TREE_TOTAL_full * 100,
        BAA_PERC = BA_TOTAL / BA_TOTAL_full * 100,
        ## Variances
        tpaVar = (1/AREA_TOTAL^2) * (treeVar + (TPA^2 * aVar) - 2 * TPA * cvT),
        baaVar = (1/AREA_TOTAL^2) * (baVar + (BAA^2 * aVar) - (2 * BAA * cvB)),
        tpVar = (1/TREE_TOTAL_full^2) * (treeVar + (TPA_PERC^2 * tTVar) - 2 * TPA_PERC * cvTT),
        bpVar = (1/BA_TOTAL_full^2) * (baVar + (BAA_PERC^2 * bTVar) - (2 * BAA_PERC * cvBT)),
        ## Sampling Errors
        TREE_SE = sqrt(treeVar) / TREE_TOTAL * 100,
        BA_SE = sqrt(baVar) / BA_TOTAL * 100,
        TREE_SE = sqrt(treeVar) / TREE_TOTAL * 100,
        BA_SE = sqrt(baVar) / BA_TOTAL * 100,
        AREA_TOTAL_SE = sqrt(aVar) / AREA_TOTAL * 100,
        TPA_SE = sqrt(tpaVar) / TPA * 100,
        BAA_SE = sqrt(baaVar) / BAA * 100,
        TPA_PERC_SE = sqrt(tpVar) / TPA_PERC * 100,
        BAA_PERC_SE = sqrt(bpVar) / BAA_PERC * 100)


    if (totals) {
      t <- t %>%
        select(TPA, BAA, TPA_PERC, BAA_PERC, TREE_TOTAL, BA_TOTAL, AREA_TOTAL, TPA_SE, BAA_SE,
               TPA_PERC_SE, BAA_PERC_SE, TREE_SE, BA_SE, AREA_TOTAL_SE, nPlots_TREE, nPlots_AREA)
    } else {
      t <- t %>%
        select(TPA, BAA, TPA_PERC, BAA_PERC, TPA_SE, BAA_SE,
               TPA_PERC_SE, BAA_PERC_SE, nPlots_TREE, nPlots_AREA)
    }
    #names(combos) <- 1:length(combos)
    #combosDF <- bind_rows(combos)

    #names(t) <- 1:length(t)
    # Convert from list to dataframe
    # t <- setNames(t, 1:length(t)) %>%
    #   bind_rows(t, .id = "column_label")
    #t <- bind_rows(t, .id = NULL)
    # Snag the names
    #tNames <- names(t)
    # Rejoin with grpBY
    t <- data.frame(combos[[x]], t) #%>%
    #filter(!is.na(YEAR))

  } else { # IF SE is FALSE
    ### BELOW DOES NOT PRODUCE SAMPLING ERRORS, use EXPNS instead (much quicker)
    t <- data %>%
      distinct(ESTN_UNIT_CN, STRATUM_CN, PLT_CN, CONDID, SUBP, TREE, EVALID, COND_STATUS_CD, .keep_all = TRUE) %>%
      # Compute estimates at plot level
      group_by(.dots = grpBy, ESTN_UNIT_CN, ESTN_METHOD, STRATUM_CN, PLT_CN) %>%
      summarize(tPlot = sum(TPA_UNADJ * tAdj * tDI * EXPNS, na.rm = TRUE),
                bPlot = sum(basalArea(DIA) * TPA_UNADJ * tAdj * tDI * EXPNS, na.rm = TRUE),
                plotIn = ifelse(sum(tDI >  0, na.rm = TRUE), 1,0)) %>%
      group_by(.dots = grpBy) %>%
      summarize(TREE_TOTAL = sum(tPlot, na.rm = TRUE),
                BA_TOTAL = sum(bPlot, na.rm = TRUE),
                nPlots_TREE = sum(plotIn, na.rm = TRUE))
    tT <- data %>%
      distinct(ESTN_UNIT_CN, STRATUM_CN, PLT_CN, CONDID, SUBP, TREE, EVALID, COND_STATUS_CD, .keep_all = TRUE) %>%
      # Compute estimates at plot level
      group_by(.dots = aGrpBy, ESTN_UNIT_CN, ESTN_METHOD, STRATUM_CN, PLT_CN) %>%
      summarize(tTPlot = sum(TPA_UNADJ * tAdj * pDI * EXPNS, na.rm = TRUE),
                bTPlot = sum(basalArea(DIA) * TPA_UNADJ * tAdj * pDI * EXPNS, na.rm = TRUE)) %>%
      group_by(.dots = aGrpBy) %>%
      summarize(TREE_TOTAL_full = sum(tTPlot, na.rm = TRUE),
                BA_TOTAL_full = sum(bTPlot, na.rm = TRUE))
    a <- data %>%
      distinct(ESTN_UNIT_CN, STRATUM_CN, PLT_CN, CONDID, .keep_all = TRUE) %>%
      group_by(.dots = aGrpBy, ESTN_UNIT_CN, ESTN_METHOD, STRATUM_CN, PLT_CN) %>%
      summarize(fa = sum(CONDPROP_UNADJ * aDI * aAdj * EXPNS, na.rm = TRUE),
                plotIn = ifelse(sum(aDI >  0, na.rm = TRUE), 1,0)) %>%
      group_by(.dots = aGrpBy) %>%
      summarize(AREA_TOTAL = sum(fa, na.rm = TRUE),
                nPlots_AREA = sum(plotIn, na.rm = TRUE))

    suppressMessages({
      t <- inner_join(t, tT) %>%
        inner_join(a) %>%
        mutate(TPA = TREE_TOTAL / AREA_TOTAL,
               BAA = BA_TOTAL / AREA_TOTAL,
               TPA_PERC = TREE_TOTAL / TREE_TOTAL_full * 100,
               BAA_PERC = BA_TOTAL / BA_TOTAL_full * 100)

      if (totals) {
        t <- t %>%
          select(grpBy, TPA, BAA, TPA_PERC, BAA_PERC, TREE_TOTAL, BA_TOTAL, AREA_TOTAL, nPlots_TREE, nPlots_AREA)
      } else {
        t <- t %>%
          select(grpBy, TPA, BAA, TPA_PERC, BAA_PERC, nPlots_TREE, nPlots_AREA)
      }
    })

  } # End SE conditional


  #Return a dataframe
  t
}

