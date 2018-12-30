## load packages
library(data.table) # used for reading and manipulation of data
library(dplyr)      # used for data manipulation and joining
library(ggplot2)    # used for ploting 
library(caret)      # used for modeling
library(corrplot)   # used for making correlation plot
library(xgboost)    # used for building XGBoost model
library(cowplot)    # used for combining multiple plots 
library(RColorBrewer)

## read datasets
#'        Variable Name                 Description
#' @field Item_Identifier               Unique product ID
#' @field Item_Weight                   Weight of product
#' @field Item_Fat_Content              Whether the product is low fat or not
#' @field Item_Visibility               The % of total display area of all products in a store allocated to the particular product
#' @field Item_Type                     The category to which the product belongs
#' @field Item_MRP                      Maximum Retail Price (list price) of the product
#' @field Outlet_Identifier             Unique store ID
#' @field Outlet_Establishment_Year     The year in which store was established
#' @field Outlet_Size                   The size of the store in terms of ground area covered
#' @field Outlet_Location_Type          The type of city in which the store is located
#' @field Outlet_Type                   Whether the outlet is just a grocery store or some sort of supermarket
#' @field Item_Outlet_Sales             Sales of the product in the particulat store. This is the outcome variable to be predicted.

train = fread("Train_UWu5bXk.csv")
test = fread("Test_u94Q5KV.csv")
submission = fread("SampleSubmission_TmnO39y.csv")

########################
# Variable Exploration #
########################
# -----------------------------------------------------------------
# Sales
ggplot(train) + 
  geom_density(aes((Item_Outlet_Sales)), fill = "lightblue") +
  xlab("Item_Outlet_Sales")

ggplot(train) + 
  geom_density(aes((Item_Outlet_Sales)^(1/3)), fill = "lightblue") +
  xlab("Item_Outlet_Sales")

# -----------------------------------------------------------------
# Fat Content and Outlet_Size
p1 = ggplot(train %>% group_by(Item_Fat_Content) %>% summarise(Count = n())) + 
  geom_bar(aes(Item_Fat_Content, Count), stat = "identity", fill = "coral1") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

p2 = ggplot(train %>% group_by(Outlet_Size) %>% summarise(Count = n())) + 
  geom_bar(aes(Outlet_Size, Count), stat = "identity", fill = "coral1") +
  geom_label(aes(Outlet_Size, Count, label = Count), vjust = 0.5) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

# In Outlet_Size’s plot, for 4016 observations, Outlet_Size is blank or missing.
# We will check for this later to substitute the missing values in the Outlet_Size.
plot_grid(p1, p2, nrow = 1)

# From the plot above, we can find that "LF" and "low fat" should be equal to "Low Fat"
# Similarly, "reg" should be equal to "Regular"
train = train %>%
  mutate(
    Item_Fat_Content = case_when(
      .$Item_Fat_Content == 'LF' ~ 'Low Fat',
      .$Item_Fat_Content == 'low fat' ~ 'Low Fat',
      .$Item_Fat_Content == 'reg' ~ 'Regular',
      TRUE ~ .$Item_Fat_Content
    )
  )

# For the missing values in the feature - Outlet Size, we will deal with it latter

# -----------------------------------------------------------------
# Outlet_Establishment_Year
p1 = ggplot(train %>% group_by(Outlet_Establishment_Year) %>% summarise(Count = n())) + 
  geom_bar(aes(factor(Outlet_Establishment_Year), Count, fill = Count), stat = "identity") +
  xlab("Outlet_Establishment_Year") +
  theme(axis.text.x = element_text(size = 8.5, hjust = 1, angle = 45)) +
  scale_x_discrete(name = '')

p2 = train %>%
  group_by(Outlet_Establishment_Year) %>%
  summarise(mean = mean(Item_Outlet_Sales)) %>%
  ungroup() %>%
  mutate(Outlet_Establishment_Year = factor(Outlet_Establishment_Year)) %>%
  ggplot() +
  geom_bar(aes(x = Outlet_Establishment_Year, y = mean, fill = mean), stat = 'identity') +
  geom_label(aes(Outlet_Establishment_Year, round(mean, 0), label = round(mean, 0)), vjust = 0.5) +
  theme(axis.text.x = element_text(size = 8.5, hjust = 1)) +
  scale_y_continuous(name = 'Mean Sale') +
  scale_x_discrete(name = '') +
  labs(title = 'Outlet Establishment Year')

