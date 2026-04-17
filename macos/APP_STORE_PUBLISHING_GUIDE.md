# AIHelper Mac App Store Publishing Guide

This document explains how to publish AIHelper to the Apple Mac App Store.

## 1. Current Readiness Review (Important)

Before submitting, verify these items. Status reflects the current codebase:

1. App Sandbox and entitlement configuration.
- Status: fixed.
- `AIHelper.xcodeproj/project.pbxproj` now sets `ENABLE_APP_SANDBOX = YES`.
- `AIHelper/AIHelper.entitlements` now has `com.apple.security.app-sandbox` set to `true`.

2. App identity strings consistency.
- Status: fixed.
- `AIHelper.xcodeproj/project.pbxproj` now sets `INFOPLIST_KEY_CFBundleDisplayName = AIHelper`.
- User-facing `Paragraph` strings were replaced with `AIHelper`.

3. Privacy-related permission copy.
- Status: fixed.
- `AIHelper/Info.plist` permission descriptions now reference AIHelper and explain shortcut/copy-paste behavior.

4. API key storage security.
- Status: fixed.
- API key storage has been moved from `UserDefaults` to Keychain Services.

5. Deployment target sanity.
- Status: fixed.
- `AIHelper.xcodeproj/project.pbxproj` now uses `MACOSX_DEPLOYMENT_TARGET = 13.0`.

> [!TIP]
> **Build Warning:** You might see a warning about `NSLocalNetworkUsageDescription`. If your app supports Ollama (local AI), you should add this key to `Info.plist` with a description like: "AIHelper connects to local AI services like Ollama."

## 2. Apple Account and App Store Connect Setup

1. Enroll in Apple Developer Program (organization or individual).
2. In App Store Connect, create a new macOS app record:
- Platform: macOS
- Name: AIHelper
- Primary language
- Bundle ID: must match Xcode `PRODUCT_BUNDLE_IDENTIFIER`
- SKU: internal unique value
3. Complete Agreements, Tax, and Banking in App Store Connect.

## 2.5 Pricing and Availability ($5.00)

To set your price to $5.00:

1. In App Store Connect, go to **Pricing and Availability**.
2. Click **Add Pricing**.
3. Select the **$4.99** price tier (Apple uses tiers, so $4.99 is the standard "five dollar" price point).
4. Select all territories (or specific ones) and click **Save**.

> [!NOTE]
> Apple takes a 15% to 30% commission depending on your enrollment in the Small Business Program.

## 3. Xcode Project Configuration Checklist

In target `AIHelper` (Release config):

1. Signing and capabilities
- Enable App Sandbox.
- Keep only entitlements that are required.
- Ensure Team and Bundle Identifier match App Store Connect.

2. Versioning
- Set `MARKETING_VERSION` (for example `1.0.0`).
- Increment `CURRENT_PROJECT_VERSION` for each upload.

3. Info metadata
- `CFBundleDisplayName`: set to `AIHelper` (or your final brand, consistently).
- Confirm `LSApplicationCategoryType` is correct (`public.app-category.productivity` is fine).
- Replace permission description text with accurate wording using your app name.

4. Privacy and network
- If connecting only to remote APIs, do not include unused local network descriptions.
- Provide a clear privacy policy URL in App Store Connect.

## 4. Required Code/Config Changes Before Submission

1. Sandbox
- Set `ENABLE_APP_SANDBOX = YES`.
- Set `com.apple.security.app-sandbox` entitlement to `true`.
- Keep `com.apple.security.network.client = true` for outbound API calls.

2. Permission text cleanup
- Replace `Paragraph` references with `AIHelper` in:
  - `AIHelper/Info.plist`
  - `AIHelper/AppDelegate.swift` accessibilityDescription

3. Secure API key storage
- Move API key persistence from `UserDefaults` to Keychain Services.
- Keep only non-sensitive settings (provider/base URL/model) in `UserDefaults`.

4. Deployment target
- Lower `MACOSX_DEPLOYMENT_TARGET` to the oldest supported macOS version you test.

5. Provider defaults and transparency
- Confirm default provider endpoint/model are intentional and documented.
- If default is not OpenAI, update UI labels/help text so users are not misled.

## 5. Build, Archive, and Upload

