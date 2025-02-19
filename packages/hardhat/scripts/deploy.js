// scripts/deploy.js
const hre = require("hardhat");

async function main() {
  // Retrieve the deployer account from Hardhat runtime
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await hre.ethers.provider.getBalance(deployer.address)).toString());

  // Deploy PumpForgeToken
  const PumpForgeToken = await hre.ethers.getContractFactory("PumpForgeToken");
  const token = await PumpForgeToken.deploy("Test Token", "TTK", "QmExampleImageHash");
  await token.waitForDeployment();
  console.log("PumpForgeToken deployed to:", token.target);

  // Deploy PumpForgeFactory
  const PumpForgeFactory = await hre.ethers.getContractFactory("PumpForgeFactory");
  const factory = await PumpForgeFactory.deploy();
  await factory.waitForDeployment();
  console.log("PumpForgeFactory deployed to:", factory.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error during deployment:", error);
    process.exit(1);
  });
