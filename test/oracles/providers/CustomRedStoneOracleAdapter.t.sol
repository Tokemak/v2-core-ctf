// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { CustomRedStoneOracleAdapter } from "src/oracles/providers/CustomRedStoneOracleAdapter.sol";
import { ICustomSetOracle } from "src/interfaces/oracles/ICustomSetOracle.sol";
import { ISecurityBase } from "src/interfaces/security/ISecurityBase.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { Roles } from "src/libs/Roles.sol";
import {
    CRV_MAINNET, PXETH_MAINNET, EZETH_MAINNET, WSTETH_MAINNET, RETH_MAINNET, RANDOM
} from "test/utils/Addresses.sol";

address constant TREASURY = 0x8b4334d4812C530574Bd4F2763FcD22dE94A969B;
address constant MAINNET_SYSTEM_REGISTRY = 0x2218F90A98b0C070676f249EF44834686dAa4285;
address constant MAINNET_CUSTOM_ORACLE = 0x53ff9D648a8A1cf70c6B60ae26B93047cc24066f;
address constant MAINNET_ORACLE_EXECUTOR = 0x1b9841A65c6777fdE03Be97C9A9E70C3d5C01E9c;

// solhint-disable func-name-mixedcase
contract CustomRedStoneOracleAdapterTest is Test {
    ISystemRegistry internal systemRegistry;
    IAccessController internal accessController;
    CustomRedStoneOracleAdapter internal redstoneAdapter;
    ICustomSetOracle internal customOracle;
    uint8 internal constant DEFAULT_UNIQUE_SIGNERS_THRESHOLD = 3;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 21_338_134);

        // Setup SystemRegistry
        systemRegistry = ISystemRegistry(MAINNET_SYSTEM_REGISTRY);
        accessController = ISystemRegistry(MAINNET_SYSTEM_REGISTRY).accessController();

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
        vm.startPrank(TREASURY);
        accessController.grantRole(Roles.ORACLE_MANAGER, address(this));
        accessController.grantRole(Roles.CUSTOM_ORACLE_EXECUTOR, address(this));

        accessController.grantRole(Roles.CUSTOM_ORACLE_EXECUTOR, MAINNET_ORACLE_EXECUTOR);
        vm.stopPrank();
    }

    ///@dev Get the Redstone payload snapshot for a given feedId
    ///@return data The real Redstone payload from their API
    function getRedstonePayload(
        bytes32 feedId
    ) internal pure returns (bytes memory data) {
        //solhint-disable max-line-length
        if (feedId == bytes32("pxETH/ETH")) {
            data =
                hex"70784554482f45544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f1d87d0193981dcc700000002000000129f52990cdbd3aa4897087c573632f6f925941b20162bac60d4136a850a7d122323ae981da4abaab8d3dc55e5b5543995fb4547b00175b3056c0ea4bcc3c5cb01b70784554482f45544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f1d87d0193981dcc700000002000000121bb6db4386ce633bd72684e2b4f9e1a666e640f18d5906aa37242f801dd916a3cb3e952a12c5adda158a3e3e75beed90abfe0399ac061431c0bf902470b14851b70784554482f45544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f1d87d0193981dcc70000000200000019e0164726b5090ee5e827a0e56e9e7c6a7e55e1d2ac1fab9aafd6a870395cfec76dec58ea38ff84ae916b58b44281c8356bef2ecd5f73ef95584102d5279f3cc1c00033137333334323339323430383523302e362e322372656473746f6e652d7072696d6172792d70726f645f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f000048000002ed57011e0000";
        }
        if (feedId == bytes32("CRV")) {
            data =
                hex"4352560000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000694fb230193981dcc70000000200000012cfc45ad2a36a38b3ed39a18266c0f2f0e2643ce6aeee8603d8a654e29bd234b595da399d0349ff9f5302419f9a8db109c7fb115a156ef0f4889c85405ed87371b4352560000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000694fb230193981dcc70000000200000015798f2db0ef555a1cd4ef44e49d581e82232ab5d0b5f416031b6ffbe272d92d367d1490d24a2e0e5c24c5aa288dccb4c361281beeb8afc008b711ef720f06d5a1b4352560000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000694fb230193981dcc70000000200000015304faba5bd3d655c7df7e31efa1e62f683705f58a3b90d68064048183e177e232d60940c4b013b10d8c6ed24be5a50810c8b1f469258e679cbdec26674a28501c00033137333334323339323431323623302e362e322372656473746f6e652d7072696d6172792d70726f645f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f000048000002ed57011e0000";
        } else if (feedId == bytes32("multiple")) {
            // Note: "multiple" is not the actual name of the feedId, just a selector in the tests
            // It combines multiple tokens in the same payload (ezETH/ETH, rETH/ETH, WSTETH/ETH)
            data =
                hex"657a4554482f45544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006200bd00193981dcc70000000200000011c8805e60a9f6e96cfc4c548842b1a3271ce555c7a2ca647b3645828e75eb8805f2c4fe0e5cf79d56a040ad18f5cfa9d6749b3622b0896a74a0226f7ef568b091b657a4554482f45544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006200bd00193981dcc7000000020000001d5a439f890de685bcd58ac9fef978cc956b0c9a8869f73f0f3624410aca0d1410d549b7dd987f82fb075de57065c61635a9c199ba6baf3cd389f09cf7be998b61c657a4554482f45544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006200bd00193981dcc7000000020000001360b441abb077d9ee3e626020370473d4fe0290859004a9c71bc3853048f85d82d63e9a9b0110a584eb610d46a07228dedc0a7f58cc36b175afb311da596a94e1b7773744554482f4554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000071125cb0193981dcc700000002000000178c734e9075b680a21ca9a879d360472e6d45157381afc96da31bd1ae64346a5217fdc05218913e5a4b70e83e090c3946151436851b5cf473df3e844023740801b7773744554482f4554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000071125cb0193981dcc700000002000000174cc6dc6ef3fab5ca239f30e94467d1980322f9c929c8b954a0b5f17613f8ff50aae2b0c562cb35948a237ab661aa8c665a0ea41cbe756457fa58bba5676849c1b7773744554482f4554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000071125cb0193981dcc70000000200000014c9a16ff85379f6608004b6bf4b7623b2812acd647e1de714656c3900c28234a61a193cd43640a3987f5890512ed01b97262903018731cbb76d00cbd2b18012b1c724554482f4554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006ac60220193981dcc7000000020000001d6e17cf6b130fe7eb37fe9095abba8b51b4cb5d62a85ca1f01579308cae425a27d8e67a158c495700dbbbdd7df004f7ca956f35c5184105a5899b6316665a7331c724554482f4554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006ac60220193981dcc7000000020000001a6059d22efa4ac3bcd3451ec3ded68b1b1724c7cb502d5083912a03f39e1550025cdb7494ea0061242de6cc71fb02d0c80d2884bc858327540d1cba9e58e738e1b724554482f4554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006ac60220193981dcc700000002000000180e9d81295797186f592654decc92d15cba4f07f33203f8130d72bf0e1b85d802a7a92970bd5c46d65304ee5e959053a56c5817a0bb93ec9a8e7189ec0aafa851b00093137333334323339323431363223302e362e322372656473746f6e652d7072696d6172792d70726f645f5f5f5f5f5f5f5f5f5f5f000034000002ed57011e0000";
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

contract RegisterFeedId is CustomRedStoneOracleAdapterTest {
    function test_RegistersFeedId() public {
        bytes32 feedId = bytes32("TEST");
        address token = makeAddr("token");

        redstoneAdapter.registerFeedId(feedId, token, true);

        (address tokenAddress, bool ethQuoted) = redstoneAdapter.registeredFeedIds(feedId);

        assertEq(tokenAddress, token);
        assertEq(ethQuoted, true);
    }

    function testRegisterFeedIdRevertsIfNoAccess() public {
        bytes32 feedId = bytes32("TEST");
        address token = makeAddr("token");

        vm.prank(RANDOM);
        vm.expectRevert(abi.encodeWithSignature("AccessDenied()"));
        redstoneAdapter.registerFeedId(feedId, token, true);
    }
}

contract RemoveFeedId is CustomRedStoneOracleAdapterTest {
    function test_RemovesFeedId() public {
        bytes32 feedId = bytes32("TEST");
        address token = makeAddr("token");

        redstoneAdapter.registerFeedId(feedId, token, true);
        redstoneAdapter.removeFeedId(feedId);

        (address tokenAddress,) = redstoneAdapter.registeredFeedIds(feedId);
        assertEq(tokenAddress, address(0));
    }

    function test_RemoveFeedIdRevertsIfNoAccess() public {
        bytes32 feedId = bytes32("TEST");
        address token = makeAddr("token");

        redstoneAdapter.registerFeedId(feedId, token, true);

        vm.prank(RANDOM);
        vm.expectRevert(abi.encodeWithSignature("AccessDenied()"));
        redstoneAdapter.removeFeedId(feedId);
    }
}

contract UpdatePriceWithFeedId is CustomRedStoneOracleAdapterTest {
    function test_UpdatePriceWithFeedIdRevertsIfNoAccess() public {
        bytes32[] memory feedIds = new bytes32[](1);
        feedIds[0] = bytes32("pxETH");

        bytes memory redstonePayload = getRedstonePayload(feedIds[0]);

        bytes memory encodedFunction = abi.encodeWithSignature("updatePriceWithFeedId(bytes32[])", feedIds);
        bytes memory encodedFunctionWithRedstonePayload = abi.encodePacked(encodedFunction, redstonePayload);

        redstoneAdapter.registerFeedId(feedIds[0], PXETH_MAINNET, true);

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
        redstoneAdapter.registerFeedId(feedIds[0], PXETH_MAINNET, true);

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

    function test_UpdatesPriceWithUsdNominatedFeedId() public {
        bytes32[] memory feedIds = new bytes32[](1);
        feedIds[0] = bytes32("CRV");
        redstoneAdapter.registerFeedId(feedIds[0], CRV_MAINNET, false);

        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = CRV_MAINNET;

        uint256 maxAge = customOracle.maxAge();
        uint256[] memory maxAges = new uint256[](1);
        maxAges[0] = maxAge;

        vm.prank(TREASURY);
        customOracle.registerTokens(tokenAddresses, maxAges);

        bytes memory redstonePayload = getRedstonePayload(feedIds[0]);
        bytes memory encodedFunction = abi.encodeWithSignature("updatePriceWithFeedId(bytes32[])", feedIds);
        bytes memory encodedFunctionWithRedstonePayload = abi.encodePacked(encodedFunction, redstonePayload);

        IAccessController mainnetAccessController = ISecurityBase(address(customOracle)).accessController();
        vm.prank(TREASURY);
        mainnetAccessController.grantRole(Roles.CUSTOM_ORACLE_EXECUTOR, address(redstoneAdapter));

        (uint192 priceBefore,,) = customOracle.prices(address(CRV_MAINNET));

        vm.prank(MAINNET_ORACLE_EXECUTOR);
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = address(redstoneAdapter).call(encodedFunctionWithRedstonePayload);
        assertEq(success, true);

        (uint192 priceAfter,,) = customOracle.prices(address(CRV_MAINNET));

        assertNotEq(priceAfter, priceBefore);
        // Prices should be quoted in ETH and have 18 decimals despite the feedId being quoted in USD
        assertEq(priceAfter, 283_801_142_910_443); // 0.000283801142910443 ETH
    }

    function test_UpdatesPriceWithSingleFeedId() public {
        bytes32[] memory feedIds = new bytes32[](1);
        feedIds[0] = bytes32("pxETH/ETH");
        redstoneAdapter.registerFeedId(feedIds[0], PXETH_MAINNET, true);

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

        redstoneAdapter.registerFeedId(feedIds[0], EZETH_MAINNET, true);
        redstoneAdapter.registerFeedId(feedIds[1], WSTETH_MAINNET, true);
        redstoneAdapter.registerFeedId(feedIds[2], RETH_MAINNET, true);

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
        assertEq(ezEthPriceAfter, 1_027_634_720_000_000_000);
        assertEq(wstEthPriceAfter, 1_185_642_990_000_000_000);
        assertEq(rEthPriceAfter, 1_119_600_980_000_000_000);
    }
}
