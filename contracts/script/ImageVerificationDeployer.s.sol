// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";
import {ImageVerificationDeploymentLib} from "./utils/ImageVerificationDeploymentLib.sol";
import {CoreDeploymentLib} from "./utils/CoreDeploymentLib.sol";
import {UpgradeableProxyLib} from "./utils/UpgradeableProxyLib.sol";
import {StrategyBase} from "@eigenlayer/contracts/strategies/StrategyBase.sol";
import {ERC20Mock} from "../test/ERC20Mock.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {StrategyFactory} from "@eigenlayer/contracts/strategies/StrategyFactory.sol";
import {StrategyManager} from "@eigenlayer/contracts/core/StrategyManager.sol";
import {IRewardsCoordinator} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {IStrategy} from "@eigenlayer-middleware/src/interfaces/IECDSAStakeRegistryEventsAndErrors.sol";

import "forge-std/Test.sol";

contract ImageVerificationDeployer is Script, Test {
    using CoreDeploymentLib for *;
    using UpgradeableProxyLib for address;

    address private deployer;
    address proxyAdmin;
    address rewardsOwner;
    address rewardsInitiator;
    IStrategy imageVerificationStrategy;
    CoreDeploymentLib.DeploymentData coreDeployment;
    ImageVerificationDeploymentLib.DeploymentData imageVerificationDeployment;
    ImageVerificationDeploymentLib.DeploymentConfigData imageVerificationConfig;
    ERC20Mock token;

    function setUp() public virtual {
        deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.label(deployer, "Deployer");

        imageVerificationConfig = ImageVerificationDeploymentLib.readDeploymentConfigValues(
            "config/image-verification/",
            block.chainid
        );

        coreDeployment = CoreDeploymentLib.readDeploymentJson("deployments/core/", block.chainid);
    }

    function run() external {
        vm.startBroadcast(deployer);
        rewardsOwner = imageVerificationConfig.rewardsOwner;
        rewardsInitiator = imageVerificationConfig.rewardsInitiator;

        token = new ERC20Mock();
        imageVerificationStrategy = IStrategy(
            StrategyFactory(coreDeployment.strategyFactory).deployNewStrategy(token)
        );

        proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();

        imageVerificationDeployment = ImageVerificationDeploymentLib.deployContracts(
            proxyAdmin,
            coreDeployment,
            rewardsInitiator,
            rewardsOwner,
            address(imageVerificationStrategy)
        );

        imageVerificationDeployment.strategy = address(imageVerificationStrategy);
        imageVerificationDeployment.token = address(token);

        vm.stopBroadcast();
        verifyDeployment();
        ImageVerificationDeploymentLib.writeDeploymentJson(imageVerificationDeployment);
    }

    function verifyDeployment() internal view {
        require(
            imageVerificationDeployment.stakeRegistry != address(0),
            "StakeRegistry address cannot be zero"
        );
        require(
            imageVerificationDeployment.imageVerificationServiceManager != address(0),
            "ImageVerificationServiceManager address cannot be zero"
        );
        require(
            imageVerificationDeployment.imageVerificationTask != address(0),
            "ImageVerificationTask address cannot be zero"
        );
        require(imageVerificationDeployment.strategy != address(0), "Strategy address cannot be zero");
        require(proxyAdmin != address(0), "ProxyAdmin address cannot be zero");
        require(
            coreDeployment.delegationManager != address(0),
            "DelegationManager address cannot be zero"
        );
        require(coreDeployment.avsDirectory != address(0), "AVSDirectory address cannot be zero");
    }
} 