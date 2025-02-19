// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import the PumpForgeToken contract that this factory will deploy.
import "./PumpForgeToken.sol";
// Import OpenZeppelin's ReentrancyGuard for protection against reentrancy attacks.
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title PumpForgeFactory
 * @notice Factory contract for deploying new PumpForgeToken instances.
 * Users can create their own tokens by providing custom parameters.
 *
 * Features:
 * - Deploys new Celo-specific PumpForgeToken contracts.
 * - Transfers ownership of the deployed token to the creator.
 * - Maintains a registry of all deployed tokens, indexed both globally and by creator.
 * - Uses ReentrancyGuard to protect against reentrancy attacks during token creation.
 *
 * This implementation follows best industry practices and is designed for production readiness.
 */
contract PumpForgeFactory is ReentrancyGuard {
    // Array to store addresses of all deployed PumpForgeToken contracts.
    address[] private allTokens;
    
    // Mapping from creator address to an array of token addresses they have deployed.
    mapping(address => address[]) private tokensByCreator;
    
    // Event emitted when a new token is created.
    event TokenCreated(
        address indexed creator,
        address indexed tokenAddress,
        string tokenName,
        string tokenSymbol,
        string tokenImageHash
    );

    /**
     * @notice Deploys a new PumpForgeToken contract instance.
     * @param _name The desired name for the token. Must be non-empty.
     * @param _symbol The desired token symbol. Must be non-empty.
     * @param _tokenImageHash The IPFS hash or URL for the token's image. Must be non-empty.
     *
     * Requirements:
     * - All parameters must be provided as non-empty strings.
     * - This function is non-reentrant.
     */
    function createToken(
        string memory _name, 
        string memory _symbol, 
        string memory _tokenImageHash
    ) external nonReentrant {
        // Validate inputs
        require(bytes(_name).length > 0, "PumpForgeFactory: token name required");
        require(bytes(_symbol).length > 0, "PumpForgeFactory: token symbol required");
        require(bytes(_tokenImageHash).length > 0, "PumpForgeFactory: token image hash required");
        
        // Deploy a new PumpForgeToken instance with the provided parameters.
        // Note: The factory is the deployer, so the token's constructor will mint tokens to this contract.
        PumpForgeToken newToken = new PumpForgeToken(_name, _symbol, _tokenImageHash);
        
        // Transfer ownership of the token contract to the caller (creator).
        newToken.transferOwnership(msg.sender);
        
        // Record the deployed token's address in our registry.
        allTokens.push(address(newToken));
        tokensByCreator[msg.sender].push(address(newToken));
        
        // Emit an event for the front-end or off-chain indexers.
        emit TokenCreated(msg.sender, address(newToken), _name, _symbol, _tokenImageHash);
    }
    
    /**
     * @notice Returns the total number of PumpForgeToken contracts deployed via this factory.
     * @return The total count of deployed tokens.
     */
    function getTotalTokens() external view returns (uint256) {
        return allTokens.length;
    }
    
    /**
     * @notice Returns the list of token addresses deployed by a specific creator.
     * @param creator The address of the token creator.
     * @return An array of token contract addresses.
     */
    function getTokensByCreator(address creator) external view returns (address[] memory) {
        return tokensByCreator[creator];
    }

    /**
     * @notice Returns the list of all PumpForgeToken contract addresses deployed by the factory.
     * @return An array of all token contract addresses.
     */
    function getAllTokens() external view returns (address[] memory) {
        return allTokens;
    }
}
