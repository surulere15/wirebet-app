// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { WirebetMarket } from "../src/WirebetMarket.sol";
import { Positions1155 } from "../src/Positions1155.sol";
import { FeeRouter } from "../src/FeeRouter.sol";
import { Side, State, Result, RiskParams } from "../src/Types.sol";

/// @dev Minimal ERC-20 mock
contract FuzzMockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function decimals() public pure override returns (uint8) { return 6; }
}

/// @title MarketHandler
/// @notice Handler contract for invariant fuzzing. Exposes bounded buy/sell
///         actions that the fuzzer calls in random order.
contract MarketHandler is Test {
    FuzzMockUSDC public usdc;
    WirebetMarket public market;
    Positions1155 public positions;

    address[] public actors;
    bytes32 public marketId;

    // Track ghost variables for deeper invariant checking
    uint256 public totalBuyCollateral;
    uint256 public totalSellCollateral;
    uint256 public callsBuy;
    uint256 public callsSell;

    constructor(
        FuzzMockUSDC _usdc,
        WirebetMarket _market,
        Positions1155 _positions,
        bytes32 _marketId,
        address[] memory _actors
    ) {
        usdc = _usdc;
        market = _market;
        positions = _positions;
        marketId = _marketId;
        actors = _actors;
    }

    /// @notice Fuzzed buy: random actor, random side, bounded amount [1, 5000] USDC
    function buyRandom(uint256 actorSeed, uint256 sideSeed, uint256 amountRaw) external {
        address actor = actors[actorSeed % actors.length];
        Side side = sideSeed % 2 == 0 ? Side.YES : Side.NO;
        // Bound to [1, 5000] USDC (well under 10k max trade)
        uint256 amount = bound(amountRaw, 1e6, 5000e6);

        vm.prank(actor);
        try market.buy(side, amount, 0) {
            totalBuyCollateral += amount;
            callsBuy++;
        } catch {
            // Exposure or other revert — skip
        }
    }

    /// @notice Fuzzed sell: random actor sells up to their full position
    function sellRandom(uint256 actorSeed, uint256 sideSeed, uint256 fractionBps) external {
        address actor = actors[actorSeed % actors.length];
        Side side = sideSeed % 2 == 0 ? Side.YES : Side.NO;

        uint256 tokenId = (uint256(marketId) << 1) | uint256(side);
        uint256 balance = positions.balanceOf(actor, tokenId);
        if (balance == 0) return;

        // Sell between 1% and 100% of position
        uint256 bps = bound(fractionBps, 100, 10_000);
        uint256 sellAmount = (balance * bps) / 10_000;
        if (sellAmount == 0) return;

        vm.prank(actor);
        try market.sell(side, sellAmount, 0) returns (uint256 collateralOut) {
            totalSellCollateral += collateralOut;
            callsSell++;
        } catch {
            // Skip
        }
    }
}

