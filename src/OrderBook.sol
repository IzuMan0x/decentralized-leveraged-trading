// SPDX-License-Identifier: UNLICENSED

/* '  ______      _   _          _____             _       ___  ___     
'  | ___ \    | | | |        |_   _|           | |      |  \/  |     
'  | |_/ / ___| |_| |_ ___ _ __| |_ __ __ _  __| | ___  | .  . | ___ 
'  | ___ \/ _ \ __| __/ _ \ '__| | '__/ _` |/ _` |/ _ \ | |\/| |/ _ \
'  | |_/ /  __/ |_| ||  __/ |  | | | | (_| | (_| |  __/_| |  | |  __/
'  \____/ \___|\__|\__\___|_|  \_/_|  \__,_|\__,_|\___(_)_|  |_/\___| */

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.19;
//Todo move structs into another contract to clean the code up, however first we need to make sure everything works and is tested
// create a memory storage contract for open orders
//Make certain contract parameters updgradeable

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPyth} from "@pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pyth-sdk-solidity/PythStructs.sol";

/// @title This is v0.1 Decentralized Leverage Trading @ bettertrade.me
/// @author Izuman
/// @notice This is a denteralized leveraged trading platform. Frontend: bettertrade.me Gitbook:
/// @dev This needs monitored by a bot that will call the liquidate function when users PNL is at a certain level
/// @dev bots are incentivized by rewards for each trade they complete.
/// @dev future updgrades will include adding limit orders, stop losses, take profit etc.
contract OrderBook is ReentrancyGuard, Ownable {
    ////////////////////
    //Errors          //
    ////////////////////
    error OrderBook__ParameterArraysMustBeTheSameLength();
    error OrderBook__NeedsMoreThanZero();
    error OrderBook__UserClosingNonExistingPosition();
    error OrderBook__InvalidTradingPair();
    error OrderBook__MaxNumberOfOpenTrades3Reached();
    error OrderBook__TransferFailed();
    error OrderBook__MaxLeverageIs150();
    error OrderBook__InvalidOrderType();
    error OrderBook__TradeSizeTooSmall();
    error OrderBook__MaxOpenInterestReachedLongs();
    error OrderBook__MaxOpenInterestShortsReached();
    error OrderBook__UserPositionNotOpenForLiquidation(int256 userPNL);
    error OrderBook__NoBotRewards();

    ////////////////////
    // State Variables //
    ////////////////////
    IPyth pyth;

    struct PositionDetails {
        uint256 pairNumber;
        int256 openPrice;
        int256 collateralAfterFee;
        int256 leverage;
        uint256 longShort; //0 for long and 1 for short
        uint256 openTime;
        uint256 indexBorrowPercentArray;
    }

    //future reference
    //maybe put a fee parameter in AssetPairDetails if we want each asset to have a different fee

    struct AssetPairDetails {
        bytes32 pythPriceFeedAddress;
        int256 assetTotalShorts;
        int256 assetTotalLongs;
        int256 maxOpenInterest; //The max amount of interest alowed to be open for a pair this will be the same for long or short
        int256[] borrowFee; //borrowFee and time array must always be the same length and stay in sync or fee calculations will be off
        uint256[] time; // they need to stay nsync
        string pairSymbol;
    }

    uint256 private constant LONG_POSITION = 0;
    uint256 private constant SHORT_POSITION = 1;
    int256 private constant FEE_PRECISION = 10_000_000; //or 1e7
    int256 private constant LEVERAGE_PRECISION = 1_000_000; //or 1e6
    int256 private constant COLLATERAL_PRECISION = 1e18;
    int256 private constant TIME_PRECISION = 1e2;
    int256 private constant PRICE_FEED_PRECISION = 1e5; //not sure yet if each price feed will have the same precision...
    int256 private constant SECONDS_IN_HOUR = 3600;

    //accepted collateral address for making trades, should be a stable coin like Dai or USDC etc.
    //These can all be changed by the owner
    address private s_tokenCollateralAddress;
    int256 private s_openingFeePercentage = 7500; //0.075% 75000
    int256 private s_baseBorrowFeePercentage = 600;
    int256 private s_baseVariableBorrowFeePercentage = 100;
    int256 private s_maxBorrowInterestRate = 100 * 100;
    int256 private s_minTradeSize = 1500 ether;
    uint256 private s_botExecutionRewardRate = 2 ether;

    //int256 private constant ROLLOVER_FEE = 10000; //0.1% this will be charged every hour on the collateral size currently not being used

    uint256 private s_numberOfAvailableAssetPairs; // we will use this to loop through the mappings and get the pair details

    //Maybe change the mappings a bit and create an order struct in another contract
    mapping(uint256 assetPairIndex => AssetPairDetails assetPairDetails) private s_assetPairDetails;

    mapping(
        address userAddress
            => mapping(
                uint256 assetPairIndex => mapping(uint256 openTradesIncrementer => PositionDetails positionDetails)
            )
    ) private s_userTradeDetails;

    // each slot will have either 0 or 1, 0 will be default and mean the trade slot is open and 1 will mean the trade slot is filled
    // to determine if the trade limit we will add get the sum of the array
    // in the future we may change these to enums for clarity and security reasons... however 1's and 0's are more clear to me
    mapping(address userAddress => mapping(uint256 pairIndex => uint256[3] numberOfOpenTrades)) private s_userOpenTrades;
    mapping(address botAddress => uint256 executionRewards) private s_botExecutionRewards;

    ////////////////////
    // Events         //
    ///////////////////
    event OrderClosed(address indexed user, uint256 indexed pairIndex, uint256 userTradeIndex);
    event MarketTrade(address indexed user, uint256 indexed pairIndex);
    event UserLiquidated(address indexed user, uint256 pairIndex, uint256 userTradeIndex);
    event TradeOpened(address indexed user, uint256 indexed pairIndex, uint256 indexed userPairTradeIndex);
    event OpenInterestUpdated(int256 interestLongs, int256 interestShorts);
    event UserLiquidationDetails(address indexed userAddress, uint256 indexed pairIndex, int256 indexed userPNL);
    event OrderClosedTradeDetails(address indexed userAddress, uint256 indexed pairIndex, int256 indexed userPNL);
    event OpeningFeeChanged(address user, int256 newOpeningFee);
    event BaseBorrowFeeChanged(address indexed user, int256 indexed newBaseBorrowFeePercentage);
    event BaseVariableBorrowFeeChanged(address indexed user, int256 indexed newVariableBorrowFeePercentage);
    event MaxBorrowRateChanged(address indexed user, int256 indexed newMaxBorrowInterestRate);
    event MinTradeSizeChanged(address indexed user, int256 indexed newMinTradeSize);
    event BotRewardsClaimed(address indexed botAddress, uint256 indexed amount);
    //Following events are used for testing purposes
    event AvgBorrowFeeCalculation(uint256 indexed pairIndex, int256 indexed borrowFee, uint256 indexed orderType);
    event BorrowFeeUpdated(uint256 indexed pairIndex, int256[] borrowFees);
    event PriceChange(int256 indexed priceChange);
    event UserPNL(int256 indexed userPNl);

    ////////////////////
    // Modifiers      //
    ////////////////////
    //Both the collateral and leverage amount need to be more than zero
    modifier validTradeParameters(address user, int256 amount, int256 leverage, uint256 pairIndex, uint256 orderType) {
        if (s_assetPairDetails[pairIndex].pythPriceFeedAddress == 0) {
            revert OrderBook__InvalidTradingPair();
        } else if (orderType != 0 && orderType != 1) {
            revert OrderBook__InvalidOrderType();
        } else if (amount == 0 || leverage == 0) {
            revert OrderBook__NeedsMoreThanZero();
        } else if (((amount * leverage) / LEVERAGE_PRECISION) < s_minTradeSize) {
            revert OrderBook__TradeSizeTooSmall();
        } else if (
            orderType == 0
                && (
                    ((amount * leverage) / LEVERAGE_PRECISION)
                        > (s_assetPairDetails[pairIndex].maxOpenInterest - s_assetPairDetails[pairIndex].assetTotalLongs)
                )
        ) {
            revert OrderBook__MaxOpenInterestReachedLongs();
        } else if (
            orderType == 1
                && ((amount * leverage) / LEVERAGE_PRECISION)
                    > (s_assetPairDetails[pairIndex].maxOpenInterest - s_assetPairDetails[pairIndex].assetTotalShorts)
        ) {
            revert OrderBook__MaxOpenInterestShortsReached();
        } //Each user is limited to three open trades per pair
        else if (_getArraySum(s_userOpenTrades[user][pairIndex]) >= 3) {
            revert OrderBook__MaxNumberOfOpenTrades3Reached();
        } else if (leverage > 150_000_000) {
            revert OrderBook__MaxLeverageIs150();
        }
        _;
    }

    //Checks to see if certain position exist for a user
    modifier userPositionExist(address user, uint256 pairIndex, uint256 userTradesIdForPair) {
        if (s_userTradeDetails[user][pairIndex][userTradesIdForPair].openPrice == 0) {
            revert OrderBook__UserClosingNonExistingPosition();
        }
        _;
    }

    //Checks that trade made with a valid pair
    modifier validPair(uint256 pairIndex) {
        if (s_assetPairDetails[pairIndex].pythPriceFeedAddress == 0) {
            revert OrderBook__InvalidTradingPair();
        }
        _;
    }

    //The max leverage allowed is 150x which has a precision of 1e6

    modifier maxLeverage(int256 leverage) {
        if (leverage > 150_000_000) {
            revert OrderBook__MaxLeverageIs150();
        }
        _;
    }
    //Currently only orderType allowed is a long or a short (0 or 1)

    modifier validOrderType(uint256 orderType) {
        if (orderType != 0 && orderType != 1) {
            revert OrderBook__InvalidOrderType();
        }
        _;
    }

    modifier rewardAmount(address user) {
        if (s_botExecutionRewards[user] == 0) {
            revert OrderBook__NoBotRewards();
        }
        _;
    }

    ////////////////////
    // Functions  🥸   //
    ////////////////////

    ////////////////////
    // Constructor    //
    ////////////////////
    /// @notice Sets the initial paramters for the contract
    /// @dev pythPriceFeedAddress will be different for each chain and can be found here: https://docs.pyth.network/documentation/pythnet-price-feeds/evm
    /// @dev pairPriceFeedAddressId are the same for EVM chains and can be found here: https://pyth.network/developers/price-feed-ids#pyth-evm-mainnet
    /// @param pythPriceFeedAddress is the contract address that will be used to retrieve the price feed data
    /// @param tokenCollateralAddress is the ERC20 token address that will be used as collateral for trades. Expected precision is 1e18
    /// @param pairPriceFeedAddressId is the pyth price feed id for asset pair e.g. ETH/USD
    /// @param maxOpenInterest (precision 1e18) Array for the max amount of interest alowed to open for a pair. this protects the protocol and the user. This can be adjusted as the protocol matures
    /// @param pairIndex This may be unecessary
    /// @param pairSymbol this will be an array of the all the trading pairs symbols e.g. ["ETH/USD", "BTC/USD", "XRP/USD"...]
    constructor(
        address pythPriceFeedAddress,
        address tokenCollateralAddress,
        bytes32[] memory pairPriceFeedAddressId,
        int256[] memory maxOpenInterest,
        uint256[] memory pairIndex,
        string[] memory pairSymbol
    ) {
        //make sure the parameter arrays are the same size. Maybe move this to a modifier
        if (pairPriceFeedAddressId.length != pairIndex.length) {
            revert OrderBook__ParameterArraysMustBeTheSameLength();
        }
        if (pairIndex.length != pairSymbol.length) {
            revert OrderBook__ParameterArraysMustBeTheSameLength();
        }
        s_tokenCollateralAddress = tokenCollateralAddress;
        s_numberOfAvailableAssetPairs = pairPriceFeedAddressId.length;
        pyth = IPyth(pythPriceFeedAddress);
        for (uint256 i = 0; i < pairPriceFeedAddressId.length; i++) {
            s_assetPairDetails[i].pythPriceFeedAddress = pairPriceFeedAddressId[i];
            s_assetPairDetails[i].pairSymbol = pairSymbol[i];
            s_assetPairDetails[i].maxOpenInterest = maxOpenInterest[i];
        }
    }

    function setOpeningFee(int256 newOpeningFeePercent) external onlyOwner {
        s_openingFeePercentage = newOpeningFeePercent;
        emit OpeningFeeChanged(msg.sender, s_openingFeePercentage);
    }

    function setBaseBorrowFeePercentage(int256 newBaseBorrowFeePercentage) external onlyOwner {
        s_baseBorrowFeePercentage = newBaseBorrowFeePercentage;
        emit BaseBorrowFeeChanged(msg.sender, s_baseBorrowFeePercentage);
    }

    function setVariableBorrowFeePercentage(int256 newVariableBorrowFeePercentage) external onlyOwner {
        s_baseVariableBorrowFeePercentage = newVariableBorrowFeePercentage;
        emit BaseVariableBorrowFeeChanged(msg.sender, s_baseVariableBorrowFeePercentage);
    }

    function setMaxBorrowInterestRate(int256 newMaxBorrowInterestRate) external onlyOwner {
        s_maxBorrowInterestRate = newMaxBorrowInterestRate;
        emit MaxBorrowRateChanged(msg.sender, s_maxBorrowInterestRate);
    }

    function setMinTradeSize(int256 newMinTradeSize) external onlyOwner {
        s_minTradeSize = newMinTradeSize;
        emit MinTradeSizeChanged(msg.sender, s_minTradeSize);
    }

    function withdrawEth(address payable _to) external payable onlyOwner {
        (bool sent, bytes memory data) = _to.call{value: address(this).balance}("");
        if (!sent) {
            revert OrderBook__TransferFailed();
        }
    }

    function withdrawErc20Token(address tokenAddress, uint256 amount) external onlyOwner {
        bool success = IERC20(tokenAddress).transferFrom(address(this), msg.sender, amount);
        if (!success) {
            revert OrderBook__TransferFailed();
        }
    }

    function withdrawBotRewards() external rewardAmount(msg.sender) nonReentrant {
        uint256 amount = s_botExecutionRewards[msg.sender];
        s_botExecutionRewards[msg.sender] = 0;

        bool success = IERC20(s_tokenCollateralAddress).transferFrom(address(this), msg.sender, amount);
        if (!success) {
            revert OrderBook__TransferFailed();
        }
        emit BotRewardsClaimed(msg.sender, amount);
    }

    /// @notice Immediately opens a trading position based on the current market price for an trading pair
    /// @dev bytes[] calldata priceUpdateData is retrieved from the pyth frontend API, check the docs for more details (https://docs.pyth.network/documentation/pythnet-price-feeds/price-service)
    /// @dev Always update the pyth price feed manually before getting a price ^^
    /// @param pairIndex index for s_assetPairDetails to retrieve/update the trading pair details
    /// @param amountCollateral amount of collateral for the trading position
    /// @param leverage amount of leverage for the trading position
    /// @param orderType 0 = long and 1 = short
    /// @param priceUpdateData needed data to update the pyth price feed

    //we will refactor the marketorder function
    //Be careful modifying this function it is very close to throwing error "stack too deep"🧐
    //trade paramter modifiers were all combined into one to solve this
    // Below are the past modifiers
    /* validPair(pairIndex)
        maxTradeCount(msg.sender, pairIndex)
        maxLeverage(leverage)
        validOrderType(orderType) */
    function marketOrder(
        uint256 pairIndex,
        int256 amountCollateral,
        int256 leverage,
        uint256 orderType,
        bytes[] calldata priceUpdateData
    ) public payable validTradeParameters(msg.sender, amountCollateral, leverage, pairIndex, orderType) nonReentrant {
        //Before making any state changes we will take the trade collateral
        _sendFunds(msg.sender, uint256(amountCollateral));

        _order(msg.sender, pairIndex, amountCollateral, leverage, orderType, priceUpdateData);

        emit MarketTrade(msg.sender, pairIndex);

        //taken out of the event emit due to stack being too deep
        // s_userTradeDetails[msg.sender][pairIndex][s_userOpenTrades[msg.sender][pairIndex]].collateralAfterFee* leverage
    }
    //////////////////////
    //Utility functions///
    //////////////////////
    /// @notice This is used to get the sum of an array of fixed size 3
    /// @dev This is used for calculating number of user open trades and for setting the trade id for the next trade which could be "0, 1, or 2"
    /// @param _array an array held in storage with a fixed size of 3
    /// @return sum_ the sum of the array

    function _getArraySum(uint256[3] storage _array) private view returns (uint256 sum_) {
        sum_ = 0;
        for (uint256 i = 0; i < 3; i++) {
            sum_ += _array[i];
        }
        return sum_;
    }

    /// @notice closes a user's trading position.
    /// @dev Can only be called by the user with a position open.
    /// @dev The function must be called with a value to update the onChain pyth price feed. This fee is retrieved from the pyth api along with the priceUpdateData
    /// @param pairIndex index for s_assetPairDetails to retrieve/update the trading pair details
    /// @param userTradesIdForPair index for s_userTradeDetails to retrieve/update the user's position details.
    /// @param userTradesIdForPair trade per pair is capped at 3 thus this value must be 0, 1, or 2. First trade starts @ 2 then 1 and 0.
    /// @param priceUpdateData needed data to update the pyth price feed. This is retrieved from pyth's off chain api will be verified on chain.
    // function flow orderClose --> userPNL --> delete position mapping --> delete position trading slot --> _updatePairTotalBorrowed --> _setBorrowFeeArray --> payoutTrade winnings or losses
    function orderClose(uint256 pairIndex, uint256 userTradesIdForPair, bytes[] calldata priceUpdateData)
        public
        payable
        userPositionExist(msg.sender, pairIndex, userTradesIdForPair)
        nonReentrant
    {
        PositionDetails memory userPositionDetails = s_userTradeDetails[msg.sender][pairIndex][userTradesIdForPair];

        int256 userPNL = _getUserPNL(msg.sender, userPositionDetails, userTradesIdForPair, priceUpdateData);
        //here we are charging an OpenFee/ClosingFee currently they cost the same
        userPNL = userPNL - _calculateOpenFee(userPositionDetails.collateralAfterFee, userPositionDetails.leverage);

        // Here for possible gas optimization
        //s_userOpenTrades[msg.sender][userPositionDetails.pairNumber][userTradesIdForPair] = 0;
        //deleting the trade details
        delete s_userTradeDetails[msg.sender][userPositionDetails.pairNumber][userTradesIdForPair];
        //setting the trade slot to zero which means it is now open
        s_userOpenTrades[msg.sender][pairIndex][userTradesIdForPair] = 0;

        //The following steps should be put into one function, since the arrays need to be kept nsync ☢
        //---------------------------------------------
        //updating the borrow array
        _updatePairTotalBorrowed(
            userPositionDetails.longShort,
            pairIndex,
            (userPositionDetails.collateralAfterFee * userPositionDetails.leverage / LEVERAGE_PRECISION),
            false
        );

        //updating the borrow fee rate... this should be called within the the _updatePairTotalBorrowed
        //Time array must be set before _setBorrowFeeArray because it may be deleted and as a result they will be out of sync
        s_assetPairDetails[pairIndex].time.push(block.timestamp);
        _setBorrowFeeArray(pairIndex);

        //---------------------------------------------

        //checking PNL and paying out winnings or losses. If PNL is less than zero the user loses their collateral
        if (userPNL > 0) {
            uint256 uintUserPNL = uint256(userPNL);
            _sendFunds(msg.sender, uintUserPNL);
        }

        emit OrderClosed(msg.sender, userPositionDetails.pairNumber, userTradesIdForPair);
        emit OrderClosedTradeDetails(msg.sender, userPositionDetails.pairNumber, userPNL);
    }

    /// @notice liquidates a user if there PNL is at zero or below
    /// @dev This can be called by anyone, but most likely a bot to liquidate a user's position
    /// @param user the address of the user that will be liquidated
    /// @param pairIndex index for s_assetPairDetails to retrieve/update the trading pair details
    /// @param userTradesIdForPair index for s_userTradeDetails to retrieve/update the user's position details
    /// @param priceUpdateData needed data to update the pyth price feed

    function liquidateUser(
        address user,
        uint256 pairIndex,
        uint256 userTradesIdForPair,
        bytes[] calldata priceUpdateData
    ) public payable userPositionExist(user, pairIndex, userTradesIdForPair) nonReentrant {
        PositionDetails memory userPositionDetails = s_userTradeDetails[user][pairIndex][userTradesIdForPair];

        int256 userPNL = _getUserPNL(user, userPositionDetails, userTradesIdForPair, priceUpdateData);

        if (userPNL <= 0) {
            delete s_userTradeDetails[user][userPositionDetails.pairNumber][userTradesIdForPair];
            _updatePairTotalBorrowed(
                userPositionDetails.longShort,
                userPositionDetails.pairNumber,
                userPositionDetails.collateralAfterFee * userPositionDetails.leverage / LEVERAGE_PRECISION,
                false
            );
            s_assetPairDetails[pairIndex].time.push(block.timestamp);
            _setBorrowFeeArray(pairIndex);

            s_userOpenTrades[user][pairIndex][userTradesIdForPair] = 0;
            s_userOpenTrades[user][userPositionDetails.pairNumber][userTradesIdForPair] = 0;
            s_botExecutionRewards[msg.sender] += s_botExecutionRewardRate;
            emit UserLiquidated(user, userPositionDetails.pairNumber, userTradesIdForPair);
            emit UserLiquidationDetails(user, userPositionDetails.pairNumber, userPNL);
        } else {
            revert OrderBook__UserPositionNotOpenForLiquidation(userPNL);
        }
    }

    //////////////////////
    // Private Functions//
    //////////////////////
    /// @notice Calculates the user PNL when closing a trade or when there is an attempted liquidation
    /// @dev PNL is based off user collateral, once PNL is equal to 0 or negative they can be liquidated
    /// @param user address of the wallet with a trade opened
    /// @param userPositionDetails a struct that contains the position details
    /// @param userTradesIdForPair ID for the trade can i.e currently trades are capped at 3 per pair, thus ID can be 0,1,2
    /// @param priceUpdateData pyth update data retrieved from the pyth api
    /// @return userPNL the PNL of the user
    function _getUserPNL(
        address user,
        PositionDetails memory userPositionDetails,
        uint256 userTradesIdForPair,
        bytes[] calldata priceUpdateData
    ) private returns (int256) {
        //get price with the pairIndex
        PythStructs.Price memory closePriceData =
            getTradingPairCurrentPrice(priceUpdateData, userPositionDetails.pairNumber);

        //precison is 1e7
        int256 borrowFeePercentage = _calculateBorrowFee(
            user, userPositionDetails.pairNumber, userPositionDetails.longShort, userTradesIdForPair
        );

        //This needs to be made an average based on the ratio of users long and short postions
        //The result can be negative which means the user will be paid fees as a reward to keeping the protocol balanced
        //totalBorrowAmount precision is 1e18
        int256 totalBorrowFeeAmount = (
            borrowFeePercentage * userPositionDetails.leverage * userPositionDetails.collateralAfterFee
                * int256(block.timestamp - userPositionDetails.openTime) * TIME_PRECISION
        ) / (FEE_PRECISION * LEVERAGE_PRECISION * SECONDS_IN_HOUR * TIME_PRECISION);
        //note price feed accuracy is 5 decimals or 1e5
        //note leverage precision is 1e6
        //collateral is 1e18
        //
        int256 userPNL;

        //for closing a trade send 1 and for opening a trade send 0, this helps with protocol stability
        int256 priceChange = userPositionDetails.openPrice
            - int256(_calculateAdjustedPrice(userPositionDetails.longShort, closePriceData, 1));

        // emitted for testing, remove for production
        emit PriceChange(priceChange);
        //userPNL should have a precision of 1e18
        if (userPositionDetails.longShort == 0) {
            userPNL = userPositionDetails.collateralAfterFee - totalBorrowFeeAmount
                - userPositionDetails.leverage * priceChange * userPositionDetails.collateralAfterFee
                    / userPositionDetails.openPrice / (LEVERAGE_PRECISION);
        }
        if (userPositionDetails.longShort == 1) {
            userPNL = userPositionDetails.collateralAfterFee - totalBorrowFeeAmount
                + userPositionDetails.leverage * priceChange * userPositionDetails.collateralAfterFee
                    / userPositionDetails.openPrice / (LEVERAGE_PRECISION);
        }
        emit UserPNL(userPNL);

        /* userPNL =
            userPNL - int256(_calculateOpenFee(userPositionDetails.collateralAfterFee, userPositionDetails.leverage)); */
        return userPNL;
    }

    function _updatePairTotalBorrowed(uint256 orderType, uint256 pairIndex, int256 positionSize, bool openingTradeBool)
        private
    {
        //Here we are checking if the order is a long or short

        if (orderType == 0) {
            //positionSize precision is 1e18
            //Next we are checking if we are opening or closing a trade
            if (openingTradeBool) {
                s_assetPairDetails[pairIndex].assetTotalLongs += (positionSize);
            } else {
                s_assetPairDetails[pairIndex].assetTotalLongs -= (positionSize);
            }
        }
        if (orderType == 1) {
            if (openingTradeBool) {
                s_assetPairDetails[pairIndex].assetTotalShorts += (positionSize);
            } else {
                s_assetPairDetails[pairIndex].assetTotalShorts -= (positionSize);
            }
        }
        emit OpenInterestUpdated(
            s_assetPairDetails[pairIndex].assetTotalLongs, s_assetPairDetails[pairIndex].assetTotalShorts
        );
    }

    function _sendFunds(address user, uint256 amount) private {
        bool success = IERC20(s_tokenCollateralAddress).transferFrom(user, address(this), amount);
        if (!success) {
            revert OrderBook__TransferFailed();
        }
    }

    function _returnUserOpenTradeSlot(uint256[3] storage _array) private view returns (uint256 index) {
        //incoming array length must be fixed at length of 3
        index = 0;
        for (uint256 i = 0; i < 3; i++) {
            if (_array[i] == 0) {
                index = i;
            }
        }
        return index;
    }

    function _order(
        address user,
        uint256 pairIndex,
        int256 amountCollateral,
        int256 leverage,
        uint256 orderType,
        bytes[] calldata priceUpdateData
    ) private {
        //Here we are getting the openFee and subtracting it from the collateral
        //collateral after fee has a precision 1e18
        int256 collateralAfterFee;
        {
            collateralAfterFee = amountCollateral - _calculateOpenFee(amountCollateral, leverage);
        }
        uint256 openTradeSlot = _returnUserOpenTradeSlot(s_userOpenTrades[user][pairIndex]);
        //ssetting the trading slot as filled
        s_userOpenTrades[user][pairIndex][openTradeSlot] = 1;

        //updating the total amount borrow for long or short positions, this should be updated everytime a trade is opened or closed
        //true for whether it is opening or closing a trade
        _updatePairTotalBorrowed(orderType, pairIndex, (collateralAfterFee * leverage / LEVERAGE_PRECISION), true);

        s_assetPairDetails[pairIndex].time.push(block.timestamp);

        _setBorrowFeeArray(pairIndex);

        PythStructs.Price memory priceData = getTradingPairCurrentPrice(priceUpdateData, pairIndex);

        int256 adjustedPrice = int256(_calculateAdjustedPrice(orderType, priceData, 0));

        //Here we are updating the user's trade position
        s_userTradeDetails[user][pairIndex][openTradeSlot] = PositionDetails(
            pairIndex,
            adjustedPrice,
            collateralAfterFee,
            leverage,
            orderType,
            priceData.publishTime,
            (s_assetPairDetails[pairIndex].time.length - 1) //here we are getting the index for when we need to calculate the borrow fee when the order is closed
        );
        emit TradeOpened(user, pairIndex, openTradeSlot);
    }

    function _setBorrowFeeArray(uint256 pairIndex) private {
        //initially checking orderType is not needed since we are checking the total open positions
        int256 borrowFee;
        //note assetTotalLongs and assetTotalShorts precision are 1e18
        if (s_assetPairDetails[pairIndex].assetTotalLongs == 0 && s_assetPairDetails[pairIndex].assetTotalShorts == 0) {
            // when deleting the borrowFee we need to delete the time array as well so they stay in sync nsync🪩🕺
            delete s_assetPairDetails[pairIndex].time;
            delete s_assetPairDetails[pairIndex].borrowFee;
        } else if (s_assetPairDetails[pairIndex].assetTotalLongs == 0) {
            borrowFee = -1 * s_maxBorrowInterestRate * (s_assetPairDetails[pairIndex].assetTotalShorts)
                / s_assetPairDetails[pairIndex].maxOpenInterest;
        } else if (s_assetPairDetails[pairIndex].assetTotalShorts == 0) {
            borrowFee = s_maxBorrowInterestRate * s_assetPairDetails[pairIndex].assetTotalLongs
                / s_assetPairDetails[pairIndex].maxOpenInterest;
        } else if ((s_assetPairDetails[pairIndex].assetTotalLongs / s_assetPairDetails[pairIndex].assetTotalShorts) > 1)
        {
            borrowFee = s_baseVariableBorrowFeePercentage * s_assetPairDetails[pairIndex].assetTotalLongs
                / s_assetPairDetails[pairIndex].assetTotalShorts;
        } else if ((s_assetPairDetails[pairIndex].assetTotalLongs / s_assetPairDetails[pairIndex].assetTotalShorts) < 1)
        {
            borrowFee = -1 * s_baseVariableBorrowFeePercentage * s_assetPairDetails[pairIndex].assetTotalShorts
                / s_assetPairDetails[pairIndex].assetTotalLongs;
        } else if (s_assetPairDetails[pairIndex].assetTotalLongs == s_assetPairDetails[pairIndex].assetTotalShorts) {
            borrowFee = 0;
        }
        s_assetPairDetails[pairIndex].borrowFee.push(borrowFee);

        emit BorrowFeeUpdated(pairIndex, s_assetPairDetails[pairIndex].borrowFee);
    }

    function _calculateAdjustedPrice(uint256 orderType, PythStructs.Price memory priceData, uint256 openingOrClosing)
        private
        view
        returns (int64)
    {
        int64 adjustedPrice;
        if (orderType == 0 && openingOrClosing == 0) {
            adjustedPrice = (priceData.price) + int64(priceData.conf);
        } else if (orderType == 0 && openingOrClosing == 1) {
            adjustedPrice = (priceData.price) - int64(priceData.conf);
        } else if (orderType == 1 && openingOrClosing == 0) {
            adjustedPrice = (priceData.price) - int64(priceData.conf);
        } else {
            adjustedPrice = (priceData.price + int64(priceData.conf));
        }

        return adjustedPrice;
    }

    function _calculateOpenFee(int256 amountCollateral, int256 leverage) private view returns (int256 openFee) {
        int256 positionSize = (amountCollateral * leverage) / LEVERAGE_PRECISION;
        //this will return openFee which will have a precision 1e18
        openFee = (positionSize * s_openingFeePercentage) / FEE_PRECISION;
        //openFee = (positionSize * OPENING_FEE_PERCENTAGE) / FEE_PRECISION;
    }

    //events for debugging
    // remove
    event StartIndex(uint256 startIndex);
    event Sum(int256 sum);
    event TimeArrayLength(uint256 timeArrayLength);

    //We want this to be dynamic and change as the amount of long and shorts change
    function _calculateBorrowFee(address user, uint256 pairIndex, uint256 orderType, uint256 openTradesIdForPair)
        private
        view
        returns (int256)
    {
        //For some reason when calling this function from liquidateUser the orderType was being reset to zero in the positionDetails struct....... so now we just send everything individually
        //uint256 orderType = s_userTradeDetails[user][pairIndex][openTradesIdForPair].longShort;
        uint256 timeArrayLength = s_assetPairDetails[pairIndex].time.length;
        //the follwing will be 1 for the first trade, which may be confusing, not really the start index since we start at zero
        uint256 startIndex = s_userTradeDetails[user][pairIndex][openTradesIdForPair].indexBorrowPercentArray;

        /* emit StartIndex(startIndex);
        emit TimeArrayLength(timeArrayLength); */

        int256 sum;
        for (uint256 i = startIndex; i < (s_assetPairDetails[pairIndex].time.length - 1); i++) {
            sum = sum
                + s_assetPairDetails[pairIndex].borrowFee[i]
                    * int256(s_assetPairDetails[pairIndex].time[i + 1] - s_assetPairDetails[pairIndex].time[i]);
        }
        /// (SECONDS_IN_HOUR * TIME_PRECISION);
        //emit Sum(sum);

        //we need to get the last sum which will be based off the current block time
        //The following code causes an array out of index error
        //***************************** */
        // whenever we reset the borrow array we need to reset the time array
        sum = sum
            + s_assetPairDetails[pairIndex].borrowFee[timeArrayLength - 1]
                * int256(block.timestamp - s_assetPairDetails[pairIndex].time[timeArrayLength - 1]);
        //***************************** */

        int256 avgBorrowFee = sum
            / (
                int256(s_assetPairDetails[pairIndex].time.length - startIndex)
                    * int256(block.timestamp - s_assetPairDetails[pairIndex].time[startIndex])
            );

        int256 borrowFee;

        if (orderType == 0) {
            borrowFee = s_baseBorrowFeePercentage + avgBorrowFee;
            //emit AvgBorrowFeeCalculation(pairIndex, borrowFee, orderType);
            return borrowFee;
        }
        if (orderType == 1) {
            borrowFee = s_baseBorrowFeePercentage - avgBorrowFee;
            //emit AvgBorrowFeeCalculation(pairIndex, borrowFee, orderType);
            return borrowFee;
        }

        //returns borrowFee with 1e7 precision
    }

    /////////////////////////////
    // For testing purposes    //
    ////////////////////////////
    //note this function is modified for testing locally... not yet
    function getTradingPairCurrentPrice(bytes[] calldata priceUpdateData, uint256 pairIndex)
        public
        payable
        returns (PythStructs.Price memory)
    {
        uint256 updateFee = pyth.getUpdateFee(priceUpdateData);
        pyth.updatePriceFeeds{value: updateFee}(priceUpdateData);

        return (pyth.getPrice(s_assetPairDetails[pairIndex].pythPriceFeedAddress));
    }

    /////////////////////////////
    // view and pure functions //
    ////////////////////////////

    function getUserTradingPositionDetails(address user, uint256 pairIndex, uint256 openTradesIdForPair)
        external
        view
        returns (PositionDetails memory)
    {
        return s_userTradeDetails[user][pairIndex][openTradesIdForPair];
    }

    function getAssetPairDetails(uint256 pairIndex) external view returns (AssetPairDetails memory) {
        return s_assetPairDetails[pairIndex];
    }

    function getUserOpenTradesForAsset(address user, uint256 pairIndex) external view returns (uint256[3] memory) {
        return s_userOpenTrades[user][pairIndex];
    }

    //Nice job mate!!👍🏻🤩
    // leave this function with some  padding if you plan to add more trading pairs.
    function getAllUserOpenTrades(address user) external view returns (PositionDetails[15] memory) {
        PositionDetails[15] memory allOpenPositions;
        // 5 is the number of available assets
        // previously the number of assets was read from storage (may have been due to another reason, it could work now, but there is not a reason to read from storage), but we were getting errors
        for (uint256 i = 0; i < 5; i++) {
            // 3 is the max number of trades user's can have for a pair
            for (uint256 index = 0; index < 3; index++) {
                if (s_userTradeDetails[user][i][index].leverage != 0) {
                    uint256 arrayLocation = i * 3 + index;
                    allOpenPositions[arrayLocation] = (s_userTradeDetails[user][i][index]);
                } else {}
            }
        }
        return allOpenPositions;
    }

    function getTradePositionBorrowFees(address user, uint256 assetPairIndex, uint256 openTradesIdForPair)
        external
        view
        returns (int256 borrowFeeAmount)
    {
        PositionDetails memory positionDetails = s_userTradeDetails[user][assetPairIndex][openTradesIdForPair];

        int256 borrowFeePercentage =
            _calculateBorrowFee(user, assetPairIndex, positionDetails.longShort, openTradesIdForPair);

        borrowFeeAmount = borrowFeePercentage * int256(block.timestamp - positionDetails.openTime)
            * int256(positionDetails.collateralAfterFee * positionDetails.leverage)
            / (LEVERAGE_PRECISION * FEE_PRECISION * SECONDS_IN_HOUR);
    }

    function getUserLiquidationPrice(address user, uint256 assetPairIndex, uint256 openTradesIdForPair)
        external
        view
        userPositionExist(user, assetPairIndex, openTradesIdForPair)
        returns (int256 liquidationPrice, int256 borrowFeeAmount)
    {
        PositionDetails memory positionDetails = s_userTradeDetails[user][assetPairIndex][openTradesIdForPair];

        int256 borrowFeePercentage =
            _calculateBorrowFee(user, assetPairIndex, positionDetails.longShort, openTradesIdForPair);

        borrowFeeAmount = borrowFeePercentage * int256(block.timestamp - positionDetails.openTime)
            * int256(positionDetails.collateralAfterFee * positionDetails.leverage)
            / (LEVERAGE_PRECISION * FEE_PRECISION * SECONDS_IN_HOUR);
        // liquidation price precision is 1e18
        if (positionDetails.longShort == 0) {
            liquidationPrice = LEVERAGE_PRECISION * positionDetails.openPrice / positionDetails.leverage
                * (positionDetails.leverage - LEVERAGE_PRECISION) * 1e7
                + (borrowFeeAmount * LEVERAGE_PRECISION) / positionDetails.leverage;
            return (liquidationPrice, borrowFeeAmount);
        }

        if (positionDetails.longShort == 1) {
            liquidationPrice = LEVERAGE_PRECISION * positionDetails.openPrice / positionDetails.leverage
                * (positionDetails.leverage + LEVERAGE_PRECISION) * 1e7
                - (borrowFeeAmount * LEVERAGE_PRECISION) / positionDetails.leverage;
            return (liquidationPrice, borrowFeeAmount);
        }
    }

    function getTotalLongAmount(uint256 pairIndex) external view returns (int256) {
        return s_assetPairDetails[pairIndex].assetTotalLongs;
    }

    function getTotalShortAmount(uint256 pairIndex) external view returns (int256) {
        return s_assetPairDetails[pairIndex].assetTotalShorts;
    }

    function getAssetPairIndexSymbol() external view returns (string[] memory) {
        //Before it was a dyanmic array string[] memory listOfPairSymbols;
        //Now we set the size statically
        //previously, it threw an error array index out of bounds, may have to do with how memory arrays act differently than storage arrays
        //current code works. Above notes are just for reference
        string[] memory listOfPairSymbols = new string[](s_numberOfAvailableAssetPairs);
        for (uint256 i = 0; i < s_numberOfAvailableAssetPairs; i++) {
            listOfPairSymbols[i] = (s_assetPairDetails[i].pairSymbol);
        }
        return listOfPairSymbols;
    }

    function getPythPriceFeedAddress() external view returns (address) {
        return address(pyth);
    }

    function getTokenCollateralAddress() external view returns (address) {
        return s_tokenCollateralAddress;
    }

    function getCurrentBorrowRate(uint256 pairIndex) external view returns (int256) {
        AssetPairDetails memory assetPairDetails = s_assetPairDetails[pairIndex];
        uint256 arrayLength = assetPairDetails.borrowFee.length;
        int256 curentBorrowFee = assetPairDetails.borrowFee[arrayLength - 1];
        return curentBorrowFee;
    }

    function getBaseBorrowFee() external view returns (int256 baseBorrowFee) {
        baseBorrowFee = s_baseBorrowFeePercentage;
    }
}
