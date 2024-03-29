# import libraries
library(gbm)
library(ROSE)
library(caret)
library(MLmetrics)
library(ggplot2)
library(dplyr)
library(AUC)

#import dataset
df <- read.csv('training data.csv', sep = ";")

#set seed and index for the train/test
set.seed(1)
train.index <- sample(c(1:dim(df)[1]), dim(df)[1]*0.7)

## ----1 feature engineering-----------------------------------------------------------
#adding some more features
df_gbdt <- df %>% select(-user_id) %>%
  mutate(subscriber_friend_pct = subscriber_friend_cnt / friend_cnt,
         loved_pct = lovedTracks/songsListened,
         delta_songsListened_pct = delta_songsListened / songsListened,
         delta_lovedsongsListened_pct = delta_lovedTracks / delta_songsListened,
         delta_lovedTracks_pct = delta_lovedTracks / lovedTracks,
         delta_subscriber_pct = delta_subscriber_friend_cnt / subscriber_friend_cnt,
         friend_country_pct = friend_cnt / friend_country_cnt,
         delta_posts_pct = delta_posts / posts,
         delta_playlists_pct = delta_playlists / playlists,
         delta_shouts_pct = delta_shouts / shouts)

df_gbdt[is.na(df_gbdt)] <- 0
df_gbdt[mapply(is.infinite, df_gbdt)] <- 0

## ----2 data preparation-----------------------------------------------------------
#split into train/valid
train.df <- df_gbdt[train.index, ]
valid.df <- df_gbdt[-train.index, ]

#over/under sample train.df
df_balanced_both <- ovun.sample(adopter ~ ., data = train.df, method = "both", p=0.5, seed = 1)$data


# Seeing the accuracy of a dummy model
train_1 = 1 - sum(train.df$adopter)/length(train.df$adopter)
valid_1 = 1 - sum(valid.df$adopter)/length(valid.df$adopter)

paste0("Dummy classifier train accuracy: ", round(train_1,4))
paste0("Dummy classifier validation accuracy: ", round(valid_1,4))


# testing over / under sampling
# over and under sample
df_balanced_both <- ovun.sample(adopter ~ ., data = train.df, method = "both", p=0.5, seed = 1)$data

# under sample
df_balanced_under <- ovun.sample(adopter ~ ., data = train.df, 
                                   method = "under", N = sum(train.df$adopter), seed = 1)$data

# over sample
df_balanced_over <- ovun.sample(adopter ~ ., data = train.df, 
                                   method = "over", N = (nrow(train.df)-sum(train.df$adopter))*2, seed = 1)$data

#ROSE
df_balanced_rose <- ROSE(adopter ~ ., data = train.df, seed = 1)$data

#create models
gbdt_original = gbm(adopter ~ . ,data = train.df, distribution = "bernoulli", n.trees = 100)
gbdt_both = gbm(adopter ~ . ,data = df_balanced_both, distribution = "bernoulli", n.trees = 100)
gbdt_over = gbm(adopter ~ . ,data = df_balanced_over, distribution = "bernoulli", n.trees = 100)
gbdt_under = gbm(adopter ~ . ,data = df_balanced_under, distribution = "bernoulli", n.trees = 100)
gbdt_rose = gbm(adopter ~ . ,data = df_balanced_rose, distribution = "bernoulli", n.trees = 100)

#make predictions on unseen data
pred.gbdt.original <- predict(gbdt_original, newdata = valid.df, n.trees = 100, type = "response")
pred.gbdt.both <- predict(gbdt_both, newdata = valid.df, n.trees = 100, type = "response")
pred.gbdt.over <- predict(gbdt_over, newdata = valid.df, n.trees = 100, type = "response")
pred.gbdt.under <- predict(gbdt_under, newdata = valid.df, n.trees = 100, type = "response")
pred.gbdt.rose <- predict(gbdt_rose, newdata = valid.df, n.trees = 100, type = "response")

#AUC ROSE
roc.curve(valid.df$adopter, pred.gbdt.original)
roc.curve(valid.df$adopter, pred.gbdt.both)
roc.curve(valid.df$adopter, pred.gbdt.over)
roc.curve(valid.df$adopter, pred.gbdt.under)
roc.curve(valid.df$adopter, pred.gbdt.rose)



## ----3 parameter tuning-----------------------------------------------------------
ntrees= c(130,150,170)
interaction.depth = c(2,3,4)
shrinkage = c(0.05,0.1)
minnodes = c(15,20)

