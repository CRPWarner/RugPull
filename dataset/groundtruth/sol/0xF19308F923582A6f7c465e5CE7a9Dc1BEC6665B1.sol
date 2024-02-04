// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./openzeppelin/security/ReentrancyGuard.sol";
import "./openzeppelin/token/ERC20/ERC20.sol";
import "./openzeppelin/interfaces/IERC165.sol";

import "../interfaces/ITitanOnBurn.sol";
import "../interfaces/ITITANX.sol";

import "../libs/calcFunctions.sol";

import "./GlobalInfo.sol";
import "./MintInfo.sol";
import "./StakeInfo.sol";
import "./BurnInfo.sol";
import "./OwnerInfo.sol";

//custom errors
error TitanX_InvalidAmount();
error TitanX_InsufficientBalance();
error TitanX_NotSupportedContract();
error TitanX_InsufficientProtocolFees();
error TitanX_FailedToSendAmount();
error TitanX_NotAllowed();
error TitanX_NoCycleRewardToClaim();
error TitanX_NoSharesExist();
error TitanX_EmptyUndistributeFees();
error TitanX_InvalidBurnRewardPercent();
error TitanX_InvalidBatchCount();
error TitanX_InvalidMintLadderInterval();
error TitanX_InvalidMintLadderRange();
error TitanX_MaxedWalletMints();
error TitanX_LPTokensHasMinted();
error TitanX_InvalidAddress();
error TitanX_InsufficientBurnAllowance();

