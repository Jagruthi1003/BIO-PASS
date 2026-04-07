/**
 * Firebase Cloud Function for sending OTP emails
 * Deploy with: firebase deploy --only functions
 * 
 * Install dependencies: npm install nodemailer @sendgrid/mail firebase-admin
 * 
 * Environment Variables Required:
 * - EMAIL_SERVICE: 'gmail' or 'sendgrid' (default: 'gmail')
 * - GMAIL_USER: Your Gmail address (if using Gmail)
 * - GMAIL_APP_PASSWORD: Gmail app-specific password (if using Gmail)
 * - SENDGRID_API_KEY: SendGrid API key (if using SendGrid)
 * - SENDGRID_FROM_EMAIL: From email address (if using SendGrid)
 */

const functions = require('firebase-functions');
const nodemailer = require('nodemailer');
const admin = require('firebase-admin');

// Initialize Firebase Admin if not already done
if (!admin.apps.length) {
  admin.initializeApp();
}

// Get environment variables
const emailService = process.env.EMAIL_SERVICE || 'gmail';
const gmailUser = process.env.GMAIL_USER;
const gmailAppPassword = process.env.GMAIL_APP_PASSWORD;
const sendgridApiKey = process.env.SENDGRID_API_KEY;
const sendgridFromEmail = process.env.SENDGRID_FROM_EMAIL;

console.log(`📧 Email Service Configured: ${emailService}`);

// Create transporter based on environment
let transporter;

if (emailService === 'gmail') {
  if (!gmailUser || !gmailAppPassword) {
    console.error('❌ Gmail credentials not configured. Set GMAIL_USER and GMAIL_APP_PASSWORD environment variables.');
  }
  transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
      user: gmailUser,
      pass: gmailAppPassword,
    },
  });
  console.log(`✅ Gmail transporter configured for: ${gmailUser}`);
} else if (emailService === 'sendgrid') {
  if (!sendgridApiKey) {
    console.error('❌ SendGrid API key not configured. Set SENDGRID_API_KEY environment variable.');
  }
  transporter = nodemailer.createTransport({
    host: 'smtp.sendgrid.net',
    port: 587,
    secure: false,
    auth: {
      user: 'apikey',
      pass: sendgridApiKey,
    },
  });
  console.log('✅ SendGrid transporter configured');
}

/**
 * Validate email address format
 */
