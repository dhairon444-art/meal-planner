# Meal Planner

Private vegetarian iPhone app built in SwiftUI, with on-device Apple Intelligence and Home Screen widgets. Current development version: **0.6.0 (7)**.

The app is developed in Xcode and installed over the existing iPhone app. [Development checklist and Mermaid flows](Docs/DevelopmentPlan.md) track the planned features, implementation, tests and remaining decisions. Source history is in the private [GitHub repository](https://github.com/dhairon444-art/meal-planner).

## Try the app

1. In **Recipes**, open your profile to enter household size, tastes, dietary restrictions and allergies.
2. Tap the grocery basket at the top of Recipes. In **Pantry**, tap **+**. Type items, choose a photo, or take a photo. Review recognized items and nutrition matches before saving. Use “I already have these items” only for food actually in stock.
3. **Recipes** recommends meals from your tastes, favourites and cooking history. Each card shows the main ingredient. “Ready to cook” appears only when the full requirements can be matched against usable pantry stock; incomplete recipes have no missing-item prompt on their cards.
4. In a recipe, tap **Add ingredients to groceries** or add it to your plan. Shopping automatically combines the selected meals and subtracts available pantry quantities.
5. **Plan** shows a calendar and the selected day’s morning, afternoon, and evening meals. Tap an empty slot to choose a recipe.
6. In **Shopping**, check purchased items and explicitly move them into stock. Items merely listed for purchase do not count as available ingredients.
7. **Settings** includes cooking history and JSON backup export/restore. Widgets are added from the iPhone Home Screen by searching for Meal Planner.

## Data and accuracy

- The 109 bundled vegetarian recipes are available offline. TheMealDB provides recipe updates and source pages.
- Grocery organization and substitution suggestions use the on-device Foundation Models framework when available. Manual grocery entry is available otherwise.
- Photos are processed on-device with Vision. Text extraction and food-label suggestions can miss or misidentify items; review is required.
- Nutrition facts come from USDA FoodData Central. Ingredient names are sent for lookup; choose the matching food and preparation. Values are per 100 g. Recipe totals are not invented when weights or nutrient coverage are incomplete.
- Stock checks preserve ingredient distinctions, distinguish units and packages, account for quantities, and ignore out-of-stock or expired entries. Unknown quantitative requirements prevent readiness. Use-by dates are entered by the user.
- Common dietary ingredient aliases are filtered, but recipe data does not certify allergens, manufacturing cross-contact, or product labels.
- Camera recognition quality, AI response quality and Home Screen widget rendering still need hands-on testing on the paired iPhone.

## Current development decisions

Costs and budgets are deferred. They are absent from the current UI and planning rules. The development plan keeps them in the later-work checklist.

Recipe-source servings, cooking time and equipment are not reliably supplied by TheMealDB. The app supports entering this information in Recipe details rather than inventing it. Health scoring, a separately hosted custom backend and household cloud sharing remain open decisions.

Pantry, preferences, meal plans and history stay on the phone. Backups include them. Existing 0.1.x data is migrated. An unreadable save is preserved instead of being overwritten by an empty session.

## Build and update

Open `GreenPantry.xcodeproj` in Xcode, select the GreenPantry scheme and paired iPhone, and choose Run. The product’s visible name is Meal Planner. Internal bundle identifiers remain unchanged to preserve installed data.

`project.yml` is the XcodeGen source for the project, including version/build numbers. Regenerate after changes with `xcodegen generate`. Keep it in sync when changing version settings in Xcode.

Use Git commits for completed changes and push them to the private repository. GitHub stores source history; it does not renew iPhone signing. The current personal development account uses seven-day profiles, so refresh through Xcode before expiry. Update the existing app without deleting it.

## Checks

Run `Checks/run.sh` on a Mac with Xcode. Checks cover data migration, recommendation independence, dietary filters, quantities, stock readiness, expiry, stock deduction, meal-plan generation, shopping aggregation, purchased stock, cooking history and the recipe catalogue. The signed app build is checked separately with Xcode.

## Sources

- [TheMealDB API](https://www.themealdb.com/api.php): development test access, with per-recipe attribution. Public distribution requires appropriate production access.
- [USDA FoodData Central](https://fdc.nal.usda.gov/api-guide/): public-domain nutrition data under CC0. Demo access is limited to 30 requests/hour and 50/day per IP address.
- [Apple Foundation Models](https://developer.apple.com/documentation/FoundationModels): on-device language model integration.
- [Apple Vision](https://developer.apple.com/documentation/vision): on-device text recognition and image classification.

## Quantity and Indian recipes

After entering an item, scroll to select a quantity and unit. Meal Planner suggests a unit using the item name and on-device intelligence when available; the suggestion is editable. Select an existing pantry or shopping item to change its quantity.

The bundled library includes six Meal Planner original Indian vegetarian recipes. Choose “Update Indian vegetarian recipes” in Recipes to search TheMealDB for additional recipes tagged as Indian and vegetarian or vegan. Source pages remain linked for imported recipes. The provider’s free development catalogue is limited and may return no new matches.

## Imported personal recipes

The 17 recipes from iCloud Drive → Downloads → Meals are bundled as personal recipes; the original files are unchanged. Source serving counts are retained when provided. Recipe pictures for these imports have not been generated yet. Shopping amounts use the source quantities; unusual or ambiguous measurements should be reviewed.

## Discover and daily planning

Discover includes All, Breakfast, Snacks, Lunch and Dinner filters. Suggested types are based on recipe names and can be changed in Recipe details. The Plan screen shows the selected day’s morning, afternoon and evening together below the calendar. Open any recipe and choose Add to meal plan, or swipe a recipe card to add it.
