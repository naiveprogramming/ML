rm(list=ls())
library(rpart)
library(dplyr)
library(rpart)
library(rpart.plot)
library(ROCR)
library(glmnet)
library(imbalance)
library(caret)
library(ggplot2)
library(randomForest)
library(scatterplot3d)
options(scipen = 999)

train <- read.table('C:/Users/julie/OneDrive/Escritorio/Di Tella/Modulo 2/Machine Learning/TP/datosTP2020/train.csv', header = T, sep =',', dec = '.')

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# EXPLORANDO EL DATA SET ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
head(train)

# ¿Cuántas observaciones y features tenemos?
dim(train) # 33008 x 312

# Exploramos un poco, Cómo es la estructura de los datos?:
head(str(train),312)
summary(train)

# Que proporcion tenemos de cada tipo de churn:
prop.table(table(train$TARGET)) # Data set desbalanceado.

summary(train)

table(is.na(train))

# Ponemos TARGET como factor:
train$TARGET <- as.factor(ifelse(train$TARGET == 0, "no", "yes"))

# GRAFICAMOS ALGUNAS RELACIONES ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ggplot(train) +
  geom_bar(aes(x = TARGET, fill = TARGET)) +
  ggtitle("Cantidad de usuarios por clase") +
  xlab("Churn vs. No Churn") +
  ylab("# de usuarios") + 
  scale_fill_manual(values=c("#E69F00", "darkgrey"))

vector_nombre_saldo <- c(colnames(train[startsWith(colnames(train), prefix = "saldo")]))

x11();
boxplot(train[,vector_nombre_saldo])
dev.off()

### Scaterplots en una matriz
x11();

# Para las vector_nombre_saldo
plot(train[vector_nombre_saldo],pch='.') # Scatter plot de las variables con saldo.
# No se ven interacciones o relaciones lineales significativas en los datos. 
# No se ve ninguna tendencia especial.

plot(train[vector_nombre_saldo],pch='.')

dev.off()

par(mfcol = c(2, 5)) 
for (k in 1:5) {
  j0 <- vector_nombre_saldo[k]
  br0 <- seq(min(train[vector_nombre_saldo[k]]), max(train[vector_nombre_saldo[k]]), le = 11)
  x0 <- seq(min(train[vector_nombre_saldo[k]]), max(train[vector_nombre_saldo[k]]), le = 50)
  for (i in 1:2) {
    i0 <- levels(train$churn)[i]
    x <- train[train$churn == i0, j0]
    hist(x, br = br0, proba = T, col = grey(0.8), main = i0,
         xlab = j0)
    lines(x0, dnorm(x0, mean(x), sd(x)), col = "red", lwd = 2)}
}
# Histogramas para cada una de las variables enteras contra churn. 
# ESTO ES CLAVE!!!

dev.off()
# INGENIERIA DE ATRIBUTOS ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#train_new <- train %>% filter(TARGET == 1)
#train_new <- train %>% filter(var36 != 99)
#train_new2 <- train %>% filter(var36 == 99)

#train_oversampling <- rbind(train, train_new) # Hacemos oversampling

# Eliminamos los NA:
train <- train %>%
  filter(complete.cases(.))

# Dado que la variable var36 tiene mas del 40% como NaN y se han imputado como el numero 99, 
# cambiaremos ese numero por una media ponderada:

ggplot(train) +
  geom_histogram(aes(x = var36, fill = TARGET)) +
  ggtitle("Distribucion de la variable var36") +
  xlab("Valores") +
  ylab("# de usuarios") +
  scale_fill_manual(values=c("#E69F00", "darkgrey"))

var36_99 <- sample(c(0,1,2,3), size = nrow(train %>% filter(var36 == 99)), 
       prob = c(0.0099, 0.3255, 0.1932, 0.4714), replace = TRUE)

# Chequeamos que nos queden bien los %. Las prob salen de train %>% filter(var36 != 99).
train$var36 <- ifelse(train$var36 == 99, var36_99 , train$var36)
prop.table(table(train$var36)) 

# Eliminamos todas aquellas variables con mas del 95% de las observaciones con el mismo valor.
for (i in 1:(ncol(train)-1)){
  max_elem <- train[i] == as.numeric(names(which.max(table(train[i]))))
  total_cases <- sum(max_elem, na.rm = TRUE)
  
  if (total_cases/nrow(train) > 0.95){
    train[i] = NULL
  }
}
max_elem <- NULL

