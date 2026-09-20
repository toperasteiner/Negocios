const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { google } = require("googleapis");

if (!admin.apps.length) {
  admin.initializeApp();
}

exports.validateGoogleSubscription = onCall(async (request) => {
  console.log("========== validateGoogleSubscription START ==========");

  const data = request.data || {};
  console.log("request.data:", JSON.stringify(data));

  const authUid = (request.auth?.uid || "").toString().trim();
  console.log("request.auth?.uid:", authUid || null);

  const uid = (data.uid || "").toString().trim();
  const productId = (data.productId || "").toString().trim().toLowerCase();
  const purchaseToken = (data.purchaseToken || "").toString().trim();

  console.log("uid recebido do app:", uid || null);
  console.log("productId:", productId);
  console.log("purchaseToken vazio?:", purchaseToken ? "nao" : "sim");

  if (!uid || !productId || !purchaseToken) {
    console.log("ERRO: dados obrigatórios ausentes");
    throw new HttpsError(
      "invalid-argument",
      "Dados obrigatórios não enviados"
    );
  }

  // Se houver auth no contexto e vier diferente do uid enviado pelo app,
  // bloqueia por segurança.
  if (authUid && authUid !== uid) {
    console.log("ERRO: UID inconsistente entre request.auth e data.uid");
    throw new HttpsError(
      "permission-denied",
      "UID inconsistente entre autenticação e requisição."
    );
  }

  try {
    console.log("Criando GoogleAuth...");
    const auth = new google.auth.GoogleAuth({
      scopes: ["https://www.googleapis.com/auth/androidpublisher"],
    });

    console.log("Obtendo authClient...");
    const authClient = await auth.getClient();
    console.log("authClient obtido com sucesso");

    const androidpublisher = google.androidpublisher({
      version: "v3",
      auth: authClient,
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
    } catch (playError) {
      console.error(
        "ERRO GOOGLE PLAY - detalhes:",
        JSON.stringify(playError?.response?.data || null)
      );
      console.error(
        "ERRO GOOGLE PLAY - mensagem:",
        playError?.message || playError
      );

      throw new HttpsError(
        "failed-precondition",
        "Erro ao validar compra na Google Play."
      );
    }

    console.log("Resposta Google Play recebida");
    console.log("response.data:", JSON.stringify(response.data));

    const subscription = response.data || {};
    const state =
      subscription.subscriptionState || "SUBSCRIPTION_STATE_UNSPECIFIED";

    const lineItem =
      Array.isArray(subscription.lineItems) && subscription.lineItems.length
        ? subscription.lineItems[0]
        : null;

    console.log("subscriptionState:", state);
    console.log("lineItem encontrado?:", lineItem ? "sim" : "nao");
    console.log("lineItem:", JSON.stringify(lineItem));

    const expiryTimeRaw = lineItem?.expiryTime || null;
    const expiryDate = expiryTimeRaw ? new Date(expiryTimeRaw) : null;
    const expiryTimestamp = expiryDate
      ? admin.firestore.Timestamp.fromDate(expiryDate)
      : null;

    console.log("expiryTimeRaw:", expiryTimeRaw);
    console.log("expiryDate:", expiryDate ? expiryDate.toISOString() : null);
    console.log(
      "expiryTimestamp:",
      expiryTimestamp ? expiryTimestamp.toDate().toISOString() : null
    );

    const latestOrderId =
      subscription.latestOrderId ||
      subscription.externalAccountIdentifiers?.obfuscatedExternalAccountId ||
      null;

    console.log("latestOrderId:", latestOrderId);

    const active =
      state === "SUBSCRIPTION_STATE_ACTIVE" ||
      state === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD";

    const autoRenewing = active;

    const PLAN_MAP = {
      starter_mensal: "starter",
      starter_monthly: "starter",
      premium_mensal: "premium",
      premium_monthly: "premium",
    };

    let plan = "free";

    if (active) {
      if (PLAN_MAP[productId]) {
        plan = PLAN_MAP[productId];
      } else if (productId.includes("premium")) {
        plan = "premium";
      } else if (productId.includes("starter")) {
        plan = "starter";
      }
    }

    let billingCycle = "";
    if (productId.includes("mensal") || productId.includes("monthly")) {
      billingCycle = "monthly";
    } else if (productId.includes("anual") || productId.includes("annual")) {
      billingCycle = "annual";
    } else if (
      productId.includes("semestral") ||
      productId.includes("semiannual")
    ) {
      billingCycle = "semiannual";
    }

    console.log("active:", active);
    console.log("autoRenewing:", autoRenewing);
    console.log("plan definido:", plan);
    console.log("billingCycle:", billingCycle);

    const userRef = admin.firestore().collection("users").doc(uid);

    console.log("Lendo users/" + uid);
    const userSnap = await userRef.get();

    console.log("userSnap.exists:", userSnap.exists);

    if (!userSnap.exists) {
      console.log("ERRO: usuário não encontrado em users/" + uid);
      throw new HttpsError("not-found", "Usuário não encontrado.");
    }

    const userData = userSnap.data() || {};
    console.log("userData:", JSON.stringify(userData));

    const companyId = (userData.companyId || uid).toString().trim() || uid;
    console.log("companyId resolvido:", companyId);

    const subscriptionRef = admin
      .firestore()
      .collection("subscriptions")
      .doc(companyId);

    const userPayload = {
      plan,
      subscriptionActive: active,
      subscriptionStatus: state,
      expiryTime: expiryTimestamp,
      purchaseToken,
      productId,
      billingCycle,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    console.log(
      "Payload users:",
      JSON.stringify({
        ...userPayload,
        updatedAt: "serverTimestamp()",
        expiryTime: expiryTimestamp
          ? expiryTimestamp.toDate().toISOString()
          : null,
      })
    );

    await userRef.set(userPayload, { merge: true });
    console.log("users/" + uid + " atualizado com sucesso");

    const subscriptionPayload = {
      companyId,
      userId: uid,
      planId: plan,
      status: active ? "active" : "expired",
      billingCycle,
      productId,
      purchaseToken,
      orderId: latestOrderId,
      purchaseSource: "google_play",
      autoRenewing,
      trial: false,
      purchaseDate: admin.firestore.FieldValue.serverTimestamp(),
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: expiryTimestamp,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    console.log(
      "Payload subscriptions:",
      JSON.stringify({
        ...subscriptionPayload,
        purchaseDate: "serverTimestamp()",
        startedAt: "serverTimestamp()",
        updatedAt: "serverTimestamp()",
        expiresAt: expiryTimestamp
          ? expiryTimestamp.toDate().toISOString()
          : null,
      })
    );

    await subscriptionRef.set(subscriptionPayload, { merge: true });
    console.log("subscriptions/" + companyId + " atualizado com sucesso");

    const result = {
      uid,
      companyId,
      plan,
      active,
      status: state,
      billingCycle,
      productId,
      expiry: expiryTimeRaw,
    };

    console.log("RETORNO:", JSON.stringify(result));
    console.log("========== validateGoogleSubscription END ==========");

    return result;
  } catch (error) {
    console.error("validateGoogleSubscription error:", error);

    if (error instanceof HttpsError) {
      throw error;
    }

    throw new HttpsError(
      "internal",
      `Erro ao validar assinatura: ${error.message || error}`
    );
  }
});