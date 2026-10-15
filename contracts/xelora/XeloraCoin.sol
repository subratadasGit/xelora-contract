pragma solidity 0.4.23;

import "./MultiownablePausableToken.sol";
import "./UpgradeableToken.sol";


/**
 * @title XeloraCoin ERC20 Compliant Token Contract
 * @author Zachary Kilgore @ Xelora Technologies LLC
 * @dev XeloraCoin is a standard ERC20 token that has the following additional
 * properties:
 *
 * - Upgradeable: Allows for the token to be upgraded to a new contract. Setting
 * the upgrade agent requires every owner to agree.
 * - Multiownable: Privileged actions are controlled by a set of owners, with
 * the number of owners required chosen per action according to how much damage
 * that action could do. This replaces the previous single-owner model.
 * - Recoverable: Allows a quorum of owners to recover ether and tokens sent to
 * the contract in error that would otherwise be trapped.
 * - Pauseable: Allows ERC20 functionality (transfer, approval, etc) to be
 * paused by any single owner in an emergency, and unpaused only by a quorum.
 */
contract XeloraCoin is MultiownablePausableToken, UpgradeableToken {

  string public constant name = "XeloraCoin";
  string public constant symbol = "FXC";
  uint8 public constant decimals = 18;

  uint256 public constant INITIAL_SUPPLY = 100000000000 * (10 ** uint256(decimals));


  /**
    * @notice XeloraCoin (ERC20 Token) contract constructor.
    * @dev Assigns all tokens to contract creator.
    */
  constructor() public {
    totalSupply_ = INITIAL_SUPPLY;
    balances[msg.sender] = INITIAL_SUPPLY;
    emit Transfer(0x0, msg.sender, INITIAL_SUPPLY);
  }

  /**
   * @dev Allow UpgradeableToken functionality only if contract is not paused.
   */
  function canUpgrade() public view returns(bool) {
    return !paused;
  }

}
