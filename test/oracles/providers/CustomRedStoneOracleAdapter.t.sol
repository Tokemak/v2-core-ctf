// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { CustomRedStoneOracleAdapter } from "src/oracles/providers/CustomRedStoneOracleAdapter.sol";
import { ICustomSetOracle } from "src/interfaces/oracles/ICustomSetOracle.sol";
import { ISecurityBase } from "src/interfaces/security/ISecurityBase.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { AccessController } from "src/security/AccessController.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { Roles } from "src/libs/Roles.sol";
import {
    WETH9_ADDRESS, PXETH_MAINNET, EZETH_MAINNET, WSTETH_MAINNET, RETH_MAINNET, RANDOM
} from "test/utils/Addresses.sol";

address constant TREASURY = 0x8b4334d4812C530574Bd4F2763FcD22dE94A969B;
address constant MAINNET_CUSTOM_ORACLE = 0x53ff9D648a8A1cf70c6B60ae26B93047cc24066f;
address constant MAINNET_ORACLE_EXECUTOR = 0x1b9841A65c6777fdE03Be97C9A9E70C3d5C01E9c;

// solhint-disable func-name-mixedcase
contract CustomRedStoneOracleAdapterTest is Test {
    SystemRegistry internal systemRegistry;
    AccessController internal accessController;
    CustomRedStoneOracleAdapter internal redstoneAdapter;
    ICustomSetOracle internal customOracle;
    uint8 internal constant DEFAULT_UNIQUE_SIGNERS_THRESHOLD = 3;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 21_337_530);

        // Setup SystemRegistry
        systemRegistry = new SystemRegistry(address(1), WETH9_ADDRESS);

        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));

        // Setup oracles
        customOracle = ICustomSetOracle(MAINNET_CUSTOM_ORACLE);

        // Pass the default authorized signers from the base contract to register on init
        address[] memory defaultAuthorizedSigners = new address[](5);
        defaultAuthorizedSigners[0] = 0x8BB8F32Df04c8b654987DAaeD53D6B6091e3B774;
        defaultAuthorizedSigners[1] = 0xdEB22f54738d54976C4c0fe5ce6d408E40d88499;
        defaultAuthorizedSigners[2] = 0x51Ce04Be4b3E32572C4Ec9135221d0691Ba7d202;
        defaultAuthorizedSigners[3] = 0xDD682daEC5A90dD295d14DA4b0bec9281017b5bE;
        defaultAuthorizedSigners[4] = 0x9c5AE89C4Af6aA32cE58588DBaF90d18a855B6de;

        redstoneAdapter = new CustomRedStoneOracleAdapter(
            systemRegistry, address(customOracle), DEFAULT_UNIQUE_SIGNERS_THRESHOLD, defaultAuthorizedSigners
        );

        // Setup roles
        accessController.grantRole(Roles.ORACLE_MANAGER, address(this));
        accessController.grantRole(Roles.CUSTOM_ORACLE_EXECUTOR, address(this));

        accessController.grantRole(Roles.CUSTOM_ORACLE_EXECUTOR, MAINNET_ORACLE_EXECUTOR);
    }

    ///@dev Get the Redstone payload snapshot for a given feedId
    ///@return data The real Redstone payload from their API
    function getRedstonePayload(
        bytes32 feedId
    ) internal pure returns (bytes memory data) {
        //solhint-disable max-line-length
        if (feedId == bytes32("pxETH/ETH")) {
            data =
                hex"70784554482f45544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f1d87d019397aeb6f00000002000000119c4a429c7d1ac62eb5ec9bdd30b6d1f19389e4ba74369deb6adcce542cb41207457333d71ea4d5726c204a94e306e8bff5f64d11ec32e0f4bb6e632716c77341b70784554482f45544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f1d87d019397aeb6f000000020000001909f90dfccd481e0f6d5e65b84e7c3139b91578deabb9fc380efd6acc8b157663351c362db36c3356afb0419416f36f2242b9f26edb5e25093c643dc6c0989081c70784554482f45544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f1d87d019397aeb6f00000002000000143aeec854fbb1d0dc38dc737d97a2e657ae9ef61b37556d3eceb5c138ab9331f6ee21216a686cd2e9d138a38a9fcbd2336364272203e8a5ef9293f24db3846b41c00033137333334313636343335303323302e362e322372656473746f6e652d7072696d6172792d70726f645f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f000048000002ed57011e0000";
        } else if (feedId == bytes32("multiple")) {
            data =
                hex"657a4554482f45544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006200299019397aeb6f0000000200000014a23f28d88b683e6ec892fa5f2db7c6a72f977c02617975c227a2bab4a4f3f547f90debc96b8fe92f5b5b3876fbd4ac03c7eab27dc9412b9132823bc8b0e68851c657a4554482f45544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006200299019397aeb6f000000020000001718e72ba066524bd306a469277ced60ef28fc09d7b132603bc3f97c992d1483c59713974904780f6dd279454d71b090c2a71a3772f1d781ab70549d3b46dfcdc1c657a4554482f45544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006200299019397aeb6f000000020000001fafb03ff2a463def0ddffca9a124bd3ff8f7f46f94b22b687f14039d3dd8f5d421ba617e557997f8f62e7a29d9e7f63674f417fe07b47b6fe27d186cdd2b505d1b7773744554482f45544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000711268b019397aeb6f00000002000000178d027aa2cc17ef4659c98fe46f1f62baa7211de33131044f72000972f8089502d95898492505010760c1b157112a56aa838d5996794a31868ddb04f9f349e701b7773744554482f45544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000711268b019397aeb6f000000020000001cd545978b824fa2131d4b2a7ca4cc2c8b2f1d2b1b94d1bc04eff52584be985f4417c4f7b68d49ce636de352d1b01714d9eb76dff1440df5091688307aed9ef791c7773744554482f45544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000711268b019397aeb6f0000000200000012e96e125e0fbca8a78c100787a0832c3f507f2d4e7cb5b7fee076cd92d1f6bd20113f6cf752f2592a95e72c2c241e392ab6660b2e670add1011861531fe73b201b724554482f4554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006ac60d8019397aeb6f000000020000001cec3fd41e88a0100a7feffb5604d2501c868de354a874291f0be072216e302291169f3c33a8be8d76d62b47f7d6d2eb6b2f52233ce782ce8777eea3257f4b72e1b724554482f4554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006ac60d8019397aeb6f000000020000001723de5fbc6213292afb37f3f3b84d2468c370df8537b9449b398902c86d66eee2fba39e4251406214851d8d8ba49020a0e1748963e8843712b49fce430e194d01b724554482f4554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006ac60d8019397aeb6f0000000200000014028d38c7959438634acc748a3ee222be173ec17834494e2bdfbf88c42a827eb065b97423eb93f59fdc552a0946efd03fd65aebc82772ac4c0244db4f0ffeef61b00093137333334313636343335333323302e362e322372656473746f6e652d7072696d6172792d70726f645f5f5f5f5f5f5f5f5f5f5f000034000002ed57011e0000";
        }
        return data;
    }
}