function isValidEmail(email) {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

/**
 * Get email template for OTP
 */
function getOTPEmailTemplate(otp, email) {
  return `
    <div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 600px; margin: 0 auto; background: #f5f5f5;">
      <!-- Header -->
      <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 40px; text-align: center; color: white;">
        <h1 style="margin: 0; font-size: 32px;">BiO Pass</h1>
        <p style="margin: 10px 0 0 0; font-size: 16px; opacity: 0.9;">Biometric Event Attendance System</p>
      </div>
      
      <!-- Content -->
      <div style="background: white; padding: 40px; margin: 20px; border-radius: 10px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
        <h2 style="color: #333; margin-bottom: 20px; font-size: 24px;">Verify Your Email</h2>
        
        <p style="color: #666; line-height: 1.6; margin-bottom: 20px;">
          We received a request to verify your email address. Enter the code below in the BiO Pass app to confirm your account.
        </p>
        
        <!-- OTP Box -->
        <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 30px; border-radius: 10px; margin: 30px 0; text-align: center;">
          <p style="color: #ffffff; margin: 0 0 15px 0; font-size: 14px; opacity: 0.9;">Your verification code is:</p>
          <p style="color: #ffffff; font-size: 48px; font-weight: bold; margin: 0; letter-spacing: 6px; font-family: 'Courier New', monospace;">${otp}</p>
        </div>
        
        <!-- Info -->
        <div style="background: #f0f7ff; border-left: 4px solid #667eea; padding: 15px; margin: 20px 0; border-radius: 4px;">
          <p style="color: #333; margin: 0; font-size: 14px;">
            <strong>⏱️ Valid for 10 minutes</strong><br>
            <span style="color: #666;">This code will expire and you'll need to request a new one.</span>
          </p>
        </div>
        
        <!-- Security Notice -->
        <div style="background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0; border-radius: 4px;">
          <p style="color: #856404; margin: 0; font-size: 13px;">
            <strong>🔒 Security Notice:</strong> Never share this code with anyone. Our team will never ask you for this code.
          </p>
        </div>
        
        <!-- Footer -->
        <p style="color: #999; font-size: 13px; margin-top: 30px; border-top: 1px solid #eee; padding-top: 20px;">
          If you didn't request this verification, you can safely ignore this email. Your account will remain secure.
        </p>
      </div>
      
      <!-- Footer Brand -->
      <div style="background: #f5f5f5; padding: 20px; text-align: center; color: #999; font-size: 12px;">
        <p style="margin: 0;">BiO Pass - Biometric Event Attendance System</p>
        <p style="margin: 5px 0 0 0;">Powered by Pondicherry University</p>
      </div>
    </div>
  `;
}

/**
 * Get email template for verification confirmation
 */
function getConfirmationEmailTemplate(userName) {
  return `
    <div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 600px; margin: 0 auto; background: #f5f5f5;">
      <!-- Header -->
      <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 40px; text-align: center; color: white;">
        <h1 style="margin: 0; font-size: 32px;">BiO Pass</h1>
        <p style="margin: 10px 0 0 0; font-size: 16px; opacity: 0.9;">Email Verified Successfully ✅</p>
      </div>
      
      <!-- Content -->
      <div style="background: white; padding: 40px; margin: 20px; border-radius: 10px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
        <h2 style="color: #333; margin-bottom: 20px; font-size: 24px;">Welcome, ${userName || 'User'}!</h2>
        
        <p style="color: #666; line-height: 1.6; margin-bottom: 20px;">
          Your email has been successfully verified. You can now access all features of BiO Pass.
        </p>
        
        <!-- Status Box -->
        <div style="background: #e8f5e9; border-left: 4px solid #4caf50; padding: 15px; margin: 20px 0; border-radius: 4px;">
          <p style="color: #2e7d32; margin: 0; font-size: 14px;">
            <strong>✅ Account Status: Active</strong><br>
            <span style="color: #558b2f;">You can now log in and access the BiO Pass application.</span>
          </p>
        </div>
        
        <!-- Features -->
        <div style="margin: 30px 0;">
          <h3 style="color: #667eea; font-size: 16px; margin-bottom: 15px;">What you can do now:</h3>
          <ul style="color: #666; line-height: 1.8; padding-left: 20px;">
            <li>Register for events using biometric authentication</li>
            <li>Verify attendance with face recognition</li>
            <li>View your attendance history</li>
            <li>Manage your profile settings</li>
          </ul>
        </div>
        
        <!-- Security Notice -->
        <div style="background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0; border-radius: 4px;">
          <p style="color: #856404; margin: 0; font-size: 13px;">
            <strong>🔐 Account Security:</strong> Keep your password secure. Never share your credentials with anyone.
          </p>
        </div>
        
        <!-- Footer -->
        <p style="color: #999; font-size: 13px; margin-top: 30px; border-top: 1px solid #eee; padding-top: 20px;">
          If you did not create this account, please contact our support team immediately.
        </p>
      </div>
      
      <!-- Footer Brand -->
      <div style="background: #f5f5f5; padding: 20px; text-align: center; color: #999; font-size: 12px;">
        <p style="margin: 0;">BiO Pass - Biometric Event Attendance System</p>
        <p style="margin: 5px 0 0 0;">Powered by Pondicherry University</p>
      </div>
    </div>
  `;
}

/**
 * Verify email configuration
 */
exports.verifyEmailConfig = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');

  if (req.method === 'OPTIONS') {
    res.status(200).send();
    return;
  }

  try {
    const verified = await transporter.verify();
    
    if (verified) {
      console.log('✅ Email transporter verified successfully');
      res.status(200).json({
        success: true,
        message: 'Email configuration is valid and ready to use',
        emailService: emailService,
        emailUser: gmailUser || sendgridFromEmail || 'Not configured',
      });
    } else {
      console.error('❌ Email transporter verification failed');
      res.status(500).json({
        success: false,
        message: 'Email transporter verification failed',
        emailService: emailService,
      });
    }
  } catch (error) {
    console.error('Email verification error:', error);
    res.status(500).json({
      success: false,
      message: 'Email configuration verification failed',
      error: error.message,
    });
  }
});

/**
 * Main Cloud Function for sending emails
 * Handles OTP emails, verification confirmations, and password resets
 */
