// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Vm } from "forge-std/Vm.sol";
import { Test, StdCheats, StdUtils } from "forge-std/Test.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IAsset } from "src/interfaces/external/balancer/IAsset.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { IBalancerMetaStablePool } from "src/interfaces/external/balancer/IBalancerMetaStablePool.sol";
import { BalancerLPMetaStableEthOracle } from "src/oracles/providers/BalancerLPMetaStableEthOracle.sol";
import { BAL_VAULT, WSTETH_MAINNET, CBETH_MAINNET, CBETH_WSTETH_BAL_POOL } from "test/utils/Addresses.sol";

contract BalancerLPMetaStableEthOracleTests is Test {
    IBalancerVault private constant VAULT = IBalancerVault(BAL_VAULT);
    address private constant WSTETH = address(WSTETH_MAINNET);
    address private constant CBETH = address(CBETH_MAINNET);
    address private constant WSTETH_CBETH_POOL = address(CBETH_WSTETH_BAL_POOL);

    IRootPriceOracle private rootPriceOracle;
    ISystemRegistry private systemRegistry;
    BalancerLPMetaStableEthOracle private oracle;

    event ReceivedPrice();

    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_269_656);
        vm.selectFork(mainnetFork);

        rootPriceOracle = IRootPriceOracle(vm.addr(324));
        systemRegistry = generateSystemRegistry(address(rootPriceOracle));
        oracle = new BalancerLPMetaStableEthOracle(systemRegistry, VAULT);
    }

    function testConstruction() public {
        assertEq(address(systemRegistry), address(oracle.getSystemRegistry()));
        assertEq(address(VAULT), address(oracle.balancerVault()));
    }

    function testcbETHwstETHPool() public {
        mockRootPrice(WSTETH, 1_123_300_000_000_000_000); //wstETH
        mockRootPrice(CBETH, 1_034_300_000_000_000_000); //cbETH

        uint256 price = oracle.getPriceInEth(WSTETH_CBETH_POOL);

        assertEq(price > 99e16, true);
        assertEq(price < 11e17, true);
    }

    function testReentrancyGuard() public {
        mockRootPrice(WSTETH, 1_123_300_000_000_000_000); //wstETH
        mockRootPrice(CBETH, 1_034_300_000_000_000_000); //cbETH

        // Runs a getPriceEth inside of a vault operation
        ReentrancyTester tester = new ReentrancyTester(oracle, address(VAULT), WSTETH,WSTETH_CBETH_POOL);
        deal(WSTETH, address(tester), 10e18);
        deal(address(tester), 10e18);
        tester.run();

        assertEq(tester.getPriceFailed(), true);
        assertEq(tester.priceReceived(), type(uint256).max);

        // Runs getPriceEth outside of a vault operation
        uint256 price = oracle.getPriceInEth(WSTETH_CBETH_POOL);
        assertEq(price > 99e16, true);
        assertEq(price < 11e17, true);
    }

    function testAlwaysTwoTokens() public {
        address mockPool = vm.addr(3434);
        bytes32 badPoolId = keccak256("x2349382440328");

        //solhint-disable-next-line max-line-length
        vm.mockCall(mockPool, abi.encodeWithSelector(IBalancerMetaStablePool.getPoolId.selector), abi.encode(badPoolId));

        address mockVault = vm.addr(3_434_343);

        ISystemRegistry localSystemRegistry = generateSystemRegistry(address(rootPriceOracle));
        BalancerLPMetaStableEthOracle localOracle =
            new BalancerLPMetaStableEthOracle(localSystemRegistry, IBalancerVault(mockVault));

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(vm.addr(2));
        uint256[] memory amounts = new uint256[](0);
        uint256 lastChangeBlock = block.number;
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(IBalancerVault.getPoolTokens.selector),
            abi.encode(tokens, amounts, lastChangeBlock)
        );

        vm.expectRevert(abi.encodeWithSelector(BalancerLPMetaStableEthOracle.InvalidTokenCount.selector, mockPool, 1));
        localOracle.getPriceInEth(mockPool);
    }

    function testInvalidPoolIdReverts() public {
        address mockPool = vm.addr(3434);
        bytes32 badPoolId = keccak256("x2349382440328");
        //solhint-disable-next-line max-line-length
        vm.mockCall(mockPool, abi.encodeWithSelector(IBalancerMetaStablePool.getPoolId.selector), abi.encode(badPoolId));

        vm.expectRevert("BAL#500");
        oracle.getPriceInEth(mockPool);
    }

    function mockRootPrice(address token, uint256 price) internal {
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, token),
            abi.encode(price)
        );
    }

    function generateSystemRegistry(address rootOracle) internal returns (ISystemRegistry) {
        address registry = vm.addr(327_849);
        vm.mockCall(registry, abi.encodeWithSelector(ISystemRegistry.rootPriceOracle.selector), abi.encode(rootOracle));
        return ISystemRegistry(registry);
    }
}

contract ReentrancyTester {
    BalancerLPMetaStableEthOracle private oracle;
    address private balancerVault;
    address private wstETH;
    address private wstETHcbEthPool;

    uint256 public priceReceived = type(uint256).max;
    bool public getPriceFailed = false;

    // Same as defined in BalancerUtilities
    error BalancerVaultReentrancy();

    constructor(
        BalancerLPMetaStableEthOracle _oracle,
        address _balancerVault,
        address _wstETH,
        address _wstETHcbEthPool
    ) {
        oracle = _oracle;
        balancerVault = _balancerVault;
        wstETH = _wstETH;
        wstETHcbEthPool = _wstETHcbEthPool;

        IERC20(wstETH).approve(balancerVault, type(uint256).max);
    }

    function run() external {
        IAsset[] memory assets = new IAsset[](2);
        assets[1] = IAsset(address(0));
        assets[0] = IAsset(address(wstETH));

        uint256[] memory amounts = new uint256[](2);
        // Join with 1 gWei less than msgValue to trigger callback
        amounts[1] = 1e18 - 1e9;
        amounts[0] = 1e18;

        uint256 msgValue;
        msgValue = 1e18;

        // wstETH/WETH
        IBalancerVault(balancerVault).joinPool{ value: msgValue }(
            0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080,
            address(this),
            address(this),
            IBalancerVault.JoinPoolRequest(
                assets,
                amounts,
                abi.encode(IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amounts, 0),
                false // Don't use internal balances
            )
        );
    }

    receive() external payable {
        if (msg.sender == balancerVault) {
            try oracle.getPriceInEth(address(CBETH_WSTETH_BAL_POOL)) returns (uint256 price) {
                priceReceived = price;
            } catch (bytes memory err) {
                if (keccak256(abi.encodeWithSelector(BalancerVaultReentrancy.selector)) == keccak256(err)) {
                    getPriceFailed = true;
                }
            }
        }
    }
}
