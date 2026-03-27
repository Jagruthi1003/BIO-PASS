#!/usr/bin/env node

/**
 * setupCircuit.js - Generate proving and verification keys using Groth16
 * 
 * This script:
 * 1. Uses trusted setup to generate ZKey (proving key)
 * 2. Extracts verification key
 * 3. Generates verification artifacts for the server
 */

import { exec } from "child_process";
import path from "path";
import fs from "fs";
import util from "util";
import https from "https";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const execAsync = util.promisify(exec);

const CIRCUIT_NAME = "zk_face_auth";
const CIRCUITS_DIR = path.resolve(__dirname, "..", "..", "zk_circuits");
const R1CS_FILE = path.resolve(CIRCUITS_DIR, `${CIRCUIT_NAME}.r1cs`);
const WASM_FILE = path.resolve(CIRCUITS_DIR, `${CIRCUIT_NAME}_js`, `${CIRCUIT_NAME}.wasm`);
const ZKEY_FILE = path.resolve(CIRCUITS_DIR, `${CIRCUIT_NAME}.zkey`);
const VKEY_FILE = path.resolve(__dirname, "..", "vkey.json");
const PTAU_FILENAME = "powersOfTau28_hez_final_15.ptau";
const PTAU_FILE = path.join(CIRCUITS_DIR, PTAU_FILENAME);

async function downloadPTAU() {
    return new Promise((resolve, reject) => {
        if (fs.existsSync(PTAU_FILE)) {
            const stats = fs.statSync(PTAU_FILE);
            if (stats.size > 0) {
                console.log("📦 Using existing Powers of Tau file");
                resolve();
                return;
            }
        }

        console.log("⏳ Downloading Powers of Tau file (this may take a few minutes)...");
        const url = `https://storage.googleapis.com/zkevm/ptau/${PTAU_FILENAME}`;
        const file = fs.createWriteStream(PTAU_FILE);

        https.get(url, (response) => {
            if (response.statusCode !== 200) {
                reject(new Error(`Failed to download: ${response.statusCode}`));
                return;
            }

            response.pipe(file);
            file.on("finish", () => {
                file.close();
                console.log("✅ Powers of Tau downloaded");
                resolve();
            });
        }).on("error", reject);
    });
}

async function setupCircuit() {
    try {
        console.log("🔐 Setting up ZK circuit with Groth16...");

        // Check if R1CS exists
        if (!fs.existsSync(R1CS_FILE)) {
            console.error(
                `❌ R1CS file not found: ${R1CS_FILE}`
            );
            console.error("Run: node scripts/compileCircuit.js");
            process.exit(1);
        }

        // Check if WASM exists
        if (!fs.existsSync(WASM_FILE)) {
            console.error(
                `❌ WASM file not found: ${WASM_FILE}`
            );
            console.error("Run: node scripts/compileCircuit.js");
            process.exit(1);
        }

        // Download or use existing Powers of Tau
        await downloadPTAU();

        // Check if snarkjs is available
        try {
            await execAsync("npx snarkjs --version");
        } catch (error) {
            console.error("❌ snarkjs not found. Install with: npm install snarkjs");
            process.exit(1);
        }

        // Generate ZKey
        console.log("⏳ Generating ZKey (proving key)...");
        const zkeyCmd = `npx snarkjs groth16 setup ${R1CS_FILE} ${PTAU_FILE} ${ZKEY_FILE}`;
        await execAsync(zkeyCmd);
        console.log("✅ ZKey generated");

        // Extract verification key
        console.log("⏳ Extracting verification key...");
        const vkeyCmd = `npx snarkjs zkey export verificationkey ${ZKEY_FILE} ${VKEY_FILE}`;
        await execAsync(vkeyCmd);
        console.log("✅ Verification key extracted");

        console.log("\n✅ Circuit setup complete!");
        console.log(`📦 Generated files:`);
        console.log(`   - ${ZKEY_FILE}`);
        console.log(`   - ${VKEY_FILE}`);
        console.log("\n📝 Next steps:");
        console.log("   1. Copy vkey.json to the server directory");
        console.log("   2. Use zkey in proof generation");

    } catch (error) {
        console.error("❌ Setup failed:");
        console.error(error.message);
        process.exit(1);
    }
}

setupCircuit();
