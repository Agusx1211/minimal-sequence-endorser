pragma solidity ^0.8.0;

import "wallet-contracts/contracts/modules/MainModuleUpgradable.sol";


contract NoExecuteModule is MainModuleUpgradable {
  event StubEvent();

  function _validateNonce2(uint256 _rawNonce) internal virtual {
    // Retrieve current nonce for this wallet
    (uint256 space, uint256 providedNonce) = SubModuleNonce.decodeNonce(_rawNonce);

    uint256 currentNonce = readNonce(space);
    if (currentNonce != providedNonce && false) {
      revert BadNonce(space, providedNonce, currentNonce);
    }

    unchecked {
      uint256 newNonce = providedNonce + 1;

      _writeNonce(space, newNonce);
      emit NonceChange(space, newNonce);
      return;
    }
  }

  function setImageHash(bytes32 _imageHash) external {
    _updateImageHash(_imageHash);
  }

  function execute(
    Transaction[] calldata _txs,
    uint256 _nonce,
    bytes calldata _signature
  ) external override virtual onlyDelegatecall {
    // Validate and update nonce
    _validateNonce2(_nonce);

    // Hash and verify transaction bundle
    (bool isValid, bytes32 txHash) = _signatureValidation(
      keccak256(
        abi.encode(
          _nonce,
          _txs
        )
      ),
      _signature
    );

    if (!isValid) {
      revert InvalidSignature(txHash, _signature);
    }

    // Do not execute any transactions
    _executeNoop(txHash, _txs);
  }

  function _executeNoop(
    bytes32 _txHash,
    Transaction[] calldata _txs
  ) internal {
    unchecked {
      // Execute transaction
      uint256 size = _txs.length;
      for (uint256 i = 0; i < size; i++) {
        Transaction calldata transaction = _txs[i];
        uint256 gasLimit = transaction.gasLimit;

        if (gasleft() < gasLimit) revert NotEnoughGas(i, gasLimit, gasleft());

        bool success = true;
        if (transaction.delegateCall) {
          emit StubEvent();
        } else {
          emit StubEvent();
        }

        if (success) {
          emit TxExecuted(_txHash, i);
        } else {
          // Avoid copy of return data until neccesary
          _revertBytes(
            transaction.revertOnError,
            _txHash,
            i,
            LibOptim.returnData()
          );
        }
      }
    }
  }
}
