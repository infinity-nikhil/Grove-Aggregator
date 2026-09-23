# So in this one we are going to code the logic of grove aggregator into steps 

### Step 1 is: Access Control Module
Functions: onlyOwner modifier, transferOwnership, acceptOwnership
Logic: Two-step ownership transfer (current owner proposes → new owner accepts).

So int the 1st commit we talked about exchanging the owner nothing much complex so didn't care to care to explain the contract 

### Fee Configuration Module
Functions: setFee, setFeeWallet, _split, _skim

the name speaks for itslef. However what is this _split ?? 
it is the connection bridge between the setFee and setFeeWallet, basically sends funds from fees to wallet 

what is this _skim ?
It basically calculates how much is to charge for fee and rest using maths. 

Rest is explained in the code

You might think while codding split and skim that we are deailing with tokens and no payable and receive ? -> Only eath requires thos 

For us we will do every calculation with uint and then usdg.safeTransferFrom, usdg.safeTransfer etc used to bring the tokens....

### Pool Allow-List Module 
There are thousands of pool and poolKey but we want to trade only specific and trusted pool 
So, in this one we are going to add those specific pool 

### What is legs[] adding that 
Till date i didn't understand what is this Leg 
Just understand it does some kinda techincal stuffs 
Ooh i remeber now it basically works on like if we have huge order of swap, buy or sell then that could effect the price and the holder/buyer/seller will be in loss....so the core idea of leg is to devide those huge order to portion and use different pools so that price stays intacted with minimum slippage....

Meanwhile what is this _checkLegs(legs);
it's a guardrail called at the start of buy/sell/swap to make sure the caller-supplied routing instructions are valid and safe before any tokens move or swaps execute.
Just a copy paste typa thing 

### All the changes 
So, these changes might seems sudden but i am giving in which we have to understand the function don't try to understand it in a linear way the code base doesn't work that way 
1. Access Control Module
Functions: onlyOwner modifier, transferOwnership, acceptOwnership

2. Fee Configuration Module
Functions: setFee, setFeeWallet, _spl

3. Pool Allow-List Module
Functions: setV4PoolAllowed

4. Leg Validation Module
Function: _checkLegs (can be tested via a harness/wrapper since it's internal)

5. Permit2 Integration Module
Function: _pullPermit

6. Core Routing Engine
Function: _route (the piece that splits amountIn across legs and calls poolManager.unlock)

7. Unlock Callback (v4 Swap Execution)
Function: unlockCallback

8. Buy Flow
Functions: buy, buyWithPermit, _buyHeld

9. Sell Flow
Functions: sell, sellWithPermit, _sellHeld

10. Swap Flow (stock ↔ stock via USDG)
Functions: swap, swapWithPermit, _swapHeld\

11. Rescue / Emergency Module
Function: rescue

12. Reentrancy Guard (cross-cutting)

And there are some important updates regarding the latest uniswap import thing in the contract 

## Now here are some main feature that i am gonna introduce so that you can test in on local blockchain aka by forking anvil 
Run the series of command as follows 

### Start the blockchain 
anvil --fork-url https://rpc.mainnet.chain.robinhood.com

This will give you the accounts and there private key use them and also set the values in .env in owner and fee wallet

### Deploy the contract 
source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast 

This will give you the contract address of the contract 

### setV4PoolAllowed init
cast send $CONTRACT_ADDRESS \
  "setV4PoolAllowed((address,address,uint24,int24,address),bool)" \
  "(0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168,0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC,3000,60,0x0000000000000000000000000000000000000000)" \
  true \
  --rpc-url http://127.0.0.1:8545 \
  --private-key $PRIVATE_KEY

If you are wodering what are the data and the addresses ? -> Those are the pool details usdg/nvda

usdg - 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168
nvda - 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC 

The thing with tick spacing and fees and hooks we don't ususally use them for a swap but some how we are using it.....still have to research on it

### fund the wallet with usdg
Rem i told you that you get 10 wallets with eth and there pvt keys 
But it does not have usdg, to fund the wallet with usdg in order to perform the swap we use:

cast rpc anvil_dealERC20 \
  $wallet address with which you are performing swap \
  0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168 \
  1000000000

### To check if you have got the usdg or not 
cast call \
  0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168 \
  "balanceOf(address)(uint256)" \
  $wallet address with which you are performing swap

### You need to approve the contract so that it can pull the tokens out of your wallet
cast send $The currency address you want to allow \
  "approve(address,uint256)" \
  $Contract_Address \
  115792089237316195423570985008687907853269984665640564039457584007913129639935 \
  --private-key $privatekey \
  --rpc-url http://127.0.0.1:8545

$The currency address you want to allow - means ki which token you want to give/allow so that you can give that and receive the other usually it's usdg 

### Finally send the buy 
cast send $ContractAdrress$ \
  "buy(address,uint256,uint256,((address,address,uint24,int24,address),uint256)[],uint256)" \
  0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC \
  1000000000 \
  1 \
  "[((0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168,0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC,3000,60,0x0000000000000000000000000000000000000000),10000)]" \
  9999999999 \
  --private-key $Pvt_key \
  --rpc-url http://127.0.0.1:8545