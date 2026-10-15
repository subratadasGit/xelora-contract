pragma solidity 0.4.23;


/**
 * @title Multiownable
 * @notice Access control for a set of N owners where a privileged action only
 * executes once M of them have independently requested the exact same action.
 * @dev Replaces the single-key Ownable / onlyOwner model.
 *
 * An "operation" is identified by the hash of the calldata plus the current
 * owners generation. Because the calldata is part of the hash, owners vote on
 * the precise call, arguments included: two owners who disagree on the
 * recipient of a transfer are voting for two different operations, and neither
 * one executes.
 *
 * Votes are tracked in a bitmask, one bit per owner, which both prevents an
 * owner from voting twice and bounds the owner set to 256 addresses.
 *
 * Based on the pattern popularised by the Bitclave Multiownable contract,
 * re-implemented and documented here for Solidity 0.4.23.
 */
contract Multiownable {

  /** Incremented whenever the owner set changes, which invalidates every
    * operation that was pending under the previous set. */
  uint256 public ownersGeneration;

  /** How many owners must agree for an onlyManyOwners action to execute. */
  uint256 public howManyOwnersDecide;

  /** The current owner set. Maximum of 256 entries. */
  address[] public owners;

  /** Operation hashes that currently have at least one vote. */
  bytes32[] public allOperations;

  /** Index of an owner within owners, offset by one so that zero means
    * "not an owner". */
  mapping(address => uint256) public ownersIndices;

  /** Position of an operation within allOperations. */
  mapping(bytes32 => uint256) public allOperationsIndices;

  /** Bitmask of owners that have voted for an operation. */
  mapping(bytes32 => uint256) public votesMaskByOperation;

  /** Number of votes an operation has collected. */
  mapping(bytes32 => uint256) public votesCountByOperation;

  /** Set while a confirmed operation is executing, so that a privileged
    * function may call another privileged function on this same contract
    * without needing a second round of votes. */
  address private insideCallSender;
  uint256 private insideCallCount;


  /** Emitted the first time an owner votes for a new operation. */
  event OperationCreated(bytes32 operation, uint256 howMany, uint256 ownersCount, address proposer);

  /** Emitted on every vote, including the first and the deciding one. */
  event OperationUpvoted(bytes32 operation, uint256 votes, uint256 howMany, uint256 ownersCount, address voter);

  /** Emitted when an operation reaches its threshold and executes. */
  event OperationPerformed(bytes32 operation, uint256 howMany, uint256 ownersCount, address performer);

  /** Emitted when an owner withdraws a vote before the threshold is reached. */
  event OperationDownvoted(bytes32 operation, uint256 votes, uint256 ownersCount, address voter);

  /** Emitted when a pending operation loses its last vote. */
  event OperationCancelled(bytes32 operation, address lastCanceller);

  /** Emitted when the owner set or the quorum changes. */
  event OwnershipTransferred(
    address[] previousOwners,
    uint256 previousHowManyOwnersDecide,
    address[] newOwners,
    uint256 newHowManyOwnersDecide
  );


  /** Any single owner may act alone. For low-risk or emergency actions. */
  modifier onlyAnyOwner {
    if (checkHowManyOwners(1)) {
      bool update = (insideCallSender == address(0));
      if (update) {
        insideCallSender = msg.sender;
        insideCallCount = 1;
      }
      _;
      if (update) {
        insideCallSender = address(0);
        insideCallCount = 0;
      }
    }
  }

  /** The configured quorum of owners must agree. The normal case. */
  modifier onlyManyOwners {
    if (checkHowManyOwners(howManyOwnersDecide)) {
      bool update = (insideCallSender == address(0));
      if (update) {
        insideCallSender = msg.sender;
        insideCallCount = howManyOwnersDecide;
      }
      _;
      if (update) {
        insideCallSender = address(0);
        insideCallCount = 0;
      }
    }
  }

  /** Every owner must agree. Reserved for irreversible actions. */
  modifier onlyAllOwners {
    if (checkHowManyOwners(owners.length)) {
      bool update = (insideCallSender == address(0));
      if (update) {
        insideCallSender = msg.sender;
        insideCallCount = owners.length;
      }
      _;
      if (update) {
        insideCallSender = address(0);
        insideCallCount = 0;
      }
    }
  }


  /**
   * @dev The deployer is the sole initial owner, so deployment scripts keep
   * working. The real owner set is installed with transferOwnershipWithHowMany
   * immediately after deployment.
   */
  constructor() public {
    owners.push(msg.sender);
    ownersIndices[msg.sender] = 1;
    howManyOwnersDecide = 1;
  }


  /** @notice Number of current owners. */
  function ownersCount() public view returns(uint256) {
    return owners.length;
  }

  /** @notice Number of operations awaiting more votes. */
  function allOperationsCount() public view returns(uint256) {
    return allOperations.length;
  }

  /** @notice Whether an address is part of the current owner set. */
  function isOwner(address _wallet) public view returns(bool) {
    return ownersIndices[_wallet] > 0;
  }

  /**
   * @notice Withdraw your vote for a pending operation.
   * @dev Lets an owner take back approval if circumstances change before the
   * quorum is reached. Once an operation executes it is no longer pending and
   * cannot be withdrawn.
   * @param _operation The operation hash to withdraw a vote from
   */
  function cancelPending(bytes32 _operation) public {
    uint256 ownerIndex = ownersIndices[msg.sender] - 1;
    require(ownerIndex < owners.length, "cancelPending: sender is not an owner");

    uint256 ownerMask = 2 ** ownerIndex;
    require(
      (votesMaskByOperation[_operation] & ownerMask) != 0,
      "cancelPending: sender has not voted for this operation"
    );

    votesMaskByOperation[_operation] -= ownerMask;
    uint256 remaining = votesCountByOperation[_operation] - 1;
    votesCountByOperation[_operation] = remaining;

    emit OperationDownvoted(_operation, remaining, owners.length, msg.sender);

    if (remaining == 0) {
      deleteOperation(_operation);
      emit OperationCancelled(_operation, msg.sender);
    }
  }

  /**
   * @notice Replace the owner set, keeping the current quorum size.
   * @param _newOwners The new owner set
   */
  function transferOwnership(address[] _newOwners) public {
    transferOwnershipWithHowMany(_newOwners, howManyOwnersDecide);
  }

  /**
   * @notice Replace the owner set and the quorum.
   * @dev Requires the current quorum to agree. This is the recovery path when
   * an owner key is lost or an owner leaves, and it is deliberately not
   * onlyAllOwners, otherwise a single lost key would freeze the contract
   * permanently.
   * @param _newOwners The new owner set
   * @param _newHowManyOwnersDecide How many of them must agree from now on
   */
  function transferOwnershipWithHowMany(
    address[] _newOwners,
    uint256 _newHowManyOwnersDecide
  )
    public
    onlyManyOwners
  {
    require(_newOwners.length > 0, "transferOwnership: owners list must not be empty");
    require(_newOwners.length <= 256, "transferOwnership: owners list is limited to 256 entries");
    require(_newHowManyOwnersDecide > 0, "transferOwnership: quorum must be greater than zero");
    require(
      _newHowManyOwnersDecide <= _newOwners.length,
      "transferOwnership: quorum must not exceed the owner count"
    );

    uint256 i;

    // Clear the reverse lookup for the outgoing set before writing the new one,
    // otherwise an address present in both sets would keep a stale index.
    for (i = 0; i < owners.length; i++) {
      delete ownersIndices[owners[i]];
    }

    for (i = 0; i < _newOwners.length; i++) {
      require(_newOwners[i] != address(0), "transferOwnership: owner must not be the zero address");
      require(ownersIndices[_newOwners[i]] == 0, "transferOwnership: owners must be unique");
      ownersIndices[_newOwners[i]] = i + 1;
    }

    emit OwnershipTransferred(owners, howManyOwnersDecide, _newOwners, _newHowManyOwnersDecide);

    owners = _newOwners;
    howManyOwnersDecide = _newHowManyOwnersDecide;

    // Every pending operation was voted on by the previous owner set, so it is
    // discarded. Bumping the generation changes every future operation hash,
    // which strands any leftover vote state permanently out of reach.
    allOperations.length = 0;
    ownersGeneration++;
  }


  /****************
   *** Internal ***
   ****************/

  /**
   * @dev Record a vote from the caller and report whether the operation has
   * now collected enough of them to execute.
   * @param _howMany Number of owners required for this particular action
   * @return true if the vote from the caller completed the quorum
   */
  function checkHowManyOwners(uint256 _howMany) internal returns(bool) {
    // A privileged function already executing under a satisfied quorum may call
    // another privileged function that needs no more owners than the one in
    // progress. Without this, internal composition would deadlock.
    if (insideCallSender == msg.sender) {
      require(
        _howMany <= insideCallCount,
        "checkHowManyOwners: nested call requires more owners than the outer call"
      );
      return true;
    }

    uint256 ownerIndex = ownersIndices[msg.sender] - 1;
    require(ownerIndex < owners.length, "checkHowManyOwners: sender is not an owner");

    // The calldata is part of the hash, so owners vote on the exact call and
    // its arguments, never merely on the function name.
    bytes32 operation = keccak256(msg.data, ownersGeneration);

    uint256 ownerMask = 2 ** ownerIndex;
    require(
      (votesMaskByOperation[operation] & ownerMask) == 0,
      "checkHowManyOwners: owner has already voted for this operation"
    );
    votesMaskByOperation[operation] |= ownerMask;

    uint256 operationVotesCount = votesCountByOperation[operation] + 1;
    votesCountByOperation[operation] = operationVotesCount;

    if (operationVotesCount == 1) {
      allOperationsIndices[operation] = allOperations.length;
      allOperations.push(operation);
      emit OperationCreated(operation, _howMany, owners.length, msg.sender);
    }

    emit OperationUpvoted(operation, operationVotesCount, _howMany, owners.length, msg.sender);

    if (operationVotesCount == _howMany) {
      deleteOperation(operation);
      emit OperationPerformed(operation, _howMany, owners.length, msg.sender);
      return true;
    }

    return false;
  }

  /**
   * @dev Remove an operation and all of its vote state.
   * @param _operation The operation hash to clear
   */
  function deleteOperation(bytes32 _operation) internal {
    uint256 index = allOperationsIndices[_operation];

    if (index < allOperations.length - 1) {
      allOperations[index] = allOperations[allOperations.length - 1];
      allOperationsIndices[allOperations[index]] = index;
    }
    allOperations.length--;

    delete votesMaskByOperation[_operation];
    delete votesCountByOperation[_operation];
    delete allOperationsIndices[_operation];
  }

}
