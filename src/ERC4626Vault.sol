// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ERC4626Vault
 * @notice Minimal ERC-4626 compatible tokenized vault
 *
 * @dev
 *  - Users deposit an underlying ERC20 asset
 *  - Vault mints ERC20 "shares" representing ownership
 *  - Share price = totalAssets / totalSupply
 *
 * Security principles:
 *  - Uses SafeERC20 for all token interactions
 *  - Follows Checks-Effects-Interactions (CEI) pattern
 *  - Rounding direction follows ERC-4626 spec
 */
contract ERC4626Vault is ERC20 {
    using SafeERC20 for IERC20;

    /// @notice Underlying asset deposited into the vault
    IERC20 private immutable _asset;

    /// @notice Decimals are inherited from the underlying asset
    uint8 private immutable _decimals;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        _asset = asset_;
        _decimals = ERC20(address(asset_)).decimals();
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT METADATA
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the address of the underlying asset
    function asset() public view virtual returns (address) {
        return address(_asset);
    }

    /// @notice Share token decimals match the underlying asset
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /// @notice Total amount of underlying assets held by the vault
    function totalAssets() public view virtual returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT / MINT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit assets and receive shares
     *
     * CEI pattern:
     *  1. CHECKS   → validate limits
     *  2. EFFECTS  → compute shares
     *  3. INTERACTIONS → transfer tokens + mint shares
     */
    function deposit(uint256 assets, address receiver)
        public
        virtual
        returns (uint256 shares)
    {
        // ---------- CHECKS ----------
        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

        // ---------- EFFECTS ----------
        shares = previewDeposit(assets);

        // ---------- INTERACTIONS ----------
        _deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Mint exact shares by depositing required assets
     */
    function mint(uint256 shares, address receiver)
        public
        virtual
        returns (uint256 assets)
    {
        // ---------- CHECKS ----------
        require(shares <= maxMint(receiver), "ERC4626: mint more than max");

        // ---------- EFFECTS ----------
        assets = previewMint(shares);

        // ---------- INTERACTIONS ----------
        _deposit(msg.sender, receiver, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                    WITHDRAW / REDEEM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraw exact assets by burning shares
     *
     * CEI pattern strictly enforced to prevent reentrancy:
     *  - Shares burned BEFORE token transfer
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual returns (uint256 shares) {
        // ---------- CHECKS ----------
        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");

        // ---------- EFFECTS ----------
        shares = previewWithdraw(assets);

        // ---------- INTERACTIONS ----------
        _withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @notice Redeem exact shares for assets
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual returns (uint256 assets) {
        // ---------- CHECKS ----------
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        // ---------- EFFECTS ----------
        assets = previewRedeem(shares);

        // ---------- INTERACTIONS ----------
        _withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                        ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Converts assets → shares using current exchange rate
     */
    function convertToShares(uint256 assets)
        public
        view
        virtual
        returns (uint256)
    {
        return _convertToShares(assets, false);
    }

    /**
     * @dev Converts shares → assets using current exchange rate
     */
    function convertToAssets(uint256 shares)
        public
        view
        virtual
        returns (uint256)
    {
        return _convertToAssets(shares, false);
    }

    /**
     * @notice Preview functions simulate state without changing it
     * @dev Used by frontends and integrators
     */
    function previewDeposit(uint256 assets)
        public
        view
        virtual
        returns (uint256)
    {
        return _convertToShares(assets, false);
    }

    function previewMint(uint256 shares)
        public
        view
        virtual
        returns (uint256)
    {
        return _convertToAssets(shares, true);
    }

    function previewWithdraw(uint256 assets)
        public
        view
        virtual
        returns (uint256)
    {
        return _convertToShares(assets, true);
    }

    function previewRedeem(uint256 shares)
        public
        view
        virtual
        returns (uint256)
    {
        return _convertToAssets(shares, false);
    }

    /*//////////////////////////////////////////////////////////////
                        LIMITS (NO RESTRICTIONS)
    //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner)
        public
        view
        virtual
        returns (uint256)
    {
        return _convertToAssets(balanceOf(owner), false);
    }

    function maxRedeem(address owner)
        public
        view
        virtual
        returns (uint256)
    {
        return balanceOf(owner);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL CONVERSION HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev assets → shares
     *
     * Rounding:
     *  - roundUp = true  → user pays slightly more
     *  - roundUp = false → user receives slightly less
     */
    function _convertToShares(uint256 assets, bool roundUp)
        internal
        view
        virtual
        returns (uint256)
    {
        uint256 supply = totalSupply();

        // Initial deposit: 1:1 ratio
        if (supply == 0) return assets;

        uint256 totalAssets_ = totalAssets();
        if (totalAssets_ == 0) return assets;

        return roundUp
            ? (assets * supply + totalAssets_ - 1) / totalAssets_
            : (assets * supply) / totalAssets_;
    }

    /**
     * @dev shares → assets
     */
    function _convertToAssets(uint256 shares, bool roundUp)
        internal
        view
        virtual
        returns (uint256)
    {
        uint256 supply = totalSupply();
        if (supply == 0) return shares;

        uint256 totalAssets_ = totalAssets();

        return roundUp
            ? (shares * totalAssets_ + supply - 1) / supply
            : (shares * totalAssets_) / supply;
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL STATE-CHANGING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal deposit
     *
     * CEI:
     *  - External call AFTER minting is safe because:
     *    - ERC20 mint has no external hooks
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual {
        // INTERACTION
        _asset.safeTransferFrom(caller, address(this), assets);

        // EFFECT
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Internal withdraw
     *
     * CEI strictly followed:
     *  1. Allowance check
     *  2. Burn shares (effect)
     *  3. Transfer assets (interaction)
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual {
        // CHECK
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // EFFECT
        _burn(owner, shares);

        // INTERACTION
        _asset.safeTransfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
