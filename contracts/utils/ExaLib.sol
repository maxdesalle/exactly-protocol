// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IExafin.sol";
import "../utils/DecimalMath.sol";

library ExaLib {
    using DecimalMath for uint256;
    using DecimalMath for Double;
    using SafeCast for uint256;

    event DistributedSupplierExa(
        address indexed exafin,
        address indexed supplier,
        uint supplierDelta,
        uint exaSupplyIndex
    );

    // Double precision
    uint224 public constant EXA_INITIAL_INDEX = 1e36; 

    struct MarketRewardsState {
        uint224 index;
        uint32 block;
    }

    struct ExaState {
        uint256 exaSpeed;
        MarketRewardsState exaSupplyState;
        MarketRewardsState exaBorrowState;
        mapping(address => uint256) exaSupplierIndex;
        mapping(address => uint256) exaBorrowerIndex;
    }

    struct RewardsState {
        uint256 exaRate;
        mapping(address => ExaLib.ExaState) exaState;
        mapping(address => uint) exaAccruedUser;
    }

    /**
     * @notice Accrue EXA to the market by updating the supply index
     * @param exafinAddress The market whose supply index to update
     */
    function updateExaSupplyIndex(
        RewardsState storage exafinState, 
        address exafinAddress
    ) external {
        _updateExaSupplyIndex(exafinState, exafinAddress);
    }

    function _updateExaSupplyIndex(        
        RewardsState storage exafinState, 
        address exafinAddress
    ) internal {
        ExaState storage exaState = exafinState.exaState[exafinAddress];
        MarketRewardsState storage supplyState = exaState.exaSupplyState;
        uint supplySpeed = exaState.exaSpeed;
        uint blockNumber = block.number;
        uint deltaBlocks = (blockNumber - uint(supplyState.block));
        if (deltaBlocks > 0 && supplySpeed > 0) {
            // TODO: This value needs to be reviewed, to validate
            // what does it mean the "totalDeposits"
            uint256 supplyTokens = IExafin(exafinAddress).totalDeposits();
            uint256 exaAccruedDelta = deltaBlocks.mul_(supplySpeed);

            Double memory ratio = supplyTokens > 0 ? exaAccruedDelta.fraction(supplyTokens) : Double({value: 0});
            Double memory index = Double({value: supplyState.index}).add_(ratio);
            
            exaState.exaSupplyState = MarketRewardsState({
                index: index.value.toUint224(),
                block: blockNumber.toUint32()
            });
        } else if (deltaBlocks > 0) {
            supplyState.block = blockNumber.toUint32();
        }
    }

    /**
     * @notice Calculate COMP accrued by a supplier and possibly transfer it to them
     * @param exafinAddress The market in which the supplier is interacting
     * @param supplier The address of the supplier to distribute COMP to
     */
    function distributeSupplierExa(
        RewardsState storage exafinState, 
        address exafinAddress,
        address supplier
    ) external {
        ExaState storage exaState = exafinState.exaState[exafinAddress];
        MarketRewardsState storage supplyState = exaState.exaSupplyState;
        Double memory supplyIndex = Double({value: supplyState.index});
        Double memory supplierIndex = Double({value: exaState.exaSupplierIndex[supplier]});
        exaState.exaSupplierIndex[supplier] = supplyIndex.value;

        if (supplierIndex.value == 0 && supplyIndex.value > 0) {
            supplierIndex.value = EXA_INITIAL_INDEX;
        }

        Double memory deltaIndex = supplyIndex.sub_(supplierIndex);

        uint supplierTokens = IExafin(exafinAddress).suppliesOf(supplier);
        uint supplierDelta = supplierTokens.mul_(deltaIndex);
        uint supplierAccrued = exafinState.exaAccruedUser[supplier] + supplierDelta;
        exafinState.exaAccruedUser[supplier] = supplierAccrued;
        emit DistributedSupplierExa(exafinAddress, supplier, supplierDelta, supplierIndex.value);
    }

    /**
     * @notice Set EXA speed for a single market
     * @param exafinAddress The market whose EXA speed to update
     * @param exaSpeed New EXA speed for market
     */
    function setExaSpeed(
        RewardsState storage exafinState, 
        address exafinAddress,
        uint256 exaSpeed
    ) external returns (bool) {
        ExaState storage state = exafinState.exaState[exafinAddress];
        uint currentExaSpeed = state.exaSpeed;
        if (currentExaSpeed != 0) {
            // uint256 borrowIndex = Exp({mantissa: cToken.borrowIndex()});
            _updateExaSupplyIndex(exafinState, exafinAddress);
            // updateCompBorrowIndex(address(cToken), borrowIndex);
        } else if (exaSpeed != 0) {
            if (state.exaSupplyState.index == 0 && state.exaSupplyState.block == 0) {
                state.exaSupplyState = MarketRewardsState({
                    index: EXA_INITIAL_INDEX,
                    block: block.number.toUint32()
                });
            }

            if (state.exaBorrowState.index == 0 && state.exaBorrowState.block == 0) {
                state.exaBorrowState = MarketRewardsState({
                    index: EXA_INITIAL_INDEX,
                    block: block.number.toUint32()
                });
            }
        }

        if (currentExaSpeed != exaSpeed) {
            exafinState.exaState[exafinAddress].exaSpeed = exaSpeed;
            return true;
        }

        return false;
    }

}