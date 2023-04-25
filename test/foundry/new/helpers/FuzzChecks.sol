// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";

import { ExpectedEventsUtil } from "./event-utils/ExpectedEventsUtil.sol";

import { OrderParametersLib } from "seaport-sol/SeaportSol.sol";

import {
    AdvancedOrder,
    Execution,
    OrderParameters,
    OrderType
} from "seaport-sol/SeaportStructs.sol";

import { OrderStatusEnum } from "seaport-sol/SpaceEnums.sol";

import { FuzzHelpers } from "./FuzzHelpers.sol";

import { FuzzTestContext } from "./FuzzTestContextLib.sol";

import { FuzzEngineLib } from "./FuzzEngineLib.sol";

import {
    TestCalldataHashContractOfferer
} from "../../../../contracts/test/TestCalldataHashContractOfferer.sol";

import {
    HashValidationZoneOfferer
} from "../../../../contracts/test/HashValidationZoneOfferer.sol";
import { ExpectedBalances } from "./ExpectedBalances.sol";

/**
 * @dev Check functions are the post-execution assertions we want to validate.
 *      Checks should be public functions that accept a FuzzTestContext as their
 *      only argument. Checks have access to the post-execution FuzzTestContext
 *      and can use it to make test assertions. The check phase happens last,
 *      immediately after execution.
 */
