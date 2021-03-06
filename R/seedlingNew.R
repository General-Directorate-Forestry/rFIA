#' @export
seedling <- function(db,
                   grpBy = NULL,
                   polys = NULL,
                   returnSpatial = FALSE,
                   bySpecies = FALSE,
                   landType = 'forest',
                   method = 'TI',
                   lambda = .5,
                   treeDomain = NULL,
                   areaDomain = NULL,
                   totals = FALSE,
                   byPlot = FALSE,
                   nCores = 1) {


  ## Need a plotCN, and a new ID
  db$PLOT <- db$PLOT %>% mutate(PLT_CN = CN,
                                pltID = paste(UNITCD, STATECD, COUNTYCD, PLOT, sep = '_'))

  ##  don't have to change original code
  grpBy_quo <- enquo(grpBy)

  # Probably cheating, but it works
  if (quo_name(grpBy_quo) != 'NULL'){
    ## Have to join tables to run select with this object type
    plt_quo <- filter(db$PLOT, !is.na(PLT_CN))
    ## We want a unique error message here to tell us when columns are not present in data
    d_quo <- tryCatch(
      error = function(cnd) {
        return(0)
      },
      plt_quo[10,] %>% # Just the first row
        left_join(select(db$COND, PLT_CN, names(db$COND)[names(db$COND) %in% names(db$PLOT) == FALSE]), by = 'PLT_CN') %>%
        select(!!grpBy_quo)
    )

    # If column doesnt exist, just returns 0, not a dataframe
    if (is.null(nrow(d_quo))){
      grpName <- quo_name(grpBy_quo)
      stop(paste('Columns', grpName, 'not found in PLOT or COND tables. Did you accidentally quote the variables names? e.g. use grpBy = ECOSUBCD (correct) instead of grpBy = "ECOSUBCD". ', collapse = ', '))
    } else {
      # Convert to character
      grpBy <- names(d_quo)
    }
  }

  reqTables <- c('PLOT', 'SEEDLING', 'COND', 'POP_PLOT_STRATUM_ASSGN', 'POP_ESTN_UNIT', 'POP_EVAL',
                 'POP_STRATUM', 'POP_EVAL_TYP', 'POP_EVAL_GRP')
  ## Some warnings
  if (class(db) != "FIA.Database"){
    stop('db must be of class "FIA.Database". Use readFIA() to load your FIA data.')
  }
  if (!is.null(polys) & first(class(polys)) %in% c('sf', 'SpatialPolygons', 'SpatialPolygonsDataFrame') == FALSE){
    stop('polys must be spatial polygons object of class sp or sf. ')
  }
  if (landType %in% c('timber', 'forest') == FALSE){
    stop('landType must be one of: "forest" or "timber".')
  }
  if (any(reqTables %in% names(db) == FALSE)){
    missT <- reqTables[reqTables %in% names(db) == FALSE]
    stop(paste('Tables', paste (as.character(missT), collapse = ', '), 'not found in object db.'))
  }
  if (str_to_upper(method) %in% c('TI', 'SMA', 'LMA', 'EMA', 'ANNUAL') == FALSE) {
    warning(paste('Method', method, 'unknown. Defaulting to Temporally Indifferent (TI).'))
  }

  # I like a unique ID for a plot through time
  if (byPlot) {grpBy <- c('pltID', grpBy)}
  # Save original grpBy for pretty return with spatial objects
  grpByOrig <- grpBy

  ## IF the object was clipped
  if ('prev' %in% names(db$PLOT)){
    ## Only want the current plots, no grm
    db$PLOT <- filter(db$PLOT, prev == 0)
  }



  ### AREAL SUMMARY PREP
  if(!is.null(polys)) {
    # Convert polygons to an sf object
    polys <- polys %>%
      as('sf')%>%
      mutate_if(is.factor,
                as.character)
    ## A unique ID
    polys$polyID <- 1:nrow(polys)

    # Add shapefile names to grpBy
    #grpBy = c(names(polys)[str_detect(names(polys), 'geometry') == FALSE], 'polyID', grpBy)
    grpBy = c(grpBy, 'polyID')

    ## Make plot data spatial, projected same as polygon layer
    pltSF <- select(db$PLOT, c('LON', 'LAT', pltID)) %>%
      filter(!is.na(LAT) & !is.na(LON)) %>%
      distinct(pltID, .keep_all = TRUE)
    coordinates(pltSF) <- ~LON+LAT
    proj4string(pltSF) <- '+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs'
    pltSF <- as(pltSF, 'sf') %>%
      st_transform(crs = st_crs(polys)$proj4string)

    ## Split up polys
    polyList <- split(polys, as.factor(polys$polyID))
    suppressWarnings({suppressMessages({
      ## Compute estimates in parallel -- Clusters in windows, forking otherwise
      if (Sys.info()['sysname'] == 'Windows'){
        cl <- makeCluster(nCores)
        clusterEvalQ(cl, {
          library(dplyr)
          library(stringr)
          library(rFIA)
        })
        out <- parLapply(cl, X = names(polyList), fun = areal_par, pltSF, polyList)
        #stopCluster(cl) # Keep the cluster active for the next run
      } else { # Unix systems
        out <- mclapply(names(polyList), FUN = areal_par, pltSF, polyList, mc.cores = nCores)
      }
    })})
    pltSF <- bind_rows(out)

    # A warning
    if (length(unique(pltSF$pltID)) < 1){
      stop('No plots in db overlap with polys.')
    }
    ## Add polygon names to PLOT
    db$PLOT <- db$PLOT %>%
      left_join(select(pltSF, polyID, pltID), by = 'pltID')

    # Test if any polygons cross state boundaries w/ different recent inventory years (continued w/in loop)
    if ('mostRecent' %in% names(db) & length(unique(db$POP_EVAL$STATECD)) > 1){
      mergeYears <- pltSF %>%
        right_join(select(db$PLOT, PLT_CN, pltID), by = 'pltID') %>%
        inner_join(select(db$POP_PLOT_STRATUM_ASSGN, c('PLT_CN', 'EVALID', 'STATECD')), by = 'PLT_CN') %>%
        inner_join(select(db$POP_EVAL, c('EVALID', 'END_INVYR')), by = 'EVALID') %>%
        group_by(polyID) %>%
        summarize(maxYear = max(END_INVYR, na.rm = TRUE))
    }

    ## TO RETURN SPATIAL PLOTS
  }
  if (byPlot & returnSpatial){
    grpBy <- c(grpBy, 'LON', 'LAT')
  } # END AREAL

  ## Build domain indicator function which is 1 if observation meets criteria, and 0 otherwise
  # Land type domain indicator
  if (tolower(landType) == 'forest'){
    db$COND$landD <- ifelse(db$COND$COND_STATUS_CD == 1, 1, 0)
  } else if (tolower(landType) == 'timber'){
    db$COND$landD <- ifelse(db$COND$COND_STATUS_CD == 1 & db$COND$SITECLCD %in% c(1, 2, 3, 4, 5, 6) & db$COND$RESERVCD == 0, 1, 0)
  }

  # update spatial domain indicator
  if(!is.null(polys)){
    db$PLOT$sp <- ifelse(db$PLOT$pltID %in% pltSF$pltID, 1, 0)
  } else {
    db$PLOT$sp <- 1
  }

  # User defined domain indicator for area (ex. specific forest type)
  pcEval <- left_join(db$PLOT, select(db$COND, -c('STATECD', 'UNITCD', 'COUNTYCD', 'INVYR', 'PLOT')), by = 'PLT_CN')
  areaDomain <- substitute(areaDomain)
  pcEval$aD <- eval(areaDomain, pcEval) ## LOGICAL, THIS IS THE DOMAIN INDICATOR
  if(!is.null(pcEval$aD)) pcEval$aD[is.na(pcEval$aD)] <- 0 # Make NAs 0s. Causes bugs otherwise
  if(is.null(pcEval$aD)) pcEval$aD <- 1 # IF NULL IS GIVEN, THEN ALL VALUES TRUE
  pcEval$aD <- as.numeric(pcEval$aD)
  db$COND <- left_join(db$COND, select(pcEval, c('PLT_CN', 'CONDID', 'aD')), by = c('PLT_CN', 'CONDID')) %>%
    mutate(aD_c = aD)
  aD_p <- pcEval %>%
    group_by(PLT_CN) %>%
    summarize(aD_p = as.numeric(any(aD > 0)))
  db$PLOT <- left_join(db$PLOT, aD_p, by = 'PLT_CN')
  rm(pcEval)

  # Same as above for tree (ex. trees > 20 ft tall)
  treeDomain <- substitute(treeDomain)
  tD <- eval(treeDomain, db$SEEDLING) ## LOGICAL, THIS IS THE DOMAIN INDICATOR
  if(!is.null(tD)) tD[is.na(tD)] <- 0 # Make NAs 0s. Causes bugs otherwise
  if(is.null(tD)) tD <- 1 # IF NULL IS GIVEN, THEN ALL VALUES TRUE
  db$SEEDLING$tD <- as.numeric(tD)

  ### Snag the EVALIDs that are needed
  db$POP_EVAL<- db$POP_EVAL %>%
    select('CN', 'END_INVYR', 'EVALID', 'ESTN_METHOD') %>%
    inner_join(select(db$POP_EVAL_TYP, c('EVAL_CN', 'EVAL_TYP')), by = c('CN' = 'EVAL_CN')) %>%
    filter(EVAL_TYP == 'EXPVOL' | EVAL_TYP == 'EXPCURR') %>%
    filter(!is.na(END_INVYR) & !is.na(EVALID) & END_INVYR >= 2003) %>%
    distinct(END_INVYR, EVALID, .keep_all = TRUE)# %>%
  #group_by(END_INVYR) %>%
  #summarise(id = list(EVALID)

  ## Make an annual panel ID, associated with an INVYR

  ### The population tables
  pops <- select(db$POP_EVAL, c('EVALID', 'ESTN_METHOD', 'CN', 'END_INVYR')) %>%
    rename(EVAL_CN = CN) %>%
    left_join(select(db$POP_ESTN_UNIT, c('CN', 'EVAL_CN', 'AREA_USED', 'P1PNTCNT_EU')), by = c('EVAL_CN')) %>%
    rename(ESTN_UNIT_CN = CN) %>%
    left_join(select(db$POP_STRATUM, c('ESTN_UNIT_CN', 'EXPNS', 'P2POINTCNT', 'CN', 'P1POINTCNT', 'ADJ_FACTOR_SUBP', 'ADJ_FACTOR_MICR', "ADJ_FACTOR_MACR")), by = c('ESTN_UNIT_CN')) %>%
    rename(STRATUM_CN = CN) %>%
    left_join(select(db$POP_PLOT_STRATUM_ASSGN, c('STRATUM_CN', 'PLT_CN', 'INVYR', 'STATECD')), by = 'STRATUM_CN') %>%
    mutate_if(is.factor,
              as.character)

  ### Which estimator to use?
  if (str_to_upper(method) %in% c('ANNUAL')){
    ## Want to use the year where plots are measured, no repeats
    ## Breaking this up into pre and post reporting becuase
    ## Estimation units get weird on us otherwise
    popOrig <- pops
    pops <- pops %>%
      group_by(STATECD) %>%
      filter(END_INVYR == INVYR) %>%
      ungroup()

    prePops <- popOrig %>%
      group_by(STATECD) %>%
      filter(INVYR < min(END_INVYR, na.rm = TRUE)) %>%
      distinct(PLT_CN, .keep_all = TRUE) %>%
      ungroup()

    pops <- bind_rows(pops, prePops) %>%
      mutate(YEAR = INVYR)

  } else {     # Otherwise temporally indifferent
    pops <- rename(pops, YEAR = END_INVYR)
  }

  ## P2POINTCNT column is NOT consistent for annnual estimates, plots
  ## within individual strata and est units are related to different INVYRs
  p2_INVYR <- pops %>%
    group_by(ESTN_UNIT_CN, STRATUM_CN, INVYR) %>%
    summarize(P2POINTCNT_INVYR = length(unique(PLT_CN)))
  ## Want a count of p2 points / eu, gets screwed up with grouping below
  p2eu_INVYR <- p2_INVYR %>%
    distinct(ESTN_UNIT_CN, STRATUM_CN, INVYR, .keep_all = TRUE) %>%
    group_by(ESTN_UNIT_CN, INVYR) %>%
    summarize(p2eu_INVYR = sum(P2POINTCNT_INVYR, na.rm = TRUE))
  p2eu <- pops %>%
    distinct(ESTN_UNIT_CN, STRATUM_CN, .keep_all = TRUE) %>%
    group_by(ESTN_UNIT_CN) %>%
    summarize(p2eu = sum(P2POINTCNT, na.rm = TRUE))

  ## Rejoin
  pops <- pops %>%
    left_join(p2_INVYR, by = c('ESTN_UNIT_CN', 'STRATUM_CN', 'INVYR')) %>%
    left_join(p2eu_INVYR, by = c('ESTN_UNIT_CN', 'INVYR')) %>%
    left_join(p2eu, by = 'ESTN_UNIT_CN')


  ## Recode a few of the estimation methods to make things easier below
  pops$ESTN_METHOD = recode(.x = pops$ESTN_METHOD,
                            `Post-Stratification` = 'strat',
                            `Stratified random sampling` = 'strat',
                            `Double sampling for stratification` = 'double',
                            `Simple random sampling` = 'simple',
                            `Subsampling units of unequal size` = 'simple')


  ## Add species to groups
  if (bySpecies) {
    db$SEEDLING <- db$SEEDLING %>%
      left_join(select(intData$REF_SPECIES_2018, c('SPCD','COMMON_NAME', 'GENUS', 'SPECIES')), by = 'SPCD') %>%
      mutate(SCIENTIFIC_NAME = paste(GENUS, SPECIES, sep = ' ')) %>%
      mutate_if(is.factor,
                as.character)
    grpBy <- c(grpBy, 'SPCD', 'COMMON_NAME', 'SCIENTIFIC_NAME')
    grpByOrig <- c(grpByOrig, 'SPCD', 'COMMON_NAME', 'SCIENTIFIC_NAME')
  }


  # Seperate area grouping names, (ex. TPA red oak in total land area of ingham county, rather than only area where red oak occurs)
  if (!is.null(polys)){
    aGrpBy <- c(grpBy[grpBy %in% names(db$PLOT) | grpBy %in% names(db$COND) | grpBy %in% names(pltSF)])
  } else {
    aGrpBy <- c(grpBy[grpBy %in% names(db$PLOT) | grpBy %in% names(db$COND)])
  }

  ## Only the necessary plots for EVAL of interest
  db$PLOT <- filter(db$PLOT, PLT_CN %in% pops$PLT_CN)

  ## Merging state and county codes
  plts <- split(db$PLOT, as.factor(paste(db$PLOT$COUNTYCD, db$PLOT$STATECD, sep = '_')))
  #plts <- split(db$PLOT, as.factor(db$PLOT$STATECD))

  suppressWarnings({
    ## Compute estimates in parallel -- Clusters in windows, forking otherwise
    if (Sys.info()['sysname'] == 'Windows'){
      cl <- makeCluster(nCores)
      clusterEvalQ(cl, {
        library(dplyr)
        library(stringr)
        library(rFIA)
      })
      out <- parLapply(cl, X = names(plts), fun = seedHelper1, plts, db, grpBy, aGrpBy, byPlot)
      #stopCluster(cl) # Keep the cluster active for the next run
    } else { # Unix systems
      out <- mclapply(names(plts), FUN = seedHelper1, plts, db, grpBy, aGrpBy, byPlot, mc.cores = nCores)
    }
  })

  if (byPlot){
    ## back to dataframes
    out <- unlist(out, recursive = FALSE)
    tOut <- bind_rows(out[names(out) == 't'])
    ## Make it spatial
    if (returnSpatial){
      tOut <- tOut %>%
        filter(!is.na(LAT) & !is.na(LON)) %>%
        st_as_sf(coords = c('LON', 'LAT'),
                 crs = '+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs')
      grpBy <- grpBy[grpBy %in% c('LAT', 'LON') == FALSE]

    }
    ## Population estimation
  } else {
    ## back to dataframes
    out <- unlist(out, recursive = FALSE)
    a <- bind_rows(out[names(out) == 'a'])
    t <- bind_rows(out[names(out) == 't'])


    ## Adding YEAR to groups
    grpBy <- c('YEAR', grpBy)
    aGrpBy <- c('YEAR', aGrpBy)


    ## Splitting up by ESTN_UNIT
    popState <- split(pops, as.factor(pops$STATECD))

    suppressWarnings({
      ## Compute estimates in parallel -- Clusters in windows, forking otherwise
      if (Sys.info()['sysname'] == 'Windows'){
        ## Use the same cluster as above
        # cl <- makeCluster(nCores)
        # clusterEvalQ(cl, {
        #   library(dplyr)
        #   library(stringr)
        #   library(rFIA)
        # })
        out <- parLapply(cl, X = names(popState), fun = seedHelper2, popState, a, t, grpBy, aGrpBy, method)
        stopCluster(cl)
      } else { # Unix systems
        out <- mclapply(names(popState), FUN = seedHelper2, popState, a, t, grpBy, aGrpBy, method, mc.cores = nCores)
      }
    })
    ## back to dataframes
    out <- unlist(out, recursive = FALSE)
    aEst <- bind_rows(out[names(out) == 'aEst'])
    tEst <- bind_rows(out[names(out) == 'tEst'])


    ##### ----------------- MOVING AVERAGES
    if (str_to_upper(method) %in% c("SMA", 'EMA', 'LMA')){
      ### ---- SIMPLE MOVING AVERAGE
      if (str_to_upper(method) == 'SMA'){
        ## Assuming a uniform weighting scheme
        wgts <- pops %>%
          group_by(ESTN_UNIT_CN) %>%
          summarize(wgt = 1 / length(unique(INVYR)))

        aEst <- left_join(aEst, wgts, by = 'ESTN_UNIT_CN')
        tEst <- left_join(tEst, wgts, by = 'ESTN_UNIT_CN')

        #### ----- Linear MOVING AVERAGE
      } else if (str_to_upper(method) == 'LMA'){
        wgts <- pops %>%
          distinct(YEAR, ESTN_UNIT_CN, INVYR, .keep_all = TRUE) %>%
          arrange(YEAR, ESTN_UNIT_CN, INVYR) %>%
          group_by(as.factor(YEAR), as.factor(ESTN_UNIT_CN)) %>%
          mutate(rank = min_rank(INVYR))

        ## Want a number of INVYRs per EU
        neu <- wgts %>%
          group_by(ESTN_UNIT_CN) %>%
          summarize(n = sum(rank, na.rm = TRUE))

        ## Rejoining and computing wgts
        wgts <- wgts %>%
          left_join(neu, by = 'ESTN_UNIT_CN') %>%
          mutate(wgt = rank / n) %>%
          ungroup() %>%
          select(ESTN_UNIT_CN, INVYR, wgt)

        aEst <- left_join(aEst, wgts, by = c('ESTN_UNIT_CN', 'INVYR'))
        tEst <- left_join(tEst, wgts, by = c('ESTN_UNIT_CN', 'INVYR'))

        #### ----- EXPONENTIAL MOVING AVERAGE
      } else if (str_to_upper(method) == 'EMA'){
        wgts <- pops %>%
          distinct(YEAR, ESTN_UNIT_CN, INVYR, .keep_all = TRUE) %>%
          arrange(YEAR, ESTN_UNIT_CN, INVYR) %>%
          group_by(as.factor(YEAR), as.factor(ESTN_UNIT_CN)) %>%
          mutate(rank = min_rank(INVYR))


        if (length(lambda) < 2){
          ## Want sum of weighitng functions
          neu <- wgts %>%
            mutate(l = lambda) %>%
            group_by(ESTN_UNIT_CN) %>%
            summarize(l = first(lambda),
                      sumwgt = sum(l*(1-l)^(1-rank), na.rm = TRUE))

          ## Rejoining and computing wgts
          wgts <- wgts %>%
            left_join(neu, by = 'ESTN_UNIT_CN') %>%
            mutate(wgt = l*(1-l)^(1-rank) / sumwgt) %>%
            ungroup() %>%
            select(ESTN_UNIT_CN, INVYR, wgt)
        } else {
          grpBy <- c('lambda', grpBy)
          aGrpBy <- c('lambda', aGrpBy)
          ## Duplicate weights for each level of lambda
          yrWgts <- list()
          for (i in 1:length(unique(lambda))) {
            yrWgts[[i]] <- mutate(wgts, lambda = lambda[i])
          }
          wgts <- bind_rows(yrWgts)
          ## Want sum of weighitng functions
          neu <- wgts %>%
            group_by(lambda, ESTN_UNIT_CN) %>%
            summarize(l = first(lambda),
                      sumwgt = sum(l*(1-l)^(1-rank), na.rm = TRUE))

          ## Rejoining and computing wgts
          wgts <- wgts %>%
            left_join(neu, by = c('lambda', 'ESTN_UNIT_CN')) %>%
            mutate(wgt = l*(1-l)^(1-rank) / sumwgt) %>%
            ungroup() %>%
            select(lambda, ESTN_UNIT_CN, INVYR, wgt)
        }

        aEst <- left_join(aEst, wgts, by = c('ESTN_UNIT_CN', 'INVYR'))
        tEst <- left_join(tEst, wgts, by = c('ESTN_UNIT_CN', 'INVYR'))

      }
      ### Applying the weights
      # Area
      aEst <- aEst %>%
        mutate_at(vars(aEst), ~(.*wgt)) %>%
        mutate_at(vars(aVar), ~(.*(wgt^2))) %>%
        group_by(ESTN_UNIT_CN, .dots = aGrpBy) %>%
        summarize_at(vars(aEst:plotIn_AREA), sum, na.rm = TRUE)


      tEst <- tEst %>%
        mutate_at(vars(tEst:tTEst), ~(.*wgt)) %>%
        mutate_at(vars(tVar:cvEst_tT), ~(.*(wgt^2))) %>%
        group_by(ESTN_UNIT_CN, .dots = grpBy) %>%
        summarize_at(vars(tEst:cvEst_tT), sum, na.rm = TRUE)

    }




    ##---------------------  TOTALS and RATIOS
    # Area
    aTotal <- aEst %>%
      group_by(.dots = aGrpBy) %>%
      summarize(AREA_TOTAL = sum(aEst, na.rm = TRUE),
                aVar = sum(aVar, na.rm = TRUE),
                AREA_TOTAL_SE = sqrt(aVar) / AREA_TOTAL * 100,
                nPlots_AREA = sum(plotIn_AREA, na.rm = TRUE))
    # Tree
    tTotal <- tEst %>%
      group_by(.dots = grpBy) %>%
      #left_join(aTotal, by = c(aGrpBy)) %>%
      summarize(TREE_TOTAL = sum(tEst, na.rm = TRUE),
                ## Variances
                treeVar = sum(tVar, na.rm = TRUE),
                #aVar = first(aVar),
                cvT = sum(cvEst_t, na.rm = TRUE),
                ## Sampling Errors
                TREE_SE = sqrt(treeVar) / TREE_TOTAL * 100,
                nPlots_SEEDLING = sum(plotIn_TREE, na.rm = TRUE)) #%>%
    ## IF using polys, we treat each zone as a unique population
    if (!is.null(polys)){
      propGrp <- c('polyID', grpBy)
    } else {
      propGrp <- 'YEAR'
    }
    ## Hand the proportions
    tpTotal <- tEst %>%
      group_by(.dots = propGrp) %>%
      summarize(TREE_TOTAL_full = sum(tTEst, na.rm = TRUE), ## Need to sum this
                tTVar = sum(tTVar, na.rm = TRUE),
                cvTT = sum(cvEst_tT, na.rm = TRUE))


    suppressWarnings({
      ## Bring them together
      tTotal <- tTotal %>%
        left_join(aTotal, by = aGrpBy) %>%
        left_join(tpTotal, by = propGrp) %>%
        mutate(TPA = TREE_TOTAL / AREA_TOTAL,
               tpaVar = (1/AREA_TOTAL^2) * (treeVar + (TPA^2 * aVar) - 2 * TPA * cvT),
               TPA_SE = sqrt(tpaVar) / TPA * 100,
               TPA_PERC = TREE_TOTAL / (TREE_TOTAL_full) * 100,
               tpVar = (1/TREE_TOTAL_full^2) * (treeVar + (TPA_PERC^2 * tTVar) - 2 * TPA_PERC * cvTT),
               TPA_PERC_SE = sqrt(tpVar) / TPA_PERC * 100)
    })


    if (totals) {
      tOut <- tTotal %>%
        select(grpBy, TPA, TPA_PERC, TREE_TOTAL, AREA_TOTAL, TPA_SE,
               TPA_PERC_SE, TREE_SE, AREA_TOTAL_SE, nPlots_SEEDLING, nPlots_AREA)
    } else {
      tOut <- tTotal %>%
        select(grpBy, TPA, TPA_PERC,  TPA_SE,
               TPA_PERC_SE, nPlots_SEEDLING, nPlots_AREA)
    }

    # Snag the names
    tNames <- names(tOut)[names(tOut) %in% grpBy == FALSE]

  }

  ## Pretty output
  tOut <- tOut %>%
    ungroup() %>%
    mutate_if(is.factor, as.character) %>%
    drop_na(grpBy) %>%
    arrange(YEAR) %>%
    as_tibble()

  # Return a spatial object
  if (!is.null(polys) & byPlot == FALSE) {
    ## NO IMPLICIT NA
    nospGrp <- unique(grpBy[grpBy %in% c('SPCD', 'SYMBOL', 'COMMON_NAME', 'SCIENTIFIC_NAME') == FALSE])
    nospSym <- syms(nospGrp)
    tOut <- complete(tOut, !!!nospSym)
    ## If species, we don't want unique combos of variables related to same species
    ## but we do want NAs in polys where species are present
    if (length(nospGrp) < length(grpBy)){
      spGrp <- unique(grpBy[grpBy %in% c('SPCD', 'SYMBOL', 'COMMON_NAME', 'SCIENTIFIC_NAME')])
      spSym <- syms(spGrp)
      tOut <- complete(tOut, nesting(!!!nospSym))
    }

    suppressMessages({suppressWarnings({tOut <- left_join(tOut, polys) %>%
      select(c('YEAR', grpByOrig, tNames, names(polys))) %>%
      filter(!is.na(polyID))})})

    ## Makes it horrible to work with as a dataframe
    if (returnSpatial == FALSE) tOut <- select(tOut, -c(geometry))
  } else if (!is.null(polys) & byPlot){
    polys <- as.data.frame(polys)
    tOut <- left_join(tOut, select(polys, -c(geometry)), by = 'polyID')
  }

  ## For spatial plots
  if (returnSpatial & byPlot) grpBy <- grpBy[grpBy %in% c('LAT', 'LON') == FALSE]

  ## Above converts to tibble
  if (returnSpatial) tOut <- st_sf(tOut)
  # ## remove any duplicates in byPlot (artifact of END_INYR loop)
  if (byPlot) tOut <- unique(tOut)
  return(tOut)
}