/// @title WirebetInvariantTest
/// @notice Stateful fuzz test: after random sequences of buy/sell,
///         the core solvency invariant must always hold:
///
///         balance(market) >= liabilityUSDC6
///
///         This is the single most important property of the protocol.
contract WirebetInvariantTest is StdInvariant, Test {
    FuzzMockUSDC usdc;
    Positions1155 positions;
    FeeRouter feeRouter;
    WirebetMarket market;
    MarketHandler handler;

    address resolver = address(0xBEEF);
    address treasury = address(0x7EA5);

    address[] actors;
    bytes32 constant MARKET_ID = keccak256("Invariant fuzz market");

    function setUp() public {
        usdc = new FuzzMockUSDC();
        positions = new Positions1155();
        feeRouter = new FeeRouter(address(usdc), treasury);

        RiskParams memory risk = RiskParams({
            bufferBps: 500,
            feeBps: 100,
            maxTradeSizeUSDC6: 10_000e6,
            maxNetExposureBps: 10000 // no limit for fuzz
        });

        market = new WirebetMarket(
            MARKET_ID,
            address(usdc),
            address(positions),
            address(feeRouter),
            resolver,
            uint64(block.timestamp + 30 days),
            risk,
            1000e6 // b = 1000 USDC
        );

        positions.setMinter(address(market), true);

        // Seed market with LP backing
        usdc.mint(address(market), 1000e6);

        // Create 4 actors with funds
        for (uint256 i = 1; i <= 4; i++) {
            address actor = address(uint160(0xA000 + i));
            actors.push(actor);
            usdc.mint(actor, 500_000e6);
            vm.prank(actor);
            usdc.approve(address(market), type(uint256).max);
        }

        // Deploy handler and target it for fuzzing
        handler = new MarketHandler(usdc, market, positions, MARKET_ID, actors);
        targetContract(address(handler));
    }

    /// @notice CORE INVARIANT: contract balance >= liability at all times
    function invariant_solvencyBalanceCoversLiability() external view {
        uint256 balance = usdc.balanceOf(address(market));
        uint256 liability = market.liabilityUSDC6();
        assertGe(balance, liability, "SOLVENCY VIOLATED: balance < liability");
    }

    /// @notice Liability should never exceed total buy collateral deposited
    function invariant_liabilityBoundedByDeposits() external view {
        uint256 liability = market.liabilityUSDC6();
        uint256 totalBuys = handler.totalBuyCollateral();
        // Liability should be <= total net collateral deposited (buys - fees)
        // Using totalBuys as an upper bound (fees make actual liability lower)
        assertLe(liability, totalBuys, "Liability exceeds total deposits");
    }

    /// @notice Outstanding shares should match qY + qN
    function invariant_sharesConsistency() external view {
        // qY and qN should always be non-negative (they're uint256 so this is implicit,
        // but an underflow revert during fuzzing would catch bugs)
        uint256 qY = market.qY();
        uint256 qN = market.qN();
        // Verify position token supply matches q values
        uint256 yesTokenId = (uint256(MARKET_ID) << 1) | uint256(Side.YES);
        uint256 noTokenId = (uint256(MARKET_ID) << 1) | uint256(Side.NO);

        uint256 totalYes;
        uint256 totalNo;
        for (uint256 i = 0; i < actors.length; i++) {
            totalYes += positions.balanceOf(actors[i], yesTokenId);
            totalNo += positions.balanceOf(actors[i], noTokenId);
        }

        assertEq(totalYes, qY, "YES token supply != qY");
        assertEq(totalNo, qN, "NO token supply != qN");
    }

    /// @notice LMSR price should stay bounded.
    ///         SD59x18 fixed-point precision means:
    ///         - Price can exceed 1e18 by up to 1 wei (rounding up)
    ///         - Price can underflow to 0 at extreme imbalances (qY >> qN or vice versa)
    ///         Both are expected; the contract uses cost function C(q) for trades, not price.
    function invariant_priceBounded() external view {
        uint256 price = market.priceYes1e18();
        assertLe(price, 1e18 + 1, "YES price > 100% + 1 wei");
    }

    /// @notice After fuzz runs, log stats for visibility
    function invariant_callSummary() external view {
        // Just a no-op assertion for logging — always passes
        // Use `forge test -vvv` to see handler.callsBuy() and callsSell()
    }
}

