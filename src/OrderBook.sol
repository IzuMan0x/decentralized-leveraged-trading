// SPDX-License-Identifier: UNLICENSED

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

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPyth} from "@pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pyth-sdk-solidity/PythStructs.sol";

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
    error OrderBook__UserPositionNotOpenForLiquidation();

    ////////////////////
    // State Variables //
    ////////////////////
    IPyth pyth;

    //note enums start at zero so LONG=0 and SHORT=1
    //This may be unecessary currently not being used
    enum PositionDirection {
        LONG,
        SHORT
    }

    //PositionDirection s_longShort;

    struct PositionDetails {
        uint256 pairNumber;
        uint64 openPrice;
        uint256 collateralAfterFee;
        uint256 leverage;
        uint256 longShort; //0 for long and 1 for short
        uint256 openTime;
        uint256 indexBorrowPercentArray;
    }
    //maybe put in fee here if we want each asset to have a different fee

    struct AssetPairDetails {
        bytes32 pythPriceFeedAddress;
        uint256 assetTotalShorts;
        uint256 assetTotalLongs;
        //the following two will be used to calculate the borrow fee for a pair
        uint256[] longShortRatio;
        uint256[] time;
        string pairSymbol;
    }

    uint256 private constant LONG_POSITION = 1;
    uint256 private constant SHORT_POSITION = 2;
    uint256 private constant FEE_PRECISION = 10_000_000; //or 1e7
    uint256 private constant LEVERAGE_PRECISION = 1_000_000;
    uint256 private constant SECONDS_IN_HOUR = 3600;
    //accepted collateral address
    address private s_tokenCollateralAddress;

    //The comments are suggested values
    //The fees are based on the total position size
    //we are going to make these constants
    uint256 private constant OPENING_FEE_PERCENTAGE = 75000; //0.075% or 75000
    uint256 private constant CLOSING_FEE_PERCENTAGE = 75000; //0.075% 75000

    //This needs to be tested
    uint256 private BASE_BORROW_FEE_PERCENTAGE = 1000; // 0.001%/h or 1000
    ///we need to add a rollerover fee as well

    //number of asset pairs currently available on the contract
    //we will use this iterate through the mapping retreive all the asset pairs
    //This will be set in the constructor should be updateable
    uint256 private s_numberOfAvailableAssetPairs;

    //Lets say 1: eth/usd 2: wbtc/usd 3: XRP/USD
    //Maybe change the mappings a bit and create an order struct in another contract
    mapping(uint256 assetPairIndex => AssetPairDetails assetPairDetails) private s_assetPairDetails;

    mapping(
        address userAddress
            => mapping(
                uint256 assetPairIndex => mapping(uint256 openTradesIncrementer => PositionDetails positionDetails)
            )
    ) private s_userTradeDetails;

    //This may be unnecessary
    mapping(address userAddress => mapping(uint256 pairIndex => uint256 numberOfOpenTrades)) private s_userOpenTrades;

    ////////////////////
    // Events         //
    ///////////////////
    event OrderClosed(address indexed user, uint256 indexed pairIndex, int256 indexed userPNL);
    event MarketTrade(address indexed user, uint256 indexed pairIndex);
    event UserLiquidated(address indexed user, uint256 pairIndex, int256 userPNL);

    ////////////////////
    // Modifiers      //
    ////////////////////
    //position and leverage needs to be more than zero
    modifier moreThanZero(uint256 amount, uint256 leverage) {
        if (amount == 0 || leverage == 0) {
            revert OrderBook__NeedsMoreThanZero();
        }
        _;
    }

    modifier userPositionExist(address user, uint256 tradeIndex, uint256 userTradesIdForPair) {
        if (s_userTradeDetails[user][tradeIndex][userTradesIdForPair].openPrice == 0) {
            revert OrderBook__UserClosingNonExistingPosition();
        }
        _;
    }

    modifier validPair(uint256 pairIndex) {
        if (s_assetPairDetails[pairIndex].pythPriceFeedAddress == 0) {
            revert OrderBook__InvalidTradingPair();
        }
        _;
    }

    modifier maxTradeCount(address user, uint256 pairIndex) {
        if (s_userOpenTrades[user][pairIndex] >= 3) {
            revert OrderBook__MaxNumberOfOpenTrades3Reached();
        }
        _;
    }

    modifier maxLeverage(uint256 leverage) {
        if (leverage > 150_000_000) {
            revert OrderBook__MaxLeverageIs150();
        }
        _;
    }

    modifier validOrderType(uint256 orderType) {
        if (orderType != 0 && orderType != 1) {
            revert OrderBook__InvalidOrderType();
        }
        _;
    }

    ////////////////////
    // Functions  🥸   //
    ////////////////////

    ////////////////////
    // Constructor    //
    ////////////////////
    constructor(
        address pythPriceFeedAddress, //pyth contract address
        address tokenCollateralAddress,
        bytes32[] memory pairPriceFeedAddressId, //pyth price id for a certain pair
        uint256[] memory pairIndex,
        string[] memory pairSymbol
    ) {
        //make sure the parameter arrays are the same size
        //maybe move this to a modifier to use for other functions
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
        }
    }

    //we will refactor the marketorder function
    //Be careful modifying this function it is very close to throwing error "stack too deep"🧐
    function marketOrder(
        uint256 pairIndex,
        uint256 amountCollateral,
        uint256 leverage,
        uint256 orderType,
        bytes[] calldata priceUpdateData
    )
        public
        payable
        moreThanZero(amountCollateral, leverage)
        validPair(pairIndex)
        maxTradeCount(msg.sender, pairIndex)
        maxLeverage(leverage)
        validOrderType(orderType)
        nonReentrant
    {
        _sendFunds(msg.sender, amountCollateral);

        _order(msg.sender, pairIndex, amountCollateral, leverage, orderType, priceUpdateData);

        //after testing change this to the function inputs, it will probably be more efficient on gas
        emit MarketTrade(msg.sender, pairIndex);
        //taken out of the event emit due to stack being too deep
        // s_userTradeDetails[msg.sender][pairIndex][s_userOpenTrades[msg.sender][pairIndex]].collateralAfterFee* leverage
    }

    function orderClose(uint256 tradeIndex, uint256 userTradesIdForPair, bytes[] calldata priceUpdateData)
        public
        userPositionExist(msg.sender, tradeIndex, userTradesIdForPair)
        nonReentrant
    {
        PositionDetails memory userPositionDetails = s_userTradeDetails[msg.sender][tradeIndex][userTradesIdForPair];

        int256 userPNL = _getUserPNL(msg.sender, userPositionDetails, userTradesIdForPair, priceUpdateData);

        //reset the trading book
        delete s_userTradeDetails[msg.sender][userPositionDetails.pairNumber][userTradesIdForPair];
        //subtracting the number of open trades
        s_userOpenTrades[msg.sender][userPositionDetails.pairNumber]--;

        if (userPNL >= 0) {
            uint256 uintUserPNL = uint256(userPNL);
            _sendFunds(msg.sender, uintUserPNL);
        }

        emit OrderClosed(msg.sender, userPositionDetails.pairNumber, userPNL);
    }

    function liquidateUser(
        address user,
        uint256 tradeIndex,
        uint256 userTradesIdForPair,
        bytes[] calldata priceUpdateData
    ) public userPositionExist(user, tradeIndex, userTradesIdForPair) nonReentrant {
        PositionDetails memory userPositionDetails = s_userTradeDetails[user][tradeIndex][userTradesIdForPair];

        int256 userPNL = _getUserPNL(msg.sender, userPositionDetails, userTradesIdForPair, priceUpdateData);

        if (userPNL <= 0) {
            delete s_userTradeDetails[user][userPositionDetails.pairNumber][userTradesIdForPair];
            s_userOpenTrades[user][userPositionDetails.pairNumber]--;
            emit UserLiquidated(user, userPositionDetails.pairNumber, userPNL);
        } else {
            revert OrderBook__UserPositionNotOpenForLiquidation();
        }
    }

    //////////////////////
    // Private Functions//
    //////////////////////
    function _getUserPNL(
        address user,
        PositionDetails memory userPositionDetails,
        uint256 userTradesIdForPair,
        bytes[] calldata priceUpdateData
    ) private returns (int256) {
        //get price with the pairIndex
        PythStructs.Price memory closePriceData =
            getTradingPairCurrentPrice(priceUpdateData, userPositionDetails.pairNumber);
        //We need to create a function that gets the average fee for the duration of the trade

        int256 borrowFeePercentage = _calculateBorrowFee(user, userPositionDetails.pairNumber, userTradesIdForPair);

        //This needs to be made an average based on the ratio of users long and short postions
        int256 totalBorrowFeeAmount = int256(borrowFeePercentage) * int256(userPositionDetails.leverage)
            * int256(userPositionDetails.collateralAfterFee) * int256(block.timestamp - userPositionDetails.openTime);

        int256 userPNL;
        int256 priceChange = int256(uint256(userPositionDetails.openPrice)) - int256(closePriceData.price);
        if (userPositionDetails.longShort == 0) {
            userPNL = int256(userPositionDetails.collateralAfterFee) - totalBorrowFeeAmount
                - int256(userPositionDetails.leverage) * priceChange * int256(userPositionDetails.collateralAfterFee);
        }
        if (userPositionDetails.longShort == 1) {
            userPNL = int256(userPositionDetails.collateralAfterFee) - totalBorrowFeeAmount
                + int256(userPositionDetails.leverage) * priceChange * int256(userPositionDetails.collateralAfterFee);
        }

        userPNL =
            userPNL - int256(_calculateOpenFee(userPositionDetails.collateralAfterFee, userPositionDetails.leverage));
        return userPNL;
    }

    //adding this for getting updating the front end however there is a possibility the priceFeed is stale, thus we dont want to pay for an update if we just reading from the
    //contract. Thus, we will just pull the userPositionDetails and calculate the PNL from the priceFeed API.
    function _getUserPnlUnsafe(
        address user,
        PositionDetails memory userPositionDetails,
        uint256 userTradesIdForPair,
        bytes[] calldata priceUpdateData
    ) private returns (int256) {
        //get price with the pairIndex
        PythStructs.Price memory closePriceData =
            getTradingPairCurrentPrice(priceUpdateData, userPositionDetails.pairNumber);
        //We need to create a function that gets the average fee for the duration of the trade

        int256 borrowFeePercentage = _calculateBorrowFee(user, userPositionDetails.pairNumber, userTradesIdForPair);

        //This needs to be made an average based on the ratio of users long and short postions
        int256 totalBorrowFeeAmount = int256(borrowFeePercentage)
            * int256(userPositionDetails.leverage / LEVERAGE_PRECISION) * int256(userPositionDetails.collateralAfterFee)
            * int256(block.timestamp - userPositionDetails.openTime);

        int256 userPNL;
        int256 priceChange = int256(uint256(userPositionDetails.openPrice)) - int256(closePriceData.price);
        if (userPositionDetails.longShort == 0) {
            userPNL = int256(userPositionDetails.collateralAfterFee) - totalBorrowFeeAmount
                - int256(userPositionDetails.leverage) * priceChange * int256(userPositionDetails.collateralAfterFee);
        }
        if (userPositionDetails.longShort == 1) {
            userPNL = int256(userPositionDetails.collateralAfterFee) - totalBorrowFeeAmount
                + int256(userPositionDetails.leverage) * priceChange * int256(userPositionDetails.collateralAfterFee);
        }

        userPNL =
            userPNL - int256(_calculateOpenFee(userPositionDetails.collateralAfterFee, userPositionDetails.leverage));
        return userPNL;
    }

    function _updatePairTotalBorrowed(uint256 orderType, uint256 pairIndex, uint256 positionSize) private {
        //This may be a little extra and not necessary
        //Here we are checking if the order is a long or short
        if (orderType == 0) {
            //orderType = PositionDirection.LONG;

            //update the total borrowed amount for long or short postion of an asset
            //make sure to test this math
            s_assetPairDetails[pairIndex].assetTotalLongs += (positionSize);
        }
        if (orderType == 1) {
            //orderType = PositionDirection.SHORT;
            s_assetPairDetails[pairIndex].assetTotalShorts += (positionSize);
        }
    }

    function _sendFunds(address user, uint256 amount) private {
        bool success = IERC20(s_tokenCollateralAddress).transferFrom(user, address(this), amount);
        if (!success) {
            revert OrderBook__TransferFailed();
        }
    }

    function _order(
        address user,
        uint256 pairIndex,
        uint256 amountCollateral,
        uint256 leverage,
        uint256 orderType,
        bytes[] calldata priceUpdateData
    ) private {
        //Watchout for math overflow
        //Here we are getting the openFee and subtracting it from the collateral
        uint256 collateralAfterFee;
        {
            collateralAfterFee = amountCollateral - _calculateOpenFee(amountCollateral, leverage);
        }

        //Here we are incrementing the number of trades a user has open for a certain asset
        //currently the max number of trades is set at 3
        s_userOpenTrades[user][pairIndex]++;

        //updating the total amount borrow for long or short positions, this should be updated everytime a trade is opened or closed
        _updatePairTotalBorrowed(orderType, pairIndex, (collateralAfterFee * (leverage / LEVERAGE_PRECISION)));

        s_assetPairDetails[pairIndex].time.push(block.timestamp);

        //note here we will be dividing by zero
        //fixed by adding one to the denominator, this will result in slightly incorrect calculations but the effect is insignificant. We will find out in testing
        s_assetPairDetails[pairIndex].longShortRatio.push(
            s_assetPairDetails[pairIndex].assetTotalLongs / (s_assetPairDetails[pairIndex].assetTotalShorts + 1 ether)
        );

        //update the total borrowed amount for long or short postion of an asset
        //make sure to test this math

        PythStructs.Price memory priceData = getTradingPairCurrentPrice(priceUpdateData, pairIndex);

        uint64 adjustedPrice = _calculateAdjustedPrice(orderType, priceData);

        //Here we are updating the user's trade position
        s_userTradeDetails[user][pairIndex][s_userOpenTrades[user][pairIndex]] = PositionDetails(
            pairIndex,
            adjustedPrice,
            collateralAfterFee,
            leverage,
            orderType,
            priceData.publishTime,
            (s_assetPairDetails[pairIndex].time.length - 1) //here we are getting the index for when we need to calculate the borrow fee when the order is closed
        );
    }

    function _calculateAdjustedPrice(uint256 orderType, PythStructs.Price memory priceData)
        private
        view
        returns (uint64)
    {
        uint64 adjustedPrice;
        if (orderType == 0) {
            adjustedPrice = uint64(priceData.price) + priceData.conf;
        }
        if (orderType == 1) {
            adjustedPrice = uint64(priceData.price) - priceData.conf;
        }

        return adjustedPrice;
    }

    function _calculateOpenFee(uint256 amountCollateral, uint256 leverage) private pure returns (uint256 openFee) {
        uint256 positionSize = amountCollateral * (leverage / LEVERAGE_PRECISION);
        openFee = positionSize * OPENING_FEE_PERCENTAGE / FEE_PRECISION;
    }

    //We want this to be dynamic and change as the amount of long and shorts change
    function _calculateBorrowFee(address user, uint256 pairIndex, uint256 openTradesIdForPair)
        private
        view
        returns (int256 borrowFee)
    {
        //Here it is correct
        //This will throw an error if there is no change in the borrow rate since the trader last opened their position
        uint256 timeArrayLength = s_assetPairDetails[pairIndex].time.length;
        uint256 startIndex = s_userTradeDetails[user][pairIndex][openTradesIdForPair].indexBorrowPercentArray;
        uint256 sum;
        for (uint256 i = startIndex; i < (s_assetPairDetails[pairIndex].time.length - 1); i++) {
            sum = sum
                + s_assetPairDetails[pairIndex].longShortRatio[i]
                    * (s_assetPairDetails[pairIndex].time[i + 1] - s_assetPairDetails[pairIndex].time[i]);
        }

        //we need to get the last sum which will be based off the current block time
        sum = sum
            + s_assetPairDetails[pairIndex].longShortRatio[timeArrayLength - 1]
                * (block.timestamp - s_assetPairDetails[pairIndex].time[timeArrayLength - 1]);

        uint256 avgBorrowRatio = sum / s_assetPairDetails[pairIndex].time.length;

        uint256 orderType = s_userTradeDetails[user][pairIndex][openTradesIdForPair].longShort;

        //This needs to be checked expecially when dealing with different types
        //For longs
        //We could simplify this more but for now it will work
        if (orderType == 0) {
            return borrowFee =
                int256(BASE_BORROW_FEE_PERCENTAGE - BASE_BORROW_FEE_PERCENTAGE * (avgBorrowRatio - 1) / avgBorrowRatio);
        }

        //For shorts
        if (orderType == 1) {
            return borrowFee = int256(BASE_BORROW_FEE_PERCENTAGE + BASE_BORROW_FEE_PERCENTAGE * (1 - avgBorrowRatio));
        }
        //if none of the conditions are met we will just return the base fee
        return borrowFee = int256(BASE_BORROW_FEE_PERCENTAGE);
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

    // The priceUpdateData needs to be retrieved from pyth API
    //uncomment the following for produciton build
    /*  function getTradingPairCurrentPrice(bytes[] calldata priceUpdateData, uint256 pairIndex)
        public
        payable
        returns (PythStructs.Price memory)
    {
        uint256 updateFee = pyth.getUpdateFee(priceUpdateData);
        pyth.updatePriceFeeds{value: updateFee}(priceUpdateData);
        //Here we have 1 for ethereum, this needs to be changed
        return (pyth.getPrice(s_assetPairDetails[pairIndex].pythPriceFeedAddress));
    } */

    /////////////////////////////
    // view and pure functions //
    ////////////////////////////

    function getUserTradingPositionDetails(address user, uint256 tradeIndex, uint256 openTradesIdForPair)
        external
        view
        returns (PositionDetails memory)
    {
        return s_userTradeDetails[user][tradeIndex][openTradesIdForPair];
    }

    function getAssetPairDetails(uint256 pairIndex) external view returns (AssetPairDetails memory) {
        return s_assetPairDetails[pairIndex];
    }

    function getUserOpenTradesForAsset(address user, uint256 pairIndex) external view returns (uint256) {
        return s_userOpenTrades[user][pairIndex];
    }

    function getUserLiquidationPrice(address user, uint256 assetPairIndex, uint256 openTradeIdForPair)
        external
        view
        returns (int256 liquidationPrice, int256 borrowFeeAmount)
    {
        PositionDetails memory positionDetails = s_userTradeDetails[user][assetPairIndex][openTradeIdForPair];

        int256 borrowFeePercentage = _calculateBorrowFee(user, assetPairIndex, openTradeIdForPair);

        //This needs to be checked
        //divided by 1e16 to get an amount with 5 decimals
        int256 borrowFeeAmount = borrowFeePercentage * int256(block.timestamp - positionDetails.openTime)
            * int256(positionDetails.collateralAfterFee * positionDetails.leverage / LEVERAGE_PRECISION)
            / int256(SECONDS_IN_HOUR) / 1e16;

        if (positionDetails.longShort == 0) {
            liquidationPrice = int256(positionDetails.leverage - LEVERAGE_PRECISION)
                * int256(uint256((positionDetails.openPrice))) / int256(positionDetails.leverage) + int256(borrowFeeAmount);
            return (liquidationPrice, borrowFeeAmount);
        }

        if (positionDetails.longShort == 1) {
            liquidationPrice = int256(positionDetails.leverage + LEVERAGE_PRECISION)
                * int256(uint256((positionDetails.openPrice))) / int256(positionDetails.leverage) - int256(borrowFeeAmount);
            return (liquidationPrice, borrowFeeAmount);
        }
    }

    function getTotalLongAmount(uint256 pairIndex) external view returns (uint256) {
        return s_assetPairDetails[pairIndex].assetTotalLongs;
    }

    function getTotalShortAmount(uint256 pairIndex) external view returns (uint256) {
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
}
