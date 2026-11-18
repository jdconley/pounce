import { readFileSync } from "node:fs";

import { describe, expect, test } from "vitest";

import { privacyPage } from "./privacy";

// The app's privacy manifest, the App Store Connect checklist and the policy page must agree
// (docs/privacy/app-store-label.md). Change them together when a feature collects new data.
const manifest = readFileSync(new URL("../../../play-ios/Pounce/Resources/PrivacyInfo.xcprivacy", import.meta.url), "utf8");
const label = readFileSync(new URL("../../../../docs/privacy/app-store-label.md", import.meta.url), "utf8");

/** Manifest key → the data type's name on App Store Connect's form. */
const NAMES: Record<string, string> = {
  NSPrivacyCollectedDataTypeName: "Name",
  NSPrivacyCollectedDataTypePhoneNumber: "Phone Number",
  NSPrivacyCollectedDataTypeGameplayContent: "Gameplay Content",
  NSPrivacyCollectedDataTypeOtherUserContent: "Other User Content",
  NSPrivacyCollectedDataTypeUserID: "User ID",
  NSPrivacyCollectedDataTypeDeviceID: "Device ID",
  NSPrivacyCollectedDataTypeProductInteraction: "Product Interaction",
  NSPrivacyCollectedDataTypeOtherUsageData: "Other Usage Data",
  NSPrivacyCollectedDataTypeOtherDataTypes: "Other Data Types",
};

const declared = [...manifest.matchAll(/<key>NSPrivacyCollectedDataType<\/key>\s*<string>(\w+)<\/string>/g)].map((m) => m[1] as string);
/** The rows of the label's question 3 table: one per ticked data type, with its purposes. */
const rowsOf = [...label.matchAll(/^\| ([A-Za-z ]+) \| (App Functionality(?:, Analytics)?) \| Yes \| No \|$/gm)];
const ticked = rowsOf.map((m) => m[1] as string);
/** The data types the first-run funnel (src/funnel) also uses for Analytics. */
const analytics = rowsOf.filter((m) => m[2]?.endsWith("Analytics")).map((m) => m[1] as string);

/** Each declared data type's purposes in the manifest, by its App Store name. */
const purposesOf = Object.fromEntries(
  [...manifest.matchAll(/<string>(NSPrivacyCollectedDataType\w+)<\/string>[\s\S]*?<key>NSPrivacyCollectedDataTypePurposes<\/key>\s*<array>([\s\S]*?)<\/array>/g)]
    .filter((m) => !(m[1] as string).startsWith("NSPrivacyCollectedDataTypePurpose"))
    .map((m) => [NAMES[m[1] as string] ?? m[1], [...(m[2] as string).matchAll(/<string>(\w+)<\/string>/g)].map((p) => p[1])]),
);

describe("privacy label", () => {
  test("the manifest declares exactly the data types the App Store checklist ticks", () => {
    expect(declared.map((k) => NAMES[k] ?? k).sort()).toEqual([...ticked].sort());
    expect(label).toContain(`Tick exactly these ${ticked.length} boxes`);
  });

  test("nothing is tracking, everything is linked, for app functionality and, for the funnel's four, analytics", () => {
    expect(manifest).toMatch(/<key>NSPrivacyTracking<\/key>\s*<false\/>/);
    expect(manifest).not.toContain("<key>NSPrivacyCollectedDataTypeTracking</key>\n\t\t\t<true/>");
    const purposes = [...manifest.matchAll(/<string>(NSPrivacyCollectedDataTypePurpose\w+)<\/string>/g)].map((m) => m[1]);
    expect(new Set(purposes)).toEqual(new Set(["NSPrivacyCollectedDataTypePurposeAppFunctionality", "NSPrivacyCollectedDataTypePurposeAnalytics"]));
    expect(analytics.sort()).toEqual(["Device ID", "Other Data Types", "Other Usage Data", "Product Interaction"]);
    for (const name of ticked) {
      const want = ["NSPrivacyCollectedDataTypePurposeAppFunctionality", ...(analytics.includes(name) ? ["NSPrivacyCollectedDataTypePurposeAnalytics"] : [])];
      expect(purposesOf[name], name).toEqual(want);
    }
  });

  test("the policy says what the funnel keeps, and never claims there are no analytics at all", async () => {
    const html = await privacyPage(true).text();
    expect(html).not.toMatch(/no analytics/i);
    expect(html).toContain("no third-party analytics");
    expect(html).toContain("How new players get started");
    expect(html).toContain("Getting-started steps: a year after the device was last used");
  });

  test("the parent's phone number is declared, as the policy says it's collected", async () => {
    expect(declared).toContain("NSPrivacyCollectedDataTypePhoneNumber");
    expect(await privacyPage(true).text()).toContain("mobile number");
  });

  test("the policy no longer claims streaks are coming soon, or that nothing is ever shared", async () => {
    const html = await privacyPage(true).text();
    expect(html).not.toContain("coming soon");
    expect(html).not.toMatch(/never sells or shares/);
    expect(html).toContain("Twilio Verify");
    expect(html).toContain("Cloudflare");
    expect(html).toContain("Delete my data");
    expect(html).toContain("Requests to play and invite links: 7 days");
  });
});

