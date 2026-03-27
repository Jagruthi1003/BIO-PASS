/**
 * quantize.ts - Utility to convert float embeddings to quantized BigInt format
 * 
 * ML embeddings are typically in the range [-1.0, 1.0]
 * We scale by 1,000,000 and convert to BigInt for ZK circuit compatibility
 */

/**
 * Quantizes a single float value to a BigInt with scale factor
 * @param value - Float value (typically -1.0 to 1.0)
 * @param scale - Scale factor (default: 1000000)
 * @returns Quantized BigInt value
 */
export function quantizeValue(value: number, scale: number = 1000000): bigint {
    const quantized = Math.round(value * scale);
    return BigInt(quantized);
}

/**
 * Quantizes an array of float embeddings
 * @param embedding - Array of float values
 * @param scale - Scale factor (default: 1000000)
 * @returns Array of quantized BigInt values
 */
export function quantizeEmbedding(
    embedding: number[],
    scale: number = 1000000
): bigint[] {
    if (!Array.isArray(embedding)) {
        throw new Error("Embedding must be an array");
    }
    
    if (embedding.length !== 128) {
        throw new Error(`Embedding must have exactly 128 dimensions, got ${embedding.length}`);
    }

    return embedding.map((value) => quantizeValue(value, scale));
}

/**
 * Dequantizes a BigInt back to float (for verification purposes)
 * @param quantized - Quantized BigInt value
 * @param scale - Scale factor used during quantization (default: 1000000)
 * @returns Float value
 */
export function dequantizeValue(quantized: bigint, scale: number = 1000000): number {
    return Number(quantized) / scale;
}

/**
 * Dequantizes an array of quantized values
 * @param quantizedArray - Array of quantized BigInt values
 * @param scale - Scale factor used during quantization (default: 1000000)
 * @returns Array of float values
 */
export function dequantizeEmbedding(
    quantizedArray: bigint[],
    scale: number = 1000000
): number[] {
    return quantizedArray.map((value) => dequantizeValue(value, scale));
}

/**
 * Validates that an embedding is within expected bounds
 * @param embedding - Array of float values
 * @param min - Minimum expected value (default: -1.0)
 * @param max - Maximum expected value (default: 1.0)
 * @returns True if all values are within bounds
 */
export function validateEmbedding(
    embedding: number[],
    min: number = -1.0,
    max: number = 1.0
): boolean {
    if (!Array.isArray(embedding) || embedding.length !== 128) {
        return false;
    }

    return embedding.every((value) => value >= min && value <= max);
}

/**
 * Calculates squared Euclidean distance between two quantized embeddings
 * @param embedding1 - First quantized embedding
 * @param embedding2 - Second quantized embedding
 * @returns Squared distance as BigInt
 */
export function calculateQuantizedDistance(
    embedding1: bigint[],
    embedding2: bigint[]
): bigint {
    if (embedding1.length !== embedding2.length || embedding1.length !== 128) {
        throw new Error("Both embeddings must have exactly 128 dimensions");
    }

    let distanceSquared = BigInt(0);

    for (let i = 0; i < embedding1.length; i++) {
        const diff = embedding1[i] - embedding2[i];
        distanceSquared += diff * diff;
    }

    return distanceSquared;
}

/**
 * Calculates squared Euclidean distance between two float embeddings
 * (for reference/testing purposes)
 * @param embedding1 - First embedding
 * @param embedding2 - Second embedding
 * @returns Squared distance as number
 */
export function calculateFloatDistance(
    embedding1: number[],
    embedding2: number[]
): number {
    if (embedding1.length !== embedding2.length || embedding1.length !== 128) {
        throw new Error("Both embeddings must have exactly 128 dimensions");
    }

    let distanceSquared = 0;

    for (let i = 0; i < embedding1.length; i++) {
        const diff = embedding1[i] - embedding2[i];
        distanceSquared += diff * diff;
    }

    return distanceSquared;
}

export default {
    quantizeValue,
    quantizeEmbedding,
    dequantizeValue,
    dequantizeEmbedding,
    validateEmbedding,
    calculateQuantizedDistance,
    calculateFloatDistance,
};
