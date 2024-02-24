pragma solidity 0.8.10;
import { WadRayMath } from "./libraries/WadRayMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VdToken is ERC20 {
	constructor(
		string memory name_,
		string memory symbol_
	) ERC20(name_, symbol_) {}

	function mint(address user, uint256 amount) external returns (bool) {
		_mint(user, amount);
		return true;
	}

	function burn(address user, uint256 amount) external {
		_burn(user, amount);
	}
}
