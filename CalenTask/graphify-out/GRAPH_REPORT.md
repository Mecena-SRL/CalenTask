# Graph Report - CalenTask/CalenTask  (2026-06-23)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 1727 nodes · 3483 edges · 94 communities (93 shown, 1 thin omitted)
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 257 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `5801df3d`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]
- [[_COMMUNITY_Community 58|Community 58]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 60|Community 60]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 62|Community 62]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]
- [[_COMMUNITY_Community 67|Community 67]]
- [[_COMMUNITY_Community 68|Community 68]]
- [[_COMMUNITY_Community 69|Community 69]]
- [[_COMMUNITY_Community 70|Community 70]]
- [[_COMMUNITY_Community 71|Community 71]]
- [[_COMMUNITY_Community 72|Community 72]]
- [[_COMMUNITY_Community 73|Community 73]]
- [[_COMMUNITY_Community 74|Community 74]]
- [[_COMMUNITY_Community 75|Community 75]]
- [[_COMMUNITY_Community 76|Community 76]]
- [[_COMMUNITY_Community 77|Community 77]]
- [[_COMMUNITY_Community 78|Community 78]]
- [[_COMMUNITY_Community 79|Community 79]]
- [[_COMMUNITY_Community 80|Community 80]]
- [[_COMMUNITY_Community 81|Community 81]]
- [[_COMMUNITY_Community 82|Community 82]]
- [[_COMMUNITY_Community 83|Community 83]]
- [[_COMMUNITY_Community 84|Community 84]]
- [[_COMMUNITY_Community 85|Community 85]]
- [[_COMMUNITY_Community 86|Community 86]]
- [[_COMMUNITY_Community 87|Community 87]]
- [[_COMMUNITY_Community 88|Community 88]]
- [[_COMMUNITY_Community 89|Community 89]]
- [[_COMMUNITY_Community 90|Community 90]]
- [[_COMMUNITY_Community 91|Community 91]]
- [[_COMMUNITY_Community 92|Community 92]]
- [[_COMMUNITY_Community 93|Community 93]]

## God Nodes (most connected - your core abstractions)
1. `SwiftUI` - 90 edges
2. `SwiftData` - 85 edges
3. `text` - 68 edges
4. `ProjectGanttView` - 44 edges
5. `Foundation` - 43 edges
6. `CalendarScreen` - 36 edges
7. `DashboardView` - 34 edges
8. `Color` - 28 edges
9. `Calendar` - 26 edges
10. `TriageFlowView` - 22 edges

## Surprising Connections (you probably didn't know these)
- `SpeechCaptureService` --calls--> `Locale`  [INFERRED]
  Services/SpeechCaptureService.swift → Features/Calendar/CalendarMath.swift
- `CalenTaskApp` --calls--> `Schema`  [INFERRED]
  App/CalenTaskApp.swift → Models/CalenTaskSchema.swift
- `WeatherService` --references--> `Bool`  [EXTRACTED]
  Features/Calendar/DayHeaderView.swift → Services/WeatherService.swift
- `DSColor` --calls--> `Color`  [EXTRACTED]
  DesignSystem/Theme.swift → DesignSystem/DSElevation.swift
- `OpenMeteoResponse` --references--> `WeatherService`  [EXTRACTED]
  Services/WeatherService.swift → Features/Calendar/DayHeaderView.swift

## Import Cycles
- None detected.

## Communities (94 total, 1 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.06
Nodes (44): Calendar, CalendarMath, Comparable, Date, CalendarScreen, CalendarViewMode, day, month (+36 more)

### Community 1 - "Community 1"
Cohesion: 0.10
Nodes (30): AnyView, Bool, CGFloat, CGPoint, CGRect, ClosedRange, Color, Date (+22 more)

### Community 2 - "Community 2"
Cohesion: 0.06
Nodes (40): people, TagChip, String, Tag, Bool, Calendar, Color, Date (+32 more)

