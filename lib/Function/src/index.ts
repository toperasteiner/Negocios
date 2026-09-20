// functions/src/index.ts
import { onRequest } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2/options";
import * as admin from "firebase-admin";
import express, { Request, Response } from "express";
import cors from "cors";

admin.initializeApp();

const REGION = "southamerica-east1";
setGlobalOptions({ region: REGION });

// ------- CORS -------
const allowedOrigins = [
  /^http:\/\/localhost:\d+$/,   // qualquer porta local
  "https://seu-dominio.com",    // troque pelo seu domínio (se tiver)
];
const corsMw = cors({
  origin(origin, cb) {
    if (!origin) return cb(null, true); // apps nativos / curl
    const ok = allowedOrigins.some((o) =>
      typeof o === "string" ? o === origin : o.test(origin)
    );
    cb(ok ? null : new Error("CORS blocked"));
  },
  credentials: true,
});

// ------- App HTTP único -------
const app = express();
app.use(express.json());
app.use(corsMw);

// handler único NA RAIZ "/" (nada de /createCompanyUser aqui)
app.options("*", corsMw); // responde preflight

app.post("/", async (req: Request, res: Response) => {
  try {
    const authz = req.header("authorization") ?? "";
    const match = authz.match(/^Bearer (.+)$/i);
    if (!match) {
      return res.status(401).json({ error: "unauthenticated" });
    }
    const idToken = match[1];
    const decoded = await admin.auth().verifyIdToken(idToken);
    const uid = decoded.uid;

    const email = String(req.body?.email ?? "").trim().toLowerCase();
    const displayName = String(req.body?.displayName ?? "").trim();
    const role = String(req.body?.role ?? "user").trim();
    const permissions = (req.body?.permissions ?? {}) as Record<string, boolean>;
    const sendEmailLink = Boolean(req.body?.sendEmailLink ?? true);

    if (!email || !displayName) {
      return res.status(400).json({ error: "invalid-argument" });
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return res.status(400).json({ error: "invalid-argument" });
    }
    if (!new Set(["admin", "manager", "user"]).has(role)) {
      return res.status(400).json({ error: "invalid-argument" });
    }

    const db = admin.firestore();
    const meSnap = await db.doc(`users/${uid}`).get();
    const me = meSnap.data() ?? {};
    if ((me.role ?? "user") !== "admin") {
      return res.status(403).json({ error: "permission-denied" });
    }

    // idempotência por e-mail
    let userRecord: admin.auth.UserRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(email);
    } catch {
      userRecord = await admin.auth().createUser({ email, displayName, disabled: false });
    }

    const companyId = (me.companyId as string) ?? uid;

    await db.doc(`users/${userRecord.uid}`).set(
      {
        displayName,
        email,
        companyId,
        role,
        permissions,
        active: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    if (sendEmailLink) {
      try {
        const link = await admin.auth().generatePasswordResetLink(email);
        console.log("password reset link:", link);
      } catch (e) {
        console.warn("Falha ao gerar reset link:", (e as Error).message);
      }
    }

    return res.json({ uid: userRecord.uid });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: "internal" });
  }
});

// exporta o function HTTP NA MESMA REGIÃO
export const createCompanyUser = onRequest(
  { region: REGION, memory: "256MiB", timeoutSeconds: 60 },
  app
);
