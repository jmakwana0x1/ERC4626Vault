// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ERC4626 Tokenized Vault
 * @notice A tokenized vault that allows users to deposit assets and receive shares
 * @dev Implements the ERC-4626 standard
 */
contract ERC4626Vault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 private immutable _asset;
    uint8 private immutable _decimals;

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        _asset = asset_;
        _decimals = ERC20(address(asset_)).decimals();
    }

    // ========== ASSET MANAGEMENT ==========

    function asset() public view virtual returns (address) {
        return address(_asset);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function totalAssets() public view virtual returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    // ========== DEPOSIT/MINT ==========

    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

        shares = previewDeposit(assets);
        _deposit(msg.sender, receiver, assets, shares);

        return shares;
    }

    function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
        require(shares <= maxMint(receiver), "ERC4626: mint more than max");

        assets = previewMint(shares);
        _deposit(msg.sender, receiver, assets, shares);

        return assets;
    }

    // ========== WITHDRAW/REDEEM ==========

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual returns (uint256 shares) {
        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");

        shares = previewWithdraw(assets);
        _withdraw(msg.sender, receiver, owner, assets, shares);

        return shares;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual returns (uint256 assets) {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        assets = previewRedeem(shares);
        _withdraw(msg.sender, receiver, owner, assets, shares);

        return assets;
    }

    // ========== ACCOUNTING ==========

    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, false);
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, false);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, false);
    }

    function previewMint(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, true);
    }

    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, true);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, false);
    }

    // ========== DEPOSIT/WITHDRAWAL LIMITS ==========

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return _convertToAssets(balanceOf(owner), false);
    }

    function maxRedeem(address owner) public view virtual returns (uint256) {
        return balanceOf(owner);
    }

    // ========== INTERNAL FUNCTIONS ==========

    function _convertToShares(uint256 assets, bool roundUp) internal view virtual returns (uint256) {
        uint256 supply = totalSupply();
        
        if (supply == 0) {
            return assets;
        }

        uint256 totalAssets_ = totalAssets();
        if (totalAssets_ == 0) {
            return assets;
        }

        if (roundUp) {
            return (assets * supply + totalAssets_ - 1) / totalAssets_;
        } else {
            return (assets * supply) / totalAssets_;
        }
    }

    function _convertToAssets(uint256 shares, bool roundUp) internal view virtual returns (uint256) {
        uint256 supply = totalSupply();
        
        if (supply == 0) {
            return shares;
        }

        uint256 totalAssets_ = totalAssets();

        if (roundUp) {
            return (shares * totalAssets_ + supply - 1) / supply;
        } else {
            return (shares * totalAssets_) / supply;
        }
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual {
        _asset.safeTransferFrom(caller, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}