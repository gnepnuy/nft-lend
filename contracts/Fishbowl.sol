//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


contract Fishbowl {

  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  address public constant ETHER_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  uint256 public constant DAY = 1 days;
  uint256 public constant HOUR = 1 hours;
  uint256 public constant MIN_LEND_TIME = DAY;
  
  uint256 public timeoutInterval;//超时区间
  uint256 public timeoutRate;//超时费率
  address[] public paycoins;//可支付的币种列表
  uint256 public fishId;//出借单的id
  mapping(uint256 => Fish) public fishs;//出借单id -> 出借单
  mapping(uint256 => address) public userFish; //出借单id -> 出借人
  mapping(address => uint256[]) public userFishs;//出借人 -> 出借单id数组
  mapping(address => uint256[]) public collectionFishs;//nft地址 -> 出借单id数组
  EnumerableSet.AddressSet private collectionAddressSet;//collection[]

  enum Status {
    Waiting,
    Lending,
    Close
  }

  struct Fish {
    address nft;//nft的合约地址
    uint256 tokenId;//nft id
    uint256 returnTime;//归还时间
    uint256 dailyRent;//一天的租金
    address payCoin;//支付币种
    uint256 deposit;//押金
    Status  status;//状态
    uint256 receivedRent;//已收到的租金
    address hirer;//租用人
    uint256 rentStartTime;//租借开始时间
  }

  
  event LEND(address indexed lender,address indexed nft,address indexed payCoin, uint256 tokenId, uint256 deposit);
  event RENT(address indexed hirer,address indexed nft,address indexed payCoin, uint256 tokenId, uint256 paymentMoney);
  event REMAND(address indexed returner,address indexed nft,address indexed payCoin, uint256 tokenId, uint256 refund);
  event CLOSE(uint256 indexed fishId,address indexed closer,address indexed nft, uint256 tokenId, uint256 refund,Status originalStatus);
  event MODIFY(uint256 indexed fishId,address indexed editor,address indexed nft, uint256 tokenId,uint256 returnTime,uint256 dailyRent,uint256 deposit,address payCoin);



  uint private unlocked = 1;
  modifier lock() {
      require(unlocked == 1, 'FISH: LOCKED');
      unlocked = 0;
      _;
      unlocked = 1;
  }

  constructor(address[] memory _paycoins,uint256  _timeoutInterval,uint256 _timeoutRate){
    //init payCoin
    for(uint256 i = 0; i < _paycoins.length; i++){
     
      paycoins.push(_paycoins[i]);
    }

    paycoins.push(ETHER_ADDRESS);

    //init timeout
    timeoutInterval = _timeoutInterval;
    timeoutRate = _timeoutRate;
  }


  /**
    出租动作，生成出租订单
   */
  function lend(address _nft,uint256 _tokenId,uint256 _returnTime,uint256 _dailyRent,address _payCoin,uint256 _deposit) 
            external lock {
    //校验是否为721
    require(ERC721(_nft).supportsInterface(0x80ac58cd), "Not ERC721");
    //首先校验下归还时间，设定一个最小的出借时间，当前时间要小于归还时间减去一天
    require(block.timestamp < (_returnTime - MIN_LEND_TIME),'Return time is too short');
    //校验支付币地址
    require(_checkPayCoin(_payCoin),'Pay coin not support');

    //把nft转到当前合约
    ERC721(_nft).transferFrom(msg.sender, address(this), _tokenId);
    //组装出借单
    fishs[fishId] = Fish({
      nft: _nft,
      tokenId: _tokenId,
      returnTime: _returnTime,
      dailyRent: _dailyRent,
      payCoin: _payCoin,
      deposit: _deposit,
      status: Status.Waiting,
      receivedRent: 0,
      hirer: address(this),
      rentStartTime: 0
    });

    //记录一些数据
    userFish[fishId] = msg.sender;
    userFishs[msg.sender].push(fishId);
    collectionFishs[_nft].push(fishId);
    collectionAddressSet.add(_nft);

    fishId++;
    emit LEND(msg.sender,_nft,_payCoin,_tokenId,_deposit);
  }

  //租用nft
  function rent(uint256 _fishId,uint256 _dailyRent,uint256 _deposit) external lock {
    //这里先校验出借单的状态
    require(fishs[_fishId].status == Status.Waiting,'Not rent');
    //校验价格
    require(fishs[_fishId].dailyRent == _dailyRent && fishs[_fishId].deposit == _deposit,'Prices have changed');
    uint256 currentTime = block.timestamp;
    //计算出需要支付的租金
    uint256 rentMoney = _calculateRent(currentTime,fishs[_fishId].returnTime,fishs[_fishId].dailyRent);
    //租金加上押金
    uint256 paymentMoney = rentMoney.add(fishs[_fishId].deposit);
    //把币转到当前合约
    ERC20(fishs[_fishId].payCoin).transferFrom(msg.sender, address(this), paymentMoney);
    //修改出借单状态
    fishs[_fishId].status = Status.Lending;

    //把借出人信息写入出借单
    fishs[_fishId].hirer = msg.sender;
    //记录借出时间
    fishs[_fishId].rentStartTime = currentTime;
    //把nft转给借出人
    ERC721(fishs[_fishId].nft).transferFrom(address(this), msg.sender, fishs[_fishId].tokenId);
    
    //event RENT(address indexed hirer,address indexed nft,address indexed payCoin, uint256 tokenId, uint256 paymentMoney);
    emit RENT(msg.sender,fishs[_fishId].nft,fishs[_fishId].payCoin,fishs[_fishId].tokenId,paymentMoney);
  }

  //归还nft
  function remand(uint256 _fishId) external lock {
    //这里先校验出借单的状态
    require(fishs[_fishId].status == Status.Lending,'Not remand');

    //这里涉及到一个是否要校验归还人是否为租借人的思考，那就不要了，不管是谁，拥有nft就能拿回押金
    //计算租了多久
    uint256 currentTime = block.timestamp;
    uint256 returnTime = fishs[_fishId].returnTime;
    uint256 paymentMoney = 0;

    //先处理掉超过超时区间的情况
    require(currentTime <= returnTime.add(timeoutInterval),'The deadline has passed');

    //算出租借时付了多少租金
    uint256 paidRent = _calculateRent(fishs[_fishId].rentStartTime,fishs[_fishId].returnTime,fishs[_fishId].dailyRent);

    //计算在超时区间需要付的费用
    if(currentTime > returnTime){
      paymentMoney = fishs[_fishId].deposit.mul(timeoutRate).div(100);
      paymentMoney = paymentMoney.add(paidRent);
      //修改出借单状态
      fishs[_fishId].status = Status.Close;
    }else{
      //计算未超时区间的费用
      paymentMoney = _calculateRent(fishs[_fishId].rentStartTime,currentTime,fishs[_fishId].dailyRent);
      //修改出借单状态
      fishs[_fishId].status = Status.Waiting;
    }

    //记录租金收益
    fishs[_fishId].receivedRent = fishs[_fishId].receivedRent.add(paymentMoney);

    if(fishs[_fishId].status == Status.Waiting){
      //把nft转到当前合约
      ERC721(fishs[_fishId].nft).transferFrom(msg.sender,address(this),fishs[_fishId].tokenId);
    }else{
      //把nft转给出借人
      ERC721(fishs[_fishId].nft).transferFrom(msg.sender,userFish[_fishId],fishs[_fishId].tokenId);
      //把收到的租金转给出借人
      ERC20(fishs[_fishId].payCoin).transfer(userFish[_fishId], fishs[_fishId].receivedRent);
    }

    //计算出退款
    uint256 returnMoney = fishs[_fishId].deposit.add(paidRent).sub(paymentMoney);

    //把押金和剩余的租金还给租借人
    ERC20(fishs[_fishId].payCoin).transfer(msg.sender, returnMoney);
    
    emit REMAND(msg.sender,fishs[_fishId].nft,fishs[_fishId].payCoin,fishs[_fishId].tokenId,returnMoney);
  }

  //出借人关闭出借单
  function closeFish(uint256 _fishId) external lock{
    //验证是不是所有者
    require(userFish[_fishId] == msg.sender,'Not the owner');

    uint256 currentTime = block.timestamp;
    uint256 returnTime = fishs[_fishId].returnTime;

    Status originalStatus = fishs[_fishId].status;
    uint256 returnMoney = 0;

    //订单状态为lending
    if(fishs[_fishId].status == Status.Lending){
      if(currentTime > returnTime.add(timeoutInterval)){
        //这里就属于超时未归还的情况，把押金，租金都转给出借人
        uint256 paidRent = _calculateRent(fishs[_fishId].rentStartTime, fishs[_fishId].returnTime ,fishs[_fishId].dailyRent);
        returnMoney = paidRent.add(fishs[_fishId].deposit);
      }
    }
    
    //订单状态为waiting
    if(fishs[_fishId].status == Status.Waiting){
      //把收到的租金和nft转给出借人
      if(fishs[_fishId].receivedRent > 0){
        returnMoney = fishs[_fishId].receivedRent;
        ERC721(fishs[_fishId].nft).transferFrom(address(this),userFish[_fishId],fishs[_fishId].tokenId);
      }
    }

     ERC20(fishs[_fishId].payCoin).transfer(userFish[_fishId], returnMoney);
     fishs[_fishId].status = Status.Close;

     //emit 
    emit CLOSE(_fishId,msg.sender,fishs[_fishId].nft,fishs[_fishId].tokenId,returnMoney,originalStatus);
  }


  //修改出借单
  function modifyFish(uint256 _fishId,uint256 _returnTime,uint256 _dailyRent,uint256 _deposit,address _payCoin) external lock{
    //验证是不是所有者
    require(userFish[_fishId] == msg.sender,'Not the owner');
    //验证状态必须为waiting
    require(fishs[_fishId].status == Status.Waiting,'');
    
    if(fishs[_fishId].returnTime != _returnTime){
      //校验下归还时间，设定一个最小的出借时间，当前时间要小于归还时间减去一天
      require(block.timestamp < (_returnTime - MIN_LEND_TIME),'Return time is too short');
      fishs[_fishId].returnTime = _returnTime;
    }

    if(fishs[_fishId].dailyRent != _dailyRent){
      require(_dailyRent > 0,'Yes, we do not allow 0 rent');
      fishs[_fishId].dailyRent = _dailyRent;
    }

    if(fishs[_fishId].deposit != _deposit){
      require(_deposit > 0,'Yes, we do not allow 0 mortgage');
      fishs[_fishId].deposit = _deposit;
    }

    if(fishs[_fishId].payCoin != _payCoin){
      //校验支付币地址
      require(_checkPayCoin(_payCoin),'Pay coin not support');
      require(fishs[_fishId].receivedRent == 0,'Two payment methods are not allowed');
      fishs[_fishId].payCoin = _payCoin;
    }

    emit MODIFY(_fishId,msg.sender,fishs[_fishId].nft, fishs[_fishId].tokenId,_returnTime,_dailyRent,_deposit,_payCoin);
  }

  function _calculateRent(uint256 _rentStartTime,uint256 _returnTime,uint256 _dailyRent) internal view returns(uint256){
    //计算出还剩多少天
    uint256 remainingTime = _returnTime - _rentStartTime;
    console.log('blockTime:',_rentStartTime,'remainingTime:',remainingTime);

    uint256 count =  remainingTime/DAY;
    console.log('count1:',count);

    if(remainingTime % DAY != 0){
      count++;
      console.log('count2:',count);
    }

    return count * _dailyRent;
  }

  function _checkPayCoin(address _payCoin) internal view returns (bool){
    for(uint i = 0;i < paycoins.length;i++){
      if(paycoins[i] == _payCoin){
        return true;
      }
    }
    return false;
  }

  /*****SIGN TEST*****/
  function verifierSign(bytes32 hash,bytes memory signature) view public returns(bool)   {
    bytes memory prefix = "\x19Ethereum Signed Message:\n32";
    bytes32 prefixedHash = keccak256(abi.encodePacked(prefix, hash));
    require(msg.sender == ECDSA.recover(prefixedHash, signature),'sign error');

    return true;
  }

  function verifierSignVRS(bytes32 hash,uint8 v, bytes32 r, bytes32 s) pure public returns(address){

    bytes memory prefix = "\x19Ethereum Signed Message:\n32";
    bytes32 prefixedHash = keccak256(abi.encodePacked(prefix, hash));

    return ecrecover(prefixedHash, v, r, s);
  }



  /*****VIEW*****/ 

  function viewCollection() external view returns(address[] memory){
    
    return collectionAddressSet.values();
  }

  function viewAddressFishIds(address _user) external view returns(uint256[] memory){

    return userFishs[_user];
  }







  
}