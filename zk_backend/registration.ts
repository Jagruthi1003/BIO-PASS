/**
 * registration.ts - Handle ZK face registration process
 * 
 * During registration:
 * 1. User provides a face embedding (128D vector of floats)
 * 2. Generate a random salt
 * 3. Compute Poseidon hash of embedding + salt
 * 4. Store the commitment (hash) and other metadata in database
 */

import { buildPoseidon } from "circomlibjs";
import { quantizeEmbedding } from "./quantize";
import crypto from "crypto";

/**
 * Interface for registration data
 */
export interface RegistrationData {
    commitment: string; // Hex string of the Poseidon hash
    salt: string; // Hex string of the random salt
    quantizedEmbedding: bigint[]; // Quantized embedding (NOT stored, only for proof generation)
    timestamp: number;
    userId?: string;
}

/**
 * Generates a random salt for hashing
 * @returns Hex string of random 32 bytes
 */
export function generateSalt(): string {
    return crypto.randomBytes(32).toString("hex");
}

/**
 * Generates a random salt as BigInt for circuit use
 * @returns BigInt representation of random bytes
 */
export function generateSaltAsBigInt(): bigint {
    const saltHex = generateSalt();
    return BigInt("0x" + saltHex);
}

/**
 * Converts hex string to BigInt
 * @param hexString - Hex string (with or without 0x prefix)
 * @returns BigInt value
 */
export function hexToBigInt(hexString: string): bigint {
    const cleaned = hexString.startsWith("0x") ? hexString : "0x" + hexString;
    return BigInt(cleaned);
}

/**
 * Converts BigInt to hex string
 * @param value - BigInt value
 * @returns Hex string without 0x prefix
 */
export function bigIntToHex(value: bigint): string {
    return value.toString(16);
}

/**
 * Computes Poseidon hash of embedding (Tree structure)
 * This is the main registration hash that gets stored
 * 
 * @param embedding - 128D float embedding
 * @param salt - Salt (kept for compatibility in DB, but not used in circuit hash)
 * @returns Commitment as hex string
 */
export async function computeRegistrationCommitment(
    embedding: number[],
    salt: string | bigint
): Promise<string> {
    if (embedding.length !== 128) {
        throw new Error("Embedding must have exactly 128 dimensions");
    }

    // Quantize the embedding
    const quantized = quantizeEmbedding(embedding);

    // Build Poseidon hasher
    const poseidon = await buildPoseidon();
    const F = (poseidon as any).F;

    // Mimic the Circom 2-level Poseidon tree since poseidon(128) is too large
    // Level 1: 8 groups of 16
    const leafOutputs = [];
    for (let i = 0; i < 8; i++) {
        const chunk = quantized.slice(i * 16, i * 16 + 16);
        const h = poseidon(chunk);
        leafOutputs.push(h);
    }

    // Level 2: Hash the 8 outputs
    const hash = poseidon(leafOutputs);

    // Convert to hex string
    return F.toString(hash, 16);
}

/**
 * Registers a new face and returns commitment for storage
 * 
 * @param embedding - 128D float embedding from face detection
 * @param userId - Optional user identifier
 * @returns RegistrationData containing commitment and metadata
 */
export async function registerFace(
    embedding: number[],
    userId?: string
): Promise<RegistrationData> {
    if (embedding.length !== 128) {
        throw new Error("Embedding must have exactly 128 dimensions");
    }

    // Generate random salt
    const salt = generateSalt();

    // Compute commitment
    const commitment = await computeRegistrationCommitment(embedding, salt);

    // Quantize embedding for later use in proof generation
    const quantizedEmbedding = quantizeEmbedding(embedding);

    return {
        commitment,
        salt,
        quantizedEmbedding,
        timestamp: Date.now(),
        userId,
    };
}

/**
 * Exports registration data for database storage
 * Should only include commitment and metadata (NOT the embedding or salt for security)
 * 
 * @param registrationData - Full registration data
 * @returns Database-safe object with commitment and metadata
 */
export function exportForDatabase(registrationData: RegistrationData) {
    // In production, you might want to encrypt the salt or store it separately
    return {
        commitment: registrationData.commitment,
        salt: registrationData.salt, // Store encrypted or in separate secure storage
        timestamp: registrationData.timestamp,
        userId: registrationData.userId,
    };
}

/**
 * Validates registration data structure
 * 
 * @param data - Data to validate
 * @returns True if data is valid
 */
export function validateRegistrationData(data: any): boolean {
    if (typeof data !== "object" || data === null) {
        return false;
    }

    const requiredFields = ["commitment", "salt", "quantizedEmbedding", "timestamp"];
    for (const field of requiredFields) {
        if (!(field in data)) {
            return false;
        }
    }

    // Validate commitment is hex string
    if (typeof data.commitment !== "string" || !/^[0-9a-f]+$/.test(data.commitment)) {
        return false;
    }

    // Validate salt is hex string
    if (typeof data.salt !== "string" || !/^[0-9a-f]+$/.test(data.salt)) {
        return false;
    }

    // Validate quantizedEmbedding is array of BigInts
    if (
        !Array.isArray(data.quantizedEmbedding) ||
        data.quantizedEmbedding.length !== 128
    ) {
        return false;
    }

    return true;
}

export default {
    generateSalt,
    generateSaltAsBigInt,
    hexToBigInt,
    bigIntToHex,
    computeRegistrationCommitment,
    registerFace,
    exportForDatabase,
    validateRegistrationData,
};
