library(e1071)
library(ROCR)

source('featurefiltering.R');
source('svmCV.R')

timestamp();

#set.seed(10);

DoRegression = TRUE;
svmCostList = c(0.3, 1, 3, 10, 30, 100);
featureCountList = seq(from=2800, to=1500, by=-50); 

# Set -1 for jackknife
nFolds = -1

balancing = "_SMOTED";
fScheme   = "_comb";

# File names #
fileNameSuffix = paste(fScheme, balancing, ".rds", sep = "");

rankedFeaturesFile = "rankedFeatures.rds" 
featureFile        = paste("featurized"    , fileNameSuffix, sep = "");
testFeatureFile    = paste("testFeaturized", fScheme,".rds", sep = "");
outFile            = paste("out", fScheme, balancing, ".csv", sep = "");

cat(as.character(Sys.time()),">> Reading training set features from", featureFile, "...\n");
features = readRDS(featureFile);
cat(as.character(Sys.time()),">> Done\n");

cat(as.character(Sys.time()),">> Reading test set features from", testFeatureFile, "...\n");
testFeatures = readRDS(testFeatureFile);
cat(as.character(Sys.time()),">> Done\n");

cat(as.character(Sys.time()),">> Reading feature ranking from", rankedFeaturesFile, "...\n");
rankedFeatures = readRDS(rankedFeaturesFile);
cat(as.character(Sys.time()),">> Done\n");

# jackknife
if (nFolds < 0) {
  nFolds = length(features[,1])
}

# random shuffle of features
features <- features[sample(nrow(features)),]

bestPerf = NULL;
bestParams = NULL;
accData = NULL;

cat(as.character(Sys.time()),">> Entering cross validation. Folds = ", nFolds, " ...\n");

# Reduce the feature vectors to the max size that we will be testing.
# This way the filtering cost in the loop below will be reduced.
features = featurefiltering(features, rankedFeatures, max(featureCountList));

# For regression study, we need to 'unfactor' the dependent var.
#
if (DoRegression) {
  
  # Cis-Golgi becomes 1 and Trans-Golgi becomes 2.
  # But we want Cis-Golgi (positive class) to be 1 and Trans-Golgi to be 0
  features$protection = 2 - as.numeric(features$protection);
}

for (maxFeatureCount in featureCountList) 
{
  trainingSet = featurefiltering(features, rankedFeatures, maxFeatureCount);

  for (svmC in svmCostList) 
  {
    perf = svmCV(protection ~ ., trainingSet, svmCost = svmC, cross = nFolds);
    if (DoRegression) {
      cat(maxFeatureCount, ",", svmC, ",", perf$auc,  ",",  perf$threshold, ",", perf$acc, ",", perf$spec, ",", perf$sens, ",", perf$mcc);
      accData = rbind(accData, c(maxFeatureCount, svmC, perf$auc, perf$threshold, perf$acc, perf$spec, perf$sens, perf$mcc));
    } else {

      cat(maxFeatureCount, ",", svmC, ",", perf$acc, ",", perf$sens, ",", perf$spec, ",", perf$mcc);
      accData = rbind(accData, c(maxFeatureCount, svmC, perf$acc, perf$sens, perf$spec, perf$mcc));
    }
    
    #write.table(accData, outFile,col.names=FALSE,row.names=FALSE,append=TRUE,sep=",");
    
    if (is.null(bestPerf) || bestPerf$acc < perf$acc) {
      bestPerf = perf;
      bestParams = list(
        "maxFeatureCount" = maxFeatureCount,
        "svmC" = svmC
      )
      cat(",<-- BEST");
    }
    
    cat("\n");
  }
}

cat("Best Result for <nF, C> = ", bestParams$maxFeatureCount, bestParams$svmC, "\n");
if (DoRegression) {
  cat("AUCROC                : ", bestPerf$auc, "\n");
  cat("Threshold             : ", bestPerf$threshold, "\n");
  # For regression we set Cis-Golgi to 1. So, sens is accuracy of Cis-Golgi
  # Let's swap the sens and spec
  temp = bestPerf$sens;
  bestPerf$sens = bestPerf$spec;
  bestPerf$spec = temp;
}

cat("Accuracy (Overall)    : ", bestPerf$acc, "\n");
cat("Accuracy (Trans-Golgi): ", bestPerf$sens, "\n");
cat("Accuracy (Cis-Golgi)  : ", bestPerf$spec, "\n");
cat("MCC                   : ", bestPerf$mcc, "\n");
bestaccData = NULL;
{
bestaccData = rbind(bestaccData, c("Jackknife Regression",bestParams$maxFeatureCount, bestParams$svmC, bestPerf$aucc, bestPerf$threshold, bestPerf$acc, bestPerf$sens, bestPerf$spec, bestPerf$mcc));
write.table(bestaccData,outFile,col.names=FALSE, row.names = FALSE, append = TRUE, sep = ",");
}