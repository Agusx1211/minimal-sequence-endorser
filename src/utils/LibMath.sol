pragma solidity ^0.8.0;


library LibMath {
  function min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }

  function min(bytes32 _a, bytes32 _b) internal pure returns (bytes32) {
    return _a < _b ? _a : _b;
  }

  function max(uint256 a, uint256 b) internal pure returns (uint256) {
    return a > b ? a : b;
  }

  function max(bytes32 _a, bytes32 _b) internal pure returns (bytes32) {
    return _a > _b ? _a : _b;
  }
}
