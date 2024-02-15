pragma solidity ^0.8.0;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

/**
 * @title PaymentRouter
 * @dev A contract that routes payments to tx.origin
 */
contract PaymentRouter {
  fallback() external payable {
    if (msg.data.length == 0) {
      SafeTransferLib.safeTransferETH(tx.origin, msg.value);
    } else {
      (address token, uint256 amount) = abi.decode(msg.data, (address, uint256));
      SafeTransferLib.safeTransfer(ERC20(token), tx.origin, amount);
    }
  }
}
