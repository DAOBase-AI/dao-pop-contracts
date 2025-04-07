import {ethers} from "hardhat";
import LockerAbi from '../artifacts/contracts/LpLocker.sol/LpLocker.json';
import BondingCurveAbi from '../artifacts/contracts/BondingCurve.sol/BondingCurve.json';
import BondingCurveHelper from '../artifacts/contracts/BondingCurveHelper.sol/BondingCurveHelper.json';
import ReferralAbi from '../artifacts/contracts/Referral.sol/Referral.json';

async function main() {

    const [signer] = await ethers.getSigners();

    const  _baseToken = "0x00D2BA95E1e61661ec76f43503DEC49e0E839F73";
    const  _uniswapV3Factory = "0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24";
    const  _positionManager = "0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2";
    const  _treasury = "0x7FfDB03888Bd6E3BD8b5EC2706f36a9122328590";
    const  _inviter = "0x7FfDB03888Bd6E3BD8b5EC2706f36a9122328590";


    const  _bondingCurveUtil = "0x0E3e0AFE43522a7d4E00c99bBBe467627AeB6a82";
    const  _lockLPAddress = "0xaDdeAe073B5a4bb8914d11D0171044aa7181DC71";
    const  _tokenImplementation = "0x64AF76461E8C8D23B19D888735C010e11A4a7b0e";
    const  _bondingCurveAddress = "0x9C0504F880D32e2607488cec33539b63968De1Ed";
    const  _bondingCurveHelperAddress = "0x2C8D8dD4DE44c585d8b2076AD912994134374250";
    const  _referralCa = "0x77dedBd6CE1B6d0097B64799D82cF066f08dBD6A";

    const bigNumber = ethers.BigNumber.from;

    const bondingCurveParam = {
        maxSupply: ethers.utils.parseUnits("1000000000", 18),
        fundingSupply: ethers.utils.parseUnits("733058550", 18),
        initialSupply: ethers.utils.parseUnits("266941450", 18),
        fundingGoal: bigNumber("2048733358").mul(20000).mul(bigNumber("10").pow(9)),
        creationFee: ethers.utils.parseUnits("0.002", 18).mul(20000),
        liquidityFee: ethers.utils.parseUnits("0.1", 18).mul(20000),
        creatorReward: ethers.utils.parseUnits("0.01", 18).mul(20000),
        referralFeePercent: 5000,
        feePercent: 100,
        A: ethers.utils.parseUnits("1126650200", 18),
        B: bigNumber("1239315220").mul(20000).mul(bigNumber("10").pow(18)),
        C: ethers.utils.parseUnits("1.1", 18).mul(20000)
    };
    const version = 1;

    const active = true;


    const BondingCurveAbi_Contract = new ethers.Contract(_bondingCurveAddress, BondingCurveAbi.abi, signer);
    await BondingCurveAbi_Contract.setAddresses(_tokenImplementation,_baseToken,_uniswapV3Factory
        ,_positionManager,_treasury,_lockLPAddress,_referralCa,_bondingCurveUtil);
    console.log("BondingCurveAbi_Contract setAddresses  ");

    await BondingCurveAbi_Contract.setParam(version, bondingCurveParam, active);
    console.log("BondingCurveAbi_Contract setParam ");

    const LpLocker_Contract = new ethers.Contract(_lockLPAddress, LockerAbi.abi, signer);
    await LpLocker_Contract.setAddresses(_treasury,_inviter,_positionManager,_bondingCurveAddress);
    console.log("LpLocker_Contract setAddresses  ");

    const BondingCurveHelper_Contract = new ethers.Contract(_bondingCurveHelperAddress, BondingCurveHelper.abi, signer);

    await BondingCurveHelper_Contract.setAddresses( _bondingCurveAddress, _bondingCurveUtil, _uniswapV3Factory);
    console.log("BondingCurveHelper_Contract setAddresses  ");
    //
    const Referral_Contract = new ethers.Contract(_referralCa, ReferralAbi.abi, signer);
    await Referral_Contract.addToWhitelist( _bondingCurveAddress);
    console.log("Referral_Contract setAddresses  ");

}

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

