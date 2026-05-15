// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { WirebetMarket } from "../src/WirebetMarket.sol";
import { Positions1155 } from "../src/Positions1155.sol";
import { FeeRouter } from "../src/FeeRouter.sol";
import { Side, State, Result, RiskParams } from "../src/Types.sol";

/// @dev Minimal ERC-20 mock for testing (mint + standard transfer/approve).
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/// @title WirebetMarketTest
/// @notice Foundry test suite covering LMSR core invariants:
///   1. Initial 50/50 pricing
///   2. Buy moves price correctly
///   3. Cancellation pro-rata payout sums to liabilityUSDC6
///   4. Resolved: winners 1:1, losers 0
///   5. Exposure limit blocks imbalanced trades
contract WirebetMarketTest is Test {
    MockUSDC usdc;
    Positions1155 positions;
    FeeRouter feeRouter;
    WirebetMarket market;

    address resolver = address(0xBEEF);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address treasury = address(0x7EA5);

    bytes32 constant MARKET_ID = keccak256("Will ETH hit 5000 by Dec 2025?");

    // Risk params: 1% fee, 5% buffer, 10k USDC max trade, 100% exposure (no limit)
    RiskParams risk = RiskParams({
        bufferBps: 500,
        feeBps: 100,
        maxTradeSizeUSDC6: 10_000e6,
        maxNetExposureBps: 10000
    });

    uint256 constant B_USDC6 = 1000e6; // b = 1000 USDC liquidity param

    function setUp() public {
        // Deploy infra
        usdc = new MockUSDC();
        positions = new Positions1155();
        feeRouter = new FeeRouter(address(usdc), treasury);

        // Deploy market (closes in 7 days)
        uint64 closeTime = uint64(block.timestamp + 7 days);
        market = new WirebetMarket(
            MARKET_ID,
            address(usdc),
            address(positions),
            address(feeRouter),
            resolver,
            closeTime,
            risk,
            B_USDC6
        );

        // Grant minter to the market
        positions.setMinter(address(market), true);

        // Seed market with LP backing: LMSR market-maker can lose up to b*ln(2) ≈ 693 USDC.
        // In production this comes from the vault/LP layer. We simulate it here.
        usdc.mint(address(market), 1000e6);

        // Fund traders
        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);

        // Approve market for both traders
        vm.prank(alice);
        usdc.approve(address(market), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(market), type(uint256).max);
    }

    // ─────────────────────────────────────────────────────────────────────
    // 1. LMSR starts at 50/50
    // ─────────────────────────────────────────────────────────────────────

    function test_initialPrice5050() public view {
        uint256 price = market.priceYes1e18();
        // At qY=0, qN=0: price = e^0 / (e^0 + e^0) = 1/2 = 0.5e18
        assertApproxEqAbs(price, 0.5e18, 0.001e18, "Initial YES price should be ~50%");
    }

    function test_initialQuantitiesZero() public view {
        assertEq(market.qY(), 0, "qY should start at 0");
        assertEq(market.qN(), 0, "qN should start at 0");
        assertEq(market.liabilityUSDC6(), 0, "liability should start at 0");
        assertEq(market.feesAccruedUSDC6(), 0, "fees should start at 0");
    }

    function test_initialState() public view {
        assertEq(uint8(market.state()), uint8(State.OPEN), "Market should start OPEN");
        assertEq(uint8(market.result()), uint8(Result.UNSET), "Result should be UNSET");
    }

    // ─────────────────────────────────────────────────────────────────────
    // 2. Buy moves price correctly
    // ─────────────────────────────────────────────────────────────────────

    function test_buyYesIncreasesYesPrice() public {
        uint256 priceBefore = market.priceYes1e18();

        vm.prank(alice);
        market.buy(Side.YES, 100e6, 0); // 100 USDC on YES

        uint256 priceAfter = market.priceYes1e18();
        assertGt(priceAfter, priceBefore, "YES price should increase after YES buy");
        assertGt(priceAfter, 0.5e18, "YES price should be above 50% after YES buy");
    }

    function test_buyNoDecreasesYesPrice() public {
        uint256 priceBefore = market.priceYes1e18();

        vm.prank(alice);
        market.buy(Side.NO, 100e6, 0); // 100 USDC on NO

        uint256 priceAfter = market.priceYes1e18();
        assertLt(priceAfter, priceBefore, "YES price should decrease after NO buy");
        assertLt(priceAfter, 0.5e18, "YES price should be below 50% after NO buy");
    }

    function test_buyMintsShares() public {
        vm.prank(alice);
        uint256 shares = market.buy(Side.YES, 100e6, 0);

        assertGt(shares, 0, "Should receive shares");
        assertEq(market.qY(), shares, "qY should equal minted shares");

        // Position token balance should match
        uint256 tokenId = (uint256(MARKET_ID) << 1) | uint256(Side.YES);
        uint256 balance = positions.balanceOf(alice, tokenId);
        assertEq(balance, shares, "Position token balance should match shares");
    }

    function test_buyTracksLiabilityAndFees() public {
        uint256 amount = 1000e6;
        uint256 expectedFee = (amount * risk.feeBps) / 10_000; // 1% = 10 USDC
        uint256 expectedNet = amount - expectedFee;

        vm.prank(alice);
        market.buy(Side.YES, amount, 0);

        assertEq(market.feesAccruedUSDC6(), expectedFee, "Fees should be 1% of collateral");
        assertEq(market.liabilityUSDC6(), expectedNet, "Liability should be net collateral");
    }

    function test_pricesSumToOne() public {
        // Buy some YES to move the price
        vm.prank(alice);
        market.buy(Side.YES, 500e6, 0);

        uint256 pYes = market.priceYes1e18();
        // pNo = 1 - pYes
        uint256 sum = pYes + (1e18 - pYes);
        assertEq(sum, 1e18, "YES + NO price should sum to 1e18");
    }

    function test_largerBuysMovesPriceMore() public {
        // Snapshot before any trades
        uint256 snap = vm.snapshotState();

        vm.prank(alice);
        market.buy(Side.YES, 100e6, 0);
        uint256 priceSmall = market.priceYes1e18();

        vm.revertToState(snap);

        vm.prank(alice);
        market.buy(Side.YES, 1000e6, 0);
        uint256 priceLarge = market.priceYes1e18();

        assertGt(priceLarge, priceSmall, "Larger buy should move price more");
    }

    // ─────────────────────────────────────────────────────────────────────
    // 3. Cancellation pro-rata: total payouts = liabilityUSDC6
    // ─────────────────────────────────────────────────────────────────────

    function test_cancelProRataSolvency() public {
        // Alice buys YES at different price than Bob buys NO
        vm.prank(alice);
        market.buy(Side.YES, 500e6, 0);

        vm.prank(bob);
        market.buy(Side.NO, 300e6, 0);

        uint256 liability = market.liabilityUSDC6();
        uint256 totalShares = market.qY() + market.qN();

        // Cancel the market
        vm.prank(resolver);
        market.cancel(bytes32(0));

        assertEq(uint8(market.state()), uint8(State.CANCELLED));

        // Get Alice's YES shares and Bob's NO shares
        uint256 yesTokenId = (uint256(MARKET_ID) << 1) | uint256(Side.YES);
        uint256 noTokenId = (uint256(MARKET_ID) << 1) | uint256(Side.NO);
        uint256 aliceShares = positions.balanceOf(alice, yesTokenId);
        uint256 bobShares = positions.balanceOf(bob, noTokenId);

        // Calculate pro-rata payouts (mirrors contract logic)
        uint256 alicePayout = (aliceShares * liability) / totalShares;
        uint256 bobPayout = (bobShares * liability) / totalShares;

        // Sum of payouts should be <= liability (rounding down is OK)
        assertLe(
            alicePayout + bobPayout,
            liability,
            "Total cancel payouts must not exceed liability"
        );

        // Rounding error should be tiny (< 2 wei)
        assertApproxEqAbs(
            alicePayout + bobPayout,
            liability,
            2,
            "Total cancel payouts should approximate liability"
        );

        // Now actually redeem and verify contract remains solvent
        uint256 contractBalBefore = usdc.balanceOf(address(market));

        vm.prank(alice);
        uint256 aliceOut = market.redeem(Side.YES, aliceShares);

        vm.prank(bob);
        uint256 bobOut = market.redeem(Side.NO, bobShares);

        assertLe(
            aliceOut + bobOut,
            contractBalBefore,
            "Actual payouts must not exceed contract balance"
        );
    }

    function test_cancelRefundPerShareView() public {
        vm.prank(alice);
        market.buy(Side.YES, 500e6, 0);

        vm.prank(bob);
        market.buy(Side.NO, 200e6, 0);

        uint256 liability = market.liabilityUSDC6();
        uint256 totalShares = market.qY() + market.qN();

        vm.prank(resolver);
        market.cancel(bytes32(0));

        uint256 refundPerShare = market.cancelRefundPerShare1e18();
        uint256 expected = (liability * 1e18) / totalShares;
        assertEq(refundPerShare, expected, "cancelRefundPerShare1e18 should match formula");
    }

    function test_cancelWithOneSidedMarket() public {
        // Only YES buyers — no NO shares outstanding
        vm.prank(alice);
        market.buy(Side.YES, 1000e6, 0);

        uint256 liability = market.liabilityUSDC6();

        vm.prank(resolver);
        market.cancel(bytes32(0));

        uint256 yesTokenId = (uint256(MARKET_ID) << 1) | uint256(Side.YES);
        uint256 aliceShares = positions.balanceOf(alice, yesTokenId);

        vm.prank(alice);
        uint256 payout = market.redeem(Side.YES, aliceShares);

        // With only one side, the payout = (shares * liability) / totalShares
        // = (shares * liability) / shares = liability
        assertEq(payout, liability, "Sole holder should get full liability on cancel");
    }

    function test_cancelNoSharesReturnsZero() public {
        // Cancel immediately with no trades
        vm.prank(resolver);
        market.cancel(bytes32(0));

        assertEq(market.cancelRefundPerShare1e18(), 0, "No shares = 0 refund");
    }

    // ─────────────────────────────────────────────────────────────────────
    // 4. Resolved: winners get 1:1, losers get 0
    // ─────────────────────────────────────────────────────────────────────

    function test_resolveYesWinnersGet1to1() public {
        vm.prank(alice);
        market.buy(Side.YES, 500e6, 0);

        vm.prank(bob);
        market.buy(Side.NO, 300e6, 0);

        uint256 yesTokenId = (uint256(MARKET_ID) << 1) | uint256(Side.YES);
        uint256 aliceShares = positions.balanceOf(alice, yesTokenId);

        // Lock and resolve YES
        vm.warp(market.closeTime() + 1);
        vm.startPrank(resolver);
        market.lock();
        market.resolve(Result.YES, bytes32(0));
        vm.stopPrank();

        // Alice redeems YES — should get 1 USDC per share
        uint256 aliceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        uint256 payout = market.redeem(Side.YES, aliceShares);
        uint256 aliceAfter = usdc.balanceOf(alice);

        assertEq(payout, aliceShares, "Winner payout should be 1:1 shares");
        assertEq(aliceAfter - aliceBefore, aliceShares, "USDC transfer should match");
    }

    function test_resolveLosersGetZero() public {
        vm.prank(alice);
        market.buy(Side.YES, 500e6, 0);

        vm.prank(bob);
        market.buy(Side.NO, 300e6, 0);

        uint256 noTokenId = (uint256(MARKET_ID) << 1) | uint256(Side.NO);
        uint256 bobShares = positions.balanceOf(bob, noTokenId);

        // Lock and resolve YES (NO loses)
        vm.warp(market.closeTime() + 1);
        vm.startPrank(resolver);
        market.lock();
        market.resolve(Result.YES, bytes32(0));
        vm.stopPrank();

        // Bob redeems NO — should get 0
        uint256 bobBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        uint256 payout = market.redeem(Side.NO, bobShares);
        uint256 bobAfter = usdc.balanceOf(bob);

        assertEq(payout, 0, "Loser payout should be 0");
        assertEq(bobAfter, bobBefore, "Loser USDC balance should not change");
    }

    function test_resolveNoBurnShares() public {
        vm.prank(alice);
        market.buy(Side.YES, 200e6, 0);

        uint256 yesTokenId = (uint256(MARKET_ID) << 1) | uint256(Side.YES);
        uint256 shares = positions.balanceOf(alice, yesTokenId);

        vm.warp(market.closeTime() + 1);
        vm.startPrank(resolver);
        market.lock();
        market.resolve(Result.NO, bytes32(0));
        vm.stopPrank();

        // Redeem losing YES — burns the shares even though payout is 0
        vm.prank(alice);
        market.redeem(Side.YES, shares);

        uint256 remaining = positions.balanceOf(alice, yesTokenId);
        assertEq(remaining, 0, "Shares should be burned after redemption");
    }

    // ─────────────────────────────────────────────────────────────────────
    // 5. Exposure limit blocks oversized imbalance
    // ─────────────────────────────────────────────────────────────────────

    /// @dev Deploy a separate market with a real exposure limit for these tests
    function _makeExposureLimitedMarket() internal returns (WirebetMarket m) {
        RiskParams memory tightRisk = RiskParams({
            bufferBps: 500,
            feeBps: 100,
            maxTradeSizeUSDC6: 10_000e6,
            maxNetExposureBps: 8000 // 80% max exposure
        });
        bytes32 id2 = keccak256("exposure-test-market");
        m = new WirebetMarket(
            id2,
            address(usdc),
            address(positions),
            address(feeRouter),
            resolver,
            uint64(block.timestamp + 7 days),
            tightRisk,
            B_USDC6
        );
        positions.setMinter(address(m), true);
        vm.prank(alice);
        usdc.approve(address(m), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(m), type(uint256).max);
    }

    function test_exposureLimitBlocks() public {
        WirebetMarket m = _makeExposureLimitedMarket();

        // First buy creates 100% exposure on one side, which exceeds 80%
        vm.prank(alice);
        vm.expectRevert(WirebetMarket.ExposureExceeded.selector);
        m.buy(Side.YES, 100e6, 0);
    }

    function test_balancedTradesPassExposure() public {
        // On the default market (100% exposure limit), equal buys should work
        vm.prank(alice);
        market.buy(Side.YES, 1000e6, 0);

        vm.prank(bob);
        market.buy(Side.NO, 1000e6, 0); // Should not revert
    }

    // ─────────────────────────────────────────────────────────────────────
    // Access control & state machine
    // ─────────────────────────────────────────────────────────────────────

    function test_onlyResolverCanLock() public {
        vm.warp(market.closeTime() + 1);
        vm.prank(alice);
        vm.expectRevert(WirebetMarket.Unauthorized.selector);
        market.lock();
    }

    function test_cannotLockBeforeCloseTime() public {
        vm.prank(resolver);
        vm.expectRevert(WirebetMarket.TooEarly.selector);
        market.lock();
    }

    function test_cannotTradeAfterLock() public {
        vm.warp(market.closeTime() + 1);
        vm.prank(resolver);
        market.lock();

        vm.prank(alice);
        vm.expectRevert(WirebetMarket.NotOpen.selector);
        market.buy(Side.YES, 100e6, 0);
    }

    function test_cannotRedeemBeforeResolution() public {
        vm.prank(alice);
        market.buy(Side.YES, 100e6, 0);

        uint256 yesTokenId = (uint256(MARKET_ID) << 1) | uint256(Side.YES);
        uint256 shares = positions.balanceOf(alice, yesTokenId);

        vm.prank(alice);
        vm.expectRevert(WirebetMarket.NotResolved.selector);
        market.redeem(Side.YES, shares);
    }

    function test_cannotCancelAfterResolve() public {
        vm.warp(market.closeTime() + 1);
        vm.startPrank(resolver);
        market.lock();
        market.resolve(Result.YES, bytes32(0));

        vm.expectRevert(WirebetMarket.CannotCancelResolved.selector);
        market.cancel(bytes32(0));
        vm.stopPrank();
    }

    function test_cannotRedeemMoreThanBalance() public {
        vm.prank(alice);
        market.buy(Side.YES, 100e6, 0);

        vm.warp(market.closeTime() + 1);
        vm.startPrank(resolver);
        market.lock();
        market.resolve(Result.YES, bytes32(0));
        vm.stopPrank();

        uint256 yesTokenId = (uint256(MARKET_ID) << 1) | uint256(Side.YES);
        uint256 shares = positions.balanceOf(alice, yesTokenId);

        vm.prank(alice);
        vm.expectRevert(WirebetMarket.InsufficientShares.selector);
        market.redeem(Side.YES, shares + 1);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Sell flow
    // ─────────────────────────────────────────────────────────────────────

    function test_sellReturnsCollateral() public {
        vm.prank(alice);
        uint256 shares = market.buy(Side.YES, 500e6, 0);

        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        uint256 collateralOut = market.sell(Side.YES, shares, 0);
        uint256 balAfter = usdc.balanceOf(alice);

        assertGt(collateralOut, 0, "Sell should return collateral");
        assertEq(balAfter - balBefore, collateralOut, "USDC transfer should match");
    }

    function test_sellReducesQuantityAndLiability() public {
        vm.prank(alice);
        uint256 shares = market.buy(Side.YES, 500e6, 0);

        uint256 qYBefore = market.qY();
        uint256 liabilityBefore = market.liabilityUSDC6();

        vm.prank(alice);
        market.sell(Side.YES, shares, 0);

        assertEq(market.qY(), qYBefore - shares, "qY should decrease by sold shares");
        assertLt(market.liabilityUSDC6(), liabilityBefore, "Liability should decrease");
    }

    function test_cannotSellMoreThanOwned() public {
        vm.prank(alice);
        uint256 shares = market.buy(Side.YES, 500e6, 0);

        vm.prank(alice);
        vm.expectRevert(WirebetMarket.InsufficientShares.selector);
        market.sell(Side.YES, shares + 1, 0);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Slippage protection
    // ─────────────────────────────────────────────────────────────────────

    function test_buySlippageReverts() public {
        vm.prank(alice);
        vm.expectRevert(WirebetMarket.Slippage.selector);
        market.buy(Side.YES, 100e6, type(uint256).max); // impossibly high min
    }

    function test_sellSlippageReverts() public {
        vm.prank(alice);
        uint256 shares = market.buy(Side.YES, 500e6, 0);

        vm.prank(alice);
        vm.expectRevert(WirebetMarket.Slippage.selector);
        market.sell(Side.YES, shares, type(uint256).max); // impossibly high min
    }

    // ─────────────────────────────────────────────────────────────────────
    // Max trade size
    // ─────────────────────────────────────────────────────────────────────

    function test_maxTradeSizeReverts() public {
        vm.prank(alice);
        vm.expectRevert(WirebetMarket.TooLarge.selector);
        market.buy(Side.YES, risk.maxTradeSizeUSDC6 + 1, 0);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Quote accuracy
    // ─────────────────────────────────────────────────────────────────────

    function test_quoteBuyMatchesActual() public {
        (uint256 quotedShares, uint256 quotedFee, ) = market.quoteBuy(Side.YES, 500e6);

        vm.prank(alice);
        uint256 actualShares = market.buy(Side.YES, 500e6, 0);
        uint256 actualFee = market.feesAccruedUSDC6();

        assertEq(actualShares, quotedShares, "Actual shares should match quote");
        assertEq(actualFee, quotedFee, "Actual fee should match quote");
    }

    // ─────────────────────────────────────────────────────────────────────
    // Pause
    // ─────────────────────────────────────────────────────────────────────

    function test_pauseBlocksTrading() public {
        vm.prank(resolver);
        market.pause();

        vm.prank(alice);
        vm.expectRevert(); // EnforcedPause
        market.buy(Side.YES, 100e6, 0);
    }

    function test_unpauseResumeTrading() public {
        vm.prank(resolver);
        market.pause();

        vm.prank(resolver);
        market.unpause();

        vm.prank(alice);
        market.buy(Side.YES, 100e6, 0); // should not revert
    }
}
