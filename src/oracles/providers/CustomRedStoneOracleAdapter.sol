// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { PrimaryProdDataServiceConsumerBase } from
    "redstone-finance/data-services/PrimaryProdDataServiceConsumerBase.sol";

import { SystemComponent } from "src/SystemComponent.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ICustomOracle } from "src/interfaces/oracles/ICustomOracle.sol";
import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";

contract CustomRedStoneOracleAdapter is PrimaryProdDataServiceConsumerBase, SystemComponent, SecurityBase {
    event FeedIdRegistered(bytes32 indexed feedId, address indexed tokenAddress);
    event FeedIdRemoved(bytes32 indexed feedId);

    error TokenNotRegistered(bytes32 feedId, address tokenAddress);

    ICustomOracle public immutable customOracle;
    uint8 private immutable uniqueSignersThreshold;

    /// @notice Mapping between a Redstone feedId and token address
    mapping(bytes32 => address) public feedIdToAddress;

    /// @notice Mapping between an authorized signer address and its index for faster lookup
    mapping(address => uint8) internal signerAddressToIndex;

    /// @notice Array of authorized signers
    address[] private _authorizedSigners;

    constructor(
        ISystemRegistry _systemRegistry,
        address _customOracle,
        uint8 _uniqueSignersThreshold
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        customOracle = ICustomOracle(_customOracle);

        // Register the feedId for ETH
        feedIdToAddress[bytes32("ETH")] = address(_systemRegistry.weth());

        uniqueSignersThreshold = _uniqueSignersThreshold;

        // Set default authorized signers from PrimaryProdDataServiceConsumerBase
        address[] memory defaultAuthorizedSigners = new address[](6);
        defaultAuthorizedSigners[0] = 0x8BB8F32Df04c8b654987DAaeD53D6B6091e3B774;
        defaultAuthorizedSigners[1] = 0xdEB22f54738d54976C4c0fe5ce6d408E40d88499;
        defaultAuthorizedSigners[2] = 0x51Ce04Be4b3E32572C4Ec9135221d0691Ba7d202;
        defaultAuthorizedSigners[3] = 0xDD682daEC5A90dD295d14DA4b0bec9281017b5bE;
        defaultAuthorizedSigners[4] = 0x9c5AE89C4Af6aA32cE58588DBaF90d18a855B6de;
        defaultAuthorizedSigners[5] = 0xFABB0ac9d68B0B445fB7357272Ff202C5651694a;

        _initializeSignerAddressToIndex(defaultAuthorizedSigners);
    }

    function _initializeSignerAddressToIndex(
        address[] memory signerAddresses
    ) private {
        uint256 len = signerAddresses.length;
        Errors.verifyNotZero(len, "len");

        for (uint256 i = 0; i < len; ++i) {
            address signerAddress = signerAddresses[i];
            Errors.verifyNotZero(signerAddress, "signerAddress");
            // We save the index + 1 to avoid 0 index
            // as it is used as a flag to check if the signer is authorized in getter function
            signerAddressToIndex[signerAddress] = uint8(i + 1);
        }
        // Set the new authorized signers array
        _authorizedSigners = signerAddresses;
    }

    /// @notice Returns array of authorized signer addresses
    /// @return Array of authorized signer addresses
    function authorizedSigners() external view returns (address[] memory) {
        return _authorizedSigners;
    }

    ///@notice Sets the price from extracted and validated Redstone payload
    function updatePriceWithFeedId(
        bytes32[] memory feedIds
    ) public hasRole(Roles.CUSTOM_ORACLE_EXECUTOR) {
        uint256 len = feedIds.length;
        Errors.verifyNotZero(len, "len");

        // Extract and validate the prices from the Redstone payload
        (uint256[] memory values, uint256 timestamp) = _securelyExtractOracleValuesAndTimestampFromTxMsg(feedIds);

        // Call of RedstoneConsumerNumericBase implementation of validateTimestamp
        validateTimestamp(timestamp);

        // Prepare the base tokens array
        address[] memory baseTokens = new address[](len);
        // Prepare the timestamps array and validate prices
        uint256[] memory queriedTimestamps = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            // Save token address from the registered mapping
            address tokenAddress = feedIdToAddress[feedIds[i]];
            if (tokenAddress == address(0) || !customOracle.isRegistered(tokenAddress)) {
                revert TokenNotRegistered(feedIds[i], tokenAddress);
            }
            baseTokens[i] = tokenAddress;

            // Validate the price
            Errors.verifyNotZero(values[i], "baseToken price");

            // Get the last set price from the custom oracle
            ICustomOracle.Price memory lastSetPrice = customOracle.prices(tokenAddress);

            // Check that the price has not been updated more recently than the timestamp in the Redstone payload
            if (lastSetPrice.timestamp >= timestamp) {
                revert Errors.InvalidParam("timestamp");
            }
            // Set the same timestamp from the Redstone payload for all base tokens
            queriedTimestamps[i] = timestamp / 1000; // adapted to seconds
        }
        // Set the price in the custom oracle
        customOracle.setPrices(baseTokens, values, queriedTimestamps);
    }

    ///@dev This is a default implementation as referenced in the RedstoneConsumerNumericMock contract
    function getUniqueSignersThreshold() public view virtual override returns (uint8) {
        return uniqueSignersThreshold;
    }

    /// @notice Registers a mapping between a Redstone feedId and token address
    /// @param feedId The Redstone feedId to register
    /// @param tokenAddress The token address to map to
    function registerFeedIdToAddress(bytes32 feedId, address tokenAddress) external hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(address(tokenAddress), "tokenAddress");
        feedIdToAddress[feedId] = tokenAddress;
        emit FeedIdRegistered(feedId, tokenAddress);
    }

    /// @notice Removes a mapping between a Redstone feedId and token address
    /// @param feedId The Redstone feedId to remove mapping for
    function removeFeedIdToAddress(
        bytes32 feedId
    ) external hasRole(Roles.ORACLE_MANAGER) {
        delete feedIdToAddress[feedId];
        emit FeedIdRemoved(feedId);
    }

    /// @notice Registers authorized signers overriding the existing ones
    /// @param signerAddresses The signers to register
    function registerAuthorizedSigners(
        address[] memory signerAddresses
    ) public hasRole(Roles.ORACLE_MANAGER) {
        // Clear the existing authorized signers
        uint256 len = _authorizedSigners.length;
        for (uint256 i = 0; i < len; ++i) {
            //slither-disable-next-line costly-loop
            delete signerAddressToIndex[_authorizedSigners[i]];
        }
        // Register the new authorized signers
        _initializeSignerAddressToIndex(signerAddresses);
    }

    /// @notice Returns the index of an authorized signer
    /// @param signerAddress The signer address to get the index for
    /// @return The index of the signer
    function getAuthorisedSignerIndex(
        address signerAddress
    ) public view virtual override returns (uint8) {
        uint8 signerIndex = signerAddressToIndex[signerAddress];
        if (signerIndex == 0) {
            revert SignerNotAuthorised(signerAddress);
        }
        return signerIndex - 1; // We subtract 1 to avoid 0 index as a flag
    }
}