p3 = train %>%
  ggplot() +
  geom_bar(aes(factor(Outlet_Establishment_Year), fill = Outlet_Location_Type)) +
  theme(axis.text.x = element_text(size = 8.5, hjust = 1, angle = 45)) +
  scale_x_discrete(name = '') +
  scale_fill_discrete(name = 'Location')

# Lesser number of observations in the data for the outlets established in the year 1998 
# as compared to the other years. It might be caused by poor sales at that year. Therefore, we plot
# the mean sale in each year and find that the mean sale in 1998 was indeed lesser than other years.
# By looking at the bottom right plot, we can find that in each year, the company tends to establish
# outlets in one location
nrow2 = plot_grid(p1, p3, nrow = 1)
plot_grid(p2, nrow2, nrow = 2)

# -----------------------------------------------------------------
# Outlet Location
p1 = train %>%
  group_by(Outlet_Location_Type) %>%
  summarise(Count = n()) %>%
  ggplot() +
  geom_bar(aes(Outlet_Location_Type, Count, fill = Count), stat = 'identity') +
  scale_x_discrete(name = '')

p2 = train %>%
  group_by(Outlet_Location_Type) %>%
  summarise(Mean_Sale = mean(Item_Outlet_Sales)) %>%
  ggplot() +
  geom_bar(aes(Outlet_Location_Type, Mean_Sale, fill = Mean_Sale), stat = 'identity') +
  scale_x_discrete(name = '') +
  labs(title = 'Outlet Location')

p3 = train %>%
  group_by(Outlet_Location_Type) %>%
  summarise(Total_Sale = sum(Item_Outlet_Sales)) %>%
  ggplot() +
  geom_bar(aes(Outlet_Location_Type, Total_Sale, fill = Total_Sale), stat = 'identity') +
  scale_x_discrete(name = '')

#' Large number of outlets locate at Tier3 so the total sales in Tier3 is 
#' the largest. However, the average sales in Tier2 is the largest
#' Maybe the company can establish more outlets at Tier2
nrow2 = plot_grid(p1, p3, nrow = 1)
plot_grid(p2, nrow2, nrow = 2)

# -----------------------------------------------------------------
# Outlet Type
p1 = ggplot(train %>% group_by(Outlet_Type) %>% summarise(Count = n())) + 
  geom_bar(aes(Outlet_Type, Count, fill = Count), stat = "identity") +
  geom_label(aes(factor(Outlet_Type), Count, label = Count), vjust = 0.5) +
  theme(axis.text.x = element_text(size = 8.5, angle = 10, hjust = 1)) +
  labs(title = 'Number of Outlet Type') +
  scale_x_discrete(name = '')

p2 = train %>%
  group_by(Outlet_Type) %>%
  summarise(mean = mean(Item_Outlet_Sales)) %>%
  ungroup() %>%
  ggplot() +
  geom_bar(aes(x = Outlet_Type, y = mean, fill = mean), stat = 'identity') +
  theme(axis.text.x = element_text(angle = 10, hjust = 1, size = 8.5)) +
  scale_y_continuous(name = 'Mean Sale') +
  labs(title = 'Mean Sale of each Outlet Type') +
  scale_x_discrete(name = '')


p3 = ggplot(train, aes(Outlet_Type)) + 
  geom_bar(aes(fill=Outlet_Location_Type), width = 0.5) + 
  theme(axis.text.x = element_text(angle=10, hjust=1, size = 8.5)) + 
  labs(title="Outlet Type across Location")  +
  scale_x_discrete(name = '') +
  scale_fill_discrete(name = 'Location')

#' Supermarket Type 1 seems to be the most popular category of Outlet_Type.
#' So we might expect that the Supermarket Type 1 should have the best sales, 
#' however, we find that Supermarket Type 3 has the best sales
nrow2 = plot_grid(p1, p3, nrow = 1)
plot_grid(p2, nrow2, nrow = 2)

#' Let's check whether the large amount of sales in Supermarket Type3 is caused by
#' higher price of the products
train %>%
  group_by(Outlet_Type) %>% 
  summarise(Average_Price = mean(Item_MRP)) %>%
  ungroup() %>%
  ggplot() +
  geom_bar(aes(Outlet_Type, Average_Price, fill = Average_Price), stat = 'identity') +
  theme(axis.text.x = element_text(angle=10, hjust=1, size = 8.5))