abstract contract FuzzChecks is Test {
    using OrderParametersLib for OrderParameters;

    using FuzzEngineLib for FuzzTestContext;
    using FuzzHelpers for AdvancedOrder;
    using FuzzHelpers for AdvancedOrder[];

    address payable testZone;
    address payable contractOfferer;

    /**
     * @dev Check that the returned `fulfilled` values were `true`.
     *
     * @param context A Fuzz test context.
     */
    function check_orderFulfilled(FuzzTestContext memory context) public {
        assertEq(
            context.returnValues.fulfilled,
            true,
            "check_orderFulfilled: not all orders were fulfilled"
        );
    }

    /**
     * @dev Check that the returned `validated` values were `true`.
     *
     * @param context A Fuzz test context.
     */
    function check_orderValidated(FuzzTestContext memory context) public {
        assertEq(
            context.returnValues.validated,
            true,
            "check_orderValidated: not all orders were validated"
        );
    }

    /**
     * @dev Check that the returned `cancelled` values were `true`.
     *
     * @param context A Fuzz test context.
     */
    function check_orderCancelled(FuzzTestContext memory context) public {
        assertEq(
            context.returnValues.cancelled,
            true,
            "check_orderCancelled: not all orders were cancelled"
        );
    }

    /**
     * @dev Check that the returned `availableOrders` array length was the
     *      expected length and matches the expected array.
     *
     * @param context A Fuzz test context.
     */
    function check_allOrdersFilled(FuzzTestContext memory context) public {
        assertEq(
            context.returnValues.availableOrders.length,
            context.executionState.orders.length,
            "check_allOrdersFilled: returnValues.availableOrders.length != orders.length"
        );
        assertEq(
            context.returnValues.availableOrders.length,
            context.expectations.expectedAvailableOrders.length,
            "check_allOrdersFilled: returnValues.availableOrders.length != expectedAvailableOrders.length"
        );

        for (uint256 i; i < context.returnValues.availableOrders.length; i++) {
            if (!context.expectations.expectedAvailableOrders[i]) {
                assertEq(
                    context.returnValues.availableOrders[i],
                    context.expectations.expectedAvailableOrders[i],
                    "check_allOrdersFilled: returnValues.availableOrders[i] != expectedAvailableOrders[i]"
                );
            }
        }
    }

    /**
     * @dev Check that the zone is getting the right calldata.
     *
     * @param context A Fuzz test context.
     */
    function check_validateOrderExpectedDataHash(
        FuzzTestContext memory context
    ) public {
        if (context.scuffDescription.pointer == 0) {
            return;
        }
        // Iterate over the orders.
        for (uint256 i; i < context.executionState.orders.length; i++) {
            OrderParameters memory order = context
                .executionState
                .orders[i]
                .parameters;

            // If the order is restricted, check the calldata.
            if (
                order.orderType == OrderType.FULL_RESTRICTED ||
                order.orderType == OrderType.PARTIAL_RESTRICTED
            ) {
                testZone = payable(order.zone);

                // Each order has a calldata hash, indexed to orders, that is
                // expected to be returned by the zone.
                bytes32 expectedCalldataHash = context
                    .expectations
                    .expectedZoneCalldataHash[i];

                bytes32 orderHash = context.executionState.orderHashes[i];

                // Use order hash to get the expected calldata hash from zone.
                // TODO: fix this in cases where contract orders are part of
                // orderHashes (the hash calculation is most likely incorrect).
                bytes32 actualCalldataHash = HashValidationZoneOfferer(testZone)
                    .orderHashToValidateOrderDataHash(orderHash);
                // Check that the expected calldata hash matches the actual
                // calldata hash.
                assertEq(
                    actualCalldataHash,
                    expectedCalldataHash,
                    "check_validateOrderExpectedDataHash: actualCalldataHash != expectedCalldataHash"
                );
            }
        }
    }

    function check_contractOrderExpectedDataHashes(
        FuzzTestContext memory context
    ) public {
        bytes32[2][] memory expectedCalldataHashes = context
            .expectations
            .expectedContractOrderCalldataHashes;

        for (uint256 i; i < context.executionState.orders.length; i++) {
            AdvancedOrder memory order = context.executionState.orders[i];

            if (order.parameters.orderType == OrderType.CONTRACT) {
                bytes32 orderHash = context.executionState.orderHashes[i];

                bytes32 expectedGenerateOrderCalldataHash = expectedCalldataHashes[
                        i
                    ][0];

                bytes32 expectedRatifyOrderCalldataHash = expectedCalldataHashes[
                        i
                    ][1];

                contractOfferer = payable(order.parameters.offerer);

                bytes32 actualGenerateOrderCalldataHash = TestCalldataHashContractOfferer(
                        contractOfferer
                    ).orderHashToGenerateOrderDataHash(orderHash);

                bytes32 actualRatifyOrderCalldataHash = TestCalldataHashContractOfferer(
                        contractOfferer
                    ).orderHashToRatifyOrderDataHash(orderHash);

                assertEq(
                    expectedGenerateOrderCalldataHash,
                    actualGenerateOrderCalldataHash,
                    "check_contractOrderExpectedDataHashes: actualGenerateOrderCalldataHash != expectedGenerateOrderCalldataHash"
                );
                assertEq(
                    expectedRatifyOrderCalldataHash,
                    actualRatifyOrderCalldataHash,
                    "check_contractOrderExpectedDataHashes: actualRatifyOrderCalldataHash != expectedRatifyOrderCalldataHash"
                );
            }
        }
    }

    /**
     * @dev Check that the returned `executions` array length is non-zero.
     *
     * @param context A Fuzz test context.
     */
    function check_executionsPresent(FuzzTestContext memory context) public {
        assertTrue(
            context.returnValues.executions.length > 0,
            "check_executionsPresent: returnValues.executions.length == 0"
        );
    }

    function check_executions(FuzzTestContext memory context) public {
        // TODO: fulfillAvailable cases return an extra expected execution

        assertEq(
            context.returnValues.executions.length,
            context.expectations.expectedExplicitExecutions.length,
            "check_executions: expectedExplicitExecutions.length != returnValues.executions.length"
        );

        for (
            uint256 i;
            (i < context.expectations.expectedExplicitExecutions.length &&
                i < context.returnValues.executions.length);
            i++
        ) {
            Execution memory actual = context.returnValues.executions[i];
            Execution memory expected = context
                .expectations
                .expectedExplicitExecutions[i];
            assertEq(
                uint256(actual.item.itemType),
                uint256(expected.item.itemType),
                "check_executions: itemType"
            );
            assertEq(
                actual.item.token,
                expected.item.token,
                "check_executions: token"
            );
            assertEq(
                actual.item.identifier,
                expected.item.identifier,
                "check_executions: identifier"
            );
            assertEq(
                actual.item.amount,
                expected.item.amount,
                "check_executions: amount"
            );
            assertEq(
                address(actual.item.recipient),
                address(expected.item.recipient),
                "check_executions: recipient"
            );
            assertEq(
                actual.conduitKey,
                expected.conduitKey,
                "check_executions: conduitKey"
            );
            assertEq(
                actual.offerer,
                expected.offerer,
                "check_executions: offerer"
            );
        }
    }

    function check_expectedTransferEventsEmitted(
        FuzzTestContext memory context
    ) public {
        ExpectedEventsUtil.checkExpectedTransferEvents(context);
    }

    function check_expectedSeaportEventsEmitted(
        FuzzTestContext memory context
    ) public {
        ExpectedEventsUtil.checkExpectedSeaportEvents(context);
    }

    function check_expectedBalances(FuzzTestContext memory context) public {
        ExpectedBalances balanceChecker = context.testHelpers.balanceChecker();
        balanceChecker.markAccountBalanceAsMaximum(
            context.executionState.caller
        );
        balanceChecker.checkBalances();
    }

    /**
     * @dev Check that the order status is in expected state.
     *
     * @param context A Fuzz test context.
     */
    function check_orderStatusFullyFilled(
        FuzzTestContext memory context
    ) public {
        for (uint256 i; i < context.executionState.orders.length; i++) {
            AdvancedOrder memory order = context.executionState.orders[i];

            bytes32 orderHash = context.executionState.orderHashes[i];

            (, , uint256 totalFilled, uint256 totalSize) = context
                .seaport
                .getOrderStatus(orderHash);

            if (
                context.executionState.preExecOrderStatuses[i] ==
                OrderStatusEnum.FULFILLED
            ) {
                assertEq(
                    totalFilled,
                    1,
                    "check_orderStatusFullyFilled: totalFilled != 1"
                );
                assertEq(
                    totalSize,
                    1,
                    "check_orderStatusFullyFilled: totalSize != 1"
                );
            } else if (
                context.executionState.preExecOrderStatuses[i] ==
                OrderStatusEnum.PARTIAL
            ) {
                if (context.expectations.expectedAvailableOrders[i]) {
                    assertEq(
                        totalFilled,
                        context
                            .expectations
                            .expectedFillFractions[i]
                            .finalFilledNumerator,
                        "check_orderStatusFullyFilled: totalFilled != expected partial"
                    );
                    assertEq(
                        totalSize,
                        context
                            .expectations
                            .expectedFillFractions[i]
                            .finalFilledDenominator,
                        "check_orderStatusFullyFilled: totalSize != expected partial"
                    );
                } else {
                    assertEq(
                        totalFilled,
                        context
                            .expectations
                            .expectedFillFractions[i]
                            .originalStatusNumerator,
                        "check_orderStatusFullyFilled: totalFilled != expected partial (skipped)"
                    );
                    assertEq(
                        totalSize,
                        context
                            .expectations
                            .expectedFillFractions[i]
                            .originalStatusDenominator,
                        "check_orderStatusFullyFilled: totalSize != expected partial (skipped)"
                    );
                }
            } else if (context.expectations.expectedAvailableOrders[i]) {
                if (order.parameters.orderType == OrderType.CONTRACT) {
                    // TODO: This just checks the nonce has been incremented
                    // at least once. It should be incremented once for each
                    // call to `generateOrder`.  So, this check should sum the
                    // expected number of calls to `generateOrder` and check
                    // that the nonce has been incremented that many times.
                    uint256 currentNonce = context
                        .seaport
                        .getContractOffererNonce(order.parameters.offerer);

                    uint256 contractOffererSpecificContractNonce = context
                        .executionState
                        .contractOffererNonce +
                        uint256(uint160(order.parameters.offerer));

                    assertTrue(
                        currentNonce - contractOffererSpecificContractNonce > 0,
                        "FuzzChecks: contract offerer nonce not incremented"
                    );
                } else {
                    assertEq(
                        totalFilled,
                        order.numerator,
                        "FuzzChecks: totalFilled != numerator"
                    );
                    assertEq(
                        totalSize,
                        order.denominator,
                        "FuzzChecks: totalSize != denominator"
                    );
                    assertTrue(totalSize != 0, "FuzzChecks: totalSize != 0");
                    assertTrue(
                        totalFilled != 0,
                        "FuzzChecks: totalFilled != 0"
                    );
                }
            } else {
                assertTrue(
                    totalFilled == 0,
                    "check_orderStatusFullyFilled: totalFilled != 0"
                );
            }
        }
    }

    function check_ordersValidated(FuzzTestContext memory context) public {
        // Iterate over all orders and if the order was validated pre-execution,
        // check that calling `getOrderStatus` on the order hash returns `true`
        // for `isValid`. Note that contract orders cannot be validated.
        for (
            uint256 i;
            i < context.executionState.preExecOrderStatuses.length;
            i++
        ) {
            // Only check orders that were validated pre-execution.
            if (
                context.executionState.preExecOrderStatuses[i] ==
                OrderStatusEnum.VALIDATED
            ) {
                bytes32 orderHash = context.executionState.orderHashes[i];
                (bool isValid, , , ) = context.seaport.getOrderStatus(
                    orderHash
                );
                assertTrue(isValid, "check_ordersValidated: !isValid");
            }
        }
    }
}

