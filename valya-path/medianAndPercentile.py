import pandas as pd

df = pd.read_csv('valya-path/variableIndexDynamic.csv')
df = df.iloc[1:]

SECONDS_PER_YEAR = 31536000

median = df['percent_deltaIndex'].median() * SECONDS_PER_YEAR

#5th and 95th percentiles
# biggest from smallest
p5 = df['percent_deltaIndex'].quantile(0.05) * SECONDS_PER_YEAR

# smallest from biggest
p95 = df['percent_deltaIndex'].quantile(0.95) * SECONDS_PER_YEAR
max_value = df['percent_deltaIndex'].max() * SECONDS_PER_YEAR

print(f"Median: {median:.30f}")
print(f"5th percentile: {p5:.30f}")
print(f"95th percentile: {p95:.30f}")
print(f"Max: {max_value:.30f}")