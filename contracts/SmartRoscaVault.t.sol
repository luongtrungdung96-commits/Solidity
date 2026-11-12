// SPDX-License-Identifier: MIT
pragma solidity =0.8.18;

contract SmartRoscaVault {
    // ============ 1. IMMUTABLES ============
    uint256 public immutable REQUIRED_AMOUNT;
    uint256 public immutable MAX_PLAYERS;
    uint256 public immutable ROUND_PERIOD;

    // ============ 2. STATE MACHINE ============
    enum PoolState { Waiting, Active, Completed, Cancelled }

    // ============ 3. STATE VARIABLES ============
    uint256 public currentRound = 1;
    uint256 public joinDeadline;
    uint256 public roundDeadline;
    PoolState public currentState;
    uint256 public roundPot;

    // ============ 4. PLAYER RECORD ============
    /// @dev Giữ struct để mở rộng sau này (creditScore, kycVerified...).
    struct Player {
        bool hasJoined;
    }

    // ============ 5. STORAGE ============
    mapping(address => Player) public players;
    mapping(uint256 => mapping(address => bool)) public deposits;
    mapping(address => uint256) public claimable;
    address[] public playerList;

    // ============ 6. EVENTS ============
    event VaultDeployed(address indexed deployer, uint256 requiredAmount, uint256 maxPlayers);
    event PlayerJoined(address indexed player, uint256 slot);
    event PoolActivated();
    event Deposited(address indexed player, uint256 indexed round, uint256 amount);
    event WinnerSelected(address indexed winner, uint256 indexed round, uint256 pot);
    event Claimed(address indexed player, uint256 amount);
    event RoundAdvanced(uint256 indexed newRound);
    event PoolCompleted();
    event PoolCancelled(string reason);

    // ============ 7. CONSTRUCTOR ============
    constructor(
        uint256 _requiredAmount,
        uint256 _maxPlayers,
        uint256 _joinPeriod,
        uint256 _roundPeriod
    ) {
        require(_maxPlayers >= 2 && _maxPlayers <= 20, "Invalid max players");
        require(_requiredAmount > 0, "Amount = 0");
        require(_joinPeriod > 0 && _roundPeriod > 0, "Period = 0");

        REQUIRED_AMOUNT = _requiredAmount;
        MAX_PLAYERS = _maxPlayers;
        ROUND_PERIOD = _roundPeriod;
        joinDeadline = block.timestamp + _joinPeriod;

        emit VaultDeployed(msg.sender, _requiredAmount, _maxPlayers);
    }

    // ============ 8. MODIFIERS ============
    modifier onlyActive() {
        require(currentState == PoolState.Active, "Pool not active");
        _;
    }

    modifier onlyPlayer() {
        require(players[msg.sender].hasJoined, "Not a player");
        _;
    }

    // ============ 9. EXTERNAL FUNCTIONS ============

    function join() external {
        require(currentState == PoolState.Waiting, "Pool not accepting joins");
        require(!players[msg.sender].hasJoined, "Already joined");
        require(playerList.length < MAX_PLAYERS, "Pool is full");
        require(block.timestamp <= joinDeadline, "Join deadline passed");

        players[msg.sender].hasJoined = true;
        playerList.push(msg.sender);
        emit PlayerJoined(msg.sender, playerList.length - 1);

        if (playerList.length == MAX_PLAYERS) {
            currentState = PoolState.Active;
            roundDeadline = block.timestamp + ROUND_PERIOD;
            emit PoolActivated();
        }
    }

    function deposit() external payable onlyActive onlyPlayer {
        require(!deposits[currentRound][msg.sender], "Already deposited this round");
        require(msg.value == REQUIRED_AMOUNT, "Wrong amount");
        require(block.timestamp <= roundDeadline, "Round deadline passed");

        deposits[currentRound][msg.sender] = true;
        roundPot += msg.value;
        emit Deposited(msg.sender, currentRound, msg.value);
    }

    /// @notice Settle round: chọn winner, ghi sổ claimable, advance round.
    /// Pull pattern: KHÔNG external call trong hàm này → không reentrancy.
    function settleRound() external onlyActive {
        require(_allDeposited(currentRound), "Not all deposited");

        address winner = playerList[currentRound - 1];
        uint256 amount = roundPot;
        roundPot = 0;
        claimable[winner] += amount;

        emit WinnerSelected(winner, currentRound, amount);
        _advanceRound();
    }

    /// @notice Ai có claimable > 0 rút về ví. Áp dụng CEI.
    function claim() external {
        uint256 amount = claimable[msg.sender];
        require(amount > 0, "Nothing to claim");
        claimable[msg.sender] = 0;

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "Transfer failed");

        emit Claimed(msg.sender, amount);
    }

    /// @notice Refund vòng hiện tại khi có người không nạp sau deadline.
    /// Chỉ ngăn KHOÁ tiền — không ngăn MẤT tiền các vòng trước.
    function abortRound() external onlyActive {
        require(block.timestamp > roundDeadline, "Round still open");
        require(!_allDeposited(currentRound), "Round complete");

        currentState = PoolState.Cancelled;

        for (uint256 i = 0; i < playerList.length; i++) {
            address p = playerList[i];
            if (deposits[currentRound][p]) {
                claimable[p] += REQUIRED_AMOUNT;
            }
        }
        roundPot = 0;
        emit PoolCancelled("Round timeout");
    }

    function cancel() external {
        require(currentState == PoolState.Waiting, "Can only cancel in Waiting");
        require(block.timestamp > joinDeadline, "Join deadline not passed");
        require(playerList.length < MAX_PLAYERS, "Pool is full");

        currentState = PoolState.Cancelled;
        emit PoolCancelled("Not enough players after deadline");
    }

    // ============ 10. INTERNAL HELPERS ============

    function _advanceRound() internal {
        if (currentRound >= MAX_PLAYERS) {
            currentState = PoolState.Completed;
            emit PoolCompleted();
        } else {
            currentRound += 1;
            roundDeadline = block.timestamp + ROUND_PERIOD;
            emit RoundAdvanced(currentRound);
        }
    }

    function _allDeposited(uint256 round) internal view returns (bool) {
        for (uint256 i = 0; i < playerList.length; i++) {
            if (!deposits[round][playerList[i]]) return false;
        }
        return true;
    }

    // ============ 11. VIEW FUNCTIONS ============

    function getPlayers() external view returns (address[] memory) {
        return playerList;
    }

    function getPlayerCount() external view returns (uint256) {
        return playerList.length;
    }

    function isRoundComplete(uint256 round) external view returns (bool) {
        return _allDeposited(round);
    }

    function getRoundStatus() external view returns (
        uint256 round,
        uint256 pot,
        uint256 deadline,
        bool readyToSettle
    ) {
        bool ready = (currentState == PoolState.Active) && _allDeposited(currentRound);
        return (currentRound, roundPot, roundDeadline, ready);
    }
}