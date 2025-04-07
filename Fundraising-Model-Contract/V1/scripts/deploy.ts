import {ethers, upgrades} from "hardhat";

async function main() {

    const BondingCurveUtil = await ethers.getContractFactory("BondingCurveUtil");
    const BondingCurveUtil_Contract = await BondingCurveUtil.deploy();
    await BondingCurveUtil_Contract.deployed();
    console.log("BondingCurveUtil :", BondingCurveUtil_Contract.address);
    
    const LpLocker = await ethers.getContractFactory("LpLocker");
    const LpLocker_Contract = await LpLocker.deploy();
    await LpLocker_Contract.deployed();
    console.log("LpLocker :", LpLocker_Contract.address);
    //
    const Token = await ethers.getContractFactory("Token");
    const Token_Contract = await Token.deploy();
    await Token_Contract.deployed();
    console.log("Token :", Token_Contract.address);
    
    //BondingCurve
    const BondingCurve = await ethers.getContractFactory("BondingCurve");
    const BondingCurve_Contract = await upgrades.deployProxy( BondingCurve,{
      initializer: "initialize",  //
    });
    console.log("BondingCurve :", BondingCurve_Contract.address);

    const BondingCurveHelper = await ethers.getContractFactory("BondingCurveHelper");
    const BondingCurveHelper_Contract = await BondingCurveHelper.deploy();
    await BondingCurveHelper_Contract.deployed();
    console.log("BondingCurveHelper :", BondingCurveHelper_Contract.address);

    
    const Referral = await ethers.getContractFactory("Referral");
    const Referral_Contract = await Referral.deploy();
    await Referral_Contract.deployed();
    console.log("Referral :", Referral_Contract.address);
    
    
    const Treasury = await ethers.getContractFactory("Treasury");
    const Treasury_Contract = await Treasury.deploy();
    await Treasury_Contract.deployed();
    console.log("Treasury :", Treasury_Contract.address);

}

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

