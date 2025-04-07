import {ethers} from "hardhat";
import LockerAbi from '../artifacts/contracts/LpLocker.sol/LpLocker.json';
import BondingCurveAbi from '../artifacts/contracts/BondingCurve.sol/BondingCurve.json';
import BondingCurveHelper from '../artifacts/contracts/BondingCurveHelper.sol/BondingCurveHelper.json';

async function main() {

    const [signer] = await ethers.getSigners();

    const  _WETH = "0xfff9976782d46cc05630d1f6ebab18b2324d6b14";
    const  _uniswapV3Factory = "0x0227628f3F023bb0B980b67D528571c95c6DaC1c";
    const  _positionManager = "0x1238536071E1c677A632429e3655c799b22cDA52";
    const  _feePercent = 100;
    const  _treasury = "0x7FfDB03888Bd6E3BD8b5EC2706f36a9122328590";
    const  _inviter = "0x7FfDB03888Bd6E3BD8b5EC2706f36a9122328590";

    const  _bondingCurveUtil = "0x32919e18460A1f0cc3Cc5095060fE5E07f774a03";
    const  _lockLPAddress = "0xA5f80fA4506e750Cf73fb990843637866e5daDfd";
    const  _tokenImplementation = "0xa0caAacebc5DaF1f5EE3802751EBe84B2352a9c5";
    const  _bondingCurveAddress = "0x8c19caCD0520E56188c35CF060Eee89411e4F9B7";
    const  _bondingCurveHelperAddress = "0x2F26f18ebe52dED22B79071BA5a2305CD5c07c75";


    const BondingCurveAbi_Contract = new ethers.Contract(_bondingCurveAddress, BondingCurveAbi.abi, signer);

    await BondingCurveAbi_Contract.setAddresses(_tokenImplementation,_WETH,_uniswapV3Factory
        ,_positionManager,_bondingCurveUtil,_feePercent,_treasury,_lockLPAddress);
    console.log("BondingCurveAbi_Contract setAddresses  ");

    const LpLocker_Contract = new ethers.Contract(_lockLPAddress, LockerAbi.abi, signer);

    await LpLocker_Contract.setAddresses(_treasury,_inviter,_positionManager,_bondingCurveAddress);
    console.log("LpLocker_Contract setAddresses  ");

    const BondingCurveHelper_Contract = new ethers.Contract(_bondingCurveHelperAddress, BondingCurveHelper.abi, signer);

    await BondingCurveHelper_Contract.setAddresses( _bondingCurveAddress, _bondingCurveUtil, _uniswapV3Factory);
    console.log("BondingCurveHelper_Contract setAddresses  ");


}

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