# Vemos las variables que pasaron el filtro:
str(train)
summary(train)

# Eliminamos la variable ID ya que no tiene poder explicativo:
train$ID <- NULL

# Vemos que sucede con la variable age, en la que creemos que se imputo el valor 23 a todos los NA:
# UNDERSAMPLING en la variable age.
hist(train$age, breaks = 40)
prop.table(table(train$age == 23, train$TARGET))

train_borrador <- train %>% filter(age == 23 & TARGET == 0)
id = sample(nrow(train_borrador), 0.75*nrow(train_borrador))
train_borrador <- train_borrador[id, ]

train_piola <- train %>% filter(age != 23)
train_avion <- train %>% filter(age == 23 & TARGET == 1)

train <- rbind(train_borrador, train_piola, train_avion)

# Cambiamos la clase de las variables:
vector_nombre_ind <- c(colnames(train[startsWith(colnames(train), prefix = "ind")]))

for (i in 1:length(vector_nombre_ind)){
  train[[vector_nombre_ind[i]]] <- as.factor(train[,vector_nombre_ind[i]])
}

# Le aplicamos logaritmo a varibales para reescalarlas:
vector_nombre_imp <- c(colnames(train[startsWith(colnames(train), prefix = "imp")]))

for (i in 1:length(vector_nombre_imp)){
  train[[vector_nombre_imp[i]]] <- log(train[,vector_nombre_imp[i]]+1)
}

train$var38 <- log(train$var38)

# Dividimos en entrenamiento y testeo ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
set.seed(777)
samp <- sample(c(0.2*nrow(train)))

train <- train[-samp,]

test <- train[samp,]

# Recordemos que la libreria glmnet consume matrices, no dataframes
matrix_train = model.matrix( ~ . - 1, train)
matrix_test = model.matrix(~. -1 , test)

x_train <- as.matrix(matrix_train[,-186]) # 186 es la variable TARGET. 
y_train = as.matrix(matrix_train[,186]) # 0/1 flag.

x_test <- as.matrix(matrix_test[,-186])
y_test<- as.matrix(matrix_test[,186])

######### REGRESION LOGISTICA  #######################
######################################################

# Entrenamos modelo de regresion logistica
rlogit.churn = glm(TARGET ~.,  data = train, family = binomial(link = "logit"))

# Ver resumen del modelo
options(scipen = 999)
summary(rlogit.churn) # Nos da info sobre la importancia de las variables.
# Complemento al analisis exploratorio.

######### REGRESION LOGISTICA SIN REGULARIZACION #######
######################################################

# Entrenamos el modelo Regresion Logistica (LASSO) - Sin Regularizacion
lasso.sin.reg = glmnet(x = x_train , 
                       y = y_train,
                       family = 'binomial', 
                       alpha = 1 , 
                       lambda = 0, # sin regularizacion
                       standardize = TRUE)

summary(lasso.sin.reg)

# Predicciones sobre datos TRAIN 
pred_tr = predict(lasso.sin.reg, s = 0 , newx = x_train, type = 'response')

# Predicciones sobre datos TEST 
pred = predict(lasso.sin.reg, s = 0 , newx = x_test, type = 'response')
head(pred) # s = 0 (sin regularizacion)

# Tabla de frecuencias (churn y no-churn)
freq_table <- table(y_train) / dim(y_train)[1]
prob_priori <- as.numeric(freq_table[1])
freq_table
prob_priori # la vamos a usar como punto de corte.
table(y_train) #/ dim(y_train)

######################
# Performance en TRAIN
######################

# Clasificamos en [0,1] en funcion de una probababilidad a priori
y_hat = as.numeric(pred_tr >= prob_priori) 
head(y_hat)

# Matriz de Confusion
matriz.confusion = table(y_hat, y_train)
matriz.confusion

# Matriz expresada en prob.
prop.table(table(y_hat, y_train))

# Tasa de error 
# estimacion puntual con datos de test
tasa_error_tr <- 1-sum(diag(matriz.confusion))/sum(matriz.confusion)
tasa_error_tr # 11.49 %
# ?Es conveniente evaluar el modelo con la tasa de acierto unicamente?

