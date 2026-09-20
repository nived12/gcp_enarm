// Controllers are registered by hand — the manifest generator is not wired up, so a
// new controller that is not added here silently never connects.
import { application } from "./application"

import ThemeController from "./theme_controller"
application.register("theme", ThemeController)
