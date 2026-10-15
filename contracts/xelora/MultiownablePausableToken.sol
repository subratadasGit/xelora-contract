pragma solidity 0.4.23;

import "openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol";
import "./Recoverable.sol";


/**
 * @title MultiownablePausableToken is a StandardToken whose ERC20 operations
 * can be frozen in an emergency.
 * @author Zachary Kilgore @ Xelora Technologies LLC
 * @dev Replaces the OpenZeppelin PausableToken, which inherits the single-key
 * Ownable. The two directions are deliberately asymmetric:
 *
 * - Pausing is a safety brake. It only ever removes power and it is worthless
 * if it arrives late, so any single owner may pull it.
 * - Unpausing restores the ability to move value. A stolen key must not be
 * able to undo the brake that was pulled because of the theft, so it takes a
 * quorum.
 */
contract MultiownablePausableToken is StandardToken, Recoverable {

  /** Whether ERC20 operations are currently frozen. */
  bool public paused = false;


  /** Event to track that the token has been paused. */
  event Pause();

  /** Event to track that the token has been unpaused. */
  event Unpause();


  /** Ensure the token is not paused. */
  modifier whenNotPaused() {
    require(!paused, "Expected the token to not be paused");
    _;
  }

  /** Ensure the token is paused. */
  modifier whenPaused() {
    require(paused, "Expected the token to be paused");
    _;
  }


  /**
   * @notice Freeze all ERC20 operations.
   * @dev Any single owner may act, so a compromise can be contained without
   * waiting to assemble a quorum.
   */
  function pause() public onlyAnyOwner whenNotPaused {
    paused = true;
    emit Pause();
  }

  /**
   * @notice Resume ERC20 operations.
   * @dev Requires a quorum, so one compromised key cannot lift the brake.
   */
  function unpause() public onlyManyOwners whenPaused {
    paused = false;
    emit Unpause();
  }


  function transfer(address _to, uint256 _value) public whenNotPaused returns(bool) {
    return super.transfer(_to, _value);
  }

  function transferFrom(address _from, address _to, uint256 _value) public whenNotPaused returns(bool) {
    return super.transferFrom(_from, _to, _value);
  }

  function approve(address _spender, uint256 _value) public whenNotPaused returns(bool) {
    return super.approve(_spender, _value);
  }

  function increaseApproval(address _spender, uint256 _addedValue) public whenNotPaused returns(bool) {
    return super.increaseApproval(_spender, _addedValue);
  }

  function decreaseApproval(address _spender, uint256 _subtractedValue) public whenNotPaused returns(bool) {
    return super.decreaseApproval(_spender, _subtractedValue);
  }

}