#' We can find that the average prices for each kind of outlets are similar,
#' so we can conclude that people tend to shop at Supermarket Type3
  
# -----------------------------------------------------------------
# Item Type
# https://www.r-bloggers.com/how-to-expand-color-palette-with-ggplot-and-rcolorbrewer/
colourCount = length(unique(train$Item_Type))
getPalette = colorRampPalette(brewer.pal(9, "YlGnBu"))

train %>%
  group_by(Outlet_Location_Type, Item_Type) %>%
  summarise(Total_Sale = sum(Item_Outlet_Sales)) %>%
  ungroup() %>%
  ggplot() +
  geom_bar(aes(x = Item_Type, y = Total_Sale, fill = Item_Type), stat = 'identity') +
  scale_fill_manual(values = getPalette(colourCount)) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8.5)) +
  facet_grid(~Outlet_Location_Type)

#' In each location, Fruit and Vegetable and Snack Foods 
#' are the most popular products 

731x457
# -----------------------------------------------------------------
# Item Visibility, MRP

# Item_Visibility vs Item_Outlet_Sales
p1 = ggplot(train) + geom_point(aes(Item_Visibility, Item_Outlet_Sales), colour = "violet", alpha = 0.3) +
      theme(axis.title = element_text(size = 8.5))

# Item_MRP vs Item_Outlet_Sales
p2 = ggplot(train) + geom_point(aes(Item_MRP, Item_Outlet_Sales), colour = "violet", alpha = 0.3) +
      theme(axis.title = element_text(size = 8.5))

# In Item_Visibility vs Item_Outlet_Sales, there is a string of points at Item_Visibility = 0.0 which seems strange as item visibility cannot be completely zero. We will take note of this issue and deal with it in the later stages.
# In the third plot of Item_MRP vs Item_Outlet_Sales, we can clearly see 4 segments of prices that can be used in feature engineering to create a new variable.
plot_grid(p1, p2, nrow = 1)

# replacing 0 in Item_Visibility with mean
zero_index = which(train$Item_Visibility == 0)
for(i in zero_index){
  
  item = train$Item_Identifier[i]
  train$Item_Visibility[i] = mean(train$Item_Visibility[train$Item_Identifier == item], na.rm = T)
  
}

# creating new independent variable - Item_MRP_clusters
train = train %>%
  mutate(
    Item_MRP_clusters = case_when(
      .$Item_MRP < 69 ~ '1st',
      .$Item_MRP >=69 & .$Item_MRP < 136 ~ '2nd',
      .$Item_MRP >=136 & .$Item_MRP < 203 ~ '3rd',
      TRUE ~ '4th'
    )
  )

# -----------------------------------------------------------------
# Item_Fat_Content and Outlet_Identifier

p1 = ggplot(train) + 
  geom_violin(aes(Item_Fat_Content, Item_Outlet_Sales)) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        axis.text = element_text(size = 8),
        axis.title = element_text(size = 8.5))

p2 = ggplot(train) + 
  geom_violin(aes(Outlet_Identifier, Item_Outlet_Sales)) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        axis.text = element_text(size = 8),
        axis.title = element_text(size = 8.5))

plot_grid(p1, p2, nrow = 1)

#' The feature - Item_Fat_Content might not have impact on 
#' the prediction of Sales
#' From the right plot, we can see that products - OUT010 and OUT019 
#' have relatively small sales


# -----------------------------------------------------------------
# Missing Values

# Count missing values in each variables
count_na = function(x){
  sum(is.na(x))
}
tidyr::gather(purrr::map_dfr(train, count_na))

## Missing Value Treatment
missing_index = which(is.na(train$Item_Weight))
for(i in missing_index){
  
  item = train$Item_Identifier[i]
  train$Item_Weight[i] = mean(train$Item_Weight[train$Item_Identifier == item], na.rm = T)
  
}

train = train %>%
  mutate(
    Outlet_Size = case_when(
      .$Outlet_Size == 'Small' ~ 1,
      .$Outlet_Size == 'Medium' ~ 2,
      .$Outlet_Size == 'High' ~ 3
    )
  ) 

missing_index = which(is.na(train$Outlet_Size))
for(i in missing_index){
  
  item = train$Item_Identifier[i]
  train$Outlet_Size[i] = mean(train$Outlet_Size[train$Item_Identifier == item], na.rm = T)
  
}