##### Curva ROC y Area baja la curva ROC (AUC)
### Primero obtenemos las propabilidades a posteriori, luego:
dev.off();
pred2 <- prediction(pred_tr, y_train)
perf <- performance(pred2,"tpr","fpr")

# Que hace 'performance'?
#help(performance)

# Graficamos la curva ROC
plot(perf, main="Curva ROC", colorize=T)

auc <- performance(pred2, measure = "auc")
auc@y.values[[1]] # 0.79 (aprox)
# Se ve visualmente que esta mas alejada del vertice. Por lo menos en train es menor en poder predictivo. 

######################
# Performance en TEST
######################

# Clasificamos en [0,1] en funcion de una probababilidad a priori
y_hat = as.numeric(pred >= prob_priori) 

# Matriz de Confusion
matriz.confusion = table(y_hat, y_test)
matriz.confusion

# Matriz expresada en prob.
prop.table(matriz.confusion)

# Tasa de error 
tasa_error <- 1-sum(diag(matriz.confusion))/sum(matriz.confusion)
tasa_error # 13%

##### Curva ROC y Area baja la curva ROC (AUC)
#dev.off();
pred2 <- prediction(pred, y_test)
perf <- performance(pred2,"tpr","fpr")

# Graficamos la curva ROC
plot(perf, main="Curva ROC", colorize=T)

auc <- performance(pred2, measure = "auc")
auc@y.values[[1]] # 0.785 (aprox)
# Menor poder predictivo pero menor gap entre val y test. 

# Reportamos las metricas obtenidas
te_train_test <- (tasa_error - tasa_error_tr) / tasa_error_tr * 100
m_reglog<- c(tasa_error, auc@y.values[[1]], te_train_test)
m_reglog

######### REGRESION LOGISTICA + REGULARIZACION #######
######################################################

# Creamos una secuencia de valores para lambda
grid.l =exp(seq(1 , -10 , length = 20)) # Secuencia de lamdas.
grid.l
# Entrenamos el modelo Regularizacion Logistica - Regularizacion
lasso.reg = glmnet(x = x_train , 
                   y = y_train,
                   family = 'binomial', 
                   alpha = 1 , 
                   lambda = grid.l,
                   standardize = TRUE)

# Analizamos Df (grados de libertad a medida que aumenta lambda)
lasso.reg # Tasa de error para cada valor de laamda.

# Visualuzamos la evolucion de los valores de las variables 
# en funcion de los distintos lambda log(??)
plot(lasso.reg, xvar = "lambda", label = TRUE) # Vemos que muchos parametros tienden a 0, se eliminan.

# Predicciones sobre datos TEST 
pred = predict(lasso.reg, s = 0.008 , newx = x_test, type = 'response')
head(pred) # s = 0 (con regularizacion)

# Evaluando PERFORNANCE del modelo ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Tabla de frecuencias (churn y no-churn)
freq_table <- table(y_train) / dim(y_train)[1]
prob_priori <- as.numeric(freq_table[1])
freq_table
prob_priori
table(y_train) #/ dim(y_train)

# Clasificamos en [0,1] en funcion de una probababilidad a priori
y_hat = as.numeric(pred >= prob_priori) 

# Comparamos los predicho vs. real para generar matriz de confusion
# Repaso de conceptos: FP y FN
matriz.confusion = table(y_hat, y_test)

# Matriz de confusion
matriz.confusion

# Matriz expresada en prob.
prop.table(matriz.confusion) # NO tiene error en falsos positivos pero si en falsos negativos.

# Tasa de error
tasa_error <- 1 - sum(diag(matriz.confusion))/sum(matriz.confusion)
tasa_error # 11.55

# Curva ROC y AUC
dev.off();
pred2 <- prediction(pred, y_test)
perf <- performance(pred2,"tpr","fpr")

# Graficamos la curva ROC
plot(perf, main="Curva ROC", colorize=T)

auc <- performance(pred2, measure = "auc")
auc@y.values[[1]] # 0.75 (aprox) Baja considerablemente cuando regularizamos

# Reportamos las metricas obtenidas
te_train_test <- (tasa_error - tasa_error_tr) / tasa_error_tr * 100
m_reglogR<- c(tasa_error, auc@y.values[[1]], te_train_test)
m_reglogR

