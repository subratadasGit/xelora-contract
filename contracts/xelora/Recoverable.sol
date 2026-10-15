pragma solidity 0.4.23;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20Basic.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "./ownership/Multiownable.sol";


/**
 * @title Recoverable ensures ether and ERC20 tokens sent to this contract in
 * error can be rescued rather than trapped forever.
 * @author Zachary Kilgore @ Xelora Technologies LLC
 * @dev Previously built on the OpenZeppelin Claimable and CanReclaimToken
 * contracts, both of which inherit the single-key Ownable. Rescue is a
 * value-moving action, so it is now gated behind a quorum of owners instead.
 *
 * The destination is an explicit argument rather than a stored owner address.
 * Because Multiownable hashes the calldata, the destination is part of what
 * the owners are voting on: a quorum approves moving funds to one specific
 * address, not merely approving a rescue in the abstract.
 */
contract Recoverable is Multiownable {
  using SafeERC20 for ERC20Basic;

  /**
   * Event to track ether being rescued from the contract.
   * @param to Address the ether was sent to
   * @param amount Amount of wei transferred
   */
  event EtherReclaimed(address indexed to, uint256 amount);

  /**
   * Event to track ERC20 tokens being rescued from the contract.
   * @param token Address of the token contract
   * @param to Address the tokens were sent to
   * @param amount Amount of tokens transferred
   */
  event TokenReclaimed(address indexed token, address indexed to, uint256 amount);


  /**
   * @notice Transfer all ether held by this contract to a chosen address.
   * @dev Requires a quorum of owners to agree on the destination.
   * @param _to Address to send the ether to
   */
  function reclaimEther(address _to) external onlyManyOwners {
    require(_to != address(0), "Destination must not be the zero address");

    uint256 _amount = address(this).balance;
    require(_amount > 0, "There must be ether to reclaim");

    _to.transfer(_amount);

    emit EtherReclaimed(_to, _amount);
  }

  /**
   * @notice Transfer the full balance of an ERC20 token held by this contract
   * to a chosen address.
   * @dev Requires a quorum of owners to agree on both the token and the
   * destination. Child contracts restrict which tokens may be moved by
   * overriding canReclaimToken.
   * @param _token The ERC20 token to rescue
   * @param _to Address to send the tokens to
   */
  function reclaimToken(ERC20Basic _token, address _to) external onlyManyOwners {
    require(address(_token) != address(0), "Token address must not be blank");
    require(_to != address(0), "Destination must not be the zero address");
    require(canReclaimToken(_token), "This token may not be reclaimed from this contract");

    uint256 _balance = _token.balanceOf(address(this));
    require(_balance > 0, "There must be tokens to reclaim");

    _token.safeTransfer(_to, _balance);

    emit TokenReclaimed(address(_token), _to, _balance);
  }

  /**
   * @notice Whether a given token is eligible to be rescued from this contract.
   * @dev Defaults to true. A contract that holds a token on behalf of other
   * people must override this so that owners cannot rescue what is not theirs.
   * @return true if the token may be reclaimed
   */
  function canReclaimToken(ERC20Basic) public view returns(bool) {
    return true;
  }

}
