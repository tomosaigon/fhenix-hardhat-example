// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

// Forked from: PWN Vault
contract Vault is IERC721Receiver {
    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /**
     * @notice Emitted when asset transfer happens from an `origin` address to a vault.
     */
    event VaultPull(address indexed asset, uint256 indexed id, address indexed origin);

    /**
     * @notice Emitted when asset transfer happens from a vault to a `beneficiary` address
     */
    event VaultPush(address indexed asset, uint256 indexed id, address indexed beneficiary);

    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /**
     * @notice Thrown when the Vault receives an asset that is not transferred by the Vault itself.
     */
    error UnsupportedTransferFunction();

    /**
     * @notice Thrown when an asset transfer is incomplete.
     */
    error IncompleteTransfer();

    /*----------------------------------------------------------*|
    |*  # TRANSFER FUNCTIONS                                    *|
    |*----------------------------------------------------------*/

    function _pullERC721(address asset, uint256 id, address origin) internal {
        uint256 originalBalance = balanceOf(asset, id, address(this));

        IERC721(asset).transferFrom(origin, address(this), id);
        _checkTransfer(asset, id, originalBalance, address(this), true);

        emit VaultPull(asset, id, origin);
    }

    function _pushERC721(address asset, uint256 id, address beneficiary) internal {
        uint256 originalBalance = balanceOf(asset, id, beneficiary);

        IERC721(asset).safeTransferFrom(address(this), beneficiary, id, "");
        _checkTransfer(asset, id, originalBalance, beneficiary, true);

        emit VaultPush(asset, id, beneficiary);
    }

    function _checkTransfer(
        address asset,
        uint256 id,
        uint256 originalBalance,
        address checkedAddress,
        bool checkIncreasingBalance
    )
        private
        view
    {
        uint256 expectedBalance = checkIncreasingBalance ? originalBalance + 1 : originalBalance - 1;

        if (expectedBalance != balanceOf(asset, id, checkedAddress)) {
            revert IncompleteTransfer();
        }
    }

    /*----------------------------------------------------------*|
    |*  # BALANCE OF                                            *|
    |*----------------------------------------------------------*/

    function balanceOf(address asset, uint256 id, address target) public view returns (uint256) {
        return IERC721(asset).ownerOf(id) == target ? 1 : 0;
    }

    /*----------------------------------------------------------*|
    |*  # ERC721/1155 RECEIVED HOOKS                            *|
    |*----------------------------------------------------------*/

    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be
     * reverted.
     *
     * @return `IERC721Receiver.onERC721Received.selector` if transfer is allowed
     */
    function onERC721Received(
        address operator,
        address, /*from*/
        uint256, /*tokenId*/
        bytes calldata /*data*/
    )
        external
        view
        override
        returns (bytes4)
    {
        if (operator != address(this)) {
            revert UnsupportedTransferFunction();
        }

        return IERC721Receiver.onERC721Received.selector;
    }

    /*----------------------------------------------------------*|
    |*  # SUPPORTED INTERFACES                                  *|
    |*----------------------------------------------------------*/

    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId;
    }
}