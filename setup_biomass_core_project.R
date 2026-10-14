# Bootstrap + run script for the LichenBiomassFullAI simulation.
#
# What this script does:
# 1) Defines project root and package repositories.
# 2) Ensures core setup packages are installed (SpaDES.project, terra).
# 3) Sanitizes environment variables to reduce PROJ/GDAL conflicts from Conda.
# 4) Runs a small terra projection smoke test before expensive setup steps.
# 5) Calls SpaDES.project::setupProject() to resolve modules/packages/paths.
# 6) Initializes and runs the simulation.

project_root <- normalizePath("g:/Home/Projects/LichenBiomassFullAI", winslash = "/", mustWork = FALSE)

# Repository priority: PredictiveEcology r-universe first, then CRAN fallback.
repo <- c(
  predictiveecology = "https://predictiveecology.r-universe.dev",
  CRAN = "https://cran.rstudio.com"
)

project_library <- file.path(project_root, "packages", "4.5")

# Install setup package if missing.
if (!requireNamespace("SpaDES.project", quietly = TRUE)) {
  install.packages("SpaDES.project", repos = repo, lib = project_library)
}

# Install spatial backend package if missing.
if (!requireNamespace("terra", quietly = TRUE)) {
  install.packages("terra", repos = repo, lib = project_library)
}

# Install spatial backend package if missing.
if (!requireNamespace("archive", quietly = TRUE)) {
  install.packages("archive", repos = repo, lib = project_library)
}

# Clear inherited GDAL/PROJ env vars first so Conda values do not persist.
# (These will be re-set explicitly to terra paths below.)
Sys.unsetenv("PROJ_LIB")
Sys.unsetenv("GDAL_DATA")

# # Remove obvious Conda entries from PATH for this R session.
# # This is a best-effort mitigation for PROJ/GDAL binary conflicts.
# path_parts <- strsplit(Sys.getenv("PATH"), .Platform$path.sep, fixed = TRUE)[[1]]
# keep <- !grepl("(?i)conda|miniconda|anaconda", path_parts, perl = TRUE)
# Sys.setenv(PATH = paste(path_parts[keep], collapse = .Platform$path.sep))

# # Hard-set PROJ/GDAL data directories to the terra package copy.
# terra_pkg <- find.package("terra")
# terra_proj <- normalizePath(file.path(terra_pkg, "proj"), winslash = "/", mustWork = TRUE)
# terra_gdal <- normalizePath(file.path(terra_pkg, "gdal"), winslash = "/", mustWork = TRUE)

# Sys.setenv(PROJ_LIB = terra_proj)
# Sys.setenv(GDAL_DATA = terra_gdal)

# # Guardrail: stop early if PROJ/GDAL still point to Conda paths.
# if (grepl("(?i)conda|miniconda|anaconda", Sys.getenv("PROJ_LIB"), perl = TRUE) ||
#     grepl("(?i)conda|miniconda|anaconda", Sys.getenv("GDAL_DATA"), perl = TRUE)) {
#   stop("Preflight failed: PROJ_LIB/GDAL_DATA still point to a Conda path")
# }

# library(terra)

# # Smoke test: if a simple reprojection fails here, fail fast with clear signal.
# smoke_rast <- terra::rast(ncols = 2, nrows = 2, xmin = -1, xmax = 1, ymin = -1, ymax = 1, crs = "EPSG:4326")
# smoke_proj <- try(terra::project(smoke_rast, "EPSG:3857"), silent = TRUE)
# if (inherits(smoke_proj, "try-error")) {
#   stop("terra::project() smoke test failed: ", as.character(smoke_proj))
# }
# if (is.na(terra::crs(smoke_proj))) {
#   stop("terra::project() smoke test failed: output CRS is NA")
# }

# Project setup: creates/validates paths, resolves modules, and installs deps.
out <- SpaDES.project::setupProject(
  name = "LichenBiomassFullAI",
  paths = list(
    projectPath = project_root,
    modulePath = file.path(project_root, "modules"),
    packagePath = file.path(project_root, "packages"),
    inputPath = file.path(project_root, "inputs"),
    outputPath = file.path(project_root, "outputs"),
    cachePath = file.path(project_root, "cache")
  ),
  modules = c(
    "PredictiveEcology/Biomass_speciesData@main",
    "PredictiveEcology/Biomass_borealDataPrep@main",
    #"PredictiveEcology/Biomass_speciesParameters@main",
    "PredictiveEcology/Biomass_core@main"
  ),
  params = list(
    .globals = list(
      sppEquivCol = 'LandR'
    )
    # Biomass_speciesData = list(
    #   vegLeadingProportion = 0.8
    # )
    # Biomass_speciesParameters = list(
    #   PSPdataTypes = c("BC", "AB", "ON", "NB", "QC", "NFI")
    # )
  ),
  times = list(start = 0, end = 10),
  options = list(
    repos = repo,
    # Force package resolution from configured repos instead of GitHub remotes.
    Require.noRemotes = TRUE
  ),
  updateRprofile = TRUE,
  useGit = FALSE,
  Restart = FALSE,
  objects = list(
    studyArea = {
      # create and use a random study area
      # Lambert Conformal Conic for Canada: this is used in NRCan's "KNN" products
      Biomass_corecrs <- "+proj=lcc +lat_1=49 +lat_2=77 +lat_0=0 +lon_0=-95 +x_0=0 +y_0=0 +datum=NAD83 +units=m +no_defs +ellps=GRS80"
      
      # Former location: near Prince Albert, Saskatchewan
      # centre <- terra::vect(cbind(-104.757, 55.68663), crs = "epsg:4326")
      # Current location: shifted farther northwest so the study area crosses ecodistrict boundaries
      centre <- terra::vect(cbind(-123.8500, 54.6500), crs = "epsg:4326")
      
      centre <- terra::project(centre, Biomass_corecrs)
      
      studyArea <- LandR::randomStudyArea(centre, size = 2e8, seed = 1234)
      # studyArea <- LandR::randomStudyArea(centre, size = 2e9, seed = 1235)
    },
    studyAreaLarge = terra::buffer(studyArea, width = 3e4)
  )
)

# Initialize and run simulation.
sim <- do.call(SpaDES.core::simInit, out)
sim <- SpaDES.core::spades(sim)
