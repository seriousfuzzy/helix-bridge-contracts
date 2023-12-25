const ethUtil = require('ethereumjs-util');
const abi = require('ethereumjs-abi');
const secp256k1 = require('secp256k1');
const fs = require("fs");

var ProxyDeployer = require("./proxy.js");

const privateKey = process.env.PRIKEY

const crabNetwork = {
    name: "crab",
    url: "https://crab-rpc.darwinia.network",
    dao: "0x88a39B052d477CfdE47600a7C9950a441Ce61cb4",
    backing: "0x27F58339CbB8c5A6f58d5D05Bfc1B3fd121F489C",
    chainid: 44
};

const sepoliaNetwork = {
    name: "sepolia",
    url: "https://rpc-sepolia.rockx.com",
    dao: "0x88a39B052d477CfdE47600a7C9950a441Ce61cb4",
    issuing: "0xFF3bc7372A8011CFaD43D240464ef2fe74C59b86",
    chainid: 11155111
};

function wallet(url) {
    const provider = new ethers.providers.JsonRpcProvider(url);
    const wallet = new ethers.Wallet(privateKey, provider);
    return wallet;
}

async function registerIssuing() {
    const issuingNetwork = sepoliaNetwork;
    const walletIssuing = wallet(sepoliaNetwork.url);

    const issuing = await ethers.getContractAt("xTokenIssuing", issuingNetwork.issuing, walletIssuing);

    await issuing.registerxToken(
        44,
        "0x0000000000000000000000000000000000000000",
        "crab",
        "crab native token",
        "CRAB",
        18,
        "0x56bc75e2d63100000",
        { gasLimit: 1000000 }
    );
}

async function registerBacking() {
    const backingNetwork = crabNetwork;
    const walletBacking = wallet(crabNetwork.url);

    const backing = await ethers.getContractAt("xTokenBacking", backingNetwork.backing, walletBacking);
    const xToken = "0x4828B88240166B8bB79A833Fd0dD38EaeADAAB1a";

    await backing.registerOriginalToken(
        11155111,
        "0x0000000000000000000000000000000000000000",
        xToken,
        "0x56bc75e2d63100000"
    );
}

async function lockAndRemoteIssuing() {
    const backingNetwork = crabNetwork;
    const walletBacking = wallet(crabNetwork.url);

    const backing = await ethers.getContractAt("xTokenBacking", backingNetwork.backing, walletBacking);

    //const tx = await backing.callStatic.lockAndRemoteIssuing(
    await backing.lockAndRemoteIssuing(
        11155111,
        "0x0000000000000000000000000000000000000000",
        walletBacking.address,
        ethers.utils.parseEther("100"),
        1703247763001,
        "0x000000000000000000000000000000000000000000000000000000000005f02200000000000000000000000088a39b052d477cfde47600a7c9950a441ce61cb400000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000",
        { value: ethers.utils.parseEther("105.4") }
    );
}

async function burnAndRemoteUnlock() {
    const issuingNetwork = sepoliaNetwork;
    const walletIssuing = wallet(sepoliaNetwork.url);

    const issuing = await ethers.getContractAt("xTokenIssuing", issuingNetwork.issuing, walletIssuing);

    const xTokenAddress = "0x4828B88240166B8bB79A833Fd0dD38EaeADAAB1a";
    const xToken = await ethers.getContractAt("xTokenErc20", xTokenAddress, walletIssuing);
    await xToken.approve(issuing.address, ethers.utils.parseEther("10000000"), {gasLimit: 500000});
    await issuing.burnAndRemoteUnlock(
        xTokenAddress,
        walletIssuing.address,
        ethers.utils.parseEther("5"),
        1703248419043,
        "0x000000000000000000000000000000000000000000000000000000000006493c00000000000000000000000088a39b052d477cfde47600a7c9950a441ce61cb400000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000",
        {
            value: ethers.utils.parseEther("0.0000007"),
            gasLimit: 1000000,
        }
    );
}

async function requestRemoteUnlockForIssuingFailure() {
    const issuingNetwork = sepoliaNetwork;
    const walletIssuing = wallet(sepoliaNetwork.url);

    const issuing = await ethers.getContractAt("xTokenIssuing", issuingNetwork.issuing, walletIssuing);

    await issuing.requestRemoteUnlockForIssuingFailure(
        44,
        "0x0000000000000000000000000000000000000000",
        walletIssuing.address,
        walletIssuing.address,
        ethers.utils.parseEther("100"),
        1703247763000,
        "0x000000000000000000000000000000000000000000000000000000000006493c00000000000000000000000088a39b052d477cfde47600a7c9950a441ce61cb400000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000",
        {
            value: ethers.utils.parseEther("0.0000007"),
            gasLimit: 1000000,
        }
    );
}

async function requestRemoteIssuingForUnlockFailure() {
    const backingNetwork = crabNetwork;
    const walletBacking = wallet(crabNetwork.url);

    const backing = await ethers.getContractAt("xTokenBacking", backingNetwork.backing, walletBacking);

    await backing.requestRemoteIssuingForUnlockFailure(
        "0xab4f619082b61cac56f60611a661e2b16d8052ab2531be791d95821f8fb232ce",
        11155111,
        "0x0000000000000000000000000000000000000000",
        walletBacking.address,
        ethers.utils.parseEther("100"),
        "0x000000000000000000000000000000000000000000000000000000000005f02200000000000000000000000088a39b052d477cfde47600a7c9950a441ce61cb400000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000",
        { value: ethers.utils.parseEther("5.4") }
    );
}

async function main() {
    //await registerIssuing();
    //await registerBacking();
    //await lockAndRemoteIssuing();
    //await burnAndRemoteUnlock();
    await requestRemoteUnlockForIssuingFailure();
    //await requestRemoteIssuingForUnlockFailure();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
    
