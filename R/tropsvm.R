#' Tropical Support Vector Machines
#'
#' Fit a discriminative two-class classifier via linear programming defined by the tropical
#' hyperplane which maximizes the minimum tropical distance from data points
#' to itself in order to separate the data points into sectors (half-spaces)
#' in the tropical projective torus.
#'
#' @importFrom parallel parLapply
#' @importFrom parallel makeCluster
#' @importFrom parallel setDefaultCluster
#' @importFrom parallel clusterExport
#' @importFrom parallel stopCluster
#' @importFrom RcppAlgos comboGeneral
#' @importFrom Rfast eachrow
#' @importFrom Rfast rowMaxs
#' @importFrom Rfast colMins
#' @importFrom lpSolve lp
#'
#' @param x a data matrix, of dimension nobs x nvars; each row is an observation vector.
#' @param y a response vector with one label for each row/component of x.
#' @param auto.assignment a logical value indicating if to provide an \code{assignment} by user.
#' If \code{FALSE}, an input is needed from the user, otherwise the function automatically
#' finds a good assignment.(default: FALSE)
#' @param accuracy a logival value indicating if return accuracy on test data and test label
#' \code{newx} and \code{newy} only. Note that if \code{TRUE}, the test data and test label
#' \code{newx} and \code{newy} should be provided. Users are more recommended to use its
#' default value as testing by prediction can be done via \code{predict.tropsvm}
#' more formally. (default: FALSE)
#' @param assignment a numeric vector indicating the sectors of tropical hyperplane that the
#' data will be assigned to. The first and third elements in the \code{assignment} are the coordinates of
#' an observed point in data matrix \code{x} believed from the first category where the maximum and second maximum
#' of the vector addition between the fitted optimal tropical hyperplane and the point itelf are achieved.
#' The meanings for the second and the fourth element in the \code{assignment} are the same
#' but for the points in the second category. Namely, the first and second values in the \code{assignment}
#' are the indices of sectors where the two point cloud will be assigned. Not needed when \code{auto.assignment = TRUE}. (default: NULL)
#' @param ind a numeric value or a numeric vector ranging from 1 to 70 indicating which classification method
#' will be used. There are 70 different classification methods. The different classification methods are proposed to resolve
#' the issue when points fall on the intersections of sectors. Users can have personal choices if better knowledge is assumed. (default: 1)
#' @param newx the same as "x" but only needed in \code{cv.tropsvm}, which is used as validation data. (default: \code{NULL})
#' @param newy the same as "y" but only needed in \code{cv.tropsvm}, which is used as validation labels (default: \code{NULL})
#'
#' @return An object with S3 class \code{"tropsvm"}.
#' \item{coef}{The vector of the fitted optimal tropical hyperplane}
#' \item{assignment}{The user-input \code{assignment}}
#' \item{method index}{The user-input \code{ind}}
#' \item{levels}{The name of each category, consistent with categories in \code{y}}
#'
#' @author Houjie Wang and Kaizhang Wang
#' Maintainer: Houjie Wang \email{whj666@@uw.edu}
#'
#' @references Tang, X., Wang, H. and Yoshida, R. (2020)
#' \emph{Tropical Support Vector Machine and its Applications to Phylogenomics}
#' \url{https://arxiv.org/pdf/2003.00677.pdf}
#'
#' @seealso \code{predict}, \code{coef} and the \code{cv.tropsvm} function.
#'
#' @keywords Tropical Geometry, Supervised Learning, Non-Euclidean Data
#'
#' @examples
#'
#' # data generation
#' library(Rfast)
#' e <- 100; n = 100; N = 100; s = 10
#' x <- rbind(rmvnorm(n, mu = c(5, -5, rep(0, e-2)), sigma = diag(s, e)),
#'           rmvnorm(n, mu = c(-5, 5, rep(0, e-2)), sigma = diag(s, e)))
#' y <- as.factor(c(rep(1, n), rep(2, n)))
#' newx <- rbind(rmvnorm(N, mu = c(5, -5, rep(0, e-2)), sigma = diag(s, e)),
#'              rmvnorm(N, mu = c(-5, 5, rep(0, e-2)), sigma = diag(s, e)))
#' newy <- as.factor(rep(c(1, 2), each = N))
#'
#' # train the tropical svm
#' tropsvm_fit <- tropsvm(x, y, auto.assignment = TRUE, ind = 1)
#'
#' coef(tropsvm_fit)
#'
#' # test with new data
#' pred <- predict(tropsvm_fit , newx, newy)
#'
#' # check with accuracy
#' table(pred, newy)
#'
#' # compute testing accuracy
#' sum(predict(tropsvm_fit , newx, newy) == newy)/length(newy)
#'
#' @export
#' @export tropsvm
tropsvm <- function(x, y, auto.assignment = FALSE, accuracy = FALSE, assignment = NULL, ind = NULL, newx = NULL, newy = NULL){
  classes <- unique(y)
  reorder_ind <- c(which(y == classes[1]), which(y == classes[2]))
  label <- y[reorder_ind]
  data <- x[reorder_ind, ]
  n1 <- sum(label == classes[1])
  n2 <- sum(label == classes[2])
  n <- n1 + n2

  if (auto.assignment){
    assignment <- assignment_finder(x[1: n1, ], x[-c(1: n1), ])[1, ]
  }
  names(assignment) = c("ip", "iq", "jp", "jq")
  ip <- assignment[1]; jp <- assignment[3]; iq <- assignment[2]; jq <- assignment[4]
  f.obj <- c(1, rep(0, 4), c(rep(-1, n1), rep(-1, n1), rep(-1, n1), rep(-1, n1), rep(-1, n2),
                             rep(-1, n2), rep(-1, n2), rep(-1, n2)))
  f.conp <- rbind(cbind(rep(1, n1), rep(-1, n1), rep(1, n1), rep(0, n1), rep(0, n1)),
                  cbind(rep(0, n1), rep(-1, n1), rep(1, n1), rep(0, n1), rep(0, n1)),
                  cbind(rep(0, n1), rep(0, n1), rep(-1, n1), rep(1, n1), rep(0, n1)),
                  cbind(rep(0, n1), rep(0, n1), rep(-1, n1), rep(0, n1), rep(1, n1)))
  f.conq <- rbind(cbind(rep(1, n2), rep(0, n2), rep(0, n2), rep(-1, n2), rep(1, n2)),
                  cbind(rep(0, n2), rep(0, n2), rep(0, n2), rep(-1, n2), rep(1, n2)),
                  cbind(rep(0, n2), rep(1, n2), rep(0, n2), rep(0, n2), rep(-1, n2)),
                  cbind(rep(0, n2), rep(0, n2), rep(1, n2), rep(0, n2), rep(-1, n2)))
  f.con <- cbind(rbind(f.conp, f.conq), diag(-1, nrow = 4*n, ncol = 4*n))
  f.dir <- rep("<=", n)
  f.rhs = c(rep(data[1: n1, ip] - data[1: n1, jp], 2),
            data[1: n1, jp] - data[1: n1, iq],
            data[1: n1, jp] - data[1: n1, jq],
            rep(data[-c(1: n1), iq] - data[-c(1: n1), jq], 2),
            data[-c(1: n1), jq] - data[-c(1: n1), ip],
            data[-c(1: n1), jq] - data[-c(1: n1), jp])
  if (accuracy){
    P_base <- matrix(c(1, 0, 0, 0,
                       0, 1, 0, 0,
                       1, 1, 0, 0,
                       1, 1, 1, 1), ncol = 4, byrow = T);
    Q_base <- matrix(c(0, 0, 1, 0,
                       0, 0, 0, 1,
                       0, 0, 1, 1,
                       0, 0, 0, 0), ncol = 4, byrow = T);
    PQ_com <- matrix(c(1, 0, 1, 0,
                       1, 0, 0, 1,
                       0, 1, 1, 0,
                       0, 1, 0, 1,
                       1, 1, 1, 0,
                       1, 1, 0, 1,
                       1, 0, 1, 1,
                       0, 1, 1, 1), ncol = 4, byrow = T)
    colnames(PQ_com) <- c("ip", "jp", "iq", "jq")
    all_method_ind <- comboGeneral(8, 4)
    reorder_ind <- c(which(newy == classes[1]), which(newy == classes[2]))
    val_label <- newy[reorder_ind]
    val_data <- newx[reorder_ind, ]
    val_n1 <- sum(val_label == classes[1])
    omega <- rep(0, ncol(data))
    omega[c(ip, jp, iq, jq)] <- lp("max", f.obj, f.con, f.dir, f.rhs)$solution[2: 5]
    omega[-c(ip, jp, iq, jq)] <- colMins(-data[, -c(ip, jp, iq, jq)] + c(data[1: n1, jp] + omega[jp], data[-c(1: n1), jq] + omega[jq]), T)
    shifted_val_data <- eachrow(val_data, omega, "+")
    diff <- eachrow(t(shifted_val_data), rowMaxs(shifted_val_data, T), oper = "-")
    raw_classification <- lapply(lapply(seq_len(ncol(diff)), function(i) diff[, i]), function(x){which(abs(x) < 1e-10)})
    accuracy <- sapply(ind, function(l){
      P = rbind(P_base, PQ_com[all_method_ind[l, ], ]); Q = rbind(Q_base, PQ_com[-all_method_ind[l, ], ])
      sum(c(sapply(raw_classification[1: val_n1], function(x){
        v = c(ip, jp, iq, jq) %in% x;
        return(sum(colSums(t(P) == v) == ncol(P)))
      }), sapply(raw_classification[-c(1: val_n1)], function(x){
        v = c(ip, jp, iq, jq) %in% x;
        return(sum(colSums(t(Q) == v) == ncol(Q)))
      })))/length(raw_classification)
    })
    accuracy
  } else{
    omega <- rep(0, ncol(data))
    sol <- lp("max", f.obj, f.con, f.dir, f.rhs)
    omega[c(ip, jp, iq, jq)] <- sol$solution[2: 5]
    omega[-c(ip, jp, iq, jq)] <- colMins(-data[, -c(ip, jp, iq, jq)] + c(data[1: n1, jp] + omega[jp], data[-c(1: n1), jq] + omega[jq]), T)
    tropsvm.out <- list("coef" = omega,
                        "assignment" = assignment,
                        "method index" = ind,
                        "levels" = as.character(classes))
    class(tropsvm.out) <- "tropsvm"
    tropsvm.out
  }
}
