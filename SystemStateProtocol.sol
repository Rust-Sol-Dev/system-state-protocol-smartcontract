// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./PLSTokenPriceFeed.sol";
import "./StateToken.sol";

contract System_State_Protocol is Ownable(msg.sender) {
    PLSTokenPriceFeed private priceFeed;
    StateToken private stateToken;
    address private AdminAddress;
    address private BackendOperationAddress;
    address private OracleWallet;
    using SafeMath for uint256;
    uint256 public ID = 1;
    uint256 private totalPSDshare;
    uint256 private totalPSTshare;
    uint256 private ActualtotalPSDshare;
    uint256 private ActualtotalPSTshare;
    uint256 public constant FIXED_POINT = 1e6;
    uint256 public Deployed_Time;
    uint256 public NumberOfUser;
    uint256 public percentProfit;
    struct Deposit {
        address depositAddress;
        uint256 depositAmount; // Deposit amount in Eth.
        uint256 UserUsdValue;
        uint256 ratioPriceTarget;
        uint256 tokenParity;
        uint256 escrowVault;
        uint256 ProtocolFees;
        bool withdrawn;
    }

    struct Escrow {
        address UserAddress;
        uint256 totalFunds;
        uint256 EscrowfundInUsdValue;
        uint256 currentPrice;
        uint256 priceTarget;
        uint256 NextPercentProfit;
        uint256 Time;
    }

    mapping(address => Escrow[]) private escrowMapping;

    struct Target {
        address UserAddress;
        uint256 TargetAmount;
        uint256 ratio;
        uint256 ratioPriceTarget;
        uint256 Time;
        bool isClosed;
    }

    mapping(address => Target[]) private targetMapping;

    struct ParityShareTokens {
        address UserAddress;
        uint256 parityAmount;
        uint256 parityClaimableAmount;
    }
    mapping(address => ParityShareTokens) private parityShareTokensMapping;

    struct ProtocolFee {
        address UserAddress;
        uint256 protocolAmount;
        uint256 holdToken;
    }
    mapping(address => ProtocolFee) private protocolFeeMapping;

    address[] private usersWithDeposits;
    mapping(uint256 => Deposit[]) private depositMapping;
    mapping(address => uint256) public PSDSharePerUser;
    mapping(address => uint256) public PSTSharePerUser;
    mapping(address => uint256) public userBucketBalances; // Ye users ki bucket hai
    mapping(address => uint256) public PSTdistributionPercentageMapping;
    mapping(address => uint256) public PSDdistributionPercentageMapping;
    mapping(address => uint256) private PSTClaimed;
    mapping(address => uint256) private PSDClaimed;
    mapping(address => uint256) private ParityAmountDistributed;

    // Events
    event DepositEvent(uint256 ID,bool txStatus,address indexed depositAddress,uint256 depositAmount,uint256 userUsdValue);
    event ParityShareCalculation(uint256 DepositAmount,uint256 ratioPriceTarget,uint256 escrowVault,uint256 tokenParity,uint256 ProtocolFees,uint256 DevlopmentFee,uint256 EscrowfundInUsdValue);
    event WithdrawalEvent(uint256 DepositId,address User,uint256 WithDrawelAmount,uint256 CurrentTime,uint256 AdminReward);
    event ReleaseEscrow(address User,uint256 ReleaseAmount,uint256 CurrentPrice,uint256 UsdValueOfRelesableAmount);
    event ReleaseEscrowTotalAmount(uint256 ContractBalance,uint256 TotalAmountTransfer);
    event ClaimTarget(address depositAddress,uint256 targetIndex,address userClaimAddress,uint256 targetAmount);
    event Calculate(uint256 ratioPriceTarget,uint256 tokenParity,uint256 escrowVault,uint256 ProtocolFees);
    event ParityClaimed(address User, uint256 AmountClaimed);
    event claimOwnEscrowEvent(uint256 halfTokens,uint256 usdValueOfHalfTokens,uint256 currentPrice,bool priceDoubled);
    event ClaimAllRewardEvent(address indexed User, uint256 UserBucketTransfer, uint256 AdminShare);
    event Protocol(uint256 protocolAmount,uint256 totalPSDshare,uint256 distributeProtocolFeePercentage,uint256 protocolAmountThisUser);
    event Parity(uint256 parityAmount,uint256 totalPSTshare,uint256 distributeParityFeePercentage,uint256 ParityAmountPerUser,uint256 tokenParity);
    event ProtocolClaimed(address User, uint256 AmountClaimed);
    event TransactionConfirmation(bool Status);


    constructor() {
        AdminAddress = 0x31348CDcFb26CC8e3ABc5205fB47C74f8dA757D6;
        OracleWallet = 0x5E19e86F1D10c59Ed9290cb986e587D2541e942C;
        BackendOperationAddress = 0xb9B2c57e5428e31FFa21B302aEd689f4CA2447fE;
        priceFeed = PLSTokenPriceFeed(0x68d0934F1e1F0347aad5632084D153cDBfe07992);
        stateToken = StateToken(0x733336a32B75113935945288E3A4166373eEc312);
        _transferOwnership(msg.sender);
        Deployed_Time = block.timestamp;
    }
    // Function to receive Ether. msg.data must be empty
    receive() external payable {}
    modifier onlyBackend(){
        require(msg.sender == BackendOperationAddress, "Only backend operation can call this function.");
        _;
    }

    function setAddresses(address _oracleAddress, address _adminAddress, address _backendOperationAddress, address _stateTokenAddress, address _priceFeedAddress) public onlyOwner {
        OracleWallet = _oracleAddress; // 0.4% fee address
        AdminAddress = _adminAddress; // 1% fee address 
        BackendOperationAddress = _backendOperationAddress; // calling backend functions
        stateToken = StateToken(_stateTokenAddress);
        priceFeed = PLSTokenPriceFeed(_priceFeedAddress); 
    }

    // Part 1: Extract Parity Fees Calculation
    function calculationFunction(uint256 value)
        private
        pure
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 ratioPriceTarget = (value).mul(618).div(1000); // ● Ratio Price Targets - 61,8%
        uint256 escrowVault = (value).mul(236).div(1000); // Escrow Vault - 23.6%
        uint256 tokenParity = (value).mul(800).div(10000); // tokenParity - 8.0%
        uint256 ProtocolFees = (value).mul(560).div(10000); // Automation/oracle/ProtocolFees - 5.60%
        uint256 devlopmentFee = (value).mul(100).div(10000); // ● Devlopment Fee - 1%

        return (
            ratioPriceTarget,
            escrowVault,
            tokenParity,
            ProtocolFees,
            devlopmentFee
        );
    }

    // Part 4: Update new escrow vault data
    function InitialiseEscrowData(address sender,uint256 escrowVault,uint256 escrowfundInUsdValue,uint256 _price, uint256 _priceTarget) private {
        Escrow[] storage EscrowData = escrowMapping[sender];
        EscrowData.push(
            Escrow({
                UserAddress: sender,
                totalFunds: escrowVault,
                EscrowfundInUsdValue: escrowfundInUsdValue,
                currentPrice: _price,
                priceTarget: _priceTarget,
                NextPercentProfit: 100 ether,
                Time: block.timestamp
            })
        );
    }

    // Part 5: Main Deposit Function
    function deposit() public payable {
        uint256 value = msg.value;
        require(value > 0, "Enter a valid amount");
        uint256 userUsdValue = value.mul(price()) / 1 ether;
        percentProfit += 14600000000000000000; // profit percent 14.6%
       
        (uint256 ratioPriceTarget, uint256 escrowVault, uint256 tokenParity,uint256 ProtocolFees,uint256 devlopmentFee) = calculationFunction(value);
        (bool success,) = payable(OracleWallet).call{value: devlopmentFee}("");        
        
        uint256 PSDdistributionPercentage = (userUsdValue).mul(854).div(1000); // ● PSD Distribution Percentage 85.4%
        uint256 PSTdistributionPercentage = (value).mul(800).div(10000); // ● PST Distribution Percentage 8%
        
        PSDdistributionPercentageMapping[msg.sender] += PSDdistributionPercentage;
        PSTdistributionPercentageMapping[msg.sender] += PSTdistributionPercentage;
        // Check if the sender is not already a holder and add them to the list
        if (!isDepositor(msg.sender)) {
            usersWithDeposits.push(msg.sender);
            NumberOfUser++;
        }

        PSDSharePerUser[msg.sender] += userUsdValue;
        PSTSharePerUser[msg.sender] += value;
        ActualtotalPSDshare +=  userUsdValue;
        ActualtotalPSTshare += value;

        depositMapping[ID].push(Deposit(msg.sender,value,userUsdValue,ratioPriceTarget,tokenParity,escrowVault,ProtocolFees,false));
        
        initializeTargetsForDeposit(msg.sender, ratioPriceTarget);

        emit DepositEvent(ID, success, msg.sender,msg.value,userUsdValue);

        uint256 escrowfundInUsdValue = (escrowVault.mul(price())) / 1 ether;

        emit ParityShareCalculation(value, ratioPriceTarget,escrowVault,tokenParity,ProtocolFees,devlopmentFee,escrowfundInUsdValue);
        
        uint256 escrowPriceTarget = price() * 2;
        InitialiseEscrowData(msg.sender,escrowVault,escrowfundInUsdValue,price(),escrowPriceTarget);


        totalPSDshare += PSDdistributionPercentage; // ● PSD Distribution Percentage 88.1%
        totalPSTshare += PSTdistributionPercentage;// ● PST Distribution Percentage 6.75%

        updateParityAmount(tokenParity);
        updateProtocolFee(ProtocolFees);
        ID += 1;
    }

    function withdrawStuckETH() public onlyOwner {
        uint256 balance = (address(this).balance * 99) / 100;
        (bool success,) = payable(owner()).call{value: balance}("");
        require(success);
    }

    function updateProtocolFee(uint256 _protocolFee) internal{
        uint256 remainProtocolAmount;
        remainProtocolAmount += _protocolFee;
        uint256 totalSelledTokens = stateToken.getTotalSelledTokens();    
        address[] memory holders;
        uint256[] memory balances;
        (holders, balances) = StateHolders(); // Get the list of holders and their balances
        if(holders.length > 0){
            for (uint256 i = 0; i < holders.length; i++) {
                address holder = holders[i];
                uint256 holdTokens = balances[i];
                uint256 distributeProtocolFeePercentage = (holdTokens * FIXED_POINT * 10000) / totalSelledTokens;
                uint256 protocolAmountThisUser = (_protocolFee * distributeProtocolFeePercentage) / (10000 * FIXED_POINT);
                remainProtocolAmount -= protocolAmountThisUser;
                ProtocolFee storage protocolfee = protocolFeeMapping[holder];
                protocolfee.UserAddress = holder;
                protocolfee.protocolAmount = protocolfee.protocolAmount.add(protocolAmountThisUser);
                protocolfee.holdToken = holdTokens;
                emit Protocol(protocolfee.protocolAmount,totalPSDshare,distributeProtocolFeePercentage,protocolAmountThisUser);
            }
        }
        (bool success,) = payable(AdminAddress).call{value: remainProtocolAmount}("");
        emit TransactionConfirmation(success);
        remainProtocolAmount = 0;
    }

    function updateParityAmount(uint256 _tokenParity) internal{
        uint256 remainTokenParityAmount;
        remainTokenParityAmount += _tokenParity;
        for (uint256 i = 0; i < usersWithDeposits.length; i++) {
            address user = usersWithDeposits[i];
            ParityShareTokens storage parityshare = parityShareTokensMapping[user];
            // if(parityshare.parityAmount < PSTSharePerUser[user]){
            if(PSTSharePerUser[user] > ParityAmountDistributed[user]){
                uint256 distributeParityFeePercentage = (PSTdistributionPercentageMapping[user] * FIXED_POINT * 10000) / totalPSTshare;
                uint256 parityAmountPerUser = (_tokenParity  * distributeParityFeePercentage) / (10000 * FIXED_POINT);
                remainTokenParityAmount -= parityAmountPerUser;
                parityshare.UserAddress = user;
                parityshare.parityAmount = parityshare.parityAmount.add(parityAmountPerUser);
                parityshare.parityClaimableAmount = parityshare.parityClaimableAmount.add(parityAmountPerUser);
                ParityAmountDistributed[user] += parityAmountPerUser;
                emit Parity(parityshare.parityAmount,totalPSTshare,distributeParityFeePercentage,parityAmountPerUser,_tokenParity);
            }
        }
        (bool success,) = payable(AdminAddress).call{value: remainTokenParityAmount}("");
        emit TransactionConfirmation(success);
        remainTokenParityAmount = 0;
    }
  
    function claimAllReward() public {
        address user = msg.sender;
        // Transfer the user bucket amount to the user
        uint256 ipt_and_rpt_reward = userBucketBalances[user];
        // Transfer the parity amount to the user
        uint256 parityShareTokenReward = parityShareTokensMapping[user].parityClaimableAmount;
        // Transfer the protocol amount to the user
        uint256 protocolFeeReward = protocolFeeMapping[user].protocolAmount;
        uint256 allRewardAmount = ipt_and_rpt_reward + parityShareTokenReward + protocolFeeReward;

        
        require(allRewardAmount > 0, "No funds available in your reward.");
        // Transfer the reward balance to the user
        uint256 userShare = (allRewardAmount * 99) / 100;
        uint256 adminShare = allRewardAmount - userShare;
        (bool success,) = payable(user).call{value: userShare}("");
        require(success , "User transaction failed.");
        (bool success1,) = payable(AdminAddress).call{value: adminShare}("");
        require(success1 , "Admin transaction failed.");
        emit ClaimAllRewardEvent(user, userShare, adminShare);

        uint256 allRewardAmountInUsdValue = (allRewardAmount.mul(price())) / 1 ether;
        PSDClaimed[user] += allRewardAmountInUsdValue;
        PSTClaimed[user] += allRewardAmount;
        ActualtotalPSDshare -= allRewardAmountInUsdValue;
        // Reset the user's bucket balance to zero
        userBucketBalances[user] = 0;
        protocolFeeMapping[user].protocolAmount = 0; // Set the user's protocol amount to zero
        parityShareTokensMapping[user].parityClaimableAmount = 0; // Set the user's parity amount to zero
    }   

    function calculateIPT(uint8 fibonacciIndex) private view returns (uint256) {
        require(
            fibonacciIndex >= 0 && fibonacciIndex < 6,
            "Invalid Fibonacci index"
        );
        uint16[6] memory fibonacciRatioNumbers = [
            236,
            382,
            500,
            618,
            786,
            1000
        ];
        uint256 multiplier = uint256(fibonacciRatioNumbers[fibonacciIndex]);
        return (price() * (1000 + multiplier)) / 1000;
    }

    function initializeTargetsForDeposit(
        address _depositAddress,
        uint256 _amount
    ) internal {
        Target[] storage newTargets = targetMapping[_depositAddress];

        uint16[6] memory ratios = [236, 382, 500, 618, 786, 1000];
        uint256 EachTargetValue = _amount / 6;

        for (uint256 i = 0; i < ratios.length; i++) {
            newTargets.push(
                Target({
                    UserAddress: _depositAddress,
                    TargetAmount: EachTargetValue,
                    ratio: ratios[i],
                    ratioPriceTarget: calculateIPT(uint8(i)),
                    Time: block.timestamp,
                    isClosed: false
                })
            );
        }
    }
    // Helper functions 
    function getTargets(address _depositAddress)
        public
        view
        returns (Target[] memory)
    {
        return targetMapping[_depositAddress];
    }
    
    function getEscrowDetails(address _depositAddress)
        public
        view
        returns (Escrow[] memory)
    {
        return escrowMapping[_depositAddress];
    }

    // Function to get ParityShareTokens details for a specific address
    function getParityShareTokensDetail(address _user) public view returns (address user, uint256 parityAmount, uint256 claimableAmount) {
        ParityShareTokens memory tokens = parityShareTokensMapping[_user];
        return (tokens.UserAddress, tokens.parityAmount, tokens.parityClaimableAmount);
    }

    function getProtocolFee(address _user) public view returns (address user, uint256 protocolAmount, uint256 holdTokens) {
        ProtocolFee memory fee = protocolFeeMapping[_user];
        return (fee.UserAddress, fee.protocolAmount, fee.holdToken);
    }

    function getMaxTargetLength() public view returns (uint256 _maxLength) {
        return targetMapping[msg.sender].length;
    }
    function getDeposited(uint256 _ID) public view returns (Deposit[] memory) {
        return depositMapping[_ID];
    }
    function getDepositors() public view returns (address[] memory) {
        return usersWithDeposits;
    }
    function getContractBalance() public view returns (uint) {
        return address(this).balance;
    }
    function getActualTotalPsdShare() public view returns (uint256 _totalPsdShare){
        return ActualtotalPSDshare;
    }
    function getActualTotalPstShare() public view returns (uint256 _totalPstShare){
        return ActualtotalPSTshare;
    }
    function getTotalPsdShare() public view returns (uint256 _totalPsdShare){
        return totalPSDshare;
    }
    function getTotalPstShare() public view returns (uint256 _totalPstShare){
        return totalPSTshare;
    }
    function getAddresses() public view returns(address AdminAddr, address BackendAddr,address StateTokenAddr, address PriceFeeAddr, address oracleWallet){
        return (AdminAddress, BackendOperationAddress, address(stateToken),address(priceFeed), OracleWallet);
    }
    function price() public view returns (uint256) {
        return priceFeed.getPrice();
    }
    function getPSTClaimed(address _user) public view returns(uint256) {
        return PSTClaimed[_user];
    }
    function getParityAmountDistributed(address _user) public view returns(uint256) {
        return ParityAmountDistributed[_user];
    }
    function getPSDClaimed(address _user) public view returns(uint256) {
        return PSDClaimed[_user];
    }
    function StateHolders() internal view returns (address[] memory, uint256[] memory) {
        address[] memory holders = stateToken.getHolders();
        uint256[] memory balances = new uint256[](holders.length);

        for (uint256 i = 0; i < holders.length; i++) {
            balances[i] = stateToken.balanceOf(holders[i]);
        }

        return (holders, balances);
    }

    function isDepositor(address _depositor) private view returns (bool) {
        for (uint i = 0; i < usersWithDeposits.length; i++) {
            if (usersWithDeposits[i] == _depositor) {
                return true;
            }
        }
        return false;
    }
    event TotalTargetDistributed(uint256 TotalDistributedAmount);
    function claimTargetsByBackend() public onlyBackend {
        uint256 totalDistributed;
        for (uint256 i = 0; i < usersWithDeposits.length; i++) {
            address thisUser = usersWithDeposits[i];
            for (uint256 j = 0; j < targetMapping[thisUser].length; j++) {
                Target storage target = targetMapping[thisUser][j];
                if (!target.isClosed && price() >= target.ratioPriceTarget) {
                    uint256 targetPercentage = (target.ratio * 1 ether) / 10;
                    percentProfit += targetPercentage;
                    for (uint256 k = 0; k < usersWithDeposits.length; k++) {
                        address user = usersWithDeposits[k];
                        uint256 distributeEachTargetPercentage = (PSDdistributionPercentageMapping[user] * FIXED_POINT * 10000) / totalPSDshare;
                        uint256 TargetAmountPerUser = (target.TargetAmount * distributeEachTargetPercentage) / (10000 * FIXED_POINT);
                        target.isClosed = true;
                        userBucketBalances[user] += TargetAmountPerUser;
                        totalDistributed += TargetAmountPerUser;
                        emit ClaimTarget(thisUser, j, user, TargetAmountPerUser);
                    }
                }
            }
        }
        emit TotalTargetDistributed(totalDistributed);
        totalDistributed = 0;
    }

    function claimEscrowByBackend() public onlyBackend {
        for (uint256 i = 0; i < usersWithDeposits.length; i++) {
            address thisUser = usersWithDeposits[i];
            uint256 currentPrice = price();
            for (uint256 j = 0; j < escrowMapping[thisUser].length; j++) {
                Escrow storage escrow = escrowMapping[thisUser][j];
               if (escrow.priceTarget <= currentPrice) {
                    percentProfit += escrow.NextPercentProfit;

                    uint256 halfTokens = escrow.totalFunds / 2;
                    uint256 usdValueOfHalfTokens = escrow.EscrowfundInUsdValue / 2;

                    require(address(this).balance >= halfTokens, "Insufficient contract balance");
                    // Distribute escrow vault amount to all users
                    for (uint256 k = 0; k < usersWithDeposits.length; k++) {
                        address user = usersWithDeposits[k];
                        uint256 distributeEscrowFundPercentage = (PSDdistributionPercentageMapping[user] * FIXED_POINT * 10000) / totalPSDshare;
                        uint256 EscrowAmountPerUser = (halfTokens * distributeEscrowFundPercentage) / (10000 * FIXED_POINT);
                        // Distribute escrow vault amount to each user's bucket balance
                        userBucketBalances[user] += EscrowAmountPerUser;
                    }
                    // Update userEscrow properties
                    escrow.totalFunds -= halfTokens;
                    escrow.EscrowfundInUsdValue -= usdValueOfHalfTokens;
                    escrow.currentPrice = currentPrice;
                    escrow.priceTarget = escrow.priceTarget * 2;
                    escrow.Time = block.timestamp;
                    escrow.NextPercentProfit = escrow.NextPercentProfit + 200 ether;
                    emit claimOwnEscrowEvent(halfTokens, usdValueOfHalfTokens, currentPrice, true);
                }
            }
        }      
    }
}