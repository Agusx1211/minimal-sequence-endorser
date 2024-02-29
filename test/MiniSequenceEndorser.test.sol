pragma solidity ^0.8.0;

import "wallet-contracts/contracts/modules/commons/interfaces/IModuleCalls.sol";

import { Test, console } from "forge-std/Test.sol";
import { MiniSequenceEndorser } from "../src/MiniSequenceEndorser.sol";
import { PaymentRouter } from "../src/PaymentRouter.sol";
import { Factory } from "wallet-contracts/contracts/Factory.sol";
import { MainModule } from "wallet-contracts/contracts/modules/MainModule.sol";
import { MainModuleUpgradable } from "wallet-contracts/contracts/modules/MainModuleUpgradable.sol";

contract MiniSequenceEndorserTest is Test {
  Factory factory;
  MiniSequenceEndorser endorser;
  PaymentRouter router;
  MainModule mainModule;

  constructor () {
    factory = new Factory();
    endorser = new MiniSequenceEndorser(address(this), address(factory));
    router = new PaymentRouter();

    MainModuleUpgradable mainModuleUpgradable = new MainModuleUpgradable();
    mainModule = new MainModule(address(factory), address(mainModuleUpgradable));
  
    address[] memory routers = new address[](1);
    routers[0] = address(router);
    endorser.setTrustedPaymentRouters(routers, true);
  
    address[] memory implementations = new address[](1);
    implementations[0] = address(mainModule);
    endorser.setKnownImplementations(implementations, true);
  }

  function testEndorse() external {
    // Signer address
    uint256 pk = uint256(2);
    address addr = vm.addr(pk);

    // Imagehash of the wallet
    // TODO
    bytes32 imageHash = bytes32(0x1ec2964607a4fe793f7be3fd04026e5f6747781a741fd690c033889d47f30043);

    // Deploy a wallet
    address wallet = factory.deploy(address(mainModule), imageHash);
    
    vm.deal(wallet, 2 ether);

    // Generate a sequence transaction
    IModuleCalls.Transaction[] memory txs = new IModuleCalls.Transaction[](1);
    txs[0] = IModuleCalls.Transaction(
      true, // delegateCall
      true, // revertOnError
      0, // gasLimit
      address(router), // target
      0, // value
      abi.encode(
        1 ether
      ) // data
    );

    uint256 nonce;

    bytes32 digest = keccak256(
      abi.encode(
        nonce,
        txs
      )
    );

    bytes32 subdigest = keccak256(
      abi.encodePacked(
        "\x19\x01",
        block.chainid,
        wallet,
        digest
      )
    );

    console.log("-----");
    console.logBytes32(digest);
    console.logBytes32(subdigest);
    console.log("-----");

    (
      uint8 _v,
      bytes32 _r,
      bytes32 _s
    ) = vm.sign(pk, subdigest);

    bytes memory signature = abi.encodePacked(
      hex"0001",     // Threshold
      hex"00000000", // Checkpoint
      hex"00",       // Signature part
      hex"01",       // Weight
      _r,
      _s,
      _v,
      hex"01"        // Signature type
    );

    bytes memory data = abi.encodeWithSelector(
      IModuleCalls.execute.selector,
      txs,
      nonce,
      signature
    );

    endorser.isOperationReady(
      wallet,
      data,
      abi.encode(mainModule, imageHash),
      500_000,
      100 gwei,
      0,
      address(0),
      0,
      0,
      false
    );
  }
}
