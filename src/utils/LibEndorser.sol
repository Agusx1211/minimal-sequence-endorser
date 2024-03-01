pragma solidity ^0.8.0;

import "erc5189-libs/interfaces/IEndorser.sol";

import "./LibMath.sol";


library LibEndorser {
  using LibEndorser for *;

  struct DependencyCarrier {
    IEndorser.GlobalDependency globalDependency;
    IEndorser.Dependency[] dependencies;
  }

  function dependencyFor(DependencyCarrier memory _carrier, address _addr) internal pure returns (IEndorser.Dependency memory) {
    unchecked {
      for (uint256 i = 0; i != _carrier.dependencies.length; i++) {
        if (_carrier.dependencies[i].addr == _addr) {
          return _carrier.dependencies[i];
        }
      }

      // We need to create a new dependency for this address, and add it to the carrier
      IEndorser.Dependency memory dep;
      dep.addr = _addr;

      IEndorser.Dependency[] memory newDeps = new IEndorser.Dependency[](_carrier.dependencies.length + 1);
      for (uint256 i = 0; i != _carrier.dependencies.length; i++) {
        newDeps[i] = _carrier.dependencies[i];
      }

      newDeps[_carrier.dependencies.length] = dep;
      _carrier.dependencies = newDeps;

      return dep;
    }
  }

  function addBalanceDependency(DependencyCarrier memory _carrier, address _addr) internal pure {
    dependencyFor(_carrier, _addr).balance = true;
  }

  function addCodeDependency(DependencyCarrier memory _carrier, address _addr) internal pure {
    dependencyFor(_carrier, _addr).code = true;
  }

  function addNonceDependency(DependencyCarrier memory _carrier, address _addr) internal pure {
    dependencyFor(_carrier, _addr).nonce = true;
  }

  function addAllSlotsDependency(DependencyCarrier memory _carrier, address _addr) internal pure {
    dependencyFor(_carrier, _addr).allSlots = true;
  }

  function addSlotDependency(DependencyCarrier memory _carrier, address _addr, bytes32 _slot) internal pure {
    unchecked {
      IEndorser.Dependency memory dep = dependencyFor(_carrier, _addr);

      for (uint256 i = 0; i != dep.slots.length; i++) {
        if (dep.slots[i] == _slot) {
          return;
        }
      }

      bytes32[] memory newSlots = new bytes32[](dep.slots.length + 1);
      for (uint256 i = 0; i != dep.slots.length; i++) {
        newSlots[i] = dep.slots[i];
      }

      newSlots[dep.slots.length] = _slot;
      dep.slots = newSlots;
    }
  }

  function addConstraint(DependencyCarrier memory _carrier, address _addr, bytes32 _slot, address _value) internal pure {
    _carrier.addConstraint(_addr, _slot, bytes32(uint256(uint160(_value))));
  }

  function addConstraint(DependencyCarrier memory _carrier, address _addr, bytes32 _slot, bytes32 _value) internal pure {
    _carrier.addConstraint(_addr, _slot, _value, _value);
  }

  function addConstraint(DependencyCarrier memory _carrier, address _addr, bytes32 _slot, bytes32 _minValue, bytes32 _maxValue) internal pure {
    unchecked {
      IEndorser.Dependency memory dep = dependencyFor(_carrier, _addr);

      IEndorser.Constraint memory constraint;
      bool exists;

      for (uint256 i = 0; i != dep.constraints.length; i++) {
        if (dep.constraints[i].slot == _slot) {
          constraint = dep.constraints[i];
          exists = true;
          break;
        }
      }

      // If it exists we can just update the values to the new min and max
      if (exists) {
        constraint.minValue = LibMath.max(constraint.minValue, _minValue);
        constraint.maxValue = LibMath.min(constraint.maxValue, _maxValue);

        if (constraint.minValue > constraint.maxValue) {
          revert("Constraint min value is greater than max value");
        }

        return;
      }

      constraint.slot = _slot;
      constraint.minValue = _minValue;
      constraint.maxValue = _maxValue;

      // Add the new constraint to the dependency
      IEndorser.Constraint[] memory newConstraints = new IEndorser.Constraint[](dep.constraints.length + 1);
      for (uint256 i = 0; i != dep.constraints.length; i++) {
        newConstraints[i] = dep.constraints[i];
      }

      newConstraints[dep.constraints.length] = constraint;
      dep.constraints = newConstraints;
    }
  }

  // 
  // Allows constructing representations of 1D Solidity mappings
  // (https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html#mappings-and-dynamic-arrays)
  //

  struct MappingMapper {
    bool exists;
    uint248 position;
  }

  function getSlotFor(MappingMapper memory _mm, bytes32 _key) internal pure returns (bytes32) {
    return keccak256(abi.encode(_key, _mm.position));
  }

  function getSlotFor(MappingMapper memory _mm, uint256 _key) internal pure returns (bytes32) {
    return keccak256(abi.encode(_key, _mm.position));
  }

  function getSlotFor(MappingMapper memory _mm, address _key) internal pure returns (bytes32) {
    return keccak256(abi.encode(_key, _mm.position));
  }
}
