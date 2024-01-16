//import { Wallet, utils, ContractFactory } from "zksync-web3";
import { Wallet, ContractFactory } from "zksync-ethers";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { ProxyDeployer } from "./proxy.ts";

const privateKey = process.env.PRIKEY

const zkSyncNetwork = {
    proxyAdmin: "0x57E8fcaAfDE61b179BAe86cDAbfaca99E2A16484",
    dao: "0x88a39B052d477CfdE47600a7C9950a441Ce61cb4",
    logicAddress: "0x93944493105771aaa13B93fcb6c9a0642118d675",
};

export default async function (hre: HardhatRuntimeEnvironment) {
  // deploy proxy admin contract
  console.log(`Running deploy script for the zksync lnv3 bridge proxy contract`);

  // Initialize the wallet.
  const wallet = new Wallet(privateKey);

  // Create deployer object and load the artifact of the contract you want to deploy.
  const deployer = new Deployer(hre, wallet);
  const artifact = await deployer.loadArtifact("HelixLnBridgeV3");

  // deploy proxy contract
  const logicFactory = new ContractFactory(artifact.abi, artifact.bytecode, wallet);
  const proxyAddress = await ProxyDeployer.deployProxyContract(deployer, zkSyncNetwork.proxyAdmin, logicFactory, zkSyncNetwork.logicAddress, [zkSyncNetwork.dao]);
  console.log(`proxy contract was deployed to ${proxyAddress}`);

  const calldata = ProxyDeployer.getInitializerData(logicFactory.interface, [zkSyncNetwork.dao], "initialize");
  const proxyVerificationId = await hre.run("verify:verify", {
      address: proxyAddress,
      constructorArguments: [zkSyncNetwork.logicAddress, zkSyncNetwork.proxyAdmin, calldata],
  });
  console.log(`Proxy Verification ID: ${proxyVerificationId}`);
}

