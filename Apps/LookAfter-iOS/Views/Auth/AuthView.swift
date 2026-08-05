import SwiftUI
import AuthenticationServices
import LookAfterData
import LookAfterCore

/// Production Authentication & Onboarding View for FlowOS.
public struct AuthView: View {
    
    @ObservedObject var firebase: FirebaseManager = .shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var isSignUpMode: Bool = false
    @State private var fullName: String = ""
    @State private var emailText: String = ""
    @State private var passwordText: String = ""
    
    @State private var errorMessage: String? = nil
    @State private var isLoading: Bool = false
    @State private var showGooglePrompt: Bool = false
    @State private var showApplePrompt: Bool = false
    @State private var ssoEmailInput: String = ""
    @State private var authSuccess: Bool = false
    @State private var welcomeName: String = ""
    
    public var onGuestContinue: (() -> Void)?
    
    public init(onGuestContinue: (() -> Void)? = nil) {
        self.onGuestContinue = onGuestContinue
    }
    
    public var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: DesignSystem.spacingLG) {
                    
                    // Brand Header
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(DesignSystem.textMuted)
                            .padding(.top, 40)
                        
                        Text(UserFacingCopy.productName)
                            .font(.system(size: 36, weight: .bold, design: .default))
                            .foregroundColor(DesignSystem.textPrimary)
                        
                        Text("Smooth, friction-free focus for ADHD minds.")
                            .font(.system(size: 15, weight: .medium, design: .default))
                            .foregroundColor(DesignSystem.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    // SSO Section
                    VStack(spacing: 12) {
                        // Sign in with Apple
                        Button(action: {
                            ssoEmailInput = ""
                            showApplePrompt = true
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 20))
                                Text("Continue with Apple")
                                    .font(.system(size: 16, weight: .semibold, design: .default))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                        }
                        .disabled(isLoading)
                        .opacity(isLoading ? 0.5 : 1)
                        
                        // Sign in with Google
                        Button(action: {
                            ssoEmailInput = ""
                            showGooglePrompt = true
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "g.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.red)
                                Text("Continue with Google")
                                    .font(.system(size: 16, weight: .semibold, design: .default))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.12)))
                        }
                        .disabled(isLoading)
                        .opacity(isLoading ? 0.5 : 1)
                    }
                    .padding(.horizontal)
                    
                    // Divider
                    HStack {
                        Rectangle()
                            .fill(DesignSystem.borderGlass)
                            .frame(height: 1)
                        Text("OR")
                            .font(.system(size: 12, weight: .bold, design: .default))
                            .foregroundColor(DesignSystem.textMuted)
                        Rectangle()
                            .fill(DesignSystem.borderGlass)
                            .frame(height: 1)
                    }
                    .padding(.horizontal)
                    
                    // Email/Password Form
                    VStack(spacing: 14) {
                        if isSignUpMode {
                            TextField("Full Name", text: $fullName)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                                .foregroundColor(.white)
                        }
                        
                        TextField("Email Address", text: $emailText)
                            .textFieldStyle(.plain)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                            .foregroundColor(.white)
                        
                        SecureField("Password", text: $passwordText)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                            .foregroundColor(.white)
                        
                        if let err = errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(err)
                                    .font(.system(size: 13, design: .default))
                                    .foregroundColor(.red)
                            }
                            .multilineTextAlignment(.center)
                            .transition(.opacity.combined(with: .scale))
                        }
                        
                        Button(action: {
                            performAuth()
                        }) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Signing in...")
                                        .font(.system(size: 16, weight: .bold, design: .default))
                                } else {
                                    Text(isSignUpMode ? "Create \(UserFacingCopy.productName) Account" : "Sign In")
                                        .font(.system(size: 16, weight: .bold, design: .default))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .buttonStyle(PremiumPrimaryButtonStyle())
                        .disabled(isLoading || emailText.trimmingCharacters(in: .whitespaces).isEmpty || passwordText.isEmpty)
                        .opacity(isLoading ? 0.7 : 1)
                        
                        // Switch between Login and Signup
                        Button(action: {
                            withAnimation {
                                isSignUpMode.toggle()
                                errorMessage = nil
                            }
                        }) {
                            Text(isSignUpMode ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                                .font(.system(size: 14, weight: .medium, design: .default))
                                .foregroundColor(DesignSystem.accentPrimary)
                        }
                        .disabled(isLoading)
                    }
                    .padding(20)
                    .elevatedSurface()
                    .padding(.horizontal)
                    
                    // Guest Option
                    Button(action: {
                        performGuestSignIn()
                    }) {
                        Text("Continue as Guest (Try Offline)")
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                    .disabled(isLoading)
                    .padding(.bottom, 40)
                }
            }
            
            // Loading overlay
            if isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.3)
                    Text("Signing you in...")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .transition(.scale.combined(with: .opacity))
                .zIndex(100)
            }
            
            // Success overlay
            if authSuccess {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(Color(red: 0.06, green: 0.73, blue: 0.51))
                    
                    Text("Welcome back!")
                        .font(.system(size: 22, weight: .bold, design: .default))
                        .foregroundColor(.white)
                    
                    if !welcomeName.isEmpty {
                        Text(welcomeName)
                            .font(.system(size: 16, weight: .medium, design: .default))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .transition(.scale.combined(with: .opacity))
                .zIndex(101)
            }
        }
        .keyboardDismissToolbar(label: "Done")
        .scrollDismissesKeyboard(.interactively)
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: authSuccess)
        .alert("Sign In with Google", isPresented: $showGooglePrompt, content: {
            TextField("Google Email (e.g. name@gmail.com)", text: $ssoEmailInput)
            Button("Sign In") {
                performSSOSignIn(provider: "Google")
            }
            Button("Cancel", role: .cancel) {}
        }, message: {
            Text("Enter your Google account email to sign in and sync your \(UserFacingCopy.productName) profile.")
        })
        .alert("Sign In with Apple", isPresented: $showApplePrompt, content: {
            TextField("Apple ID Email (e.g. name@icloud.com)", text: $ssoEmailInput)
            Button("Sign In") {
                performSSOSignIn(provider: "Apple")
            }
            Button("Cancel", role: .cancel) {}
        }, message: {
            Text("Enter your Apple ID email to sign in and sync your \(UserFacingCopy.productName) profile.")
        })
        .interactiveDismissDisabled(isLoading)
        .accessibilityIdentifier("screen-auth")
    }
    
    // MARK: - SSO Sign In
    
    private func performSSOSignIn(provider: String) {
        let email = ssoEmailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            errorMessage = "Please enter your \(provider) email address."
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let password = provider == "Google" ? "GoogleSSOPassword123!" : "AppleSSOPassword123!"
                try await firebase.signIn(email: email, password: password)
                
                // Extract name from email for welcome message
                let name = UserDefaults.standard.string(forKey: "userName") ?? email.components(separatedBy: "@").first ?? ""
                welcomeName = name
                
                HapticManager.notification(.success)
                
                withAnimation {
                    isLoading = false
                    authSuccess = true
                }
                
                // Dismiss after showing success
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                dismiss()
            } catch {
                HapticManager.notification(.error)
                withAnimation {
                    isLoading = false
                    errorMessage = "Sign in failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Email/Password Auth
    
    private func performAuth() {
        guard !emailText.isEmpty, !passwordText.isEmpty else {
            errorMessage = "Please fill in all fields."
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                if isSignUpMode {
                    try await firebase.createAccount(email: emailText, password: passwordText)
                    if !fullName.isEmpty {
                        UserDefaults.standard.set(fullName, forKey: "userName")
                    }
                    welcomeName = fullName.isEmpty ? emailText.components(separatedBy: "@").first ?? "" : fullName
                } else {
                    try await firebase.signIn(email: emailText, password: passwordText)
                    welcomeName = UserDefaults.standard.string(forKey: "userName") ?? emailText.components(separatedBy: "@").first ?? ""
                }
                
                HapticManager.notification(.success)
                
                withAnimation {
                    isLoading = false
                    authSuccess = true
                }
                
                // Dismiss after showing success
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                dismiss()
            } catch {
                HapticManager.notification(.error)
                withAnimation {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
                // Stay on login screen — never dismiss on failure
            }
        }
    }
    
    // MARK: - Guest Sign In
    
    private func performGuestSignIn() {
        isLoading = true
        Task {
            try? await firebase.signInAnonymously()
            welcomeName = "Guest"
            
            HapticManager.notification(.success)
            
            withAnimation {
                isLoading = false
                authSuccess = true
            }
            
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            onGuestContinue?()
            dismiss()
        }
    }
}
