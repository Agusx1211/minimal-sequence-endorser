pragma solidity ^0.8.0;

import "./LibBytes.sol";
import "./LibSlices.sol";


library LibSequenceSig {
  using LibSlices for *;
  using LibBytes for *;

  /// @dev ModuleAuth
  bytes1 private constant _LEGACY_TYPE      = 0x00;
  bytes1 private constant _DYNAMIC_TYPE     = 0x01;
  bytes1 private constant _NO_CHAIN_ID_TYPE = 0x02;
  bytes1 private constant _CHAINED_TYPE     = 0x03;

  /// @dev SequenceBaseSig
  bytes1 private constant _FLAG_SIGNATURE         = 0x00;
  bytes1 private constant _FLAG_ADDRESS           = 0x01;
  bytes1 private constant _FLAG_DYNAMIC_SIGNATURE = 0x02;
  bytes1 private constant _FLAG_NODE              = 0x03;
  bytes1 private constant _FLAG_BRANCH            = 0x04;
  bytes1 private constant _FLAG_SUBDIGEST         = 0x05;
  bytes1 private constant _FLAG_NESTED            = 0x06;

  function readEIP1271FromTree(bytes memory _sig) internal pure returns (address[] memory res) {
    unchecked {
      uint256 rindex = 0;
      while (rindex < _sig.length) {
        bytes1 flag = _sig[rindex];
        rindex += 1;

        if (flag == _FLAG_SIGNATURE) {
          // Skip static signatures, EOAs don't change
          rindex += 67; // [u8: weight, bytes32: r, bytes32: s, u8: v, u8: type]
          continue;
        }

        if (flag == _FLAG_ADDRESS) {
          rindex += 20; // [u8: weight, address: addr]
          continue;
        }

        if (flag == _FLAG_DYNAMIC_SIGNATURE) {
          rindex += 1; // [u8: weight]

          res = res.append(_sig.slice(rindex, rindex+20).toAddress());
          rindex += 20; // [address: addr]
        
          uint256 size = _sig.slice(rindex, rindex+3).toUint24();
          rindex += 3;    // [u24: size]
          rindex += size; // [bytes: signature]
          continue;
        }

        if (flag == _FLAG_NODE) {
          rindex += 32; // [u8: weight, bytes32: node]
          continue;
        }

        if (flag == _FLAG_SUBDIGEST) {
          rindex += 32; // [u8: weight, bytes32: subdigest]
          continue;
        }

        if (flag == _FLAG_BRANCH) {
          uint256 size = _sig.slice(rindex, rindex+3).toUint24();
          rindex += 3;    // [u24: size]

          bytes memory branch = _sig.slice(rindex, rindex+size);
          rindex += size; // [bytes: branch]

          res = res.append(readEIP1271FromTree(branch));
          continue;
        }

        if (flag == _FLAG_NESTED) {
          rindex += 3; // [u8: externalWeight, u16: internalThreshold]

          uint256 size = _sig.slice(rindex, rindex+3).toUint24();
          rindex += 3;    // [u24: size]

          bytes memory nested = _sig.slice(rindex, rindex+size);
          rindex += size; // [bytes: nested]

          res = res.append(readEIP1271FromTree(nested));
          continue;
        }

        revert("LibSequenceSig: invalid part flag");
      }
    }
  }

  function readEIP1271FromSig(bytes memory _sig) internal pure returns (address[] memory) {
    unchecked {
      bytes1 flag = _sig[0];

      if (flag == _LEGACY_TYPE) {
        return readEIP1271FromTree(_sig.slice(6));
      }

      if (flag == _DYNAMIC_TYPE) {
        return readEIP1271FromTree(_sig.slice(7));
      }

      if (flag == _NO_CHAIN_ID_TYPE) {
        return readEIP1271FromTree(_sig.slice(7));
      }

      if (flag == _CHAINED_TYPE) {
        uint256 rindex = 0;
        address[] memory res;

        while (rindex < _sig.length) {
          uint256 size = _sig.slice(rindex+1, rindex+4).toUint24();
          rindex += 4;    // [u24: size]
          res = res.append(readEIP1271FromTree(_sig.slice(rindex, rindex+size)));
          rindex += size; // [bytes: tree]
        }

        return res;
      }

      revert("LibSequenceSig: invalid flag");
    }
  }
}