###############################################################
###     Ajustando lambda via 5-fold cross-validation.      ####  
###############################################################
set.seed(123)
cv.out = cv.glmnet(x_train, y_train, 
                   family = 'binomial', # Modelo logistico.
                   type.measure="auc", # Metrica del CV (no depende del umbral).
                   lambda = grid.l, 
                   alpha = 1, # LASSO.
                   nfolds = 5)

cv.out
# Graficamos como varia AUC en funcion del valor de lambda 
# Recordamos que significan las lineas verticales
# the left vertical line in our plot shows us where the CV-error curve hits its minimum. 
# The right vertical line shows us the most regularized model with CV-error 
#           within 1 standard deviation of the minimum. 
# We also extract such optimal ??'s
# Mas info sobre paquete glmnet: 
# https://web.stanford.edu/~hastie/glmnet/glmnet_alpha.html#log

plot (cv.out)
bestlam = cv.out$lambda.min
bestlam # poca regularizacion, nos da la idea de que no ganamos mucho con la regularizacion.

# Lambda con 1 Stev
cv.out$lambda.1se

# Predicciones sobre el conjunto de TEST con el mejor lambda
pred = predict(lasso.reg, s = bestlam , newx = x_test, type = 'response')
y_hat = as.numeric(pred>= prob_priori)

# Evaluamos Performance en TEST
# Matriz de confusion 
matriz.confusion = table(y_hat, y_test)
matriz.confusion

# Tasa de Error
tasa_error <- 1 - sum(diag(matriz.confusion))/sum(matriz.confusion)
tasa_error # 13%

# Curva ROC y AUC
pred2 <- prediction(pred, y_test)
perf <- performance(pred2,"tpr","fpr")
auc <- performance(pred2,"auc")
auc@y.values[[1]] # 0.783 ()

# Reportamos las metricas obtenidas
te_train_test <- (tasa_error - tasa_error_tr) / tasa_error_tr * 100
m_reglogRcv<- c(tasa_error, auc@y.values[[1]], te_train_test)
m_reglogRcv

########################################################
############## Clasificacion R. Forest: ################
########################################################

# Breve repaso teorico
# R. Forest = ?Arboles + Bootstrap 'decorrelado' + Ensamblaje
#  re-muestreo doble: Por un lado observaciones y por otro lado features (covariables).


churn.forest = randomForest(TARGET~.,
                            data=train,
                            mtry = floor(sqrt(ncol(train))), # numero de variables candidatas para corte --> sqrt(p) --> Numero recomendado inicial.
                            ntree=500,                       # B: numero de arboles bootstrap 
                            sample = 0.5*floor(train),       # tamanio de cada re-muestra bootstrap.
                            maxnodes = 10,                   # cantidad maxima de nodos terminales en c/ arbol.
                            nodesize = 50,                   # cantidad minima de datos en nodo terminal.
                            importance=T,                    # Computar importancia de c/ covariable.
                            proximity =F                     # computa la matriz de proximidad entre observaciones.
                            # na.action =  na.roughfix       # imputa perdidos con mediana / moda. 
                            # na.action = rfImpute           # imputa perdidos con datos proximos.
                            # na.action = na.omit            # descarta valores perdidos. 
)

# Respecto del Fitting del modelo: 
head(churn.forest$votes,3)     # estimaciones para cada observacion (OOB)
head(churn.forest$predicted,3) # (Idem pero catagorias).
head(churn.forest$oob.times,3) # nro de veces q cada obs queda out-of-bag. # Numero de veces que cada observacion queda outofbag. Nos sirve para optimizar el RF.
churn.forest$confusion         # Matriz de confusuion (OOB) 

# Performance: (estimaciones OOB)
churn.forest  # (17 + 374)/3333 = 11.73%
# Cantidad de arboles, cantidad de variables en cada split.

# Importancia de cada variable: (+ alto = mas contribucion).
head(churn.forest$importance,5)
# www.stat.berkeley.edu/~breiman/RandomForests/cc_home.htm#varimp

dev.off()
varImpPlot(churn.forest, main ='Importancia de cada feature')

# Performance fuera de la muestra
pred.rfor.test = predict(churn.forest,newdata=test)
matriz.conf = table(pred.rfor.test,test$TARGET)
matriz.conf
t_error <- 1-sum(diag(matriz.conf))/sum(matriz.conf) 
paste(c("Tasa Error % (TEST) = "),round(t_error,4)*100,sep="")
#T.Error = 10.44%

