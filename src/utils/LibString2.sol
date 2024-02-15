pragma solidity ^0.8.0;

import { LibString } from "solmate/utils/LibString.sol";

bytes constant HEX_CHARS = bytes("0123456789abcdef");

library LibString2 {
  function concat(string memory _a, string memory _b) internal pure returns (string memory) {
    return string(abi.encodePacked(_a, _b));
  }

  function toString(int256 x) internal pure returns (string memory) {
    return LibString.toString(x);
  }

  function toString(uint256 x) internal pure returns (string memory) {
    return LibString.toString(x);
  }

  function toString(bytes32 x) internal pure returns (string memory) {
    return LibString2.toString(abi.encode(x));
  }

  function toString(bytes4 x) internal pure returns (string memory) {
    return LibString2.toString(abi.encodePacked(x));
  }

  function toString(address x) internal pure returns (string memory) {
    return LibString2.toString(abi.encodePacked(x));
  }

  function toString(bytes memory _data) internal pure returns (string memory) {
    // Each byte takes 2 hex characters + the 0x prefix
    bytes memory str = new bytes(2 * _data.length + 2);

    unchecked {
      str[0] = "0";
      str[1] = "x";

      for (uint256 i = 0; i < _data.length; i++) {
        str[2 * i + 2] = HEX_CHARS[uint8(_data[i]) >> 4];
        str[2 * i + 3] = HEX_CHARS[uint8(_data[i]) & 0x0f];
      }
    }
  
    return string(str);
  }
}
