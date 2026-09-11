import SwiftUI
import LookAfterData
import LookAfterCore

/// Production Authentication & Onboarding View for FlowOS.
public struct AuthView: View {
    
    @ObservedObject var firebase: FirebaseManager = .shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    @State private var isSignUpMode: Bool = false
    @State private var fullName: String = ""
    @State private var emailText: String = ""
    @State private var passwordText: String = ""
    
    @State private var errorMessage: String? = nil
    @State private var isLoading: Bool = false
    @State private var authSuccess: Bool = false
    @State private var welcomeName: String = ""
    @State private var showLicensePrompt: Bool = false
    
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
                        #if SIGN_IN_WITH_APPLE
                        Button(action: { performAppleSignIn() }) {
                            HStack(spacing: 10) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 18))
                                Text("Continue with Apple")
                                    .font(.system(size: 15, weight: .semibold, design: .default))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: DesignSystem.minTouchTarget)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                        }
                        .disabled(isLoading)
                        .opacity(isLoading ? 0.5 : 1)
                        #endif

                        if FirebaseManager.isMockConfiguration {
                            Text("Google Sign-In needs a real Firebase iOS config in Config/GoogleService-Info.plist.")
                                .font(.system(size: 13, weight: .medium, design: .default))
                                .foregroundColor(DesignSystem.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                        } else {
                            Button(action: { performGoogleSignIn() }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "g.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text("Continue with Google")
                                        .font(.system(size: 15, weight: .semibold, design: .default))
                                        .foregroundColor(DesignSystem.accentOnPrimary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: DesignSystem.minTouchTarget)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(DesignSystem.accentPrimary)
                                )
                            }
                            .disabled(isLoading)
                            .opacity(isLoading ? 0.5 : 1)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Divider
                    HStack {
                        Rectangle()
                            .fill(DesignSystem.border)
                            .frame(height: 1)
                        Text("OR")
                            .font(.system(size: 12, weight: .bold, design: .default))
                            .foregroundColor(DesignSystem.textMuted)
                        Rectangle()
                            .fill(DesignSystem.border)
                            .frame(height: 1)
                    }
                    .padding(.horizontal)
                    
                    // Email/Password Form
                    VStack(spacing: 14) {
                        if isSignUpMode {
                            TextField("Full Name", text: $fullName)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 12).fill(DesignSystem.contentSurfaceSubtle))
                                .foregroundColor(.white)
                        }
                        
                        TextField("Email Address", text: $emailText)
                            .textFieldStyle(.plain)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(DesignSystem.contentSurfaceSubtle))
                            .foregroundColor(.white)
                        
                        SecureField("Password", text: $passwordText)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(DesignSystem.contentSurfaceSubtle))
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
                                        .progressViewStyle(CircularProgressViewStyle(tint: DesignSystem.accentOnPrimary))
                                    Text("Signing in...")
                                        .font(.system(size: 15, weight: .semibold, design: .default))
                                } else {
                                    Text(isSignUpMode ? "Create \(UserFacingCopy.productName) Account" : "Sign In")
                                        .font(.system(size: 15, weight: .semibold, design: .default))
                                }
                            }
                            .foregroundColor(DesignSystem.accentOnPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: DesignSystem.minTouchTarget)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(DesignSystem.accentPrimary)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading || emailText.trimmingCharacters(in: .whitespaces).isEmpty || passwordText.isEmpty)
                        .opacity(isLoading ? 0.7 : 1)
                        
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
            
            if isLoading {
                LookAfterChrome.overlayScrim
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
                .modifier(AuthLoadingChrome(reduceTransparency: reduceTransparency))
                .transition(.scale.combined(with: .opacity))
                .zIndex(100)
            }
            
            if authSuccess {
                LookAfterChrome.overlayScrim
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
                        .fill(DesignSystem.contentSurfaceElevated)
                )
                .transition(.scale.combined(with: .opacity))
                .zIndex(101)
            }
        }
        .keyboardDismissToolbar(label: "Done")
        .scrollDismissesKeyboard(.interactively)
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: authSuccess)
        .sheet(isPresented: $showLicensePrompt) {
            NavigationStack {
                LicenseRedeemView(onFinished: {
                    showLicensePrompt = false
                    dismiss()
                })
            }
        }
        .interactiveDismissDisabled(isLoading)
        .accessibilityIdentifier("screen-auth")
    }
    
    // MARK: - SSO
    
    private func performAppleSignIn() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await firebase.signInWithApple()
                welcomeName = UserDefaults.standard.string(forKey: "userName")
                    ?? firebase.userEmail?.components(separatedBy: "@").first
                    ?? "there"
                await finishAuthenticated(offerLicense: true)
            } catch {
                failAuth(error)
            }
        }
    }
    
    private func performGoogleSignIn() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await firebase.signInWithGoogle()
                welcomeName = UserDefaults.standard.string(forKey: "userName")
                    ?? firebase.userEmail?.components(separatedBy: "@").first
                    ?? "there"
                await finishAuthenticated(offerLicense: true)
            } catch {
                failAuth(error)
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
                await finishAuthenticated(offerLicense: true)
            } catch {
                failAuth(error)
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

    private func finishAuthenticated(offerLicense: Bool) async {
        HapticManager.notification(.success)
        withAnimation {
            isLoading = false
            authSuccess = true
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        let needsLicense = offerLicense
            && LicenseManager.shared.proxyClient != nil
            && !LicenseManager.shared.isLicensed
        if needsLicense {
            authSuccess = false
            showLicensePrompt = true
        } else {
            dismiss()
        }
    }

    private func failAuth(_ error: Error) {
        HapticManager.notification(.error)
        withAnimation {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}

private struct AuthLoadingChrome: ViewModifier {
    let reduceTransparency: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(DesignSystem.contentSurfaceElevated))
                .overlay(shape.stroke(DesignSystem.border, lineWidth: 1))
        } else {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
    }
}
