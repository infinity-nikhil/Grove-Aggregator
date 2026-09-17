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