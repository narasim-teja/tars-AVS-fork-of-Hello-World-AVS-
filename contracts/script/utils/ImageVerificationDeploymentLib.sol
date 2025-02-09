// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {ImageVerificationServiceManager} from "../../src/ImageVerificationServiceManager.sol";
import {ImageVerificationTask} from "../../src/ImageVerificationTask.sol";
import {ECDSAStakeRegistry} from "@eigenlayer-middleware/src/unaudited/ECDSAStakeRegistry.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {Quorum, StrategyParams, IStrategy} from "@eigenlayer-middleware/src/interfaces/IECDSAStakeRegistryEventsAndErrors.sol";

import {CoreDeploymentLib} from "./CoreDeploymentLib.sol";
import {UpgradeableProxyLib} from "./UpgradeableProxyLib.sol";

library ImageVerificationDeploymentLib {
    using stdJson for *;
    using Strings for *;
    using UpgradeableProxyLib for address;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct DeploymentData {
        address stakeRegistry;
        address imageVerificationServiceManager;
        address imageVerificationTask;
        address strategy;
        address token;
    }

    struct DeploymentConfigData {
        address rewardsOwner;
        address rewardsInitiator;
    }

    function deployContracts(
        address proxyAdmin,
        CoreDeploymentLib.DeploymentData memory coreDeployment,
        address rewardsInitiator,
        address rewardsOwner,
        address strategy
    ) internal returns (DeploymentData memory) {
        DeploymentData memory data;
        data.strategy = strategy;

        // Deploy service manager first since it's needed for stake registry initialization
        address serviceManagerImpl = address(new ImageVerificationServiceManager(
            coreDeployment.avsDirectory,
            address(0), // This will be updated after stake registry deployment
            coreDeployment.rewardsCoordinator,
            coreDeployment.delegationManager
        ));
        data.imageVerificationServiceManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);

        // Deploy stake registry
        address stakeRegistryImpl = address(new ECDSAStakeRegistry(IDelegationManager(coreDeployment.delegationManager)));
        data.stakeRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);

        // Create a quorum with the strategy
        StrategyParams[] memory strategies = new StrategyParams[](1);
        strategies[0] = StrategyParams({
            strategy: IStrategy(strategy),
            multiplier: 10_000
        });
        Quorum memory quorum = Quorum({
            strategies: strategies
        });

        // Initialize stake registry
        bytes memory initData = abi.encodeCall(
            ECDSAStakeRegistry.initialize,
            (data.imageVerificationServiceManager, 0, quorum)
        );
        UpgradeableProxyLib.upgradeAndCall(data.stakeRegistry, stakeRegistryImpl, initData);

        // Update service manager implementation with correct stake registry address
        serviceManagerImpl = address(new ImageVerificationServiceManager(
            coreDeployment.avsDirectory,
            data.stakeRegistry,
            coreDeployment.rewardsCoordinator,
            coreDeployment.delegationManager
        ));

        // Initialize service manager
        initData = abi.encodeCall(
            ImageVerificationServiceManager.initialize,
            (rewardsOwner, rewardsInitiator)
        );
        UpgradeableProxyLib.upgradeAndCall(data.imageVerificationServiceManager, serviceManagerImpl, initData);

        // Deploy task contract
        data.imageVerificationTask = address(new ImageVerificationTask(data.imageVerificationServiceManager));

        return data;
    }

    function readDeploymentConfigValues(
        string memory directoryPath,
        uint256 chainId
    ) internal view returns (DeploymentConfigData memory) {
        return readDeploymentConfigValues(directoryPath, string.concat(vm.toString(chainId), ".json"));
    }

    function readDeploymentConfigValues(
        string memory directoryPath,
        string memory fileName
    ) internal view returns (DeploymentConfigData memory) {
        string memory pathToFile = string.concat(directoryPath, fileName);

        require(vm.exists(pathToFile), "ImageVerificationDeployment: Deployment config file does not exist");

        string memory json = vm.readFile(pathToFile);

        DeploymentConfigData memory data;
        data.rewardsOwner = json.readAddress(".rewardsOwner");
        data.rewardsInitiator = json.readAddress(".rewardsInitiator");

        return data;
    }

    function writeDeploymentJson(DeploymentData memory data) internal {
        writeDeploymentJson("deployments/image-verification/", block.chainid, data);
    }

    function writeDeploymentJson(
        string memory path,
        uint256 chainId,
        DeploymentData memory data
    ) internal {
        address proxyAdmin = address(UpgradeableProxyLib.getProxyAdmin(data.imageVerificationServiceManager));

        string memory deploymentData = _generateDeploymentJson(data, proxyAdmin);

        string memory fileName = string.concat(path, vm.toString(chainId), ".json");
        if (!vm.exists(path)) {
            vm.createDir(path, true);
        }

        vm.writeFile(fileName, deploymentData);
        console2.log("Deployment artifacts written to:", fileName);
    }

    function _generateDeploymentJson(
        DeploymentData memory data,
        address proxyAdmin
    ) private view returns (string memory) {
        return string.concat(
            '{"lastUpdate":{"timestamp":"',
            vm.toString(block.timestamp),
            '","block_number":"',
            vm.toString(block.number),
            '"},"addresses":',
            _generateContractsJson(data, proxyAdmin),
            "}"
        );
    }

    function _generateContractsJson(
        DeploymentData memory data,
        address proxyAdmin
    ) private view returns (string memory) {
        return string.concat(
            '{"proxyAdmin":"',
            proxyAdmin.toHexString(),
            '","stakeRegistry":"',
            data.stakeRegistry.toHexString(),
            '","stakeRegistryImpl":"',
            data.stakeRegistry.getImplementation().toHexString(),
            '","imageVerificationServiceManager":"',
            data.imageVerificationServiceManager.toHexString(),
            '","imageVerificationServiceManagerImpl":"',
            data.imageVerificationServiceManager.getImplementation().toHexString(),
            '","imageVerificationTask":"',
            data.imageVerificationTask.toHexString(),
            '","strategy":"',
            data.strategy.toHexString(),
            '","token":"',
            data.token.toHexString(),
            '"}'
        );
    }
} 