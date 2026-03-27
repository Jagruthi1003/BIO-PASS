pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";

template FaceVerify() {
    // Public inputs
    signal input existingCommitment;
    signal input threshold; // Squared distance threshold

    // Private inputs
    signal input registeredEmbedding[128];
    signal input newEmbedding[128];
    signal input salt;

    // Signals for intermediate calculations
    signal embeddingHash;
    signal distanceSquared;

    // ============ Step 1: Hash the registered embedding with salt ============
    component poseidonHasher = Poseidon(129); // 128 embedding values + 1 salt
    
    for (var i = 0; i < 128; i++) {
        poseidonHasher.inputs[i] <== registeredEmbedding[i];
    }
    poseidonHasher.inputs[128] <== salt;
    
    embeddingHash <== poseidonHasher.out;

    // Verify that the hash matches the existingCommitment
    embeddingHash === existingCommitment;

    // ============ Step 2: Calculate squared Euclidean distance ============
    // distance^2 = sum((registeredEmbedding[i] - newEmbedding[i])^2)
    
    component differenceSquared[128];
    signal differences[128];
    signal diffSquares[128];
    
    var accumulatedDistance = 0;
    
    for (var i = 0; i < 128; i++) {
        differences[i] <== registeredEmbedding[i] - newEmbedding[i];
        diffSquares[i] <== differences[i] * differences[i];
        accumulatedDistance = accumulatedDistance + diffSquares[i];
    }
    
    distanceSquared <== accumulatedDistance;

    // ============ Step 3: Verify distance is less than threshold ============
    // We use a LessThan comparator to ensure the distance is within acceptable bounds
    component isDistanceLess = LessThan(252);
    isDistanceLess.in[0] <== distanceSquared;
    isDistanceLess.in[1] <== threshold;
    
    // The output must be 1 (true)
    isDistanceLess.out === 1;
}

component main {public [existingCommitment, threshold]} = FaceVerify();
