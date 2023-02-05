// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Gomoku.sol";

contract Platform {

    address player_black;
    address player_white;

    GomokuGame gomokuGame;

    mapping(address=>address) gamerToGame;

    /*
    * @dev join the game
    */
    function join(bool choose_black) external {
        require(player_black == address(0) || player_white == address(0),
        "this game is fulfilled");

        if (choose_black) {
            require(player_black == address(0),
            "Oops, black stone player has been occupied.");
            require(player_white != msg.sender,
            "You cannot compete with yourself.");

            player_black = msg.sender;
            
        } else {
            require(player_white == address(0),
            "Oops, white stone player has been occupied.");
            require(player_black != msg.sender,
            "You cannot compete with yourself.");
            
            player_white = msg.sender;
             
        }
        
    }

    modifier playerReady(){
        require(player_black != address(0) && player_white != address(0),
        "Two players are needed before starting the game"
        );
        _;
    }

    modifier onlyStartPlayer(){
        require(msg.sender == player_black,
        "Only player black can start the game as they are the first to play.");
        _;
    }

    function launchGomoku() external playerReady onlyStartPlayer {
        gomokuGame = new GomokuGame(180, 60, 1, player_black, player_white);
        gomokuGame.startGame();
        gamerToGame[player_black] = address(gomokuGame);
        gamerToGame[player_white] = address(gomokuGame);
    }

    function whereIsMyGame() external view returns(address) {
        require(gamerToGame[msg.sender] != address(0),
        "You don't have an active game yet."
        );
        return gamerToGame[msg.sender];
    }

    uint8 public j = 1;
    
    function stupid() public {

        for (uint8 i=1; i<0; i++){
            j ++;
        }
    }
}
