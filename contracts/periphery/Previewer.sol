// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { FixedPointMathLib } from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import { InterestRateModel, AlreadyMatured } from "../InterestRateModel.sol";
import { ExactlyOracle } from "../ExactlyOracle.sol";
import { FixedLib } from "../utils/FixedLib.sol";
import { Auditor } from "../Auditor.sol";
import { Market } from "../Market.sol";

/// @title Previewer
/// @notice Contract to be consumed by Exactly's front-end dApp.
contract Previewer {
  using FixedPointMathLib for uint256;
  using FixedPointMathLib for int256;
  using FixedLib for FixedLib.Position;
  using FixedLib for FixedLib.Pool;
  using FixedLib for uint256;

  Auditor public immutable auditor;

  struct FixedPosition {
    uint256 maturity;
    FixedLib.Position position;
  }

  struct FixedLiquidity {
    uint256 maturity;
    uint256 assets;
    uint256 utilization;
  }

  struct MarketAccount {
    Market market;
    uint8 decimals;
    string assetSymbol;
    uint256 oraclePrice;
    uint128 penaltyRate;
    uint128 adjustFactor;
    uint8 maxFuturePools;
    bool isCollateral;
    uint256 floatingDepositShares;
    uint256 floatingDepositAssets;
    uint256 floatingBorrowShares;
    uint256 floatingBorrowAssets;
    uint256 floatingAvailableLiquidity;
    FixedPosition[] fixedDepositPositions;
    FixedPosition[] fixedBorrowPositions;
    FixedLiquidity[] fixedAvailableLiquidity;
  }

  constructor(Auditor auditor_) {
    auditor = auditor_;
  }

  /// @notice Gets the assets plus yield offered by a maturity when depositing a certain amount.
  /// @param market address of the market.
  /// @param maturity maturity date/pool where the assets will be deposited.
  /// @param assets amount of assets that will be deposited.
  /// @return positionAssets amount plus yield that the depositor will receive after maturity.
  function previewDepositAtMaturity(
    Market market,
    uint256 maturity,
    uint256 assets
  ) public view returns (uint256 positionAssets) {
    if (block.timestamp > maturity) revert AlreadyMatured();

    return assets + getFixedDepositYield(market, maturity, assets);
  }

  /// @notice Gets the assets plus yield offered by all VALID maturities when depositing a certain amount.
  /// @param market address of the market.
  /// @param assets amount of assets that will be deposited.
  /// @return positionAssetsMaturities array containing amount plus yield that user will receive after each maturity.
  function previewDepositAtAllMaturities(Market market, uint256 assets)
    external
    view
    returns (FixedLiquidity[] memory positionAssetsMaturities)
  {
    FixedLib.Pool memory pool;
    uint256 maxFuturePools = market.maxFuturePools();
    uint256 nextMaturity = block.timestamp - (block.timestamp % FixedLib.INTERVAL) + FixedLib.INTERVAL;
    positionAssetsMaturities = new FixedLiquidity[](maxFuturePools);
    uint256 fullUtilization = market.interestRateModel().fixedFullUtilization();
    for (uint256 i = 0; i < maxFuturePools; i++) {
      uint256 maturity = nextMaturity + FixedLib.INTERVAL * i;
      (pool.borrowed, pool.supplied, , ) = market.fixedPools(maturity);
      uint256 memFloatingAssetsAverage = floatingAssetsAverage(market);

      positionAssetsMaturities[i] = FixedLiquidity({
        maturity: maturity,
        assets: previewDepositAtMaturity(market, maturity, assets),
        utilization: memFloatingAssetsAverage > 0
          ? (pool.borrowed + assets).divWadDown(pool.supplied + memFloatingAssetsAverage.divWadDown(fullUtilization))
          : 0
      });
    }
  }

  /// @notice Gets the amount plus fees to be repaid at maturity when borrowing certain amount of assets.
  /// @param market address of the market.
  /// @param maturity maturity date/pool where the assets will be borrowed.
  /// @param assets amount of assets that will be borrowed.
  /// @return positionAssets amount plus fees that the depositor will repay at maturity.
  function previewBorrowAtMaturity(
    Market market,
    uint256 maturity,
    uint256 assets
  ) external view returns (uint256 positionAssets, uint256 utilizationAfter) {
    FixedLib.Pool memory pool;
    (pool.borrowed, pool.supplied, , ) = market.fixedPools(maturity);
    uint256 fullUtilization = market.interestRateModel().fixedFullUtilization();
    uint256 memFloatingAssetsAverage = floatingAssetsAverage(market);

    uint256 fees = assets.mulWadDown(
      market.interestRateModel().getFixedBorrowRate(
        maturity,
        assets,
        pool.borrowed,
        pool.supplied,
        memFloatingAssetsAverage
      )
    );
    positionAssets = assets + fees;
    utilizationAfter = memFloatingAssetsAverage > 0
      ? (pool.borrowed + assets).divWadDown(pool.supplied + memFloatingAssetsAverage.divWadDown(fullUtilization))
      : 0;
  }

  /// @notice Gets the amount to be withdrawn for a certain positionAmount of assets at maturity.
  /// @param market address of the market.
  /// @param maturity maturity date/pool where the assets will be withdrawn.
  /// @param positionAssets amount of assets that will be tried to withdraw.
  /// @return withdrawAssets amount that will be withdrawn.
  function previewWithdrawAtMaturity(
    Market market,
    uint256 maturity,
    uint256 positionAssets
  ) external view returns (uint256 withdrawAssets) {
    if (block.timestamp >= maturity) return positionAssets;

    FixedLib.Pool memory pool;
    (pool.borrowed, pool.supplied, , ) = market.fixedPools(maturity);

    withdrawAssets = positionAssets.divWadDown(
      1e18 +
        market.interestRateModel().getFixedBorrowRate(
          maturity,
          positionAssets,
          pool.borrowed,
          pool.supplied,
          floatingAssetsAverage(market)
        )
    );
  }

  /// @notice Gets the assets that will be repaid when repaying a certain amount at the current maturity.
  /// @param market address of the market.
  /// @param maturity maturity date/pool where the assets will be repaid.
  /// @param positionAssets amount of assets that will be subtracted from the position.
  /// @param borrower address of the borrower.
  /// @return repayAssets amount of assets that will be repaid.
  function previewRepayAtMaturity(
    Market market,
    uint256 maturity,
    uint256 positionAssets,
    address borrower
  ) external view returns (uint256 repayAssets) {
    if (block.timestamp >= maturity) {
      return positionAssets + positionAssets.mulWadDown((block.timestamp - maturity) * market.penaltyRate());
    }

    FixedLib.Position memory position;
    (position.principal, position.fee) = market.fixedBorrowPositions(maturity, borrower);

    return
      positionAssets - getFixedDepositYield(market, maturity, position.scaleProportionally(positionAssets).principal);
  }

  /// @notice Function to get a certain account extended data.
  /// @param account address which the extended data will be calculated.
  /// @return data extended accountability of all markets for the account.
  function accounts(address account) external view returns (MarketAccount[] memory data) {
    ExactlyOracle oracle = auditor.oracle();
    uint256 markets = auditor.accountMarkets(account);
    uint256 maxValue = auditor.getAllMarkets().length;
    data = new MarketAccount[](maxValue);
    for (uint256 i = 0; i < maxValue; ++i) {
      Market market = auditor.getAllMarkets()[i];
      (uint128 adjustFactor, uint8 decimals, , ) = auditor.markets(market);
      data[i] = MarketAccount({
        market: market,
        decimals: decimals,
        assetSymbol: market.asset().symbol(),
        oraclePrice: oracle.getAssetPrice(market),
        penaltyRate: uint128(market.penaltyRate()),
        adjustFactor: adjustFactor,
        maxFuturePools: market.maxFuturePools(),
        isCollateral: markets & (1 << i) != 0 ? true : false,
        floatingDepositShares: market.balanceOf(account),
        floatingDepositAssets: market.maxWithdraw(account),
        floatingBorrowShares: market.flexibleBorrowPositions(account),
        floatingBorrowAssets: market.maxRepay(account),
        floatingAvailableLiquidity: floatingAvailableLiquidity(market),
        fixedAvailableLiquidity: fixedAvailableLiquidity(market),
        fixedDepositPositions: maturityPositions(account, market.fixedDeposits, market.fixedDepositPositions),
        fixedBorrowPositions: maturityPositions(account, market.fixedBorrows, market.fixedBorrowPositions)
      });
    }
  }

  function fixedAvailableLiquidity(Market market) internal view returns (FixedLiquidity[] memory availableLiquidities) {
    availableLiquidities = new FixedLiquidity[](market.maxFuturePools());
    uint256 fullUtilization = market.interestRateModel().fixedFullUtilization();
    for (uint256 i = 0; i < market.maxFuturePools(); i++) {
      uint256 maturity = block.timestamp - (block.timestamp % FixedLib.INTERVAL) + FixedLib.INTERVAL * (i + 1);
      FixedLib.Pool memory pool;
      (pool.borrowed, pool.supplied, , ) = market.fixedPools(maturity);

      uint256 maxAssets = market.floatingAssets().mulWadDown(1e18 - market.reserveFactor());
      uint256 memFloatingAssetsAverage = floatingAssetsAverage(market);

      availableLiquidities[i] = FixedLiquidity({
        maturity: maturity,
        assets: Math.min(
          maxAssets - Math.min(maxAssets, market.floatingBackupBorrowed() + market.floatingDebt()),
          floatingAssetsAverage(market)
        ) +
          pool.supplied -
          Math.min(pool.supplied, pool.borrowed),
        utilization: memFloatingAssetsAverage > 0
          ? pool.borrowed.divWadDown(pool.supplied + memFloatingAssetsAverage.divWadDown(fullUtilization))
          : 0
      });
    }
  }

  function floatingAvailableLiquidity(Market market) internal view returns (uint256) {
    uint256 maxAssets = market.floatingAssets().mulWadDown(1e18 - market.reserveFactor());
    return maxAssets - Math.min(maxAssets, market.floatingBackupBorrowed() + market.floatingDebt());
  }

  function maturityPositions(
    address account,
    function(address) external view returns (uint256) getMaturities,
    function(uint256, address) external view returns (uint256, uint256) getPositions
  ) internal view returns (FixedPosition[] memory userMaturityPositions) {
    uint256 userMaturityCount = 0;
    FixedPosition[] memory allMaturityPositions = new FixedPosition[](224);
    uint256 packedMaturities = getMaturities(account);
    for (uint256 i = 0; i < 224; ++i) {
      if (((packedMaturities >> 32) & (1 << i)) != 0) {
        uint256 maturity = (packedMaturities % (1 << 32)) + (i * FixedLib.INTERVAL);
        (uint256 principal, uint256 fee) = getPositions(maturity, account);
        allMaturityPositions[userMaturityCount].maturity = maturity;
        allMaturityPositions[userMaturityCount].position = FixedLib.Position(principal, fee);
        ++userMaturityCount;
      }
      if ((1 << i) > packedMaturities) break;
    }

    userMaturityPositions = new FixedPosition[](userMaturityCount);
    for (uint256 i = 0; i < userMaturityCount; ++i) userMaturityPositions[i] = allMaturityPositions[i];
  }

  function getFixedDepositYield(
    Market market,
    uint256 maturity,
    uint256 assets
  ) internal view returns (uint256 yield) {
    FixedLib.Pool memory pool;
    (pool.borrowed, pool.supplied, pool.unassignedEarnings, pool.lastAccrual) = market.fixedPools(maturity);
    pool.unassignedEarnings -= pool.unassignedEarnings.mulDivDown(
      block.timestamp - pool.lastAccrual,
      maturity - pool.lastAccrual
    );
    (yield, ) = pool.getDepositYield(assets, market.backupFeeRate());
  }

  function floatingAssetsAverage(Market market) internal view returns (uint256) {
    uint256 dampSpeedFactor = market.floatingAssets() < market.floatingAssetsAverage()
      ? market.dampSpeedDown()
      : market.dampSpeedUp();
    uint256 averageFactor = uint256(
      1e18 - (-int256(dampSpeedFactor * (block.timestamp - market.lastAverageUpdate()))).expWad()
    );
    return
      market.floatingAssetsAverage().mulWadDown(1e18 - averageFactor) +
      averageFactor.mulWadDown(market.floatingAssets());
  }
}
