library(readxl)
library(rlist)
library(jsonlite)
library(datimvalidation)
library(tidyr)

ProduceSchema <-
  function(row = 6,
           start_col = 3,
           end_col = 1000,
           sheet_name,
           sheet_path) {
    
    if (sheet_name == "Follow on Mech List") {
      
      foo <-
        list(
          sheet_name = "Follow on Mech List",
          row = 4,
          start_col = 3,
          end_col = 5,
          method ='skip',
          fields = as.list(c("Closing Out","Follow on","Notes")))
      
    } else if (sheet_name == 'Allocation by SNUxIM') {
      row=6
      start_col = 2
      end_col = 232
      sheet_name=sheet_name
      foo<-list(sheet_name=sheet_name,
                row=row,
                start_col = start_col,
                end_col = end_col,
                method = 'skip',
      fields = as.list(names(as.list(
        read_excel(
          path = sheet_path,
          sheet = sheet_name,
          range = cell_limits(c(row, start_col),
                              c(row, end_col)))))))
    } else if (sheet_name == "IMPATT Table") {
      row=6
      start_col = 3
      end_col = 6
      sheet_name=sheet_name
      foo<-list(sheet_name=sheet_name,
                row=row,
                start_col = start_col,
                end_col = end_col,
                method = 'impatt',
                fields = as.list(c("psnu","psnuuid","snu_priotization_fy19","plhiv_fy19")))
    } else {  foo <-
      list(
        sheet_name = sheet_name,
        row = row,
        start_col = start_col,
        end_col = end_col,
        method = 'standard',
        fields = as.list(names(as.list(
          read_excel(
            path = sheet_path,
            sheet = sheet_name,
            range = cell_limits(c(row, start_col),
                                c(row, end_col))
          )
        )))
      )
    #Remove any unnamed columns
    foo$fields <- foo$fields[!grepl("X_", foo$fields)]
    foo$end_col = start_col + length(foo$fields)-1
    
        }
    return(foo)
  }

produceSchemas <- function(sheet_path,mode) {
  
  sheets <- excel_sheets(sheet_path)
  #Exclude these two , as they are custom
  custom_sheets<-c("Home")
  sheets <-sheets[!(sheets %in% custom_sheets)]
  foo<-lapply(sheets,function(x) {ProduceSchema(sheet_name=x,sheet_path = sheet_path)})
  return(list(mode=mode,schema=foo))
}

produceSiteToolSchemas <- function(sheet_path,mode) {
  
  sheets <- excel_sheets(sheet_path)
  #Exclude these two , as they are custom
  custom_sheets<-c("SiteList","Mechs")
  sheets <-sheets[!(sheets %in% custom_sheets)]
  foo<-lapply(sheets,function(x) {ProduceSchema(sheet_name=x,sheet_path = sheet_path,start_col = 1)})
  return(list(mode=mode,schema=foo))
}


processMechs<-function() {
  
  url<-paste0(getOption("baseurl"),"api/sqlViews/fgUtV6e9YIX/data.csv")
  d<-read.csv(url,stringsAsFactors = FALSE)
  return(d[,c("code","uid")])
}


processDataElements<-function() {
  read.csv("data-raw/DataPackCodes.csv",stringsAsFactors = FALSE,na="") %>%
  dplyr::select(.,code=DataPackCode,combi=pd_2019_P) %>% 
    dplyr::filter(.,complete.cases(.))
  }

getOrganisationUnitGroups <- function() {
  url <-
    paste0(getOption("baseurl"),
           "api/organisationUnitGroups?format=json&paging=false")
  organisationUnitGroups <-
    fromJSON(content(GET(url), "text"), flatten = TRUE)
  organisationUnitGroups <- as.data.frame(organisationUnitGroups)
  names(organisationUnitGroups) <- c("siteTypeUID", "siteType")
  return(organisationUnitGroups)
}


siteToolSchema<-function(wb_path) {
  sheets <- excel_sheets(wb_path)
}

getSiteList <- function(siteType) {
            organisationUnitGroups <- getOrganisationUnitGroups()
            stUID<-organisationUnitGroups[organisationUnitGroups$siteType==siteType,][1]
            url<-paste0(getOption("baseurl"),"api/organisationUnitGroups/",stUID,"?fields=organisationUnits[id],id,name&format=json")
            resp<-fromJSON(content(GET(url),"text"), flatten=TRUE)
            resp<-as.data.frame(resp)
            names(resp)<-c("siteType","siteTypeUID","orgUnit")
            return(resp)
}


