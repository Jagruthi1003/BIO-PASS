pragma circom 2.0.0;

include "../zk_backend/node_modules/circomlib/circuits/poseidon.circom";
include "../zk_backend/node_modules/circomlib/circuits/comparators.circom";

template ZKFaceAuth() {
    // Public Inputs
    signal input stored_hash;
    signal input threshold;
    signal input challenge; // Cryptographic nonce to prevent replay attacks

    // Private Inputs
    signal input reg_embedding[128];
    signal input live_embedding[128];
    
    // Output
    signal output auth_valid;

    // ==========================================
    // Constraint 1: Integrity (Poseidon Hash)
    // ==========================================
    // We cannot use Poseidon(128) directly since the maximum inputs for standard Poseidon is 16.
    // We build a simple Merkle-tree-like structure (2 levels: 8 leaves of 16 inputs each).
    
    // Level 1: 8 hashers, each taking 16 elements.
    component leafHashers[8];
    for (var i = 0; i < 8; i++) {
        leafHashers[i] = Poseidon(16);
        for (var j = 0; j < 16; j++) {
            leafHashers[i].inputs[j] <== reg_embedding[i * 16 + j];
        }
    }
    
    // Level 2: 1 hasher taking the 8 outputs from Level 1.
    component rootHasher = Poseidon(8);
    for (var i = 0; i < 8; i++) {
        rootHasher.inputs[i] <== leafHashers[i].out;
    }
    
    // Constrain the hash to match the public stored_hash
    rootHasher.out === stored_hash;

    // ==========================================
    // Constraint 2: Biometric Match 
    // (Squared Euclidean Distance)
    // ==========================================
    signal diff[128];
    signal diffSq[128];
    signal sumSq[129];
    
    sumSq[0] <== 0;
    
    for (var i = 0; i < 128; i++) {
        diff[i] <== reg_embedding[i] - live_embedding[i];
        diffSq[i] <== diff[i] * diff[i];
        sumSq[i+1] <== sumSq[i] + diffSq[i];
    }
    
    signal D2;
    D2 <== sumSq[128];

    // ==========================================
    // Constraint 3: Threshold Verification
    // ==========================================
    // We use LessEqThan(32) to ensure D2 <= threshold.
    // D2 fits in 32 bits since 128 * (255)^2 is around 8.3 million, 
    // which is well within the 4 billion limit of 32 bits.
    component isLessEq = LessEqThan(32);
    isLessEq.in[0] <== D2;
    isLessEq.in[1] <== threshold;
    isLessEq.out === 1; // It must be <= threshold
    
    // ==========================================
    // Constraint 4: Liveness/Challenge Binding
    // ==========================================
    // Hash the challenge with a successful match indicator (1)
    // This cryptographically binds the proof to the session securely
    component challengeHasher = Poseidon(2);
    challengeHasher.inputs[0] <== challenge;
    challengeHasher.inputs[1] <== 1;
    
    auth_valid <== challengeHasher.out;
}

// Instantiate the component with appropriate public inputs
component main {public [stored_hash, threshold, challenge]} = ZKFaceAuth();
