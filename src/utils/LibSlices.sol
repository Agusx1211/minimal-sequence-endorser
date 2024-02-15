pragma solidity ^0.8.0;


library LibSlices {
  function append(address[] memory _a, address[] memory _b) internal pure returns (address[] memory) {
    unchecked {
      if (_a.length == 0) {
        return _b;
      }

      if (_b.length == 0) {
        return _a;
      }

      address[] memory newAddresses = new address[](_a.length + _b.length);
      for (uint256 i = 0; i != _a.length; i++) {
        newAddresses[i] = _a[i];
      }
      for (uint256 i = 0; i != _b.length; i++) {
        newAddresses[i + _a.length] = _b[i];
      }
      return newAddresses; 
    }
  }

  function append(address[] memory _a, address _b) internal pure returns (address[] memory) {
    unchecked {
      address[] memory newAddresses = new address[](_a.length + 1);
      for (uint256 i = 0; i != _a.length; i++) {
        newAddresses[i] = _a[i];
      }
      newAddresses[_a.length] = _b;
      return newAddresses; 
    }
  }
}
