# [CRPWarner, Contracted-related Rug Pull Warner]

**CRPWarner** is a static analysis framework of bytecode of Solidity smart contracts. It is used to detect the malicious functions used to perform a rug pull.

## Definition and Classification of Rug Pull

"Rug Pull" is a kind of cryptocurrency scam occurs when the developer of a particular token project intentionally abandons the project and disappears with investors' funds. 

We categorized these rug pull events into two main categories: *Contract-related* Rug Pull, which occurs through malicious functions in smart contracts, and *Transaction-related* Rug Pull, which occur through cryptocurrency trading without the use of malicious functions. The brief definition of each type of rug pull is shown in below.

### *Contract-Related* Rug Pull

| Rug Pull Type | Definition | 
|-------|-------|
| Hidden Mint Function | Exist a mint function to generate any number of tokens to any address. | 
| Limiting Sell Order | Exist a mechanism to restrict users from selling tokens. | 
| Leaking Token | Exist a mechanism to leak token from other users without permission. | 

### *Transaction-Related* Rug Pull

| Rug Pull Type | Definition | 
|-------|-------|
| Dumping Cryptocurrency | Sell off a large number of cryptocurrency suddenly. | 
| Withdrawing Liquidity | Withdraw liquidity and steal almost all the valuable assets in the pool. | 
| Abandoning Project after Funding | Abandon the project and abscond without delivering on their promises. | 

## Dataset of Real-world Rug Pull Events

The dataset of real-world Rug Pull Events and the result of manual analysis is shown in *dataset/rugpullevents/rugpullevents.xlsx*

The information included in this dataset is as follows:
+ **Project Name**: The name of DeFi project which has Rug Pull.
+ **Classification**: The Rug Pull Event is *Contract-related* Rug Pull or *Transaction-related* Rug Pull.
+ **Pattern**: Which of the above six methods did the DeFi project specifically use to execute the Rug Pull?
+ **Open Source**: Is the smart contract associated with this Rug Pull project open source?
+ **Enough Information**: Does the report on this event include the necessary information to determine the specific method of the Rug Pull?
+ **Loss**: The economic loss caused by this Rug Pull event (unit: kUSD).
+ **Source**: The source of the report for this Rug Pull event.

## CRPWarner

We propose CRPWarner, an analysis tool designed to assess the risk of *Contract-related* Rug Pull.

### Install

CRPWarner is based on the environment of gigahorse.

### Usage

Run Slither on a Hardhat/Foundry/Dapp/Brownie application:

```
cd ./gigahorse
python ./gigahorse.py -C ./clients/crpwarner.dl ../dataset/groundtruth/hex/0x0414D8C87b271266a5864329fb4932bBE19c0c49.hex
```

### Dataset of Rug Pull Risk Detection

We constructed two datasets to validate the effectiveness of CRPWarner: one corresponding to real-world Rug Pull events, and the other consisting of a large-scale dataset of the bytecodes of token contracts on Ethereum. The paths for these two datasets are: *dataset/groundtruth* and *dataset/large*.




