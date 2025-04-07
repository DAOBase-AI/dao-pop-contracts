import {ethers} from "hardhat";
import LockerAbi from '../artifacts/contracts/LpLocker.sol/LpLocker.json';
import BondingCurveAbi from '../artifacts/contracts/BondingCurve.sol/BondingCurve.json';
import BondingCurveHelper from '../artifacts/contracts/BondingCurveHelper.sol/BondingCurveHelper.json';
import ReferralAbi from '../artifacts/contracts/Referral.sol/Referral.json';


async function main() {

    const [signer] = await ethers.getSigners();

    const  _WETH = "0x4200000000000000000000000000000000000006";
    const  _uniswapV3Factory = "0x33128a8fC17869897dcE68Ed026d694621f6FDfD";
    const  _positionManager = "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1";
    const  _swapRouter02 = "0x2626664c2603336E57B271c5C0b26F421741e481";

    const  _feePercent = 100;
    const  _treasury = "0xB1Aad75E75463041ef73aC3cBf72CC131A99ac51";
    const  _bondingCurveFee = "0x79d91b007E81015faEC497F8c654826f550A6537";

    const  _bondingCurveUtil = "0x1443BeF262eB7Dce2c06f0913403eAEA3130FA49";
    const  _lockLPAddress = "0x946BBdA51F96dFbb9e6AEbbe86B119e964Aad2f4";
    const  _tokenImplementation = "0x9d83A0529a7a7991c01a03c88ce75e5CF1C9B23C";
    const  _bondingCurveAddress = "0xD0F96132313E84f86Ca057b3092E1614a6D5638C";
    const  _bondingCurveHelperAddress = "0x4F020a547cA3c98013FD2FA1b4B8561c40CFAF61";
    const  _referralCa = "0x38eF38520B6109fe33FA9f931146266D46064deA";
    const  _treasuryAddress = "0xb4CB585a92F876eEfa27E3cEbB8bB62217E60dE1";


    const BondingCurveAbi_Contract = new ethers.Contract(_bondingCurveAddress, BondingCurveAbi.abi, signer);

    await BondingCurveAbi_Contract.setAddresses(_tokenImplementation,_treasuryAddress,_WETH,_uniswapV3Factory
        ,_positionManager,_swapRouter02,_bondingCurveUtil,_feePercent,_treasury,_lockLPAddress,_referralCa);
    console.log("BondingCurveAbi_Contract setAddresses  ");

    const LpLocker_Contract = new ethers.Contract(_lockLPAddress, LockerAbi.abi, signer);

    await LpLocker_Contract.setAddresses(_treasury,_bondingCurveFee,_positionManager,_bondingCurveAddress);
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

