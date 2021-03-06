% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/analysis.R
\name{panel_lfc}
\alias{panel_lfc}
\title{Calculates flux log-fold changes between in-panel and out-panel samples.}
\usage{
panel_lfc(v, map, extra = NULL)
}
\arguments{
\item{v}{A matrix of fluxes where rows denote samples across different
panels and columns denote fluxes.}

\item{map}{A map translating the row names of v to their specific panel.}

\item{extra}{Optional data.frame with as many rows as rows in v that contains
additional information about the fluxes that should be appended to the results.}
}
\value{
A data.table containing the log-fold changes for each flux and panel.
}
\description{
`panel_lfc` takes values for fluxes across different panels and calculates
the log-fold changes between the flux in a given target panel against all
all other panels, for all panels.
}
\examples{
 NULL

}

