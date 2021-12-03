# Basic Sample Hardhat Project

This project demonstrates a basic Hardhat use case. It comes with a sample contract, a test for that contract, a sample script that deploys that contract, and an example of a task implementation, which simply lists the available accounts.

Try running some of the following tasks:

```shell
npx hardhat accounts
npx hardhat compile
npx hardhat clean
npx hardhat test
npx hardhat node
node scripts/sample-script.js
npx hardhat help
```
# nft借贷
1，主要的业务逻辑是用户可以把自己的nft租借给其他用户，
2，具体的操作流程
  用户A在平台操作，生成一个出借单，出借单大概会包括一下信息
    出借单{
      出借的nft: nft的合约地址，id
      出借截至时间：必须归还的时间节点
      出借的租金：暂定为以24小时为计算单位，不满24小时也按24小时计算，出借的租金，借出人必须先支付剩余借出时间的所有租金才能借出nft,提前归还会返回剩余的租金
      未归还的抵押金：借出人要借走这个nft的话，必须抵押一定金额的币，如果借出人在截至时间内未归还nft的话，出借人可以拿走抵押金
    }


3,先给这个项目起个名字 idle fish,goldfish ,fish tank



### 梳理下状态
Status{
  Waiting,
  Lending,
  Close
}
1,出借人创建出借单   ---Waiting

2,租借人借出nft     ---Lending
3,租借人还nft       ---是否超时? close : waiting//这里引入一个超时归还的概念，设定一个超时区间，在超时区间内归还会扣除一定比例的押金
4,出借人关闭出借单  ---close
5,出借人修改出借单参数  --- waiting


