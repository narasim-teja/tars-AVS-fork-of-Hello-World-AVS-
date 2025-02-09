// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {ImageVerificationServiceManager} from "./ImageVerificationServiceManager.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract ImageVerificationTask {
    using ECDSA for bytes32;

    ImageVerificationServiceManager public immutable serviceManager;
    uint32 public constant RESPONSE_WINDOW_BLOCKS = 30;

    struct VerificationResult {
        bool isAuthentic;
        bytes32 proofHash;
        uint256 timestamp;
        address[] verifiers;
        uint256 quorumWeight;
    }

    mapping(bytes32 => VerificationResult) public verificationResults;
    mapping(bytes32 => mapping(address => bool)) public operatorResponses;

    event VerificationCompleted(
        bytes32 indexed taskId,
        bool isAuthentic,
        bytes32 proofHash,
        uint256 timestamp,
        uint256 quorumWeight
    );

    constructor(address _serviceManager) {
        serviceManager = ImageVerificationServiceManager(_serviceManager);
    }

    function verifyTask(
        ImageVerificationServiceManager.Task calldata task,
        uint32 referenceTaskIndex,
        bytes memory signature
    ) external {
        require(
            msg.sender == address(serviceManager),
            "Only service manager can verify tasks"
        );

        require(
            block.number <= task.taskCreatedBlock + RESPONSE_WINDOW_BLOCKS,
            "Task response window expired"
        );

        bytes32 taskId = keccak256(
            abi.encodePacked(
                task.imageHash,
                task.metadataHash,
                task.taskCreatedBlock
            )
        );

        require(!operatorResponses[taskId][msg.sender], "Operator already responded");
        operatorResponses[taskId][msg.sender] = true;

        // Get or create verification result
        VerificationResult storage result = verificationResults[taskId];
        if (result.timestamp == 0) {
            result.timestamp = block.timestamp;
            result.verifiers = new address[](0);
        }

        // Add verifier
        result.verifiers.push(msg.sender);
        
        // Update quorum weight (in a real implementation, this would check the operator's stake)
        result.quorumWeight += 1;

        // Check if we have enough quorum weight for verification
        if (result.quorumWeight >= 2) { // Requiring at least 2 operators for this example
            result.isAuthentic = verifyImageAuthenticity(
                task.imageHash,
                task.metadataHash,
                task.deviceSignature
            );

            result.proofHash = keccak256(
                abi.encodePacked(
                    taskId,
                    signature,
                    block.number,
                    result.verifiers
                )
            );

            emit VerificationCompleted(
                taskId,
                result.isAuthentic,
                result.proofHash,
                result.timestamp,
                result.quorumWeight
            );
        }
    }

    function verifyImageAuthenticity(
        bytes32 imageHash,
        bytes32 metadataHash,
        bytes memory deviceSignature
    ) internal pure returns (bool) {
        // In a real implementation, this would:
        // 1. Verify the device signature against known Meta device public keys
        // 2. Check the image hash against a merkle tree of known valid images
        // 3. Verify the metadata hash matches the expected format
        // For this example, we'll return true if we have a valid device signature
        return deviceSignature.length > 0;
    }

    function getVerificationResult(bytes32 taskId) external view returns (
        bool isAuthentic,
        bytes32 proofHash,
        uint256 timestamp,
        address[] memory verifiers,
        uint256 quorumWeight
    ) {
        VerificationResult storage result = verificationResults[taskId];
        return (
            result.isAuthentic,
            result.proofHash,
            result.timestamp,
            result.verifiers,
            result.quorumWeight
        );
    }
} 