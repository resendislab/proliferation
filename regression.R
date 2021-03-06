#  regression.R
#
#  Copyright 2016 Christian Diener <mail[at]cdiener.com>
#
#  MIT license. See LICENSE for more information.

library(prtools)

start_t <- proc.time()
registerDoMC(6)

cat("Reading data\n")
rdata <- fread("regprob.csv", header = T)
norm <- readRDS("norm_factor.rds")
join <- readRDS("join.rds")
cutoff <- 1
good <- join[(tcga_rnaseq * norm[1] + norm[2] - nci60_huex) ^ 2 < cutoff &
    (tcga_huex + norm[2] - join$nci60_huex) ^ 2 < cutoff, ensgene]
rates <- rdata$rates
rdata[, "rates" := NULL]
rdata <- as.matrix(rdata)[, good]

cat("Running 1st order regressor\n")

pred <- data.frame()
m <- data.frame()
folds <- length(rates)

mod1 <- cv.glmnet(rdata, rates, nfolds = folds, keep = T, parallel = T,
    grouped = FALSE, standardize = FALSE)
pred_train <- predict(mod1, rdata, s = "lambda.min")[, 1]
pred_test <- mod1$fit.preval[, which.min(mod1$cvm)]
pred <- rbind(pred, data.frame(truth = rates, pred = pred_train, set = "train",
    order = "1st"))
pred <- rbind(pred, data.frame(truth = rates, pred = pred_test,
    set = "validation", order = "1st"))
m <- rbind(m, data.frame(t(measures(rates, pred_train)), set = "train",
    order = "1st"))
m <- rbind(m, data.frame(t(measures(rates, pred_test)), set = "validation",
    order = "1st"))
nonzero <- abs(coef(mod1, s = "lambda.min")[-1]) > 0

cat("Running 2nd order regressor\n")

data2 <- inter(rdata[, nonzero])
mod2 <- cv.glmnet(data2, rates, nfolds = folds, keep = T, parallel = T,
    grouped = FALSE, standardize = FALSE)
pred_train <- predict(mod2, data2, s = "lambda.min")[, 1]
pred_test <- mod2$fit.preval[, which.min(mod2$cvm)]
pred <- rbind(pred, data.frame(truth = rates, pred = pred_train, set = "train",
    order = "2nd"))
pred <- rbind(pred, data.frame(truth = rates, pred = pred_test,
    set = "validation", order = "2nd"))
m <- rbind(m, data.frame(t(measures(rates, pred_train)), set = "train",
    order = "2nd"))
m <- rbind(m, data.frame(t(measures(rates, pred_test)), set = "validation",
    order = "2nd"))

cat("Running 1st + 2nd order regressor\n")

data12 <- cbind(rdata[, nonzero], data2)
mod3 <- cv.glmnet(data12, rates, nfolds = folds, keep = T, parallel = T,
    grouped = FALSE, standardize = FALSE)
pred_train <- predict(mod3, data12, s = "lambda.min")[, 1]
pred_test <- mod3$fit.preval[, which.min(mod3$cvm)]
pred <- rbind(pred, data.frame(truth = rates, pred = pred_train, set = "train",
    order = "1st and 2nd"))
pred <- rbind(pred, data.frame(truth = rates, pred = pred_test,
    set = "validation", order = "1st and 2nd"))
m <- rbind(m, data.frame(t(measures(rates, pred_train)), set = "train",
    order = "1st and 2nd"))
m <- rbind(m, data.frame(t(measures(rates, pred_test)), set = "validation",
    order = "1st and 2nd"))

cat("Reducing model by cutoff\n")
cf <- as.numeric(coef(mod2, s = "lambda.min"))[-1]
names(cf) <- rownames(coef(mod2))[-1]
nonzero <- abs(cf) > quantile(abs(cf[abs(cf) > 0]), 0.25)
data_red <- data2[, nonzero]
mod <- cv.glmnet(data_red, rates, nfolds = folds, keep = T,
    grouped = FALSE, standardize = FALSE)
pred_train <- predict(mod, data_red, s = "lambda.min")[, 1]
pred_test <- mod$fit.preval[, which.min(mod$cvm)]
pred <- rbind(pred, data.frame(truth = rates, pred = pred_train, set = "train",
    order = "2nd + cutoff"))
pred <- rbind(pred, data.frame(truth = rates, pred = pred_test,
    set = "validation", order = "2nd + cutoff"))
m <- rbind(m, data.frame(t(measures(rates, pred_train)), set = "train",
    order = "2nd + cutoff"))
m <- rbind(m, data.frame(t(measures(rates, pred_test)), set = "validation",
    order = "2nd + cutoff"))

genes <- do.call(rbind, strsplit(colnames(data_red), "x"))
colnames(genes) <- c("gene1", "gene2")
write.csv(data.frame(genes, coef = cf[nonzero]), "best_interactions.csv")

#Assemble predictions
pred_plot <- ggplot(pred, aes(x = truth, y = pred, col = order)) +
    geom_abline() + geom_point() + facet_grid(set ~ order) + theme_bw() +
    xlab("measured proliferation rate [1/h]") +
    ylab("predicted proliferation rate [1/h]") +
    theme(legend.position = "none")
ggsave("images/model.png", pred_plot, width = 185, height = 90, units = "mm",
    dpi = 300)

cat("Predicting...\n")
tcga <- readRDS("tcga.rds")
map <- genemap
setkey(map, ensgene)

symbs <- cbind(map[genes[, 1], symbol], map[genes[, 2], symbol])
huex_ex <- tcga$huex$assay[unique(as.vector(symbs)), ]
huex_ex <- huex_ex + norm[2]
huex_red <- t(huex_ex[symbs[, 1], ] * huex_ex[symbs[, 2], ])
colnames(huex_red) <- paste0(symbs[, 1], "x", symbs[, 2])
rates_huex <- predict(mod, huex_red, s = "lambda.min")[, 1]
controls <- is.na(tcga$huex$samples$tumor)
rates_huex <- rates_huex[!controls]

rna_ex <- tcga$rnaseq$counts[unique(as.vector(genes)), ]
rna_ex <- log(rna_ex + 1, 2)
rna_ex <- rna_ex * norm[1] + norm[2]
rna_red <- t(rna_ex[genes[, 1], ] * rna_ex[genes[, 2], ])
colnames(rna_red) <- paste0(genes[, 1], "x", genes[, 2])
rates_rna <- predict(mod, rna_red, s = "lambda.min")[, 1]

pred <- data.table(
    patient_barcode = c(tcga$rnaseq$samples$patient_barcode,
                        tcga$huex$samples$patient_barcode[!controls]),
    panel = c(tcga$rnaseq$samples$panel, tcga$huex$samples$panel[!controls]),
    rates = c(rates_rna, rates_huex),
    tumor = c(tcga$rnaseq$samples$tumor, tcga$huex$samples$tumor[!controls])
    )

comb <- merge(pred, tcga$clinical, by = c("patient_barcode", "panel"))

saveRDS(comb, "combined.rds")
readr::write_csv(pred, "pred_rates.csv")

write("----------\nUsed time:\n----------", file = "")
print(proc.time() - start_t)
