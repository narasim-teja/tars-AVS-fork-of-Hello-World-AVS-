// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {IServiceManager} from "@eigenlayer-middleware/src/interfaces/IServiceManager.sol";

interface IImageVerificationServiceManager is IServiceManager {
    struct Task {
        bytes32 imageHash;
        bytes32 metadataHash;
        uint32 taskCreatedBlock;
        bytes deviceSignature;
    }

    event NewTaskCreated(uint32 indexed taskIndex, Task task);
    event TaskResponded(uint32 indexed taskIndex, Task task, address operator);

    function createNewTask(
        bytes32 imageHash,
        bytes32 metadataHash,
        bytes calldata deviceSignature
    ) external returns (Task memory);

    function respondToTask(
        Task calldata task,
        uint32 referenceTaskIndex,
        bytes memory signature
    ) external;

    function latestTaskNum() external view returns (uint32);
    function allTaskHashes(uint32 taskIndex) external view returns (bytes32);
    function allTaskResponses(address operator, uint32 taskIndex) external view returns (bytes memory);
} 