### Community 3 - "Community 3"
Cohesion: 0.06
Nodes (30): TaskComposerView, Bool, Date, Project, RecurrenceFrequency, RecurrenceMode, String, TaskKind (+22 more)

### Community 4 - "Community 4"
Cohesion: 0.09
Nodes (21): Calendar, Date, Project, TaskStatus, WorkflowStage, TodoTask, AutomationEngine, AutomationRule (+13 more)

### Community 5 - "Community 5"
Cohesion: 0.07
Nodes (28): CaptureApplier, CaptureAssistView, Demo, QuickCaptureView, CaptureParser, Equatable, Bool, Character (+20 more)

### Community 6 - "Community 6"
Cohesion: 0.06
Nodes (31): DSSectionHeader, TaskRow, DashboardRole, collaborator, full, owner, preproduction, RoleDashboardView (+23 more)

### Community 7 - "Community 7"
Cohesion: 0.07
Nodes (31): AppDestination, project, smartList, tag, AppRouter, Date, UUID, AppShellView (+23 more)

### Community 8 - "Community 8"
Cohesion: 0.10
Nodes (27): DashboardView, HealthSlice, LoadSlice, StatSpec, TimelineBar, TodoTask, DashboardRole, Binding (+19 more)

### Community 9 - "Community 9"
Cohesion: 0.08
Nodes (25): section, Bool, Contact, CrewAssignment, Project, String, TodoTask, Void (+17 more)

### Community 10 - "Community 10"
Cohesion: 0.11
Nodes (28): CGSize, DraggedWidgetGhost, MasonryLayout, ReorderableWidgetGrid, View, WidgetDragModel, WidgetSpanKey, CGFloat (+20 more)

### Community 11 - "Community 11"
Cohesion: 0.07
Nodes (28): Bool, Int, Project, Void, WorkflowStage, Binding, CustomFieldDefinition, Date (+20 more)

### Community 12 - "Community 12"
Cohesion: 0.09
Nodes (22): CNContact, CNKeyDescriptor, Contacts, ContactsImportService, Contact, Set, String, ContactsImportView (+14 more)

### Community 13 - "Community 13"
Cohesion: 0.09
Nodes (23): Binding, Bool, Contact, CrewAssignment, Date, ProductionScene, String, TodoTask (+15 more)

### Community 14 - "Community 14"
Cohesion: 0.12
Nodes (29): Charts, Advice, DashboardAdviceSection, DashboardTrendSection, DayCount, NotificationsBellButton, AppSection, Calendar (+21 more)

### Community 15 - "Community 15"
Cohesion: 0.13
Nodes (26): App, CalenTaskApp, processHasCloudKitEntitlement(), Bool, ModelContainer, CalenTaskSchemaV1, CalenTaskSchemaV2, CalenTaskSchemaV3 (+18 more)

### Community 16 - "Community 16"
Cohesion: 0.13
Nodes (18): CLLocation, CLLocationCoordinate2D, CLLocationManager, CLLocationManagerDelegate, Codable, CoreLocation, Decodable, Cache (+10 more)

### Community 17 - "Community 17"
Cohesion: 0.13
Nodes (18): PhaseTemplate, PhaseTemplate, ProjectTemplate, String, TemplateCatalog, TemplateCategory, business, cinema (+10 more)

### Community 18 - "Community 18"
Cohesion: 0.17
Nodes (13): DayTimelineView, SubtaskCheckRow, TimeBlockView, Bool, CGFloat, CGPoint, Color, Date (+5 more)

### Community 19 - "Community 19"
Cohesion: 0.09
Nodes (26): CaseIterable, DependencyType, finishToStart, MembershipRole, admin, member, owner, ProjectStatus (+18 more)

### Community 20 - "Community 20"
Cohesion: 0.16
Nodes (16): AllDayItem, TimedItem, WeekGridView, DSEventBlockModifier, DSNowLine, View, Bool, Color (+8 more)

