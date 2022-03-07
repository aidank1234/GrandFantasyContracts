pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "./PickemContestManager.sol";

// Struct that represents a game for the PickEm
// Team1Name and Team2Name up to 32 characters
// startTime is unix timestamp
// winner will be set to 1 or 2 after the game concludes, depending on which team won
struct Game {
  bytes32 team1Name;
  bytes32 team2Name;
  uint32 startTime;
  uint16 id;
  uint8 winner;
  string sportsRadarId;
}

contract GrandFantasyNFTPickEm {
  using Counters for Counters.Counter;

  // Whether or not players can place picks, this will be set to false before game begin
  bool public contestOpen;

  // Address of the Grand Fantasy managed wallet that will perform administrative actions for the contest
  address public administrator;

  // Address of Grand Fantasy contest manager smart contract that handles deployment of contests
  address public managerAddress;

  // UNIX timestamp of what time the next PickEm competition will open for entries...0 for not scheduled
  uint32 public nextContestStartTime;

  // UNIX timestamp of the start time of the earliest game added to the contest
  uint32 public firstGameStartTime;

  // UNIX timestamp of the start time of the latest game added to the contest
  uint32 public lastGameStartTime;

  // Boolean indicating whether or not the winners for the games have been sent in
  bool public gameWinnersReceived;

  // Boolean indicating whether or not all past contests on this contract have been resolved
  bool public contestResolved;

  // The number of correct picks a user needs to be deemed a winner of the current contest
  uint8 public requirementToWin;

  // The number of total picks a user needs to submit to be entered in to a contest
  // This is calculated when adding games to the contest
  uint8 public totalPicksRequired;

  // In wei, the prize pool of the current contest
  // Prize pool goes up with each entry
  uint256 public prizePool;

  // Name of the contest for display in the client side UI
  bytes32 public contestName;

  // Entry fee, in wei, for the contest
  uint256 public weiEntryFee;

  // Counter to keep track of how many entrants there are in the current contest
  Counters.Counter private currentEntrants;

  // Maximum number of entrants for the contest
  uint32 public maxEntrants;

  // Counter to apply an id to user pick selections
  Counters.Counter private currentPickId;

  // Array of addresses that will hold the winners of the current contest
  // Array will be populated from the end of one contest until the next is set up
  address[] public winners;

  // Chainlink upkeep variables used in order to update contests automatically
  // and without direct administrator intervention
  uint public immutable interval;
  uint public lastTimeStamp;

  constructor(uint updateInterval) {
    // Set the administrator to be the contract owner initially
    administrator = msg.sender;

    // Increment the currentPickId so it starts at 1
    currentPickId.increment();

    // Make is so the admin is able to create a new contest by default
    contestResolved = true;

    // Set chainlink upkeep variables
    interval = updateInterval;
    lastTimeStamp = block.timestamp;
  }

  // Only executable by contract administrator
  modifier onlyAdmin {
    require(msg.sender == administrator);
    _;
  }

  // Determines whether or not upkeep is needed on the contract
  function checkUpkeep() external view returns (bool upkeepNeeded) {
    if((block.timestamp - lastTimeStamp) > interval) {
      // If there have been no games added or contest details have not been added, there is no upkeep to perform
      if(totalPicksRequired > 0 && requirementToWin > 0) {
        upkeepNeeded = true;
      } else {
        upkeepNeeded = false;
      }
    } else {
      upkeepNeeded = false;
    }
  }

  function performUpkeep() external onlyAdmin {
    lastTimeStamp = block.timestamp;

    // If the contest is closed for entries, but the next contest has been scheduled
    if(!contestOpen && nextContestStartTime > 0) {
      // Open the contest for entries if the current date is an hour or less before
      // the scheduled time to open entries
      if(block.timestamp > nextContestStartTime) {
        contestOpen = true;
        nextContestStartTime = 0;
        contestResolved = false;
      } else if(nextContestStartTime - block.timestamp <= 3600) {
        contestOpen = true;
        nextContestStartTime = 0;
        contestResolved = false;
      }
    }
    // If the contest is closed for entries and a contest is ongoing
    else if(!contestOpen && nextContestStartTime == 0 && gameWinnersReceived) {
      // Resolve contest and pay out winners if it has been at least 8 hours since the start
      // time of the latest game
      // This also requires knowing the outcome of the games
      if(block.timestamp > lastGameStartTime && block.timestamp - lastGameStartTime >= 28800) {
        markForPayout();
      }
    }
    // If entries for the contest are currently open
    else if(contestOpen) {
      // Close contest entries if upkeep is happening within an hour and a half of the
      // earliest game
      if(block.timestamp > firstGameStartTime) {
        contestOpen = false;
        if(currentEntrants.current() < 3) {
          refundContest();
        }
      } else if(firstGameStartTime - block.timestamp <= 5400) {
        contestOpen = false;
        if(currentEntrants.current() < 3) {
          refundContest();
        }
      }
    }
  }

  // Returns the number of current entrants into the contest
  function getCurrentEntrants() public view returns (uint) {
    return currentEntrants.current();
  }

  // Passes administration privleges to a new address
  function passAdministrationPrivleges(address newAdministrator) public onlyAdmin {
    administrator = newAdministrator;
  }

  // Set grand fantasy manager address
  function setManagerAddress(address manager) public onlyAdmin {
    managerAddress = manager;
  }

  // Function that sets the start time, number of picks required to win, and
  // maximum entrants of a new contest
  // Param startTime - unix timestamp for start time
  function setContestDetails(uint32 startTime) private {
    require(contestResolved);

    // Winners could still be populated from a previous contest, clear the array
    delete winners;

    nextContestStartTime = startTime;

    uint8 requirement = totalPicksRequired - (totalPicksRequired / 3);
    requirementToWin = requirement;
    maxEntrants = 20;
  }

  // Setter for metadata regarding this contest
  // Param name - name for the contest for display in UI
  // Param entryFee - entry fee, in wei, for the contest
  function setContestMetadata(bytes32 name, uint256 entryFee) public onlyAdmin {
    require(contestResolved);
    contestName = name;
    weiEntryFee = entryFee;
  }

  // Maps GameIds to game struct
  mapping (uint16 => Game) public games;

  // Returns an array of all games that have been added to the contest
  function getGames() public view returns(Game[] memory) {
    Game[] memory allGames = new Game[](totalPicksRequired);
    uint i;
    for(i = 0; i < totalPicksRequired; i++) {
      allGames[i] = games[uint16(i)];
    }
    return allGames;
  }

  // Struct that represents a single user pick for the PickEm
  // Pick is a value 1 to pick team1 or 2 to pick team2
  struct Pick {
    uint16 gameId;
    uint8 pick;
    uint24 pickId;
  }
  mapping (uint24 => Pick) public picks;

  // Struct that represents a player in a PickEm contest
  // playerAddress, weiOwed will be persistent accross contests
  struct Player {
    address playerAddress;
    uint24[] pickIds;
    uint256 weiOwed;
    bool enteredToday;
  }
  mapping (address => Player) public playerStructs;

  // Holds the players that have entered into the current contest
  address[] public playersToday;

  // Adds [games] for use in the PickEm contest. Winner value of these games will be set to 0.
  // Param newGames are the games to add to the games mapping
  function addGames(Game[] memory newGames) public onlyAdmin {
    require(contestResolved);

    totalPicksRequired = uint8(newGames.length);

    // Only the administrator can send in games and
    // will not send more than how many PickEm games are in a day. Likely ~10
    uint i;

    // Use max int for comparison
    uint256 firstStartTime = 2**256 - 1;
    uint32 lastStartTime;
    for (i = 0; i < newGames.length; i++) {
      // Record the start time of the earliest game and the start time of the
      // lastest game
      if(uint256(newGames[i].startTime) < firstStartTime) {
        firstStartTime = uint256(newGames[i].startTime);
      }
      if(newGames[i].startTime > lastStartTime) {
        lastStartTime = newGames[i].startTime;
      }

      games[newGames[i].id] = newGames[i];
    }

    // Save earliest and latest start time to storage
    firstGameStartTime = uint32(firstStartTime);
    lastGameStartTime = lastStartTime;

    // Open contest for entries 24 hours before games
    uint256 contestStartTime = firstStartTime - 86400;
    setContestDetails(uint32(contestStartTime));
  }

  // Function to make picks here
  function submitPicksForContest(uint8 playerPicks) public payable {
    // Require contest to be open to place picks
    require(contestOpen);

    // Require the entrants to not be over the max
    require(currentEntrants.current() < maxEntrants);

    // Require the value of the transaction to be over the wei entry fee
    require(msg.value == weiEntryFee);

    address player = msg.sender;
    // Only one entry allowed per player
    require(playerStructs[player].enteredToday == false);

    // This is a new player, initialize them in the struct
    if(playerStructs[player].playerAddress == address(0x0)) {
      Player memory newPlayer;
      newPlayer.playerAddress = player;
      playerStructs[player] = newPlayer;
    }
    playerStructs[player].pickIds.push(newPickId);

    uint i;
    for(i = 0; i<totalPicksRequired; i++) {
      uint8 playerPick = ((playerPicks>>i)%2)+1;
      // Picks must either be for team 1 or team 2, no other values
      require(playerPick == 1 || playerPick == 2);

      // Create data for each pick
      Pick memory newPick;
      newPick.gameId = uint16(i);
      newPick.pick = playerPick;
      uint24 newPickId = uint24(currentPickId.current());
      newPick.pickId = newPickId;

      // Reflect the new pick in the picks struct
      picks[newPickId] = newPick;

      // Increment the counter so each pick has a unique id
      currentPickId.increment();
    }

    // Player has been successfully entered in the current contest
    playerStructs[player].enteredToday = true;
    playersToday.push(player);
    currentEntrants.increment();
    prizePool = prizePool + weiEntryFee;
  }

  function getPicksForPlayer(address player) public view returns(Pick[] memory) {
    uint24[] memory playerPickIds = playerStructs[player].pickIds;
    Pick[] memory playerPicks = new Pick[](playerPickIds.length);
    uint i;
    for(i = 0; i<playerPickIds.length; i++) {
      playerPicks[i] = picks[playerPickIds[i]];
    }
    return playerPicks;
  }

  function receiveWinners(uint8[] memory finalGames) public {
    require(msg.sender == managerAddress);

    // If the contest has been refunded, we don't want to do any of this
    if(contestResolved == false) {
      uint i;
      // Update all game structs to contain the winners using administrator data
      for(i = 0; i < finalGames.length; i++) {
        games[uint16(i)].winner = finalGames[i];
      }

      gameWinnersReceived = true;
    }
  }

  function markForPayout() private {
    uint i;
    uint8 correctPicks;
    uint x;
    ContestPerformance[] memory contestPerformances = new ContestPerformance[](currentEntrants.current());

    // At this point, the winner portion of the games structs are set
    // Go through all players today
    for(i = 0; i < playersToday.length; i++) {
      Player memory player = playerStructs[playersToday[i]];

      correctPicks = 0;

      // For each player today, go through each of their picks
      // Number of pickIds is bounded by the number of games added for the contest, usually ~10
      for(x = 0; x < player.pickIds.length; x++) {
        Pick memory pick = picks[player.pickIds[x]];
        Game memory game = games[pick.gameId];

        // If the pick aligns with the winner, it was correct
        if(game.winner == pick.pick) {
          correctPicks++;
        }
      }

      // Clear the pick ids, they will never be needed again but we may need this field again
      delete player.pickIds;

      // Remove entered today so that players will be able to enter the next contest
      player.enteredToday = false;

      // If the player has enough correct picks, they are officially a winner
      ContestPerformance memory newPerformance;
      if(correctPicks >= requirementToWin) {
        newPerformance.contestName = contestName;
        newPerformance.entryFee = weiEntryFee;
        newPerformance.payout = 0;
        newPerformance.status = 2;
        newPerformance.picksCorrect = correctPicks;
        newPerformance.totalPicks = totalPicksRequired;
        newPerformance.player = playersToday[i];
        contestPerformances[i] = newPerformance;

        winners.push(player.playerAddress);
      } else {
        newPerformance.contestName = contestName;
        newPerformance.entryFee = weiEntryFee;
        newPerformance.payout = 0;
        newPerformance.status = 1;
        newPerformance.picksCorrect = correctPicks;
        newPerformance.totalPicks = totalPicksRequired;
        newPerformance.player = playersToday[i];
        contestPerformances[i] = newPerformance;
      }

      // Set memory variable back to storage so that changes persist
      playerStructs[playersToday[i]] = player;
    }

    // Calculate payout by dividing prize pool by # of winners
    // Take a 10% rake here
    uint256 payout;
    if(winners.length > 0) {
      payout = (prizePool / 10 * 9) / winners.length;
    } else {
      playerStructs[administrator].weiOwed = playerStructs[administrator].weiOwed + prizePool;
    }

    bool takeRake = false;

    for(i = 0; i < winners.length; i++) {
      if(payout < weiEntryFee) {
        playerStructs[winners[i]].weiOwed = playerStructs[winners[i]].weiOwed + weiEntryFee;
      } else {
        playerStructs[winners[i]].weiOwed = playerStructs[winners[i]].weiOwed + payout;
        takeRake = true;
      }
    }

    for(i = 0; i<contestPerformances.length; i++) {
      if(payout < weiEntryFee &&  (contestPerformances[i].picksCorrect >= requirementToWin)) {
        contestPerformances[i].payout = contestPerformances[i].payout + weiEntryFee;
      } else if(contestPerformances[i].picksCorrect >= requirementToWin) {
        contestPerformances[i].payout = contestPerformances[i].payout + payout;
      }
    }

    GrandFantasyManager manager = GrandFantasyManager(managerAddress);
    manager.receivePerformance(contestPerformances);

    if(takeRake) {
      // The administrator wallet is able to withdraw the rake
      uint256 rake = prizePool / 10;
      playerStructs[administrator].weiOwed = playerStructs[administrator].weiOwed + rake;
    }

    // Delete all games from the games mapping
    for(i = 0; i < totalPicksRequired; i++) {
      delete games[uint16(i)];
    }

    // Do some housekeeping to get ready for any future contests
    requirementToWin = 0;
    totalPicksRequired = 0;
    prizePool = 0;
    maxEntrants = 0;
    firstGameStartTime = 0;
    lastGameStartTime = 0;
    gameWinnersReceived = false;
    contestResolved = true;

    delete playersToday;
    currentEntrants.reset();
  }

  //Function to refund contest
  function refundContest() private {
    uint i;
    ContestPerformance[] memory refundPerformances = new ContestPerformance[](playersToday.length);
    for(i = 0; i < playersToday.length; i++) {
      Player memory player = playerStructs[playersToday[i]];

      // Clear the pick ids, they will never be needed again but we may need this field again
      delete player.pickIds;

      // Remove entered today so that players will be able to enter the next contest
      player.enteredToday = false;

      // Refund the entry fee to the contest
      player.weiOwed = player.weiOwed + weiEntryFee;

      // Set memory variable back to storage so that changes persist
      playerStructs[playersToday[i]] = player;

      ContestPerformance memory newPerformance;
      newPerformance.contestName = contestName;
      newPerformance.entryFee = weiEntryFee;
      newPerformance.payout = weiEntryFee;
      newPerformance.status = 0;
      newPerformance.picksCorrect = 0;
      newPerformance.totalPicks = 0;
      newPerformance.player = playersToday[i];
      refundPerformances[i] = newPerformance;
    }

    GrandFantasyManager manager = GrandFantasyManager(managerAddress);
    manager.receivePerformance(refundPerformances);

    // Delete all games from the games mapping
    for(i = 0; i < totalPicksRequired; i++) {
      delete games[uint16(i)];
    }

    // Do some housekeeping to get ready for any future contests
    requirementToWin = 0;
    totalPicksRequired = 0;
    prizePool = 0;
    maxEntrants = 0;
    firstGameStartTime = 0;
    lastGameStartTime = 0;
    gameWinnersReceived = false;
    contestResolved = true;

    delete playersToday;
    currentEntrants.reset();
  }

  // If a wallet is owed wei from contests, they can call upon this function
  // to withdraw this money
  function withdrawWinnings() public {
    if(playerStructs[msg.sender].weiOwed > 0) {
      (bool sent, bytes memory data) = msg.sender.call{value: playerStructs[msg.sender].weiOwed}("");
      require(sent, "Failed to send matic");
      playerStructs[msg.sender].weiOwed = 0;
    }
  }

  // Getter function for the client API to check how much wei the user is owed,
  // prior to creating a withdraw transaction
  function getWinningsOwed() public view returns(uint256) {
    return playerStructs[msg.sender].weiOwed;
  }
}