contract RegisterAuthorizedSigners is CustomRedStoneOracleAdapterTest {
    function test_RegistersAuthorisedSigners() public {
        address[] memory initialAuthorizedSigners = new address[](1);
        initialAuthorizedSigners[0] = MAINNET_ORACLE_EXECUTOR;
        redstoneAdapter.registerAuthorizedSigners(initialAuthorizedSigners);

        // New authorized signers override the existing ones
        address[] memory newAuthorizedSigners = new address[](2);
        newAuthorizedSigners[0] = RANDOM;
        newAuthorizedSigners[1] = TREASURY;
        redstoneAdapter.registerAuthorizedSigners(newAuthorizedSigners);

        assertEq(redstoneAdapter.authorizedSigners().length, 2);
        assertEq(redstoneAdapter.authorizedSigners()[0], RANDOM);
        assertEq(redstoneAdapter.authorizedSigners()[1], TREASURY);

        assertEq(redstoneAdapter.getAuthorisedSignerIndex(RANDOM), 0);
        assertEq(redstoneAdapter.getAuthorisedSignerIndex(TREASURY), 1);

        vm.expectRevert(abi.encodeWithSignature("SignerNotAuthorised(address)", initialAuthorizedSigners[0]));
        redstoneAdapter.getAuthorisedSignerIndex(initialAuthorizedSigners[0]);

        // Resetting the authorized signers array
        redstoneAdapter.registerAuthorizedSigners(new address[](0));
        assertEq(redstoneAdapter.authorizedSigners().length, 0);
    }
}

contract GetAuthorisedSignerIndex is CustomRedStoneOracleAdapterTest {
    function test_GetAuthorisedSignerIndexRevertsIfSignerNotAuthorised() public {
        vm.expectRevert(abi.encodeWithSignature("SignerNotAuthorised(address)", RANDOM));
        redstoneAdapter.getAuthorisedSignerIndex(RANDOM);
    }
}

contract GetUniqueSignersThreshold is CustomRedStoneOracleAdapterTest {
    function test_GetsUniqueSignersThreshold() public {
        assertEq(redstoneAdapter.getUniqueSignersThreshold(), 3);
    }
}

contract SetUniqueSignersThreshold is CustomRedStoneOracleAdapterTest {
    function test_SetsUniqueSignersThreshold() public {
        redstoneAdapter.setUniqueSignersThreshold(4);
        assertEq(redstoneAdapter.getUniqueSignersThreshold(), 4);
    }
}