### Community 21 - "Community 21"
Cohesion: 0.14
Nodes (16): WorkspaceScope, WorkspaceScopePicker, Bool, CGFloat, Color, Int, String, T (+8 more)

### Community 22 - "Community 22"
Cohesion: 0.13
Nodes (17): DashboardLayout, DashboardWidget, advice, health, timeline, today, trend, upcoming (+9 more)

### Community 23 - "Community 23"
Cohesion: 0.12
Nodes (11): AppKit, AVFoundation, MenuBarCaptureView, Foundation, MessageUI, Observation, Speech, DebugSeeder (+3 more)

### Community 24 - "Community 24"
Cohesion: 0.14
Nodes (13): AutomationListView, AutomationRuleEditor, Locale, AutomationRule, Binding, Project, String, UserProfile (+5 more)

### Community 25 - "Community 25"
Cohesion: 0.17
Nodes (11): EKEvent, EKRecurrenceFrequency, EventKit, CalendarSyncService, RecurrenceFrequency, Bool, Date, ModelContext (+3 more)

### Community 26 - "Community 26"
Cohesion: 0.09
Nodes (17): DSCard, DSEmptyState, PriorityDot, StatusBadge, StatTile, Content, String, Void (+9 more)

### Community 27 - "Community 27"
Cohesion: 0.12
Nodes (21): ProductionScene, SceneDayNight, dawn, day, dusk, night, SceneIntExt, ext (+13 more)

### Community 28 - "Community 28"
Cohesion: 0.13
Nodes (13): AppSection, DSAppearance, Color, String, Contact, Tag, Workspace, WelcomeView (+5 more)

### Community 29 - "Community 29"
Cohesion: 0.15
Nodes (16): Binding, Bool, Color, SavedView, Set, String, T, Tag (+8 more)

### Community 30 - "Community 30"
Cohesion: 0.18
Nodes (15): DSDateField, DSFieldRow, DSIconTile, DSNotesEditor, DSPriorityField, DSPromptField, DSTextFieldRow, Bool (+7 more)

### Community 31 - "Community 31"
Cohesion: 0.16
Nodes (15): Bool, Color, Project, String, TaskStatus, TodoTask, UUID, Void (+7 more)

### Community 32 - "Community 32"
Cohesion: 0.14
Nodes (12): SidebarView, AppDestination, AppSection, Binding, Date, Int, Project, SavedView (+4 more)

### Community 33 - "Community 33"
Cohesion: 0.12
Nodes (13): AllDayLaneView, Demo, DSCheckToggle, Bool, Void, Duration, TodoTask, Content (+5 more)

### Community 34 - "Community 34"
Cohesion: 0.16
Nodes (15): Binding, Bool, Color, Date, Project, SavedView, String, TaskKind (+7 more)

### Community 35 - "Community 35"
Cohesion: 0.16
Nodes (16): Bool, Date, Double, Int, Project, RecurrenceFrequency, RecurrenceMode, String (+8 more)

### Community 36 - "Community 36"
Cohesion: 0.15
Nodes (14): Int, Predicate, Project, String, TaskProvenance, TodoTask, UserProfile, UUID (+6 more)

### Community 37 - "Community 37"
Cohesion: 0.20
Nodes (12): Item, Bool, Date, Int, ModelContext, String, TodoTask, URL (+4 more)

### Community 38 - "Community 38"
Cohesion: 0.23
Nodes (9): Bool, Color, Int, Project, String, TodoTask, UUID, BoardColumn (+1 more)

### Community 39 - "Community 39"
Cohesion: 0.17
Nodes (10): Calendar, CGFloat, Color, Content, Int, String, TodoTask, Void (+2 more)

### Community 40 - "Community 40"
Cohesion: 0.27
Nodes (7): DayAgendaView, Bool, Color, Date, Int, String, TodoTask

### Community 41 - "Community 41"
Cohesion: 0.13
Nodes (15): Identifiable, InboxGroup, InboxDateBucket, CustomFieldType, checkbox, date, number, select (+7 more)