for (tree in ntrees){
  for (depth in interaction.depth) {
    for (shrink in shrinkage) {
      for (minnode in minnodes) {
        model_balanced = gbm(adopter ~ . , data = df_balanced_both,
                 distribution = "bernoulli", n.trees = tree, cv.folds = 5,
                 interaction.depth = depth , shrinkage = shrink, n.minobsinnode = minnode)
        pred_balanced = predict.gbm(object = model_balanced, newdata = valid.df, type= "response")
        r_balanced <- roc(pred_balanced, as.factor(valid.df$adopter))
        print(paste("Features:", tree, depth, shrink, minnode))
        print(paste0("AUC: ", round(auc(r_balanced),5)))
      }
    }
  }
}


## ----4 model creation-----------------------------------------------------------
ntrees = 160
depth = 3
shrink = 0.05
minobs = 20

# model
model_balanced = gbm(adopter ~ . , data = df_balanced_both,
                 distribution = "bernoulli", n.trees = ntrees, cv.folds = 5,
                 interaction.depth =depth , shrinkage = shrink, n.minobsinnode=5)

# predict validation
pred_balanced = predict.gbm(object = model_balanced, newdata = valid.df, type = "response")
r_balanced <- roc(pred_balanced, as.factor(valid.df$adopter))
acc_balanced <- mean(pred_binary_balanced == valid.df$adopter)

pred_train_balanced = predict.gbm(model_balanced, newdata = train.df, type = "response")

print(paste0("AUC: ", round(auc(r_balanced),4)))

## ----feature importance--------------------------------------------------
# inspecting most important variables
#balanced data
featimp_balanced <- summary.gbm(model_balanced, normalize = TRUE)
featimp_balanced

## ----5 determined decision boundary-----------------------------------------------------------
#testing for the balanced data set
thresholds = seq(0.7,0.8, 0.001)
train_pred = pred_train_balanced
test_pred = pred_balanced

train_acc = c()
train_f1 = c()
train_pred1 = c()
test_acc = c()
test_f1 = c()
test_pred1 = c()


for (p in thresholds) {
  train_pred_binary <- ifelse(train_pred >= p, 1, 0)
  test_pred_binary <- ifelse(test_pred >= p, 1, 0)
  
  test_acc = c(test_acc, Accuracy(y_pred = test_pred_binary, y_true = valid.df$adopter))
  test_f1 = c(test_f1, F1_Score(test_pred_binary, valid.df$adopter, positive = "1"))
  test_pred1 <- c(test_pred1, sum(test_pred_binary))
  
  train_acc = c(train_acc, Accuracy(y_pred = train_pred_binary, y_true = train.df$adopter))
  train_f1 = c(train_f1, F1_Score(train_pred_binary, train.df$adopter, positive = "1"))
  train_pred1 <- c(train_pred1, sum(train_pred_binary))
}

# code will break when the model doesn't predict any 1s
# when the code breaks, run the below

test_f1

# getting the index when f1 is max
nrow = which.max(test_f1)

paste0("Decision Boundary: ", round(thresholds[nrow],4))
paste0("Train accuracy: ", round(train_acc[nrow],4))
paste0("Train F1: ", round(train_f1[nrow],4))
paste0("Test accuracy: ", round(test_acc[nrow],4))
paste0("Test predicted 1s: ", round(test_pred1[nrow],4))
paste0("Test F1: ", round(test_f1[nrow],4))


## ----6 run on test data---------------------------------------------------
#read in test data
test.df <- read.csv("test data.csv", sep = ";")

#feature engineering on test data
test.df <- test.df %>%
  mutate(subscriber_friend_pct = subscriber_friend_cnt / friend_cnt,
         loved_pct = lovedTracks/songsListened,
         delta_songsListened_pct = delta_songsListened / songsListened,
         delta_lovedsongsListened_pct = delta_lovedTracks / delta_songsListened,
         delta_lovedTracks_pct = delta_lovedTracks / lovedTracks,
         delta_subscriber_pct = delta_subscriber_friend_cnt / subscriber_friend_cnt,
         friend_country_pct = friend_cnt / friend_country_cnt,
         delta_posts_pct = delta_posts / posts,
         delta_playlists_pct = delta_playlists / playlists,
         delta_shouts_pct = delta_shouts / shouts)

#predict for balanced model
test.pred = predict.gbm(object = model_balanced, newdata = test.df, type = "response")
test.pred_binary = ifelse(test.pred >= 0.773, 1, 0)

paste0("1s predicted: ", sum(test.pred_binary))
paste("% 1st predcited: ", sum(test.pred_binary)/length(test.pred))

gbdt_balanced <- data.frame(test.df$user_id, test.pred_binary)
colnames(gbdt_balanced) <- c("user_id", "Predictions")

readr::write_csv(x = gbdt_balanced,"20191014_SNP_GBDT_Balanced.csv")

