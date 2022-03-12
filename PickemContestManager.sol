pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "./nftpickem.sol";

// Status 1 is loss, 2 is win, 0 is refund
struct ContestPerformance {
  bytes32 contestName;
  uint256 entryFee;
  uint256 payout;
  uint8 status;
  uint8 picksCorrect;
  uint8 totalPicks;
  address player;
}

contract GrandFantasyManager is ChainlinkClient {
  using Counters for Counters.Counter;
  using Chainlink for Chainlink.Request;

  // Variables to hold contest history for participants
  mapping (uint => ContestPerformance) public performances;
  mapping (address => uint[]) public playerPerformances;
  Counters.Counter private currentPerformanceId;

  // Gets current oracle address for The Rundown
  function getOracleAddress() external view returns (address) {
    return chainlinkOracleAddress();
  }

  // Sets oracle address for The Rundown
  function setOracle(address _oracle) external {
    require(msg.sender == administrator);
    setChainlinkOracle(_oracle);
  }

  // Sends all link in contract back to administrator
  function withdrawLink() public {
    require(msg.sender == administrator);
    LinkTokenInterface linkToken = LinkTokenInterface(chainlinkTokenAddress());
    require(linkToken.transfer(administrator, linkToken.balanceOf(address(this))), "Unable to transfer");
  }

  // Sets the JobId for The Rundown get resolved games job
  function setSpecId(bytes32 jobId) public {
    require(msg.sender == administrator);
    specId = jobId;
  }

  // Resolved game response that will be received from The Rundown oracle
  struct GameResolve {
    bytes32 gameId;
    uint8 homeScore;
    uint8 awayScore;
    uint8 statusId;
  }
  // Game data received from fulfill
  bytes[] public gamesFromOracle;

  function bytes32ToStr(bytes32 _bytes32) public pure returns (string memory) {
    bytes memory bytesArray = new bytes(32);
    for (uint256 i; i < 32; i++) {
        bytesArray[i] = _bytes32[i];
        }
    return string(bytesArray);
  }


  // Calls the rundown api to receive game results for the contest group with the
  // highest priority
  function requestGameResults(uint32 date, uint256 payment, uint contractGroup, uint gamesLength) private {
    Chainlink.Request memory request = buildChainlinkRequest(specId, address(this), this.fulfill.selector);
    uint i;
    string[] memory gameIds = new string[](gamesLength);
    if(contractGroup == 1) {
      for(i = 0; i<ncaabGames1.length; i++) {
        gameIds[i] = string(bytes32ToStr(ncaabGames1[i].rundownId));
      }
    } else if(contractGroup == 2) {
      for(i = 0; i<ncaabGames2.length; i++) {
        gameIds[i] = string(bytes32ToStr(ncaabGames2[i].rundownId));
      }
    } else if(contractGroup == 3) {
      for(i = 0; i<ncaabGames3.length; i++) {
        gameIds[i] = string(bytes32ToStr(ncaabGames3[i].rundownId));
      }
    }

    request.addUint("sportId", 5);
    request.add("market", "resolve");
    request.addUint("date", uint256(date));
    request.addStringArray("gameIds", gameIds);

    sendChainlinkRequest(request, payment);
  }

  // Callback function from request game results
  function fulfill(bytes32 _requestId, bytes[] memory _games) public recordChainlinkFulfillment(_requestId) {
    //Games come back here
    gamesFromOracle = _games;
  }

  // Receives a group of contest performancs from a child contract
  // these contest performances are used to hold contest history
  function receivePerformance(ContestPerformance[] memory newPerformances) public {
    address sender = msg.sender;
    bool senderValid = false;

    uint i;
    for(i = 0; i<activeContracts1.current() + 1; i++) {
      if(ncaabContracts1[i] == sender) {
        senderValid = true;
      }
    }
    for(i = 0; i<activeContracts2.current(); i++) {
      if(ncaabContracts2[i] == sender) {
        senderValid = true;
      }
    }
    for(i = 0; i<activeContracts3.current(); i++) {
      if(ncaabContracts3[i] == sender) {
        senderValid = true;
      }
    }

    require(senderValid);

    for(i = 0; i<newPerformances.length; i++) {
      performances[uint(currentPerformanceId.current())] = newPerformances[i];
      playerPerformances[newPerformances[i].player].push(uint(currentPerformanceId.current()));
      currentPerformanceId.increment();
    }
  }

  function getPerformanceForPlayer(address playerWallet) public view returns(ContestPerformance[] memory) {
    uint[] memory performanceIds = playerPerformances[playerWallet];
    ContestPerformance[] memory returnPerformances = new ContestPerformance[](performanceIds.length);
    uint i;
    for(i = 0; i<performanceIds.length; i++) {
      returnPerformances[i] = performances[performanceIds[i]];
    }
    return returnPerformances;
  }


  // Queue for contest resolution
  mapping(uint256 => uint) queue;
  uint256 first = 1;
  uint256 last = 0;
  function enqueue(uint data) private {
      last += 1;
      queue[last] = data;
  }
  function dequeue() private returns (uint data) {
      require(last >= first);  // non-empty queue

      data = queue[first];

      delete queue[first];
      first += 1;
  }
  function peek() private view returns (uint data) {
    require(last >= first);
    data = queue[first];
  }

  // Holds all reusable ncaab contest smart contracts
  // and the games areas that will be populated for ongoing contest group
  address[] public ncaabContracts1;
  Game[] public ncaabGames1;
  bytes32[] public ncaabGameIds1;
  Counters.Counter private activeContracts1;
  address[] public ncaabContracts2;
  Game[] public ncaabGames2;
  bytes32[] public ncaabGameIds2;
  Counters.Counter private activeContracts2;
  address[] public ncaabContracts3;
  Game[] public ncaabGames3;
  bytes32[] public ncaabGameIds3;
  Counters.Counter private activeContracts3;
  bool ongoingContracts1;
  bool ongoingContracts2;
  bool ongoingContracts3;
  uint public maxChildContracts;
  // Address of the Grand Fantasy managed wallet that will perform administrative actions for the manager
  address public administrator;

  bytes32 specId;

  constructor(address _link, address _oracle, bytes32 jobId) {
    // Set chainlink token address and The Rundown oracle address
    setChainlinkToken(_link);
    setChainlinkOracle(_oracle);
    specId = jobId;


    // Set the administrator to be the contract owner initially
    administrator = msg.sender;

    ongoingContracts1 = false;
    ongoingContracts2 = false;
    ongoingContracts3 = false;

    // multiple of 4 since 4 contracts are deployed at a time for each group
    maxChildContracts = 32;

    currentPerformanceId.increment();
  }

  function setMaxChildContracts(uint max) public {
    require(msg.sender == administrator);
    maxChildContracts = max;
  }

  // Returns a list of contracts that the player is entered in
  // All remaining spaces in array filled with 0x0
  function getOngoingContractsForPlayer(address player) public view returns(address[] memory) {
    // Nearly all of these slots are not going to be filled, but this is technically the max
    address[] memory ongoingContracts = new address[](maxChildContracts * 3);
    uint numberOfOngoing = 0;

    uint i;
    for(i = 0; i<ncaabContracts1.length; i++) {
      GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts1[i]);
      if(pickEm.getEnteredToday(player)) {
        ongoingContracts[numberOfOngoing] = ncaabContracts1[i];
        numberOfOngoing++;
      }
    }
    for(i = 0; i<ncaabContracts2.length; i++) {
      GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts2[i]);
      if(pickEm.getEnteredToday(player)) {
        ongoingContracts[numberOfOngoing] = ncaabContracts2[i];
        numberOfOngoing++;
      }
    }
    for(i = 0; i<ncaabContracts3.length; i++) {
      GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts3[i]);
      if(pickEm.getEnteredToday(player)) {
        ongoingContracts[numberOfOngoing] = ncaabContracts3[i];
        numberOfOngoing++;
      }
    }

    return ongoingContracts;
  }

  // Returns a list of contracts that owe a player wei
  // all remaining spaces in array filled with 0x0
  function getContractsThatOwePlayer(address player) public view returns(address[] memory) {
    // Nearly all of these slots are not going to be filled, but this is technically the max
    address[] memory contractsThatOwe = new address[](maxChildContracts * 3);
    uint numberThatOwe = 0;

    uint i;
    for(i = 0; i<ncaabContracts1.length; i++) {
      GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts1[i]);
      if(pickEm.getWinningsOwed(player) > 0) {
        contractsThatOwe[numberThatOwe] = ncaabContracts1[i];
        numberThatOwe++;
      }
    }
    for(i = 0; i<ncaabContracts2.length; i++) {
      GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts2[i]);
      if(pickEm.getWinningsOwed(player) > 0) {
        contractsThatOwe[numberThatOwe] = ncaabContracts2[i];
        numberThatOwe++;
      }
    }
    for(i = 0; i<ncaabContracts3.length; i++) {
      GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts3[i]);
      if(pickEm.getWinningsOwed(player) > 0) {
        contractsThatOwe[numberThatOwe] = ncaabContracts3[i];
        numberThatOwe++;
      }
    }

    return contractsThatOwe;
  }

  // Checks whether or not new contest contracts are needed
  function needsDeployment() public view returns(bool[] memory) {
    bool[] memory needsDeploy = new bool[](3);

    // Cap the number of child contracts at 32 until we know exactly how this scales
    if(ncaabContracts1.length < maxChildContracts) {
      GrandFantasyNFTPickEm group1 = GrandFantasyNFTPickEm(ncaabContracts1[activeContracts1.current()]);
      if(group1.getContestOpen() && (group1.getCurrentEntrants() >= group1.getMaxEntrants()) && (ncaabContracts1.length < activeContracts1.current() + 2)) {
        needsDeploy[0] = true;
      }
    }

    if(ncaabContracts2.length <maxChildContracts) {
      GrandFantasyNFTPickEm group2 = GrandFantasyNFTPickEm(ncaabContracts2[activeContracts2.current()]);
      if(group2.getContestOpen() && (group2.getCurrentEntrants() >= group2.getMaxEntrants()) && (ncaabContracts2.length < activeContracts2.current() + 2)) {
        needsDeploy[1] = true;
      }
    }

    if(ncaabContracts3.length < maxChildContracts) {
      GrandFantasyNFTPickEm group3 = GrandFantasyNFTPickEm(ncaabContracts3[activeContracts3.current()]);
      if(group3.getContestOpen() && (group3.getCurrentEntrants() >= group3.getMaxEntrants()) && (ncaabContracts3.length < activeContracts3.current() + 2)) {
        needsDeploy[2] = true;
      }
    }

    return needsDeploy;
  }

  function needsScaling() public view returns(bool[] memory) {
    bool[] memory shouldScale = new bool[](3);
    GrandFantasyNFTPickEm group1 = GrandFantasyNFTPickEm(ncaabContracts1[activeContracts1.current()]);
    if(group1.getContestOpen() && (group1.getCurrentEntrants() >= group1.getMaxEntrants()) && (ncaabContracts1.length >= activeContracts1.current() + 2)) {
      shouldScale[0] = true;
    }

    GrandFantasyNFTPickEm group2 = GrandFantasyNFTPickEm(ncaabContracts2[activeContracts2.current()]);
    if(group2.getContestOpen() && (group2.getCurrentEntrants() >= group2.getMaxEntrants()) && (ncaabContracts2.length >= activeContracts2.current() + 2)) {
      shouldScale[1] = true;
    }

    GrandFantasyNFTPickEm group3 = GrandFantasyNFTPickEm(ncaabContracts3[activeContracts3.current()]);
    if(group3.getContestOpen() && (group3.getCurrentEntrants() >= group3.getMaxEntrants()) && (ncaabContracts3.length >= activeContracts3.current() + 2)) {
      shouldScale[2] = true;
    }

    return shouldScale;
  }

  function scaleGroup(uint8 group) public {
    require(msg.sender == administrator);

    uint i;
    if(group == 1) {
      for(i = 0; i<4; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts1[i]);
        pickEm.addGames(ncaabGames1);
        pickEm.performUpkeep();
      }
    } else if(group == 2) {
      for(i = 0; i<4; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts2[i]);
        pickEm.addGames(ncaabGames2);
        pickEm.performUpkeep();
      }
    } else if(group == 3) {
      for(i = 0; i<4; i++) {
        activeContracts3.increment();
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts3[i]);
        pickEm.addGames(ncaabGames3);
        pickEm.performUpkeep();
      }
    }
  }


  function deployToGroup(address[] memory contractsToAdd, uint8 group) public {
    require(msg.sender == administrator);
    require(contractsToAdd.length == 4);

    if(group == 1) {
      uint i;
      for(i = 0; i<4; i++) {
        ncaabContracts1.push(contractsToAdd[i]);
        if(ncaabGames1.length > 0) {
          GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(contractsToAdd[i]);
          pickEm.addGames(ncaabGames1);
          pickEm.performUpkeep();
        }
      }
    } else if(group == 2) {
      uint i;
      for(i = 0; i<4; i++) {
        ncaabContracts2.push(contractsToAdd[i]);
        if(ncaabGames2.length > 0) {
          GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(contractsToAdd[i]);
          pickEm.addGames(ncaabGames2);
          pickEm.performUpkeep();
        }
      }
    } else if(group == 3) {
      uint i;
      for(i = 0; i<4; i++) {
        ncaabContracts3.push(contractsToAdd[i]);
        if(ncaabGames3.length > 0) {
          GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(contractsToAdd[i]);
          pickEm.addGames(ncaabGames3);
          pickEm.performUpkeep();
        }
      }
    }
  }

  function pullContractsForContests() public view returns(address[] memory) {
    uint totalContractAddresses = activeContracts1.current() + 1;
    totalContractAddresses = totalContractAddresses + activeContracts2.current() + 1;
    totalContractAddresses = totalContractAddresses + activeContracts3.current() + 1;

    address[] memory contracts = new address[](totalContractAddresses);
    uint i;
    for(i = 0; i<activeContracts1.current() + 1; i++) {
      contracts[i] = ncaabContracts1[i];
    }
    for(i = 0; i<activeContracts2.current() + 1; i++) {
      contracts[i + activeContracts1.current() + 1] = ncaabContracts2[i];
    }
    for(i = 0; i<activeContracts3.current() + 1; i++) {
      contracts[i + activeContracts1.current() + 1 + activeContracts2.current() + 1] = ncaabContracts3[i];
    }

    return contracts;
  }

  function addGames(Game[] memory newGames) public {
    require(msg.sender == administrator);
    require(newGames.length <= 16);
    // There must be contracts available to run the contests on
    require(ongoingContracts1 == false || ongoingContracts2 == false || ongoingContracts3 == false);
    uint i;

    // There are not currently contests running on the contracts group 1
    if(ongoingContracts1 == false) {
      activeContracts1.reset();

      // Add games to first four contracts
      uint lengthToAdd = ncaabContracts1.length >= 4 ? 4 : 0;
      for(i = 0; i<lengthToAdd; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts1[i]);
        pickEm.addGames(newGames);

        if(i != lengthToAdd - 1) {
          activeContracts1.increment();
        }
      }
      for(i = 0; i<newGames.length; i++) {
        ncaabGameIds1.push(newGames[i].rundownId);
        ncaabGames1.push(newGames[i]);
      }

      // There are now contests ongoing on the contracts group 1
      ongoingContracts1 = true;
      enqueue(1);
    } else if(ongoingContracts2 == false) {
      activeContracts2.reset();

      // Add games to first four contracts
      uint lengthToAdd = ncaabContracts2.length >= 4 ? 3 : 0;
      for(i = 0; i<lengthToAdd; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts2[i]);
        pickEm.addGames(newGames);

        if(i != lengthToAdd - 1) {
          activeContracts2.increment();
        }
      }
      for(i = 0; i<newGames.length; i++) {
        ncaabGameIds2.push(newGames[i].rundownId);
        ncaabGames2.push(newGames[i]);
      }

      ongoingContracts2 = true;
      enqueue(2);
    } else if(ongoingContracts3 == false) {
        activeContracts3.reset();

        // Add game to first four contracts
        uint lengthToAdd = ncaabContracts3.length >= 4 ? 3 : 0;
        for(i = 0; i<lengthToAdd; i++) {
          GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts3[i]);
          pickEm.addGames(newGames);

          if(i != lengthToAdd - 1) {
            activeContracts3.increment();
          }
        }
        for(i = 0; i<newGames.length; i++) {
          ncaabGameIds3.push(newGames[i].rundownId);
          ncaabGames3.push(newGames[i]);
        }

        // There are now contests ongoing on the contracts group 3
        ongoingContracts3 = true;
        enqueue(3);
    }
  }

  // Makes request to oracle to get results for the highest priority games
  // that have ended.
  // Param apiKey is a valid key for the Rundown API
  function getWinners() public {
    require(msg.sender == administrator);

    // Peek which contest group is up next for resolution
    uint contractsToResolve = peek();
    uint gamesLength = 0;

    // Grab the start time of the last game to check alongside the current timestamp
    // Also populate a list of game ids to resolve
    uint i;
    uint32 lastGameStartTime = 0;
    if(contractsToResolve == 1) {
      gamesLength = ncaabGameIds1.length;
      for(i = 0; i<ncaabGames1.length; i++) {
        if(ncaabGames1[i].startTime > lastGameStartTime) {
          lastGameStartTime = ncaabGames1[i].startTime;
        }
      }
    } else if(contractsToResolve == 2) {
      gamesLength = ncaabGameIds2.length;
      for(i = 0; i<ncaabGames2.length; i++) {
        if(ncaabGames2[i].startTime > lastGameStartTime) {
          lastGameStartTime = ncaabGames2[i].startTime;
        }
      }
    } else if (contractsToResolve == 3) {
      gamesLength = ncaabGameIds3.length;
      for(i = 0; i<ncaabGames3.length; i++) {
        if(ncaabGames3[i].startTime > lastGameStartTime) {
          lastGameStartTime = ncaabGames3[i].startTime;
        }
      }
    }


    // Only make the oracle request for the winners when the games are  over
    // Making the request before the games end will not be useful
    uint256 comparisonTimestamp = lastGameStartTime + 28800;
    if(block.timestamp > comparisonTimestamp) {
      uint256 payment = 0.1 * 10 ** 18;
      requestGameResults(lastGameStartTime, payment, contractsToResolve, gamesLength);
    }
  }

  // When called, takes scores received through oracle and distributes
  // to the correct child contract
  function distributeWinnersToContests() public {
    uint i;
    uint x;
    uint contractsToResolve = peek();

    // First, grab the games that have been received from the oracle
    // Assign winners to the existing games
    require(gamesFromOracle.length > 0);
    if(contractsToResolve == 1) {
      for(i = 0; i<gamesFromOracle.length; i++) {
        GameResolve memory game = abi.decode(gamesFromOracle[i], (GameResolve));
        for(x = 0; x<ncaabGames1.length; x++) {
          if(ncaabGames1[x].rundownId == game.gameId) {
            ncaabGames1[x].winner = game.homeScore > game.awayScore ? 1 : 2;
            break;
          }
        }
      }
    } else if(contractsToResolve == 2) {
      for(i = 0; i<gamesFromOracle.length; i++) {
        GameResolve memory game = abi.decode(gamesFromOracle[i], (GameResolve));
        for(x = 0; x<ncaabGames2.length; x++) {
          if(ncaabGames2[x].rundownId == game.gameId) {
            ncaabGames2[x].winner = game.homeScore > game.awayScore ? 1 : 2;
            break;
          }
        }
      }
    } else if(contractsToResolve == 3) {
      for(i = 0; i<gamesFromOracle.length; i++) {
        GameResolve memory game = abi.decode(gamesFromOracle[i], (GameResolve));
        for(x = 0; x<ncaabGames3.length; x++) {
          if(ncaabGames3[x].rundownId == game.gameId) {
            ncaabGames3[x].winner = game.homeScore > game.awayScore ? 1 : 2;
            break;
          }
        }
      }
    }

    // Next, make sure that we have the winner for every single
    // game
    if(contractsToResolve == 1) {
      for(i = 0; i<ncaabGames1.length; i++) {
        require(ncaabGames1[i].winner > 0);
      }
    } else if(contractsToResolve == 2) {
      for(i = 0; i<ncaabGames2.length; i++) {
        require(ncaabGames2[i].winner > 0);
      }
    } else {
      for(i = 0; i<ncaabGames3.length; i++) {
        require(ncaabGames3[i].winner > 0);
      }
    }

    // If we've made it here, we have all necessary winners to proceed
    // we can dequeue and resolve the contests
    contractsToResolve = dequeue();
    if(contractsToResolve == 1) {
      uint8[] memory finalGameWinners = new uint8[](ncaabGameIds1.length);
      for(x = 0; x<ncaabGames1.length; x++) {
        finalGameWinners[x] = ncaabGames1[x].winner;
      }

      for(i = 0; i<activeContracts1.current() + 1; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts1[i]);
        pickEm.receiveWinners(finalGameWinners);
      }

      ongoingContracts1 = false;
      delete ncaabGameIds1;
      delete ncaabGames1;
      delete gamesFromOracle;
    } else if(contractsToResolve == 2) {
      uint8[] memory finalGameWinners = new uint8[](ncaabGameIds2.length);
      for(x = 0; x<ncaabGames2.length; x++) {
        finalGameWinners[x] = ncaabGames2[x].winner;
      }

      for(i = 0; i<activeContracts2.current() + 1; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts2[i]);
        pickEm.receiveWinners(finalGameWinners);
      }

      ongoingContracts2 = false;
      delete ncaabGameIds2;
      delete ncaabGames2;
      delete gamesFromOracle;
    } else if(contractsToResolve == 3) {
      uint8[] memory finalGameWinners = new uint8[](ncaabGameIds3.length);
      for(x = 0; x<ncaabGames3.length; x++) {
        finalGameWinners[x] = ncaabGames3[x].winner;
      }

      for(i = 0; i<activeContracts3.current() + 1; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts3[i]);
        pickEm.receiveWinners(finalGameWinners);
      }

      ongoingContracts3 = false;
      delete ncaabGameIds3;
      delete ncaabGames3;
      delete gamesFromOracle;
    }
  }

  // This function is an emergency alternative to resolving contests
  // with chainlink oracles
  // If the oracle service is down or data is problematic, any contest can be
  // refunded
  function refundContest() public {
    require(msg.sender == administrator);

    uint contractsToRefund = dequeue();
    uint i;
    if(contractsToRefund == 1) {
      for(i = 0; i<activeContracts1.current() + 1; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts1[i]);
        pickEm.refundContest();
      }

      delete ncaabGameIds1;
      delete ncaabGames1;
      delete gamesFromOracle;
    } else if(contractsToRefund == 2) {
      for(i = 0; i<activeContracts2.current() + 1; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts2[i]);
        pickEm.refundContest();
      }

      delete ncaabGameIds2;
      delete ncaabGames2;
      delete gamesFromOracle;
    } else if(contractsToRefund == 3) {
      for(i = 0; i<activeContracts3.current() + 1; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts3[i]);
        pickEm.refundContest();
      }

      delete ncaabGameIds3;
      delete ncaabGames3;
      delete gamesFromOracle;
    }
  }
}
