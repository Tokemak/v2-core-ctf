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
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 21_223_276);

        // Setup SystemRegistry
        systemRegistry = new SystemRegistry(address(1), WETH9_ADDRESS);

        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));

        // Setup oracles
        customOracle = ICustomSetOracle(MAINNET_CUSTOM_ORACLE);
        redstoneAdapter =
            new CustomRedStoneOracleAdapter(systemRegistry, address(customOracle), DEFAULT_UNIQUE_SIGNERS_THRESHOLD);

        // Setup roles
        accessController.grantRole(Roles.ORACLE_MANAGER, address(this));
        accessController.grantRole(Roles.CUSTOM_ORACLE_EXECUTOR, address(this));

        accessController.grantRole(Roles.CUSTOM_ORACLE_EXECUTOR, MAINNET_ORACLE_EXECUTOR);

        address[] memory defaultAuthorizedSigners = new address[](5);
        defaultAuthorizedSigners[0] = 0x8BB8F32Df04c8b654987DAaeD53D6B6091e3B774;
        defaultAuthorizedSigners[1] = 0xdEB22f54738d54976C4c0fe5ce6d408E40d88499;
        defaultAuthorizedSigners[2] = 0x51Ce04Be4b3E32572C4Ec9135221d0691Ba7d202;
        defaultAuthorizedSigners[3] = 0xDD682daEC5A90dD295d14DA4b0bec9281017b5bE;
        defaultAuthorizedSigners[4] = 0x9c5AE89C4Af6aA32cE58588DBaF90d18a855B6de;
        // Register the default authorized signers from the base contract
        redstoneAdapter.registerAuthorizedSigners(defaultAuthorizedSigners);
    }

    ///@dev Get the Redstone payload snapshot for a given feedId
    ///@return data The real Redstone payload from their API
    function getRedstonePayload(
        bytes32 feedId
    ) internal pure returns (bytes memory data) {
        //solhint-disable max-line-length
        if (feedId == bytes32("pxETH")) {
            data =
                hex"7078455448000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000486e6acc0d01934578445000000020000001fbed1688a84f22a6d9cfde3c19c9ae9b0c4e46382a20a6c66d9a74c184626e89140a41b939ef80b685f0123c713e3fff5c4b6d2ba2bb0c33edb3320774f0e9931c7078455448000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000486e7a0939019345784450000000200000010ad694b5ba0543000923aa9707d569486480e651d370180f0e5be8a011173a323105d09626c69412e08cb5a51932892a1481a47928b39b6c35dce97393d9b2ac1c7078455448000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000486e264df801934578445000000020000001811d9b359f2b9690cf0dea41ac5c27b99e5e50d1dd47aa8e088ca1e3a62e71a6495e5d6b7f4248ce148aaa7d7c639efb4ec739f20b4505cf6da66c27df0af1271b00033137333230333733343238313423302e362e322372656473746f6e652d7072696d6172792d70726f645f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f000048000002ed57011e0000";
        } else if (feedId == bytes32("multiple")) {
            data =
                hex"657a4554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004a56ba3fb301934578445000000020000001b0b5012b5051b926892f4357d7f77c47cc447ffa28c121513ff5e667f8386b4652cf2888b8a4b286b7cf984eb727859570e38b32df5620d128ce659885bb942d1b657a4554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004a56c9e39c019345784450000000200000012d7c58c490bf25cf6481d99ee3ee7b82910156accd7b638257db6257abb16bc65ce3984028b44129f36e30c5e0b7e05cc513259b11ff4a3ab761a71f90d1ea061c657a4554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004a5673f3dd01934578445000000020000001b20b6a4842f6672287638ff0bb751d3508cb71e24ab6f443bec74c22e1d23fcd44ea074f0e0c295f665207593ee437235866a147f7adfc7189b6979d3d4a52101b777374455448000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000055f9106ac2019345784450000000200000011ab30e5ec9ce56cdd91e0dfa95dd341e3d5a132ba6d3fe26c8a3f2e0b77a9644454662504619b4ca6890548f3bb2099fe7b058c799c8e9ba50070987b30872f71b777374455448000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000055f91975eb019345784450000000200000017b205fa9d3379ae3a5df14e49aaa1d90887da2ee179cd9bd9cbae42f371e51a24a4b13af1f8a27da788fb3eacf8795a3de84f46eefbf2a2c3564dcf11de0047a1c777374455448000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000055f8386ad20193457844500000002000000113f8932c0c3a70e0cbf5d98e4dfcd604a30d6675266758aed2cb0b67f7453cc65d767ad0e6855824d0fb752749a1d65463dd936ec062ebb55a4d0e8d772eadb41c724554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000051309e781601934578445000000020000001b666e8102d2b38e504f7f83d69ec84db4c9a2c903aecfaf862e0b1e7f69975a80e4b94e4e9444ac34c1ffce4cd162a50efbb54b3dcb40c4f698a30d27b9fbf4e1c72455448000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005130a70272019345784450000000200000017bf5714ed8abb003c6db35ab1f14d3d466609c1a38ba684eea50738a289633095be5482986f2d47c4aeff84d573053dd8e2915665be393a810b507294e07c4e21c7245544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000512fd27c7701934578445000000020000001a3ae769e0037649bd91305a5b045bb4c9a6eaace13eb2b55019e43d35b82f2e15ccdbb98de87295aa6c9d15e42daeefaad7b0c0d5491792345ccf0283d06b9551c00093137333230333733343238373423302e362e322372656473746f6e652d7072696d6172792d70726f645f5f5f5f5f5f5f5f5f5f5f000034000002ed57011e0000";
        }
        return data;
    }
}

contract SignersTests is CustomRedStoneOracleAdapterTest {
    function test_GetAuthorisedSignerIndexRevertsIfSignerNotAuthorised() public {
        vm.expectRevert(abi.encodeWithSignature("SignerNotAuthorised(address)", RANDOM));
        redstoneAdapter.getAuthorisedSignerIndex(RANDOM);
    }

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

    function test_GetsUniqueSignersThreshold() public {
        assertEq(redstoneAdapter.getUniqueSignersThreshold(), 3);
    }

    function test_SetsUniqueSignersThreshold() public {
        redstoneAdapter.setUniqueSignersThreshold(4);
        assertEq(redstoneAdapter.getUniqueSignersThreshold(), 4);
    }
}

contract FeedIdsTests is CustomRedStoneOracleAdapterTest {
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

contract UpdatePriceTests is CustomRedStoneOracleAdapterTest {
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

        (uint192 priceBefore,,) = customOracle.prices(address(PXETH_MAINNET));

        vm.prank(MAINNET_ORACLE_EXECUTOR);
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = address(redstoneAdapter).call(encodedFunctionWithRedstonePayload);
        assertEq(success, false);
    }

    function test_UpdatesPriceWithSingleFeedId() public {
        bytes32[] memory feedIds = new bytes32[](1);
        feedIds[0] = bytes32("pxETH");
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
        assertEq(priceAfter, 311_090_138_125);
    }

    function test_UpdatesPriceWithMultipleFeedIds() public {
        bytes32[] memory feedIds = new bytes32[](3);
        feedIds[0] = bytes32("ezETH");
        feedIds[1] = bytes32("wstETH");
        feedIds[2] = bytes32("rETH");

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

        assertEq(ezEthPriceAfter, 319_282_626_483);
        assertEq(wstEthPriceAfter, 369_250_822_850);
        assertEq(rEthPriceAfter, 348_708_042_774);
    }
}
