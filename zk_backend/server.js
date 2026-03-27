import express from 'express';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import * as snarkjs from 'snarkjs';
import cors from 'cors'; // Highly recommended for mobile app backends

// --- ES Module Compatibility Fix ---
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * server.js - Express backend server for ZK proof verification
 * 
 * This server:
 * 1. Receives face authentication requests with ZK proofs
 * 2. Verifies proofs using snarkjs
 * 3. Checks that public signals match expected values
 * 4. Issues authentication tokens or status
 */

const { groth16 } = snarkjs;
const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json({ limit: "50mb" }));

// In-memory user database (replace with real database)
const users = new Map();

/**
 * Deserializes proof from network format
 */
function deserializeProof(serialized) {
    return {
        pi_a: serialized.pi_a.map((x) => BigInt(x)),
        pi_b: serialized.pi_b.map((row) => row.map((x) => BigInt(x))),
        pi_c: serialized.pi_c.map((x) => BigInt(x)),
        protocol: serialized.protocol,
        curve: serialized.curve,
    };
}

/**
 * POST /register - Register a new user with face commitment
 * 
 * Body: {
 *   userId: string,
 *   commitment: string (hex),
 *   salt: string (hex)
 * }
 */
app.post("/register", (req, res) => {
    try {
        const { userId, commitment, salt } = req.body;

        if (!userId || !commitment || !salt) {
            return res.status(400).json({
                error: "Missing required fields: userId, commitment, salt",
            });
        }

        // Validate hex format
        if (!/^[0-9a-f]+$/i.test(commitment) || !/^[0-9a-f]+$/i.test(salt)) {
            return res.status(400).json({
                error: "Commitment and salt must be valid hex strings",
            });
        }

        // Store user registration
        users.set(userId, {
            commitment,
            salt,
            registeredAt: new Date(),
            loginAttempts: 0,
            lastLogin: null,
        });

        return res.status(201).json({
            success: true,
            message: "User registered successfully",
            userId,
        });
    } catch (error) {
        console.error("Registration error:", error);
        return res.status(500).json({ error: error.message });
    }
});

/**
 * POST /authenticate - Verify a ZK proof for face authentication
 * 
 * Body: {
 *   userId: string,
 *   proof: {
 *     pi_a: string[],
 *     pi_b: string[][],
 *     pi_c: string[],
 *     protocol: string,
 *     curve: string
 *   },
 *   publicSignals: string[]
 * }
 */
app.post("/authenticate", async (req, res) => {
    try {
        const { userId, proof: serializedProof, publicSignals } = req.body;

        if (!userId || !serializedProof || !publicSignals) {
            return res.status(400).json({
                error: "Missing required fields: userId, proof, publicSignals",
            });
        }

        // Check if user exists
        const user = users.get(userId);
        if (!user) {
            return res.status(404).json({
                error: "User not found",
            });
        }

        // Deserialize proof
        const proof = deserializeProof(serializedProof);

        // Load verification key (this should be pre-loaded in production)
        const vkeyPath = path.join(__dirname, "vkey.json");
        if (!fs.existsSync(vkeyPath)) {
            return res.status(500).json({
                error: "Verification key not found. Please run: node scripts/setupCircuit.js",
            });
        }

        const vkey = JSON.parse(fs.readFileSync(vkeyPath, "utf8"));

        // Verify proof
        const isValid = await groth16.verify(vkey, publicSignals, proof);

        if (!isValid) {
            user.loginAttempts++;
            return res.status(401).json({
                success: false,
                message: "Proof verification failed",
                reason: "invalid_proof",
            });
        }

        // Parse public signals: [commitment, threshold]
        const publicCommitment = publicSignals[0];
        const publicThreshold = publicSignals[1];

        // Verify that the commitment matches user's stored commitment
        if (publicCommitment !== user.commitment) {
            user.loginAttempts++;
            return res.status(401).json({
                success: false,
                message: "Commitment mismatch",
                reason: "invalid_commitment",
            });
        }

        // Authentication successful
        user.lastLogin = new Date();
        user.loginAttempts = 0;

        // Generate session token (in production, use JWT)
        const sessionToken = Buffer.from(
            JSON.stringify({
                userId,
                timestamp: Date.now(),
                proof: publicCommitment,
            })
        ).toString("base64");

        return res.status(200).json({
            success: true,
            message: "Authentication successful",
            userId,
            sessionToken,
            commitment: publicCommitment,
        });
    } catch (error) {
        console.error("Authentication error:", error);
        return res.status(500).json({
            error: error.message,
        });
    }
});

/**
 * POST /verify-token - Verify a session token
 */
app.post("/verify-token", (req, res) => {
    try {
        const { token } = req.body;

        if (!token) {
            return res.status(400).json({ error: "Token required" });
        }

        // Decode and verify token
        const decoded = JSON.parse(Buffer.from(token, "base64").toString("utf8"));
        const user = users.get(decoded.userId);

        if (!user || decoded.proof !== user.commitment) {
            return res.status(401).json({
                success: false,
                message: "Invalid token",
            });
        }

        return res.status(200).json({
            success: true,
            userId: decoded.userId,
        });
    } catch (error) {
        return res.status(401).json({
            success: false,
            message: "Token verification failed",
            error: error.message,
        });
    }
});

/**
 * GET /user/:userId - Get user registration status
 */
app.get("/user/:userId", (req, res) => {
    const { userId } = req.params;
    const user = users.get(userId);

    if (!user) {
        return res.status(404).json({
            error: "User not found",
        });
    }

    return res.status(200).json({
        userId,
        registered: true,
        registeredAt: user.registeredAt,
        lastLogin: user.lastLogin,
    });
});

/**
 * DELETE /user/:userId - Delete user (for testing)
 */
app.delete("/user/:userId", (req, res) => {
    const { userId } = req.params;

    if (!users.has(userId)) {
        return res.status(404).json({
            error: "User not found",
        });
    }

    users.delete(userId);
    return res.status(200).json({
        success: true,
        message: "User deleted",
    });
});

/**
 * GET /health - Health check
 */
app.get("/health", (req, res) => {
    return res.status(200).json({
        status: "ok",
        timestamp: new Date(),
        usersCount: users.size,
    });
});

/**
 * Error handling middleware
 */
app.use((err, req, res, next) => {
    console.error("Unhandled error:", err);
    res.status(500).json({
        error: "Internal server error",
        message: err.message,
    });
});

// Start server
app.listen(PORT, () => {
    console.log(`ZK Face Authentication Server running on port ${PORT}`);
    console.log(`Environment: ${process.env.NODE_ENV || "development"}`);
    console.log("Available endpoints:");
    console.log("  POST   /register              - Register new user");
    console.log("  POST   /authenticate          - Verify face with ZK proof");
    console.log("  POST   /verify-token          - Verify session token");
    console.log("  GET    /user/:userId          - Get user status");
    console.log("  DELETE /user/:userId          - Delete user");
    console.log("  GET    /health                - Health check");
});
