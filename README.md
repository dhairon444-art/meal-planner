# Meal Planner

Private vegetarian iPhone app built with SwiftUI, Foundation Models, and WidgetKit. The first development build was installed on the paired iPhone on 11 November 2026. The display name is Meal Planner; the existing internal project and bundle identity remain unchanged to preserve updates and saved data.

## First use

1. Open Meal Planner and tap **+** in My pantry.
2. Enter groceries in natural language, then choose **Organize with Apple Intelligence**. Manual entry is available when Apple Intelligence is unavailable.
3. Review the ingredient names, quantities, categories, and suggested USDA nutrition matches. Select the correct nutrition match before saving.
4. Open Recipes to browse 86 bundled vegetarian recipes, ranked by missing ingredients. Download updates when online.
5. Open a recipe to add missing ingredients to Shopping or request on-device substitution suggestions.
6. On the Home Screen, choose Edit → Add Widget → Meal Planner. Shopping and recipe widgets open the corresponding app section.

Dairy and eggs are included by default. Settings offers an egg exclusion option. Existing pantry entries remain visible when that setting changes.

## Current limits

- This is a first development version. Recipe matching currently uses normalized ingredient names and a conservative alias list; it does not reconcile stock quantities, unit conversions, or serving sizes.
- Substitutions are suggestions for review. Cheese, sauces, product labels, and dietary requirements still need checking.
- Nutrition data is per 100 g, not calculated per consumed portion. USDA demo access is limited to 30 requests/hour and 50/day per IP address. Automatic lookup covers the first ten ingredients in a batch; other items can be looked up individually.
- Home Screen widgets show a read-only snapshot and open the app when tapped. Inline shopping checkboxes are not included yet.
- Pantry data stays on the phone. The app exports a JSON text backup through Settings; backup restore is not implemented yet.
- The recipe catalogue is bundled and can download updates from TheMealDB. A separate custom backend has not been deployed.
- Xcode generated seven-day development profiles for the current account. Refresh the app through Xcode before expiry. Reinstall over the existing app; do not delete it when refreshing.

## Sources and access

Recipes: [TheMealDB](https://www.themealdb.com/api.php), using its development test key. Each recipe links to its original page. Public App Store release requires appropriate production access.

Nutrition: [USDA FoodData Central](https://fdc.nal.usda.gov/api-guide/), public-domain data under CC0. This build uses the public DEMO_KEY. Ingredient names are sent to USDA for lookup; the pantry is not uploaded.

AI: Apple's on-device Foundation Models framework. The app checks device availability at runtime and provides manual grocery entry when the model is not ready.

## Project and validation

Open `GreenPantry.xcodeproj` in Xcode. Select the GreenPantry scheme and your paired iPhone, then Run. Signing is configured for the existing local development team. `project.yml` recreates the project with XcodeGen.

The app and widget extension passed a signed physical-device build. Public recipe and nutrition endpoints responded successfully. Checks cover ingredient aliases, vegetarian filtering, eggplant/egg distinctions, missing-ingredient matching, the 86-recipe catalogue, and persistence encoding/decoding. On-device AI responses and widget rendering require further hands-on testing.

## Updating the app

Develop on the Mac in Xcode; use the iPhone to test the installed build. Select the paired iPhone and choose Run to update the existing app. Keep the bundle identifiers unchanged so updates retain pantry data. Do not delete the app to update it.

Settings → About shows the installed version and build number. This build is version 0.1.1 (2). Increase the version for a user-facing release and the build number for each distributed test build. XcodeGen reads these values from `project.yml`; keep it in sync when changing version settings in Xcode.

Local Git history records source changes independently of the installed app. Commit completed changes, then push them to the private GitHub repository. GitHub stores source history; it does not renew iPhone signing or install updates on the phone.