### Community 42 - "Community 42"
Cohesion: 0.21
Nodes (12): SavedView, SavedViewFilters, Bool, Date, Int, ProjectViewType, String, TaskKind (+4 more)

### Community 43 - "Community 43"
Cohesion: 0.14
Nodes (12): BlockVisibility, always, autoHide, hidden, StatBlock, inbox, overdue, today (+4 more)

### Community 44 - "Community 44"
Cohesion: 0.24
Nodes (11): Bool, Double, Int, Project, ProjectViewType, String, TodoTask, Void (+3 more)

### Community 45 - "Community 45"
Cohesion: 0.31
Nodes (6): MonthGridView, Color, Date, Double, Int, TodoTask

### Community 46 - "Community 46"
Cohesion: 0.26
Nodes (10): DSElevation, canvas, card, modal, panel, DSHoverHighlightModifier, DSSurfaceModifier, CGFloat (+2 more)

### Community 47 - "Community 47"
Cohesion: 0.15
Nodes (12): TaskPriority, high, low, normal, urgent, TaskStatus, blocked, doing (+4 more)

### Community 48 - "Community 48"
Cohesion: 0.27
Nodes (8): ButtonStyle, DSButtonChrome, DSGhostButtonStyle, DSProminentButtonStyle, Configuration, Bool, Content, View

### Community 49 - "Community 49"
Cohesion: 0.21
Nodes (7): Content, View, Color, DSColor, String, TaskPriority, TaskStatus

### Community 50 - "Community 50"
Cohesion: 0.24
Nodes (8): Bool, Int, String, TodoTask, Workspace, Preset, WorkspaceEditorView, WorkspacesSettingsSection

### Community 51 - "Community 51"
Cohesion: 0.26
Nodes (10): AutomationRule, Bool, Date, Int, String, TaskStatus, UUID, TriggerType (+2 more)

### Community 52 - "Community 52"
Cohesion: 0.33
Nodes (9): CustomFieldDefinition, CustomFieldValue, Bool, CustomFieldType, Date, Double, Int, String (+1 more)

### Community 53 - "Community 53"
Cohesion: 0.22
Nodes (8): Any, AppDelegate, Bool, Notification, NSApplicationDelegate, UIApplication, UIApplicationDelegate, UNUserNotificationCenterDelegate

### Community 54 - "Community 54"
Cohesion: 0.22
Nodes (7): ProjectDestinationView, SmartListDestinationView, Project, SavedView, Tag, UUID, TagDestinationView

### Community 55 - "Community 55"
Cohesion: 0.27
Nodes (6): Attachment, AttachmentsSection, URL, UUID, QuickLook, UniformTypeIdentifiers

### Community 56 - "Community 56"
Cohesion: 0.27
Nodes (6): BrowseView, AppDestination, Project, SavedView, Tag, TodoTask

### Community 57 - "Community 57"
Cohesion: 0.24
Nodes (8): Context, MFMailComposeViewController, EmailService, MailComposeView, Bool, String, URL, UIViewControllerRepresentable

### Community 58 - "Community 58"
Cohesion: 0.24
Nodes (8): CustomFieldValue, Binding, Bool, CustomFieldDefinition, String, TodoTask, Void, CustomFieldValueRow

### Community 59 - "Community 59"
Cohesion: 0.31
Nodes (7): Data, Attachment, Bool, Date, String, URL, UUID

### Community 60 - "Community 60"
Cohesion: 0.29
Nodes (8): Project, Bool, Date, Int, String, TodoTask, UUID, ProjectStatus

### Community 61 - "Community 61"
Cohesion: 0.24
Nodes (8): DayHeaderView, DayModeToggle, DayWeatherBadge, Color, Date, Int, String, TodoTask

### Community 62 - "Community 62"
Cohesion: 0.31
Nodes (6): MiniMonthView, Color, Date, Double, Int, Void