# Curva ROC sobre test
pred = predict(churn.forest, newdata = test ,type='prob')[,1]
pred2 <- prediction(pred, test$TARGET)
auc.rf <- performance(pred2, measure = "auc")@y.values[[1]]
paste(c("AUC % (TEST) = "),round(auc.rf,6)*100,sep="")
#####################################################


############### Sintonia fina de hiper-parametros (OOB):
valores.m = c(90,100,120)  # valores de "m", numero de variables candidatas para corte
valores.maxnode = c(34, 36, 40)  # Complejidad de Arboles en el bosque.
parametros = expand.grid(valores.m = valores.m,valores.maxnode = valores.maxnode) 
# En la practica elegimos una grilla mas grande.
head(parametros,3) # Matriz de 35 filas x 2 columnas.
dim(parametros)

te = c() # Tasa de error estimada por OOB.
for(i in 1:dim(parametros)[1]){ # i recorre la grilla de parametros.
  forest.oob  = randomForest(TARGET~.,
                             data=train,
                             mtry = parametros[i,1], # m
                             ntree=5000,               
                             sample = 0.15*nrow(train), 
                             maxnodes = parametros[i,2], # complejidad 
                             nodesize = 8, 
                             proximity =F)  
  te[i] = 1 - sum(diag(forest.oob$confusion[,-3]))/sum(forest.oob$confusion[,-3])
  print(i)
}

forest.oob # OOB Error 6,69%
# print(te)

which(min(te)==te)
parametros[which(min(te)==te),] # m* = 9, maxnode* = 28 # Si caen en los extremos conviene cambiar la grilla y seguir entrenando.
best_m <- parametros[which(min(te)==te),][1][,1]
best_maxnode <- parametros[which(min(te)==te),][2][,1]

# Aca podemos analizar como varia la T.Error
# en funcion de la grilla de hiperparametros que entrenamos
scatterplot3d(cbind(parametros,te),type = "h", color = "blue")

# Recomendacion: Continuar explorando un poco mas el espacio de hiperparametros.

# Re-entrenamaos con m* y maxnodes*:
modelo.final = randomForest(TARGET~.,
                            data=train,
                            mtry = best_m,     # Estimacion de m*
                            ntree = 5000,              
                            sample = 0.15*nrow(train), 
                            maxnodes = best_maxnode, # Estimacion de maxnodes*
                            nodesize = 8,
                            importance=F, 
                            proximity =T,
                            classwt = c(0.8849329, 0.1150671)
)  

# Matriz de similaridades S
# donde si,j = cantidad de veces que las obs. i y j 
# comparten nodo terminal entre los ?arboles del bosque.

dim(modelo.final$proximity) # Matriz de proximidades. Se busca ver si el modelo esta funcionando correctamente para separar las clases.
# MDSplot(modelo.final, fac=train$TARGET , k = 2) # k = nro dim.
# Falsos positivos con los True positives se mezclan abajo a la derecha.
# Tiene sentido.

# Performance en TEST
pred.rfor.test = predict(modelo.final,newdata=test)
matriz.conf = table(pred.rfor.test,test$TARGET)
matriz.conf
t_error <- 1-sum(diag(matriz.conf))/sum(matriz.conf) # 6.18% 
paste(c("Tasa Error % (TEST) = "),round(t_error,4)*100,sep="")
#T.Error = 6.18%

# Curva ROC sobre test
pred = predict(modelo.final, newdata = test ,type='prob')[,2]
pred2 <- prediction(pred, test$TARGET)
auc.rf <- performance(pred2, measure = "auc")@y.values[[1]]
paste(c("AUC % (TEST) = "),round(auc.rf,6)*100,sep="")
# AUC = 91.6


################################################# 
# Compare models
#################################################

metrics <- c("Tasa Error","AUC", "Var T.Error Train/Test")
df_arbol <- data.frame(metrics, m_arbolvc)
cbind(df_arbol,m_arbolvc, m_reglog, m_reglogR, m_reglogRcv, m_reglogRcvF1)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# PROBANDO MODELOS
ctrl <- trainControl(method = "boot", # Usamos el metodo bootstrap
                     number = 5, 
                     verboseIter = FALSE,
                     sampling = "down") # Hacemos undersampling

model_rf_under <- caret::train(TARGET ~ .,
                               data = train,
                               method = 'rf', #RANDOM FOREST
                               trControl = ctrl)

