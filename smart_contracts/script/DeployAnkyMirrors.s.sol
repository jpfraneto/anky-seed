// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Continuity} from "../src/ANKY_MIRRORS.sol";

contract DeployAnkyMirrors is Script {
    function run() external returns (Continuity mirrors) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.envAddress("ANKY_MIRRORS_OWNER");
        address initialMintSigner = vm.envAddress("ANKY_MIRRORS_MINT_SIGNER");
        address initialTreasury = vm.envAddress("ANKY_MIRRORS_TREASURY");
        string memory initialContractURI = vm.envOr("ANKY_MIRRORS_CONTRACT_URI", string(""));

        vm.startBroadcast(deployerPrivateKey);

        mirrors = new Continuity(initialOwner, initialMintSigner, initialTreasury, initialContractURI);

        vm.stopBroadcast();
    }
}
