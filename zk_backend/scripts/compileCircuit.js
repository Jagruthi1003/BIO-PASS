#!/usr/bin/env node

/**
 * compileCircuit.js - Compile Circom circuit to WASM
 * 
 * This script:
 * 1. Compiles face_verify.circom to R1CS
 * 2. Generates WASM representation
 * 3. Outputs files needed for proof generation
 */

import { exec } from "child_process";
import path from "path";
import fs from "fs";
import util from "util";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const execAsync = util.promisify(exec);

const CIRCUIT_NAME = "zk_face_auth";
const CIRCUIT_FILE = path.resolve(__dirname, "..", "..", "zk_circuits", `${CIRCUIT_NAME}.circom`);
const OUTPUT_DIR = path.resolve(__dirname, "..", "..", "zk_circuits");

async function compileCircuit() {
    try {
        console.log("🔧 Compiling Circom circuit...");

        // Check if circuit file exists
        if (!fs.existsSync(CIRCUIT_FILE)) {
            console.error(`❌ Circuit file not found: ${CIRCUIT_FILE}`);
            process.exit(1);
        }

        console.log(`📄 Circuit file: ${CIRCUIT_FILE}`);

        // Check if circom is installed
        try {
            await execAsync("circom --version");
        } catch (error) {
            console.error("❌ circom is not installed. Install it globally:");
            console.error("   npm install -g circom");
            process.exit(1);
        }

        // Compile to R1CS
        console.log("⏳ Compiling to R1CS...");
        const compileCmd = `circom ${CIRCUIT_FILE} --r1cs --wasm --sym -o ${OUTPUT_DIR}`;
        await execAsync(compileCmd);

        console.log("✅ Compilation successful!");
        console.log(`📦 Generated files in: ${OUTPUT_DIR}`);
        console.log(`   - ${CIRCUIT_NAME}.r1cs`);
        console.log(`   - ${CIRCUIT_NAME}.sym`);
        console.log(`   - ${CIRCUIT_NAME}_js/`);

    } catch (error) {
        console.error("❌ Compilation failed:");
        console.error(error.message);
        process.exit(1);
    }
}

compileCircuit();
