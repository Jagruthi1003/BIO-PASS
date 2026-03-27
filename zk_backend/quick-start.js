#!/usr/bin/env node

/**
 * quick-start.js - Automated setup script for ZK Face Authentication
 * Guides through complete setup process
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const readline = require('readline');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

const COLORS = {
  RESET: '\x1b[0m',
  RED: '\x1b[31m',
  GREEN: '\x1b[32m',
  YELLOW: '\x1b[33m',
  BLUE: '\x1b[34m',
  CYAN: '\x1b[36m',
};

function log(message, color = 'RESET') {
  console.log(`${COLORS[color]}${message}${COLORS.RESET}`);
}

function question(prompt) {
  return new Promise((resolve) => {
    rl.question(prompt, resolve);
  });
}

async function checkPrerequisites() {
  log('\n🔍 Checking prerequisites...', 'CYAN');

  try {
    execSync('node --version', { stdio: 'pipe' });
    log('  ✓ Node.js installed', 'GREEN');
  } catch (e) {
    log('  ✗ Node.js not installed', 'RED');
    log('    Download from: https://nodejs.org/', 'YELLOW');
    return false;
  }

  try {
    execSync('circom --version', { stdio: 'pipe' });
    log('  ✓ Circom installed', 'GREEN');
  } catch (e) {
    log('  ✗ Circom not installed', 'RED');
    log('    Install with: npm install -g circom', 'YELLOW');

    const install = await question('Install Circom now? (y/n): ');
    if (install.toLowerCase() === 'y') {
      log('\n⏳ Installing Circom...', 'BLUE');
      try {
        execSync('npm install -g circom', { stdio: 'inherit' });
        log('✓ Circom installed successfully', 'GREEN');
      } catch (e) {
        log('✗ Failed to install Circom', 'RED');
        return false;
      }
    } else {
      return false;
    }
  }

  return true;
}

async function setupBackend() {
  log('\n📦 Setting up backend...', 'CYAN');

  try {
    log('Installing npm dependencies...', 'BLUE');
    execSync('npm install', { stdio: 'inherit', cwd: __dirname });
    log('✓ Dependencies installed', 'GREEN');
  } catch (e) {
    log('✗ Failed to install dependencies', 'RED');
    return false;
  }

  return true;
}

async function compileCircuit() {
  log('\n🔧 Compiling Circom circuit...', 'CYAN');

  try {
    const result = execSync('node scripts/compileCircuit.js', {
      stdio: 'inherit',
      cwd: __dirname,
    });
    log('✓ Circuit compiled successfully', 'GREEN');
    return true;
  } catch (e) {
    log('✗ Circuit compilation failed', 'RED');
    return false;
  }
}

async function setupKeys() {
  log('\n🔐 Setting up proving and verification keys...', 'CYAN');
  log('(This may take several minutes and ~1.4GB download)', 'YELLOW');

  const proceed = await question('Continue? (y/n): ');
  if (proceed.toLowerCase() !== 'y') {
    log('Skipped key generation', 'YELLOW');
    return false;
  }

  try {
    const result = execSync('node scripts/setupCircuit.js', {
      stdio: 'inherit',
      cwd: __dirname,
    });
    log('✓ Keys generated successfully', 'GREEN');
    return true;
  } catch (e) {
    log('✗ Key generation failed', 'RED');
    return false;
  }
}

async function verifySetup() {
  log('\n✓ Verifying setup...', 'CYAN');

  const requiredFiles = [
    'zk_circuits/face_verify.r1cs',
    'zk_circuits/face_verify_js/face_verify.wasm',
    'zk_circuits/face_verify.zkey',
    'vkey.json',
  ];

  let allFound = true;

  for (const file of requiredFiles) {
    const fullPath = path.join(__dirname, file);
    if (fs.existsSync(fullPath)) {
      log(`  ✓ ${file}`, 'GREEN');
    } else {
      log(`  ✗ ${file} NOT FOUND`, 'RED');
      allFound = false;
    }
  }

  return allFound;
}

async function startServer() {
  log('\n🚀 Starting backend server...', 'CYAN');

  log('Server will run on: http://localhost:3000', 'BLUE');
  log('Press Ctrl+C to stop', 'YELLOW');

  try {
    execSync('node server.js', {
      stdio: 'inherit',
      cwd: __dirname,
    });
  } catch (e) {
    if (e.signal === 'SIGINT') {
      log('\n\nServer stopped', 'YELLOW');
    } else {
      log('Server error:', 'RED');
      console.error(e);
    }
  }
}

async function main() {
  log('\n╔════════════════════════════════════════════════════════════╗', 'CYAN');
  log('║  Zero-Knowledge Face Authentication - Quick Start Setup    ║', 'CYAN');
  log('╚════════════════════════════════════════════════════════════╝\n', 'CYAN');

  // Check prerequisites
  const hasPrereqs = await checkPrerequisites();
  if (!hasPrereqs) {
    log('\n✗ Setup incomplete. Install missing prerequisites.', 'RED');
    rl.close();
    process.exit(1);
  }

  // Setup backend
  const backendReady = await setupBackend();
  if (!backendReady) {
    log('\n✗ Backend setup failed', 'RED');
    rl.close();
    process.exit(1);
  }

  // Compile circuit
  const circuitReady = await compileCircuit();
  if (!circuitReady) {
    log('\n✗ Circuit compilation failed', 'RED');
    rl.close();
    process.exit(1);
  }

  // Setup keys
  const keysReady = await setupKeys();

  // Verify setup
  const verified = await verifySetup();
  if (!verified) {
    log('\n⚠️  Some files are missing', 'YELLOW');
    log('Try running: node scripts/setupCircuit.js', 'YELLOW');
  }

  // Option to start server
  log('\n' + '='.repeat(60), 'CYAN');
  const startNow = await question('Start backend server now? (y/n): ');

  rl.close();

  if (startNow.toLowerCase() === 'y') {
    await startServer();
  } else {
    log('\n✓ Setup complete!', 'GREEN');
    log('\nTo start the server later, run:', 'YELLOW');
    log('  npm start', 'BLUE');
    log('\nFor Flutter integration, use:', 'YELLOW');
    log('  serverUrl: "http://<your-ip>:3000"', 'BLUE');
  }
}

main().catch((e) => {
  log(`\nError: ${e.message}`, 'RED');
  rl.close();
  process.exit(1);
});
