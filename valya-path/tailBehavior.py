# uv run python valya-path/tailBehavior.py

import pandas as pd

df = pd.read_csv('valya-path/variableIndexDynamic.csv')
df = df.iloc[1:]

# smallest from biggest
p95 = df['percent_deltaIndex'].quantile(0.95)

# all time intervals where apr growth was unusually high - isolate tail events
# here are all time intervals where borrow index growth was unusually high
tail_events = df[df['percent_deltaIndex'] > p95]

p95 = df['percent_deltaIndex'].quantile(0.95)

p99 = df['percent_deltaIndex'].quantile(0.99)
print(f"p99 deltaindex = {p99:.30f}")

p99_rate = df['currentVariableBorrowRate'].quantile(0.99)
print(f"p99 currentVariableBorrowRate = {p99_rate:.30f}")

median = df['percent_deltaIndex'].median()
max_value = df['percent_deltaIndex'].max()



# if any 'true' - here is a fat-tailed process. Fat tails = liquidation alpha
# tail detection is indirectly dececting PERIODS OF MARKET STRESS!!!
print(p95 >= 5 * median) # 5x extreme volatility regime
print(p99 >= 25 * median) # 25x means rare but massive shocks - means does the extreme 1% behave completely differently
print(max_value >= 300 * median) # 300x means a single catastrophic spike, monster outliers, black-swan scale events

# IN AAVE:
# variableIndex = rate * time
#      ||
#      \/
# rate jumps when utilization spikes
#      ||
#      \/
# utilization spikes when liquidity disappears
#      ||
#      \/
# liquidity disappears during volatility




# Do top 1% events occur consecutively?
tail_events_99 = df[df['percent_deltaIndex'] > p99]
print(tail_events_99) # yes - because utilization jumped, this is not noisy process

# Does p99 cluster in short windows?
start = tail_events_99.at[759, 'timestamp']
end = tail_events_99.at[775, 'timestamp']
time_window_sec = end - start
print(start)
print(end)
print("cluster in time window (minutes): ", time_window_sec / 60) #result 18.6 minutes - temporary elevated slope - VERY MEANINGFUL

# How far is p99 from p95?
print(f"How far is p99 from p95? {(p99 - p95):.30f}") # result  0.000000000030825240000000081212 - THIS IS TINY NUMBER -> RARE UPWARD REGIME

average_utilization = df['utilization'].mean()
print(f"average utilization = {average_utilization:.30f}")