// The Apple TV app has its own manifest, under the same App Store record and label: the label's
// "Apple TV (tvOS)" section says what it declares, and nothing it declares is a new box.
const tvManifest = readFileSync(new URL("../../../play-ios/PounceTV/Resources/PrivacyInfo.xcprivacy", import.meta.url), "utf8");
const tvSection = label.slice(label.indexOf("## Apple TV (tvOS)"));

const PURPOSES: Record<string, string> = {
  NSPrivacyCollectedDataTypePurposeAppFunctionality: "App Functionality",
  NSPrivacyCollectedDataTypePurposeAnalytics: "Analytics",
};

/** Each data type a manifest declares, by its App Store name: its purposes, linked and tracking. */
function collected(plist: string): Record<string, { purposes: string[]; linked: boolean; tracking: boolean }> {
  const dicts = [...plist.matchAll(/<dict>\s*<key>NSPrivacyCollectedDataType<\/key>([\s\S]*?)<\/dict>/g)].map((m) => m[1] as string);
  return Object.fromEntries(
    dicts.map((body) => {
      const type = /^\s*<string>(\w+)<\/string>/.exec(body)?.[1] ?? "";
      const purposes = [...(/<key>NSPrivacyCollectedDataTypePurposes<\/key>\s*<array>([\s\S]*?)<\/array>/.exec(body)?.[1] ?? "").matchAll(/<string>(\w+)<\/string>/g)]
        .map((p) => PURPOSES[p[1] as string] ?? (p[1] as string));
      const linked = /<key>NSPrivacyCollectedDataTypeLinked<\/key>\s*<true\/>/.test(body);
      const tracking = /<key>NSPrivacyCollectedDataTypeTracking<\/key>\s*<true\/>/.test(body);
      return [NAMES[type] ?? type, { purposes, linked, tracking }];
    }),
  );
}

/** A manifest's required-reason API categories, each with its reasons. */
function accessedAPIs(plist: string): Record<string, string[]> {
  return Object.fromEntries(
    [...plist.matchAll(/<key>NSPrivacyAccessedAPIType<\/key>\s*<string>(\w+)<\/string>\s*<key>NSPrivacyAccessedAPITypeReasons<\/key>\s*<array>([\s\S]*?)<\/array>/g)].map((m) => [
      m[1] as string,
      [...(m[2] as string).matchAll(/<string>([\w.]+)<\/string>/g)].map((r) => r[1] as string),
    ]),
  );
}

describe("Apple TV privacy label", () => {
  test("the label's Apple TV section names exactly what the TV manifest declares, with the same purposes", () => {
    const sentence = /The TV's manifest declares (.+?), all linked and none for tracking/.exec(tvSection)?.[1];
    expect(sentence, "the Apple TV section's \"The TV's manifest declares …\" sentence").toBeDefined();
    const said = Object.fromEntries(
      [...(sentence ?? "").matchAll(/([A-Z][A-Za-z ]+?) \(([^)]+)\)/g)].map((m) => [(m[1] as string).replace(/^and /, ""), (m[2] as string).split(", ")]),
    );
    const tv = collected(tvManifest);
    expect(Object.keys(tv).sort()).toEqual(Object.keys(said).sort());
    for (const [name, { purposes }] of Object.entries(tv)) expect(purposes, name).toEqual(said[name]);
  });

  test("the TV adds no box: everything it declares is ticked on the shared label, linked and not tracking", () => {
    const tv = collected(tvManifest);
    for (const [name, { linked, tracking }] of Object.entries(tv)) {
      expect(ticked, name).toContain(name);
      expect(linked, name).toBe(true);
      expect(tracking, name).toBe(false);
    }
    expect(tvManifest).toMatch(/<key>NSPrivacyTracking<\/key>\s*<false\/>/);
    expect(tvManifest).toMatch(/<key>NSPrivacyTrackingDomains<\/key>\s*<array\/>/);
  });

  test("the TV's required-reason APIs are the ones the label lists", () => {
    const said = Object.fromEntries(
      [...tvSection.matchAll(/^- `(NSPrivacyAccessedAPICategory\w+)`, reason `([\w.]+)`/gm)].map((m) => [m[1] as string, [m[2] as string]]),
    );
    expect(Object.keys(said).length).toBeGreaterThan(0);
    expect(accessedAPIs(tvManifest)).toEqual(said);
  });
});
