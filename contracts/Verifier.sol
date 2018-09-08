// this code is taken from https://github.com/JacobEberhardt/ZoKrates 

pragma solidity ^0.4.24;

import "./Pairing.sol";

contract Verifier {
    using Pairing for *;
    event Verified(string);
    uint sealed;
    uint i;

    struct VerifyingKey {
        Pairing.G2Point A;
        Pairing.G1Point B;
        Pairing.G2Point C;

        Pairing.G2Point gamma;
        Pairing.G1Point gammaBeta1;
        Pairing.G2Point gammaBeta2;

        Pairing.G2Point Z;

        Pairing.G1Point[] IC; // IC is an array of (x,y) points on G1
    }

    struct Proof {
        Pairing.G1Point A;
        Pairing.G1Point A_p;
        Pairing.G2Point B;
        Pairing.G1Point B_p;
        Pairing.G1Point C;
        Pairing.G1Point C_p;
        Pairing.G1Point K;
        Pairing.G1Point H;
    }

    VerifyingKey verifyKey;

    // Initialize parameters of the verifier. All generated from libsnark, we
    // pass them from the generated json file (`contract_deploy.py`)
    // Docs on why verifyKey is constructed like that?
    constructor (
        uint[2] A1, 
        uint[2] A2, 
        uint[2] B, 
        uint[2] C1, 
        uint[2] C2,
        uint[2] gamma1,
        uint[2] gamma2,
        uint[2] gammaBeta1, 
        uint[2] gammaBeta2_1,
        uint[2] gammaBeta2_2,
        uint[2] Z1,
        uint[2] Z2) 
        {
            // A.X = A1, A.Y = A2
            verifyKey.A = Pairing.G2Point(A1,A2);
            // B.X = B[0], B.Y = B[1]
            verifyKey.B = Pairing.G1Point(B[0], B[1]);
            // C.X = C1, C.Y = C2
            verifyKey.C = Pairing.G2Point(C1, C2);

            verifyKey.gamma = Pairing.G2Point(gamma1, gamma2);
            verifyKey.gammaBeta1 = Pairing.G1Point(gammaBeta1[0], gammaBeta1[1]);
            verifyKey.gammaBeta2 = Pairing.G2Point(gammaBeta2_1, gammaBeta2_2);
            verifyKey.Z = Pairing.G2Point(Z1,Z2);
        }

        // Input is of the form (input[i], input[i+1]) where each pair is a
        // G1 Point
        function addIC(uint[] input) {  
            require(sealed ==0);
            while (verifyKey.IC.length != input.length/2 && msg.gas > 200000) {
                verifyKey.IC.push(Pairing.G1Point(input[i], input[i+1]));
                i += 2;
            } 
            if (verifyKey.IC.length == input.length/2) {
                sealed = 1;
            }
        } 

        function getIC(uint i) returns(uint, uint) {
            return(verifyKey.IC[i].X, verifyKey.IC[i].Y);
        }

        function getICLen() returns (uint) { 
            return(verifyKey.IC.length);
        } 

        function verify(uint[] input, Proof proof) internal returns (uint) {
            VerifyingKey memory vk = verifyKey;
            require(input.length + 1 == vk.IC.length);

            // Compute the linear combination vk_x
            Pairing.G1Point memory vk_x = Pairing.G1Point(0, 0);
            for (uint i = 0; i < input.length; i++) {
                vk_x = Pairing.add(
                    vk_x, 
                    Pairing.mul(vk.IC[i + 1], input[i])
                );
            }
            vk_x = Pairing.add(vk_x, vk.IC[0]);

            bool pairing;

            pairing = Pairing.pairingProd2(
                proof.A, 
                vk.A, 
                Pairing.negate(proof.A_p), 
                Pairing.P2()
            );
            if (!pairing) { return 1; }

            pairing = Pairing.pairingProd2(
                vk.B, 
                proof.B, 
                Pairing.negate(proof.B_p), 
                Pairing.P2()
            );
            if (!pairing) { return 2; }

            pairing = Pairing.pairingProd2(
                proof.C, 
                vk.C, 
                Pairing.negate(proof.C_p), 
                Pairing.P2()
            );
            if (!pairing) { return 3; }


            pairing = Pairing.pairingProd3(
                proof.K, 
                vk.gamma,
                Pairing.negate(
                    Pairing.add(vk_x, Pairing.add(proof.A, proof.C))
                ), 
                vk.gammaBeta2,
                Pairing.negate(vk.gammaBeta1), 
                proof.B
            ); 
            if (!pairing) { return 4; }

            pairing = Pairing.pairingProd3(
                Pairing.add(vk_x, proof.A), 
                proof.B,
                Pairing.negate(proof.H), 
                vk.Z,
                Pairing.negate(proof.C), 
                Pairing.P2()
            );
            if (!pairing) { return 5; } 

            return 0;
        }

        function verifyTx(
            uint[2] a,
            uint[2] a_p,
            uint[2][2] b,
            uint[2] b_p,
            uint[2] c,
            uint[2] c_p,
            uint[2] h,
            uint[2] k,
            uint[] input
        ) 
        returns (bool) 
        {
            Proof memory proof;
            proof.A = Pairing.G1Point(a[0], a[1]);
            proof.A_p = Pairing.G1Point(a_p[0], a_p[1]);
            proof.B = Pairing.G2Point([b[0][0], b[0][1]], [b[1][0], b[1][1]]);
            proof.B_p = Pairing.G1Point(b_p[0], b_p[1]);
            proof.C = Pairing.G1Point(c[0], c[1]);
            proof.C_p = Pairing.G1Point(c_p[0], c_p[1]);
            proof.H = Pairing.G1Point(h[0], h[1]);
            proof.K = Pairing.G1Point(k[0], k[1]);

            if (verify(input, proof) == 0) {
                emit Verified("Transaction successfully verified.");
                return true;
            } else {
                return false;
            }

        } 
}
