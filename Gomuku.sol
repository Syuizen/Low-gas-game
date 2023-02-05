// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/*
* @dev a Gomoku game contract with standard board size = 15*15 = 225
* The development of this contract is for self-educating solidity
* This script aims to create low-gas Gomoku game instance
*
* @rule the first player who has 5 stones on a row/column/diagonal line wins
*       tie-breaker: if there is no winner announced yet, and the board is full filled with stones
*           then player_white wins (compensation for not being the game starter)
*/

contract GomokuGame {

    /*
    * @dev declare storage variables
    */
    address immutable player_white; 
    address immutable player_black; // black starts first
    uint32 immutable turnTimeLimit; // time limit for a single turn
    uint32 immutable revokeWaitTimeLimit; // time limit for waiting the opponent player approves a revoke
    uint32 immutable requestRevokeTimeLimit; // time limit for launching a revoke request

    struct GameEnv { // 32 bytes
        address revokeRequester; // 20 bytes
        uint32 lastMoveTime; // 4 bytes
        uint32 requestRevokeTime; // 4 bytes
        uint8 gameStatus; // 1 byte
        uint8 stoneNum; // 1 byte (max 225 stones < 255 = MAX_UINT8)
        bool blackWins; // 1 byte
        bool blackPlayerTurn; // 1 byte
    }

    /*
    * @dev a board consists of 2 uint256-equivalent status: 
    * 1 for black stones and 1 for white stones
    * Now, think 16*15 as a matrix:
    * top-right 15*15 is essentially the board
    * ---------------------------
    * |                    | 0  |
    * |                    | 0  |
    * |       BOARD        | 0  |
    * |      15 * 15       | 0  |
    * |                    | 0  |
    * ---------------------------
    * | LastMove 8| UsedRevoke 8|
    * ---------------------------
    * if last move is row i and columns j, then
    *  > last move rows (LMR) = i
    *  > last move cols (LMC) = j
    */
    struct Board { // 64 bytes
        uint16[16] black; // 30 bytes
        //uint8 blackLastMove; // 1 byte
        //uint8 blackUsedRevokeNum; // 1 byte

        uint16[16] white;
        //uint8 whiteLastMove; // 1 byte
        //uint8 whiteUsedRevokeNum; // 1 byte
    }

    Board board;
    GameEnv env;

    /*
    * @dev events
    */
    event GameStart(address indexed player_black, address indexed player_white);
    event ThisIsYourTurn(address indexed _address);
    event RequestRevokingLastMove(address indexed _rasier);
    event RevokedLastMove(address indexed _rasier);
    event GameEnd(address indexed _winner, address indexed _loser);

    function _getPos(uint16[16] storage stone_board, uint8 _row, uint8 _col) internal view returns(uint16) {
        require(_row < 15 && _col < 15, "Cannot locate a pos out of the board 15*15");
        return stone_board[_row] & uint16(1 << _col);
    }

    function getPos(uint8 _row, uint8 _col) external view returns(string memory) {
        if (_getPos(board.black, _row, _col) == 1){
            return "Black";
        }
        if (_getPos(board.white, _row, _col) == 1){
            return "White";
        }
        return "Empty";
    }

    constructor (uint32 _turnTimeLimit,
                uint32 _revokeWaitTimeLimit,
                uint32 _requestRevokeTimeLimit,
                address _player_black,
                address _player_white
    ) {
        turnTimeLimit = _turnTimeLimit;
        revokeWaitTimeLimit = _revokeWaitTimeLimit;
        requestRevokeTimeLimit = _requestRevokeTimeLimit;
        player_black = _player_black;
        player_white = _player_white;
    }
        

    /*
    * @dev game starter
    */
    function startGame() public {
        require(env.gameStatus==0, 
        "Cannot restart a game.");
        env.blackPlayerTurn = true;
        env.lastMoveTime = uint32(block.timestamp);
        env.gameStatus = 1;
        emit GameStart(player_black, player_white);
    }

    /*
    * @dev switch players
    */
    function _switchPlayer() internal {
        env.blackPlayerTurn = !env.blackPlayerTurn;
    }

    /*
    * @dev check role of the msg.sender 
    */
    function whoIAm() external view returns(string memory) {
        if (msg.sender == player_black) {
            return "Player: BLACK";
        }
        if (msg.sender == player_white) {
                return "Player: WHITE";
        }
        return "Audience";
    }

    /*
    * @dev get the current player
    */
    function whoPlaysNow() public view returns(address) {
        if (env.blackPlayerTurn) {
            return player_black;
        } else {
            return player_white;
        }
    }

    /*
    * @dev check the remaining time
    */
    function remainingTime() external view returns(uint32) {
        return (turnTimeLimit + env.lastMoveTime - uint32(block.timestamp));
    }

    modifier activeGame() {
        require(env.gameStatus==1,
        "Game is not active.");
        _;
    }

    modifier onlyTurnPlayer() {
        require(msg.sender == whoPlaysNow(),
        "This is not your turn, stay tune.");
        _;
    }

    modifier eligibleMove(uint8 _row, uint8 _col) {
        require(block.timestamp <= env.lastMoveTime + turnTimeLimit, "Turn is timed-out. Please call endGame().");
        require(_row < 15 && _col < 15, "Cannot move out of the board 15*15");
        require(_getPos(board.black, _row, _col) == 0 && _getPos(board.white, _row, _col) == 0,
        "This place has already been occupied.");
        _;
    }

    /*
    * @dev end game if turn is timed-out.
    */
    function endGame() external activeGame {
        require(block.timestamp > env.lastMoveTime + turnTimeLimit,
        "This turn is still active!");            
        
        _EndGame(env.blackPlayerTurn? player_white : player_black);
    }

    /*
    * @dev make a move on the board
    * the function can be called by turn player
    */
    function MakeMove(uint8 _row, uint8 _col) external activeGame onlyTurnPlayer eligibleMove(_row, _col) {
        // move
        _move(_row, _col, env.blackPlayerTurn? board.black : board.white);
        _CheckWinner(_row, _col, env.blackPlayerTurn? board.black : board.white);
        env.stoneNum ++;
        _switchPlayer();
    } 
    
    /*
    * @dev make a move without checker (use after checking eligibleMove)
    */
    function _move(uint8 _row, uint8 _col, uint16[16] storage stone_board) internal {
        stone_board[_row] |= uint16(1 << _col);
        env.lastMoveTime = uint32(block.timestamp);
    }

    /*
    * @dev end the game (use with caution)
    */
    function _EndGame(address _winner) internal {
        // change status of board
        env.gameStatus = 2;
        if (_winner == player_black) {
            env.blackWins = true;
            emit GameEnd(player_black, player_white);
        } else {
            env.blackWins = false;
            emit GameEnd(player_white, player_black);
        }
    }

    /*
    * @dev decide if the current board has been won
    *      only check the winning pattern involves last move
    */
    function _CheckWinner(uint8 _row, uint8 _col, uint16[16] storage stone_board) internal {
        // check row
        uint8 stone_cont = 1;
        
        // look left
        if (_col > 0){
            for (uint8 c=_col-1; c >= 0; c --){
                if ( _getPos(stone_board, _row, c) == 1 ) {
                    stone_cont ++;
                } else {
                    break;
                }
            }
        }
        
        // look right
        for (uint8 c=_col+1; c < 15; c ++){
            if ( _getPos(stone_board, _row, c) == 1 ) {
                stone_cont ++;
            } else {
                break;
            }
        }
        
        if (stone_cont >= 5) {
            _EndGame(whoPlaysNow());
        }
        
        // check column
        stone_cont = 1;
        // look above
        for (uint8 r=_row+1; r < 15; r ++){
            if (_getPos(stone_board, r, _col) == 1){
                stone_cont ++;
            } else {
                break;
            }
        }
        // look downwards
        if (_row > 0){
            for (uint8 r=_row-1; r >= 0; r --){
                if (_getPos(stone_board, r, _col) == 1){
                    stone_cont ++;
                } else {
                    break;
                }
            }
        }
        if (stone_cont >= 5) {
            _EndGame(whoPlaysNow());
        }

        // check diagonal (top left -> bottom right)
        stone_cont = 1;
        uint8 max_up = _row > _col ? _col : _row;
        uint8 max_lower = _row > _col ? (14-_row) : (14-_col);
        // go to top left
        for (uint8 d=1; d < max_up; d++){
            if (_getPos(stone_board, _row-d, _col-d) == 1) {
                stone_cont ++;
            } else {
                break;
            }
        }
        // go to bottom right
        for (uint8 d=1; d < max_lower; d++) {
            if (_getPos(stone_board, _row+d, _col+d)==1){
                stone_cont ++;
            } else {
                break;
            }
        }
        if (stone_cont >= 5) {
            _EndGame(whoPlaysNow());
        }

        // check diagonal (top right -> bottom left)
        stone_cont = 1;
        max_up = (14-_row) > _col ? _col : (14-_row);
        max_lower = _row > (14-_col) ? (14-_col) : _row;
        // go to top right
        for (uint8 d=1; d < max_up; d++){
            if (_getPos(stone_board, _row+d, _col-d) == 1) {
                stone_cont ++;
            } else {
                break;
            }
        }
        // go to bottom left
        for (uint8 d=1; d < max_lower; d++) {
            if (_getPos(stone_board, _row-d, _col+d)==1){
                stone_cont ++;
            } else {
                break;
            }
        }
        if (stone_cont >= 5) {
            _EndGame(whoPlaysNow());
        }

        // if tie at a fulfilled board, white player wins
        if (env.stoneNum == 225) {
            _EndGame(player_white);
        }
        
    }

    /*
    * @dev check winner
    */
    function winner() external view returns(address){
        require(env.gameStatus==2,
        "The winner has not been annouced yet!");
        
        return env.blackWins? player_black : player_white;
    }

}
