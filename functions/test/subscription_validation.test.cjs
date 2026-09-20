const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const ts = require("typescript");

// Exercise the actual callable body with in-memory Play/Firestore dependencies.
const source = fs.readFileSync(path.join(__dirname, "../src/index.ts"), "utf8");
const ast = ts.createSourceFile("index.ts", source, ts.ScriptTarget.Latest, true);
const declaration = ast.statements.find((node) =>
  ts.isVariableStatement(node) &&
  node.declarationList.declarations.some((item) =>
    item.name.getText(ast) === "validateGoogleSubscription"));
assert.ok(declaration);
const compiled = ts.transpileModule(declaration.getText(ast), {
  compilerOptions: { module: ts.ModuleKind.CommonJS },
}).outputText;

function fixture({ active = true, failCommit = false } = {}) {
  const docs = new Map([
    ["users/buyer", {
      companyId: "company", plan: "free", planId: "free",
      legacyField: "preserve", planStartAt: "original-start",
    }],
    ["subscriptions/company", { planId: "free", legacyField: "preserve" }],
  ]);
  let commits = 0;
  const db = {
    collection: (collection) => ({
      doc: (id) => ({
        path: collection + "/" + id,
        get: async () => ({
          exists: docs.has(collection + "/" + id),
          data: () => docs.get(collection + "/" + id),
        }),
        set: () => { throw Error("Expected atomic batch, not direct write"); },
      }),
    }),
    batch: () => {
      const pending = [];
      return {
        set: (ref, value, options) => {
          assert.deepEqual(options, { merge: true });
          pending.push([ref.path, value]);
        },
        commit: async () => {
          assert.equal(pending.length, 2);
          if (failCommit) throw Error("commit rejected");
          for (const [key, value] of pending) {
            docs.set(key, { ...docs.get(key), ...value });
          }
          commits++;
        },
      };
    },
  };
  const firestore = Object.assign(() => db, {
    Timestamp: { fromDate: (value) => value.toISOString() },
    FieldValue: { serverTimestamp: () => "server-timestamp" },
  });
  const google = {
    auth: { GoogleAuth: class {} },
    androidpublisher: () => ({
      purchases: { subscriptionsv2: {
        get: async () => ({ data: {
          subscriptionState: active
            ? "SUBSCRIPTION_STATE_ACTIVE" : "SUBSCRIPTION_STATE_EXPIRED",
          lineItems: [{ expiryTime: new Date(Date.now() + 86400000).toISOString() }],
          latestOrderId: "order",
        } }),
      } },
    }),
  };
  class HttpsError extends Error {
    constructor(code, message) { super(message); this.code = code; }
  }
  const exports = {};
  const quiet = { log() {}, warn() {}, error() {} };
  new Function("exports", "onCall", "REGION", "google", "admin", "HttpsError",
    "console", compiled)(
    exports, (_, handler) => handler, "southamerica-east1",
    google, { firestore }, HttpsError, quiet);
  return {
    docs,
    commits: () => commits,
    validate: (productId) => exports.validateGoogleSubscription({
      auth: { uid: "buyer" },
      data: { uid: "buyer", productId, purchaseToken: "test-token" },
    }),
  };
}

for (const plan of ["premium", "starter"]) {
  test(plan + " validation synchronizes both aliases and subscription", async () => {
    const f = fixture();
    const result = await f.validate(plan + "_mensal");
    assert.equal(result.active, true);
    assert.equal(result.planId, plan);
    assert.equal(f.commits(), 1);
    assert.equal(f.docs.get("users/buyer").plan, plan);
    assert.equal(f.docs.get("users/buyer").planId, plan);
    assert.equal(f.docs.get("subscriptions/company").planId, plan);
    assert.equal(f.docs.get("users/buyer").legacyField, "preserve");
    assert.equal(f.docs.get("subscriptions/company").legacyField, "preserve");
    assert.equal(f.docs.get("users/buyer").planStartAt, "original-start");
  });
}

test("inactive validation writes Free consistently", async () => {
  const f = fixture({ active: false });
  const result = await f.validate("premium_mensal");
  assert.equal(result.active, false);
  assert.equal(f.docs.get("users/buyer").plan, "free");
  assert.equal(f.docs.get("users/buyer").planId, "free");
  assert.equal(f.docs.get("subscriptions/company").status, "expired");
});

test("revalidation used by restore keeps the same field contract", async () => {
  const f = fixture();
  await f.validate("premium_mensal");
  const userKeys = Object.keys(f.docs.get("users/buyer")).sort();
  const subscriptionKeys = Object.keys(f.docs.get("subscriptions/company")).sort();
  await f.validate("premium_mensal");
  assert.equal(f.commits(), 2);
  assert.deepEqual(Object.keys(f.docs.get("users/buyer")).sort(), userKeys);
  assert.deepEqual(Object.keys(f.docs.get("subscriptions/company")).sort(), subscriptionKeys);
  assert.equal(f.docs.get("users/buyer").plan, "premium");
  assert.equal(f.docs.get("users/buyer").planId, "premium");
});

test("failed batch leaves both documents unchanged", async () => {
  const f = fixture({ failCommit: true });
  const before = JSON.stringify([...f.docs]);
  await assert.rejects(f.validate("premium_mensal"), /commit rejected/);
  assert.equal(JSON.stringify([...f.docs]), before);
  assert.equal(f.commits(), 0);
});
