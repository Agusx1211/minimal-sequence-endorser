pragma solidity ^0.8.0;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { Owned } from "solmate/auth/Owned.sol";
import { LibSequenceSig } from "./utils/LibSequenceSig.sol";
import { NoExecuteModule } from "./NoExecuteModule.sol";

import "wallet-contracts/contracts/modules/commons/interfaces/IModuleCalls.sol";
import "wallet-contracts/contracts/modules/commons/submodules/nonce/SubModuleNonce.sol";
import "wallet-contracts/contracts/modules/commons/ModuleAuthUpgradable.sol";
import "wallet-contracts/contracts/modules/commons/ModuleAuthFixed.sol";
import "wallet-contracts/contracts/modules/commons/ModuleNonce.sol";
import "wallet-contracts/contracts/Factory.sol";
import "erc5189-libs/interfaces/IEndorser.sol";

import "./utils/LibEndorser.sol";
import "./utils/LibString2.sol";
import "./utils/LibBytes2.sol";

// This is a simple Sequence transaction endorser
// that if the transaction pays THE FULL fee at the end
// of the transaction. It does not account for any possible
// refunding to the wallet.
contract MiniSequenceEndorser is IEndorser, Owned {
  using LibString2 for *;
  using LibBytes2 for *;
  using LibEndorser for *;

  //                       NONCE_KEY = keccak256("org.arcadeum.module.calls.nonce");
  bytes32 private constant NONCE_KEY = bytes32(0x8d0bf1fd623d628c741362c1289948e57b3e2905218c676d3e69abee36d6ae2e);
  //                        IMAGE_HASH_KEY = keccak256("org.arcadeum.module.auth.upgradable.image.hash");
  bytes32 internal constant IMAGE_HASH_KEY = bytes32(0xea7157fa25e3aa17d0ae2d5280fa4e24d421c61842aa85e45194e1145aa72bf8);
  bytes private constant SEQUENCE_PROXY_CODE = hex"363d3d373d3d3d363d30545af43d82803e903d91601857fd5bf3";

  mapping(address => LibEndorser.MappingMapper) public erc20BalanceMappers;

  mapping(address => bool) public isKnownImplementation;
  mapping(address => bool) public isGuestModule;
  mapping(address => bool) public isTrustedNestedSigner;
  mapping(address => bool) public isTrustedPaymentRouter;

  address immutable public sequenceFactory;
  address immutable public noExecuteModule;
  address payable immutable public noopWallet;

  constructor(address _owner, address _sequenceFactory) Owned(_owner) {
    sequenceFactory = _sequenceFactory;
    noExecuteModule = address(new NoExecuteModule());
    noopWallet = payable(Factory(_sequenceFactory).deploy(noExecuteModule, bytes32(0)));
  }

  struct ExecuteCall {
    IModuleCalls.Transaction[] txs;
    uint256 nonce;
    bytes signature;
  }

  struct EntrypointControl {
    bool isCreate;
    address wallet;
    bytes data;
    address implementation;
    bytes32 imageHash;
  }

  function setKnownImplementations(address[] calldata _addrs, bool _isKnown) external onlyOwner {
    unchecked {
      for (uint256 i = 0; i < _addrs.length; i++) {
        isKnownImplementation[_addrs[i]] = _isKnown;
      }
    }
  }

  function setGuestModules(address[] calldata _addrs, bool _isGuest) external onlyOwner {
    unchecked {
      for (uint256 i = 0; i < _addrs.length; i++) {
        isGuestModule[_addrs[i]] = _isGuest;
      }
    }
  }

  function setTrustedNestedSigners(address[] calldata _addrs, bool _isTrusted) external onlyOwner {
    unchecked {
      for (uint256 i = 0; i < _addrs.length; i++) {
        isTrustedNestedSigner[_addrs[i]] = _isTrusted;
      }
    }
  }

  function setTrustedPaymentRouters(address[] calldata _addrs, bool _isTrusted) external onlyOwner {
    unchecked {
      for (uint256 i = 0; i < _addrs.length; i++) {
        isTrustedPaymentRouter[_addrs[i]] = _isTrusted;
      }
    }
  }

  function isOperationReady(
    address _entrypoint,
    bytes calldata _data,
    bytes calldata _endorserCallData,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256,
    address _feeToken,
    uint256,
    uint256,
    bool
  ) external returns (
    bool,
    IEndorser.GlobalDependency memory,
    IEndorser.Dependency[] memory
  ) {
    // Create a new dependency carrier
    // this will be passed around to any function that may have
    // a dependency to add
    LibEndorser.DependencyCarrier memory dc;

    // Check if the entrypoint is a Sequence
    // wallet or a guest module, and fetch the meaningful data
    EntrypointControl memory ec = _controlEntrypoint(_entrypoint, _data);

    // We will use this call data a few times
    ExecuteCall memory call = _decodeExecuteCall(_data);

    // This verifies that the first transaction is the payment to the bundler
    uint256 usedEth = _controlFeeTransaction(dc, ec, call, _gasLimit, _maxFeePerGas, _feeToken);

    // We need to verify that all transactions are safe (revertOnError=false,delegateCall=false)
    // we also need to verify that the wallet isn't transfering more funds than what it has
    // or else the top level call will revert.
    // we can use this oportunity to pull the total maximum gasLimit that they may use
    uint256 txsGasLimit = _controlTransactions(dc, call, ec, usedEth);

    // We need to validate the implementation, or else we can't guarantee
    // that the wallet will behave as we expect
    _controlImplementation(dc, _endorserCallData, ec);

    // The nonce determines that the transaction has not been replayed yet
    _controlNonce(dc, call, ec);

    // Nested signatures are stateful! We need to validate them
    // or else they could invalidate the transaction, and thus make the endorser fail
    _controlSignature(call);

    // The imageHash will be validated during the simulation, but we need to have it
    // available for it. We also add it as a dependency
    _controlImagehash(dc, ec, _endorserCallData);

    // Now there are only two things left to do:
    // - Validate that the signature is correct
    // - Measure the gas cost of the signature validation (outside the list of txs)
    // Because all the other variables have been resolved, we can now just simulate the
    // operation. If the operation succeeds we can measure the gas, and if the gasLimit is
    // enough, then we know that the operation is ready.
    txsGasLimit += _simulateOperation(ec, _entrypoint, _data);

    if (txsGasLimit > _gasLimit) {
      revert("Gas limit exceeded: ".concat(txsGasLimit.toString()).concat(" > ").concat(_gasLimit.toString()));
    }

    return (
      true,
      dc.globalDependency,
      dc.dependencies
    );
  }

  function _simulateOperation(
    EntrypointControl memory _ec,
    address _entrypoint,
    bytes calldata _data
  ) internal returns (uint256 gasUsed) {
    unchecked {
      // We need to execute the operation and measure the gas used
      // this will give us a picture of the cost of the non-call parts
      // of the operation. We use a "mirror" wallet that does not perform the calls
      // or else we would end up counting all the gas used by the calls twice.
      NoExecuteModule(noopWallet).setImpersonate(_ec.imageHash, _ec.wallet);

      bool ok;
      if (_ec.isCreate) {
        // This is a bit more complicated, since we should also measure the overhead
        // introduced by the GuestModule call. But we can simulate it too, we only need
        // to reemplace the second call with a call to our noopWallet
        (IModuleCalls.Transaction[] memory txs,,) = abi.decode(_data.slice(4), (IModuleCalls.Transaction[], uint256, bytes));
        txs[1].target = noopWallet;
        bytes memory calldata2 = abi.encodeWithSelector(IModuleCalls.execute.selector, txs, 0, bytes(""));

        uint256 prevGas = gasleft();
        (ok,) = _entrypoint.call(calldata2);
        gasUsed = prevGas - gasleft();
      } else {
        uint256 prevGas = gasleft();
        (ok,) = noopWallet.call(_data);
        gasUsed = prevGas - gasleft();
      }

      if (!ok) {
        revert("Operation simulation failed");
      }
    }
  }

  function _controlImagehash(
    LibEndorser.DependencyCarrier memory _dc,
    EntrypointControl memory _ec,
    bytes calldata _endorserCallData
  ) internal view {
    // Either the wallet is new, and we have the imageHash
    // or we need to fetch it from the wallet, in both cases
    // we make the imageHash a dependency, as other transaction
    // (on a different nonce space) may change it
    _dc.addSlotDependency(_ec.wallet, IMAGE_HASH_KEY);

    if (!_ec.isCreate) {
      (bool ok, bytes memory res) = _ec.wallet.staticcall(abi.encodeWithSelector(ModuleAuthUpgradable.imageHash.selector));

      if (ok && res.length == 32) {
        _ec.imageHash = abi.decode(res, (bytes32));
      } else {
        // This is a counter-factual wallet, so we expect
        // the endorserCallData to provide the imageHash
        // we also need to verify it by computing the sequence address
        if (_endorserCallData.length != 64) {
          revert("counter-factual wallet must provide implementation AND imageHash on endorser calldata");
        }

        (, bytes32 imageHash) = abi.decode(_endorserCallData, (address, bytes32));
        address counterFactualAddr = address(
          uint160(
            uint256(
              keccak256(
                abi.encodePacked(
                  hex"ff",
                  sequenceFactory,
                  imageHash,
                  ModuleAuthFixed(_ec.wallet).INIT_CODE_HASH()
                )
              )
            )
          )
        );

        if (counterFactualAddr != _ec.wallet) {
          revert("Invalid counter-factual wallet address: ".concat(counterFactualAddr.toString().concat(" != ").concat(_ec.wallet.toString())));
        }

        _ec.imageHash = imageHash;
      }
    }

    if (_ec.imageHash == bytes32(0)) {
      revert("Invalid imageHash: 0x0");
    }
  }

  function _controlSignature(
    ExecuteCall memory _call
  ) internal view {
    address[] memory eip1271Signers = LibSequenceSig.readEIP1271FromSig(_call.signature);
    for (uint256 i = 0; i < eip1271Signers.length; i++) {
      // TODO: If we knew the internal structure of these wallets
      // we can instead add them (with the proper dependencies)
      // We can't just mark the signer as a dependency, because
      // the signer MAY also have nested signers
      if (!isTrustedNestedSigner[eip1271Signers[i]]) {
        revert("Untrusted nested signer: ".concat(eip1271Signers[i].toString()));
      }
    }
  }

  function _controlNonce(
    LibEndorser.DependencyCarrier memory _dc,
    ExecuteCall memory _call,
    EntrypointControl memory _ec
  ) internal view {
    (uint256 space, uint256 nonce) = SubModuleNonce.decodeNonce(_call.nonce);

    uint256 currentNonce = ModuleNonce(_ec.wallet).readNonce(space);
    if (nonce != currentNonce) {
      revert("Invalid nonce: ".concat(nonce.toString()).concat(" != ").concat(currentNonce.toString()));
    }

    // This transaction depends on this specific nonce space
    bytes32 nonceSlot = keccak256(abi.encode(NONCE_KEY, space));
    _dc.addSlotDependency(_ec.wallet, nonceSlot);
  }

  function _controlImplementation(
    LibEndorser.DependencyCarrier memory _dc,
    bytes calldata _endorserCalldata,
    EntrypointControl memory _ec
  ) internal view {
    // If the wallet is new we have the implementation from the wallet creation
    // we can just check if it is a good one
    if (_ec.implementation != address(0)) {
      if (!isKnownImplementation[_ec.implementation]) {
        revert("Unknown implementation: ".concat(_ec.implementation.toString()));
      }

      // The wallet is not deployed, this means that the wallet code itself
      // becomes a dependency, as after deployed this path no longer works.
      _dc.addCodeDependency(_ec.wallet);
    } else {
      // Here it becomes a bit more tricky, since we can't directly know the implementation
      // but we can pass it on _endorserCalldata and then as a constraint. Just keep in mind
      // that we won't forward ALL implementations, only the ones that are known to be good.
      address implementation = abi.decode(_endorserCalldata, (address));
      if (!isKnownImplementation[implementation]) {
        revert("Unknown provided implementation: ".concat(implementation.toString()));
      }

      _dc.addConstraint(_ec.wallet, bytes32(uint256(uint160(_ec.wallet))), implementation);      
    }
  }

  function _controlTransactions(
    LibEndorser.DependencyCarrier memory _dc,
    ExecuteCall memory _call,
    EntrypointControl memory _ec,
    uint256 usedEth
  ) internal view returns (uint256 gasLimit) {
    uint256 balance = _ec.wallet.balance;

    if (usedEth > balance) {
      revert("Not enough balance for eth fee: ".concat(usedEth.toString()).concat(" > ").concat(balance.toString()));
    }

    balance -= usedEth;

    unchecked {
      for (uint256 i = 0; i < _call.txs.length; i++) {
        if (i != 0) {
          if (_call.txs[i].revertOnError) {
            revert("Transaction with revertOnError=true: ".concat(i.toString()));
          }

          // The first transaction uses delegateCall
          // it is the only one that can use it
          if (i != 0 && _call.txs[i].delegateCall) {
            revert("Transaction with delegateCall=true: ".concat(i.toString()));
          }
        }

        if (_call.txs[i].value > balance) {
          revert("Transaction with value > balance: ".concat(i.toString()));
        }

        balance -= _call.txs[i].value;
        gasLimit += _call.txs[i].gasLimit;
      }

      // This transaction uses balance
      // so it depends on the wallet's balance
      if (balance != _ec.wallet.balance) {
        _dc.addBalanceDependency(_ec.wallet);
      }
    }
  }

  function _controlFeeTransaction(
    LibEndorser.DependencyCarrier memory _dc,
    EntrypointControl memory _ec,
    ExecuteCall memory _call,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    address _feeToken
  ) internal view returns (uint256 ethUsed) {
    // The first transaction should go to the payment router
    // we need to ask for the first, because the other transactions
    // may spend the funds
    if (!isTrustedPaymentRouter[_call.txs[0].target]) {
      revert("First transaction is not to the payment router");
    }

    if (!_call.txs[0].delegateCall) {
      revert("Payment router must use delegatecall");
    }

    if (!_call.txs[0].revertOnError) {
      revert("Payment router must revert on error");
    }

    if (_call.txs[0].value != 0) {
      revert("Payment router call with value");
    }

    uint256 feeAmount = _maxFeePerGas * _gasLimit;

    if (_feeToken == address(0)) {
      if (_call.txs[0].data.length != 32) {
        revert("Payment router eth call with wrong data length");
      }

      ethUsed = abi.decode(_call.txs[0].data, (uint256));
      if (ethUsed < feeAmount) {
        revert("Not enough ether for the fee: ".concat(ethUsed.toString()).concat(" < ").concat(feeAmount.toString()));
      }

      // This transaction uses balance
      _dc.addBalanceDependency(_ec.wallet);
    } else {
      if (_call.txs[0].data.length != 64) {
        revert("Payment router erc20 call with wrong data length");
      }

      (address token, uint256 amount) = abi.decode(_call.txs[0].data, (address, uint256));
      if (token != _feeToken) {
        revert("Payment router call with wrong token");
      }

      if (amount < feeAmount) {
        revert("Not enough tokens for the fee: ".concat(amount.toString()).concat(" < ").concat(feeAmount.toString()));
      }

      // The token must be supported, we validate this using the mapping mapper
      LibEndorser.MappingMapper memory mapper = erc20BalanceMappers[_feeToken];
      if (!mapper.exists) {
        revert("Fee token not supported: ".concat(_feeToken.toString()));
      }

      // Here we DO NOT check the balance of the wallet
      // NOTICE: That some ERC20s may have more rules (freezing, etc.)
      // this endorser does not support those cases
      ERC20 erc20 = ERC20(_feeToken);
      if (erc20.balanceOf(_ec.wallet) < amount) {
        revert("Not enough tokens for the fee");
      }

      // This transaction depends on the ERC20's balance
      // each ERC20 has its own balance layout, so we use the mapping mapper.
      _dc.addSlotDependency(_feeToken, mapper.getSlotFor(_ec.wallet));
    }
  }

  function _controlEntrypoint(
    address _entrypoint,
    bytes calldata _data
  ) internal view returns (EntrypointControl memory) {
    // Not always is the wallet called directly
    // in this case we can continue, we know that the
    // factory always deploys sequence proxies
    if (!_entrypoint.code.eq(SEQUENCE_PROXY_CODE)) {
      return _controlGuestModuleCall(_entrypoint, _data);
    }

    // The entrypoint is already a wallet, so we must very that
    // it is a Sequence PROXY and that the call is to the execute method
    if (bytes4(_data) != IModuleCalls.execute.selector) {
      revert("Bad entrypoint selector: ".concat(_data[:4].toString()));
    }

    // We don't know implementation and imageHash, this will be important later
    // during signature validation and implementation validation
    EntrypointControl memory res;
    res.wallet = _entrypoint;
    res.data = _data;
    return res;
  }

  function _decodeExecuteCall(bytes memory _data) internal pure returns (ExecuteCall memory) {
    if (bytes4(_data) != IModuleCalls.execute.selector) {
      revert("Bad entrypoint selector: ".concat(_data.slice(0, 4).toString()));
    }

    (
      IModuleCalls.Transaction[] memory txs,
      uint256 nonce,
      bytes memory signature
    ) = abi.decode(_data.slice(4), (IModuleCalls.Transaction[], uint256, bytes));

    return ExecuteCall(txs, nonce, signature);
  }

  function _controlGuestModuleCall(
    address _entrypoint,
    bytes calldata _data
  ) internal view returns (EntrypointControl memory res) {
    // If the entrypoint is a guestModule, then it MUST
    // be a call to execute, with no nonce or signature
    // and it MUST only have two argument: the execute
    // and the wallet deployment.
    if (isGuestModule[_entrypoint]) {
      return _controlGuestModuleCall(_entrypoint, _data);
    }

    ExecuteCall memory call = _decodeExecuteCall(_data);

    if (call.nonce != 0) {
      revert("Guest module call with nonce: ".concat(call.nonce.toString()));
    }
  
    if (call.signature.length != 0) {
      revert("Guest module call with signature: ".concat(call.signature.toString()));
    }

    if (call.txs.length != 2) {
      revert("Guest module call with more than 2 transactions: ".concat(call.txs.length.toString()));
    }

    if (call.txs[0].value != 0) {
      revert("Guest module call with value: ".concat(call.txs[0].value.toString()));
    }

    // The first transaction must be the Sequence factory
    if (call.txs[0].target != sequenceFactory) {
      revert("Guest module call with wrong factory: ".concat(call.txs[0].target.toString()));
    }
  
    // It should be a call to deploy a wallet
    if (bytes4(call.txs[0].data) != Factory.deploy.selector) {
      revert("Guest module call with wrong factory selector: ".concat(call.txs[0].data.slice(0, 4).toString()));
    }
  
    // Get the imageHash, we will need this to very the signature
    // as the wallet does not exist yet
    (res.implementation, res.imageHash) = abi.decode(call.txs[0].data.slice(4), (address, bytes32));

    // The second transaction must be the entrypoint
    // it contains the real calldata and the real target
    res.wallet = call.txs[1].target;
    res.data = call.txs[1].data;
    res.isCreate = true;
  }
}