/// @title WirebetCancelFuzzTest
/// @notice Fuzz test: random trades followed by cancellation.
///         Verifies all redeemed payouts sum to <= liability.
contract WirebetCancelFuzzTest is Test {
    FuzzMockUSDC usdc;
    Positions1155 positions;
    FeeRouter feeRouter;

    address resolver = address(0xBEEF);
    address treasury = address(0x7EA5);
    bytes32 constant MARKET_ID = keccak256("Cancel fuzz market");

    /// @notice Fuzz: random buy amounts for two traders, then cancel and redeem all.
    ///         Verify contract stays solvent.
    function testFuzz_cancelSolvency(
        uint256 aliceYesAmount,
        uint256 aliceNoAmount,
        uint256 bobYesAmount,
        uint256 bobNoAmount
    ) public {
        // Bound inputs to reasonable range
        aliceYesAmount = bound(aliceYesAmount, 0, 5000e6);
        aliceNoAmount = bound(aliceNoAmount, 0, 5000e6);
        bobYesAmount = bound(bobYesAmount, 0, 5000e6);
        bobNoAmount = bound(bobNoAmount, 0, 5000e6);

        // Need at least one trade
        if (aliceYesAmount + aliceNoAmount + bobYesAmount + bobNoAmount == 0) {
            aliceYesAmount = 100e6;
        }

        // Fresh deploy per run
        usdc = new FuzzMockUSDC();
        positions = new Positions1155();
        feeRouter = new FeeRouter(address(usdc), treasury);

        RiskParams memory risk = RiskParams({
            bufferBps: 500,
            feeBps: 100,
            maxTradeSizeUSDC6: 10_000e6,
            maxNetExposureBps: 10000
        });

        WirebetMarket market = new WirebetMarket(
            MARKET_ID,
            address(usdc),
            address(positions),
            address(feeRouter),
            resolver,
            uint64(block.timestamp + 7 days),
            risk,
            1000e6
        );
        positions.setMinter(address(market), true);
        usdc.mint(address(market), 1000e6); // LP seed

        address alice = address(0xA11CE);
        address bob = address(0xB0B);
        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);
        vm.prank(alice);
        usdc.approve(address(market), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(market), type(uint256).max);

        // Execute trades (skip if amount is 0)
        if (aliceYesAmount > 0) { vm.prank(alice); try market.buy(Side.YES, aliceYesAmount, 0) {} catch {} }
        if (aliceNoAmount > 0) { vm.prank(alice); try market.buy(Side.NO, aliceNoAmount, 0) {} catch {} }
        if (bobYesAmount > 0) { vm.prank(bob); try market.buy(Side.YES, bobYesAmount, 0) {} catch {} }
        if (bobNoAmount > 0) { vm.prank(bob); try market.buy(Side.NO, bobNoAmount, 0) {} catch {} }

        // Snapshot solvency before cancel
        uint256 balanceBefore = usdc.balanceOf(address(market));
        uint256 liability = market.liabilityUSDC6();
        assertGe(balanceBefore, liability, "Pre-cancel: balance < liability");

        // Cancel
        vm.prank(resolver);
        market.cancel(bytes32(0));

        // Redeem all positions
        uint256 yesTokenId = (uint256(MARKET_ID) << 1) | uint256(Side.YES);
        uint256 noTokenId = (uint256(MARKET_ID) << 1) | uint256(Side.NO);

        uint256 totalPayout;

        uint256 aliceYes = positions.balanceOf(alice, yesTokenId);
        if (aliceYes > 0) { vm.prank(alice); totalPayout += market.redeem(Side.YES, aliceYes); }

        uint256 aliceNo = positions.balanceOf(alice, noTokenId);
        if (aliceNo > 0) { vm.prank(alice); totalPayout += market.redeem(Side.NO, aliceNo); }

        uint256 bobYes = positions.balanceOf(bob, yesTokenId);
        if (bobYes > 0) { vm.prank(bob); totalPayout += market.redeem(Side.YES, bobYes); }

        uint256 bobNo = positions.balanceOf(bob, noTokenId);
        if (bobNo > 0) { vm.prank(bob); totalPayout += market.redeem(Side.NO, bobNo); }

        // Core assertion: total payouts should not exceed pre-cancel balance
        assertLe(totalPayout, balanceBefore, "CANCEL INSOLVENCY: payouts > balance");

        // Payouts should approximate liability (within rounding)
        assertApproxEqAbs(totalPayout, liability, 4, "Cancel payouts diverge from liability");
    }
}
