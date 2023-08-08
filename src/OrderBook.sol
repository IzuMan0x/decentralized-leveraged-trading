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

contract OrderBook is ReentrancyGuard, Ownable {
    ////////////////////
    //Errors          //
    ////////////////////
    error OrderBook__NeedsMoreThanZero();
    error OrderBook__UserClosingNonExistingPosition();
    error OrderBook__InvalidTradingPair();
    error OrderBook__MaxNumberOfOpenTrades5Reached();
    error OrderBook__TransferFailed();

    ////////////////////
    // State Variables //
    ////////////////////
    uint256 private constant LONG_POSITION = 1;
    uint256 private constant SHORT_POSITION = 2;
    uint256 private constant FEE_PRECISION = 1_000_000; //or 1e6
    //accepted collateral address
    address private s_tokenCollateralAddress;

    //The comments are suggested values
    //The fees are based on the total position size
    uint256 private s_openFeePercentage; //0.075% or 75000
    uint256 private s_closingFeePercentage; //0.075% 75000

    //This needs to be tested
    uint256 private s_baseBorrowFeePercentage; // 0.001%/h or 1000

    //Lets say 1: eth/usd 2: wbtc/usd 3: XRP/USD
    mapping(uint256 pairIndex => address priceFeedAddress) private s_tradingPairs;
    mapping(address userTrades => mapping(uint256 tradeIndex => uint256[] positionDetails)) private s_userTrades;
    mapping(address userAddress => uint256 openTrades) private s_userOpenTrades;
    mapping(uint256 pairIndex => uint256[] totalPositionsSize) private s_longShortTotal; //uint256[] index 1 is for longs and index 2 is for shorts

    ////////////////////
    // Events         //
    ///////////////////
    event OrderClosed(address indexed user, uint256 indexed pairIndex, int256 indexed userPNL);
    event MarketTrade(address indexed user, uint256 indexed pairIndex, uint256 indexed positionSize);

    ////////////////////
    // Modifiers      //
    ////////////////////
    //position nad leverage needs to be more than zero
    modifier moreThanZero(uint256 amount, uint256 leverage) {
        if (amount == 0 || leverage == 0) {
            revert OrderBook__NeedsMoreThanZero();
        }
        _;
    }

    modifier userPositionExist(address user, uint256 tradeIndex) {
        if (s_userTrades[user][tradeIndex][1] == 0) {
            revert OrderBook__UserClosingNonExistingPosition();
        }
        _;
    }

    modifier validPair(uint256 pairIndex) {
        if (s_tradingPairs[pairIndex] == address(0)) {
            revert OrderBook__InvalidTradingPair();
        }
        _;
    }

    modifier maxTradeCount(address user) {
        if (s_userOpenTrades[user] >= 5) {
            revert OrderBook__MaxNumberOfOpenTrades5Reached();
        }
        _;
    }

    ////////////////////
    // Functions  🥸   //
    ////////////////////
    constructor(
        address tokenCollateralAddress,
        uint256 openFeePercentage,
        uint256 closingFeePercentage,
        uint256 baseBorrowFeePercentage
    ) {
        s_tokenCollateralAddress = tokenCollateralAddress;
        s_openFeePercentage = openFeePercentage;
        s_closingFeePercentage = closingFeePercentage;
        s_baseBorrowFeePercentage = baseBorrowFeePercentage;
    }

    function marketOrder(uint256 pairIndex, uint256 amountCollateral, uint256 leverage, uint8 orderType)
        public
        moreThanZero(amountCollateral, leverage)
        validPair(pairIndex)
        maxTradeCount(msg.sender)
        nonReentrant
    {
        bool success = IERC20(s_tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert OrderBook__TransferFailed();
        }
        uint256 openFee = _calculateOpenFee(pairIndex, amountCollateral, leverage, orderType);
        uint256 collateralAfterFee = amountCollateral - openFee;
        //This needs to be changed to a oracle
        uint256 openTime = block.timestamp;
        uint256 openPrice = 0.5 ether;

        s_userOpenTrades[msg.sender]++;

        //We might be able to just store the total position size and not the collateral amount and leverage

        s_userTrades[msg.sender][pairIndex] = [pairIndex, openPrice, collateralAfterFee, leverage, orderType, openTime];

        emit MarketTrade(msg.sender, pairIndex, collateralAfterFee * leverage);
    }

    function orderClose(uint256 tradeIndex) public userPositionExist(msg.sender, tradeIndex) nonReentrant {
        /* [uint256 pairIndex,
            uint256 openPrice,
            uint256 amountCollateral,
            uint256 leverage,
            uint256 orderType,
            uint256 openTime,]
         = s_userTrades[msg.sender][tradeIndex]; */

        uint256[] memory orderDetails = s_userTrades[msg.sender][tradeIndex];

        uint256 pairIndex = orderDetails[1];
        uint256 openPrice = orderDetails[2];
        uint256 amountCollateral = orderDetails[3];
        uint256 leverage = orderDetails[4];
        uint256 orderType = orderDetails[5];
        uint256 openTime = orderDetails[6];

        uint256 feePercentage;

        //get price with teh pairIndex
        uint256 closePrice = 1 ether;

        if (orderType == 1) {
            (feePercentage,) = calculateBorrowFee(pairIndex, amountCollateral, leverage, orderType);
        }

        if (orderType == 2) {
            (, feePercentage) = calculateBorrowFee(pairIndex, amountCollateral, leverage, orderType);
        }

        //This needs to be made an average based on the ratio of users long and short postions
        uint256 totalBorrowFee = feePercentage * leverage * amountCollateral * (block.timestamp - openTime);
        int256 userPNL;
        uint256 userTradeChange;
        bool priceIncrease;

        //For now we will have a static borrow fee
        /* if (openPrice >= closePrice) {
            //before closing fee
            userTradeChange = (openPrice - closePrice) * leverage * amountCollateral;
            priceIncrease = true;
        }
        if( openPrice <= closePrice){
            userTradeChange = (closePrice-openPrice) * leverage * amountCollateral;
            priceIncrease = false;
        }
        */
        if (orderType == 1) {
            userPNL = int256((closePrice - openPrice) * leverage * amountCollateral);
        }
        if (orderType == 2) {
            userPNL = int256((openPrice - closePrice) * leverage * amountCollateral);
        }

        userPNL = userPNL - int256(_calculateOpenFee(pairIndex, amountCollateral, leverage, orderType) - totalBorrowFee);
        //reset the trading book
        delete s_userTrades[msg.sender][pairIndex];
        if (userPNL >= 0) {
            uint256 uintUserPNL = uint256(userPNL);
            bool success = IERC20(s_tokenCollateralAddress).transferFrom(msg.sender, address(this), uintUserPNL);
            if (!success) {
                revert OrderBook__TransferFailed();
            }
        }

        emit OrderClosed(msg.sender, pairIndex, userPNL);
    }

    function _calculateOpenFee(uint256 pairIndex, uint256 amountCollateral, uint256 leverage, uint256 orderType)
        private
        view
        returns (uint256 openFee)
    {
        uint256 positionSize = amountCollateral * leverage;
        openFee = positionSize * s_openFeePercentage / FEE_PRECISION;
    }

    function calculateBorrowFee(uint256 pairIndex, uint256 amountCollateral, uint256 leverage, uint256 orderType)
        private
        view
        returns (uint256 borrowFeeLong, uint256 borrowFeeShort)
    {
        uint256 longTotal = s_longShortTotal[pairIndex][LONG_POSITION];
        uint256 shortTotal = s_longShortTotal[pairIndex][SHORT_POSITION];
        if (longTotal == shortTotal) {
            return (borrowFeeLong = s_baseBorrowFeePercentage, borrowFeeShort = s_baseBorrowFeePercentage);
        }
        if (longTotal > shortTotal) {
            uint256 difference = longTotal - shortTotal;
            return (borrowFeeLong = s_baseBorrowFeePercentage * difference, borrowFeeShort = s_baseBorrowFeePercentage);
        }
        if (longTotal < shortTotal) {
            uint256 difference = shortTotal - longTotal;
            return (borrowFeeLong = s_baseBorrowFeePercentage, borrowFeeShort = s_baseBorrowFeePercentage * difference);
        }
    }
}
