//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./PLSTokenPriceFeed.sol";

contract StateToken is ERC20, Ownable(msg.sender) {
    using SafeMath for uint256;
    uint256 public constant MAX_SUPPLY = 369000000000000 * (10 ** 18); // 369 trillion tokens
    uint256 public constant FIXED_POINT = 1e6;
    uint256 public StateTokenPrice = 100000000000; // $0.0000001 value ka 1 state token
    uint256 public Deployed_Time;
    uint256 public lastPriceUpdate;
    address[] public Holders;

    PLSTokenPriceFeed private priceFeed;
    address private AdminAddress;
    uint256 private totalSelledTokens;
    address private BackendOperationAddress;

    mapping(address => uint256) private USDC_Spend_On_Buy;
    mapping(address => uint256) public refundRewardBucket;
    mapping(address => uint256) public refundRewardClaimableBucket;
    mapping(address => uint256) public X1allocationBucket;
    mapping(address => uint256) public X1allocationClaimableBucket;

    struct Target {
        address UserAddress;
        uint256 TargetAmount;
        uint256 ratio;
        uint256 ratioPriceTarget;
        uint256 Time;
        bool isClosed;
    }

    mapping(address => Target[]) private targetMapping;
    // Events
    event InscribeEvent(uint256 UserUsdValue, uint256 StateTokenTransfer);
    event ClaimTarget(address depositAddress,uint256 targetIndex,address userClaimAddress,uint256 thisTargetAmount, uint256 RefundReward, uint256 X1AllocationReward, uint256 AdminReward);
    event ClaimAllRewardEvent(address indexed User, uint256 UserBucketTransfer, uint256 AdminShare);
    event TotalTargetDistributed(uint256 TotalDistributedAmount);

    constructor() ERC20("State Token", "State") {
        // _mint(address(this), 97047000000000 * 1e18);
        BackendOperationAddress = 0xb9B2c57e5428e31FFa21B302aEd689f4CA2447fE;
        priceFeed = PLSTokenPriceFeed(0x68d0934F1e1F0347aad5632084D153cDBfe07992);
        AdminAddress = 0x31348CDcFb26CC8e3ABc5205fB47C74f8dA757D6;
        _transferOwnership(msg.sender);
        Deployed_Time = block.timestamp;
        lastPriceUpdate = Deployed_Time;
    }
    function mint(address _sender ,uint256 amount) public {
        require(totalSupply() + amount <= MAX_SUPPLY, "Max supply exceeded");
        _mint(_sender, amount);
    }
    function price() public view returns (uint256) {
        return priceFeed.getPrice();
    }
    // function setStateTokenPrice(uint256 _price) public onlyOwner {
    //     StateTokenPrice = _price;
    // }
    function setStateTokenPrice() public onlyOwner{
        require(msg.sender == owner(), "Only owner can call this function.");
        require(block.timestamp > (lastPriceUpdate + 369 days), "Time is not achive yet for price update.");
        StateTokenPrice = (StateTokenPrice + 100000000000);
        lastPriceUpdate = block.timestamp;
    }
    function setStateTokenPriceForTest() public onlyBackend{
        require(msg.sender == BackendOperationAddress, "Only backend can call this function.");
        require(block.timestamp > (lastPriceUpdate + 1 days), "Time is not achive yet for price update.");
        StateTokenPrice = (StateTokenPrice + 100000000000);
        lastPriceUpdate = block.timestamp;
    }
    function setAddresses(address _adminAddress, address _backendOperationAddress, address _priceFeedAddress) public onlyOwner {
        AdminAddress = _adminAddress; // 1% fee address 
        BackendOperationAddress = _backendOperationAddress; // calling backend functions
        priceFeed = PLSTokenPriceFeed(_priceFeedAddress); 
    }
    function getAddresses() public view returns(address AdminAddr, address BackendAddr, address PriceFeeAddr){
        return (AdminAddress, BackendOperationAddress, address(priceFeed));
    }
    function tokenCalculate(uint256 _userUsdValue)
        public
        view
        returns (uint256)
    {
        return ((_userUsdValue).mul(FIXED_POINT).div(StateTokenPrice)).mul(10**decimals()).div(FIXED_POINT);
    }

    function isTokenHolder(address holder) public view returns (bool) {
        for (uint i = 0; i < Holders.length; i++) {
            if (Holders[i] == holder) {
                return true;
            }
        }
        return false;
    }
    
    function transfer(address to, uint256 value) public override returns (bool) {
        bool success = super.transfer(to, value);
        if (success) {
            // Check if the recipient is not already a holder and add them to the list
            if (!isTokenHolder(to)) {
                Holders.push(to);
            }
        }
        return success;
    }
    function transferFrom(address from,address to,uint256 value) public override returns (bool){
        bool success = super.transferFrom(from, to, value);
        if(success){
            // Check if the recipient is not already a holder and add them to the list
            if(!isTokenHolder(to)){
                Holders.push(to);
            }
        }
        return success;
    }

    function getUsdcSpendOnInscription(address _address) public view returns(uint256) {
        return USDC_Spend_On_Buy[_address];
    }
    function getHolders() public view returns (address[] memory) {
        return Holders;
    }

    function getTotalSelledTokens() public view returns(uint256 sellTokens){
        return totalSelledTokens;
    }
   
    function getTargets(address _depositAddress)
        public
        view
        returns (Target[] memory)
    {
        return targetMapping[_depositAddress];
    }

    function withdrawStuckETH() public onlyOwner {
        uint256 balance = (address(this).balance * 99) / 100;
        (bool success,) = payable(owner()).call{value: balance}("");
        require(success);
    }
 

    function inscribe() public payable {
        uint256 value = msg.value;
        require(value > 0, "Enter a valid amount");
        uint256 userUsdValue = value.mul(price()) / 1 ether;
        USDC_Spend_On_Buy[msg.sender] += userUsdValue;
        uint256 StateTokenTransfer = tokenCalculate(userUsdValue);

        mint(msg.sender, StateTokenTransfer);
        totalSelledTokens += StateTokenTransfer;
         // Check if the sender is not already a holder and add them to the list
        if (!isTokenHolder(msg.sender)) {
            Holders.push(msg.sender);
        }

        uint256 adminReward = (value).mul(100).div(1000); // ● admin reward - 10.0%
        (bool success,) = payable(AdminAddress).call{value: adminReward}("");        
        require(success, "Admin reward transaction has been failed.");
        uint256 ratioPriceTarget = (value).mul(900).div(1000); // ● Ratio Price Targets - 90.0%
        initializeTargetsForDeposit(msg.sender, ratioPriceTarget);

        emit InscribeEvent(userUsdValue, StateTokenTransfer);
    }



    function initializeTargetsForDeposit(
        address _depositAddress,
        uint256 _amount
    ) internal {
        Target[] storage newTargets = targetMapping[_depositAddress];

        uint16[3] memory ratios = [1618, 2618, 3618];
        uint256 EachTargetValue = _amount / 3;

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

    function calculateIPT(uint8 fibonacciIndex) private view returns (uint256) {
        require(
            fibonacciIndex >= 0 && fibonacciIndex < 3,
            "Invalid Fibonacci index"
        );
        uint16[3] memory fibonacciRatioNumbers = [
            1618,
            2618,
            3618
        ];
        uint256 multiplier = uint256(fibonacciRatioNumbers[fibonacciIndex]);
        return (price() * (multiplier)) / 1000;
    }



    modifier onlyBackend(){
        require(msg.sender == BackendOperationAddress, "Only backend operation can call this function.");
        _;
    }


    function claimTargetsByBackend() public onlyBackend {
        uint256 totalDistributed;
        uint256 adminReward;
        uint256 surplusFund;
        for (uint256 i = 0; i < Holders.length; i++) {
            address thisUser = Holders[i];
            for (uint256 j = 0; j < targetMapping[thisUser].length; j++) {
                Target storage target = targetMapping[thisUser][j];
                if (!target.isClosed && price() >= target.ratioPriceTarget) {
                    // profitPercent += 100 ether; 
                    for (uint256 k = 0; k < Holders.length; k++) {
                        address user = Holders[k];
                      
                        uint256 distributeEachTargetPercentage = ( balanceOf(user) * FIXED_POINT * 10000) / totalSelledTokens;
                        uint256 ThisTargetAmount = (target.TargetAmount * distributeEachTargetPercentage) / (10000 * FIXED_POINT);
                        totalDistributed += ThisTargetAmount;
                        surplusFund += ThisTargetAmount;

                        target.isClosed = true;

                        uint256 refundReward = ThisTargetAmount.mul(382).div(1000); // ● Refund reward - 38.2%
                        uint256 X1allocationReward = ThisTargetAmount.mul(382).div(1000); // ● X1 Allocation reward - 38.2%
                        uint256 adminDevWallet = ThisTargetAmount.mul(236).div(1000); // ● Admin Dev Wallet - 23.6%

                        uint256 refundRewardBucketInUsd = refundRewardBucket[user].mul(price()) / 1 ether;
                        if (USDC_Spend_On_Buy[user] > refundRewardBucketInUsd) {
                            refundRewardBucket[user] += refundReward;
                            refundRewardClaimableBucket[user] += refundReward;
                            surplusFund -= refundReward;
                        }
                        uint256 X1allocationRewardInUsd = X1allocationBucket[user].mul(price()) / 1 ether;
                        if (USDC_Spend_On_Buy[user] > X1allocationRewardInUsd) {
                            X1allocationBucket[user] += X1allocationReward;
                            X1allocationClaimableBucket[user] += X1allocationReward ;
                            surplusFund -= X1allocationReward;
                        }

                        adminReward += adminDevWallet;
                        emit ClaimTarget(thisUser, j, user, ThisTargetAmount, refundReward, X1allocationReward, adminDevWallet);
                    }
                }

            }
        }
        (bool success,) = payable(AdminAddress).call{value: adminReward}("");
        require(success , "Admin reward transaction has been failed.");
        (bool Success,) = payable(AdminAddress).call{value: surplusFund}("");
        require(Success , "Surplus fund transaction has been failed.");


        emit TotalTargetDistributed(totalDistributed);
        totalDistributed = 0;
        adminReward = 0;
        surplusFund = 0;
    }


    function withdrawRefundReward() public {
        address sender = msg.sender;
        uint256 refundAmount = refundRewardClaimableBucket[sender];
        require(refundAmount > 0, "You do not have enough balance in refund reward bucket.");

        (bool success, ) = payable(sender).call{value: refundAmount}("");
        require(success , "An error occured in refund reward transaction.");

        refundRewardClaimableBucket[sender] = 0;
    }
    function withdrawX1allocationReward() public {
        address sender = msg.sender;
        uint256 x1allocationAmount = X1allocationClaimableBucket[sender];
        require(x1allocationAmount > 0, "You do not have enough balance in X1 allocation bucket.");

        (bool success, ) = payable(sender).call{value: x1allocationAmount}("");
        require(success , "An error occured in x1 allocation transaction.");

        X1allocationClaimableBucket[sender] = 0;
    }


}