########################################################
######################## SVM ###########################
########################################################

# Repaso de SVM: Maquinas de Vector Soporte en problemas de Clasificacion
# Clases linealmente separables y maximizacion de margenes. 
# Relajacion del problema de optimizacion con variables de holgura
# Modelos lineales en feature space
# C penaliza la violacion del margen, lo aprendemos por VC 
# C alto: margenes chicos, > varianza (overfitting?)
# C bajo: margenes grandes, > sesgo

# ?svm
# SVM LINEAL
svm.lin <- svm(churn ~ ., 
               data = Train, 
               type = 'C-classification', 
               cross = 10, # Estima el error por VC
               kernel = "linear", # En el espacio original
               cost = 10, # Parametro C; Costo por no separar bien las clases con el hiperplano.
               scale = TRUE) # Recomendable con SVM lineal.

svm.lin

summary(svm.lin)

svm.lin$index[1:3] # Indice de los datos de train que resultaron vectores soportes.
Train[10,] # Primer vector soporte.

head(svm.lin$SV) # coordenadas de los primeros vectores soporte.

svm.lin$cost

svm.lin$fitted[1:5] # Estimaciones en la muestra de entrenamiento

svm.lin$accuracies # Tasas de acierto en cada fold

svm.lin$tot.accuracy # Tasas de acierto estimada por VC

# Curva ROC
rocplot = function (pred , truth , ...) {
  predob = prediction(pred , truth )
  perf = performance(predob ,"tpr" , "fpr")
  auc =  performance(predob , measure = "auc")
  plot ( perf ,...) 
  return(auc@y.values[[1]])
}

fitted = attributes(predict(svm.lin,Train,decision.values=T))$decision.values
head(fitted, 3) # Distancia al hiperplano.

x11()
par(mfrow = c(1,2))
auc.svm.linT <- rocplot(-1*fitted, Train$churn , main ="Training Data")
plot(fitted, pch = 20, col = as.factor(Train$churn))
auc.svm.linT


#### El modelo no es muy bueno (al menos en la muestra de entrenamiento)
#### veamos que ocurre con los datos en Test:

pred.outsample = predict(svm.lin,newdata = Test)
matriz.conf <- table(pred.outsample, Test$churn)
t_error <- 1-sum(diag(matriz.conf))/sum(matriz.conf) 
paste(c("Tasa Error % (TEST) = "),round(t_error,4)*100,sep="")
#T.Error = 13.44%

#### Puedes intentar mejorar aun mas el modelo haciendo VC sobre el parametro
#### de costo----> utilizar el comando 'tune.svm' (o implementa por tu cuenta)
#### Validacion cruzada dentro de la libreria e1071

# Recordatorio: definicion de costo
#cost of constraints violation
# it is the 'C'-constant of the regularization term in the Lagrange formulation.

# Optimizacion del par?metro COSTO por VC
# Este codigo tarda en ejecutarse...lo dejamos offline
cost_vector <- c(0.1, 0.25, 0.5, 1)  #2^(-1:5)
tune.out <- tune.svm(churn ~ ., 
                     data = Train, 
                     cross = 5, 
                     kernel = "linear",  
                     cost = cost_vector, 
                     scale = TRUE)

summary(tune.out)

x11()
plot(tune.out)

summary(tune.out$best.model)
opt_cost <- tune.out$best.model$cost
opt_cost

"
Parameter tuning of 'svm':
  
  - sampling method: 10-fold cross validation 

- best parameters:
  cost
0.5

- best performance: 0.1449066 

- Detailed performance results: Para distintos costos tenemos el mismo nivel de error.
  cost     error dispersion
1  0.5 0.1449066 0.01911787
2  1.0 0.1449066 0.01911787
3  2.0 0.1449066 0.01911787
4  4.0 0.1449066 0.01911787
5  8.0 0.1449066 0.01911787
6 16.0 0.1449066 0.01911787
7 32.0 0.1449066 0.01911787
"
################################
# Cost  = 5
svm.lin <- svm(churn ~ ., 
               data = Train,
               kernel = "linear", 
               cost = 5, 
               scale = TRUE)


# Entrenamos un modelo con un costo de 5.
# Curva ROC sobre test
fitted = attributes(predict(svm.lin,Test,decision.values=T))$decision.values
head(fitted, 3) # Distancia al hiperplano.