/** @title Titan X */
contract TITANX is ERC20, ReentrancyGuard, GlobalInfo, MintInfo, StakeInfo, BurnInfo, OwnerInfo {
    /** Storage Variables*/
    /** @dev stores genesis wallet address */
    address private s_genesisAddress;
    /** @dev stores buy and burn contract address */
    address private s_buyAndBurnAddress;

    /** @dev tracks collected protocol fees until it is distributed */
    uint88 private s_undistributedEth;
    /** @dev tracks burn reward from distributeETH() until payout is triggered */
    uint88 private s_cycleBurnReward;

    /** @dev tracks if initial LP tokens has minted or not */
    InitialLPMinted private s_initialLPMinted;

    /** @dev trigger to turn on burn pool reward */
    BurnPoolEnabled private s_burnPoolEnabled;

    /** @dev tracks user + project burn mints allowance */
    mapping(address => mapping(address => uint256)) private s_allowanceBurnMints;

    /** @dev tracks user + project burn stakes allowance */
    mapping(address => mapping(address => uint256)) private s_allowanceBurnStakes;

    event ProtocolFeeRecevied(address indexed user, uint256 indexed day, uint256 indexed amount);
    event ETHDistributed(address indexed caller, uint256 indexed amount);
    event CyclePayoutTriggered(
        address indexed caller,
        uint256 indexed cycleNo,
        uint256 indexed reward,
        uint256 burnReward
    );
    event RewardClaimed(address indexed user, uint256 indexed reward);
    event ApproveBurnStakes(address indexed user, address indexed project, uint256 indexed amount);
    event ApproveBurnMints(address indexed user, address indexed project, uint256 indexed amount);

    constructor(address genesisAddress, address buyAndBurnAddress) ERC20("TITAN X", "TITANX") {
        if (genesisAddress == address(0)) revert TitanX_InvalidAddress();
        if (buyAndBurnAddress == address(0)) revert TitanX_InvalidAddress();
        s_genesisAddress = genesisAddress;
        s_buyAndBurnAddress = buyAndBurnAddress;
    }

    /**** Mint Functions *****/
    /** @notice create a new mint
     * @param mintPower 1 - 100
     * @param numOfDays mint length of 1 - 280
     */
    function startMint(
        uint256 mintPower,
        uint256 numOfDays
    ) external payable nonReentrant dailyUpdate {
        if (getUserLatestMintId(_msgSender()) + 1 > MAX_MINT_PER_WALLET)
            revert TitanX_MaxedWalletMints();
        uint256 gMintPower = getGlobalMintPower() + mintPower;
        uint256 currentTRank = getGlobalTRank() + 1;
        uint256 gMinting = getTotalMinting() +
            _startMint(
                _msgSender(),
                mintPower,
                numOfDays,
                getCurrentMintableTitan(),
                getCurrentMintPowerBonus(),
                getCurrentEAABonus(),
                getUserBurnAmplifierBonus(_msgSender()),
                gMintPower,
                currentTRank,
                getBatchMintCost(mintPower, 1, getCurrentMintCost())
            );
        _updateMintStats(currentTRank, gMintPower, gMinting);
        _protocolFees(mintPower, 1);
    }

    /** @notice create new mints in batch of up to 100 mints
     * @param mintPower 1 - 100
     * @param numOfDays mint length of 1 - 280
     * @param count 1 - 100
     */
    function batchMint(
        uint256 mintPower,
        uint256 numOfDays,
        uint256 count
    ) external payable nonReentrant dailyUpdate {
        if (count == 0 || count > MAX_BATCH_MINT_COUNT) revert TitanX_InvalidBatchCount();
        if (getUserLatestMintId(_msgSender()) + count > MAX_MINT_PER_WALLET)
            revert TitanX_MaxedWalletMints();

        _startBatchMint(
            _msgSender(),
            mintPower,
            numOfDays,
            getCurrentMintableTitan(),
            getCurrentMintPowerBonus(),
            getCurrentEAABonus(),
            getUserBurnAmplifierBonus(_msgSender()),
            count,
            getBatchMintCost(mintPower, 1, getCurrentMintCost()) //only need 1 mint cost for all mints
        );
        _protocolFees(mintPower, count);
    }

    /** @notice create new mints in ladder up to 100 mints
     * @param mintPower 1 - 100
     * @param minDay minimum mint length
     * @param maxDay maximum mint lenght
     * @param dayInterval day increase from previous mint length
     * @param countPerInterval how many mints per mint length
     */
    function batchMintLadder(
        uint256 mintPower,
        uint256 minDay,
        uint256 maxDay,
        uint256 dayInterval,
        uint256 countPerInterval
    ) external payable nonReentrant dailyUpdate {
        if (dayInterval == 0) revert TitanX_InvalidMintLadderInterval();
        if (maxDay < minDay || minDay == 0 || maxDay > MAX_MINT_LENGTH)
            revert TitanX_InvalidMintLadderRange();

        uint256 count = getBatchMintLadderCount(minDay, maxDay, dayInterval, countPerInterval);
        if (count == 0 || count > MAX_BATCH_MINT_COUNT) revert TitanX_InvalidBatchCount();
        if (getUserLatestMintId(_msgSender()) + count > MAX_MINT_PER_WALLET)
            revert TitanX_MaxedWalletMints();

        uint256 mintCost = getBatchMintCost(mintPower, 1, getCurrentMintCost()); //only need 1 mint cost for all mints

        _startbatchMintLadder(
            _msgSender(),
            mintPower,
            minDay,
            maxDay,
            dayInterval,
            countPerInterval,
            getCurrentMintableTitan(),
            getCurrentMintPowerBonus(),
            getCurrentEAABonus(),
            getUserBurnAmplifierBonus(_msgSender()),
            mintCost
        );
        _protocolFees(mintPower, count);
    }

    /** @notice claim a matured mint
     * @param id mint id
     */
    function claimMint(uint256 id) external dailyUpdate nonReentrant {
        _mintReward(_claimMint(_msgSender(), id, MintAction.CLAIM));
    }

    /** @notice batch claim matured mint of up to 100 claims per run
     */
    function batchClaimMint() external dailyUpdate nonReentrant {
        _mintReward(_batchClaimMint(_msgSender()));
    }

    /**** Stake Functions *****/
    /** @notice start a new stake
     * @param amount titan amount
     * @param numOfDays stake length
     */
    function startStake(uint256 amount, uint256 numOfDays) external dailyUpdate nonReentrant {
        if (balanceOf(_msgSender()) < amount) revert TitanX_InsufficientBalance();

        _burn(_msgSender(), amount);
        _initFirstSharesCycleIndex(
            _msgSender(),
            _startStake(
                _msgSender(),
                amount,
                numOfDays,
                getCurrentShareRate(),
                getCurrentContractDay(),
                getGlobalPayoutTriggered()
            )
        );
    }

    /** @notice end a stake
     * @param id stake id
     */
    function endStake(uint256 id) external dailyUpdate nonReentrant {
        _mint(
            _msgSender(),
            _endStake(
                _msgSender(),
                id,
                getCurrentContractDay(),
                StakeAction.END,
                StakeAction.END_OWN,
                getGlobalPayoutTriggered()
            )
        );
    }

    /** @notice end a stake for others
     * @param user wallet address
     * @param id stake id
     */
    function endStakeForOthers(address user, uint256 id) external dailyUpdate nonReentrant {
        _mint(
            user,
            _endStake(
                user,
                id,
                getCurrentContractDay(),
                StakeAction.END,
                StakeAction.END_OTHER,
                getGlobalPayoutTriggered()
            )
        );
    }

    /** @notice distribute the collected protocol fees into different pools/payouts
     * automatically send the incentive fee to caller, buyAndBurnFunds to BuyAndBurn contract, and genesis wallet
     */
    function distributeETH() external dailyUpdate nonReentrant {
        (uint256 incentiveFee, uint256 buyAndBurnFunds, uint256 genesisWallet) = _distributeETH();
        _sendFunds(incentiveFee, buyAndBurnFunds, genesisWallet);
    }

    /** @notice trigger cylce payouts for day 8, 28, 90, 369, 888 including the burn reward cycle 28
     * As long as the cycle has met its maturiy day (eg. Cycle8 is day 8), payout can be triggered in any day onwards
     */
    function triggerPayouts() external dailyUpdate nonReentrant {
        uint256 globalActiveShares = getGlobalShares() - getGlobalExpiredShares();
        if (globalActiveShares < 1) revert TitanX_NoSharesExist();

        uint256 incentiveFee;
        uint256 buyAndBurnFunds;
        uint256 genesisWallet;
        if (s_undistributedEth != 0)
            (incentiveFee, buyAndBurnFunds, genesisWallet) = _distributeETH();

        uint256 currentContractDay = getCurrentContractDay();
        PayoutTriggered isTriggered = PayoutTriggered.NO;
        _triggerCyclePayout(DAY8, globalActiveShares, currentContractDay) == PayoutTriggered.YES &&
            isTriggered == PayoutTriggered.NO
            ? isTriggered = PayoutTriggered.YES
            : isTriggered;
        _triggerCyclePayout(DAY28, globalActiveShares, currentContractDay) == PayoutTriggered.YES &&
            isTriggered == PayoutTriggered.NO
            ? isTriggered = PayoutTriggered.YES
            : isTriggered;
        _triggerCyclePayout(DAY90, globalActiveShares, currentContractDay) == PayoutTriggered.YES &&
            isTriggered == PayoutTriggered.NO
            ? isTriggered = PayoutTriggered.YES
            : isTriggered;
        _triggerCyclePayout(DAY369, globalActiveShares, currentContractDay) ==
            PayoutTriggered.YES &&
            isTriggered == PayoutTriggered.NO
            ? isTriggered = PayoutTriggered.YES
            : isTriggered;
        _triggerCyclePayout(DAY888, globalActiveShares, currentContractDay) ==
            PayoutTriggered.YES &&
            isTriggered == PayoutTriggered.NO
            ? isTriggered = PayoutTriggered.YES
            : isTriggered;

        if (isTriggered == PayoutTriggered.YES) {
            if (getGlobalPayoutTriggered() == PayoutTriggered.NO) _setGlobalPayoutTriggered();
        }

        if (incentiveFee != 0) _sendFunds(incentiveFee, buyAndBurnFunds, genesisWallet);
    }

    /** @notice claim all user available ETH payouts in one call */
    function claimUserAvailableETHPayouts() external dailyUpdate nonReentrant {
        uint256 reward = _claimCyclePayout(DAY8, PayoutClaim.SHARES);
        reward += _claimCyclePayout(DAY28, PayoutClaim.SHARES);
        reward += _claimCyclePayout(DAY90, PayoutClaim.SHARES);
        reward += _claimCyclePayout(DAY369, PayoutClaim.SHARES);
        reward += _claimCyclePayout(DAY888, PayoutClaim.SHARES);

        if (reward == 0) revert TitanX_NoCycleRewardToClaim();
        _sendViaCall(payable(_msgSender()), reward);
        emit RewardClaimed(_msgSender(), reward);
    }

    /** @notice claim all user available burn rewards in one call */
    function claimUserAvailableETHBurnPool() external dailyUpdate nonReentrant {
        uint256 reward = _claimCyclePayout(DAY28, PayoutClaim.BURN);
        if (reward == 0) revert TitanX_NoCycleRewardToClaim();
        _sendViaCall(payable(_msgSender()), reward);
        emit RewardClaimed(_msgSender(), reward);
    }

    /** @notice Set BuyAndBurn Contract Address - able to change to new contract that supports UniswapV4+
     * Only owner can call this function
     * @param contractAddress BuyAndBurn contract address
     */
    function setBuyAndBurnContractAddress(address contractAddress) external onlyOwner {
        if (contractAddress == address(0)) revert TitanX_InvalidAddress();
        s_buyAndBurnAddress = contractAddress;
    }

    /** @notice enable burn pool to start accumulate reward. Only owner can call this function. */
    function enableBurnPoolReward() external onlyOwner {
        s_burnPoolEnabled = BurnPoolEnabled.TRUE;
    }

    /** @notice Set to new genesis wallet. Only genesis wallet can call this function
     * @param newAddress new genesis wallet address
     */
    function setNewGenesisAddress(address newAddress) external {
        if (_msgSender() != s_genesisAddress) revert TitanX_NotAllowed();
        if (newAddress == address(0)) revert TitanX_InvalidAddress();
        s_genesisAddress = newAddress;
    }

    /** @notice mint initial LP tokens. Only BuyAndBurn contract set by genesis wallet can call this function
     */
    function mintLPTokens() external {
        if (_msgSender() != s_buyAndBurnAddress) revert TitanX_NotAllowed();
        if (s_initialLPMinted == InitialLPMinted.YES) revert TitanX_LPTokensHasMinted();
        s_initialLPMinted = InitialLPMinted.YES;
        _mint(s_buyAndBurnAddress, INITAL_LP_TOKENS);
    }

    /** @notice burn all BuyAndBurn contract Titan */
    function burnLPTokens() external dailyUpdate {
        _burn(s_buyAndBurnAddress, balanceOf(s_buyAndBurnAddress));
    }

    //private functions
    /** @dev mint reward to user and 1% to genesis wallet
     * @param reward titan amount
     */
    function _mintReward(uint256 reward) private {
        _mint(_msgSender(), reward);
        _mint(s_genesisAddress, (reward * 800) / PERCENT_BPS);
    }

    /** @dev send ETH to respective parties
     * @param incentiveFee fees for caller to run distributeETH()
     * @param buyAndBurnFunds funds for buy and burn
     * @param genesisWalletFunds funds for genesis wallet
     */
    function _sendFunds(
        uint256 incentiveFee,
        uint256 buyAndBurnFunds,
        uint256 genesisWalletFunds
    ) private {
        _sendViaCall(payable(_msgSender()), incentiveFee);
        _sendViaCall(payable(s_genesisAddress), genesisWalletFunds);
        _sendViaCall(payable(s_buyAndBurnAddress), buyAndBurnFunds);
    }

    /** @dev calculation to distribute collected protocol fees into different pools/parties */
    function _distributeETH()
        private
        returns (uint256 incentiveFee, uint256 buyAndBurnFunds, uint256 genesisWallet)
    {
        uint256 accumulatedFees = s_undistributedEth;
        if (accumulatedFees == 0) revert TitanX_EmptyUndistributeFees();
        s_undistributedEth = 0;
        emit ETHDistributed(_msgSender(), accumulatedFees);

        incentiveFee = (accumulatedFees * INCENTIVE_FEE_PERCENT) / INCENTIVE_FEE_PERCENT_BASE; //0.01%
        accumulatedFees -= incentiveFee;

        buyAndBurnFunds = (accumulatedFees * PERCENT_TO_BUY_AND_BURN) / PERCENT_BPS;
        uint256 cylceBurnReward = (accumulatedFees * PERCENT_TO_BURN_PAYOUTS) / PERCENT_BPS;
        genesisWallet = (accumulatedFees * PERCENT_TO_GENESIS) / PERCENT_BPS;
        uint256 cycleRewardPool = accumulatedFees -
            buyAndBurnFunds -
            cylceBurnReward -
            genesisWallet;

        if (s_burnPoolEnabled == BurnPoolEnabled.TRUE) s_cycleBurnReward += uint88(cylceBurnReward);
        else buyAndBurnFunds += cylceBurnReward;

        //cycle payout
        if (cycleRewardPool != 0) {
            uint256 cycle8Reward = (cycleRewardPool * CYCLE_8_PERCENT) / PERCENT_BPS;
            uint256 cycle28Reward = (cycleRewardPool * CYCLE_28_PERCENT) / PERCENT_BPS;
            uint256 cycle90Reward = (cycleRewardPool * CYCLE_90_PERCENT) / PERCENT_BPS;
            uint256 cycle369Reward = (cycleRewardPool * CYCLE_369_PERCENT) / PERCENT_BPS;
            _setCyclePayoutPool(DAY8, cycle8Reward);
            _setCyclePayoutPool(DAY28, cycle28Reward);
            _setCyclePayoutPool(DAY90, cycle90Reward);
            _setCyclePayoutPool(DAY369, cycle369Reward);
            _setCyclePayoutPool(
                DAY888,
                cycleRewardPool - cycle8Reward - cycle28Reward - cycle90Reward - cycle369Reward
            );
        }
    }

    /** @dev calcualte required protocol fees, and return the balance (if any)
     * @param mintPower mint power 1-100
     * @param count how many mints
     */
    function _protocolFees(uint256 mintPower, uint256 count) private {
        uint256 protocolFee;

        protocolFee = getBatchMintCost(mintPower, count, getCurrentMintCost());
        if (msg.value < protocolFee) revert TitanX_InsufficientProtocolFees();

        uint256 feeBalance;
        s_undistributedEth += uint88(protocolFee);
        feeBalance = msg.value - protocolFee;

        if (feeBalance != 0) {
            _sendViaCall(payable(_msgSender()), feeBalance);
        }

        emit ProtocolFeeRecevied(_msgSender(), getCurrentContractDay(), protocolFee);
    }

    /** @dev calculate payouts for each cycle day tracked by cycle index
     * @param cycleNo cylce day 8, 28, 90, 369, 888
     * @param globalActiveShares global active shares
     * @param currentContractDay current contract day
     * @return triggered is payout triggered succesfully
     */
    function _triggerCyclePayout(
        uint256 cycleNo,
        uint256 globalActiveShares,
        uint256 currentContractDay
    ) private returns (PayoutTriggered triggered) {
        //check against cylce payout maturity day
        if (currentContractDay < getNextCyclePayoutDay(cycleNo)) return PayoutTriggered.NO;

        //update the next cycle payout day regardless of payout triggered succesfully or not
        _setNextCyclePayoutDay(cycleNo);

        uint256 reward = getCyclePayoutPool(cycleNo);
        if (reward == 0) return PayoutTriggered.NO;

        //calculate cycle reward per share and get new cycle Index
        uint256 cycleIndex = _calculateCycleRewardPerShare(cycleNo, reward, globalActiveShares);

        //calculate burn reward if cycle is 28
        uint256 totalCycleBurn = getCycleBurnTotal(cycleIndex);
        uint256 burnReward;
        if (cycleNo == DAY28 && totalCycleBurn != 0) {
            burnReward = s_cycleBurnReward;
            if (burnReward != 0) {
                s_cycleBurnReward = 0;
                _calculateCycleBurnRewardPerToken(cycleIndex, burnReward, totalCycleBurn);
            }
        }

        emit CyclePayoutTriggered(_msgSender(), cycleNo, reward, burnReward);

        return PayoutTriggered.YES;
    }

    /** @dev calculate user reward with specified cycle day and claim type (shares/burn) and update user's last claim cycle index
     * @param cycleNo cycle day 8, 28, 90, 369, 888
     * @param payoutClaim claim type - (Shares=0/Burn=1)
     */
    function _claimCyclePayout(uint256 cycleNo, PayoutClaim payoutClaim) private returns (uint256) {
        (
            uint256 reward,
            uint256 userClaimCycleIndex,
            uint256 userClaimSharesIndex,
            uint256 userClaimBurnCycleIndex
        ) = _calculateUserCycleReward(_msgSender(), cycleNo, payoutClaim);

        if (payoutClaim == PayoutClaim.SHARES)
            _updateUserClaimIndexes(
                _msgSender(),
                cycleNo,
                userClaimCycleIndex,
                userClaimSharesIndex
            );
        if (payoutClaim == PayoutClaim.BURN) {
            _updateUserBurnCycleClaimIndex(_msgSender(), cycleNo, userClaimBurnCycleIndex);
        }

        return reward;
    }

    /** @dev burn liquid Titan through other project.
     * called by other contracts for proof of burn 2.0 with up to 8% for both builder fee and user rebate
     * @param user user address
     * @param amount liquid titan amount
     * @param userRebatePercentage percentage for user rebate in liquid titan (0 - 8)
     * @param rewardPaybackPercentage percentage for builder fee in liquid titan (0 - 8)
     * @param rewardPaybackAddress builder can opt to receive fee in another address
     */
    function _burnLiquidTitan(
        address user,
        uint256 amount,
        uint256 userRebatePercentage,
        uint256 rewardPaybackPercentage,
        address rewardPaybackAddress
    ) private {
        if (amount == 0) revert TitanX_InvalidAmount();
        if (balanceOf(user) < amount) revert TitanX_InsufficientBalance();
        _spendAllowance(user, _msgSender(), amount);
        _burnbefore(userRebatePercentage, rewardPaybackPercentage);
        _burn(user, amount);
        _burnAfter(
            user,
            amount,
            userRebatePercentage,
            rewardPaybackPercentage,
            rewardPaybackAddress,
            BurnSource.LIQUID
        );
    }

    /** @dev burn stake through other project.
     * called by other contracts for proof of burn 2.0 with up to 8% for both builder fee and user rebate
     * @param user user address
     * @param id stake id
     * @param userRebatePercentage percentage for user rebate in liquid titan (0 - 8)
     * @param rewardPaybackPercentage percentage for builder fee in liquid titan (0 - 8)
     * @param rewardPaybackAddress builder can opt to receive fee in another address
     */
    function _burnStake(
        address user,
        uint256 id,
        uint256 userRebatePercentage,
        uint256 rewardPaybackPercentage,
        address rewardPaybackAddress
    ) private {
        _spendBurnStakeAllowance(user);
        _burnbefore(userRebatePercentage, rewardPaybackPercentage);
        _burnAfter(
            user,
            _endStake(
                user,
                id,
                getCurrentContractDay(),
                StakeAction.BURN,
                StakeAction.END_OWN,
                getGlobalPayoutTriggered()
            ),
            userRebatePercentage,
            rewardPaybackPercentage,
            rewardPaybackAddress,
            BurnSource.STAKE
        );
    }

    /** @dev burn mint through other project.
     * called by other contracts for proof of burn 2.0
     * burn mint has no builder reward and no user rebate
     * @param user user address
     * @param id mint id
     */
    function _burnMint(address user, uint256 id) private {
        _spendBurnMintAllowance(user);
        _burnbefore(0, 0);
        uint256 amount = _claimMint(user, id, MintAction.BURN);
        _mint(s_genesisAddress, (amount * 800) / PERCENT_BPS);
        _burnAfter(user, amount, 0, 0, _msgSender(), BurnSource.MINT);
    }

    /** @dev perform checks before burning starts.
     * check reward percentage and check if called by supported contract
     * @param userRebatePercentage percentage for user rebate
     * @param rewardPaybackPercentage percentage for builder fee
     */
    function _burnbefore(
        uint256 userRebatePercentage,
        uint256 rewardPaybackPercentage
    ) private view {
        if (rewardPaybackPercentage + userRebatePercentage > MAX_BURN_REWARD_PERCENT)
            revert TitanX_InvalidBurnRewardPercent();

        //Only supported contracts is allowed to call this function
        if (
            !IERC165(_msgSender()).supportsInterface(IERC165.supportsInterface.selector) ||
            !IERC165(_msgSender()).supportsInterface(type(ITitanOnBurn).interfaceId)
        ) revert TitanX_NotSupportedContract();
    }

    /** @dev update burn stats and mint reward to builder or user if applicable
     * @param user user address
     * @param amount titan amount burned
     * @param userRebatePercentage percentage for user rebate in liquid titan (0 - 8)
     * @param rewardPaybackPercentage percentage for builder fee in liquid titan (0 - 8)
     * @param rewardPaybackAddress builder can opt to receive fee in another address
     * @param source liquid/mint/stake
     */
    function _burnAfter(
        address user,
        uint256 amount,
        uint256 userRebatePercentage,
        uint256 rewardPaybackPercentage,
        address rewardPaybackAddress,
        BurnSource source
    ) private {
        uint256 index = getCurrentCycleIndex(DAY28) + 1;
        /** set to the latest cylceIndex + 1 for fresh wallet
         * same concept as _initFirstSharesCycleIndex, refer to its dev comment  */
        if (getUserBurnTotal(user) == 0) _updateUserBurnCycleClaimIndex(user, DAY28, index);
        _updateBurnAmount(user, _msgSender(), amount, index, source);

        uint256 devFee;
        uint256 userRebate;
        if (rewardPaybackPercentage != 0)
            devFee = (amount * rewardPaybackPercentage * PERCENT_BPS) / (100 * PERCENT_BPS);
        if (userRebatePercentage != 0)
            userRebate = (amount * userRebatePercentage * PERCENT_BPS) / (100 * PERCENT_BPS);

        if (devFee != 0) _mint(rewardPaybackAddress, devFee);
        if (userRebate != 0) _mint(user, userRebate);

        ITitanOnBurn(_msgSender()).onBurn(user, amount);
    }

    /** @dev Recommended method to use to send native coins.
     * @param to receiving address.
     * @param amount in wei.
     */
    function _sendViaCall(address payable to, uint256 amount) private {
        if (to == address(0)) revert TitanX_InvalidAddress();
        (bool sent, ) = to.call{value: amount}("");
        if (!sent) revert TitanX_FailedToSendAmount();
    }

    /** @dev reduce user's allowance for caller (spender/project) by 1 (burn 1 stake at a time)
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     * @param user user address
     */
    function _spendBurnStakeAllowance(address user) private {
        uint256 currentAllowance = allowanceBurnStakes(user, _msgSender());
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance == 0) revert TitanX_InsufficientBurnAllowance();
            --s_allowanceBurnStakes[user][_msgSender()];
        }
    }

    /** @dev reduce user's allowance for caller (spender/project) by 1 (burn 1 mint at a time)
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     * @param user user address
     */
    function _spendBurnMintAllowance(address user) private {
        uint256 currentAllowance = allowanceBurnMints(user, _msgSender());
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance == 0) revert TitanX_InsufficientBurnAllowance();
            --s_allowanceBurnMints[user][_msgSender()];
        }
    }

    //Views
    /** @dev calculate user payout reward with specified cycle day and claim type (shares/burn).
     * it loops through all the unclaimed cylce index until the latest cycle index
     * @param user user address
     * @param cycleNo cycle day 8, 28, 90, 369, 888
     * @param payoutClaim claim type (Shares=0/Burn=1)
     * @return rewards calculated reward
     * @return userClaimCycleIndex last claim cycle index
     * @return userClaimSharesIndex last claim shares index
     * @return userClaimBurnCycleIndex last claim burn cycle index
     */
    function _calculateUserCycleReward(
        address user,
        uint256 cycleNo,
        PayoutClaim payoutClaim
    )
        private
        view
        returns (
            uint256 rewards,
            uint256 userClaimCycleIndex,
            uint256 userClaimSharesIndex,
            uint256 userClaimBurnCycleIndex
        )
    {
        uint256 cycleMaxIndex = getCurrentCycleIndex(cycleNo);

        if (payoutClaim == PayoutClaim.SHARES) {
            (userClaimCycleIndex, userClaimSharesIndex) = getUserLastClaimIndex(user, cycleNo);
            uint256 sharesMaxIndex = getUserLatestShareIndex(user);

            for (uint256 i = userClaimCycleIndex; i <= cycleMaxIndex; i++) {
                (uint256 payoutPerShare, uint256 payoutDay) = getPayoutPerShare(cycleNo, i);
                uint256 shares;

                //loop shares indexes to find the last updated shares before/same triggered payout day
                for (uint256 j = userClaimSharesIndex; j <= sharesMaxIndex; j++) {
                    if (getUserActiveSharesDay(user, j) <= payoutDay)
                        shares = getUserActiveShares(user, j);
                    else break;

                    userClaimSharesIndex = j;
                }

                if (payoutPerShare != 0 && shares != 0) {
                    //reward has 18 decimals scaling, so here divide by 1e18
                    rewards += (shares * payoutPerShare) / SCALING_FACTOR_1e18;
                }

                userClaimCycleIndex = i + 1;
            }
        } else if (cycleNo == DAY28 && payoutClaim == PayoutClaim.BURN) {
            userClaimBurnCycleIndex = getUserLastBurnClaimIndex(user, cycleNo);
            for (uint256 i = userClaimBurnCycleIndex; i <= cycleMaxIndex; i++) {
                uint256 burnPayoutPerToken = getCycleBurnPayoutPerToken(i);
                rewards += (burnPayoutPerToken != 0)
                    ? (burnPayoutPerToken * _getUserCycleBurnTotal(user, i)) / SCALING_FACTOR_1e18
                    : 0;
                userClaimBurnCycleIndex = i + 1;
            }
        }
    }

    /** @notice get contract ETH balance
     * @return balance eth balance
     */
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /** @notice get undistributed ETH balance
     * @return amount eth amount
     */
    function getUndistributedEth() public view returns (uint256) {
        return s_undistributedEth;
    }

    /** @notice get user ETH payout for all cycles
     * @param user user address
     * @return reward total reward
     */
    function getUserETHClaimableTotal(address user) public view returns (uint256 reward) {
        uint256 _reward;
        (_reward, , , ) = _calculateUserCycleReward(user, DAY8, PayoutClaim.SHARES);
        reward += _reward;
        (_reward, , , ) = _calculateUserCycleReward(user, DAY28, PayoutClaim.SHARES);
        reward += _reward;
        (_reward, , , ) = _calculateUserCycleReward(user, DAY90, PayoutClaim.SHARES);
        reward += _reward;
        (_reward, , , ) = _calculateUserCycleReward(user, DAY369, PayoutClaim.SHARES);
        reward += _reward;
        (_reward, , , ) = _calculateUserCycleReward(user, DAY888, PayoutClaim.SHARES);
        reward += _reward;
    }

    /** @notice get user burn reward ETH payout
     * @param user user address
     * @return reward burn reward
     */
    function getUserBurnPoolETHClaimableTotal(address user) public view returns (uint256 reward) {
        (reward, , , ) = _calculateUserCycleReward(user, DAY28, PayoutClaim.BURN);
    }

    /** @notice get total penalties from mint and stake
     * @return amount total penalties
     */
    function getTotalPenalties() public view returns (uint256) {
        return getTotalMintPenalty() + getTotalStakePenalty();
    }

    /** @notice get burn pool reward
     * @return reward burn pool reward
     */
    function getCycleBurnPool() public view returns (uint256) {
        return s_cycleBurnReward;
    }

    /** @notice get user current burn cycle percentage
     * @return percentage in 18 decimals
     */
    function getCurrentUserBurnCyclePercentage() public view returns (uint256) {
        uint256 index = getCurrentCycleIndex(DAY28) + 1;
        uint256 cycleBurnTotal = getCycleBurnTotal(index);
        return
            cycleBurnTotal == 0
                ? 0
                : (_getUserCycleBurnTotal(_msgSender(), index) * 100 * SCALING_FACTOR_1e18) /
                    cycleBurnTotal;
    }

    /** @notice get user current cycle total titan burned
     * @param user user address
     * @return burnTotal total titan burned in curreny burn cycle
     */
    function getUserCycleBurnTotal(address user) public view returns (uint256) {
        return _getUserCycleBurnTotal(user, getCurrentCycleIndex(DAY28) + 1);
    }

    function isBurnPoolEnabled() public view returns (BurnPoolEnabled) {
        return s_burnPoolEnabled;
    }

    /** @notice returns user's burn stakes allowance of a project
     * @param user user address
     * @param spender project address
     */
    function allowanceBurnStakes(address user, address spender) public view returns (uint256) {
        return s_allowanceBurnStakes[user][spender];
    }

    /** @notice returns user's burn mints allowance of a project
     * @param user user address
     * @param spender project address
     */
    function allowanceBurnMints(address user, address spender) public view returns (uint256) {
        return s_allowanceBurnMints[user][spender];
    }

    //Public functions for devs to intergrate with Titan
    /** @notice allow anyone to sync dailyUpdate manually */
    function manualDailyUpdate() public dailyUpdate {}

    /** @notice Burn Titan tokens and creates Proof-Of-Burn record to be used by connected DeFi and fee is paid to specified address
     * @param user user address
     * @param amount titan amount
     * @param userRebatePercentage percentage for user rebate in liquid titan (0 - 8)
     * @param rewardPaybackPercentage percentage for builder fee in liquid titan (0 - 8)
     * @param rewardPaybackAddress builder can opt to receive fee in another address
     */
    function burnTokensToPayAddress(
        address user,
        uint256 amount,
        uint256 userRebatePercentage,
        uint256 rewardPaybackPercentage,
        address rewardPaybackAddress
    ) public dailyUpdate nonReentrant {
        _burnLiquidTitan(
            user,
            amount,
            userRebatePercentage,
            rewardPaybackPercentage,
            rewardPaybackAddress
        );
    }

    /** @notice Burn Titan tokens and creates Proof-Of-Burn record to be used by connected DeFi and fee is paid to specified address
     * @param user user address
     * @param amount titan amount
     * @param userRebatePercentage percentage for user rebate in liquid titan (0 - 8)
     * @param rewardPaybackPercentage percentage for builder fee in liquid titan (0 - 8)
     */
    function burnTokens(
        address user,
        uint256 amount,
        uint256 userRebatePercentage,
        uint256 rewardPaybackPercentage
    ) public dailyUpdate nonReentrant {
        _burnLiquidTitan(user, amount, userRebatePercentage, rewardPaybackPercentage, _msgSender());
    }

    /** @notice allows user to burn liquid titan directly from contract
     * @param amount titan amount
     */
    function userBurnTokens(uint256 amount) public dailyUpdate nonReentrant {
        if (amount == 0) revert TitanX_InvalidAmount();
        if (balanceOf(_msgSender()) < amount) revert TitanX_InsufficientBalance();
        _burn(_msgSender(), amount);
        _updateBurnAmount(
            _msgSender(),
            address(0),
            amount,
            getCurrentCycleIndex(DAY28) + 1,
            BurnSource.LIQUID
        );
    }

    /** @notice Burn stake and creates Proof-Of-Burn record to be used by connected DeFi and fee is paid to specified address
     * @param user user address
     * @param id stake id
     * @param userRebatePercentage percentage for user rebate in liquid titan (0 - 8)
     * @param rewardPaybackPercentage percentage for builder fee in liquid titan (0 - 8)
     * @param rewardPaybackAddress builder can opt to receive fee in another address
     */
    function burnStakeToPayAddress(
        address user,
        uint256 id,
        uint256 userRebatePercentage,
        uint256 rewardPaybackPercentage,
        address rewardPaybackAddress
    ) public dailyUpdate nonReentrant {
        _burnStake(user, id, userRebatePercentage, rewardPaybackPercentage, rewardPaybackAddress);
    }

    /** @notice Burn stake and creates Proof-Of-Burn record to be used by connected DeFi and fee is paid to project contract address
     * @param user user address
     * @param id stake id
     * @param userRebatePercentage percentage for user rebate in liquid titan (0 - 8)
     * @param rewardPaybackPercentage percentage for builder fee in liquid titan (0 - 8)
     */
    function burnStake(
        address user,
        uint256 id,
        uint256 userRebatePercentage,
        uint256 rewardPaybackPercentage
    ) public dailyUpdate nonReentrant {
        _burnStake(user, id, userRebatePercentage, rewardPaybackPercentage, _msgSender());
    }

    /** @notice allows user to burn stake directly from contract
     * @param id stake id
     */
    function userBurnStake(uint256 id) public dailyUpdate nonReentrant {
        _updateBurnAmount(
            _msgSender(),
            address(0),
            _endStake(
                _msgSender(),
                id,
                getCurrentContractDay(),
                StakeAction.BURN,
                StakeAction.END_OWN,
                getGlobalPayoutTriggered()
            ),
            getCurrentCycleIndex(DAY28) + 1,
            BurnSource.STAKE
        );
    }

    /** @notice Burn mint and creates Proof-Of-Burn record to be used by connected DeFi.
     * Burn mint has no project reward or user rebate
     * @param user user address
     * @param id mint id
     */
    function burnMint(address user, uint256 id) public dailyUpdate nonReentrant {
        _burnMint(user, id);
    }

    /** @notice allows user to burn mint directly from contract
     * @param id mint id
     */
    function userBurnMint(uint256 id) public dailyUpdate nonReentrant {
        _updateBurnAmount(
            _msgSender(),
            address(0),
            _claimMint(_msgSender(), id, MintAction.BURN),
            getCurrentCycleIndex(DAY28) + 1,
            BurnSource.MINT
        );
    }

    /** @notice Sets `amount` as the allowance of `spender` over the caller's (user) mints.
     * @param spender contract address
     * @param amount allowance amount
     */
    function approveBurnMints(address spender, uint256 amount) public returns (bool) {
        if (spender == address(0)) revert TitanX_InvalidAddress();
        s_allowanceBurnMints[_msgSender()][spender] = amount;
        emit ApproveBurnMints(_msgSender(), spender, amount);
        return true;
    }

    /** @notice Sets `amount` as the allowance of `spender` over the caller's (user) stakes.
     * @param spender contract address
     * @param amount allowance amount
     */
    function approveBurnStakes(address spender, uint256 amount) public returns (bool) {
        if (spender == address(0)) revert TitanX_InvalidAddress();
        s_allowanceBurnStakes[_msgSender()][spender] = amount;
        emit ApproveBurnStakes(_msgSender(), spender, amount);
        return true;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./openzeppelin/utils/Context.sol";

error TitanX_NotOnwer();

abstract contract OwnerInfo is Context {
    address private s_owner;

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        s_owner = _msgSender();
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (s_owner != _msgSender()) revert TitanX_NotOnwer();
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        _setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        s_owner = newOwner;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../libs/constant.sol";
import "../libs/enum.sol";

/**
 * @title BurnInfo
 * @dev this contract is meant to be inherited into main contract
 * @notice It has the variables and functions specifically for tracking burn amount and reward
 */

abstract contract BurnInfo {
    //Variables
    //track the total titan burn amount
    uint256 private s_totalTitanBurned;

    //mappings
    //track wallet address -> total titan burn amount
    mapping(address => uint256) private s_userBurnAmount;
    //track contract/project address -> total titan burn amount
    mapping(address => uint256) private s_project_BurnAmount;
    //track contract/project address, wallet address -> total titan burn amount
    mapping(address => mapping(address => uint256)) private s_projectUser_BurnAmount;

    /** @dev cycleIndex is increased when triggerPayouts() was called successfully
     * so we track data in current cycleIndex + 1 which means tracking for the next cycle payout
     * cycleIndex is passed from the TITANX contract during function call
     */
    //track cycleIndex + 1 -> total burn amount
    mapping(uint256 => uint256) private s_cycle28TotalBurn;
    //track address, cycleIndex + 1 -> total burn amount
    mapping(address => mapping(uint256 => uint256)) private s_userCycle28TotalBurn;
    //track cycleIndex + 1 -> burn payout per token
    mapping(uint256 => uint256) private s_cycle28BurnPayoutPerToken;

    //events
    /** @dev log user burn titan event
     * project can be address(0) if user burns Titan directly from Titan contract
     * burnPoolCycleIndex is the cycle 28 index, which reuse the same index as Day 28 cycle index
     * titanSource 0=Liquid, 1=Mint, 2=Stake
     */
    event TitanBurned(
        address indexed user,
        address indexed project,
        uint256 indexed burnPoolCycleIndex,
        uint256 amount,
        BurnSource titanSource
    );

    //functions
    /** @dev update the burn amount in each 28-cylce for user and project (if any)
     * @param user wallet address
     * @param project contract address
     * @param amount titan amount burned
     * @param cycleIndex cycle payout triggered index
     */
    function _updateBurnAmount(
        address user,
        address project,
        uint256 amount,
        uint256 cycleIndex,
        BurnSource source
    ) internal {
        s_userBurnAmount[user] += amount;
        s_totalTitanBurned += amount;
        s_cycle28TotalBurn[cycleIndex] += amount;
        s_userCycle28TotalBurn[user][cycleIndex] += amount;

        if (project != address(0)) {
            s_project_BurnAmount[project] += amount;
            s_projectUser_BurnAmount[project][user] += amount;
        }

        emit TitanBurned(user, project, cycleIndex, amount, source);
    }

    /**
     * @dev calculate burn reward per titan burned based on total reward / total titan burned in current cycle
     * @param cycleIndex wallet address
     * @param reward contract address
     * @param cycleBurnAmount titan amount burned
     */
    function _calculateCycleBurnRewardPerToken(
        uint256 cycleIndex,
        uint256 reward,
        uint256 cycleBurnAmount
    ) internal {
        //add 18 decimals to reward for better precision in calculation
        s_cycle28BurnPayoutPerToken[cycleIndex] = (reward * SCALING_FACTOR_1e18) / cycleBurnAmount;
    }

    /** @dev returned value is in 18 decimals, need to divide it by 1e18 and 100 (percentage) when using this value for reward calculation
     * The burn amplifier percentage is applied to all future mints. Capped at MAX_BURN_AMP_PERCENT (8%)
     * @param user wallet address
     * @return percentage returns percentage value in 18 decimals
     */
    function getUserBurnAmplifierBonus(address user) public view returns (uint256) {
        uint256 userBurnTotal = getUserBurnTotal(user);
        if (userBurnTotal == 0) return 0;
        if (userBurnTotal >= MAX_BURN_AMP_BASE) return MAX_BURN_AMP_PERCENT;
        return (MAX_BURN_AMP_PERCENT * userBurnTotal) / MAX_BURN_AMP_BASE;
    }

    //views
    /** @notice return total burned titan amount from all users burn or projects burn
     * @return totalBurnAmount returns entire burned titan
     */
    function getTotalBurnTotal() public view returns (uint256) {
        return s_totalTitanBurned;
    }

    /** @notice return user address total burned titan
     * @return userBurnAmount returns user address total burned titan
     */
    function getUserBurnTotal(address user) public view returns (uint256) {
        return s_userBurnAmount[user];
    }

    /** @notice return project address total burned titan amount
     * @return projectTotalBurnAmount returns project total burned titan
     */
    function getProjectBurnTotal(address contractAddress) public view returns (uint256) {
        return s_project_BurnAmount[contractAddress];
    }

    /** @notice return user address total burned titan amount via a project address
     * @param contractAddress project address
     * @param user user address
     * @return projectUserTotalBurnAmount returns user address total burned titan via a project address
     */
    function getProjectUserBurnTotal(
        address contractAddress,
        address user
    ) public view returns (uint256) {
        return s_projectUser_BurnAmount[contractAddress][user];
    }

    /** @notice return cycle28 total burned titan amount with the specified cycleIndex
     * @param cycleIndex cycle index
     * @return cycle28TotalBurn returns cycle28 total burned titan amount with the specified cycleIndex
     */
    function getCycleBurnTotal(uint256 cycleIndex) public view returns (uint256) {
        return s_cycle28TotalBurn[cycleIndex];
    }

    /** @notice return cycle28 total burned titan amount with the specified cycleIndex
     * @param user user address
     * @param cycleIndex cycle index
     * @return cycle28TotalBurn returns cycle28 user address total burned titan amount with the specified cycleIndex
     */
    function _getUserCycleBurnTotal(
        address user,
        uint256 cycleIndex
    ) internal view returns (uint256) {
        return s_userCycle28TotalBurn[user][cycleIndex];
    }

    /** @notice return cycle28 burn payout per titan with the specified cycleIndex
     * @param cycleIndex cycle index
     * @return cycle28TotalBurn returns cycle28 burn payout per titan with the specified cycleIndex
     */
    function getCycleBurnPayoutPerToken(uint256 cycleIndex) public view returns (uint256) {
        return s_cycle28BurnPayoutPerToken[cycleIndex];
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../libs/calcFunctions.sol";

//custom errors
error TitanX_InvalidStakeLength();
error TitanX_RequireOneMinimumShare();
error TitanX_ExceedMaxAmountPerStake();
error TitanX_NoStakeExists();
error TitanX_StakeHasEnded();
error TitanX_StakeNotMatured();
error TitanX_StakeHasBurned();
error TitanX_MaxedWalletStakes();

abstract contract StakeInfo {
    //Variables
    /** @dev track global stake Id */
    uint256 private s_globalStakeId;
    /** @dev track global shares */
    uint256 private s_globalShares;
    /** @dev track global expired shares */
    uint256 private s_globalExpiredShares;
    /** @dev track global staked titan */
    uint256 private s_globalTitanStaked;
    /** @dev track global end stake penalty */
    uint256 private s_globalStakePenalty;
    /** @dev track global ended stake */
    uint256 private s_globalStakeEnd;
    /** @dev track global burned stake */
    uint256 private s_globalStakeBurn;

    //mappings
    /** @dev track address => stakeId */
    mapping(address => uint256) private s_addressSId;
    /** @dev track address, stakeId => global stake Id */
    mapping(address => mapping(uint256 => uint256)) private s_addressSIdToGlobalStakeId;
    /** @dev track global stake Id => stake info */
    mapping(uint256 => UserStakeInfo) private s_globalStakeIdToStakeInfo;

    /** @dev track address => shares Index */
    mapping(address => uint256) private s_userSharesIndex;
    /** @dev track user total active shares by user shares index
     * s_addressIdToActiveShares[user][index] = UserActiveShares (contract day, total user active shares)
     * works like a snapshot or log when user shares has changed (increase/decrease)
     */
    mapping(address => mapping(uint256 => UserActiveShares)) private s_addressIdToActiveShares;

    //structs
    struct UserStakeInfo {
        uint152 titanAmount;
        uint128 shares;
        uint16 numOfDays;
        uint48 stakeStartTs;
        uint48 maturityTs;
        StakeStatus status;
    }

    struct UserStake {
        uint256 sId;
        uint256 globalStakeId;
        UserStakeInfo stakeInfo;
    }

    struct UserActiveShares {
        uint256 day;
        uint256 activeShares;
    }

    //events
    event StakeStarted(
        address indexed user,
        uint256 indexed globalStakeId,
        uint256 numOfDays,
        UserStakeInfo indexed userStakeInfo
    );

    event StakeEnded(
        address indexed user,
        uint256 indexed globalStakeId,
        uint256 titanAmount,
        uint256 indexed penalty,
        uint256 penaltyAmount
    );

    //functions
    /** @dev create a new stake
     * @param user user address
     * @param amount titan amount
     * @param numOfDays stake lenght
     * @param shareRate current share rate
     * @param day current contract day
     * @param isPayoutTriggered has global payout triggered
     * @return isFirstShares first created shares or not
     */
    function _startStake(
        address user,
        uint256 amount,
        uint256 numOfDays,
        uint256 shareRate,
        uint256 day,
        PayoutTriggered isPayoutTriggered
    ) internal returns (uint256 isFirstShares) {
        uint256 sId = ++s_addressSId[user];
        if (sId > MAX_STAKE_PER_WALLET) revert TitanX_MaxedWalletStakes();
        if (numOfDays < MIN_STAKE_LENGTH || numOfDays > MAX_STAKE_LENGTH)
            revert TitanX_InvalidStakeLength();

        //calculate shares
        uint256 shares = calculateShares(amount, numOfDays, shareRate);
        if (shares / SCALING_FACTOR_1e18 < 1) revert TitanX_RequireOneMinimumShare();

        uint256 currentGStakeId = ++s_globalStakeId;
        uint256 maturityTs;

        maturityTs = block.timestamp + (numOfDays * SECONDS_IN_DAY);

        UserStakeInfo memory userStakeInfo = UserStakeInfo({
            titanAmount: uint152(amount),
            shares: uint128(shares),
            numOfDays: uint16(numOfDays),
            stakeStartTs: uint48(block.timestamp),
            maturityTs: uint48(maturityTs),
            status: StakeStatus.ACTIVE
        });

        /** s_addressSId[user] tracks stake Id for each address
         * s_addressSIdToGlobalStakeId[user][id] tracks stack id to global stake Id
         * s_globalStakeIdToStakeInfo[currentGStakeId] stores stake info
         */
        s_addressSIdToGlobalStakeId[user][sId] = currentGStakeId;
        s_globalStakeIdToStakeInfo[currentGStakeId] = userStakeInfo;

        //update shares changes
        isFirstShares = _updateSharesStats(
            user,
            shares,
            amount,
            day,
            isPayoutTriggered,
            StakeAction.START
        );

        emit StakeStarted(user, currentGStakeId, numOfDays, userStakeInfo);
    }

    /** @dev end stake and calculate pinciple with penalties (if any) or burn stake
     * @param user user address
     * @param id stake Id
     * @param day current contract day
     * @param action end stake or burn stake
     * @param payOther is end stake for others
     * @param isPayoutTriggered has global payout triggered
     * @return titan titan principle
     */
    function _endStake(
        address user,
        uint256 id,
        uint256 day,
        StakeAction action,
        StakeAction payOther,
        PayoutTriggered isPayoutTriggered
    ) internal returns (uint256 titan) {
        uint256 globalStakeId = s_addressSIdToGlobalStakeId[user][id];
        if (globalStakeId == 0) revert TitanX_NoStakeExists();

        UserStakeInfo memory userStakeInfo = s_globalStakeIdToStakeInfo[globalStakeId];
        if (userStakeInfo.status == StakeStatus.ENDED) revert TitanX_StakeHasEnded();
        if (userStakeInfo.status == StakeStatus.BURNED) revert TitanX_StakeHasBurned();
        //end stake for others requires matured stake to prevent EES for others
        if (payOther == StakeAction.END_OTHER && block.timestamp < userStakeInfo.maturityTs)
            revert TitanX_StakeNotMatured();

        //update shares changes
        uint256 shares = userStakeInfo.shares;
        _updateSharesStats(user, shares, userStakeInfo.titanAmount, day, isPayoutTriggered, action);

        if (action == StakeAction.END) {
            ++s_globalStakeEnd;
            s_globalStakeIdToStakeInfo[globalStakeId].status = StakeStatus.ENDED;
        } else if (action == StakeAction.BURN) {
            ++s_globalStakeBurn;
            s_globalStakeIdToStakeInfo[globalStakeId].status = StakeStatus.BURNED;
        }

        titan = _calculatePrinciple(user, globalStakeId, userStakeInfo, action);
    }

    /** @dev update shares changes to track when user shares has changed, this affect the payout calculation
     * @param user user address
     * @param shares shares
     * @param amount titan amount
     * @param day current contract day
     * @param isPayoutTriggered has global payout triggered
     * @param action start stake or end stake
     * @return isFirstShares first created shares or not
     */
    function _updateSharesStats(
        address user,
        uint256 shares,
        uint256 amount,
        uint256 day,
        PayoutTriggered isPayoutTriggered,
        StakeAction action
    ) private returns (uint256 isFirstShares) {
        //Get previous active shares to calculate new shares change
        uint256 index = s_userSharesIndex[user];
        uint256 previousShares = s_addressIdToActiveShares[user][index].activeShares;

        if (action == StakeAction.START) {
            //return 1 if this is a new wallet address
            //this is used to initialize last claim index to the latest cycle index
            if (index == 0) isFirstShares = 1;

            s_addressIdToActiveShares[user][++index].activeShares = previousShares + shares;
            s_globalShares += shares;
            s_globalTitanStaked += amount;
        } else {
            s_addressIdToActiveShares[user][++index].activeShares = previousShares - shares;
            s_globalExpiredShares += shares;
            s_globalTitanStaked -= amount;
        }

        //If global payout hasn't triggered, use current contract day to eligible for payout
        //If global payout has triggered, then start with next contract day as it's no longer eligible to claim latest payout
        s_addressIdToActiveShares[user][index].day = uint128(
            isPayoutTriggered == PayoutTriggered.NO ? day : day + 1
        );

        s_userSharesIndex[user] = index;
    }

    /** @dev calculate stake principle and apply penalty (if any)
     * @param user user address
     * @param globalStakeId global stake Id
     * @param userStakeInfo stake info
     * @param action end stake or burn stake
     * @return principle calculated principle after penalty (if any)
     */
    function _calculatePrinciple(
        address user,
        uint256 globalStakeId,
        UserStakeInfo memory userStakeInfo,
        StakeAction action
    ) internal returns (uint256 principle) {
        uint256 titanAmount = userStakeInfo.titanAmount;
        //penalty is in percentage
        uint256 penalty = calculateEndStakePenalty(
            userStakeInfo.stakeStartTs,
            userStakeInfo.maturityTs,
            block.timestamp,
            action
        );

        uint256 penaltyAmount;
        penaltyAmount = (titanAmount * penalty) / 100;
        principle = titanAmount - penaltyAmount;
        s_globalStakePenalty += penaltyAmount;

        emit StakeEnded(user, globalStakeId, principle, penalty, penaltyAmount);
    }

    //Views
    /** @notice get global shares
     * @return globalShares global shares
     */
    function getGlobalShares() public view returns (uint256) {
        return s_globalShares;
    }

    /** @notice get global expired shares
     * @return globalExpiredShares global expired shares
     */
    function getGlobalExpiredShares() public view returns (uint256) {
        return s_globalExpiredShares;
    }

    /** @notice get global active shares
     * @return globalActiveShares global active shares
     */
    function getGlobalActiveShares() public view returns (uint256) {
        return s_globalShares - s_globalExpiredShares;
    }

    /** @notice get total titan staked
     * @return totalTitanStaked total titan staked
     */
    function getTotalTitanStaked() public view returns (uint256) {
        return s_globalTitanStaked;
    }

    /** @notice get global stake id
     * @return globalStakeId global stake id
     */
    function getGlobalStakeId() public view returns (uint256) {
        return s_globalStakeId;
    }

    /** @notice get global active stakes
     * @return globalActiveStakes global active stakes
     */
    function getGlobalActiveStakes() public view returns (uint256) {
        return s_globalStakeId - getTotalStakeEnd();
    }

    /** @notice get total stake ended
     * @return totalStakeEnded total stake ended
     */
    function getTotalStakeEnd() public view returns (uint256) {
        return s_globalStakeEnd;
    }

    /** @notice get total stake burned
     * @return totalStakeBurned total stake burned
     */
    function getTotalStakeBurn() public view returns (uint256) {
        return s_globalStakeBurn;
    }

    /** @notice get total end stake penalty
     * @return totalEndStakePenalty total end stake penalty
     */
    function getTotalStakePenalty() public view returns (uint256) {
        return s_globalStakePenalty;
    }

    /** @notice get user latest shares index
     * @return latestSharesIndex latest shares index
     */
    function getUserLatestShareIndex(address user) public view returns (uint256) {
        return s_userSharesIndex[user];
    }

    /** @notice get user current active shares
     * @return currentActiveShares current active shares
     */
    function getUserCurrentActiveShares(address user) public view returns (uint256) {
        return s_addressIdToActiveShares[user][getUserLatestShareIndex(user)].activeShares;
    }

    /** @notice get user active shares at sharesIndex
     * @return activeShares active shares at sharesIndex
     */
    function getUserActiveShares(
        address user,
        uint256 sharesIndex
    ) internal view returns (uint256) {
        return s_addressIdToActiveShares[user][sharesIndex].activeShares;
    }

    /** @notice get user active shares contract day at sharesIndex
     * @return activeSharesDay active shares contract day at sharesIndex
     */
    function getUserActiveSharesDay(
        address user,
        uint256 sharesIndex
    ) internal view returns (uint256) {
        return s_addressIdToActiveShares[user][sharesIndex].day;
    }

    /** @notice get stake info with stake id
     * @return stakeInfo stake info
     */
    function getUserStakeInfo(address user, uint256 id) public view returns (UserStakeInfo memory) {
        return s_globalStakeIdToStakeInfo[s_addressSIdToGlobalStakeId[user][id]];
    }

    /** @notice get all stake info of an address
     * @return stakeInfos all stake info of an address
     */
    function getUserStakes(address user) public view returns (UserStake[] memory) {
        uint256 count = s_addressSId[user];
        UserStake[] memory stakes = new UserStake[](count);

        for (uint256 i = 1; i <= count; i++) {
            stakes[i - 1] = UserStake({
                sId: i,
                globalStakeId: uint128(s_addressSIdToGlobalStakeId[user][i]),
                stakeInfo: getUserStakeInfo(user, i)
            });
        }

        return stakes;
    }
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../libs/calcFunctions.sol";

//custom errors
error TitanX_InvalidMintLength();
error TitanX_InvalidMintPower();
error TitanX_NoMintExists();
error TitanX_MintHasClaimed();
error TitanX_MintNotMature();
error TitanX_MintHasBurned();

abstract contract MintInfo {
    //variables
    /** @dev track global tRank */
    uint256 private s_globalTRank;
    /** @dev track total mint claimed */
    uint256 private s_globalMintClaim;
    /** @dev track total mint burned */
    uint256 private s_globalMintBurn;
    /** @dev track total titan minting */
    uint256 private s_globalTitanMinting;
    /** @dev track total titan penalty */
    uint256 private s_globalTitanMintPenalty;
    /** @dev track global mint power */
    uint256 private s_globalMintPower;

    //mappings
    /** @dev track address => mintId */
    mapping(address => uint256) private s_addressMId;
    /** @dev track address, mintId => tRank info (gTrank, gMintPower) */
    mapping(address => mapping(uint256 => TRankInfo)) private s_addressMIdToTRankInfo;
    /** @dev track global tRank => mintInfo*/
    mapping(uint256 => UserMintInfo) private s_tRankToMintInfo;

    //structs
    struct UserMintInfo {
        uint8 mintPower;
        uint16 numOfDays;
        uint96 mintableTitan;
        uint48 mintStartTs;
        uint48 maturityTs;
        uint32 mintPowerBonus;
        uint32 EAABonus;
        uint128 mintedTitan;
        uint64 mintCost;
        MintStatus status;
    }

    struct TRankInfo {
        uint256 tRank;
        uint256 gMintPower;
    }

    struct UserMint {
        uint256 mId;
        uint256 tRank;
        uint256 gMintPower;
        UserMintInfo mintInfo;
    }

    //events
    event MintStarted(
        address indexed user,
        uint256 indexed tRank,
        uint256 indexed gMintpower,
        UserMintInfo userMintInfo
    );

    event MintClaimed(
        address indexed user,
        uint256 indexed tRank,
        uint256 rewardMinted,
        uint256 indexed penalty,
        uint256 mintPenalty
    );

    //functions
    /** @dev create a new mint
     * @param user user address
     * @param mintPower mint power
     * @param numOfDays mint lenght
     * @param mintableTitan mintable titan
     * @param mintPowerBonus mint power bonus
     * @param EAABonus EAA bonus
     * @param burnAmpBonus burn amplifier bonus
     * @param gMintPower global mint power
     * @param currentTRank current global tRank
     * @param mintCost actual mint cost paid for a mint
     */
    function _startMint(
        address user,
        uint256 mintPower,
        uint256 numOfDays,
        uint256 mintableTitan,
        uint256 mintPowerBonus,
        uint256 EAABonus,
        uint256 burnAmpBonus,
        uint256 gMintPower,
        uint256 currentTRank,
        uint256 mintCost
    ) internal returns (uint256 mintable) {
        if (numOfDays == 0 || numOfDays > MAX_MINT_LENGTH) revert TitanX_InvalidMintLength();
        if (mintPower == 0 || mintPower > MAX_MINT_POWER_CAP) revert TitanX_InvalidMintPower();

        //calculate mint reward up front with the provided params
        mintable = calculateMintReward(mintPower, numOfDays, mintableTitan, EAABonus, burnAmpBonus);

        //store variables into mint info
        UserMintInfo memory userMintInfo = UserMintInfo({
            mintPower: uint8(mintPower),
            numOfDays: uint16(numOfDays),
            mintableTitan: uint96(mintable),
            mintPowerBonus: uint32(mintPowerBonus),
            EAABonus: uint32(EAABonus),
            mintStartTs: uint48(block.timestamp),
            maturityTs: uint48(block.timestamp + (numOfDays * SECONDS_IN_DAY)),
            mintedTitan: 0,
            mintCost: uint64(mintCost),
            status: MintStatus.ACTIVE
        });

        /** s_addressMId[user] tracks mintId for each addrress
         * s_addressMIdToTRankInfo[user][id] tracks current mint tRank and gPowerMint
         *  s_tRankToMintInfo[currentTRank] stores mint info
         */
        uint256 id = ++s_addressMId[user];
        s_addressMIdToTRankInfo[user][id].tRank = currentTRank;
        s_addressMIdToTRankInfo[user][id].gMintPower = gMintPower;
        s_tRankToMintInfo[currentTRank] = userMintInfo;

        emit MintStarted(user, currentTRank, gMintPower, userMintInfo);
    }

    /** @dev create new mint in a batch of up to max 100 mints with the same mint length
     * @param user user address
     * @param mintPower mint power
     * @param numOfDays mint lenght
     * @param mintableTitan mintable titan
     * @param mintPowerBonus mint power bonus
     * @param EAABonus EAA bonus
     * @param burnAmpBonus burn amplifier bonus
     * @param mintCost actual mint cost paid for a mint
     */
    function _startBatchMint(
        address user,
        uint256 mintPower,
        uint256 numOfDays,
        uint256 mintableTitan,
        uint256 mintPowerBonus,
        uint256 EAABonus,
        uint256 burnAmpBonus,
        uint256 count,
        uint256 mintCost
    ) internal {
        uint256 gMintPower = s_globalMintPower;
        uint256 currentTRank = s_globalTRank;
        uint256 gMinting = s_globalTitanMinting;

        for (uint256 i = 0; i < count; i++) {
            gMintPower += mintPower;
            gMinting += _startMint(
                user,
                mintPower,
                numOfDays,
                mintableTitan,
                mintPowerBonus,
                EAABonus,
                burnAmpBonus,
                gMintPower,
                ++currentTRank,
                mintCost
            );
        }
        _updateMintStats(currentTRank, gMintPower, gMinting);
    }

    /** @dev create new mint in a batch of up to max 100 mints with different mint length
     * @param user user address
     * @param mintPower mint power
     * @param minDay minimum start day
     * @param maxDay maximum end day
     * @param dayInterval days interval between each new mint length
     * @param countPerInterval number of mint(s) to create in each mint length interval
     * @param mintableTitan mintable titan
     * @param mintPowerBonus mint power bonus
     * @param EAABonus EAA bonus
     * @param burnAmpBonus burn amplifier bonus
     * @param mintCost actual mint cost paid for a mint
     */
    function _startbatchMintLadder(
        address user,
        uint256 mintPower,
        uint256 minDay,
        uint256 maxDay,
        uint256 dayInterval,
        uint256 countPerInterval,
        uint256 mintableTitan,
        uint256 mintPowerBonus,
        uint256 EAABonus,
        uint256 burnAmpBonus,
        uint256 mintCost
    ) internal {
        uint256 gMintPower = s_globalMintPower;
        uint256 currentTRank = s_globalTRank;
        uint256 gMinting = s_globalTitanMinting;

        /**first for loop is used to determine mint length
         * minDay is the starting mint length
         * maxDay is the max mint length where it stops
         * dayInterval increases the minDay for the next mint
         */
        for (; minDay <= maxDay; minDay += dayInterval) {
            /**first for loop is used to determine mint length
             * second for loop is to create number mints per mint length
             */
            for (uint256 j = 0; j < countPerInterval; j++) {
                gMintPower += mintPower;
                gMinting += _startMint(
                    user,
                    mintPower,
                    minDay,
                    mintableTitan,
                    mintPowerBonus,
                    EAABonus,
                    burnAmpBonus,
                    gMintPower,
                    ++currentTRank,
                    mintCost
                );
            }
        }
        _updateMintStats(currentTRank, gMintPower, gMinting);
    }

    /** @dev update variables
     * @param currentTRank current tRank
     * @param gMintPower current global mint power
     * @param gMinting current global minting
     */
    function _updateMintStats(uint256 currentTRank, uint256 gMintPower, uint256 gMinting) internal {
        s_globalTRank = currentTRank;
        s_globalMintPower = gMintPower;
        s_globalTitanMinting = gMinting;
    }

    /** @dev calculate reward for claim mint or burn mint.
     * Claim mint has maturity check while burn mint would bypass maturity check.
     * @param user user address
     * @param id mint id
     * @param action claim mint or burn mint
     * @return reward calculated final reward after all bonuses and penalty (if any)
     */
    function _claimMint(
        address user,
        uint256 id,
        MintAction action
    ) internal returns (uint256 reward) {
        uint256 tRank = s_addressMIdToTRankInfo[user][id].tRank;
        uint256 gMintPower = s_addressMIdToTRankInfo[user][id].gMintPower;
        if (tRank == 0) revert TitanX_NoMintExists();

        UserMintInfo memory mint = s_tRankToMintInfo[tRank];
        if (mint.status == MintStatus.CLAIMED) revert TitanX_MintHasClaimed();
        if (mint.status == MintStatus.BURNED) revert TitanX_MintHasBurned();

        //Only check maturity for claim mint action, burn mint bypass this check
        if (mint.maturityTs > block.timestamp && action == MintAction.CLAIM)
            revert TitanX_MintNotMature();

        s_globalTitanMinting -= mint.mintableTitan;
        reward = _calculateClaimReward(user, tRank, gMintPower, mint, action);
    }

    /** @dev calculate reward up to 100 claims for batch claim function. Only calculate active and matured mints.
     * @param user user address
     * @return reward total batch claims final calculated reward after all bonuses and penalty (if any)
     */
    function _batchClaimMint(address user) internal returns (uint256 reward) {
        uint256 maxId = s_addressMId[user];
        uint256 claimCount;
        uint256 tRank;
        uint256 gMinting;
        UserMintInfo memory mint;

        for (uint256 i = 1; i <= maxId; i++) {
            tRank = s_addressMIdToTRankInfo[user][i].tRank;
            mint = s_tRankToMintInfo[tRank];
            if (mint.status == MintStatus.ACTIVE && block.timestamp >= mint.maturityTs) {
                reward += _calculateClaimReward(
                    user,
                    tRank,
                    s_addressMIdToTRankInfo[user][i].gMintPower,
                    mint,
                    MintAction.CLAIM
                );

                gMinting += mint.mintableTitan;
                ++claimCount;
            }

            if (claimCount == 100) break;
        }

        s_globalTitanMinting -= gMinting;
    }

    /** @dev calculate final reward with bonuses and penalty (if any)
     * @param user user address
     * @param tRank mint's tRank
     * @param gMintPower mint's gMintPower
     * @param userMintInfo mint's info
     * @param action claim mint or burn mint
     * @return reward calculated final reward after all bonuses and penalty (if any)
     */
    function _calculateClaimReward(
        address user,
        uint256 tRank,
        uint256 gMintPower,
        UserMintInfo memory userMintInfo,
        MintAction action
    ) private returns (uint256 reward) {
        if (action == MintAction.CLAIM) s_tRankToMintInfo[tRank].status = MintStatus.CLAIMED;
        if (action == MintAction.BURN) s_tRankToMintInfo[tRank].status = MintStatus.BURNED;

        uint256 penaltyAmount;
        uint256 penalty;
        uint256 bonus;

        //only calculate penalty when current block timestamp > maturity timestamp
        if (block.timestamp > userMintInfo.maturityTs) {
            penalty = calculateClaimMintPenalty(block.timestamp - userMintInfo.maturityTs);
        }

        //Only Claim action has mintPower bonus
        if (action == MintAction.CLAIM) {
            bonus = calculateMintPowerBonus(
                userMintInfo.mintPowerBonus,
                userMintInfo.mintPower,
                gMintPower,
                s_globalMintPower
            );
        }

        //mintPowerBonus has scaling factor of 1e7, so divide by 1e7
        reward = uint256(userMintInfo.mintableTitan) + (bonus / SCALING_FACTOR_1e7);
        penaltyAmount = (reward * penalty) / 100;
        reward -= penaltyAmount;

        if (action == MintAction.CLAIM) ++s_globalMintClaim;
        if (action == MintAction.BURN) ++s_globalMintBurn;
        if (penaltyAmount != 0) s_globalTitanMintPenalty += penaltyAmount;

        //only stored minted amount for claim mint
        if (action == MintAction.CLAIM) s_tRankToMintInfo[tRank].mintedTitan = uint128(reward);

        emit MintClaimed(user, tRank, reward, penalty, penaltyAmount);
    }

    //views
    /** @notice Returns the latest Mint Id of an address
     * @param user address
     * @return mId latest mint id
     */
    function getUserLatestMintId(address user) public view returns (uint256) {
        return s_addressMId[user];
    }

    /** @notice Returns mint info of an address + mint id
     * @param user address
     * @param id mint id
     * @return mintInfo user mint info
     */
    function getUserMintInfo(
        address user,
        uint256 id
    ) public view returns (UserMintInfo memory mintInfo) {
        return s_tRankToMintInfo[s_addressMIdToTRankInfo[user][id].tRank];
    }

    /** @notice Return all mints info of an address
     * @param user address
     * @return mintInfos all mints info of an address including mint id, tRank and gMintPower
     */
    function getUserMints(address user) public view returns (UserMint[] memory mintInfos) {
        uint256 count = s_addressMId[user];
        mintInfos = new UserMint[](count);

        for (uint256 i = 1; i <= count; i++) {
            mintInfos[i - 1] = UserMint({
                mId: i,
                tRank: s_addressMIdToTRankInfo[user][i].tRank,
                gMintPower: s_addressMIdToTRankInfo[user][i].gMintPower,
                mintInfo: getUserMintInfo(user, i)
            });
        }
    }

    /** @notice Return total mints burned
     * @return totalMintBurned total mints burned
     */
    function getTotalMintBurn() public view returns (uint256) {
        return s_globalMintBurn;
    }

    /** @notice Return current gobal tRank
     * @return globalTRank global tRank
     */
    function getGlobalTRank() public view returns (uint256) {
        return s_globalTRank;
    }

    /** @notice Return current gobal mint power
     * @return globalMintPower global mint power
     */
    function getGlobalMintPower() public view returns (uint256) {
        return s_globalMintPower;
    }

    /** @notice Return total mints claimed
     * @return totalMintClaimed total mints claimed
     */
    function getTotalMintClaim() public view returns (uint256) {
        return s_globalMintClaim;
    }

    /** @notice Return total active mints (exluded claimed and burned mints)
     * @return totalActiveMints total active mints
     */
    function getTotalActiveMints() public view returns (uint256) {
        return s_globalTRank - s_globalMintClaim - s_globalMintBurn;
    }

    /** @notice Return total minting titan
     * @return totalMinting total minting titan
     */
    function getTotalMinting() public view returns (uint256) {
        return s_globalTitanMinting;
    }

    /** @notice Return total titan penalty
     * @return totalTitanPenalty total titan penalty
     */
    function getTotalMintPenalty() public view returns (uint256) {
        return s_globalTitanMintPenalty;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../libs/enum.sol";
import "../libs/constant.sol";

abstract contract GlobalInfo {
    //Variables
    //deployed timestamp
    uint256 private immutable i_genesisTs;

    /** @dev track current contract day */
    uint256 private s_currentContractDay;
    /** @dev shareRate starts 800 ether and increases capped at 2800 ether, uint72 has enough size */
    uint72 private s_currentshareRate;
    /** @dev mintCost starts 0.2 ether increases and capped at 1 ether, uint64 has enough size */
    uint64 private s_currentMintCost;
    /** @dev mintableTitan starts 8m ether decreases and capped at 800 ether, uint96 has enough size */
    uint96 private s_currentMintableTitan;
    /** @dev mintPowerBonus starts 350_000_000 and decreases capped at 35_000, uint32 has enough size */
    uint32 private s_currentMintPowerBonus;
    /** @dev EAABonus starts 10_000_000 and decreases to 0, uint32 has enough size */
    uint32 private s_currentEAABonus;

    /** @dev track if any of the cycle day 8, 28, 90, 369, 888 has payout triggered succesfully
     * this is used in end stake where either the shares change should be tracked in current/next payout cycle
     */
    PayoutTriggered private s_isGlobalPayoutTriggered;

    /** @dev track payouts based on every cycle day 8, 28, 90, 369, 888 when distributeETH() is called */
    mapping(uint256 => uint256) private s_cyclePayouts;

    /** @dev track payout index for each cycle day, increased by 1 when triggerPayouts() is called succesfully
     *  eg. curent index is 2, s_cyclePayoutIndex[DAY8] = 2 */
    mapping(uint256 => uint256) private s_cyclePayoutIndex;

    /** @dev track payout info (day and payout per share) for each cycle day
     * eg. s_cyclePayoutIndex is 2,
     *  s_CyclePayoutPerShare[DAY8][2].day = 8
     * s_CyclePayoutPerShare[DAY8][2].payoutPerShare = 0.1
     */
    mapping(uint256 => mapping(uint256 => CycleRewardPerShare)) private s_cyclePayoutPerShare;

    /** @dev track user last payout reward claim index for cycleIndex, burnCycleIndex and sharesIndex
     * so calculation would start from next index instead of the first index
     * [address][DAY8].cycleIndex = 1
     * [address][DAY8].burnCycleIndex = 1
     * [address][DAY8].sharesIndex = 2
     * cycleIndex is the last stop in s_cyclePayoutPerShare
     * sharesIndex is the last stop in s_addressIdToActiveShares
     */
    mapping(address => mapping(uint256 => UserCycleClaimIndex))
        private s_addressCycleToLastClaimIndex;

    /** @dev track when is the next cycle payout day for each cycle day
     * eg. s_nextCyclePayoutDay[DAY8] = 8
     *     s_nextCyclePayoutDay[DAY28] = 28
     */
    mapping(uint256 => uint256) s_nextCyclePayoutDay;

    //structs
    struct CycleRewardPerShare {
        uint256 day;
        uint256 payoutPerShare;
    }

    struct UserCycleClaimIndex {
        uint96 cycleIndex;
        uint96 burnCycleIndex;
        uint64 sharesIndex;
    }

    //event
    event GlobalDailyUpdateStats(
        uint256 indexed day,
        uint256 indexed mintCost,
        uint256 indexed shareRate,
        uint256 mintableTitan,
        uint256 mintPowerBonus,
        uint256 EAABonus
    );

    /** @dev Update variables in terms of day, modifier is used in all external/public functions (exclude view)
     * Every interaction to the contract would run this function to update variables
     */
    modifier dailyUpdate() {
        _dailyUpdate();
        _;
    }

    constructor() {
        i_genesisTs = block.timestamp;
        s_currentContractDay = 1;
        s_currentMintCost = uint64(START_MAX_MINT_COST);
        s_currentMintableTitan = uint96(START_MAX_MINTABLE_PER_DAY);
        s_currentshareRate = uint72(START_SHARE_RATE);
        s_currentMintPowerBonus = uint32(START_MINTPOWER_INCREASE_BONUS);
        s_currentEAABonus = uint32(EAA_START);
        s_nextCyclePayoutDay[DAY8] = DAY8;
        s_nextCyclePayoutDay[DAY28] = DAY28;
        s_nextCyclePayoutDay[DAY90] = DAY90;
        s_nextCyclePayoutDay[DAY369] = DAY369;
        s_nextCyclePayoutDay[DAY888] = DAY888;
    }

    /** @dev calculate and update variables daily and reset triggers flag */
    function _dailyUpdate() private {
        uint256 currentContractDay = s_currentContractDay;
        uint256 currentBlockDay = ((block.timestamp - i_genesisTs) / 1 days) + 1;

        if (currentBlockDay > currentContractDay) {
            //get last day info ready for calculation
            uint256 newMintCost = s_currentMintCost;
            uint256 newShareRate = s_currentshareRate;
            uint256 newMintableTitan = s_currentMintableTitan;
            uint256 newMintPowerBonus = s_currentMintPowerBonus;
            uint256 newEAABonus = s_currentEAABonus;
            uint256 dayDifference = currentBlockDay - currentContractDay;

            /** Reason for a for loop to update Mint supply
             * Ideally, user interaction happens daily, so Mint supply is synced in every day
             *      (cylceDifference = 1)
             * However, if there's no interaction for more than 1 day, then
             *      Mint supply isn't updated correctly due to cylceDifference > 1 day
             * Eg. 2 days of no interaction, then interaction happens in 3rd day.
             *     It's incorrect to only decrease the Mint supply one time as now it's in 3rd day.
             *   And if this happens, there will be no tracked data for the skipped days as not needed
             */
            for (uint256 i; i < dayDifference; i++) {
                newMintCost = (newMintCost * DAILY_MINT_COST_INCREASE_STEP) / PERCENT_BPS;
                newShareRate = (newShareRate * DAILY_SHARE_RATE_INCREASE_STEP) / PERCENT_BPS;
                newMintableTitan =
                    (newMintableTitan * DAILY_SUPPLY_MINTABLE_REDUCTION) /
                    PERCENT_BPS;
                newMintPowerBonus =
                    (newMintPowerBonus * DAILY_MINTPOWER_INCREASE_BONUS_REDUCTION) /
                    PERCENT_BPS;

                if (newMintCost > 1 ether) {
                    newMintCost = CAPPED_MAX_MINT_COST;
                }

                if (newShareRate > CAPPED_MAX_RATE) newShareRate = CAPPED_MAX_RATE;

                if (newMintableTitan < CAPPED_MIN_DAILY_TITAN_MINTABLE) {
                    newMintableTitan = CAPPED_MIN_DAILY_TITAN_MINTABLE;
                }

                if (newMintPowerBonus < CAPPED_MIN_MINTPOWER_BONUS) {
                    newMintPowerBonus = CAPPED_MIN_MINTPOWER_BONUS;
                }

                if (currentBlockDay <= MAX_BONUS_DAY) {
                    newEAABonus -= EAA_BONUSE_FIXED_REDUCTION_PER_DAY;
                } else {
                    newEAABonus = EAA_END;
                }

                emit GlobalDailyUpdateStats(
                    ++currentContractDay,
                    newMintCost,
                    newShareRate,
                    newMintableTitan,
                    newMintPowerBonus,
                    newEAABonus
                );
            }

            s_currentMintCost = uint64(newMintCost);
            s_currentshareRate = uint72(newShareRate);
            s_currentMintableTitan = uint96(newMintableTitan);
            s_currentMintPowerBonus = uint32(newMintPowerBonus);
            s_currentEAABonus = uint32(newEAABonus);
            s_currentContractDay = currentBlockDay;
            s_isGlobalPayoutTriggered = PayoutTriggered.NO;
        }
    }

    /** @dev first created shares will start from the last payout index + 1 (next cycle payout)
     * as first shares will always disqualified from past payouts
     * reduce gas cost needed to loop from first index
     * @param user user address
     * @param isFirstShares flag to only initialize when address is fresh wallet
     */
    function _initFirstSharesCycleIndex(address user, uint256 isFirstShares) internal {
        if (isFirstShares == 1) {
            if (s_cyclePayoutIndex[DAY8] != 0) {
                s_addressCycleToLastClaimIndex[user][DAY8].cycleIndex = uint96(
                    s_cyclePayoutIndex[DAY8] + 1
                );

                s_addressCycleToLastClaimIndex[user][DAY28].cycleIndex = uint96(
                    s_cyclePayoutIndex[DAY28] + 1
                );

                s_addressCycleToLastClaimIndex[user][DAY90].cycleIndex = uint96(
                    s_cyclePayoutIndex[DAY90] + 1
                );

                s_addressCycleToLastClaimIndex[user][DAY369].cycleIndex = uint96(
                    s_cyclePayoutIndex[DAY369] + 1
                );

                s_addressCycleToLastClaimIndex[user][DAY888].cycleIndex = uint96(
                    s_cyclePayoutIndex[DAY888] + 1
                );
            }
        }
    }

    /** @dev first created shares will start from the last payout index + 1 (next cycle payout)
     * as first shares will always disqualified from past payouts
     * reduce gas cost needed to loop from first index
     * @param cycleNo cylce day 8, 28, 90, 369, 888
     * @param reward total accumulated reward in cycle day 8, 28, 90, 369, 888
     * @param globalActiveShares global active shares
     * @return index return latest current cycleIndex
     */
    function _calculateCycleRewardPerShare(
        uint256 cycleNo,
        uint256 reward,
        uint256 globalActiveShares
    ) internal returns (uint256 index) {
        s_cyclePayouts[cycleNo] = 0;
        index = ++s_cyclePayoutIndex[cycleNo];
        //add 18 decimals to reward for better precision in calculation
        s_cyclePayoutPerShare[cycleNo][index].payoutPerShare =
            (reward * SCALING_FACTOR_1e18) /
            globalActiveShares;
        s_cyclePayoutPerShare[cycleNo][index].day = getCurrentContractDay();
    }

    /** @dev update with the last index where a user has claimed the payout reward
     * @param user user address
     * @param cycleNo cylce day 8, 28, 90, 369, 888
     * @param userClaimCycleIndex last claimed cycle index
     * @param userClaimSharesIndex last claimed shares index
     */
    function _updateUserClaimIndexes(
        address user,
        uint256 cycleNo,
        uint256 userClaimCycleIndex,
        uint256 userClaimSharesIndex
    ) internal {
        if (userClaimCycleIndex != s_addressCycleToLastClaimIndex[user][cycleNo].cycleIndex)
            s_addressCycleToLastClaimIndex[user][cycleNo].cycleIndex = uint96(userClaimCycleIndex);

        if (userClaimSharesIndex != s_addressCycleToLastClaimIndex[user][cycleNo].sharesIndex)
            s_addressCycleToLastClaimIndex[user][cycleNo].sharesIndex = uint64(
                userClaimSharesIndex
            );
    }

    /** @dev update with the last index where a user has claimed the burn payout reward
     * @param user user address
     * @param cycleNo cylce day 8, 28, 90, 369, 888
     * @param userClaimBurnCycleIndex last claimed burn cycle index
     */
    function _updateUserBurnCycleClaimIndex(
        address user,
        uint256 cycleNo,
        uint256 userClaimBurnCycleIndex
    ) internal {
        if (userClaimBurnCycleIndex != s_addressCycleToLastClaimIndex[user][cycleNo].burnCycleIndex)
            s_addressCycleToLastClaimIndex[user][cycleNo].burnCycleIndex = uint96(
                userClaimBurnCycleIndex
            );
    }

    /** @dev set to YES when any of the cycle days payout is triggered
     * reset to NO in new contract day
     */
    function _setGlobalPayoutTriggered() internal {
        s_isGlobalPayoutTriggered = PayoutTriggered.YES;
    }

    /** @dev add reward into cycle day 8, 28, 90, 369, 888 pool
     * @param cycleNo cycle day 8, 28, 90, 369, 888
     * @param reward reward from distributeETH()
     */
    function _setCyclePayoutPool(uint256 cycleNo, uint256 reward) internal {
        s_cyclePayouts[cycleNo] += reward;
    }

    /** @dev calculate and update the next payout day for specified cycleNo
     * the formula will update the payout day based on current contract day
     * this is to make sure the value is correct when for some reason has skipped more than one cycle payout
     * @param cycleNo cycle day 8, 28, 90, 369, 888
     */
    function _setNextCyclePayoutDay(uint256 cycleNo) internal {
        uint256 maturityDay = s_nextCyclePayoutDay[cycleNo];
        uint256 currentContractDay = s_currentContractDay;
        if (currentContractDay >= maturityDay) {
            s_nextCyclePayoutDay[cycleNo] +=
                cycleNo *
                (((currentContractDay - maturityDay) / cycleNo) + 1);
        }
    }

    /** Views */
    /** @notice Returns current block timestamp
     * @return currentBlockTs current block timestamp
     */
    function getCurrentBlockTimeStamp() public view returns (uint256) {
        return block.timestamp;
    }

    /** @notice Returns current contract day
     * @return currentContractDay current contract day
     */
    function getCurrentContractDay() public view returns (uint256) {
        return s_currentContractDay;
    }

    /** @notice Returns current mint cost
     * @return currentMintCost current block timestamp
     */
    function getCurrentMintCost() public view returns (uint256) {
        return s_currentMintCost;
    }

    /** @notice Returns current share rate
     * @return currentShareRate current share rate
     */
    function getCurrentShareRate() public view returns (uint256) {
        return s_currentshareRate;
    }

    /** @notice Returns current mintable titan
     * @return currentMintableTitan current mintable titan
     */
    function getCurrentMintableTitan() public view returns (uint256) {
        return s_currentMintableTitan;
    }

    /** @notice Returns current mint power bonus
     * @return currentMintPowerBonus current mint power bonus
     */
    function getCurrentMintPowerBonus() public view returns (uint256) {
        return s_currentMintPowerBonus;
    }

    /** @notice Returns current contract EAA bonus
     * @return currentEAABonus current EAA bonus
     */
    function getCurrentEAABonus() public view returns (uint256) {
        return s_currentEAABonus;
    }

    /** @notice Returns current cycle index for the specified cycle day
     * @param cycleNo cycle day 8, 28, 90, 369, 888
     * @return currentCycleIndex current cycle index to track the payouts
     */
    function getCurrentCycleIndex(uint256 cycleNo) public view returns (uint256) {
        return s_cyclePayoutIndex[cycleNo];
    }

    /** @notice Returns whether payout is triggered successfully in any cylce day
     * @return isTriggered 0 or 1, 0= No, 1=Yes
     */
    function getGlobalPayoutTriggered() public view returns (PayoutTriggered) {
        return s_isGlobalPayoutTriggered;
    }

    /** @notice Returns the distributed pool reward for the specified cycle day
     * @param cycleNo cycle day 8, 28, 90, 369, 888
     * @return currentPayoutPool current accumulated payout pool
     */
    function getCyclePayoutPool(uint256 cycleNo) public view returns (uint256) {
        return s_cyclePayouts[cycleNo];
    }

    /** @notice Returns the calculated payout per share and contract day for the specified cycle day and index
     * @param cycleNo cycle day 8, 28, 90, 369, 888
     * @param index cycle index
     * @return payoutPerShare calculated payout per share
     * @return triggeredDay the day when payout was triggered to perform calculation
     */
    function getPayoutPerShare(
        uint256 cycleNo,
        uint256 index
    ) public view returns (uint256, uint256) {
        return (
            s_cyclePayoutPerShare[cycleNo][index].payoutPerShare,
            s_cyclePayoutPerShare[cycleNo][index].day
        );
    }

    /** @notice Returns user's last claimed shares payout indexes for the specified cycle day
     * @param user user address
     * @param cycleNo cycle day 8, 28, 90, 369, 888
     * @return cycleIndex cycle index
     * @return sharesIndex shares index
     
     */
    function getUserLastClaimIndex(
        address user,
        uint256 cycleNo
    ) public view returns (uint256 cycleIndex, uint256 sharesIndex) {
        return (
            s_addressCycleToLastClaimIndex[user][cycleNo].cycleIndex,
            s_addressCycleToLastClaimIndex[user][cycleNo].sharesIndex
        );
    }

    /** @notice Returns user's last claimed burn payout index for the specified cycle day
     * @param user user address
     * @param cycleNo cycle day 8, 28, 90, 369, 888
     * @return burnCycleIndex burn cycle index
     */
    function getUserLastBurnClaimIndex(
        address user,
        uint256 cycleNo
    ) public view returns (uint256 burnCycleIndex) {
        return s_addressCycleToLastClaimIndex[user][cycleNo].burnCycleIndex;
    }

    /** @notice Returns contract deployment block timestamp
     * @return genesisTs deployed timestamp
     */
    function genesisTs() public view returns (uint256) {
        return i_genesisTs;
    }

    /** @notice Returns next payout day for the specified cycle day
     * @param cycleNo cycle day 8, 28, 90, 369, 888
     * @return nextPayoutDay next payout day
     */
    function getNextCyclePayoutDay(uint256 cycleNo) public view returns (uint256) {
        return s_nextCyclePayoutDay[cycleNo];
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./constant.sol";
import "./enum.sol";

//TitanX
/**@notice get batch mint ladder total count
 * @param minDay minimum mint length
 * @param maxDay maximum mint length, cap at 280
 * @param dayInterval day increase from previous mint length
 * @param countPerInterval number of mints per minth length
 * @return count total mints
 */
function getBatchMintLadderCount(
    uint256 minDay,
    uint256 maxDay,
    uint256 dayInterval,
    uint256 countPerInterval
) pure returns (uint256 count) {
    if (maxDay > minDay) {
        count = (((maxDay - minDay) / dayInterval) + 1) * countPerInterval;
    }
}

/** @notice get incentive fee in 4 decimals scaling
 * @return fee fee
 */
function getIncentiveFeePercent() pure returns (uint256) {
    return (INCENTIVE_FEE_PERCENT * 1e4) / INCENTIVE_FEE_PERCENT_BASE;
}

/** @notice get batch mint cost
 * @param mintPower mint power (1 - 100)
 * @param count number of mints
 * @return mintCost total mint cost
 */
function getBatchMintCost(
    uint256 mintPower,
    uint256 count,
    uint256 mintCost
) pure returns (uint256) {
    return (mintCost * mintPower * count) / MAX_MINT_POWER_CAP;
}

//MintInfo

/** @notice the formula to calculate mint reward at create new mint
 * @param mintPower mint power 1 - 100
 * @param numOfDays mint length 1 - 280
 * @param mintableTitan current contract day mintable titan
 * @param EAABonus current contract day EAA Bonus
 * @param burnAmpBonus user burn amplifier bonus from getUserBurnAmplifierBonus(user)
 * @return reward base titan amount
 */
function calculateMintReward(
    uint256 mintPower,
    uint256 numOfDays,
    uint256 mintableTitan,
    uint256 EAABonus,
    uint256 burnAmpBonus
) pure returns (uint256 reward) {
    uint256 baseReward = (mintableTitan * mintPower * numOfDays);
    if (numOfDays != 1)
        baseReward -= (baseReward * MINT_DAILY_REDUCTION * (numOfDays - 1)) / PERCENT_BPS;

    reward = baseReward;
    if (EAABonus != 0) {
        //EAA Bonus has 1e6 scaling, so here divide by 1e6
        reward += ((baseReward * EAABonus) / 100 / SCALING_FACTOR_1e6);
    }

    if (burnAmpBonus != 0) {
        //burnAmpBonus has 1e18 scaling
        reward += (baseReward * burnAmpBonus) / 100 / SCALING_FACTOR_1e18;
    }

    reward /= MAX_MINT_POWER_CAP;
}

/** @notice the formula to calculate bonus reward
 * heavily influenced by the difference between current global mint power and user mint's global mint power
 * @param mintPowerBonus mint power bonus from mintinfo
 * @param mintPower mint power 1 - 100 from mintinfo
 * @param gMintPower global mint power from mintinfo
 * @param globalMintPower current global mint power
 * @return bonus bonus amount in titan
 */
function calculateMintPowerBonus(
    uint256 mintPowerBonus,
    uint256 mintPower,
    uint256 gMintPower,
    uint256 globalMintPower
) pure returns (uint256 bonus) {
    if (globalMintPower <= gMintPower) return 0;
    bonus = (((mintPowerBonus * mintPower * (globalMintPower - gMintPower)) * SCALING_FACTOR_1e18) /
        MAX_MINT_POWER_CAP);
}

/** @notice Return max mint length
 * @return maxMintLength max mint length
 */
function getMaxMintDays() pure returns (uint256) {
    return MAX_MINT_LENGTH;
}

/** @notice Return max mints per wallet
 * @return maxMintPerWallet max mints per wallet
 */
function getMaxMintsPerWallet() pure returns (uint256) {
    return MAX_MINT_PER_WALLET;
}

/**
 * @dev Return penalty percentage based on number of days late after the grace period of 7 days
 * @param secsLate seconds late (block timestamp - maturity timestamp)
 * @return penalty penalty in percentage
 */
function calculateClaimMintPenalty(uint256 secsLate) pure returns (uint256 penalty) {
    if (secsLate <= CLAIM_MINT_GRACE_PERIOD * SECONDS_IN_DAY) return 0;
    if (secsLate <= (CLAIM_MINT_GRACE_PERIOD + 1) * SECONDS_IN_DAY) return 1;
    if (secsLate <= (CLAIM_MINT_GRACE_PERIOD + 2) * SECONDS_IN_DAY) return 3;
    if (secsLate <= (CLAIM_MINT_GRACE_PERIOD + 3) * SECONDS_IN_DAY) return 8;
    if (secsLate <= (CLAIM_MINT_GRACE_PERIOD + 4) * SECONDS_IN_DAY) return 17;
    if (secsLate <= (CLAIM_MINT_GRACE_PERIOD + 5) * SECONDS_IN_DAY) return 35;
    if (secsLate <= (CLAIM_MINT_GRACE_PERIOD + 6) * SECONDS_IN_DAY) return 72;
    return 99;
}

//StakeInfo

error TitanX_AtLeastHalfMaturity();

/** @notice get max stake length
 * @return maxStakeLength max stake length
 */
function getMaxStakeLength() pure returns (uint256) {
    return MAX_STAKE_LENGTH;
}

/** @notice calculate shares and shares bonus
 * @param amount titan amount
 * @param noOfDays stake length
 * @param shareRate current contract share rate
 * @return shares calculated shares in 18 decimals
 */
function calculateShares(
    uint256 amount,
    uint256 noOfDays,
    uint256 shareRate
) pure returns (uint256) {
    uint256 shares = amount;
    shares += (shares * calculateShareBonus(amount, noOfDays)) / SCALING_FACTOR_1e11;
    shares /= (shareRate / SCALING_FACTOR_1e18);
    return shares;
}

/** @notice calculate share bonus
 * @param amount titan amount
 * @param noOfDays stake length
 * @return shareBonus calculated shares bonus in 11 decimals
 */
function calculateShareBonus(uint256 amount, uint256 noOfDays) pure returns (uint256 shareBonus) {
    uint256 cappedExtraDays = noOfDays <= LPB_MAX_DAYS ? noOfDays : LPB_MAX_DAYS;
    uint256 cappedStakedTitan = amount <= BPB_MAX_TITAN ? amount : BPB_MAX_TITAN;
    shareBonus =
        ((cappedExtraDays * SCALING_FACTOR_1e11) / LPB_PER_PERCENT) +
        ((cappedStakedTitan * SCALING_FACTOR_1e11) / BPB_PER_PERCENT);
    return shareBonus;
}

/** @notice calculate end stake penalty
 * @param stakeStartTs start stake timestamp
 * @param maturityTs  maturity timestamp
 * @param currentBlockTs current block timestamp
 * @param action end stake or burn stake
 * @return penalty penalty in percentage
 */
function calculateEndStakePenalty(
    uint256 stakeStartTs,
    uint256 maturityTs,
    uint256 currentBlockTs,
    StakeAction action
) view returns (uint256) {
    //Matured, then calculate and return penalty
    if (currentBlockTs > maturityTs) {
        uint256 lateSec = currentBlockTs - maturityTs;
        uint256 gracePeriodSec = END_STAKE_GRACE_PERIOD * SECONDS_IN_DAY;
        if (lateSec <= gracePeriodSec) return 0;
        return max((min((lateSec - gracePeriodSec), 1) / SECONDS_IN_DAY) + 1, 99);
    }

    //burn stake is excluded from penalty
    //if not matured and action is burn stake then return 0
    if (action == StakeAction.BURN) return 0;

    //Emergency End Stake
    //Not allow to EES below 50% maturity
    if (block.timestamp < stakeStartTs + (maturityTs - stakeStartTs) / 2)
        revert TitanX_AtLeastHalfMaturity();

    //50% penalty for EES before maturity timestamp
    return 50;
}

//a - input to check against b
//b - minimum number
function min(uint256 a, uint256 b) pure returns (uint256) {
    if (a > b) return a;
    return b;
}

//a - input to check against b
//b - maximum number
function max(uint256 a, uint256 b) pure returns (uint256) {
    if (a > b) return b;
    return a;
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface ITITANX {
    function balanceOf(address account) external returns (uint256);

    function getBalance() external;

    function mintLPTokens() external;

    function burnLPTokens() external;
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface ITitanOnBurn {
    function onBurn(address user, uint256 amount) external;
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (interfaces/IERC165.sol)

pragma solidity ^0.8.0;

import "../utils/introspection/IERC165.sol";

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./extensions/IERC20Metadata.sol";
import "../../utils/Context.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.openzeppelin.com/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC20
 * applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(
        address owner,
        address spender
    ) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     */
    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

enum MintAction {
    CLAIM,
    BURN
}
enum MintStatus {
    ACTIVE,
    CLAIMED,
    BURNED
}
enum StakeAction {
    START,
    END,
    BURN,
    END_OWN,
    END_OTHER
}
enum StakeStatus {
    ACTIVE,
    ENDED,
    BURNED
}
enum PayoutTriggered {
    NO,
    YES
}
enum InitialLPMinted {
    NO,
    YES
}
enum PayoutClaim {
    SHARES,
    BURN
}
enum BurnSource {
    LIQUID,
    MINT,
    STAKE
}
enum BurnPoolEnabled {
    FALSE,
    TRUE
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// ===================== common ==========================================
uint256 constant SECONDS_IN_DAY = 86400;
uint256 constant SCALING_FACTOR_1e3 = 1e3;
uint256 constant SCALING_FACTOR_1e6 = 1e6;
uint256 constant SCALING_FACTOR_1e7 = 1e7;
uint256 constant SCALING_FACTOR_1e11 = 1e11;
uint256 constant SCALING_FACTOR_1e18 = 1e18;

// ===================== TITANX ==========================================
uint256 constant PERCENT_TO_BUY_AND_BURN = 62_00;
uint256 constant PERCENT_TO_CYCLE_PAYOUTS = 28_00;
uint256 constant PERCENT_TO_BURN_PAYOUTS = 7_00;
uint256 constant PERCENT_TO_GENESIS = 3_00;

uint256 constant INCENTIVE_FEE_PERCENT = 3300;
uint256 constant INCENTIVE_FEE_PERCENT_BASE = 1_000_000;

uint256 constant INITAL_LP_TOKENS = 100_000_000_000 ether;

// ===================== globalInfo ==========================================
//Titan Supply Variables
uint256 constant START_MAX_MINTABLE_PER_DAY = 8_000_000 ether;
uint256 constant CAPPED_MIN_DAILY_TITAN_MINTABLE = 800 ether;
uint256 constant DAILY_SUPPLY_MINTABLE_REDUCTION = 99_65;

//EAA Variables
uint256 constant EAA_START = 10 * SCALING_FACTOR_1e6;
uint256 constant EAA_BONUSE_FIXED_REDUCTION_PER_DAY = 28_571;
uint256 constant EAA_END = 0;
uint256 constant MAX_BONUS_DAY = 350;

//Mint Cost Variables
uint256 constant START_MAX_MINT_COST = 0.2 ether;
uint256 constant CAPPED_MAX_MINT_COST = 1 ether;
uint256 constant DAILY_MINT_COST_INCREASE_STEP = 100_08;

//mintPower Bonus Variables
uint256 constant START_MINTPOWER_INCREASE_BONUS = 35 * SCALING_FACTOR_1e7; //starts at 35 with 1e7 scaling factor
uint256 constant CAPPED_MIN_MINTPOWER_BONUS = 35 * SCALING_FACTOR_1e3; //capped min of 0.0035 * 1e7 = 35 * 1e3
uint256 constant DAILY_MINTPOWER_INCREASE_BONUS_REDUCTION = 99_65;

//Share Rate Variables
uint256 constant START_SHARE_RATE = 800 ether;
uint256 constant DAILY_SHARE_RATE_INCREASE_STEP = 100_03;
uint256 constant CAPPED_MAX_RATE = 2_800 ether;

//Cycle Variables
uint256 constant DAY8 = 8;
uint256 constant DAY28 = 28;
uint256 constant DAY90 = 90;
uint256 constant DAY369 = 369;
uint256 constant DAY888 = 888;
uint256 constant CYCLE_8_PERCENT = 28_00;
uint256 constant CYCLE_28_PERCENT = 28_00;
uint256 constant CYCLE_90_PERCENT = 18_00;
uint256 constant CYCLE_369_PERCENT = 18_00;
uint256 constant CYCLE_888_PERCENT = 8_00;
uint256 constant PERCENT_BPS = 100_00;

// ===================== mintInfo ==========================================
uint256 constant MAX_MINT_POWER_CAP = 100;
uint256 constant MAX_MINT_LENGTH = 280;
uint256 constant CLAIM_MINT_GRACE_PERIOD = 7;
uint256 constant MAX_BATCH_MINT_COUNT = 100;
uint256 constant MAX_MINT_PER_WALLET = 1000;
uint256 constant MAX_BURN_AMP_BASE = 80 * 1e9 * 1 ether;
uint256 constant MAX_BURN_AMP_PERCENT = 8 ether;
uint256 constant MINT_DAILY_REDUCTION = 11;

// ===================== stakeInfo ==========================================
uint256 constant MAX_STAKE_PER_WALLET = 1000;
uint256 constant MIN_STAKE_LENGTH = 28;
uint256 constant MAX_STAKE_LENGTH = 3500;
uint256 constant END_STAKE_GRACE_PERIOD = 7;

/* Stake Longer Pays Better bonus */
uint256 constant LPB_MAX_DAYS = 2888;
uint256 constant LPB_PER_PERCENT = 825;

/* Stake Bigger Pays Better bonus */
uint256 constant BPB_MAX_TITAN = 100 * 1e9 * SCALING_FACTOR_1e18; //100 billion
uint256 constant BPB_PER_PERCENT = 1_250_000_000_000 * SCALING_FACTOR_1e18;

// ===================== burnInfo ==========================================
uint256 constant MAX_BURN_REWARD_PERCENT = 8;

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/IERC20Metadata.sol)

pragma solidity ^0.8.0;

import "../IERC20.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/introspection/IERC165.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}