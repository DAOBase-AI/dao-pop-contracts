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
    const  _swapRouter02 = "0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4";
    const  _feePercent = 100;
    const  _treasury = "0x7FfDB03888Bd6E3BD8b5EC2706f36a9122328590";
    const  _inviter = "0x7FfDB03888Bd6E3BD8b5EC2706f36a9122328590";

    const  _bondingCurveUtil = "0xA23d80e0523821fD174BD4c9CdFc7e2E948864EB";
    const  _lockLPAddress = "0xB667b92764195e21449f1CA3e936E3678594433b";
    const  _tokenImplementation = "0x734385eb2A597239e1e27D2956028Ca85000e9c2";
    const  _bondingCurveAddress = "0x0B68bA03e9081418720b424d130Cb4Cb302B8cf3";
    const  _bondingCurveHelperAddress = "0xaA669B06D899951283BD51B417c1042Db9c0aF9F";
    const  _referralCa = "0x77dedBd6CE1B6d0097B64799D82cF066f08dBD6A";
    const  _treasuryAddress = "0x0A05E09906E786C93a883D1e7b4a199c2D5EE598";


    const BondingCurveAbi_Contract = new ethers.Contract(_bondingCurveAddress, BondingCurveAbi.abi, signer);

    await BondingCurveAbi_Contract.setAddresses(_tokenImplementation,_treasuryAddress,_baseToken,_uniswapV3Factory
        ,_positionManager,_swapRouter02,_bondingCurveUtil,_feePercent,_treasury,_lockLPAddress,_referralCa);
    console.log("BondingCurveAbi_Contract setAddresses  ");

    const LpLocker_Contract = new ethers.Contract(_lockLPAddress, LockerAbi.abi, signer);

    await LpLocker_Contract.setAddresses(_treasury,_inviter,_positionManager,_bondingCurveAddress);
    console.log("LpLocker_Contract setAddresses  ");

    const BondingCurveHelper_Contract = new ethers.Contract(_bondingCurveHelperAddress, BondingCurveHelper.abi, signer);

    await BondingCurveHelper_Contract.setAddresses( _bondingCurveAddress, _bondingCurveUtil, _uniswapV3Factory);
    console.log("BondingCurveHelper_Contract setAddresses  ");


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

