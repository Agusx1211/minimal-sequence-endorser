pragma solidity ^0.8.0;


library LibBytes2 {
  using LibBytes2 for *;

  function eq(bytes memory _a, bytes memory _b) internal pure returns (bool) {
    return keccak256(_a) == keccak256(_b);
  }

  function eq(bytes memory _a, bytes4 _b) internal pure returns (bool) {
    return _a.eq(abi.encodePacked(_b));
  }

  function toAddress(bytes memory _bytes) internal pure returns (address) {
    if (_bytes.length != 20) {
      revert("LibBytes: toAddress length != 20");
    }

    address result;
    assembly {
      result := mload(add(_bytes, 20))
    }

    return result;
  }

  function toUint24(bytes memory _bytes) internal pure returns (uint24) {
    if (_bytes.length != 3) {
      revert("LibBytes: toUint24 length != 3");
    }

    uint24 result;
    assembly {
      result := mload(add(_bytes, 3))
    }

    return result;
  }

  function slice(bytes memory _bytes, uint256 _start) internal pure returns (bytes memory res) {
    require(_bytes.length >= _start, "LibBytes: slice out of range");

    res = new bytes(_bytes.length - _start);
    for (uint256 i = _start; i < _bytes.length; i++) {
      res[i - _start] = _bytes[i];
    }
  }

  function slice(bytes memory _bytes, uint256 _start, uint256 _length) internal pure returns (bytes memory res) {
    if (_length == 0) {
      return res;
    }

    require(_bytes.length >= _start + _length, "LibBytes: slice out of range");

    res = new bytes(_length);
    for (uint256 i = 0; i < _length; i++) {
      res[i] = _bytes[_start + i];
    }
  }
}
