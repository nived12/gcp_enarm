// Controllers are registered by hand — the manifest generator is not wired up, so a
// new controller that is not added here silently never connects.
import { application } from "./application"

import ThemeController from "./theme_controller"
application.register("theme", ThemeController)

import TimerController from "./timer_controller"
application.register("timer", TimerController)

import AutosaveController from "./autosave_controller"
application.register("autosave", AutosaveController)

import TopicPickerController from "./topic_picker_controller"
application.register("topic-picker", TopicPickerController)
