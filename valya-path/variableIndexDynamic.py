from web3 import Web3
from dotenv import load_dotenv
import os
import pandas as pd

load_dotenv()

USDC_RESERVE_MAINNET_ETHEREUM_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
POOL_ADDRESS="0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"
URL_MAINNET_ETHEREUM = os.getenv("URL_MAINNET_ETHEREUM")

print("url from env ", URL_MAINNET_ETHEREUM)

POOL_ABI=[{
                    "inputs": [
                        {
                            "internalType": "address",
                            "name": "asset",
                            "type": "address"
                        }
                    ],
                    "stateMutability": "view",
                    "type": "function",
                    "name": "getReserveData",
                    "outputs": [
                        {
                            "internalType": "struct DataTypes.ReserveData",
                            "name": "",
                            "type": "tuple",
                            "components": [
                                {
                                    "internalType": "struct DataTypes.ReserveConfigurationMap",
                                    "name": "configuration",
                                    "type": "tuple",
                                    "components": [
                                        {
                                            "internalType": "uint256",
                                            "name": "data",
                                            "type": "uint256"
                                        }
                                    ]
                                },
                                {
                                    "internalType": "uint128",
                                    "name": "liquidityIndex",
                                    "type": "uint128"
                                },
                                {
                                    "internalType": "uint128",
                                    "name": "currentLiquidityRate",
                                    "type": "uint128"
                                },
                                {
                                    "internalType": "uint128",
                                    "name": "variableBorrowIndex",
                                    "type": "uint128"
                                },
                                {
                                    "internalType": "uint128",
                                    "name": "currentVariableBorrowRate",
                                    "type": "uint128"
                                },
                                {
                                    "internalType": "uint128",
                                    "name": "currentStableBorrowRate",
                                    "type": "uint128"
                                },
                                {
                                    "internalType": "uint40",
                                    "name": "lastUpdateTimestamp",
                                    "type": "uint40"
                                },
                                {
                                    "internalType": "uint16",
                                    "name": "id",
                                    "type": "uint16"
                                },
                                {
                                    "internalType": "address",
                                    "name": "aTokenAddress",
                                    "type": "address"
                                },
                                {
                                    "internalType": "address",
                                    "name": "stableDebtTokenAddress",
                                    "type": "address"
                                },
                                {
                                    "internalType": "address",
                                    "name": "variableDebtTokenAddress",
                                    "type": "address"
                                },
                                {
                                    "internalType": "address",
                                    "name": "interestRateStrategyAddress",
                                    "type": "address"
                                },
                                {
                                    "internalType": "uint128",
                                    "name": "accruedToTreasury",
                                    "type": "uint128"
                                },
                                {
                                    "internalType": "uint128",
                                    "name": "unbacked",
                                    "type": "uint128"
                                },
                                {
                                    "internalType": "uint128",
                                    "name": "isolationModeTotalDebt",
                                    "type": "uint128"
                                }
                            ]
                        }
                    ]
                }]

w3 = Web3(Web3.HTTPProvider(URL_MAINNET_ETHEREUM))
print("Connected:", w3.is_connected())

latest_block = w3.eth.block_number
print("latest block ", latest_block)

pool_contract = w3.eth.contract(address=POOL_ADDRESS, abi=POOL_ABI)
reserveData = pool_contract.functions.getReserveData(USDC_RESERVE_MAINNET_ETHEREUM_ADDRESS).call(block_identifier=latest_block)
        
aTokenAddress = reserveData[8]
aToken_abi = [{
                    "inputs": [],
                    "stateMutability": "view",
                    "type": "function",
                    "name": "totalSupply",
                    "outputs": [
                        {
                            "internalType": "uint256",
                            "name": "",
                            "type": "uint256"
                        }
                    ]
                }]
aToken_contract = w3.eth.contract(address=aTokenAddress, abi=aToken_abi)


variableDebtTokenAddress = reserveData[10]
variableDebtToken_abi = [{
                    "inputs": [],
                    "stateMutability": "view",
                    "type": "function",
                    "name": "scaledTotalSupply",
                    "outputs": [
                        {
                            "internalType": "uint256",
                            "name": "",
                            "type": "uint256"
                        }
                    ]
                }]
variableDebtToken_contract = w3.eth.contract(address=variableDebtTokenAddress, abi=variableDebtToken_abi)

# blocks range for the last 30 days
blocksPerDay = 7200
days = 1
startBlock = latest_block - blocksPerDay * days

# loop through blocks to get variable borrow index for each block to get array
data = []
columns = [
    'block', 
    'timestamp',
    'previousVariableBorrowIndex',
    'variableBorrowIndex',
    'percent_deltaIndex',
    'currentVariableBorrowRate',
    'utilization']
previousVariableBorrowIndex = pool_contract.functions.getReserveData(USDC_RESERVE_MAINNET_ETHEREUM_ADDRESS).call(block_identifier=startBlock)[3]
print("previousIndex ", previousVariableBorrowIndex)
previousTimestamp = w3.eth.get_block(startBlock)['timestamp']
print("previousTimestamp ", previousTimestamp)

# for block in range(startBlock, latest_block+1):
# #for block in range(latest_block-1, latest_block+1):
#     try:
#         reserveData = pool_contract.functions.getReserveData(USDC_RESERVE_MAINNET_ETHEREUM_ADDRESS).call(block_identifier=block)
        
#         variableBorrowIndex = reserveData[3]

#         if(previousVariableBorrowIndex != variableBorrowIndex):
#             # UTILIZATION
#             variableDebtTokenScaledTotlaSupply = variableDebtToken_contract.functions.scaledTotalSupply().call(block_identifier=block)
#             totalVariableDebt = variableBorrowIndex * variableDebtTokenScaledTotlaSupply / 1e27

#             totalLiquidity = aToken_contract.functions.totalSupply().call(block_identifier=block)
#             utilization = totalVariableDebt / totalLiquidity

#             # RATE
#             currentVariableBorrowRate = reserveData[4]
        
#             # TIMESTAMP
#             currentBlock = w3.eth.get_block(block)
#             timestamp = currentBlock['timestamp']

#             deltaTimeSinceIndexChange = timestamp - previousTimestamp

#             # calculate deltaIndex
#             deltaIndexPerSecond = deltaIndex = ((variableBorrowIndex / previousVariableBorrowIndex) - 1) / deltaTimeSinceIndexChange
            
#             print(f"block: {block}, timestamp: {timestamp}, previous: {previousVariableBorrowIndex}, variableBorrowIndex: {variableBorrowIndex}, percent_deltaIndex: {deltaIndex:.30f}, currentVariableBorrowRate: {currentVariableBorrowRate}, utilization: {utilization}")
            
#             data.append([block, timestamp, previousVariableBorrowIndex, variableBorrowIndex, deltaIndex, currentVariableBorrowRate, utilization])
            
#             previousVariableBorrowIndex = variableBorrowIndex
#             previousTimestamp = timestamp
#     except Exception as e:
#         print(f"Skipped block {block}: {e}")

# df = pd.DataFrame(data, columns=columns)
# df.to_csv('valya-path/variableIndexDynamic.csv', index=False, float_format='%.30f')

