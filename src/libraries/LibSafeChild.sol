// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Constants} from "../constants/Constants.sol";
import {IwZRX} from "../interfaces/IwZRX.sol";

interface ISafeProxyFactory {
    function proxyCreationCode() external view returns (bytes memory);
    function createProxyWithNonce(address singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);
}

interface ISafe {
    function setup(
        address[] calldata owners,
        uint256 threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;
    function approveHash(bytes32 hashToApprove) external;
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);
    function nonce() external view returns (uint256);
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 nonce
    ) external view returns (bytes32);
}

library LibSafeChild {
    // Safe v1.3.0 EIP-712 type hashes.
    bytes32 private constant SAFE_TX_TYPEHASH =
        0xbb8310d4860db7303ce6f8cd20104e744dfa5135f2060d0e264a8f2b302c5b48;
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH =
        0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

    function childSafeSaltNonce(address masterSafe, address delegatee)
        internal
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encodePacked(masterSafe, delegatee)));
    }

    function childSafeInitializer(address masterSafe) internal pure returns (bytes memory) {
        address[] memory owners = new address[](1);
        owners[0] = masterSafe;
        return abi.encodeWithSelector(
            ISafe.setup.selector,
            owners,
            1, // threshold
            address(0),
            "",
            address(0),
            address(0),
            0,
            payable(address(0))
        );
    }

    function predictChildSafeAddress(address masterSafe, address delegatee)
        internal
        view
        returns (address)
    {
        bytes memory initializer = childSafeInitializer(masterSafe);
        uint256 saltNonce = childSafeSaltNonce(masterSafe, delegatee);

        ISafeProxyFactory factory = ISafeProxyFactory(Constants.SAFE_PROXY_FACTORY);
        bytes memory proxyCreationCode = factory.proxyCreationCode();

        bytes memory initCode =
            abi.encodePacked(proxyCreationCode, abi.encode(Constants.SAFE_SINGLETON));

        // forge-lint: disable-start(asm-keccak256)
        // Intentionally not hand-rolled: this is the CREATE2 address prediction for
        // the child Safe. A memory-layout bug in inline assembly would send wZRX to
        // an uncontrolled address, so we keep the explicit abi.encodePacked form.
        bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), saltNonce));

        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), Constants.SAFE_PROXY_FACTORY, salt, keccak256(initCode))
        );
        // forge-lint: disable-end(asm-keccak256)

        return address(uint160(uint256(hash)));
    }

    function deployChildSafeCalldata(address masterSafe, address delegatee)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            ISafeProxyFactory.createProxyWithNonce.selector,
            Constants.SAFE_SINGLETON,
            childSafeInitializer(masterSafe),
            childSafeSaltNonce(masterSafe, delegatee)
        );
    }

    function childSafeDelegateTxHash(address childSafe, address delegatee)
        internal
        view
        returns (bytes32)
    {
        uint256 currentNonce = childSafe.code.length > 0 ? ISafe(childSafe).nonce() : 0;
        bytes memory delegateData = abi.encodeWithSelector(IwZRX.delegate.selector, delegatee);

        // forge-lint: disable-start(asm-keccak256)
        // Intentionally not hand-rolled: this is the EIP-712 hash of the child Safe
        // delegate transaction. A bug in inline-assembly hashing would produce an
        // approved-hash signature that execTransaction rejects, so we keep the
        // explicit abi.encode form.
        bytes32 domainSeparator =
            keccak256(abi.encode(DOMAIN_SEPARATOR_TYPEHASH, block.chainid, childSafe));
        bytes32 structHash = keccak256(
            abi.encode(
                SAFE_TX_TYPEHASH,
                Constants.WZRX_TOKEN,
                0,
                keccak256(delegateData),
                uint8(0), // operation Call
                0,
                0,
                0,
                address(0),
                address(0),
                currentNonce
            )
        );

        return keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator, structHash));
        // forge-lint: disable-end(asm-keccak256)
    }

    function approveDelegateHashCalldata(address childSafe, address delegatee)
        internal
        view
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            ISafe.approveHash.selector, childSafeDelegateTxHash(childSafe, delegatee)
        );
    }

    function deployChildSafe(address masterSafe, address delegatee)
        internal
        returns (address childSafe)
    {
        childSafe = ISafeProxyFactory(Constants.SAFE_PROXY_FACTORY)
            .createProxyWithNonce(
                Constants.SAFE_SINGLETON,
                childSafeInitializer(masterSafe),
                childSafeSaltNonce(masterSafe, delegatee)
            );
        require(childSafe != address(0), "Safe child deployment failed");
        require(childSafe.code.length > 0, "Safe child has no code");
    }

    function approveAndExecDelegate(address childSafe, address delegatee, address masterSafe)
        internal
    {
        ISafe(childSafe).approveHash(childSafeDelegateTxHash(childSafe, delegatee));
        (bool success,) = childSafe.call(execDelegateCalldata(childSafe, delegatee, masterSafe));
        require(success, "Safe child delegate execution failed");
    }

    function execDelegateCalldata(
        address,
        /* childSafe */
        address delegatee,
        address masterSafe
    )
        internal
        pure
        returns (bytes memory)
    {
        bytes memory delegateData = abi.encodeWithSelector(IwZRX.delegate.selector, delegatee);

        // Signature for an approved hash: r = owner (masterSafe), s = 0, v = 1.
        bytes memory signatures =
            abi.encodePacked(bytes32(uint256(uint160(masterSafe))), bytes32(0), uint8(1));

        return abi.encodeWithSelector(
            ISafe.execTransaction.selector,
            Constants.WZRX_TOKEN,
            0,
            delegateData,
            0, // operation Call
            0,
            0,
            0,
            address(0),
            address(0),
            signatures
        );
    }
}
