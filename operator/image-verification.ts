import { ethers } from "ethers";
import * as dotenv from "dotenv";
const fs = require('fs');
const path = require('path');
dotenv.config();

// Check if the process.env object is empty
if (!Object.keys(process.env).length) {
    throw new Error("process.env object is empty");
}

// Setup env variables
const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);
let chainId = 31337;

const avsDeploymentData = JSON.parse(fs.readFileSync(path.resolve(__dirname, `../contracts/deployments/image-verification/${chainId}.json`), 'utf8'));
const coreDeploymentData = JSON.parse(fs.readFileSync(path.resolve(__dirname, `../contracts/deployments/core/${chainId}.json`), 'utf8'));

const delegationManagerAddress = coreDeploymentData.addresses.delegation;
const avsDirectoryAddress = coreDeploymentData.addresses.avsDirectory;
const imageVerificationServiceManagerAddress = avsDeploymentData.addresses.imageVerificationServiceManager;
const ecdsaStakeRegistryAddress = avsDeploymentData.addresses.stakeRegistry;

// Load ABIs
const delegationManagerABI = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../abis/IDelegationManager.json'), 'utf8'));
const ecdsaRegistryABI = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../abis/ECDSAStakeRegistry.json'), 'utf8'));
const imageVerificationServiceManagerABI = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../abis/ImageVerificationServiceManager.json'), 'utf8'));
const avsDirectoryABI = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../abis/IAVSDirectory.json'), 'utf8'));

// Initialize contract objects from ABIs
const delegationManager = new ethers.Contract(delegationManagerAddress, delegationManagerABI, wallet);
const imageVerificationServiceManager = new ethers.Contract(imageVerificationServiceManagerAddress, imageVerificationServiceManagerABI, wallet);
const ecdsaRegistryContract = new ethers.Contract(ecdsaStakeRegistryAddress, ecdsaRegistryABI, wallet);
const avsDirectory = new ethers.Contract(avsDirectoryAddress, avsDirectoryABI, wallet);

const signAndRespondToTask = async (taskIndex: number, task: any) => {
    // Create message hash from task data
    const messageHash = ethers.solidityPackedKeccak256(
        ["bytes32", "bytes32", "uint32", "bytes"],
        [task.imageHash, task.metadataHash, task.taskCreatedBlock, task.deviceSignature]
    );
    
    // Convert to EIP-191 format
    const ethSignedMessageHash = ethers.hashMessage(ethers.getBytes(messageHash));
    
    // Get the operator's address
    const operatorAddress = await wallet.getAddress();
    
    // Create the signature data for EIP-1271 validation
    const signature = await wallet.signMessage(ethers.getBytes(messageHash));
    const operators = [operatorAddress];
    const signatures = [signature];
    const signedTaskData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address[]", "bytes[]", "uint32"],
        [operators, signatures, ethers.toBigInt(await provider.getBlockNumber()-1)]
    );

    console.log(`Signing and responding to task ${taskIndex}`);
    console.log('Task hash:', messageHash);
    console.log('EIP-191 hash:', ethSignedMessageHash);
    console.log('Operator:', operatorAddress);
    console.log('Block number:', await provider.getBlockNumber());

    // Ensure task object matches the contract's Task struct exactly
    const taskStruct = {
        imageHash: task.imageHash,
        metadataHash: task.metadataHash,
        taskCreatedBlock: task.taskCreatedBlock,
        deviceSignature: task.deviceSignature
    };

    const tx = await imageVerificationServiceManager.respondToTask(
        taskStruct,
        taskIndex,
        signedTaskData
    );
    await tx.wait();
    console.log(`Responded to task ${taskIndex} successfully`);
};

const registerOperator = async () => {
    // Registers as an Operator in EigenLayer.
    try {
        const isOperator = await delegationManager.isOperator(wallet.address);
        if (!isOperator) {
            const tx1 = await delegationManager.registerAsOperator({
                __deprecated_earningsReceiver: await wallet.address,
                delegationApprover: "0x0000000000000000000000000000000000000000",
                stakerOptOutWindowBlocks: 0
            }, "");
            await tx1.wait();
            console.log("Operator registered to Core EigenLayer contracts");
        } else {
            console.log("Operator already registered with EigenLayer");
        }
    } catch (error) {
        console.error("Error in registering as operator:", error);
        // Continue execution as the operator might already be registered
    }
    
    // Check if already registered with AVS
    try {
        const isAVSOperator = await ecdsaRegistryContract.isOperator(wallet.address);
        if (isAVSOperator) {
            console.log("Operator already registered with AVS");
            return;
        }
    } catch (error) {
        // Continue with registration if check fails
    }

    const salt = ethers.hexlify(ethers.randomBytes(32));
    const expiry = Math.floor(Date.now() / 1000) + 3600; // Example expiry, 1 hour from now

    // Calculate the digest hash
    const operatorDigestHash = await avsDirectory.calculateOperatorAVSRegistrationDigestHash(
        wallet.address, 
        await imageVerificationServiceManager.getAddress(), 
        salt, 
        expiry
    );
    console.log("Operator registration digest hash:", operatorDigestHash);
    
    // Sign the digest hash with the operator's private key
    console.log("Signing digest hash with operator's private key");
    const signature = await wallet.signMessage(ethers.getBytes(operatorDigestHash));

    // Check if operator is already registered with EigenLayer
    const isOperator = await delegationManager.isOperator(wallet.address);
    if (isOperator) {
        console.log("Operator already registered with EigenLayer");
    } else {
        // Register as an operator with EigenLayer
        console.log("Registering as an operator with EigenLayer");
        const tx1 = await delegationManager.registerAsOperator();
        await tx1.wait();
        console.log("Successfully registered with EigenLayer");
    }

    // Check if operator is already registered with AVS
    const isRegistered = await ecdsaRegistryContract.operatorRegistered(wallet.address);
    if (isRegistered) {
        console.log("Operator already registered with AVS");
    } else {
        // Register Operator to AVS
        const operatorSignature = {
            signature: signature,
            salt: salt,
            expiry: expiry
        };

        const tx2 = await ecdsaRegistryContract.registerOperatorWithSignature(
            operatorSignature,
            await wallet.getAddress() // Use getAddress() to ensure proper address format
        );
        await tx2.wait();
        console.log("Operator registered on AVS successfully");
    }
};

const monitorNewTasks = async () => {
    console.log("Monitoring for new image verification tasks...");
    
    imageVerificationServiceManager.on("NewTaskCreated", async (taskIndex, task) => {
        console.log(`New image verification task detected: ${taskIndex}`);
        console.log(`Image Hash: ${task.imageHash}`);
        console.log(`Metadata Hash: ${task.metadataHash}`);
        
        try {
            await signAndRespondToTask(taskIndex, task);
        } catch (error) {
            console.error(`Error responding to task ${taskIndex}:`, error);
        }
    });
};

const main = async () => {
    try {
        await registerOperator();
        console.log("Operator registered on AVS successfully");
        await monitorNewTasks();
    } catch (error) {
        console.error("Error in main function:", error);
    }
};

main().catch((error) => {
    console.error(error);
    process.exit(1);
}); 