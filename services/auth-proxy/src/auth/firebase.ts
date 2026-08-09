import * as admin from "firebase-admin";
import type { AppConfig } from "../config";

let initialized = false;

export function initFirebase(config: AppConfig): void {
  if (initialized) return;

  if (config.firebaseServiceAccountJson) {
    const parsed = JSON.parse(config.firebaseServiceAccountJson) as admin.ServiceAccount;
    admin.initializeApp({
      credential: admin.credential.cert(parsed),
      projectId: config.firebaseProjectId,
    });
  } else {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: config.firebaseProjectId,
    });
  }
  initialized = true;
}

export type VerifiedUser = {
  uid: string;
  email?: string;
};

export async function verifyFirebaseIdToken(idToken: string): Promise<VerifiedUser> {
  const decoded = await admin.auth().verifyIdToken(idToken);
  return {
    uid: decoded.uid,
    email: decoded.email,
  };
}
