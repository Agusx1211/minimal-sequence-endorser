pragma solidity ^0.8.0;


contract PaymentRouter {
  function payTxOrigin(address _token, uint256 _amount) external {
    
  }

  fallback() external payable {
    payable(tx.origin).transfer(msg.value);
  }
}