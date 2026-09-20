// functions/src/index.ts
import { onRequest, onCall, HttpsError } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2/options";
import * as admin from "firebase-admin";
import express, { Request, Response } from "express";
import cors from "cors";
import { google } from "googleapis";
import { onObjectFinalized } from "firebase-functions/v2/storage";
import vision from "@google-cloud/vision";

if (!admin.apps.length) {
  admin.initializeApp();
}

const REGION = "southamerica-east1";
setGlobalOptions({ region: REGION });

// ------- CORS -------
const allowedOrigins = [
  /^http:\/\/localhost:\d+$/,
  "https://seu-dominio.com",
];

const corsMw = cors({
  origin(origin, cb) {
    if (!origin) return cb(null, true);
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
app.options("*", corsMw);

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

    let userRecord: admin.auth.UserRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(email);
    } catch {
      userRecord = await admin.auth().createUser({
        email,
        displayName,
        disabled: false,
      });
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

export const createCompanyUser = onRequest(
  { region: REGION, memory: "256MiB", timeoutSeconds: 60 },
  app
);

async function assertAdminImagem(uidAuth: string): Promise<void> {
  const userSnap = await admin
    .firestore()
    .collection("users")
    .doc(uidAuth)
    .get();

  if (!userSnap.exists) {
    throw new HttpsError("permission-denied", "Usuário não encontrado.");
  }

  const user = userSnap.data() || {};
  const email = String(user.email ?? user.emailKey ?? "")
    .trim()
    .toLowerCase();

  if (email !== "dani@dani.com") {
    throw new HttpsError("permission-denied", "Sem permissão.");
  }
}

function validarPathImagemPendente(pathOriginal: string): {
  uidDono: string;
  nomeArquivo: string;
} {
  if (!pathOriginal.startsWith("produtos_pendentes/")) {
    throw new HttpsError("invalid-argument", "Caminho fora de produtos_pendentes.");
  }

  const partes = pathOriginal.split("/");

  if (
    partes.length < 3 ||
    partes[0] !== "produtos_pendentes" ||
    !partes[1] ||
    !partes[2] ||
    !/\.(jpg|jpeg|png|webp)$/i.test(partes[2])
  ) {
    throw new HttpsError(
      "invalid-argument",
      `Caminho inválido da imagem: ${pathOriginal}`
    );
  }

  return {
    uidDono: partes[1],
    nomeArquivo: partes[2],
  };
}

export const aprovarImagemProdutoManual = onCall(
  { region: REGION, memory: "256MiB", timeoutSeconds: 60 },
  async (request) => {
    const uidAuth = request.auth?.uid;
    const produtoId = String(request.data?.produtoId ?? "").trim();
    const pathOriginal = String(request.data?.pathOriginal ?? "").trim();

    if (!uidAuth) {
      throw new HttpsError("unauthenticated", "Usuário não autenticado.");
    }

    await assertAdminImagem(uidAuth);

    if (!produtoId || !pathOriginal) {
      throw new HttpsError("invalid-argument", "Dados inválidos.");
    }

    const { uidDono, nomeArquivo } = validarPathImagemPendente(pathOriginal);

    const destino = `produtos/${uidDono}/${nomeArquivo}`;
    const bucket = admin.storage().bucket();

    const [exists] = await bucket.file(pathOriginal).exists();
    if (!exists) {
      throw new HttpsError(
        "not-found",
        `Arquivo não encontrado no Storage: ${pathOriginal}`
      );
    }

    await bucket.file(pathOriginal).copy(bucket.file(destino));

    await admin.firestore().collection("produtos").doc(produtoId).update({
      fotos: admin.firestore.FieldValue.arrayUnion(destino),
      fotosPendentes: admin.firestore.FieldValue.arrayRemove(pathOriginal),
      imagemStatus: "aprovada",
      imagemAprovada: true,
      imagemMotivoRecusa: null,
      imagemAprovadaManual: true,
      imagemAprovadaPor: uidAuth,
      imagemAprovadaEm: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await bucket.file(pathOriginal).delete().catch(() => null);

    return { ok: true, destino };
  }
);

export const recusarImagemProdutoManual = onCall(
  { region: REGION, memory: "256MiB", timeoutSeconds: 60 },
  async (request) => {
    const uidAuth = request.auth?.uid;
    const produtoId = String(request.data?.produtoId ?? "").trim();
    const pathOriginal = String(request.data?.pathOriginal ?? "").trim();
    const motivo = String(request.data?.motivo ?? "").trim();

    if (!uidAuth) {
      throw new HttpsError("unauthenticated", "Usuário não autenticado.");
    }

    await assertAdminImagem(uidAuth);

    if (!produtoId || !pathOriginal) {
      throw new HttpsError("invalid-argument", "Dados inválidos.");
    }

    validarPathImagemPendente(pathOriginal);

    await admin.firestore().collection("produtos").doc(produtoId).update({
      fotosPendentes: admin.firestore.FieldValue.arrayRemove(pathOriginal),
      fotosRecusadas: admin.firestore.FieldValue.arrayUnion(pathOriginal),
      imagemStatus: "recusada",
      imagemAprovada: false,
      imagemMotivoRecusa: motivo || "Imagem recusada manualmente.",
      imagemRecusadaManual: true,
      imagemRecusadaPor: uidAuth,
      imagemRecusadaEm: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ok: true };
  }
);

// ------- Callable: validar assinatura Google Play -------
export const validateGoogleSubscription = onCall(
  { region: REGION, memory: "256MiB", timeoutSeconds: 60 },
  async (request) => {
    console.log("========== validateGoogleSubscription START ==========");

    const data = request.data || {};
    console.log("request.data:", JSON.stringify(data));
    console.log("request.auth:", JSON.stringify(request.auth ?? null));

    const authUid = String(request.auth?.uid ?? "").trim();
    const uid = String(data.uid ?? "").trim();
    const productId = String(data.productId ?? "").trim().toLowerCase();
    const purchaseToken = String(data.purchaseToken ?? "").trim();

    console.log("authUid:", authUid || null);
    console.log("uid recebido do app:", uid || null);
    console.log("productId:", productId || null);
    console.log("purchaseToken vazio?:", purchaseToken ? "nao" : "sim");

    if (!uid || !productId || !purchaseToken) {
      console.log("ERRO: dados obrigatórios ausentes");
      throw new HttpsError(
        "invalid-argument",
        "Dados obrigatórios não enviados."
      );
    }

    if (!authUid) {
      console.warn("AUTH NULL - usando UID do payload:", uid);

      if (!uid) {
        throw new HttpsError(
          "unauthenticated",
          "Usuário não autenticado e UID não informado."
        );
      }
    } else if (authUid !== uid) {
      console.log("ERRO: UID inconsistente entre request.auth.uid e data.uid");
      throw new HttpsError(
        "permission-denied",
        "UID inconsistente entre autenticação e requisição."
      );
    }

    try {
      const playAuth = new google.auth.GoogleAuth({
        scopes: ["https://www.googleapis.com/auth/androidpublisher"],
      });

      const androidpublisher = google.androidpublisher({
        version: "v3",
        auth: playAuth,
      });

      const packageName = "br.com.danielsousa.pedidos";
      console.log("packageName:", packageName);

      let response;
      try {
        console.log("Consultando assinatura na Google Play...");
        response = await androidpublisher.purchases.subscriptionsv2.get({
          packageName,
          token: purchaseToken,
        });
      } catch (playError: any) {
        console.error(
          "ERRO GOOGLE PLAY - response.data:",
          JSON.stringify(playError?.response?.data ?? null)
        );
        console.error(
          "ERRO GOOGLE PLAY - message:",
          playError?.message ?? playError
        );

        throw new HttpsError(
          "failed-precondition",
          "Erro ao validar compra na Google Play."
        );
      }

      console.log("response.data:", JSON.stringify(response.data));

      const subscription = response.data || {};
      const state = String(
        subscription.subscriptionState || "SUBSCRIPTION_STATE_UNSPECIFIED"
      );

      const lineItem =
        Array.isArray(subscription.lineItems) && subscription.lineItems.length > 0 ?
          subscription.lineItems[0] :
          null;

      console.log("subscriptionState:", state);
      console.log("lineItem encontrado?:", lineItem ? "sim" : "nao");
      console.log("lineItem:", JSON.stringify(lineItem));

      const expiryTimeRaw = lineItem?.expiryTime ?? null;
      const expiryDate = expiryTimeRaw ? new Date(expiryTimeRaw) : null;
      const expiryTimestamp = expiryDate ?
        admin.firestore.Timestamp.fromDate(expiryDate) :
        null;

      const nowDate = new Date();
      const nowTs = admin.firestore.Timestamp.fromDate(nowDate);

      const latestOrderId =
        subscription.latestOrderId ||
        subscription.externalAccountIdentifiers?.obfuscatedExternalAccountId ||
        null;

      const stateAllowsEntitlement =
        state === "SUBSCRIPTION_STATE_ACTIVE" ||
        state === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD";

      const notExpired =
  expiryDate != null && expiryDate.getTime() > nowDate.getTime();

      const active = stateAllowsEntitlement && notExpired;

      const autoRenewing = active;

      const PLAN_MAP: Record<string, string> = {
        starter_mensal: "starter",
        starter_monthly: "starter",
        starter_semestral: "starter",
        starter_semiannual: "starter",
        starter_anual: "starter",
        starter_annual: "starter",

        premium_mensal: "premium",
        premium_monthly: "premium",
        premium_semestral: "premium",
        premium_semiannual: "premium",
        premium_anual: "premium",
        premium_annual: "premium",
      };

      let planId = "free";

      if (active) {
        if (PLAN_MAP[productId]) {
          planId = PLAN_MAP[productId];
        } else if (productId.includes("premium")) {
          planId = "premium";
        } else if (productId.includes("starter")) {
          planId = "starter";
        }
      }

      let billingCycle = "";
      if (productId.includes("mensal") || productId.includes("monthly")) {
        billingCycle = "monthly";
      } else if (
        productId.includes("semestral") ||
        productId.includes("semiannual")
      ) {
        billingCycle = "semiannual";
      } else if (
        productId.includes("anual") ||
        productId.includes("annual")
      ) {
        billingCycle = "annual";
      }

      console.log("active:", active);
      console.log("autoRenewing:", autoRenewing);
      console.log("planId definido:", planId);
      console.log("billingCycle:", billingCycle);
      console.log("latestOrderId:", latestOrderId);
      console.log("expiryTimeRaw:", expiryTimeRaw);

      const db = admin.firestore();
      const userRef = db.collection("users").doc(uid);

      console.log(`Lendo users/${uid}`);
      const userSnap = await userRef.get();

      if (!userSnap.exists) {
        console.log(`ERRO: usuário não encontrado em users/${uid}`);
        throw new HttpsError("not-found", "Usuário não encontrado.");
      }

      const userData = userSnap.data() || {};
      console.log("userData:", JSON.stringify(userData));

      const companyId = String(userData.companyId || uid).trim() || uid;
      console.log("companyId resolvido:", companyId);

      const subscriptionRef = db.collection("subscriptions").doc(companyId);

      const userPayload = {
        plan: planId,
        planId,
        planStatus: active ? "active" : "expired",
        subscriptionActive: active,
        subscriptionStatus: state,
        subscriptionProductId: productId,
        purchaseToken,
        billingCycle,
        planStartAt:
          active ?
            (userData.planStartAt ?? admin.firestore.FieldValue.serverTimestamp()) :
            null,
        planEndAt: expiryTimestamp,
        subscriptionProvider: "google_play",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Commit user aliases and the authoritative subscription together.

      const subscriptionPayload = {
        companyId,
        userId: uid,
        planId,
        status: active ? "active" : "expired",
        billingCycle,
        productId,
        purchaseToken,
        orderId: latestOrderId,
        purchaseSource: "google_play",
        autoRenewing,
        trial: false,
        purchaseDate:
          userData.purchaseDate ?? admin.firestore.FieldValue.serverTimestamp(),
        startedAt:
          userData.planStartAt ?? admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: expiryTimestamp,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        validatedAt: nowTs,
        googlePlayState: state,
      };

      const batch = db.batch();
      batch.set(userRef, userPayload, { merge: true });
      batch.set(subscriptionRef, subscriptionPayload, { merge: true });
      await batch.commit();
      console.log(`subscriptions/${companyId} atualizado com sucesso`);

      const result = {
        uid,
        companyId,
        planId,
        active,
        status: state,
        billingCycle,
        productId,
        expiry: expiryTimeRaw,
        orderId: latestOrderId,
      };

      console.log("RETORNO:", JSON.stringify(result));
      console.log("========== validateGoogleSubscription END ==========");

      return result;
    } catch (error: any) {
      console.error("validateGoogleSubscription error:", error);

      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError(
        "internal",
        `Erro ao validar assinatura: ${error?.message || error}`
      );
    }
  }
);

const db = admin.firestore();
const bucket = admin.storage().bucket();

// const client = new vision.ImageAnnotatorClient();

type Likelihood =
  | "UNKNOWN"
  | "VERY_UNLIKELY"
  | "UNLIKELY"
  | "POSSIBLE"
  | "LIKELY"
  | "VERY_LIKELY";

function isLikely(value?: string | null): boolean {
  return value === "LIKELY" || value === "VERY_LIKELY";
}

function isPossible(value?: string | null): boolean {
  return value === "POSSIBLE";
}

function hasForbiddenLabel(labels: string[]): string | null {
  const forbidden = [
    "weapon",
    "gun",
    "firearm",
    "rifle",
    "handgun",
    "knife",
    "blade",
    "drug",
    "cannabis",
    "marijuana",
    "cocaine",
    "narcotic",
    "alcohol",
    "beer",
    "wine",
    "liquor",
    "cigarette",
    "smoking",
    "tobacco",
  ];

  const normalizedLabels = labels.map((l) => l.toLowerCase());

  for (const forbiddenWord of forbidden) {
    if (normalizedLabels.some((label) => label.includes(forbiddenWord))) {
      return forbiddenWord;
    }
  }

  return null;
}

function extractProdutoId(filePath: string): string | null {
  // esperado:
  // produtos_pendentes/{uid}/{produtoId}_{timestamp}.jpg
  const parts = filePath.split("/");

  if (parts.length < 3) return null;
  if (parts[0] !== "produtos_pendentes") return null;

  const fileName = parts[2];
  const produtoId = fileName.split("_")[0];

  return produtoId || null;
}
function extractUid(filePath: string): string | null {
  // esperado:
  // produtos_pendentes/{uid}/{produtoId}_{timestamp}.jpg
  const parts = filePath.split("/");

  if (parts.length < 3) return null;
  if (parts[0] !== "produtos_pendentes") return null;

  return parts[1] || null;
}

export const moderarImagemProduto = onObjectFinalized(
  {
    region: "southamerica-east1",
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (event) => {
    const object = event.data;
    const filePath = object.name;
    const contentType = object.contentType || "";

    if (!filePath) return;

    if (!filePath.startsWith("produtos_pendentes/")) {
      console.log("Ignorando arquivo fora de produtos_pendentes:", filePath);
      return;
    }

    if (!contentType.startsWith("image/")) {
      console.log("Ignorando arquivo que não é imagem:", filePath);
      return;
    }

    const produtoId = extractProdutoId(filePath);
    const uid = extractUid(filePath);

    if (!produtoId || !uid) {
      console.log("ProdutoId ou UID não encontrado no path:", filePath);
      return;
    }

    const gcsUri = `gs://${object.bucket}/${filePath}`;

    console.log("Moderando imagem:", gcsUri);

    const client = new vision.ImageAnnotatorClient();

    const [result] = await client.annotateImage({
      image: {
        source: {
          imageUri: gcsUri,
        },
      },
      features: [
        { type: "SAFE_SEARCH_DETECTION" },
        { type: "LABEL_DETECTION", maxResults: 20 },
      ],
    });

    const safe = result.safeSearchAnnotation || {};
    const labels =
      result.labelAnnotations?.map((label) => label.description || "") || [];

    const adult = safe.adult as Likelihood | undefined;
    const racy = safe.racy as Likelihood | undefined;
    const violence = safe.violence as Likelihood | undefined;
    const medical = safe.medical as Likelihood | undefined;
    const spoof = safe.spoof as Likelihood | undefined;

    const forbiddenLabel = hasForbiddenLabel(labels);

    let status: "aprovada" | "recusada" | "revisao_manual" = "aprovada";
    let motivo: string | null = null;

    if (isLikely(adult)) {
      status = "recusada";
      motivo = "Conteúdo adulto detectado.";
    } else if (isLikely(racy)) {
      status = "recusada";
      motivo = "Conteúdo sugestivo/impróprio detectado.";
    } else if (isLikely(violence)) {
      status = "recusada";
      motivo = "Conteúdo violento detectado.";
    } else if (forbiddenLabel) {
      status = "recusada";
      motivo = `Conteúdo proibido detectado: ${forbiddenLabel}.`;
    } else if (isPossible(adult) || isPossible(racy) || isPossible(violence)) {
      status = "revisao_manual";
      motivo = "Imagem precisa de revisão manual.";
    }

    const produtoRef = db.collection("produtos").doc(produtoId);

    const moderacao = {
      adult: adult || null,
      racy: racy || null,
      violence: violence || null,
      medical: medical || null,
      spoof: spoof || null,
      labels,
      forbiddenLabel,
      analisadoEm: admin.firestore.FieldValue.serverTimestamp(),
      pathOriginal: filePath,
      gcsUri,
    };

    if (status === "aprovada") {
      const nomeArquivo = filePath.split("/").pop();
      const destino = `produtos/${uid}/${nomeArquivo}`;

      await bucket.file(filePath).copy(bucket.file(destino));

      await produtoRef.update({
        fotos: admin.firestore.FieldValue.arrayUnion(destino),
        fotosPendentes: admin.firestore.FieldValue.arrayRemove(filePath),
        imagemStatus: "aprovada",
        imagemAprovada: true,
        imagemMotivoRecusa: null,
        imagemModeracao: moderacao,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await bucket.file(filePath).delete().catch(() => null);

      console.log("Imagem aprovada:", destino);
      return;
    }

    if (status === "recusada") {
      await produtoRef.update({
        fotosPendentes: admin.firestore.FieldValue.arrayRemove(filePath),
        fotosRecusadas: admin.firestore.FieldValue.arrayUnion(filePath),
        imagemStatus: "recusada",
        imagemAprovada: false,
        imagemMotivoRecusa: motivo,
        imagemModeracao: moderacao,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log("Imagem recusada:", motivo);
      return;
    }

    await produtoRef.update({
      imagemStatus: "revisao_manual",
      imagemAprovada: false,
      imagemMotivoRecusa: motivo,
      imagemModeracao: moderacao,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log("Imagem enviada para revisão manual:", filePath);
  }
);

// ============================================================================
// AGENDA PÚBLICA - CONSULTAR DISPONIBILIDADE
// ============================================================================
// ============================================================================
// AGENDA PÚBLICA - CONSULTAR DISPONIBILIDADE
// ============================================================================

type AgendaPeriodo = {
  inicio: string;
  fim: string;
};

type AgendaDia = {
  ativo?: boolean;
  periodos?: AgendaPeriodo[];
};

type AgendaIntervalo = {
  inicio: Date;
  fim: Date;
};

type AgendaDataInfo = {
  ano: number;
  mes: number;
  dia: number;
  inicioDia: Date;
  fimDia: Date;
  diaSemana: string;
};

const AGENDA_INTERVALO_GRADE_MINUTOS = 15;

const AGENDA_DIAS: Record<number, string> = {
  0: "domingo",
  1: "segunda",
  2: "terca",
  3: "quarta",
  4: "quinta",
  5: "sexta",
  6: "sabado",
};

/*
 * Inicialmente estamos considerando horário de Brasília/São Paulo (-03:00).
 *
 * Futuramente podemos gravar o timezone da empresa na configuração
 * da agenda, caso seja necessário atender empresas de outros fusos.
 */
const AGENDA_OFFSET_HORAS = -3;

function agendaHorarioParaMinutos(horario: string): number | null {
  const match = /^(\d{2}):(\d{2})$/.exec(horario.trim());

  if (!match) {
    return null;
  }

  const hora = Number(match[1]);
  const minuto = Number(match[2]);

  if (
    hora < 0 ||
    hora > 23 ||
    minuto < 0 ||
    minuto > 59
  ) {
    return null;
  }

  return hora * 60 + minuto;
}

function agendaMinutosParaHorario(minutos: number): string {
  const hora = Math.floor(minutos / 60);
  const minuto = minutos % 60;

  return (
    `${String(hora).padStart(2, "0")}:` +
    `${String(minuto).padStart(2, "0")}`
  );
}

function agendaDataSP(
  ano: number,
  mes: number,
  dia: number,
  minutos: number
): Date {
  const hora = Math.floor(minutos / 60);
  const minuto = minutos % 60;

  const anoTexto = String(ano).padStart(4, "0");
  const mesTexto = String(mes).padStart(2, "0");
  const diaTexto = String(dia).padStart(2, "0");
  const horaTexto = String(hora).padStart(2, "0");
  const minutoTexto = String(minuto).padStart(2, "0");

  return new Date(
    `${anoTexto}-${mesTexto}-${diaTexto}` +
    `T${horaTexto}:${minutoTexto}:00-03:00`
  );
}

function agendaParseData(valor: string): AgendaDataInfo | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(valor);

  if (!match) {
    return null;
  }

  const ano = Number(match[1]);
  const mes = Number(match[2]);
  const dia = Number(match[3]);

  const validacao = new Date(Date.UTC(ano, mes - 1, dia));

  if (
    validacao.getUTCFullYear() !== ano ||
    validacao.getUTCMonth() !== mes - 1 ||
    validacao.getUTCDate() !== dia
  ) {
    return null;
  }

  const inicioDia = agendaDataSP(
    ano,
    mes,
    dia,
    0
  );

  const proximoDiaUtc = new Date(
    Date.UTC(
      ano,
      mes - 1,
      dia + 1
    )
  );

  const fimDia = agendaDataSP(
    proximoDiaUtc.getUTCFullYear(),
    proximoDiaUtc.getUTCMonth() + 1,
    proximoDiaUtc.getUTCDate(),
    0
  );

  return {
    ano,
    mes,
    dia,
    inicioDia,
    fimDia,
    diaSemana: AGENDA_DIAS[validacao.getUTCDay()],
  };
}

function agendaDate(valor: unknown): Date | null {
  if (valor instanceof admin.firestore.Timestamp) {
    return valor.toDate();
  }

  if (valor instanceof Date) {
    return valor;
  }

  return null;
}

function agendaOverlap(
  inicioA: Date,
  fimA: Date,
  inicioB: Date,
  fimB: Date
): boolean {
  return (
    inicioA.getTime() < fimB.getTime() &&
    fimA.getTime() > inicioB.getTime()
  );
}

function agendaHorarios(
  valor: unknown
): Record<string, AgendaDia> | null {
  if (
    valor &&
    typeof valor === "object" &&
    !Array.isArray(valor)
  ) {
    return valor as Record<string, AgendaDia>;
  }

  return null;
}

function agendaHojeSP(): {
  ano: number;
  mes: number;
  dia: number;
  } {
  const agora = new Date();

  /*
   * Converte o instante atual para a representação
   * de calendário do horário -03:00.
   */
  const ajustado = new Date(
    agora.getTime() +
    AGENDA_OFFSET_HORAS * 60 * 60 * 1000
  );

  return {
    ano: ajustado.getUTCFullYear(),
    mes: ajustado.getUTCMonth() + 1,
    dia: ajustado.getUTCDate(),
  };
}

function agendaSomarDias(
  ano: number,
  mes: number,
  dia: number,
  quantidade: number
): {
  ano: number;
  mes: number;
  dia: number;
} {
  const data = new Date(
    Date.UTC(
      ano,
      mes - 1,
      dia + quantidade
    )
  );

  return {
    ano: data.getUTCFullYear(),
    mes: data.getUTCMonth() + 1,
    dia: data.getUTCDate(),
  };
}

function agendaFormatarData(
  ano: number,
  mes: number,
  dia: number
): string {
  return (
    `${String(ano).padStart(4, "0")}-` +
    `${String(mes).padStart(2, "0")}-` +
    `${String(dia).padStart(2, "0")}`
  );
}

function agendaGerarHorariosDia(
  di: AgendaDataInfo,
  horariosEfetivos: Record<string, AgendaDia>,
  ocupacaoMinutos: number,
  bloqueios: AgendaIntervalo[],
  agendamentos: AgendaIntervalo[],
  agora: Date
): string[] {
  const diaConfigurado = horariosEfetivos[di.diaSemana];

  if (
    !diaConfigurado ||
    diaConfigurado.ativo !== true ||
    !Array.isArray(diaConfigurado.periodos)
  ) {
    return [];
  }

  const horarios: string[] = [];

  for (const periodo of diaConfigurado.periodos) {
    const inicioPeriodo = agendaHorarioParaMinutos(
      String(periodo.inicio ?? "")
    );

    const fimPeriodo = agendaHorarioParaMinutos(
      String(periodo.fim ?? "")
    );

    if (
      inicioPeriodo == null ||
      fimPeriodo == null ||
      fimPeriodo <= inicioPeriodo
    ) {
      continue;
    }

    for (
      let minuto = inicioPeriodo;
      minuto + ocupacaoMinutos <= fimPeriodo;
      minuto += AGENDA_INTERVALO_GRADE_MINUTOS
    ) {
      const inicio = agendaDataSP(
        di.ano,
        di.mes,
        di.dia,
        minuto
      );

      const fim = new Date(
        inicio.getTime() +
        ocupacaoMinutos * 60 * 1000
      );

      /*
       * Não apresenta horário que já passou.
       */
      if (inicio.getTime() <= agora.getTime()) {
        continue;
      }

      const possuiBloqueio = bloqueios.some(
        (bloqueio) =>
          agendaOverlap(
            inicio,
            fim,
            bloqueio.inicio,
            bloqueio.fim
          )
      );

      if (possuiBloqueio) {
        continue;
      }

      const possuiAgendamento = agendamentos.some(
        (agendamento) =>
          agendaOverlap(
            inicio,
            fim,
            agendamento.inicio,
            agendamento.fim
          )
      );

      if (possuiAgendamento) {
        continue;
      }

      horarios.push(
        agendaMinutosParaHorario(minuto)
      );
    }
  }

  return [...new Set(horarios)].sort();
}

export const consultarDisponibilidadeAgenda = onCall(
  {
    region: REGION,
    memory: "256MiB",
    timeoutSeconds: 60,
  },
  async (request) => {
    try {
      const slug = String(
        request.data?.slug ?? ""
      ).trim().toLowerCase();

      const servicoId = String(
        request.data?.servicoId ?? ""
      ).trim();

      const profissionalId = String(
        request.data?.profissionalId ?? ""
      ).trim();

      const data = String(
        request.data?.data ?? ""
      ).trim();

      /*
       * Mantemos compatibilidade com a versão anterior:
       *
       * Se a chamada enviar uma data e não enviar modo,
       * consideramos automaticamente "horarios".
       *
       * Se não enviar data, consideramos "datas".
       */
      const modoRecebido = String(
        request.data?.modo ?? ""
      ).trim().toLowerCase();

      const modo = modoRecebido ||
        (data ? "horarios" : "datas");

      if (
        !slug ||
        !servicoId ||
        !profissionalId
      ) {
        throw new HttpsError(
          "invalid-argument",
          "Slug, serviço e profissional são obrigatórios."
        );
      }

      if (
        modo !== "datas" &&
        modo !== "horarios"
      ) {
        throw new HttpsError(
          "invalid-argument",
          "Modo inválido. Use datas ou horarios."
        );
      }

      if (
        modo === "horarios" &&
        !data
      ) {
        throw new HttpsError(
          "invalid-argument",
          "A data é obrigatória para consultar horários."
        );
      }

      /*
       * ======================================================
       * PÁGINA PÚBLICA
       * ======================================================
       */
      const paginaSnap = await db
        .collection("agenda_paginas_publicas")
        .doc(slug)
        .get();

      if (!paginaSnap.exists) {
        throw new HttpsError(
          "not-found",
          "Página de agendamento não encontrada."
        );
      }

      const pagina = paginaSnap.data() || {};

      const companyId = String(
        pagina.companyId ?? ""
      ).trim();

      /*
       * O controller público já trabalha com ativo == true.
       * Mantemos a mesma regra no backend.
       */
      if (
        !companyId ||
        pagina.ativo !== true
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Página de agendamento indisponível."
        );
      }

      /*
       * ======================================================
       * SERVIÇO
       * ======================================================
       */
      const servicoSnap = await db
        .collection("agenda_servicos_publicos")
        .doc(companyId)
        .collection("servicos")
        .doc(servicoId)
        .get();

      if (!servicoSnap.exists) {
        throw new HttpsError(
          "not-found",
          "Serviço não encontrado."
        );
      }

      const servico = servicoSnap.data() || {};

      if (
        servico.ativo !== true ||
        String(
          servico.companyId ?? companyId
        ).trim() !== companyId
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Serviço indisponível."
        );
      }

      const duracao = Math.ceil(
        Number(
          servico.duracaoMinutos ?? 0
        )
      );

      const buffer = Math.ceil(
        Number(
          servico.intervaloAposAtendimentoMinutos ?? 0
        )
      );

      if (
        !Number.isFinite(duracao) ||
        duracao <= 0 ||
        !Number.isFinite(buffer) ||
        buffer < 0
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Duração do serviço inválida."
        );
      }

      const ocupacao = duracao + buffer;

      /*
       * ======================================================
       * PROFISSIONAL
       * ======================================================
       */
      const profissionalSnap = await db
        .collection("agenda_profissionais_publicos")
        .doc(companyId)
        .collection("profissionais")
        .doc(profissionalId)
        .get();

      if (!profissionalSnap.exists) {
        throw new HttpsError(
          "not-found",
          "Profissional não encontrado."
        );
      }

      const profissional =
        profissionalSnap.data() || {};

      const servicosIds = Array.isArray(
        profissional.servicosIds
      ) ?
        profissional.servicosIds.map(
          (valor: unknown) => String(valor)
        ) :
        [];

      if (
        profissional.ativo !== true ||
        String(
          profissional.companyId ?? companyId
        ).trim() !== companyId ||
        !servicosIds.includes(servicoId)
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Profissional indisponível para este serviço."
        );
      }

      /*
       * ======================================================
       * HORÁRIO DA EMPRESA
       * ======================================================
       */
      const configuracaoSnap = await db
        .collection("agenda_configuracoes")
        .doc(companyId)
        .get();

      if (!configuracaoSnap.exists) {
        if (modo === "datas") {
          return {
            datas: [],
          };
        }

        return {
          data,
          horarios: [],
        };
      }

      const horariosEmpresa = agendaHorarios(
        (configuracaoSnap.data() || {})
          .horariosFuncionamento
      );

      if (!horariosEmpresa) {
        if (modo === "datas") {
          return {
            datas: [],
          };
        }

        return {
          data,
          horarios: [],
        };
      }

      let horariosEfetivos = horariosEmpresa;

      /*
       * ======================================================
       * HORÁRIO DO PROFISSIONAL
       * ======================================================
       */
      const horarioProfissionalSnap = await db
        .collection("agenda_profissionais_horarios")
        .doc(profissionalId)
        .get();

      if (horarioProfissionalSnap.exists) {
        const horarioProfissional =
          horarioProfissionalSnap.data() || {};

        if (
          String(
            horarioProfissional.companyId ??
            companyId
          ).trim() !== companyId
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Horário do profissional inválido."
          );
        }

        if (
          horarioProfissional
            .usaHorarioPadraoEmpresa === false
        ) {
          const horarioProprio = agendaHorarios(
            horarioProfissional.horarios
          );

          /*
           * Mantém o mesmo comportamento da tela atual:
           * se o mapa personalizado estiver malformado,
           * utilizamos o horário padrão da empresa.
           */
          if (horarioProprio) {
            horariosEfetivos = horarioProprio;
          }
        }
      }

      const agora = new Date();

      /*
       * ======================================================
       * MODO HORÁRIOS
       * ======================================================
       */
      if (modo === "horarios") {
        const di = agendaParseData(data);

        if (!di) {
          throw new HttpsError(
            "invalid-argument",
            "Data inválida. Use AAAA-MM-DD."
          );
        }

        if (
          di.fimDia.getTime() <=
          agora.getTime()
        ) {
          return {
            data,
            horarios: [],
          };
        }

        const bloqueiosSnap = await db
          .collection("agenda_bloqueios")
          .where(
            "companyId",
            "==",
            companyId
          )
          .where(
            "dataInicio",
            "<",
            admin.firestore.Timestamp.fromDate(
              di.fimDia
            )
          )
          .get();

        const bloqueios: AgendaIntervalo[] =
          bloqueiosSnap.docs
            .map((doc) => doc.data())
            .filter((bloqueio) => {
              if (
                bloqueio.ativo === false
              ) {
                return false;
              }

              const inicio = agendaDate(
                bloqueio.dataInicio
              );

              const fim = agendaDate(
                bloqueio.dataFim
              );

              const bloqueiaProfissional =
                bloqueio.todosProfissionais === true ||
                String(
                  bloqueio.profissionalId ?? ""
                ).trim() === profissionalId;

              return (
                inicio != null &&
                fim != null &&
                bloqueiaProfissional &&
                agendaOverlap(
                  inicio,
                  fim,
                  di.inicioDia,
                  di.fimDia
                )
              );
            })
            .map((bloqueio) => ({
              inicio: agendaDate(
                bloqueio.dataInicio
              )!,
              fim: agendaDate(
                bloqueio.dataFim
              )!,
            }));

        const agendamentosSnap = await db
          .collection("agenda_agendamentos")
          .where(
            "companyId",
            "==",
            companyId
          )
          .where(
            "profissionalId",
            "==",
            profissionalId
          )
          .where(
            "inicio",
            "<",
            admin.firestore.Timestamp.fromDate(
              di.fimDia
            )
          )
          .get();

        const statusQueOcupam = new Set([
          "agendado",
          "confirmado",
          "em_atendimento",
        ]);

        const agendamentos: AgendaIntervalo[] =
          agendamentosSnap.docs
            .map((doc) => doc.data())
            .filter((agendamento) => {
              const status = String(
                agendamento.status ?? ""
              ).trim().toLowerCase();

              if (
                !statusQueOcupam.has(status)
              ) {
                return false;
              }

              const inicio = agendaDate(
                agendamento.inicio
              );

              const fim =
                agendaDate(
                  agendamento.fimOcupacao
                ) ??
                agendaDate(
                  agendamento.fim
                );

              return (
                inicio != null &&
                fim != null &&
                agendaOverlap(
                  inicio,
                  fim,
                  di.inicioDia,
                  di.fimDia
                )
              );
            })
            .map((agendamento) => ({
              inicio: agendaDate(
                agendamento.inicio
              )!,
              fim:
                agendaDate(
                  agendamento.fimOcupacao
                ) ??
                agendaDate(
                  agendamento.fim
                )!,
            }));

        const horarios = agendaGerarHorariosDia(
          di,
          horariosEfetivos,
          ocupacao,
          bloqueios,
          agendamentos,
          agora
        );

        return {
          data,
          horarios,
        };
      }

      /*
       * ======================================================
       * MODO DATAS
       *
       * Consulta por padrão os próximos 30 dias.
       * Permitimos no máximo 60.
       * ======================================================
       */
      let quantidadeDias = Number(
        request.data?.dias ?? 30
      );

      if (
        !Number.isFinite(quantidadeDias)
      ) {
        quantidadeDias = 30;
      }

      quantidadeDias = Math.floor(
        quantidadeDias
      );

      if (quantidadeDias < 1) {
        quantidadeDias = 1;
      }

      if (quantidadeDias > 60) {
        quantidadeDias = 60;
      }

      const hoje = agendaHojeSP();

      const ultimoDia = agendaSomarDias(
        hoje.ano,
        hoje.mes,
        hoje.dia,
        quantidadeDias
      );

      const inicioJanela = agendaDataSP(
        hoje.ano,
        hoje.mes,
        hoje.dia,
        0
      );

      const fimJanela = agendaDataSP(
        ultimoDia.ano,
        ultimoDia.mes,
        ultimoDia.dia,
        0
      );

      /*
       * Buscamos bloqueios uma única vez para toda
       * a janela de datas.
       */
      const bloqueiosSnap = await db
        .collection("agenda_bloqueios")
        .where(
          "companyId",
          "==",
          companyId
        )
        .where(
          "dataInicio",
          "<",
          admin.firestore.Timestamp.fromDate(
            fimJanela
          )
        )
        .get();

      const bloqueios: AgendaIntervalo[] =
        bloqueiosSnap.docs
          .map((doc) => doc.data())
          .filter((bloqueio) => {
            if (
              bloqueio.ativo === false
            ) {
              return false;
            }

            const inicio = agendaDate(
              bloqueio.dataInicio
            );

            const fim = agendaDate(
              bloqueio.dataFim
            );

            const bloqueiaProfissional =
              bloqueio.todosProfissionais === true ||
              String(
                bloqueio.profissionalId ?? ""
              ).trim() === profissionalId;

            return (
              inicio != null &&
              fim != null &&
              bloqueiaProfissional &&
              agendaOverlap(
                inicio,
                fim,
                inicioJanela,
                fimJanela
              )
            );
          })
          .map((bloqueio) => ({
            inicio: agendaDate(
              bloqueio.dataInicio
            )!,
            fim: agendaDate(
              bloqueio.dataFim
            )!,
          }));

      /*
       * Buscamos os agendamentos uma única vez para
       * toda a janela.
       */
      const agendamentosSnap = await db
        .collection("agenda_agendamentos")
        .where(
          "companyId",
          "==",
          companyId
        )
        .where(
          "profissionalId",
          "==",
          profissionalId
        )
        .where(
          "inicio",
          "<",
          admin.firestore.Timestamp.fromDate(
            fimJanela
          )
        )
        .get();

      const statusQueOcupam = new Set([
        "agendado",
        "confirmado",
        "em_atendimento",
      ]);

      const agendamentos: AgendaIntervalo[] =
        agendamentosSnap.docs
          .map((doc) => doc.data())
          .filter((agendamento) => {
            const status = String(
              agendamento.status ?? ""
            ).trim().toLowerCase();

            if (
              !statusQueOcupam.has(status)
            ) {
              return false;
            }

            const inicio = agendaDate(
              agendamento.inicio
            );

            const fim =
              agendaDate(
                agendamento.fimOcupacao
              ) ??
              agendaDate(
                agendamento.fim
              );

            return (
              inicio != null &&
              fim != null &&
              agendaOverlap(
                inicio,
                fim,
                inicioJanela,
                fimJanela
              )
            );
          })
          .map((agendamento) => ({
            inicio: agendaDate(
              agendamento.inicio
            )!,
            fim:
              agendaDate(
                agendamento.fimOcupacao
              ) ??
              agendaDate(
                agendamento.fim
              )!,
          }));

      const datasDisponiveis: string[] = [];

      for (
        let indice = 0;
        indice < quantidadeDias;
        indice++
      ) {
        const atual = agendaSomarDias(
          hoje.ano,
          hoje.mes,
          hoje.dia,
          indice
        );

        const dataTexto = agendaFormatarData(
          atual.ano,
          atual.mes,
          atual.dia
        );

        const di = agendaParseData(
          dataTexto
        );

        if (!di) {
          continue;
        }

        const horarios = agendaGerarHorariosDia(
          di,
          horariosEfetivos,
          ocupacao,
          bloqueios,
          agendamentos,
          agora
        );

        /*
         * Só devolvemos a data caso exista pelo menos
         * um horário realmente disponível.
         */
        if (horarios.length > 0) {
          datasDisponiveis.push(
            dataTexto
          );
        }
      }

      return {
        datas: datasDisponiveis,
      };
    } catch (error: any) {
      console.error(
        "consultarDisponibilidadeAgenda error:",
        error
      );

      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError(
        "internal",
        "Erro ao consultar disponibilidade: " +
        `${error?.message || error}`
      );
    }
  }
);

// ============================================================================
// AGENDA PÚBLICA - CONFIRMAR AGENDAMENTO
// ============================================================================

function agendaSomenteNumeros(valor: unknown): string {
  return String(valor ?? "").replace(/\D/g, "");
}

function agendaNormalizarEmail(valor: unknown): string {
  return String(valor ?? "").trim().toLowerCase();
}

function agendaNormalizarNome(valor: unknown): string {
  return String(valor ?? "").trim();
}

export const confirmarAgendamentoPublico = onCall(
  {
    region: REGION,
    memory: "256MiB",
    timeoutSeconds: 60,
  },
  async (request) => {
    try {
      console.log(
        "========== confirmarAgendamentoPublico START =========="
      );

      /* ======================================================
       * DADOS RECEBIDOS
       * ====================================================== */

      const slug = String(
        request.data?.slug ?? ""
      ).trim().toLowerCase();

      const servicoId = String(
        request.data?.servicoId ?? ""
      ).trim();

      const profissionalId = String(
        request.data?.profissionalId ?? ""
      ).trim();

      const data = String(
        request.data?.data ?? ""
      ).trim();

      const horario = String(
        request.data?.horario ?? ""
      ).trim();

      const nomeCliente = agendaNormalizarNome(
        request.data?.nome
      );

      const telefoneCliente = agendaSomenteNumeros(
        request.data?.telefone
      );

      const emailCliente = agendaNormalizarEmail(
        request.data?.email
      );

      const observacao = String(
        request.data?.observacao ?? ""
      ).trim();

      /* ======================================================
       * VALIDAÇÕES BÁSICAS
       * ====================================================== */

      if (
        !slug ||
        !servicoId ||
        !profissionalId ||
        !data ||
        !horario
      ) {
        throw new HttpsError(
          "invalid-argument",
          "Dados do agendamento incompletos."
        );
      }

      if (nomeCliente.length < 2) {
        throw new HttpsError(
          "invalid-argument",
          "Informe um nome válido."
        );
      }

      if (telefoneCliente.length < 10) {
        throw new HttpsError(
          "invalid-argument",
          "Informe um telefone válido."
        );
      }

      if (
        emailCliente &&
        !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailCliente)
      ) {
        throw new HttpsError(
          "invalid-argument",
          "Informe um e-mail válido."
        );
      }

      const di = agendaParseData(data);

      if (!di) {
        throw new HttpsError(
          "invalid-argument",
          "Data inválida."
        );
      }

      const minutosInicio =
        agendaHorarioParaMinutos(horario);

      if (minutosInicio == null) {
        throw new HttpsError(
          "invalid-argument",
          "Horário inválido."
        );
      }

      /* ======================================================
       * PÁGINA PÚBLICA
       * ====================================================== */

      const paginaSnap = await db
        .collection("agenda_paginas_publicas")
        .doc(slug)
        .get();

      if (!paginaSnap.exists) {
        throw new HttpsError(
          "not-found",
          "Página de agendamento não encontrada."
        );
      }

      const pagina = paginaSnap.data() || {};

      const companyId = String(
        pagina.companyId ?? ""
      ).trim();

      if (
        !companyId ||
        pagina.ativo !== true
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Página de agendamento indisponível."
        );
      }

      /* ======================================================
       * SERVIÇO
       * ====================================================== */

      const servicoSnap = await db
        .collection("agenda_servicos_publicos")
        .doc(companyId)
        .collection("servicos")
        .doc(servicoId)
        .get();

      if (!servicoSnap.exists) {
        throw new HttpsError(
          "not-found",
          "Serviço não encontrado."
        );
      }

      const servico = servicoSnap.data() || {};

      if (
        servico.ativo !== true ||
        String(
          servico.companyId ?? companyId
        ).trim() !== companyId
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Serviço indisponível."
        );
      }

      const duracaoMinutos = Math.ceil(
        Number(servico.duracaoMinutos ?? 0)
      );

      const intervaloAposAtendimentoMinutos =
        Math.ceil(
          Number(
            servico.intervaloAposAtendimentoMinutos ?? 0
          )
        );

      if (
        !Number.isFinite(duracaoMinutos) ||
        duracaoMinutos <= 0 ||
        !Number.isFinite(
          intervaloAposAtendimentoMinutos
        ) ||
        intervaloAposAtendimentoMinutos < 0
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Configuração do serviço inválida."
        );
      }

      const ocupacaoMinutos =
        duracaoMinutos +
        intervaloAposAtendimentoMinutos;

      const servicoNome = String(
        servico.nome ?? "Serviço"
      ).trim();

      const valorServico = Number(
        servico.precoVenda ??
        servico.valorVenda ??
        servico.valorUnitario ??
        servico.preco ??
        servico.valor ??
        0
      );

      /* ======================================================
       * PROFISSIONAL
       * ====================================================== */

      const profissionalSnap = await db
        .collection("agenda_profissionais_publicos")
        .doc(companyId)
        .collection("profissionais")
        .doc(profissionalId)
        .get();

      if (!profissionalSnap.exists) {
        throw new HttpsError(
          "not-found",
          "Profissional não encontrado."
        );
      }

      const profissional =
        profissionalSnap.data() || {};

      const servicosIds = Array.isArray(
        profissional.servicosIds
      ) ?
        profissional.servicosIds.map(
          (valor: unknown) => String(valor)
        ) :
        [];

      if (
        profissional.ativo !== true ||
        String(
          profissional.companyId ?? companyId
        ).trim() !== companyId ||
        !servicosIds.includes(servicoId)
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Profissional indisponível para este serviço."
        );
      }

      const profissionalNome = String(
        profissional.nome ?? "Profissional"
      ).trim();

      /* ======================================================
       * CALCULA INÍCIO / FIM
       * ====================================================== */

      const inicio = agendaDataSP(
        di.ano,
        di.mes,
        di.dia,
        minutosInicio
      );

      const fim = new Date(
        inicio.getTime() +
        duracaoMinutos * 60 * 1000
      );

      const fimOcupacao = new Date(
        inicio.getTime() +
        ocupacaoMinutos * 60 * 1000
      );

      if (inicio.getTime() <= Date.now()) {
        throw new HttpsError(
          "failed-precondition",
          "Este horário já passou."
        );
      }

      /* ======================================================
       * HORÁRIO DA EMPRESA
       * ====================================================== */

      const configuracaoSnap = await db
        .collection("agenda_configuracoes")
        .doc(companyId)
        .get();

      if (!configuracaoSnap.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Agenda da empresa não configurada."
        );
      }

      const horariosEmpresa = agendaHorarios(
        (configuracaoSnap.data() || {})
          .horariosFuncionamento
      );

      if (!horariosEmpresa) {
        throw new HttpsError(
          "failed-precondition",
          "Horário de funcionamento não configurado."
        );
      }

      let horariosEfetivos = horariosEmpresa;

      /* ======================================================
       * HORÁRIO DO PROFISSIONAL
       * ====================================================== */

      const horarioProfissionalSnap = await db
        .collection("agenda_profissionais_horarios")
        .doc(profissionalId)
        .get();

      if (horarioProfissionalSnap.exists) {
        const horarioProfissional =
          horarioProfissionalSnap.data() || {};

        if (
          String(
            horarioProfissional.companyId ??
            companyId
          ).trim() !== companyId
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Horário do profissional inválido."
          );
        }

        if (
          horarioProfissional
            .usaHorarioPadraoEmpresa === false
        ) {
          const horarioProprio = agendaHorarios(
            horarioProfissional.horarios
          );

          if (horarioProprio) {
            horariosEfetivos = horarioProprio;
          }
        }
      }

      /* ======================================================
       * BLOQUEIOS
       * ====================================================== */

      const bloqueiosSnap = await db
        .collection("agenda_bloqueios")
        .where(
          "companyId",
          "==",
          companyId
        )
        .where(
          "dataInicio",
          "<",
          admin.firestore.Timestamp.fromDate(
            di.fimDia
          )
        )
        .get();

      const bloqueios: AgendaIntervalo[] =
        bloqueiosSnap.docs
          .map((doc) => doc.data())
          .filter((bloqueio) => {
            if (bloqueio.ativo === false) {
              return false;
            }

            const bloqueioInicio =
              agendaDate(bloqueio.dataInicio);

            const bloqueioFim =
              agendaDate(bloqueio.dataFim);

            const bloqueiaProfissional =
              bloqueio.todosProfissionais === true ||
              String(
                bloqueio.profissionalId ?? ""
              ).trim() === profissionalId;

            return (
              bloqueioInicio != null &&
              bloqueioFim != null &&
              bloqueiaProfissional &&
              agendaOverlap(
                bloqueioInicio,
                bloqueioFim,
                di.inicioDia,
                di.fimDia
              )
            );
          })
          .map((bloqueio) => ({
            inicio: agendaDate(
              bloqueio.dataInicio
            )!,
            fim: agendaDate(
              bloqueio.dataFim
            )!,
          }));

      /* ======================================================
       * AGENDAMENTOS EXISTENTES
       * ====================================================== */

      const agendamentosSnap = await db
        .collection("agenda_agendamentos")
        .where(
          "companyId",
          "==",
          companyId
        )
        .where(
          "profissionalId",
          "==",
          profissionalId
        )
        .where(
          "inicio",
          "<",
          admin.firestore.Timestamp.fromDate(
            di.fimDia
          )
        )
        .get();

      const statusQueOcupam = new Set([
        "agendado",
        "confirmado",
        "em_atendimento",
      ]);

      const agendamentos: AgendaIntervalo[] =
        agendamentosSnap.docs
          .map((doc) => doc.data())
          .filter((agendamento) => {
            const status = String(
              agendamento.status ?? ""
            ).trim().toLowerCase();

            if (!statusQueOcupam.has(status)) {
              return false;
            }

            const agendamentoInicio =
              agendaDate(agendamento.inicio);

            const agendamentoFim =
              agendaDate(
                agendamento.fimOcupacao
              ) ??
              agendaDate(
                agendamento.fim
              );

            return (
              agendamentoInicio != null &&
              agendamentoFim != null &&
              agendaOverlap(
                agendamentoInicio,
                agendamentoFim,
                di.inicioDia,
                di.fimDia
              )
            );
          })
          .map((agendamento) => ({
            inicio: agendaDate(
              agendamento.inicio
            )!,
            fim:
              agendaDate(
                agendamento.fimOcupacao
              ) ??
              agendaDate(
                agendamento.fim
              )!,
          }));

      /* ======================================================
       * RECALCULA OS HORÁRIOS DISPONÍVEIS
       *
       * Essa validação é fundamental.
       * Não confiamos somente no horário enviado pelo browser.
       * ====================================================== */

      const horariosDisponiveis =
        agendaGerarHorariosDia(
          di,
          horariosEfetivos,
          ocupacaoMinutos,
          bloqueios,
          agendamentos,
          new Date()
        );

      if (!horariosDisponiveis.includes(horario)) {
        throw new HttpsError(
          "already-exists",
          "Este horário não está mais disponível. Escolha outro horário."
        );
      }

      /* ======================================================
 * LOCALIZAR CLIENTE PELO TELEFONE
 *
 * O telefone normalizado é a principal chave de
 * identificação do cliente dentro da empresa.
 * ====================================================== */

      let clienteId: string | null = null;
      let clienteExistente = false;

      /*
 * 1. Forma nova e recomendada:
 *
 * procura pelo campo telefoneNormalizado.
 */
      const clienteNormalizadoSnap = await db
        .collection("clientes")
        .where(
          "companyId",
          "==",
          companyId
        )
        .where(
          "telefoneNormalizado",
          "==",
          telefoneCliente
        )
        .limit(1)
        .get();

      if (!clienteNormalizadoSnap.empty) {
        clienteId =
    clienteNormalizadoSnap.docs[0].id;

        clienteExistente = true;
      }

      /*
 * 2. Compatibilidade com clientes antigos.
 *
 * Alguns registros podem ainda não possuir
 * telefoneNormalizado.
 */
      if (!clienteId) {
        const clienteWhatsappSnap = await db
          .collection("clientes")
          .where(
            "companyId",
            "==",
            companyId
          )
          .where(
            "whatsapp",
            "==",
            telefoneCliente
          )
          .limit(1)
          .get();

        if (!clienteWhatsappSnap.empty) {
          clienteId =
      clienteWhatsappSnap.docs[0].id;

          clienteExistente = true;
        }
      }

      /*
 * 3. Segunda compatibilidade:
 * procura no campo telefone.
 */
      if (!clienteId) {
        const clienteTelefoneSnap = await db
          .collection("clientes")
          .where(
            "companyId",
            "==",
            companyId
          )
          .where(
            "telefone",
            "==",
            telefoneCliente
          )
          .limit(1)
          .get();

        if (!clienteTelefoneSnap.empty) {
          clienteId =
      clienteTelefoneSnap.docs[0].id;

          clienteExistente = true;
        }
      }

      /* ======================================================
       * CRIA OU ATUALIZA CLIENTE
       * ====================================================== */


      let clienteRef:
        admin.firestore.DocumentReference;

      if (clienteId) {
        clienteRef = db
          .collection("clientes")
          .doc(clienteId);

        /*
         * Atualizamos somente os dados úteis recebidos.
         * Não sobrescrevemos CPF, CNPJ, endereço etc.
         */
        const atualizacaoCliente:
            Record<string, unknown> = {
              telefoneNormalizado: telefoneCliente,
              isCliente: true,
              updatedAt:
                admin.firestore.FieldValue
                  .serverTimestamp(),
            };

        if (emailCliente) {
          atualizacaoCliente.email = emailCliente;
        }

        await clienteRef.set(
          atualizacaoCliente,
          { merge: true }
        );
      } else {
        clienteRef =
          db.collection("clientes").doc();

        clienteId = clienteRef.id;

        await clienteRef.set({
          companyId,
          userId: companyId,

          nome: nomeCliente,
          nomeLower:
            nomeCliente.toLowerCase(),

          tipoCliente: "pf",

          cpf: null,
          cnpj: null,
          razaoSocial: null,

          telefone: null,
          whatsapp: telefoneCliente,
          telefoneNormalizado: telefoneCliente,

          email:
            emailCliente || null,

          endereco: {
            rua: null,
            numero: null,
            complemento: null,
            bairro: null,
            cidade: null,
            estado: null,
            cep: null,
          },

          observacao:
            "Cliente cadastrado pela agenda pública.",

          isCliente: true,
          isFornecedor: false,
          isWebCliente: true,

          origem: "agenda_publica",
          perfilRelacionamento: "WEB",

          createdByUid: companyId,

          createdAt:
            admin.firestore.FieldValue
              .serverTimestamp(),

          updatedAt:
            admin.firestore.FieldValue
              .serverTimestamp(),
        });
      }

      /* ======================================================
       * CRIA AGENDAMENTO
       * ====================================================== */

      const agendamentoRef =
        db.collection(
          "agenda_agendamentos"
        ).doc();

      await agendamentoRef.set({
        companyId,

        clienteId,
        clienteNome: nomeCliente,
        clienteTelefone: telefoneCliente,
        clienteWhatsapp: telefoneCliente,
        clienteEmail:
          emailCliente || null,

        servicoId,
        servicoNome,

        valorServico:
          Number.isFinite(valorServico) ?
            valorServico :
            0,

        duracaoMinutos,

        intervaloAposAtendimentoMinutos,

        profissionalId,
        profissionalNome,

        inicio:
          admin.firestore.Timestamp
            .fromDate(inicio),

        fim:
          admin.firestore.Timestamp
            .fromDate(fim),

        fimOcupacao:
          admin.firestore.Timestamp
            .fromDate(fimOcupacao),

        status: "agendado",

        origem: "agenda_publica",

        observacao:
          observacao || null,

        createdAt:
          admin.firestore.FieldValue
            .serverTimestamp(),

        updatedAt:
          admin.firestore.FieldValue
            .serverTimestamp(),
      });

      console.log(
        "Agendamento criado:",
        agendamentoRef.id
      );

      console.log(
        "Cliente:",
        clienteId,
        clienteExistente ?
          "(existente)" :
          "(novo)"
      );

      console.log(
        "========== confirmarAgendamentoPublico END =========="
      );

      return {
        ok: true,
        agendamentoId:
          agendamentoRef.id,
        clienteId,
        clienteNovo:
          !clienteExistente,
        data,
        horario,
        servicoNome,
        profissionalNome,
      };
    } catch (error: any) {
      console.error(
        "confirmarAgendamentoPublico error:",
        error
      );

      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError(
        "internal",
        "Erro ao confirmar agendamento: " +
        `${error?.message || error}`
      );
    }
  }
);
