// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {ECDSAServiceManagerBase} from "@eigenlayer-middleware/src/unaudited/ECDSAServiceManagerBase.sol";
import {ECDSAStakeRegistry} from "@eigenlayer-middleware/src/unaudited/ECDSAStakeRegistry.sol";
import {IServiceManager} from "@eigenlayer-middleware/src/interfaces/IServiceManager.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract ImageVerificationServiceManager is ECDSAServiceManagerBase {
    using ECDSA for bytes32;

    uint32 public latestTaskNum;
    mapping(uint32 => bytes32) public allTaskHashes;
    mapping(address => mapping(uint32 => bytes)) public allTaskResponses;

    struct Task {
        bytes32 imageHash;
        bytes32 metadataHash;
        uint32 taskCreatedBlock;
        bytes deviceSignature;
    }

    event NewTaskCreated(uint32 indexed taskIndex, Task task);
    event TaskResponded(uint32 indexed taskIndex, Task task, address operator);

    modifier onlyOperator() {
        require(
            ECDSAStakeRegistry(stakeRegistry).operatorRegistered(msg.sender),
            "Operator must be the caller"
        );
        _;
    }

    constructor(
        address _avsDirectory,
        address _stakeRegistry,
        address _rewardsCoordinator,
        address _delegationManager
    )
        ECDSAServiceManagerBase(
            _avsDirectory,
            _stakeRegistry,
            _rewardsCoordinator,
            _delegationManager
        )
    {}

    function initialize(
        address initialOwner,
        address _rewardsInitiator
    ) external initializer {
        __ServiceManagerBase_init(initialOwner, _rewardsInitiator);
    }

    function createNewTask(
        bytes32 imageHash,
        bytes32 metadataHash,
        bytes calldata deviceSignature
    ) external returns (Task memory) {
        Task memory newTask;
        newTask.imageHash = imageHash;
        newTask.metadataHash = metadataHash;
        newTask.taskCreatedBlock = uint32(block.number);
        newTask.deviceSignature = deviceSignature;

        allTaskHashes[latestTaskNum] = keccak256(abi.encode(newTask));
        emit NewTaskCreated(latestTaskNum, newTask);
        latestTaskNum = latestTaskNum + 1;

        return newTask;
    }

    function respondToTask(
        Task calldata task,
        uint32 referenceTaskIndex,
        bytes memory signature
    ) external onlyOperator {
        require(
            keccak256(abi.encode(task)) == allTaskHashes[referenceTaskIndex],
            "Task does not match recorded hash"
        );
        require(
            allTaskResponses[msg.sender][referenceTaskIndex].length == 0,
            "Operator already responded"
        );

        // Create message hash from task data
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                task.imageHash,
                task.metadataHash,
                task.taskCreatedBlock,
                task.deviceSignature
            )
        );
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        
        // Verify operator's signature
        bytes4 magicValue = IERC1271.isValidSignature.selector;
        require(
            magicValue == ECDSAStakeRegistry(stakeRegistry).isValidSignature(ethSignedMessageHash, signature),
            "Invalid signature"
        );

        // Store response
        allTaskResponses[msg.sender][referenceTaskIndex] = signature;
        emit TaskResponded(referenceTaskIndex, task, msg.sender);
    }
} 