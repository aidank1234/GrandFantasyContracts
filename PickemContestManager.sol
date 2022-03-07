pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "./ReusablePickemContest.sol";

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

contract GrandFantasyManager {
  using Counters for Counters.Counter;

  mapping (uint => ContestPerformance) public performances;
  mapping (address => uint[]) public playerPerformances;
  Counters.Counter private currentPerformanceId;

  // Only executable by contract administrator
  modifier onlyAdmin {
    require(msg.sender == administrator);
    _;
  }

  function receivePerformance(ContestPerformance[] memory newPerformances) public {
    address sender = msg.sender;
    bool senderValid = false;

    uint i;
    for(i = 0; i<ncaabContracts1.length; i++) {
      if(ncaabContracts1[i] == sender) {
        senderValid = true;
      }
    }
    for(i = 0; i<ncaabContracts2.length; i++) {
      if(ncaabContracts2[i] == sender) {
        senderValid = true;
      }
    }
    for(i = 0; i<ncaabContracts3.length; i++) {
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

  // Holds all reusable ncaab contest smart contracts
  address[] public ncaabContracts1;
  string[] public ncaabGameIds1;
  address[] public ncaabContracts2;
  string[] public ncaabGameIds2;
  address[] public ncaabContracts3;
  string[] public ncaabGameIds3;
  bool ongoingContracts1;
  bool ongoingContracts2;
  bool ongoingContracts3;
  // Address of the Grand Fantasy managed wallet that will perform administrative actions for the manager
  address public administrator;

  constructor() {
    // Set the administrator to be the contract owner initially
    administrator = msg.sender;

    ongoingContracts1 = false;
    ongoingContracts2 = false;
    ongoingContracts3 = false;

    currentPerformanceId.increment();
  }

  function addToGroup1(address contractToAdd) public onlyAdmin {
    ncaabContracts1.push(contractToAdd);
  }

  function addToGroup2(address contractToAdd) public onlyAdmin {
    ncaabContracts2.push(contractToAdd);
  }

  function addToGroup3(address contractToAdd) public onlyAdmin {
    ncaabContracts3.push(contractToAdd);
  }

  function pullContractsForContests() public view returns(address[] memory) {
    uint totalContractAddresses = ncaabContracts1.length;
    totalContractAddresses = totalContractAddresses + ncaabContracts2.length;
    totalContractAddresses = totalContractAddresses + ncaabContracts3.length;

    address[] memory contracts = new address[](totalContractAddresses);
    uint i;
    for(i = 0; i<ncaabContracts1.length; i++) {
      contracts[i] = ncaabContracts1[i];
    }
    for(i = 0; i<ncaabContracts2.length; i++) {
      contracts[i + ncaabContracts1.length] = ncaabContracts2[i];
    }
    for(i = 0; i<ncaabContracts3.length; i++) {
      contracts[i + ncaabContracts1.length + ncaabContracts2.length] = ncaabContracts3[i];
    }

    return contracts;
  }

  function addGames(Game[] memory newGames) public onlyAdmin {
    // There must be contracts available to run the contests on
    require(ongoingContracts1 == false || ongoingContracts2 == false || ongoingContracts3 == false);
    uint i;

    // There are not currently contests running on the contracts group 1
    if(ongoingContracts1 == false) {

      // Add games to all contracts
      for(i = 0; i<ncaabContracts1.length; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts1[i]);
        pickEm.addGames(newGames);
      }
      for(i = 0; i<newGames.length; i++) {
        ncaabGameIds1.push(newGames[i].sportsRadarId);
      }

      // There are now contests ongoing on the contracts group 1
      ongoingContracts1 = true;
      enqueue(1);
    } else if(ongoingContracts2 == false) {

      // Add game to all contracts
      for(i = 0; i<ncaabContracts2.length; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts2[i]);
        pickEm.addGames(newGames);
      }
      for(i = 0; i<newGames.length; i++) {
        ncaabGameIds2.push(newGames[i].sportsRadarId);
      }

      ongoingContracts2 = true;
      enqueue(2);
    } else if(ongoingContracts3 == false) {
      // Add game to all contracts
      for(i = 0; i<ncaabContracts3.length; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts3[i]);
        pickEm.addGames(newGames);
      }
      for(i = 0; i<newGames.length; i++) {
        ncaabGameIds3.push(newGames[i].sportsRadarId);
      }

      // There are now contests ongoing on the contracts group 3
      ongoingContracts3 = true;
      enqueue(3);
    }
  }

  function hashCompareWithLengthCheck(string memory a, string memory b) private returns (bool) {
    if(bytes(a).length != bytes(b).length) {
      return false;
    } else {
      return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
  }

  function receiveWinners(Game[] memory finalGames) public onlyAdmin {
    uint contractsToResolve = dequeue();
    uint i;
    uint x;
    if(contractsToResolve == 1) {
      uint8[] memory finalGameWinners = new uint8[](ncaabGameIds1.length);
      for(i = 0; i<ncaabGameIds1.length; i++) {
        bool shouldBreak = false;
        for(x = 0; x<finalGames.length; x++) {
          if(hashCompareWithLengthCheck(ncaabGameIds1[i], finalGames[x].sportsRadarId)) {
            finalGameWinners[i] = finalGames[x].winner;
            shouldBreak = true;
          }
          if(shouldBreak) {
            break;
          }
        }
      }

      for(i = 0; i<ncaabContracts1.length; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts1[i]);
        pickEm.receiveWinners(finalGameWinners);
      }

      ongoingContracts1 = false;
      delete ncaabGameIds1;
    } else if(contractsToResolve == 2) {
      uint8[] memory finalGameWinners = new uint8[](ncaabGameIds2.length);
      for(i = 0; i<ncaabGameIds2.length; i++) {
        bool shouldBreak = false;
        for(x = 0; x<finalGames.length; x++) {
          if(hashCompareWithLengthCheck(ncaabGameIds2[i], finalGames[x].sportsRadarId)) {
            finalGameWinners[i] = finalGames[x].winner;
            shouldBreak = true;
          }
          if(shouldBreak) {
            break;
          }
        }
      }

      for(i = 0; i<ncaabContracts2.length; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts2[i]);
        pickEm.receiveWinners(finalGameWinners);
      }

      ongoingContracts2 = false;
      delete ncaabGameIds2;
    } else if(contractsToResolve == 3) {
      uint8[] memory finalGameWinners = new uint8[](ncaabGameIds3.length);
      for(i = 0; i<ncaabGameIds3.length; i++) {
        bool shouldBreak = false;
        for(x = 0; x<finalGames.length; x++) {
          if(hashCompareWithLengthCheck(ncaabGameIds3[i], finalGames[x].sportsRadarId)) {
            finalGameWinners[i] = finalGames[x].winner;
            shouldBreak = true;
          }
          if(shouldBreak) {
            break;
          }
        }
      }

      for(i = 0; i<ncaabContracts3.length; i++) {
        GrandFantasyNFTPickEm pickEm = GrandFantasyNFTPickEm(ncaabContracts3[i]);
        pickEm.receiveWinners(finalGameWinners);
      }

      ongoingContracts3 = false;
      delete ncaabGameIds3;
    }
  }
}
