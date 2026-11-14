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
