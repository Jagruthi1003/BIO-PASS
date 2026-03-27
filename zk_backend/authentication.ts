/**
 * authentication.ts - Handle ZK proof generation for face authentication
 * 
 * During authentication:
 * 1. User provides a new face embedding
 * 2. Client has the registered embedding and salt (from secure storage)
 * 3. Generate a ZK proof that proves:
 *    - The hash of registered embedding matches stored commitment
 *    - The new embedding is within distance threshold
 * 4. Send proof and public signals to server for verification
 */

import { groth16 } from "snarkjs";
import { quantizeEmbedding, calculateQuantizedDistance } from "./quantize";
import { hexToBigInt, bigIntToHex, computeRegistrationCommitment } from "./registration";
import fs from "fs";
import path from "path";

/**
 * Interface for proof generation inputs
 */
export interface ProofInputs {
    registeredEmbedding: bigint[]; // Quantized registered embedding
    newEmbedding: bigint[]; // Quantized new embedding
    existingCommitment: bigint; // Stored commitment (stored_hash)
    threshold: bigint; // Distance threshold
    challenge: bigint; // Unique challenge
}

/**
 * Interface for generated proof
 */
export interface GeneratedProof {
    proof: any; // SnarkJS proof object
    publicSignals: string[]; // Public signals as strings
}

/**
 * Interface for proof verification result
 */
export interface VerificationResult {
    isValid: boolean;
    distanceWithinThreshold: boolean;
    distance?: bigint;
    commitment: string;
}

/**
 * Calculates appropriate threshold based on quality metric
 * Lower thresholds mean stricter matching
 * 
 * @param qualityScore - Face detection quality (0-1)
 * @param baseThreshold - Base threshold value
 * @returns Adjusted threshold as BigInt
 */
export function calculateThreshold(
    qualityScore: number = 1.0,
    baseThreshold: bigint = BigInt(500000000) // 0.5 in quantized space
): bigint {
    // Adjust threshold based on quality
    const adjustedThreshold = baseThreshold * BigInt(Math.max(1, qualityScore));
    return adjustedThreshold;
}

/**
 * Constructs witness input for Circom circuit
 */
export function constructWitness(
    registeredEmbedding: bigint[],
    newEmbedding: bigint[],
    existingCommitment: bigint,
    threshold: bigint,
    challenge: bigint
): ProofInputs {
    if (registeredEmbedding.length !== 128 || newEmbedding.length !== 128) {
        throw new Error("Both embeddings must have exactly 128 dimensions");
    }

    return {
        registeredEmbedding,
        newEmbedding,
        existingCommitment,
        threshold,
        challenge
    };
}

/**
 * Generates a ZK proof using Groth16
 */
export async function generateProof(
    inputs: ProofInputs,
    wasmPath: string,
    zkeyPath: string
): Promise<GeneratedProof> {
    try {
        // Validate inputs
        if (inputs.registeredEmbedding.length !== 128 || inputs.newEmbedding.length !== 128) {
            throw new Error("Embeddings must have exactly 128 dimensions");
        }

        // Convert inputs to circuit format matching ZKFaceAuth signal names
        const circuitInputs = {
            reg_embedding: inputs.registeredEmbedding.map((x) => x.toString()),
            live_embedding: inputs.newEmbedding.map((x) => x.toString()),
            stored_hash: inputs.existingCommitment.toString(),
            threshold: inputs.threshold.toString(),
            challenge: inputs.challenge.toString(),
        };

        // Load WASM and zkey
        if (!fs.existsSync(wasmPath)) {
            throw new Error(`WASM file not found: ${wasmPath}`);
        }
        if (!fs.existsSync(zkeyPath)) {
            throw new Error(`zKey file not found: ${zkeyPath}`);
        }

        // Generate proof using Groth16
        const { proof, publicSignals } = await groth16.fullProve(
            circuitInputs,
            wasmPath,
            zkeyPath
        );

        return { proof, publicSignals };
    } catch (error) {
        throw new Error(`Failed to generate proof: ${error}`);
    }
}

/**
 * Converts proof to JSON-serializable format for transmission
 * 
 * @param proof - Generated proof object
 * @returns JSON-serializable proof
 */
export function serializeProof(proof: any): any {
    return {
        pi_a: proof.pi_a.map((x: bigint) => x.toString()),
        pi_b: proof.pi_b.map((row: bigint[]) => row.map((x: bigint) => x.toString())),
        pi_c: proof.pi_c.map((x: bigint) => x.toString()),
        protocol: proof.protocol,
        curve: proof.curve,
    };
}

/**
 * Converts serialized proof back to format for verification
 * 
 * @param serialized - Serialized proof
 * @returns Proof object for verification
 */
export function deserializeProof(serialized: any): any {
    return {
        pi_a: serialized.pi_a.map((x: string) => BigInt(x)),
        pi_b: serialized.pi_b.map((row: string[]) => row.map((x: string) => BigInt(x))),
        pi_c: serialized.pi_c.map((x: string) => BigInt(x)),
        protocol: serialized.protocol,
        curve: serialized.curve,
    };
}

/**
 * Client-side authentication flow
 * 
 * @param newEmbedding - New face embedding (float array)
 * @param registeredEmbedding - Stored registered embedding (float array)
 * @param challenge - Cryptographic nonce for session binding
 * @param commitment - Stored commitment (hex string)
 * @param wasmPath - Path to circuit WASM
 * @param zkeyPath - Path to zkey file
 * @param threshold - Optional distance threshold
 * @returns Generated proof ready for server verification
 */
export async function authenticateWithProof(
    newEmbedding: number[],
    registeredEmbedding: number[],
    challenge: string,
    commitment: string,
    wasmPath: string,
    zkeyPath: string,
    threshold?: bigint
): Promise<GeneratedProof> {
    // Quantize embeddings
    const quantizedNew = quantizeEmbedding(newEmbedding);
    const quantizedRegistered = quantizeEmbedding(registeredEmbedding);

    const challengeBigInt = hexToBigInt(challenge);
    const commitmentBigInt = hexToBigInt(commitment);

    // Calculate or use provided threshold
    const distanceThreshold = threshold || calculateThreshold(1.0);

    // Construct witness
    const inputs = constructWitness(
        quantizedRegistered,
        quantizedNew,
        commitmentBigInt,
        distanceThreshold,
        challengeBigInt
    );

    // Generate proof
    return await generateProof(inputs, wasmPath, zkeyPath);
}

/**
 * Prepares proof data for network transmission
 * 
 * @param proof - Generated proof
 * @param publicSignals - Public signals
 * @returns JSON-serializable object for HTTP transmission
 */
export function prepareProofForTransmission(proof: any, publicSignals: string[]): any {
    return {
        proof: serializeProof(proof),
        publicSignals: publicSignals,
        timestamp: Date.now(),
    };
}

export default {
    calculateThreshold,
    constructWitness,
    generateProof,
    serializeProof,
    deserializeProof,
    authenticateWithProof,
    prepareProofForTransmission,
};