get_full_site_list <- function() {
  #Change this to grab the CSV file from the API
  source_file<-paste0(getOption("datapack_support_files"),"A flat view of OU to level 9.csv")

  psnu_levels <-
    paste0(getOption("baseurl"),
           "api/dataStore/dataSetAssignments/ous") %>%
    httr::GET() %>%
    httr::content(., "text") %>%
    jsonlite::fromJSON(., flatten = TRUE) %>%
    do.call(rbind.data.frame, .) %>%
    dplyr::select(name3, prioritization) %>%
    dplyr::mutate(name3 = as.character(name3)) %>%
    dplyr::filter(prioritization != 0)
  
  ous_list<-read.csv(source_file,stringsAsFactors = FALSE)
  ous_list<-ous_list %>% 
    dplyr::inner_join(psnu_levels,by=c("level3name" = "name3"))
  
  for (i in 1:nrow(ous_list)) {
    if (ous_list$prioritization[i] == 4) {
      ous_list$psnu_name[i] = ous_list$level4name[i]
    }
    if (ous_list$prioritization[i] == 5) {
      ous_list$psnu_name[i] = ous_list$level5name[i]
    }
    if (ous_list$prioritization[i] == 6) {
      ous_list$psnu_name[i] = ous_list$level6name[i]
    }
  }
  ous_list %>% 
    dplyr::select(organisationunituid,name,ou_uid=uidlevel3,ou_name=level3name,psnu_name)
}



##Procedural logic to generate the actual schemas
##PSNU HTS Template
sheet_path = "data-raw/MalawiCOP18DisaggTool_HTSv2018.02.10.xlsx"
mode="HTS"
hts_schema<-produceSchemas(sheet_path,mode)

##Normal PSNU template
sheet_path = "data-raw/MalawiCOP18DisaggToolv2018.02.10.xlsx"
mode="NORMAL"
main_schema<-produceSchemas(sheet_path,mode)

#Normal Site level  tools
sheet_path="data-raw/SiteLevelReview_TEMPLATE.xlsx"
mode="NORMAL_SITE"
main_site_schema<-produceSiteToolSchemas(sheet_path,mode)

#Normal HTS Site level  tool
sheet_path="data-raw/SiteLevelReview_HTS_TEMPLATE.xlsx"
mode="HTS_SITE"
hts_site_schema<-produceSiteToolSchemas(sheet_path,mode)

schemas<-list(hts=hts_schema,normal=main_schema)
names(schemas)<-c("hts","normal")

#List of mechanisms
mechs<-processMechs()
#List of data elements
des<-processDataElements()
#IMPATT option set
impatt<-fromJSON("data-raw/impatt_option_set.json")

datimvalidation::loadSecrets("/home/jason/.secrets/datim.json")
source("data-raw/transform_code_lists.R")
rCOP18deMapT<-generateCodeListT()%>% mapDataPackCodes()
rCOP18deMap<-generateCOP18deMap(rCOP18deMapT)


#MilitaryUnits
militaryUnits<-getSiteList("Military")

clusters <- function() {
  df<- read.csv("data-raw/COP18Clusters.csv",stringsAsFactors=F,header=T) %>%
    mutate(operatingUnitUID=case_when(operatingunit=="Botswana"~"l1KFEXKI4Dg"
                                      ,operatingunit=="Cameroon"~"bQQJe0cC1eD"
                                      ,operatingunit=="Haiti"~"JTypsdEUNPw"
                                      ,operatingunit=="Mozambique"~"h11OyvlPxpJ"
                                      ,operatingunit=="Namibia"~"FFVkaV9Zk1S"
                                      ,TRUE~""))
  return(df)
}