contract RegisterFeedIdToAddress is CustomRedStoneOracleAdapterTest {
    function test_RegistersFeedId() public {
        bytes32 feedId = bytes32("TEST");
        address token = makeAddr("token");

        redstoneAdapter.registerFeedIdToAddress(feedId, token);

        assertEq(redstoneAdapter.feedIdToAddress(feedId), token);
    }

    function testRegisterFeedIdRevertsIfNoAccess() public {
        bytes32 feedId = bytes32("TEST");
        address token = makeAddr("token");

        vm.prank(RANDOM);
        vm.expectRevert(abi.encodeWithSignature("AccessDenied()"));
        redstoneAdapter.registerFeedIdToAddress(feedId, token);
    }
}

contract RemoveFeedIdToAddress is CustomRedStoneOracleAdapterTest {
    function test_RemovesFeedId() public {
        bytes32 feedId = bytes32("TEST");
        address token = makeAddr("token");

        redstoneAdapter.registerFeedIdToAddress(feedId, token);
        redstoneAdapter.removeFeedIdToAddress(feedId);

        assertEq(redstoneAdapter.feedIdToAddress(feedId), address(0));
    }

    function test_RemoveFeedIdRevertsIfNoAccess() public {
        bytes32 feedId = bytes32("TEST");
        address token = makeAddr("token");

        redstoneAdapter.registerFeedIdToAddress(feedId, token);

        vm.prank(RANDOM);
        vm.expectRevert(abi.encodeWithSignature("AccessDenied()"));
        redstoneAdapter.removeFeedIdToAddress(feedId);
    }
}

