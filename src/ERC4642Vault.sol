//SPDX-License-Identifier:MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
@title ERC4642 Tokenized Vault
@notice A tokenized Vault that allows user to deposit assest and recieve shares
@dev Implements the ERC4642 standard
*/

contract ERC4642Vault is ERC20{
    using SafeERC20 for IERC20;
    
    IERC20 private immutable _asset;
    uint8 private immutable _decimals;

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_
    )ERC20(name_,symbol_){
        _asset=asset_;
        _decimals = ERC20(address(asset_)).decimals();
    }

    //ASSET MANAGEMENT
    function asset() public view virtual returns(address){
        return address(_asset);
    }

    function decimals()public view virtual override returns(uint8){
        return _decimals;
    }

    function totalAssets() public view virtual returns (uint256){
        return _asset.balanceOf(address(this));
    }

    //Deposit
    function deposit(uint256 assets,address reciever)public virtual returns(uint256 shares){
        require(assets <= maxDeposit(reciever),"ERC4642:deposit more than max");

        shares= previewDeposit(assets);
        _deposit(msg.sender,reciever,assests,shares);
        
        return shares;
    }

    function mint(uint256 shares,address reciever)public virtual returns(uint256 assets){
        require(shares<=maxMint(reciever),"ERC4642:mint more than max");

        assets=previewMint(shares);
        _deposit()
    }
}