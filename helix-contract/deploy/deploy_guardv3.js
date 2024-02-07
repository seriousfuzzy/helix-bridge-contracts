const ethUtil = require('ethereumjs-util');
const abi = require('ethereumjs-abi');
const secp256k1 = require('secp256k1');
const fs = require("fs");

var Create2 = require("./create2.js");

const privateKey = process.env.PRIKEY

function wallet(configure, network) {
    const provider = new ethers.providers.JsonRpcProvider(network.url);
    const wallet = new ethers.Wallet(privateKey, provider);
    return wallet;
}

function chainInfo(configure, network) {
    return configure.chains[network];
}

async function deployGuardV3(wallet, deployerAddress, salt) {
    const guardContract = await ethers.getContractFactory("GuardV3", wallet);
    const bytecode = Create2.getDeployedBytecode(
        guardContract,
        ['address[]','address','uint256','uint256'],
        [['0x3B9E571AdeCB0c277486036D6097E9C2CCcfa9d9'],wallet.address,1,259200]);
    const address = await Create2.deploy(deployerAddress, wallet, bytecode, salt, 8000000);
    console.log("finish to deploy guard contract, address: ", address);
    return address;
}

// 2. deploy mapping token factory
async function main() {
    const pathConfig = "./address/ln-dev.json";
    const configure = JSON.parse(
        fs.readFileSync(pathConfig, "utf8")
    );

    const network = chainInfo(configure, "sepolia");
    const w = wallet(configure, network);
    await deployGuardV3(w, network.deployer, "guardv3-v1.0.0");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