### Community 63 - "Community 63"
Cohesion: 0.22
Nodes (9): Command, CommandPaletteView, Bool, Color, Project, SavedView, String, TodoTask (+1 more)

### Community 64 - "Community 64"
Cohesion: 0.22
Nodes (8): Binding, Color, Int, Project, TaskStatus, TodoTask, Void, PhaseSectionView

### Community 65 - "Community 65"
Cohesion: 0.33
Nodes (5): String, TodoTask, UserProfile, TagService, TeamView

### Community 66 - "Community 66"
Cohesion: 0.32
Nodes (6): TaskMenuContent, View, Project, TodoTask, UserProfile, WorkflowStage

### Community 67 - "Community 67"
Cohesion: 0.25
Nodes (6): Coordinator, MFMailComposeResult, MFMailComposeViewControllerDelegate, NSObject, Coordinator, Error

### Community 68 - "Community 68"
Cohesion: 0.36
Nodes (4): ContactEditorView, CrewView, Contact, ContactKind

### Community 69 - "Community 69"
Cohesion: 0.36
Nodes (6): Bool, Project, TodoTask, UUID, PhasePlannerView, PlannerColumn

### Community 70 - "Community 70"
Cohesion: 0.25
Nodes (7): Bool, CGFloat, Color, String, UserProfile, AccountAvatar, AccountSection

### Community 71 - "Community 71"
Cohesion: 0.36
Nodes (6): ConflictService, Date, ModelContext, Set, TodoTask, UUID

### Community 72 - "Community 72"
Cohesion: 0.29
Nodes (7): AppSection, calendar, dashboard, inbox, projects, quick, Color

### Community 73 - "Community 73"
Cohesion: 0.38
Nodes (3): Double, text, String

### Community 74 - "Community 74"
Cohesion: 0.29
Nodes (5): DSMixedSchemeModifier, Bool, Content, View, ViewModifier

### Community 75 - "Community 75"
Cohesion: 0.43
Nodes (6): Demo, DSPalette, DSPaletteGrid, Swatch, Color, String

### Community 76 - "Community 76"
Cohesion: 0.38
Nodes (5): CustomFieldDefinition, CustomFieldType, Project, CustomFieldsEditorView, FieldDefinitionRow

### Community 77 - "Community 77"
Cohesion: 0.29
Nodes (7): ProjectViewType, board, gantt, kanban, list, stripboard, summary

### Community 78 - "Community 78"
Cohesion: 0.33
Nodes (6): Project, ProjectSmartStatus, atRisk, late, onTrack, Color

### Community 79 - "Community 79"
Cohesion: 0.33
Nodes (6): ColorScheme, DSAppearance, auto, dark, light, mixed

### Community 80 - "Community 80"
Cohesion: 0.47
Nodes (4): DateChipPicker, Bool, Date, String

### Community 81 - "Community 81"
Cohesion: 0.53
Nodes (5): DependencyType, Date, String, UUID, TaskDependency

### Community 82 - "Community 82"
Cohesion: 0.53
Nodes (5): Date, String, TodoTask, UUID, Tag

### Community 83 - "Community 83"
Cohesion: 0.40
Nodes (4): HashtagParser, String, Tag, TodoTask

### Community 84 - "Community 84"
Cohesion: 0.60
Nodes (5): Date, String, URL, UUID, UserProfile

### Community 85 - "Community 85"
Cohesion: 0.40
Nodes (4): UNNotification, UNNotificationPresentationOptions, UNNotificationResponse, UNUserNotificationCenter

### Community 86 - "Community 86"
Cohesion: 0.40
Nodes (4): TaskCardView, Bool, TodoTask, Void

### Community 87 - "Community 87"
Cohesion: 0.40
Nodes (4): Project, TaskProvenance, TodoTask, TriageRow

### Community 88 - "Community 88"
Cohesion: 0.50
Nodes (3): Bool, ProjectTemplate, NewProjectSheet