exports.sendOTPEmail = functions.https.onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(200).send();
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ 
      success: false,
      error: 'Method not allowed. Use POST.' 
    });
    return;
  }

  try {
    const { email, otp, type, userName, resetLink } = req.body;

    // Validate email
    if (!email) {
      console.warn('❌ Email not provided');
      res.status(400).json({ 
        success: false,
        error: 'Email is required' 
      });
      return;
    }

    if (!isValidEmail(email)) {
      console.warn('❌ Invalid email format:', email);
      res.status(400).json({ 
        success: false,
        error: 'Invalid email format' 
      });
      return;
    }

    console.log(`📧 Processing email request for: ${email}, type: ${type || 'otp'}`);

    let mailOptions = {};
    let subject = '';

    if (type === 'verification_confirmation') {
      // Send confirmation email
      mailOptions = {
        from: gmailUser || sendgridFromEmail,
        to: email,
        subject: 'BiO Pass - Email Verified Successfully! ✅',
        html: getConfirmationEmailTemplate(userName),
      };
      subject = 'confirmation email';
    } else if (type === 'password_reset') {
      // Send password reset email
      mailOptions = {
        from: gmailUser || sendgridFromEmail,
        to: email,
        subject: 'BiO Pass - Password Reset Request 🔐',
        html: `
          <div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 600px; margin: 0 auto; background: #f5f5f5;">
            <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 40px; text-align: center; color: white;">
              <h1 style="margin: 0; font-size: 32px;">BiO Pass</h1>
              <p style="margin: 10px 0 0 0; font-size: 16px; opacity: 0.9;">Password Reset Request</p>
            </div>
            <div style="background: white; padding: 40px; margin: 20px; border-radius: 10px;">
              <p style="color: #666; line-height: 1.6;">We received a request to reset your password. Click the link below to proceed:</p>
              <div style="text-align: center; margin: 30px 0;">
                <a href="${resetLink}" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; display: inline-block;">Reset Password</a>
              </div>
              <p style="color: #999; font-size: 12px; margin-top: 20px; border-top: 1px solid #eee; padding-top: 20px;">
                If you didn't request this, ignore this email. Your account remains secure.
              </p>
            </div>
          </div>
        `,
      };
      subject = 'password reset email';
    } else {
      // Send OTP email (default)
      if (!otp) {
        console.warn('❌ OTP not provided');
        res.status(400).json({ 
          success: false,
          error: 'OTP is required for otp_verification type' 
        });
        return;
      }

      if (otp.length !== 6 || !/^\d+$/.test(otp)) {
        console.warn('❌ Invalid OTP format:', otp);
        res.status(400).json({ 
          success: false,
          error: 'OTP must be exactly 6 digits' 
        });
        return;
      }

      mailOptions = {
        from: gmailUser || sendgridFromEmail,
        to: email,
        subject: 'BiO Pass - Your OTP Verification Code 🔐',
        html: getOTPEmailTemplate(otp, email),
      };
      subject = 'OTP email';
    }

    try {
      const info = await transporter.sendMail(mailOptions);
      console.log(`✅ ${subject} sent to: ${email}`);
      console.log(`📋 Response: ${info.response}`);
      
      res.status(200).json({ 
        success: true, 
        message: `${subject.charAt(0).toUpperCase() + subject.slice(1)} sent successfully`,
        recipient: email,
        timestamp: new Date().toISOString(),
      });
    } catch (emailError) {
      console.error(`❌ Error sending ${subject}:`, emailError);
      res.status(500).json({ 
        success: false,
        error: `Failed to send ${subject}`,
        details: emailError.message,
        recipient: email,
      });
    }
  } catch (error) {
    console.error('❌ Unhandled error in sendOTPEmail:', error);
    res.status(500).json({
      success: false,
      error: 'Internal server error',
      message: error.message,
    });
  }
});

/**
 * Health check and configuration test endpoint
 */
exports.testEmail = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(200).send();
    return;
  }

  try {
    const testEmail = req.query.email || req.body.email || gmailUser;
    
    if (!testEmail) {
      return res.status(400).json({
        success: false,
        error: 'No email provided for testing'
      });
    }

    if (!isValidEmail(testEmail)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid email format'
      });
    }

    const mailOptions = {
      from: gmailUser || sendgridFromEmail,
      to: testEmail,
      subject: 'BiO Pass - Test Email 🧪',
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 2px solid #667eea; border-radius: 10px;">
          <h1 style="color: #667eea;">BiO Pass - Test Email</h1>
          <p style="color: #666;">This is a test email from your Firebase Cloud Function.</p>
          <div style="background: #e8f5e9; padding: 15px; border-radius: 5px; margin: 20px 0;">
            <p style="color: #2e7d32; margin: 0;"><strong>✅ Status: Email configuration is working!</strong></p>
          </div>
          <p style="color: #999; font-size: 12px; margin-top: 30px;">
            Timestamp: ${new Date().toISOString()}
          </p>
        </div>
      `,
    };

    const info = await transporter.sendMail(mailOptions);
    console.log(`✅ Test email sent to: ${testEmail}`);
    
    res.status(200).json({
      success: true,
      message: 'Test email sent successfully',
      recipient: testEmail,
      emailService: emailService,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    console.error('❌ Test email error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to send test email',
      message: error.message,
    });
  }
});


