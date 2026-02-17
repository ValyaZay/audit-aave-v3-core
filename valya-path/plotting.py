import pandas as pd
import matplotlib.pyplot as plt

plt.figure(figsize=(12,6))
df = pd.read_csv('valya-path/variableIndexDynamic.csv')
df = df.iloc[1:]
df['datetime'] = pd.to_datetime(df['timestamp'], unit='s')

plt.plot(df['datetime'], df['percent_deltaIndex'])


plt.xlabel('Time')
plt.ylabel('delta index per second')
plt.title('VariableBorrowIndex growth per second')

plt.savefig('valya-path/deltaIndexPerSecond.png', dpi=300)
print("Plot saved")

