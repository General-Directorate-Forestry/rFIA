standStructHelper <- function(x, combos, data, grpBy, totals, tidy, SE){
  # Update domain indicator for each each column speficed in grpBy
  td = 1 # Start both at 1, update as we iterate through
  ad = 1
  for (n in 1:ncol(combos[[x]])){
    # Area domain indicator for each column in
    aObs <- as.character(combos[[x]][[grpBy[n]]]) == as.character(data[[grpBy[n]]])
    ad <- data$aDI * aObs * ad
  }

  if(SE){
    data$aDI <- ad
    data$aDI[is.na(data$aDI)] <- 0
    # Compute estimates
    s <- data %>%
      group_by(ESTN_UNIT_CN, ESTN_METHOD, STRATUM_CN, PLT_CN, CONDID) %>%
      # filter(tDI > 0) %>%
      summarize(CONDPROP_UNADJ = first(CONDPROP_UNADJ),
                stage = structHelper(DIA, CCLCD),
                a = first(AREA_USED),
                p1EU = first(P1PNTCNT_EU),
                p1 = first(P1POINTCNT),
                p2 = first(P2POINTCNT),
                aAdj = first(aAdj),
                aDI = first(aDI)) %>%
      group_by(ESTN_UNIT_CN, ESTN_METHOD, STRATUM_CN, PLT_CN) %>%
      summarize(p = sum(CONDPROP_UNADJ[stage == 'pole'] * aDI[stage == 'pole'] * aAdj[stage == 'pole'], na.rm = TRUE),
                ma = sum(CONDPROP_UNADJ[stage == 'mature'] * aDI[stage == 'mature'] * aAdj[stage == 'mature'], na.rm = TRUE),
                l = sum(CONDPROP_UNADJ[stage == 'late'] * aDI[stage == 'late'] * aAdj[stage == 'late'], na.rm = TRUE),
                mo = sum(CONDPROP_UNADJ[stage == 'mosaic'] * aDI[stage == 'mosaic'] * aAdj[stage == 'mosaic'], na.rm = TRUE),
                faFull = sum(CONDPROP_UNADJ * aDI * aAdj, na.rm = TRUE),
                plotIn = ifelse(sum(aDI >  0, na.rm = TRUE), 1,0),
                p1EU = first(p1EU),
                a = first(a),
                p1 = first(p1),
                p2 = first(p2)) %>%
      # Continue through totals
      #d <- dInt %>%
      #filter(plotIn > 0) %>%
      group_by(ESTN_UNIT_CN, ESTN_METHOD, STRATUM_CN) %>%
      summarize(pStrat = mean(p, na.rm = TRUE),
                maStrat = mean(ma, na.rm = TRUE),
                lStrat = mean(l, na.rm = TRUE),
                moStrat = mean(mo, na.rm = TRUE),
                fullStrat = mean(faFull, na.rm = TRUE),
                plotIn = sum(plotIn, na.rm = TRUE),
                #vPlots = ifelse(plotIn > 1, plotIn, NA),
                a = first(a),
                w = first(p1) / first(p1EU), # Stratum weight
                nh = first(p2), # Number plots in stratum
                # Strata level variances
                pv = ifelse(first(ESTN_METHOD == 'simple'),
                            var(p * first(a) / nh),
                            (sum(p^2, na.rm = TRUE) - sum(nh * pStrat^2, na.rm = TRUE)) / (nh * (nh-1))),
                mav = ifelse(first(ESTN_METHOD == 'simple'),
                             var(ma * first(a) / nh),
                             (sum(ma^2, na.rm = TRUE) - sum(nh * maStrat^2, na.rm = TRUE)) / (nh * (nh-1))),
                lv = ifelse(first(ESTN_METHOD == 'simple'),
                            var(l * first(a) / nh),
                            (sum(l^2, na.rm = TRUE) - sum(nh * lStrat^2, na.rm = TRUE)) / (nh * (nh-1))),
                mov = ifelse(first(ESTN_METHOD == 'simple'),
                             var(mo * first(a) / nh),
                             (sum(mo^2, na.rm = TRUE) - sum(nh * moStrat^2, na.rm = TRUE)) / (nh * (nh-1))),
                fullv = ifelse(first(ESTN_METHOD == 'simple'),
                               var(faFull * first(a) / nh),
                               (sum(faFull^2, na.rm = TRUE) - sum(nh * fullStrat^2, na.rm = TRUE)) / (nh * (nh-1))),
                # cvStrat_t = ifelse(first(ESTN_METHOD == 'simple'),
                #                    cov(fa,tPlot),
                #                    (sum(fa*tPlot) - sum(nh * aStrat *tStrat)) / (nh * (nh-1))), # Stratified and double cases
                cvStrat_p = ifelse(first(ESTN_METHOD == 'simple'),
                                   cov(faFull,p),
                                   (sum(faFull*p, na.rm = TRUE) - sum(nh * pStrat *fullStrat, na.rm = TRUE)) / (nh * (nh-1))),
                cvStrat_ma = ifelse(first(ESTN_METHOD == 'simple'),
                                    cov(faFull,ma),
                                    (sum(faFull*ma, na.rm = TRUE) - sum(nh * maStrat *fullStrat, na.rm = TRUE)) / (nh * (nh-1))),
                cvStrat_l = ifelse(first(ESTN_METHOD == 'simple'),
                                   cov(faFull,l),
                                   (sum(faFull*l, na.rm = TRUE) - sum(nh * lStrat *fullStrat, na.rm = TRUE)) / (nh * (nh-1))),
                cvStrat_mo = ifelse(first(ESTN_METHOD == 'simple'),
                                    cov(faFullmo),
                                    (sum(faFull*mo, na.rm = TRUE) - sum(nh * moStrat *fullStrat, na.rm = TRUE)) / (nh * (nh-1)))) %>% # Stratified and double cases) %>% # Stratified and double cases
      group_by(ESTN_UNIT_CN) %>%
      summarize(plotIn = sum(plotIn, na.rm = TRUE),
                #vPlots = ifelse(plotIn > 1, plotIn, NA),
                pEst = unitMean(ESTN_METHOD, a, plotIn, w, pStrat),
                maEst = unitMean(ESTN_METHOD, a, plotIn, w, maStrat),
                lEst = unitMean(ESTN_METHOD, a, plotIn, w, lStrat),
                moEst = unitMean(ESTN_METHOD, a, plotIn, w, moStrat),
                fullEst = unitMean(ESTN_METHOD, a, plotIn, w, fullStrat),
                # Estimation of unit variance,
                pVar = unitVar(method = 'var', ESTN_METHOD, a, nh, w, pv, pStrat, pEst),
                maVar = unitVar(method = 'var', ESTN_METHOD, a, nh, w, mav, maStrat, maEst),
                lVar = unitVar(method = 'var', ESTN_METHOD, a, nh, w, lv, lStrat, lEst),
                moVar = unitVar(method = 'var', ESTN_METHOD, a, nh, w, mov, moStrat, moEst),
                fullVar = unitVar(method = 'var', ESTN_METHOD, a, nh, w, fullv, fullStrat, fullEst),
                cvEst_p = unitVar(method = 'cov', ESTN_METHOD, a, nh, w, cvStrat_p, pStrat, pEst, fullStrat, fullEst),
                cvEst_ma = unitVar(method = 'cov', ESTN_METHOD, a, nh, w, cvStrat_ma, maStrat, maEst, fullStrat, fullEst),
                cvEst_l = unitVar(method = 'cov', ESTN_METHOD, a, nh, w, cvStrat_l, lStrat, lEst, fullStrat, fullEst),
                cvEst_mo = unitVar(method = 'cov', ESTN_METHOD, a, nh, w, cvStrat_mo, moStrat, moEst, fullStrat, fullEst)) %>%
      # Compute totals
      summarize(POLE_AREA = sum(pEst, na.rm = TRUE),
                MATURE_AREA = sum(maEst, na.rm = TRUE),
                LATE_AREA = sum(lEst, na.rm = TRUE),
                MOSAIC_AREA = sum(moEst, na.rm = TRUE),
                TOTAL_AREA = sum(fullEst, na.rm = TRUE),
                POLE_PERC = POLE_AREA / TOTAL_AREA * 100,
                MATURE_PERC = MATURE_AREA / TOTAL_AREA * 100,
                LATE_PERC = LATE_AREA / TOTAL_AREA * 100,
                MOSAIC_PERC = MOSAIC_AREA / TOTAL_AREA * 100,
                nPlots = sum(plotIn, na.rm = TRUE),
                pVar = sum(pVar, na.rm = TRUE),
                maVar = sum(maVar, na.rm = TRUE),
                lVar = sum(lVar, na.rm = TRUE),
                moVar = sum(moVar, na.rm = TRUE),
                fVar = sum(fullVar, na.rm = TRUE),
                cvP = sum(cvEst_p, na.rm = TRUE),
                cvMa = sum(cvEst_ma, na.rm = TRUE),
                cvL = sum(cvEst_l, na.rm = TRUE),
                cvMo = sum(cvEst_mo, na.rm = TRUE),
                ppVar = (1/TOTAL_AREA^2) * (pVar + (POLE_PERC^2 * fVar) - 2 * POLE_PERC * cvP),
                mapVar = (1/TOTAL_AREA^2) * (maVar + (MATURE_PERC^2 * fVar) - 2 * MATURE_PERC * cvMa),
                lpVar = (1/TOTAL_AREA^2) * (lVar + (LATE_PERC^2 * fVar) - 2 * LATE_PERC * cvL),
                mopVar = (1/TOTAL_AREA^2) * (moVar + (MOSAIC_PERC^2 * fVar) - 2 * MOSAIC_PERC * cvMo),
                POLE_AREA_SE = ifelse(nPlots > 1, sqrt(pVar) / POLE_AREA * 100,0),
                MATURE_AREA_SE = ifelse(nPlots > 1, sqrt(maVar) / MATURE_AREA * 100,0),
                LATE_AREA_SE = ifelse(nPlots > 1, sqrt(lVar) / LATE_AREA * 100,0),
                MOSAIC_AREA_SE = ifelse(nPlots > 1, sqrt(moVar) / MOSAIC_AREA * 100,0),
                POLE_PERC_SE = ifelse(nPlots > 1, sqrt(ppVar) / POLE_PERC * 100,0),
                MATURE_PERC_SE = ifelse(nPlots > 1, sqrt(mapVar) / MATURE_PERC * 100,0),
                LATE_PERC_SE = ifelse(nPlots > 1, sqrt(lpVar) / LATE_PERC * 100,0),
                MOSAIC_PERC_SE = ifelse(nPlots > 1, sqrt(mopVar) / MOSAIC_PERC * 100,0),
                TOTAL_AREA_SE = ifelse(nPlots > 1, sqrt(fVar) / TOTAL_AREA * 100,0)) %>%
      select(POLE_PERC, MATURE_PERC, LATE_PERC, MOSAIC_PERC,
             POLE_AREA, MATURE_AREA, LATE_AREA, MOSAIC_AREA, TOTAL_AREA,
             POLE_PERC_SE, MATURE_PERC_SE, LATE_PERC_SE, MOSAIC_PERC_SE,
             POLE_AREA_SE, MATURE_AREA_SE, LATE_AREA_SE, MOSAIC_AREA_SE,
             TOTAL_AREA_SE, nPlots)
    if(totals == FALSE){
      s <- s %>%
        select(POLE_PERC, MATURE_PERC, LATE_PERC, MOSAIC_PERC,
               POLE_PERC_SE, MATURE_PERC_SE, LATE_PERC_SE, MOSAIC_PERC_SE, nPlots)
    }

    # Rejoin w/ groupby names
    s <- data.frame(combos[[x]], s)

  } else {
    # Compute estimates
    s <- data %>%
      group_by(.dots = grpBy, ESTN_UNIT_CN, ESTN_METHOD, STRATUM_CN, PLT_CN, CONDID) %>%
      # filter(tDI > 0) %>%
      summarize(CONDPROP_UNADJ = first(CONDPROP_UNADJ),
                stage = structHelper(DIA, CCLCD),
                aAdj = first(aAdj),
                aDI = first(aDI),
                EXPNS = first(EXPNS)) %>%
      group_by(.dots = grpBy, ESTN_UNIT_CN, ESTN_METHOD, STRATUM_CN, PLT_CN) %>%
      summarize(p = sum(CONDPROP_UNADJ[stage == 'pole'] * aDI[stage == 'pole'] * aAdj[stage == 'pole'] * EXPNS[stage == 'pole'], na.rm = TRUE),
                ma = sum(CONDPROP_UNADJ[stage == 'mature'] * aDI[stage == 'mature'] * aAdj[stage == 'mature'] * EXPNS[stage == 'mature'], na.rm = TRUE),
                l = sum(CONDPROP_UNADJ[stage == 'late'] * aDI[stage == 'late'] * aAdj[stage == 'late'] * EXPNS[stage == 'late'], na.rm = TRUE),
                mo = sum(CONDPROP_UNADJ[stage == 'mosaic'] * aDI[stage == 'mosaic'] * aAdj[stage == 'mosaic'] * EXPNS[stage == 'mosaic'], na.rm = TRUE),
                faFull = sum(CONDPROP_UNADJ * aDI * aAdj * EXPNS, na.rm = TRUE),
                plotIn = ifelse(sum(aDI >  0, na.rm = TRUE), 1,0)) %>%
      group_by(.dots = grpBy) %>%
      summarize(POLE_AREA = sum(p, na.rm = TRUE),
                MATURE_AREA = sum(ma, na.rm = TRUE),
                LATE_AREA = sum(l, na.rm = TRUE),
                MOSAIC_AREA = sum(mo, na.rm = TRUE),
                TOTAL_AREA = sum(faFull, na.rm = TRUE),
                POLE_PERC = POLE_AREA / TOTAL_AREA * 100,
                MATURE_PERC = MATURE_AREA / TOTAL_AREA * 100,
                LATE_PERC = LATE_AREA / TOTAL_AREA * 100,
                MOSAIC_PERC = MOSAIC_AREA / TOTAL_AREA * 100,
                nPlots = sum(plotIn, na.rm = TRUE)) %>%
      select(grpBy, POLE_PERC, MATURE_PERC, LATE_PERC, MOSAIC_PERC,
             POLE_AREA, MATURE_AREA, LATE_AREA, MOSAIC_AREA, TOTAL_AREA,
             nPlots)

    if(totals == FALSE){
      s <- s %>%
        select(grpBy, POLE_PERC, MATURE_PERC, LATE_PERC, MOSAIC_PERC, nPlots)
    }


  } # End SE Conditional

  # Do some cleanup
  gc()

  #Return a dataframe
  s


}