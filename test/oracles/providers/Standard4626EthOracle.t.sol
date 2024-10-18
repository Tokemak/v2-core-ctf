// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { Test } from "forge-std/Test.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { RedstoneOracle } from "src/oracles/providers/RedstoneOracle.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { ISfrxEth } from "src/interfaces/external/frax/ISfrxEth.sol";
import { Standard4626EthOracle } from "src/oracles/providers/Standard4626EthOracle.sol";
import {
    TOKE_MAINNET,
    WETH9_ADDRESS,
    FRXETH_MAINNET,
    SFRXETH_MAINNET,
    SFRXETH_RS_FEED_MAINNET
} from "test/utils/Addresses.sol";
import { ERC4626, IERC4626, IERC20, ERC20, Math } from "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

/*
 * Tests Standard46426EthOracle with frxETH and sfrxETH 
 *
 */

contract Standard46426EthOracleTests is Test {
    RootPriceOracle public rootPriceOracle;
    SystemRegistry public systemRegistry;
    Standard4626EthOracle public oracle;
    ISfrxEth public sfrxETH;
    RedstoneOracle public sfrxETHRedstoneOracle;

    SystemRegistry public systemRegistry2;
    Standard4626EthOracle public oracle2;

    function setUp() public virtual {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_711_565);
        vm.selectFork(mainnetFork);

        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH9_ADDRESS);
        AccessController accessControl = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessControl));
        rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        oracle = new Standard4626EthOracle(systemRegistry, SFRXETH_MAINNET);
        sfrxETH = ISfrxEth(SFRXETH_MAINNET);
        sfrxETHRedstoneOracle = new RedstoneOracle(systemRegistry);

        accessControl.grantRole(Roles.ORACLE_MANAGER, address(this));
        sfrxETHRedstoneOracle.registerOracle(
            SFRXETH_MAINNET,
            IAggregatorV3Interface(SFRXETH_RS_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );

        rootPriceOracle.registerMapping(SFRXETH_MAINNET, sfrxETHRedstoneOracle);
    }
}

contract Construct is Standard46426EthOracleTests {
    //Constructor Tests
    function test_OracleInitializedState() public {
        uint256 vaultTokenOne = 10 ** IERC4626(SFRXETH_MAINNET).decimals();

        assertEq(address(oracle.vault()), SFRXETH_MAINNET);
        assertEq(address(oracle.underlyingAsset()), FRXETH_MAINNET);
        assertEq(vaultTokenOne, oracle.vaultTokenOne());
    }

    function test_RevertSystemRegistryZeroAddress() public {
        vm.expectRevert();
        oracle = new Standard4626EthOracle(ISystemRegistry(address(0)), SFRXETH_MAINNET);
    }

    function test_RevertVaultZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_vault4626"));
        oracle = new Standard4626EthOracle(systemRegistry, address(0));
    }

    function test_RevertRootPriceOracleNotSetup() public {
        systemRegistry2 = new SystemRegistry(TOKE_MAINNET, WETH9_ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "rootPriceOracle"));
        oracle2 = new Standard4626EthOracle(systemRegistry2, SFRXETH_MAINNET);
    }
}

contract GetDescription is Standard46426EthOracleTests {
    function test_description() public {
        string memory description = oracle.getDescription();
        assertEq(description, "frxETH");
    }
}

contract GetPriceInEth is Standard46426EthOracleTests {
    function testBasicPriceFRXETH() public {
        uint256 expectedPrice = 996_304_328_573_279_558;
        uint256 price = oracle.getPriceInEth(FRXETH_MAINNET);
        assertApproxEqAbs(price, expectedPrice, 1e17);
    }

    function testInvalidToken() public {
        address fakeAddr = vm.addr(34_343);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidToken.selector, fakeAddr));
        oracle.getPriceInEth(address(fakeAddr));
    }
}

