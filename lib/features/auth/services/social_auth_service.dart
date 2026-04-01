import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class SocialAuthService {
  SocialAuthService._();

  // ── Google ──────────────────────────────────────────────────────────────────
  static Future<SocialAuthResult> signInWithGoogle() async {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    await googleSignIn.signOut();

    final GoogleSignInAccount? account = await googleSignIn.signIn();
    if (account == null) {
      throw const SocialAuthException('Google sign-in was cancelled.');
    }

    final GoogleSignInAuthentication googleAuth = await account.authentication;

    final String? googleAccessToken = googleAuth.accessToken;
    final String? googleIdToken = googleAuth.idToken;

    if (googleAccessToken == null && googleIdToken == null) {
      throw const SocialAuthException(
        'Unable to get Google auth tokens. Check Google Sign-In setup.',
      );
    }

    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAccessToken,
      idToken: googleIdToken,
    );

    final UserCredential userCredential =
    await FirebaseAuth.instance.signInWithCredential(credential);

    final User? firebaseUser = userCredential.user;
    if (firebaseUser == null) {
      throw const SocialAuthException(
        'Firebase sign-in succeeded but returned no user.',
      );
    }

    final String? firebaseIdToken = await firebaseUser.getIdToken();
    if (firebaseIdToken == null || firebaseIdToken.isEmpty) {
      throw const SocialAuthException('Firebase returned an empty ID token.');
    }

    return SocialAuthResult(
      identifier: firebaseUser.email ?? account.email,
      idToken: firebaseIdToken,
      accessToken: googleAccessToken,
    );
  }

  // ── Apple ───────────────────────────────────────────────────────────────────
  static Future<SocialAuthResult> signInWithApple() async {
    final bool isAvailable = await SignInWithApple.isAvailable();
    print('🍎 Apple available: $isAvailable');

    if (!isAvailable) {
      throw const SocialAuthException(
        'Apple Sign-In is not available on this device.',
      );
    }

    // Step 1 — get Apple credential
    final AuthorizationCredentialAppleID appleCredential =
    await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    print('🍎 Got Apple credential: ${appleCredential.userIdentifier}');

    final String? appleIdToken = appleCredential.identityToken;
    print('🍎 Apple idToken null? ${appleIdToken == null}');

    if (appleIdToken == null) {
      throw const SocialAuthException('Unable to get Apple identity token.');
    }

    // Step 2 — build Firebase credential from Apple tokens
    print('🍎 Building Firebase credential...');
    final OAuthCredential credential = OAuthProvider('apple.com').credential(
      idToken: appleIdToken,
      accessToken: appleCredential.authorizationCode,
    );

    // Step 3 — sign into Firebase
    print('🍎 Signing into Firebase...');
    try {
      final UserCredential userCredential =
      await FirebaseAuth.instance.signInWithCredential(credential);
      print('🍎 Firebase sign-in success: ${userCredential.user?.uid}');

      final User? firebaseUser = userCredential.user;
      if (firebaseUser == null) {
        throw const SocialAuthException(
          'Firebase sign-in succeeded but returned no user.',
        );
      }

      // Step 4 — get Firebase ID token
      print('🍎 Getting Firebase ID token...');
      final String? firebaseIdToken = await firebaseUser.getIdToken();
      print('🍎 Firebase token received: ${firebaseIdToken != null}');

      if (firebaseIdToken == null || firebaseIdToken.isEmpty) {
        throw const SocialAuthException('Firebase returned an empty ID token.');
      }

      final String identifier = (
          firebaseUser.email ??
              appleCredential.email ??
              appleCredential.userIdentifier ??
              ''
      ).trim();
      print('🍎 identifier: $identifier');

      return SocialAuthResult(
        identifier: identifier,
        idToken: firebaseIdToken,
        accessToken: appleCredential.authorizationCode,
      );
    } catch (e) {
      print('🍎 Firebase error type: ${e.runtimeType}');
      print('🍎 Firebase error: $e');
      rethrow;
    }
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

  const SocialAuthResult({this.identifier, this.idToken, this.accessToken});
}