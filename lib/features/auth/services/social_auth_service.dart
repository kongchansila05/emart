import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Handles social sign-in flows and returns a [SocialAuthResult] containing
/// a Firebase ID token that the backend can verify via
/// `verifyFirebaseGoogleToken()` / `verifyFirebasePhoneToken()`.
class SocialAuthService {
  SocialAuthService._();

  // ── Google ──────────────────────────────────────────────────────────────────
  //
  // Flow:
  //   1. google_sign_in  → GoogleSignInAuthentication (Google access token)
  //   2. firebase_auth   → OAuthCredential
  //   3. FirebaseAuth.signInWithCredential → UserCredential
  //   4. user.getIdToken() → Firebase ID token  ✅  (what the backend expects)
  //
  // The backend's verifyFirebaseGoogleToken() validates:
  //   • iss  contains "securetoken.google.com"
  //   • firebase.sign_in_provider == "google.com"
  //   • exp  not expired
  //   • email present
  //
  static Future<SocialAuthResult> signInWithGoogle() async {
    // Force account picker so users can switch accounts.
    final GoogleSignIn googleSignIn = GoogleSignIn();
    await googleSignIn.signOut();

    final GoogleSignInAccount? account = await googleSignIn.signIn();
    if (account == null) {
      throw const SocialAuthException('Google sign-in was cancelled.');
    }

    // Step 1 — get Google credentials.
    final GoogleSignInAuthentication googleAuth =
    await account.authentication;

    final String? googleAccessToken = googleAuth.accessToken;
    final String? googleIdToken     = googleAuth.idToken;

    if (googleAccessToken == null && googleIdToken == null) {
      throw const SocialAuthException(
        'Unable to get Google auth tokens. Check Google Sign-In setup.',
      );
    }

    // Step 2 — build Firebase credential from Google tokens.
    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAccessToken,
      idToken:     googleIdToken,
    );

    // Step 3 — sign into Firebase (creates/links the Firebase user).
    final UserCredential userCredential =
    await FirebaseAuth.instance.signInWithCredential(credential);

    final User? firebaseUser = userCredential.user;
    if (firebaseUser == null) {
      throw const SocialAuthException(
        'Firebase sign-in succeeded but returned no user.',
      );
    }

    // Step 4 — get the Firebase ID token (forceRefresh = false is fine here
    //           since the token was just issued).
    // getIdToken() returns String? in firebase_auth ^5.x so we null-check it.
    final String? firebaseIdToken = await firebaseUser.getIdToken();

    if (firebaseIdToken == null || firebaseIdToken.isEmpty) {
      throw const SocialAuthException(
        'Firebase returned an empty ID token.',
      );
    }

    return SocialAuthResult(
      identifier:  firebaseUser.email ?? account.email,
      idToken:     firebaseIdToken,   // Firebase JWT ✅
      accessToken: googleAccessToken, // kept for optional use
    );
  }

  // ── Apple ───────────────────────────────────────────────────────────────────
  static Future<SocialAuthResult> signInWithApple() async {
    final bool isAvailable = await SignInWithApple.isAvailable();
    if (!isAvailable) {
      throw const SocialAuthException(
        'Apple Sign-In is not available on this device.',
      );
    }

    final AuthorizationCredentialAppleID appleCredential =
    await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    final String? idToken = appleCredential.identityToken;
    if (idToken == null) {
      throw const SocialAuthException('Unable to get Apple identity token.');
    }

    final String identifier =
    (appleCredential.email ?? appleCredential.userIdentifier ?? '').trim();

    return SocialAuthResult(identifier: identifier, idToken: idToken);
  }
}

// ── Supporting types ──────────────────────────────────────────────────────────

class SocialAuthException implements Exception {
  final String message;
  const SocialAuthException(this.message);

  @override
  String toString() => message;
}

class SocialAuthResult {
  final String? identifier;
  final String? idToken;
  final String? accessToken;

  const SocialAuthResult({
    this.identifier,
    this.idToken,
    this.accessToken,
  });
}