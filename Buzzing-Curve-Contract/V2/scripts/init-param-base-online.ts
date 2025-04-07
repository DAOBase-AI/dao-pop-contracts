import {ethers} from "hardhat";
import LockerAbi from '../artifacts/contracts/LpLocker.sol/LpLocker.json';
import BondingCurveAbi from '../artifacts/contracts/BondingCurve.sol/BondingCurve.json';
import BondingCurveHelper from '../artifacts/contracts/BondingCurveHelper.sol/BondingCurveHelper.json';

async function main() {

    const [signer] = await ethers.getSigners();

    const  _WETH = "0x4200000000000000000000000000000000000006";
    const  _uniswapV3Factory = "0x33128a8fC17869897dcE68Ed026d694621f6FDfD";
    const  _positionManager = "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1";
    const  _feePercent = 100;
    const  _treasury = "0xB1Aad75E75463041ef73aC3cBf72CC131A99ac51";
    const  _bondingCurveFee = "0x79d91b007E81015faEC497F8c654826f550A6537";

    const  _bondingCurveUtil = "0x7D7DD204b4104057b8Bd141b0b14F22f3d3D5F77";
    const  _lockLPAddress = "0x1391A4B8295243f92eA05dd7bd60e7026a36b960";
    const  _tokenImplementation = "0xc2e21d0a45cB3b1dC3E70CeD5E4203F8d3E2150A";
    const  _bondingCurveAddress = "0x43b97b95772f154c00196Fe84cb3352a71fFF274";
    const  _bondingCurveHelperAddress = "0xeF6925281D188E88cB54ad8eF111C10991dcac38";


    const BondingCurveAbi_Contract = new ethers.Contract(_bondingCurveAddress, BondingCurveAbi.abi, signer);

    await BondingCurveAbi_Contract.setAddresses(_tokenImplementation,_WETH,_uniswapV3Factory
        ,_positionManager,_bondingCurveUtil,_feePercent,_bondingCurveFee,_lockLPAddress);
    console.log("BondingCurveAbi_Contract setAddresses  ");

    const LpLocker_Contract = new ethers.Contract(_lockLPAddress, LockerAbi.abi, signer);

    await LpLocker_Contract.setAddresses(_treasury,_treasury,_positionManager,_bondingCurveAddress);
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

