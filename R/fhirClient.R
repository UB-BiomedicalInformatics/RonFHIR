#' fhirClient
#'
#' Read and search only client in R for FHIR STU 3.
#' Based on \href{https://github.com/ewoutkramer/fhir-net-api}{the official HL7 FHIR .NET API.}
#'
#' @section Usage:
#' \preformatted{
#' client <- fhirClient$new(endpoint)
#'
#' client$read(location, summaryType = NULL)
#' client$search(resourceType, criteria = NULL, includes = NULL, pageSize = NULL, summaryType = NULL)
#' client$searchById(resourceType, id, includes = NULL, summaryType = NULL)
#' client$wholeSystemSearch(criteria = NULL, includes = NULL, pageSize = NULL, summaryType = NULL)
#' client$searchParams(params, resourceType = NULL)
#' client$continue(bundle)
#'
#' print(client)
#' }
#'
#' @section Arguments:
#' \describe{
#'   \item{client}{A \code{fhirClient} object.}
#'   \item{endpoint}{The URL of the server to connect to.}
#'   \item{resourceType}{The type of resource to search for.}
#'   \item{id}{The id of the Resource to search for.}
#'   \item{summaryType}{Whether to include only return a summary of the Resource(s).}
#'   \item{location}{The url of the Resource to fetch. This can be a Resource id url or a version-specific.}
#'   \item{criteria}{The search parameters to filter the Resources on. Each given string is a combined key/value pair (separated by '=').}
#'   \item{includes}{Paths to include in the search.}
#'   \item{pageSize}{Asks server to limit the number of entries per page returned.}
#'   \item{query}{A searchParams object containing the search parameters.}
#'   \item{bundle}{The bundle as received from the last response.}
#' }
#'
#' @section Details:
#' \code{$new()} Creates a new fhirClient using a given endpoint.
#' If the endpoint does not end with a slash (/), it will be added.
#'
#' \code{$read()} Fetches a typed Resource from a FHIR resource endpoint.
#'
#' \code{$search()} Search for Resources of a certain type that match the given criteria.
#'
#' \code{$searchById()} Search for Resources based on a Resource's id.
#'
#' \code{$wholeSystemSearch()} Search for Resources across the whole server that match the given criteria.
#'
#' \code{$searchByQuery()} Search for Resources based on a searchParams object.
#'
#' \code{$continue()} Uses the FHIR paging mechanism to go navigate around a series of paged result Bundles.
#'
#' \code{print(p)} or \code{p$print()} Shows which endpoint is configured.
#'
#' @importFrom R6 R6Class
#' @importFrom httr GET
#' @importFrom httr content
#' @importFrom httr http_error
#' @importFrom httr http_status
#' @importFrom httr accept_json
#' @importFrom jsonlite fromJSON
#' @importFrom jsonlite validate
#' @importFrom utils URLencode
#' @name fhirClient
#'
#' @examples
#' \dontrun{
#' # Setting up a fhirClient
#' client <- fhirClient$new("http://vonk.furore.com")
#' # Read
#' client$read("Patient/example")
#'
#' # Search
#' bundle <- client$search("Patient", c("name=Peter", "address-postalcode=3999"))
#'
#' while(!is.null(bundle)){
#'    # Do something useful
#'    bundle <- client$continue(bundle)
#' }
#' }
#'
NULL

#' @export
fhirClient <- R6Class("fhirClient",
                      public = list(
                        # Initializing the fhirClient
                        initialize = function(endpoint)
                          execInitialize(self, private, endpoint),

                        # Methods
                        read = function(location, summaryType = NULL)
                          execRead(self, private, location, summaryType),
                        search = function(resourceType, criteria = NULL, includes = NULL, pageSize = NULL, summaryType = NULL)
                          execSearch(self, private, resourceType, criteria, includes, pageSize, summaryType),
                        searchById = function(resourceType, id, includes = NULL, summaryType = NULL)
                          execSearchById(self, private, resourceType, id, includes, summaryType),
                        wholeSystemSearch = function(criteria = NULL, includes = NULL, pageSize = NULL, summaryType = NULL)
                          execWholeSystemSearch(self, private, criteria, includes, pageSize, summaryType),
                        searchByQuery = function(params, resourceType = NULL)
                          execSearchByQuery(self, private, params, resourceType),
                        qraphQL = function(query, location = NULL)
                          execGraphQL(self, private, query, location),
                        continue = function(bundle)
                          execContinue(self, private, bundle),
                        operation = function (resourceType = NULL, id = NULL, name, parameters = NULL) 
                          execOperation(self, private, resourceType, id, name, parameters),
                        update = function(resource)
                          execUpdate(self, private, resource),
                        print = function()
                          execPrint(self, private)
                      ),
                      private = list(
                        # Private variables
                        endpoint = NULL
                      )
)


execInitialize <- function(self, private, endpoint) {
  if(substr(endpoint, nchar(endpoint), nchar(endpoint)) != "/"){
    endpoint <- paste(endpoint, "/", sep="")
  }

  private$endpoint <- endpoint
  json <- getJSON(paste(endpoint, "metadata?_summary=true", sep = ""))
  meta <- fromJSON(json)

  tryCatch(meta$resourceType == "CapabilityStatement", error = function(e){stop("Could not connect to endpoint", call. = FALSE)})

  fhirVersion <- substr(meta$fhirVersion, 1, 1)
  if(fhirVersion != "3"){
    stop(paste("R on FHIR is not compatible with", fhirVersion, "only with STU 3"), call. = FALSE)
  }
}

execRead <- function(self, private, location, summaryType){
  url <- toReadURL(private, location, summaryType)
  getResource(url)
}

execGraphQL <- function(self, private, query, location){
  url <- toGraphQLURL(private, location, query)
  getResource(url)
}

execSearch <- function(self, private, resourceType, criteria, includes, pageSize, summaryType){
  url <- toSearchURL(private, resourceType, criteria, includes, pageSize, summaryType, NULL)
  getBundle(url)
}

execSearchById <- function(self, private, resourceType, id, includes, summaryType){
  criteria <- paste("_id=", id, sep = "")
  url <- toSearchURL(private, resourceType, criteria, includes, NULL, summaryType, NULL)
  getBundle(url)
}

execWholeSystemSearch <- function(self, private, criteria, includes, pageSize, summaryType){
  url <- toSearchURL(private, NULL, criteria, includes, pageSize, summaryType, NULL)
  getBundle(url)
}

execSearchByQuery <- function(self, private, query, resourceType){
  if(!("searchParams" %in% class(query))){
    stop("Parameter is not a valid searchParams object", call. = FALSE)
  }
  url <- toSearchURL(private, resourceType, NULL, NULL, NULL, NULL, query)
  getBundle(url)
}

execContinue <- function(self, private, bundle)
{
  tryCatch(bundle$resourceType == "Bundle", error = function(e){stop("Input is not recognized as a Bundle", call. = FALSE)})
  next_url <- bundle$link[bundle$link$relation == "next",]$url
  if(length(next_url) == 0)
  {
    return(NULL)
  }
  else
  {
    json <- getJSON(next_url)
    return(fromJSON(json))
  }
}

execOperation <- function(self, private, resourceType, id, name, parameters) 
{
  url <- toOperationURL(private, resourceType, id, name, parameters)
  getBundle(url)
}

execUpdate <- function(self, private, resource){
  putResource(self, private, resource)
}

execPrint <- function(self, private){
  cat(
    "Endpoint:", private$endpoint
  )
  invisible(self)
}