x11()
par(mfrow = c(1,2))
auc.svm.lin <- rocplot(-1*fitted, Test$churn , main ="TEST Data")
plot(fitted, pch = 20, col = as.factor(Test$churn))
paste(c("AUC % (TEST) = "),round(auc.svm.lin,6)*100,sep="")
# AUC = 71.96

################################
# Cost  = 0.1
svm.lin <- svm(churn ~ ., 
               data = Train,
               kernel = "linear", 
               cost = 0.1, 
               scale = TRUE)

# Curva ROC sobre test
fitted = attributes(predict(svm.lin,Test,decision.values=T))$decision.values

x11()
par(mfrow = c(1,2))
auc.svm.lin <- rocplot(-1*fitted, Test$churn , main ="TEST Data")
plot(fitted, pch = 20, col = as.factor(Test$churn))
paste(c("AUC % (TEST) = "),round(auc.svm.lin,6)*100,sep="")
# AUC = 80.87

pred.insample = predict(svm.lin)
head(pred.insample)

# Predicciones en train
matriz.insample <- table(pred.insample,Train$churn)
1-sum(diag(matriz.insample))/sum(matriz.insample)  
#T.Error = 14.5%

# Predicciones en test
pred.outsample = predict(svm.lin, newdata = Test)
matriz.conf <- table(pred.outsample, Test$churn)
t_error <- 1-sum(diag(matriz.conf))/sum(matriz.conf) 
paste(c("Tasa Error % (TEST) = "),round(t_error,6)*100,sep="")
#T.Error = 13.4%

########################################################
# SVM GAUSSIANO
svm.rad <- svm(churn ~ ., 
               data = Train, 
               kernel = "radial", 
               cost = 100,
               gamma = 0.1,
               scale = TRUE)
svm.rad

# Predicciones en test
pred.outsample = predict(svm.rad, newdata = Test)
matriz.conf <- table(pred.outsample, Test$churn)
t_error <- 1-sum(diag(matriz.conf))/sum(matriz.conf) 
paste(c("Tas Error % (TEST) = "),round(t_error,4)*100,sep="")
#T.Error = 8.4%


# Optimizacion del par?metro COSTO y GAMMA por VC
# Este codigo tarda en ejecutarse...lo dejamos OFFLNE

tune.out <- tune.svm(churn ~ ., data = Train, 
                     cross = 5, 
                     kernel = "radial",  
                     cost= c(50,100),
                     gamma = c(0.001,0.01),
                     scale = TRUE)
summary(tune.out)

plot(tune.out)

opt_cost <- tune.out$best.model$cost
opt_gamma <- tune.out$best.model$gamma

opt_cost; opt_gamma

summary(tune.out$best.model)

# Optimizados los parametros

svm.rad <- svm(churn ~ ., 
               data = Train, 
               kernel = "radial", 
               cost = 50,
               gamma = 0.01,
               scale = TRUE)

# Predicciones en test
pred.outsample = predict(svm.rad, newdata = Test)
matriz.conf <- table(pred.outsample, Test$churn)
t_error <- 1-sum(diag(matriz.conf))/sum(matriz.conf) 
paste(c("Tasa Error % (TEST) = "),round(t_error,4)*100,sep="")
#T.Error = 7.44%

# Curva ROC sobre test
fitted = attributes(predict(svm.rad,Test,decision.values=T))$decision.values
head(fitted, 3) # Distancia al hiperplano.

dev.off()
x11()
par(mfrow = c(1,2))
auc.svm.rad <- rocplot(-1*fitted, Test$churn , main ="TEST Data")
plot(fitted, pch = 20, col = as.factor(Test$churn))
paste(c("AUC % (TEST) = "),round(auc.svm.rad,6)*100,sep="")
# AUC = 90.7


# Curva ROC ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pred.acp = predict(model_rf_under,type='prob')
### Primero obtenemos las propabilidades a posteriori, luego:
pred2 <- prediction(final_under[,1], test$TARGET)
perf2 <- performance(pred2,"tpr","fpr")


auc <- performance(pred2,"auc")
auc@y.values[[1]] # 0.91 (aprox)
auc <- unlist(slot(auc, "y.values"))
auct <- paste(c("AUC = "),round(auc,2),sep="")
auct
