import { ethers } from "ethers";
import * as dotenv from "dotenv";
const fs = require('fs');
const path = require('path');
dotenv.config();

// Setup env variables
const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);
let chainId = 31337;

const avsDeploymentData = JSON.parse(fs.readFileSync(path.resolve(__dirname, `../contracts/deployments/image-verification/${chainId}.json`), 'utf8'));
const imageVerificationServiceManagerAddress = avsDeploymentData.addresses.imageVerificationServiceManager;

// Load ABI
const imageVerificationServiceManagerABI = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../abis/ImageVerificationServiceManager.json'), 'utf8'));

// Initialize contract object
const imageVerificationServiceManager = new ethers.Contract(imageVerificationServiceManagerAddress, imageVerificationServiceManagerABI, wallet);

const createTask = async () => {
    // Create a mock image hash and metadata hash
    const imageHash = ethers.keccak256(ethers.toUtf8Bytes("test_image.jpg"));
    const metadataHash = ethers.keccak256(ethers.toUtf8Bytes(JSON.stringify({
        timestamp: Date.now(),
        device: "Meta Quest Pro",
        location: "San Francisco, CA"
    })));

    // Create a mock device signature
    const mockDeviceKey = ethers.Wallet.createRandom();
    const messageHash = ethers.solidityPackedKeccak256(
        ["bytes32", "bytes32"],
        [imageHash, metadataHash]
    );
    const deviceSignature = await mockDeviceKey.signMessage(ethers.getBytes(messageHash));

    console.log("Creating new image verification task");
    console.log("Image Hash:", imageHash);
    console.log("Metadata Hash:", metadataHash);

    const tx = await imageVerificationServiceManager.createNewTask(
        imageHash,
        metadataHash,
        deviceSignature
    );
    await tx.wait();
    console.log("Task created successfully");
};

const main = async () => {
    // Create a new task every 5 seconds
    setInterval(async () => {
        try {
            await createTask();
        } catch (error) {
            console.error("Error creating task:", error);
        }
    }, 5000);
};

main().catch((error) => {
    console.error("Error in main function:", error);
}); 