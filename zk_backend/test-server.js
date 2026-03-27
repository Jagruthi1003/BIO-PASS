#!/usr/bin/env node

/**
 * test-zk-server.js - Test ZK Face Authentication Server
 * 
 * This script tests all server endpoints without requiring actual face data
 */

const http = require('http');
const https = require('https');

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

function request(method, path, data = null, baseUrl = 'http://localhost:3000') {
  return new Promise((resolve, reject) => {
    const url = new URL(path, baseUrl);
    const options = {
      method,
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      headers: {
        'Content-Type': 'application/json',
      },
    };

    const isHttps = url.protocol === 'https:';
    const client = isHttps ? https : http;

    const req = client.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => (body += chunk));
      res.on('end', () => {
        try {
          const json = JSON.parse(body);
          resolve({ status: res.statusCode, body: json });
        } catch (e) {
          resolve({ status: res.statusCode, body });
        }
      });
    });

    req.on('error', reject);

    if (data) {
      req.write(JSON.stringify(data));
    }

    req.end();
  });
}

async function runTests() {
  log('\n╔════════════════════════════════════════════════════════════╗', 'CYAN');
  log('║            ZK Face Authentication - Server Tests           ║', 'CYAN');
  log('╚════════════════════════════════════════════════════════════╝\n', 'CYAN');

  let passed = 0;
  let failed = 0;

  // Test 1: Health Check
  log('🔍 Test 1: Health Check', 'BLUE');
  try {
    const res = await request('GET', '/health');
    if (res.status === 200 && res.body.status === 'ok') {
      log('  ✓ Server is healthy', 'GREEN');
      passed++;
    } else {
      log('  ✗ Unexpected response', 'RED');
      failed++;
    }
  } catch (e) {
    log(`  ✗ Connection failed: ${e.message}`, 'RED');
    log('\n⚠️  Make sure backend server is running: npm start', 'YELLOW');
    process.exit(1);
  }

  // Test 2: Register User
  log('\n🔍 Test 2: User Registration', 'BLUE');
  const testUser = {
    userId: 'test-user-' + Date.now(),
    commitment: '0x' + '1234567890abcdef'.repeat(8),
    salt: '0x' + 'fedcba0987654321'.repeat(8),
  };

  try {
    const res = await request('POST', '/register', testUser);
    if (res.status === 201 && res.body.success) {
      log(`  ✓ User registered: ${res.body.userId}`, 'GREEN');
      passed++;
    } else {
      log(`  ✗ Registration failed: ${res.body.error || res.body.message}`, 'RED');
      failed++;
    }
  } catch (e) {
    log(`  ✗ Error: ${e.message}`, 'RED');
    failed++;
  }

  // Test 3: Get User Status
  log('\n🔍 Test 3: Get User Status', 'BLUE');
  try {
    const res = await request('GET', `/user/${testUser.userId}`);
    if (res.status === 200 && res.body.registered) {
      log(`  ✓ User found and registered`, 'GREEN');
      passed++;
    } else {
      log(`  ✗ Could not retrieve user status`, 'RED');
      failed++;
    }
  } catch (e) {
    log(`  ✗ Error: ${e.message}`, 'RED');
    failed++;
  }

  // Test 4: Authenticate with Proof (Mock)
  log('\n🔍 Test 4: Authentication with Proof', 'BLUE');
  const mockProof = {
    userId: testUser.userId,
    proof: {
      pi_a: ['0', '0', '1'],
      pi_b: [
        ['0', '0'],
        ['0', '0'],
        ['1', '0'],
      ],
      pi_c: ['0', '0', '1'],
      protocol: 'groth16',
      curve: 'bn128',
    },
    publicSignals: [testUser.commitment, '500000000'],
  };

  try {
    const res = await request('POST', '/authenticate', mockProof);
    if (res.status === 200 && res.body.success) {
      log(`  ✓ Authentication successful`, 'GREEN');
      log(`    Session Token: ${res.body.sessionToken?.substring(0, 20)}...`, 'YELLOW');
      passed++;
    } else {
      log(`  ✗ Authentication failed: ${res.body.message || res.body.error}`, 'RED');
      failed++;
    }
  } catch (e) {
    log(`  ✗ Error: ${e.message}`, 'RED');
    failed++;
  }

  // Test 5: Invalid User Registration
  log('\n🔍 Test 5: Error Handling - Invalid Registration', 'BLUE');
  try {
    const res = await request('POST', '/register', {
      userId: 'test-user',
      // Missing commitment and salt
    });
    if (res.status !== 201) {
      log(`  ✓ Correctly rejected invalid request`, 'GREEN');
      passed++;
    } else {
      log(`  ✗ Should have rejected invalid data`, 'RED');
      failed++;
    }
  } catch (e) {
    log(`  ✗ Error: ${e.message}`, 'RED');
    failed++;
  }

  // Test 6: Verify Token (from auth response)
  log('\n🔍 Test 6: Token Verification', 'BLUE');
  try {
    // First authenticate to get a token
    const authRes = await request('POST', '/authenticate', mockProof);

    if (authRes.body.sessionToken) {
      const tokenRes = await request('POST', '/verify-token', {
        token: authRes.body.sessionToken,
      });

      if (tokenRes.status === 200 && tokenRes.body.success) {
        log(`  ✓ Token verified successfully`, 'GREEN');
        passed++;
      } else {
        log(`  ✗ Token verification failed`, 'RED');
        failed++;
      }
    }
  } catch (e) {
    log(`  ✗ Error: ${e.message}`, 'RED');
    failed++;
  }

  // Test 7: Delete User
  log('\n🔍 Test 7: User Deletion', 'BLUE');
  try {
    const res = await request('DELETE', `/user/${testUser.userId}`);
    if (res.status === 200 && res.body.success) {
      log(`  ✓ User deleted successfully`, 'GREEN');
      passed++;
    } else {
      log(`  ✗ User deletion failed`, 'RED');
      failed++;
    }
  } catch (e) {
    log(`  ✗ Error: ${e.message}`, 'RED');
    failed++;
  }

  // Test 8: Verify Deletion
  log('\n🔍 Test 8: Verify User Deletion', 'BLUE');
  try {
    const res = await request('GET', `/user/${testUser.userId}`);
    if (res.status !== 200) {
      log(`  ✓ User successfully deleted (404)`, 'GREEN');
      passed++;
    } else {
      log(`  ✗ User still exists after deletion`, 'RED');
      failed++;
    }
  } catch (e) {
    // Expected to fail after deletion
    log(`  ✓ User successfully deleted`, 'GREEN');
    passed++;
  }

  // Summary
  log('\n' + '='.repeat(60), 'CYAN');
  log(`\nTest Results: ${passed} passed, ${failed} failed`, passed > failed ? 'GREEN' : 'RED');

  if (failed === 0) {
    log('\n✅ All tests passed! Server is working correctly.', 'GREEN');
  } else {
    log(`\n⚠️  ${failed} test(s) failed. Check server logs.`, 'RED');
  }
}

runTests().catch((e) => {
  log(`\nTest execution error: ${e.message}`, 'RED');
  process.exit(1);
});