function fuzzCheckName(bytes4 selector) pure returns (string memory) {
    if (selector == FuzzChecks.check_orderFulfilled.selector) {
        return "check_orderFulfilled";
    }
    if (selector == FuzzChecks.check_orderValidated.selector) {
        return "check_orderValidated";
    }
    if (selector == FuzzChecks.check_orderCancelled.selector) {
        return "check_orderCancelled";
    }
    if (selector == FuzzChecks.check_allOrdersFilled.selector) {
        return "check_allOrdersFilled";
    }
    if (selector == FuzzChecks.check_validateOrderExpectedDataHash.selector) {
        return "check_validateOrderExpectedDataHash";
    }
    if (selector == FuzzChecks.check_contractOrderExpectedDataHashes.selector) {
        return "check_contractOrderExpectedDataHashes";
    }
    if (selector == FuzzChecks.check_executionsPresent.selector) {
        return "check_executionsPresent";
    }
    if (selector == FuzzChecks.check_executions.selector) {
        return "check_executions";
    }
    if (selector == FuzzChecks.check_expectedTransferEventsEmitted.selector) {
        return "check_expectedTransferEventsEmitted";
    }
    if (selector == FuzzChecks.check_expectedSeaportEventsEmitted.selector) {
        return "check_expectedSeaportEventsEmitted";
    }
    if (selector == FuzzChecks.check_expectedBalances.selector) {
        return "check_expectedBalances";
    }
    if (selector == FuzzChecks.check_orderStatusFullyFilled.selector) {
        return "check_orderStatusFullyFilled";
    }
    if (selector == FuzzChecks.check_ordersValidated.selector) {
        return "check_ordersValidated";
    }
}