### Community 89 - "Community 89"
Cohesion: 0.40
Nodes (3): TodoTask, UUID, TaskDeepLinkView

### Community 91 - "Community 91"
Cohesion: 0.67
Nodes (3): DS, Radius, CGFloat

### Community 92 - "Community 92"
Cohesion: 0.50
Nodes (3): Tag, TodoTask, TaggedTasksView

### Community 93 - "Community 93"
Cohesion: 0.50
Nodes (3): Date, Bool, String

## Knowledge Gaps
- **513 isolated node(s):** `UNUserNotificationCenter`, `UNNotification`, `UNNotificationPresentationOptions`, `UNNotificationResponse`, `UIApplication` (+508 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `SwiftData` connect `Community 23` to `Community 0`, `Community 1`, `Community 2`, `Community 3`, `Community 4`, `Community 5`, `Community 6`, `Community 7`, `Community 8`, `Community 9`, `Community 11`, `Community 12`, `Community 13`, `Community 14`, `Community 15`, `Community 17`, `Community 18`, `Community 20`, `Community 21`, `Community 24`, `Community 25`, `Community 27`, `Community 28`, `Community 29`, `Community 31`, `Community 32`, `Community 34`, `Community 35`, `Community 36`, `Community 37`, `Community 38`, `Community 39`, `Community 42`, `Community 44`, `Community 50`, `Community 51`, `Community 52`, `Community 54`, `Community 55`, `Community 56`, `Community 58`, `Community 59`, `Community 60`, `Community 63`, `Community 64`, `Community 65`, `Community 66`, `Community 68`, `Community 69`, `Community 70`, `Community 76`, `Community 86`, `Community 87`, `Community 88`, `Community 89`, `Community 92`?**
  _High betweenness centrality (0.175) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Community 23` to `Community 0`, `Community 2`, `Community 3`, `Community 4`, `Community 5`, `Community 11`, `Community 12`, `Community 13`, `Community 15`, `Community 16`, `Community 17`, `Community 19`, `Community 21`, `Community 25`, `Community 27`, `Community 35`, `Community 37`, `Community 42`, `Community 51`, `Community 52`, `Community 59`, `Community 60`, `Community 78`, `Community 83`, `Community 91`, `Community 93`?**
  _High betweenness centrality (0.105) - this node is a cross-community bridge._
- **Why does `SwiftUI` connect `Community 26` to `Community 0`, `Community 1`, `Community 2`, `Community 3`, `Community 5`, `Community 6`, `Community 7`, `Community 8`, `Community 9`, `Community 10`, `Community 11`, `Community 12`, `Community 13`, `Community 14`, `Community 15`, `Community 18`, `Community 20`, `Community 21`, `Community 22`, `Community 23`, `Community 24`, `Community 28`, `Community 29`, `Community 30`, `Community 31`, `Community 32`, `Community 33`, `Community 34`, `Community 36`, `Community 38`, `Community 39`, `Community 40`, `Community 43`, `Community 44`, `Community 45`, `Community 46`, `Community 48`, `Community 49`, `Community 50`, `Community 54`, `Community 55`, `Community 56`, `Community 58`, `Community 61`, `Community 62`, `Community 63`, `Community 64`, `Community 65`, `Community 66`, `Community 68`, `Community 69`, `Community 70`, `Community 74`, `Community 75`, `Community 76`, `Community 78`, `Community 80`, `Community 86`, `Community 87`, `Community 88`, `Community 89`, `Community 92`?**
  _High betweenness centrality (0.099) - this node is a cross-community bridge._
- **Are the 67 inferred relationships involving `text` (e.g. with `.sidebarProjectRow()` and `.smartListRow()`) actually correct?**
  _`text` has 67 INFERRED edges - model-reasoned connections that need verification._
- **What connects `UNUserNotificationCenter`, `UNNotification`, `UNNotificationPresentationOptions` to the rest of the system?**
  _513 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.05570611261668172 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.10119047619047619 - nodes in this community are weakly interconnected._