// Tests to ensure vault is working correctly with decimal differences between vault and asset
contract GetPriceInEthDecimals is Standard46426EthOracleTests {
    MockERC20 public mockToken;
    ERC4626DecimalOffset public offsetVault;

    function setUp() public virtual override {
        super.setUp();

        mockToken = new MockERC20("MockToken", "MT", 18);
        offsetVault = new ERC4626DecimalOffset(IERC20(mockToken));
    }

    function test_VaultAndAssetDecimals_StoredCorrectly_WhenDifferent() public {
        // Update vault decimals first, offset by three decimals
        offsetVault.setDecimalOffset(6);

        Standard4626EthOracle localOracle = new Standard4626EthOracle(systemRegistry, address(offsetVault));

        assertEq(localOracle.vaultTokenOne(), 10 ** 24); // Underlying 18 + offset 6 = 24 total decimals
        assertEq(localOracle.underlyingAssetOne(), 10 ** 18);
    }

    function test_getPriceInEth_ReturnsCorrectDecimals_DifferingVaultAndAssetDecimals() public {
        // Update vault decimals first, offset by three decimals
        offsetVault.setDecimalOffset(3);

        Standard4626EthOracle localOracle = new Standard4626EthOracle(systemRegistry, address(offsetVault));

        // Check that vaultTokenOne is expected, make sure that conversion to assets working as expected
        assertEq(localOracle.vaultTokenOne(), 1e21);
        assertEq(offsetVault.convertToAssets(localOracle.vaultTokenOne()), 1e18);

        _mockGetPriceInEthCall(1e18, offsetVault);

        // Price should return 1e18 exactly
        //    getPriceInEth - 1e18
        //    underlyingAssetOne - 1e18
        //    convertToAssets - 1e18
        assertEq(localOracle.getPriceInEth(address(mockToken)), 1e18);
    }

    function test_getPriceInEth_AssetAndVault_NotEighteenDecimals() public {
        // Create new token with 9 decimals
        MockERC20 mockTokenLocal = new MockERC20("MockTokenLocal", "MTL", 9);

        // new vault because of new asset
        ERC4626DecimalOffset localOffsetVault = new ERC4626DecimalOffset(IERC20(mockTokenLocal));

        // Four decimal offset, vault will be in 13 decimals
        localOffsetVault.setDecimalOffset(4);

        Standard4626EthOracle localOracle = new Standard4626EthOracle(systemRegistry, address(localOffsetVault));

        // Check that vaultTokenOne is expected, make sure that conversion to assets working as expected
        assertEq(localOracle.vaultTokenOne(), 1e13, "1");
        assertEq(localOffsetVault.convertToAssets(localOracle.vaultTokenOne()), 1e9, "2");

        _mockGetPriceInEthCall(1e18, localOffsetVault);

        // Price should return 1e18 exactly
        //    getPriceInEth - 1e18
        //    underlyingAssetOne - 1e9
        //    convertToAssets - Takes in 1e13, returns in 1e9
        assertEq(localOracle.getPriceInEth(address(mockTokenLocal)), 1e18, "3");
    }

    // Not using root price oracle for direct interactions with 4626 oracle, only for `getPriceInEth` call in
    // oracle, so we can just mock this call.
    function _mockGetPriceInEthCall(uint256 _price, ERC4626DecimalOffset _offsetVault) private {
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeCall(RootPriceOracle.getPriceInEth, (address(_offsetVault))),
            abi.encode(_price)
        );
    }
}

// Version of OZ we are using does not contain decimal offset, this contract will mimic functionality. See
// OZ version 4.9 or later, we are using version 4.8.1
contract ERC4626DecimalOffset is ERC4626 {
    using Math for uint256;

    uint8 public decimalOffset;

    constructor(
        IERC20 _asset
    ) ERC4626(_asset) ERC20("mockVault", "MV") { }

    function setDecimalOffset(
        uint8 _decimalOffset
    ) public {
        decimalOffset = _decimalOffset;
    }

    function decimals() public view override(ERC4626) returns (uint8) {
        return super.decimals() + _decimalsOffset();
    }

    function _decimalsOffset() private view returns (uint8) {
        return decimalOffset;
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256) {
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }
}
