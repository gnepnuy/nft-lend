import chai, { expect } from 'chai';
import { ethers } from 'hardhat';
import { solidity } from 'ethereum-waffle';
import { Contract, ContractFactory, BigNumber, utils } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import exp from 'constants';

chai.use(solidity);

describe("fishbowl",() => {

  const ether = 100000000000000000;
  const ethAddress = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

  let fishbowl: Contract;
  let boredApeYachtClub: Contract;  
  let owner: SignerWithAddress;

  beforeEach('deploy fishbowl and nft',async function(){
    [owner] = await ethers.getSigners();

    const Fishbowl = await ethers.getContractFactory('Fishbowl');
    const paycoins = ["0x93e7523E24BDe43ce93b5970c6fa251c5b1E1aEa","0x93e7523E24BDe43ce93b5970c6fa251c5b1E1aEa"];
    const timeoutInterval = 86400;
    const timeoutRate = 3;
    fishbowl = await Fishbowl.deploy(paycoins,timeoutInterval,timeoutRate);
    await fishbowl.deployed();

    expect(await fishbowl.timeoutInterval()).to.eq(timeoutInterval);
    expect(await fishbowl.timeoutRate()).to.eq(timeoutRate);

    const BoredApeYachtClub = await ethers.getContractFactory('BoredApeYachtClub');
    const name = "BoredApeYachtClub";
    const symbol = "BAYC";
    const baseUrl = "ipfs://QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq/";
    boredApeYachtClub = await BoredApeYachtClub.deploy(name,symbol);
    await boredApeYachtClub.deployed();
    await boredApeYachtClub.setBaseURI(baseUrl);
    await boredApeYachtClub.mint();
    await boredApeYachtClub.mint();

    expect(await boredApeYachtClub.baseURI()).to.eq(baseUrl);
    expect(await boredApeYachtClub.name()).to.eq(name);
    expect(await boredApeYachtClub.symbol()).to.eq(symbol);
    expect(await boredApeYachtClub.totalSupply()).to.eq(2);

    //上面是部署合约和参数校验，下面的就是发布一个出借单
    //function approve(address to, uint256 tokenId) external;
    const tokenId = 1;
    //await boredApeYachtClub.approve(fishbowl.address,tokenId);

    //function setApprovalForAll(address operator, bool _approved) external;
    await boredApeYachtClub.setApprovalForAll(fishbowl.address,true);
    //function lend(address _nft,uint256 _tokenId,uint256 _returnTime,uint256 _dailyRent,address _payCoin,uint256 _deposit) 
 
    const nft = boredApeYachtClub.address;
    
    const returnTime = 1647251200;//2021-11-19 00:00:00
    const dailyRent = BigNumber.from(1).mul(BigNumber.from(10).pow(18));
    const payCoin = ethAddress;
    const deposit = BigNumber.from(10).mul(BigNumber.from(10).pow(18));

    await fishbowl.lend(nft,tokenId,returnTime,dailyRent,payCoin,deposit);

    await fishbowl.lend(nft,2,returnTime,dailyRent,payCoin,deposit);



  })


  it("这里去校验下出借单的数据",async function () {
    
    // const totalSupply = await boredApeYachtClub.totalSupply();
    // console.log("猴子的总量：",totalSupply.toString());
    // const nftAmount = await boredApeYachtClub.balanceOf(fishbowl.address);
    // console.log("鱼缸的nft数量：",nftAmount.toString());

    const userFishIds = await fishbowl.viewAddressFishIds(owner.address);

    expect(userFishIds[1]).to.eq(1);
    const fish = await fishbowl.fishs(userFishIds[1]);
    
    expect(fish[0]).to.eq(boredApeYachtClub.address);
    expect(fish[1]).to.eq(2);
    expect(fish[8]).to.eq(fishbowl.address);
    expect(fish[9]).to.eq(0);
    //console.log(fish.toString());
  });


  // it("这里测试签名",async function(){
  //   const testContent = "aaaaaaaa";

  //   const message = ethers.utils.id(testContent);

  //   const messageBytes = ethers.utils.arrayify(message);
  //   //const sig = owner.signMessage(messageBytes);
  //   let wallet = new ethers.Wallet("cbe3eb8472ccd739ee99ffa2e443ce23e8456243fd45d3b0176b9b1ee7849429");

  //   const flatSig = await wallet.signMessage(messageBytes);
  //   // expect(await fishbowl.verifierSign(messageBytes,flatSig)).to.equal(true);

  //   let sig = ethers.utils.splitSignature(flatSig);
  //   expect(await fishbowl.verifierSignVRS(messageBytes,sig.v, sig.r, sig.s)).to.equal('0xf71A370D35F70E4467A90BC696D48e357bA91A46');
  // })

})