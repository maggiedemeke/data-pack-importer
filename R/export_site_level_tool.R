#' @export
#' @title write_site_level_sheet(wb,schema,df)
#'
#' @description Validates the layout of all relevant sheets in a data pack workbook
#' @param wb_path Workbook object
#' @param schema Schema object for this sheet
#' @param df Data frame object 

write_site_level_sheet <- function(wb,schema,df) {
  #Is this always true??
  fields<-unlist(schema$fields)[-c(1:4)]
  #Filter  out this indicator
  df_indicator<- df %>% 
    dplyr::filter(match_code %in% fields) %>%
    na.omit()
  if (nrow(df_indicator) > 0){
    #Create the OU level summary
    sums<- df_indicator %>% dplyr::group_by(match_code) %>%
      dplyr::summarise(value=sum(value,na.rm = TRUE)) %>%
      dplyr::mutate(match_code=factor(match_code,levels = fields)) %>%
      tidyr::spread(match_code,value,drop=FALSE)
    
    openxlsx::writeData(wb,sheet=schema$sheet_name,sums,xy=c(5,4),colNames=F,keepNA=F)
    
    df_indicator<-df_indicator %>% 
      dplyr::mutate(match_code=factor(match_code,levels = fields)) %>%
      tidyr::spread(match_code,value,drop=FALSE)
    openxlsx::writeData(wb,sheet=schema$sheet_name,df_indicator,xy=c(2,7),colNames=F,keepNA=F)
    
    inactiveFormula<-paste0("IF(AND(",schema$sheet_name,"!$B",7:((NROW(df_indicator)+6)*3),"<>\"\",INDEX(SiteList!$B:$B,MATCH(",schema$sheet_name,"!$B",7:(NROW(df_indicator)+6),",SiteList,0)+1)=1),\"!!\",\"\")")
    openxlsx::writeFormula(wb,schema$sheet_name,inactiveFormula,xy=c(1,7))
    openxlsx::dataValidation(wb,schema$sheet_name,cols=2,rows=7:1048576,"list",value="SiteList")
    openxlsx::dataValidation(wb,schema$sheet_name,cols=3,rows=7:1048576,"list",value="MechList")
    openxlsx::dataValidation(wb,schema$sheet_name,cols=4,rows=7:1048576,"list",value="DSDTA")
  }
  
  
}

#' @export
#' @title export_site_level_tool(d)
#'
#' @description Validates the layout of all relevant sheets in a data pack workbook
#' @param d Object returned from the site level distribution function

export_site_level_tool <- function(d) {
  if (d$wb_info$wb_type == "NORMAL") {
    template_name = "SiteLevelReview_TEMPLATE.xlsx"
  } else if (d$wb_info$wb_type == "HTS") {
    template_name = "SiteLevelReview_HTS_TEMPLATE.xlsx"
  }
  template_path <- paste0(d$wb_info$support_files_path, template_name)
  
  output_file_path <- paste0(
    dirname(d$wb_info$wb_path),
    "/SiteLevelReview_",
    d$wb_info$wb_type,
    "_",
    d$wb_info$ou_name,
    "_",
    format(Sys.time(), "%Y%m%d%H%M%S"),
    ".xlsx"
  )
  #Create the concatenated PSNU > OU_Name (UID) string
  d$sites$name_full <-
    paste0(d$sites$psnu_name,
           " > ",
           d$sites$name,
           " ( ",
           d$sites$organisationunituid,
           " )")
  wb <- openxlsx::loadWorkbook(file = template_path)
  
  #Fill in the Homepage details
  #TODO Do this from the schema
  openxlsx::writeData(
    wb,
    "Home",
    d$wb_info$ou_name,
    xy = c(15, 1),
    colNames = F,
    keepNA = F
  )
  #OU UID
  openxlsx::writeData(
    wb,
    "Home",
    d$wb_info$ou_uid,
    xy = c(15, 4),
    colNames = F,
    keepNA = F
  )
  #OU
  openxlsx::writeData(
    wb,
    "Home",
    d$wb_info$wb_type,
    xy = c(15, 3),
    colNames = F,
    keepNA = F
  )
  openxlsx::writeData(
    wb,
    "SiteList",
    d$sites$name_full,
    xy = c(1, 2),
    colNames = F,
    keepNA = F
  )
  openxlsx::writeData(
    wb,
    "Mechs",
    d$mechanisms$mechanism,
    xy = c(1, 2),
    colNames = F,
    keepNA = F
  )

  if (d$wb_info$wb_type == "HTS") {
    schemas <- datapackimporter::hts_site_schema
  }
  if (d$wb_info$wb_type == "NORMAL") {
    schemas <- datapackimporter::main_site_schema
  }
  
  #Munge the data a bit to get it into shape
  df <- d$data %>% dplyr::mutate(match_code = gsub("_dsd$", "", DataPackCode)) %>%
    dplyr::mutate(match_code = gsub("_dsd$", "", DataPackCode)) %>%
    dplyr::left_join(d$mechanisms, by = "attributeoptioncombo") %>%
    dplyr::left_join(d$sites, by = c("orgunit" = "organisationunituid")) %>%
    dplyr::select(name = name_full, mechanism, supportType, match_code, value) %>%
    dplyr::group_by(name, mechanism, supportType, match_code) %>%
    dplyr::summarise(value = sum(value, na.rm = TRUE))
    #Duplicates were noted here, but I think this should not have to be done
    #At this point. 
  
  for (i in 1:length(schemas$schema)) {
    schema <- schemas$schema[[i]]
    write_site_level_sheet(wb = wb,
                           schema = schema,
                           df = df)
  }
  openxlsx::saveWorkbook(wb = wb,
                         file = output_file_path,
                         overwrite = TRUE)
  print(paste0("Successfully saved output to ",output_file_path))
}