1. In Xcode, select the `AIHelper` scheme and `Any Mac (Apple Silicon, Intel)`.
2. Product -> Archive (Release).
3. In Organizer:
- Validate App
- Distribute App -> App Store Connect -> Upload
4. Resolve any validation errors and re-archive if needed.

## 6. App Store Connect Submission Fields

Complete the following for the app version:

1. App description, subtitle, keywords, support URL, marketing URL (optional).
2. Privacy policy URL (required for apps handling user text and network requests).
3. Screenshots for required Mac display sizes:
   - **Primary Size:** 1280 x 800 (standard) or 1440 x 900.
   - **Retina Size:** 2560 x 1600 or 2880 x 1800.
   - *Tip:* Use `Cmd + Shift + 4` then `Space` to take a clean screenshot of just the window.

> [!TIP]
> **What to show in screenshots:**
> 1. **The Hero Shot:** The main popup over some text in a document (e.g., Mail or Notes).
> 2. **The "Fixing" State:** The popup with loading dots or a fresh AI response.
> 3. **The Settings:** Show the Shortcut Settings view to prove customization.
> 4. **Modern UI:** Showcase the dark mode and premium design we built.
4. Age rating questionnaire.
5. Export compliance (encryption questions).
6. App Privacy section:
- Declare that selected user text may be transmitted to AI provider endpoints.
- Declare diagnostics/identifiers only if collected.

## 7. App Review Notes (Recommended)

In "Notes for App Review", explain:

1. Why Accessibility permission is required (global shortcut and selected text workflow).
2. Why Apple Events/clipboard-style automation is required (copy/paste integration).
3. That user-triggered text is sent to configured AI provider endpoints.
4. How users configure provider/API key in Settings.

## 7.5 App Review Strategy: The "Sandbox" Challenge

> [!IMPORTANT]
> Because your app is Sandboxed (required for App Store), Apple is very strict about apps that request **Accessibility Permissions** to read/control other apps. 

To pass review:
1. **Explain the Workflow:** Be very clear that AIHelper only captures text *when the user presses the shortcut*. It does not "spy" passively.
2. **Provide a Demo Video:** Upload a video to App Store Connect showing you using the shortcut to fix text. This helps the reviewer understand the utility.
3. **App Store Guidelines:** Be prepared to argue that your app falls under "Productivity" and the Accessibility permission is the *only* way to provide the "Paste-back" feature seamlessly.

## 8. Release and Post-Release

1. Submit for review.
2. Monitor App Store Connect for metadata or binary rejection notes.
3. After approval, release manually or automatically.
4. Track crashes/feedback and prepare `1.0.1` bugfix build.

## Appendix A: Privacy Policy Template

Because AIHelper processes user text, Apple requires a valid Privacy Policy URL. You can host this simple privacy policy on a free site (like GitHub Pages or Notion) and paste the link into App Store Connect:

> **AIHelper Privacy Policy**
> 
> **Data Collection and Use**
> AIHelper is a utility designed to assist with writing by sending user-selected text to a designated AI text-generation endpoint (e.g., OpenAI or a local Ollama instance).
> 
> 1. **Text Processing:** Text is only captured when you explicitly trigger the AIHelper shortcut while text is selected. The selected text is sent directly to your configured AI provider. AIHelper does not intercept or log keystrokes continually.
> 2. **API Keys:** If you configure an API key (like OpenAI), it is stored securely on your device using macOS Keychain Services. It is solely used to authenticate your requests with the chosen provider and is never sent to our servers.
> 3. **Data Retention:** AIHelper does not store, transmit, or retain any of your text, prompts, or generated responses on our servers, nor does it collect analytics or diagnostic data. All data transmission occurs exclusively between your device and your chosen AI endpoint.

## 9. Fast Pre-Submission Checklist

- [x] Sandbox enabled and valid entitlements
- [x] Consistent app naming in all permission prompts
- [x] API key stored in Keychain (not UserDefaults)
- [x] Realistic deployment target (v13.0)
- [x] Version/build numbers updated (v1.0.0)
- [/] Privacy policy ready (needs hosting and URL in App Store Connect)
- [x] Archive validation passes with no critical warnings
- [x] App Review notes template ready in this guide