contract UpdatePriceWithFeedId is CustomRedStoneOracleAdapterTest {
    function test_UpdatePriceWithFeedIdRevertsIfNoAccess() public {
        bytes32[] memory feedIds = new bytes32[](1);
        feedIds[0] = bytes32("pxETH");

        bytes memory redstonePayload = getRedstonePayload(feedIds[0]);

        bytes memory encodedFunction = abi.encodeWithSignature("updatePriceWithFeedId(bytes32[])", feedIds);
        bytes memory encodedFunctionWithRedstonePayload = abi.encodePacked(encodedFunction, redstonePayload);

        redstoneAdapter.registerFeedIdToAddress(feedIds[0], PXETH_MAINNET);

        IAccessController mainnetAccessController = ISecurityBase(address(customOracle)).accessController();
        vm.prank(TREASURY);
        mainnetAccessController.grantRole(Roles.CUSTOM_ORACLE_EXECUTOR, address(redstoneAdapter));

        vm.prank(RANDOM);
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = address(redstoneAdapter).call(encodedFunctionWithRedstonePayload);
        assertEq(success, false);
    }

    function test_UpdatePriceWithFeedIdRevertsIfFeedIdNotRegistered() public {
        bytes32[] memory feedIds = new bytes32[](1);
        feedIds[0] = bytes32("pxETH");

        bytes memory redstonePayload = getRedstonePayload(feedIds[0]);

        bytes memory encodedFunction = abi.encodeWithSignature("updatePriceWithFeedId(bytes32[])", feedIds);
        bytes memory encodedFunctionWithRedstonePayload = abi.encodePacked(encodedFunction, redstonePayload);

        IAccessController mainnetAccessController = ISecurityBase(address(customOracle)).accessController();
        vm.prank(TREASURY);
        mainnetAccessController.grantRole(Roles.CUSTOM_ORACLE_EXECUTOR, address(redstoneAdapter));

        vm.prank(MAINNET_ORACLE_EXECUTOR);
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = address(redstoneAdapter).call(encodedFunctionWithRedstonePayload);
        assertEq(success, false);
    }

    function test_UpdatePriceWithFeedIdRevertsIfFeedIdIsNotExisting() public {
        bytes32[] memory feedIds = new bytes32[](1);
        feedIds[0] = bytes32("someRandomFeedIdThatDoesNotExist");
        redstoneAdapter.registerFeedIdToAddress(feedIds[0], PXETH_MAINNET);

        bytes memory redstonePayload = getRedstonePayload(feedIds[0]);
        bytes memory encodedFunction = abi.encodeWithSignature("updatePriceWithFeedId(bytes32[])", feedIds);
        bytes memory encodedFunctionWithRedstonePayload = abi.encodePacked(encodedFunction, redstonePayload);

        IAccessController mainnetAccessController = ISecurityBase(address(customOracle)).accessController();
        vm.prank(TREASURY);
        mainnetAccessController.grantRole(Roles.CUSTOM_ORACLE_EXECUTOR, address(redstoneAdapter));

        vm.prank(MAINNET_ORACLE_EXECUTOR);
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = address(redstoneAdapter).call(encodedFunctionWithRedstonePayload);
        assertEq(success, false);
    }

    function test_UpdatesPriceWithSingleFeedId() public {
        bytes32[] memory feedIds = new bytes32[](1);
        feedIds[0] = bytes32("pxETH/ETH");
        redstoneAdapter.registerFeedIdToAddress(feedIds[0], PXETH_MAINNET);

        bytes memory redstonePayload = getRedstonePayload(feedIds[0]);
        bytes memory encodedFunction = abi.encodeWithSignature("updatePriceWithFeedId(bytes32[])", feedIds);
        bytes memory encodedFunctionWithRedstonePayload = abi.encodePacked(encodedFunction, redstonePayload);

        IAccessController mainnetAccessController = ISecurityBase(address(customOracle)).accessController();
        vm.prank(TREASURY);
        mainnetAccessController.grantRole(Roles.CUSTOM_ORACLE_EXECUTOR, address(redstoneAdapter));

        (uint192 priceBefore,,) = customOracle.prices(address(PXETH_MAINNET));

        vm.prank(MAINNET_ORACLE_EXECUTOR);
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = address(redstoneAdapter).call(encodedFunctionWithRedstonePayload);
        assertEq(success, true);

        (uint192 priceAfter,,) = customOracle.prices(address(PXETH_MAINNET));

        assertNotEq(priceAfter, priceBefore);
        // Prices should be quoted in ETH and have 18 decimals
        assertEq(priceAfter, 997_356_770_000_000_000);
    }

    function test_UpdatesPriceWithMultipleFeedIds() public {
        bytes32[] memory feedIds = new bytes32[](3);
        feedIds[0] = bytes32("ezETH/ETH");
        feedIds[1] = bytes32("wstETH/ETH");
        feedIds[2] = bytes32("rETH/ETH");

        address[] memory tokenAddresses = new address[](3);
        tokenAddresses[0] = EZETH_MAINNET;
        tokenAddresses[1] = WSTETH_MAINNET;
        tokenAddresses[2] = RETH_MAINNET;

        uint256 maxAge = customOracle.maxAge();
        uint256[] memory maxAges = new uint256[](3);
        maxAges[0] = maxAge;
        maxAges[1] = maxAge;
        maxAges[2] = maxAge;

        vm.prank(TREASURY);
        customOracle.registerTokens(tokenAddresses, maxAges);

        bytes memory redstonePayload = getRedstonePayload(bytes32("multiple"));

        bytes memory encodedFunction = abi.encodeWithSignature("updatePriceWithFeedId(bytes32[])", feedIds);
        bytes memory encodedFunctionWithRedstonePayload = abi.encodePacked(encodedFunction, redstonePayload);

        redstoneAdapter.registerFeedIdToAddress(feedIds[0], EZETH_MAINNET);
        redstoneAdapter.registerFeedIdToAddress(feedIds[1], WSTETH_MAINNET);
        redstoneAdapter.registerFeedIdToAddress(feedIds[2], RETH_MAINNET);

        IAccessController mainnetAccessController = ISecurityBase(address(customOracle)).accessController();
        vm.prank(TREASURY);
        mainnetAccessController.grantRole(Roles.CUSTOM_ORACLE_EXECUTOR, address(redstoneAdapter));

        (uint192 ezEthPriceBefore,,) = customOracle.prices(EZETH_MAINNET);
        (uint192 wstEthPriceBefore,,) = customOracle.prices(WSTETH_MAINNET);
        (uint192 rEthPriceBefore,,) = customOracle.prices(RETH_MAINNET);

        vm.prank(MAINNET_ORACLE_EXECUTOR);
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = address(redstoneAdapter).call(encodedFunctionWithRedstonePayload);
        assertEq(success, true);

        (uint192 ezEthPriceAfter,,) = customOracle.prices(EZETH_MAINNET);
        (uint192 wstEthPriceAfter,,) = customOracle.prices(WSTETH_MAINNET);
        (uint192 rEthPriceAfter,,) = customOracle.prices(RETH_MAINNET);

        assertNotEq(ezEthPriceAfter, ezEthPriceBefore);
        assertNotEq(wstEthPriceAfter, wstEthPriceBefore);
        assertNotEq(rEthPriceAfter, rEthPriceBefore);

        // Prices should be quoted in ETH and have 18 decimals
        assertEq(ezEthPriceAfter, 1_027_611_130_000_000_000);
        assertEq(wstEthPriceAfter, 1_185_644_910_000_000_000);
        assertEq(rEthPriceAfter, 1_119_602_800_000_000_000);
    }
}