clusters<-clusters()
#Sites to exclude
sites_exclude<-c('fNH1Ny5vXI5', 'Tiqj6KDtx3p', 'BspXUn4c2i0', 'wnFyQ8gWVuP', 'b0WbjlNgwpg', 'Smw76afBRxh', 'TyDdI16aem2', 'u6UHEEYSsrY', 'ZHAEPwL6s87', 'oitze45vmuG', 'imQAg2FmqIi', 'JWb1FJrb6u0', 'oU9JrXHFBwo', 'ZvjmhaNkDJP', 'ph5hfp4TDYa', 'NDGAjm5He3s', 'S0wsB3mH7As', 'WKQumwV8vzz', 'aIl7B0aJZE7', 'EwvYCRwMaj2', 'Zj3QFD5LCN0', 'DWqxLhccQpN', 'FMA01mDjzg9', 'Wt4Ap0dVT0K', 'kTDYtuRlsRJ', 'B2aBYUFKEtP', 'eBMjxJa6Hyo', 'Jn8Dy8Kt8r6', 'BP8kSSf9mVh', 'uM7bKbyQMUb', 'xRNWRGhiL2x', 'CLsTOua0sYz', 'foN7Fc7qqd5', 'Pn5Egy0nEvw', 'ZU5YFwWSAM7', 'ahCpXE5nYKO', 'WQUnNhUravY', 'lSrgJWMVhKP', 'SWMW9b7WMMG', 'LdH3sTixu4G', 'PUWNeEDqKjG', 'kQLMdNG7tOr', 'qjxX1U1zOV9', 'un7KU5UBkTp', 'nMYhhbh463E', 'cugQdSJzIzf', 'Vgz3Af04heg', 'VXhW2lbMHeT', 'o1OrLbuDePL', 'gdWruPti7dW', 'kpLxWaoSWp5', 'GGNlHihWQLS', 'c78scqZGQPc', 'WXCDaZ8ldbb', 'DmpYVwgbt0k', 'kbLOPXlsHH4', 'KabE1XwF8CH', 'sk68oHctZOt', 'boqES0AhYHD', 'ecpaElyx1MZ', 'TDk0oLAqK6H', 'p3n96zLyWoP', 'hF8sLm9vE1U', 't5GdyeN9riy', 'Fu0wZlUnntH', 'TixiR1SsebU', 'u86Kfypb8DG', 'JJJOwYzvDZo', 'Dgi2sUBjGzO', 'e9eJh4Dn286', 'dV6akh4l1Ej', 'I93yMz1rjkQ', 'TVrtknExg0t', 'FL40UCPHJke', 'WxIBVamFcg0', 'BpLP6v9NeWX', 'D7uuBfToHfb', 'ItoS9FGQg24', 'M8Yb2Y9rgNe', 'tBcAME3DNk1', 'jBOH9BBbqEW', 'J9Nmumn9DRc', 'sEJ8peJ3Jz6', 'g0HJxd9XWMy', 'tLcy3vpV6LF', 'QITi8Rd6xV5', 'zrHn3k5oIAT', 'szenMEdV4sF', 'EzzYi29hyNF', 'RJWMt1CU1HW', 'JSmcOMrC6zZ', 'RQykElqy1HR', 'Ae8uPosEFeF', 'NEk0GiXI2SW', 'HSoAojlwB7Q', 'hRq9qYMyBE7', 'Rq9EVeiR0PU', 'OyDnBG2RCgS', 'q3WGbWcjdWf', 'aGQbouk9S3E', 'GMHwNlqPAzS', 'm6eYOfLPzmF', 'lAhBMeGXsvQ', 'zZXWPXydW2S', 'VGVbROfDHWh', 'bMtviLCfDub', 'ZCbh020F2TA', 'cVnfnV5N1w5', 'L6HMMjCf2em', 'U9YejzJibuv', 'ASSntKFP1Ns')

#Map of OUs and PSNUs
ous<-httr::GET(paste0(getOption("baseurl"),"api/organisationUnits?filter=level:eq:3&fields=id,name")) %>% 
  httr::content("text") %>% 
  jsonlite::fromJSON() %>%
  rlist::list.extract("organisationUnits") 

ou_prioritization_levels<-httr::GET(paste0(getOption("baseurl"),"api/dataStore/dataSetAssignments/ous")) %>% 
  httr::content("text") %>% 
  jsonlite::fromJSON() %>% 
    plyr::ldply(function(x) {data.frame(x,stringsAsFactors = FALSE)}) %>%
  dplyr::select(name=name3,prioritization) %>%
  distinct %>%
  inner_join(ous,by=c("name")) 

getOrgunitsAtLevel <- function(parent_id,level) {
  url<-paste0(getOption("baseurl"),"api/organisationUnits?filter=path:like:",parent_id,"&filter=level:eq:",level,"&fields=id,name&paging=false")
  
  httr::GET(url) %>%
    httr::content("text") %>% 
    jsonlite::fromJSON() %>%
    rlist::list.extract("organisationUnits") 
}

psnus<-mapply(getOrgunitsAtLevel,ou_prioritization_levels$id,ou_prioritization_levels$prioritization)

militaryUnits<-getSiteList("Military")

#Save the data to sysdata.Rda. Be sure to rebuild the package and commit after this!
devtools::use_data(hts_schema,main_schema,main_site_schema,hts_site_schema,mechs,des,impatt,rCOP18deMap,rCOP18deMapT,clusters, sites_exclude,psnus,militaryUnits,internal = TRUE,overwrite = TRUE)
